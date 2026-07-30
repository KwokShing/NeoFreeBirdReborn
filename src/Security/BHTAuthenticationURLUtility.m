#import "Security/BHTAuthenticationURLUtility.h"

#import <stdatomic.h>

typedef NS_ENUM(NSUInteger, BHTAuthenticationURLReason) {
    BHTAuthenticationURLReasonMissingURL = 0,
    BHTAuthenticationURLReasonDeclaredCallbackScheme,
    BHTAuthenticationURLReasonIdentityProvider,
    BHTAuthenticationURLReasonFirstPartyAccountHost,
    BHTAuthenticationURLReasonFirstPartyAuthPath,
    BHTAuthenticationURLReasonFirstPartyAuthQuery,
    BHTAuthenticationURLReasonExternalEligible,
    BHTAuthenticationURLReasonCount,
};

static atomic_ulong
    BHTAuthenticationURLCounters[BHTAuthenticationURLReasonCount];

static BOOL BHTHostMatchesDomain(NSString* host, NSString* domain) {
    if ([host isEqualToString:domain]) {
        return YES;
    }
    return [host hasSuffix:[@"." stringByAppendingString:domain]];
}

static BOOL BHTPathEqualsOrDescendsFrom(NSString* path, NSString* root) {
    if ([path isEqualToString:root]) {
        return YES;
    }
    return [path hasPrefix:[root stringByAppendingString:@"/"]];
}

static NSSet<NSString*>* BHTDeclaredAuthenticationSchemes(void) {
    static NSSet<NSString*>* schemes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableSet<NSString*>* values = [NSMutableSet set];
        id urlTypes =
            [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleURLTypes"];
        if (![urlTypes isKindOfClass:NSArray.class]) {
            schemes = [values copy];
            return;
        }
        for (id urlType in (NSArray*)urlTypes) {
            if (![urlType isKindOfClass:NSDictionary.class]) {
                continue;
            }
            NSArray* declaredSchemes = urlType[@"CFBundleURLSchemes"];
            if (![declaredSchemes isKindOfClass:NSArray.class]) {
                continue;
            }
            for (id value in declaredSchemes) {
                if (![value isKindOfClass:NSString.class]) {
                    continue;
                }
                NSString* scheme =
                    [(NSString*)value lowercaseString];
                BOOL authenticationScheme =
                    [scheme isEqualToString:@"twitterauth"] ||
                    [scheme hasPrefix:@"com.googleusercontent.apps."];
                if (authenticationScheme) {
                    [values addObject:scheme];
                }
            }
        }
        schemes = [values copy];
    });
    return schemes;
}

static BHTAuthenticationURLReason BHTAuthenticationReasonForURL(NSURL* url) {
    if (url == nil) {
        return BHTAuthenticationURLReasonMissingURL;
    }

    NSURLComponents* components =
        [NSURLComponents componentsWithURL:url
                   resolvingAgainstBaseURL:NO];
    NSString* scheme = components.scheme.lowercaseString ?: @"";
    if ([BHTDeclaredAuthenticationSchemes() containsObject:scheme]) {
        return BHTAuthenticationURLReasonDeclaredCallbackScheme;
    }

    if (!([scheme isEqualToString:@"http"] ||
          [scheme isEqualToString:@"https"])) {
        return BHTAuthenticationURLReasonExternalEligible;
    }

    NSString* host = components.host.lowercaseString ?: @"";
    if ([host isEqualToString:@"accounts.google.com"] ||
        [host isEqualToString:@"appleid.apple.com"]) {
        return BHTAuthenticationURLReasonIdentityProvider;
    }

    if ([host isEqualToString:@"accounts.x.com"] ||
        [host isEqualToString:@"accounts.twitter.com"]) {
        return BHTAuthenticationURLReasonFirstPartyAccountHost;
    }

    BOOL firstPartyHost =
        BHTHostMatchesDomain(host, @"x.com") ||
        BHTHostMatchesDomain(host, @"twitter.com");
    if (!firstPartyHost) {
        return BHTAuthenticationURLReasonExternalEligible;
    }

    NSString* path = components.path.lowercaseString ?: @"/";
    for (NSString* root in @[
             @"/account",
             @"/login",
             @"/i/flow",
             @"/i/oauth2",
             @"/oauth",
         ]) {
        if (BHTPathEqualsOrDescendsFrom(path, root)) {
            return BHTAuthenticationURLReasonFirstPartyAuthPath;
        }
    }

    NSSet<NSString*>* authQueryNames = [NSSet setWithArray:@[
        @"oauth_token",
        @"oauth_verifier",
        @"oauth_callback",
        @"redirect_uri",
        @"redirect_after_login",
        @"return_to",
        @"code_challenge",
    ]];
    for (NSURLQueryItem* item in components.queryItems) {
        if ([authQueryNames containsObject:item.name.lowercaseString]) {
            return BHTAuthenticationURLReasonFirstPartyAuthQuery;
        }
    }

    return BHTAuthenticationURLReasonExternalEligible;
}

BOOL BHTShouldKeepAuthenticationURLInApp(NSURL* url) {
    BHTAuthenticationURLReason reason =
        BHTAuthenticationReasonForURL(url);
    atomic_fetch_add_explicit(
        &BHTAuthenticationURLCounters[reason], 1,
        memory_order_relaxed);
    return reason != BHTAuthenticationURLReasonMissingURL &&
           reason != BHTAuthenticationURLReasonExternalEligible;
}

NSDictionary<NSString*, NSNumber*>*
BHTAuthenticationRoutingDiagnosticSnapshot(void) {
    NSArray<NSString*>* names = @[
        @"missingURL",
        @"declaredCallbackScheme",
        @"identityProvider",
        @"firstPartyAccountHost",
        @"firstPartyAuthPath",
        @"firstPartyAuthQuery",
        @"externalEligible",
    ];
    NSMutableDictionary<NSString*, NSNumber*>* snapshot =
        [NSMutableDictionary dictionaryWithCapacity:names.count];
    [names enumerateObjectsUsingBlock:^(
               NSString* name, NSUInteger index, BOOL* stop) {
        snapshot[name] =
            @(atomic_load_explicit(
                &BHTAuthenticationURLCounters[index],
                memory_order_relaxed));
    }];
    return [snapshot copy];
}
