#import "Login/BHTWebSessionSecurity.h"

#include <errno.h>
#include <stdlib.h>

static BOOL BHTWebSessionHostMatchesDomain(
    NSString* host,
    NSString* domain) {
    return [host isEqualToString:domain] ||
           [host hasSuffix:[@"." stringByAppendingString:domain]];
}

BOOL BHTWebSessionURLIsAllowed(NSURL* URL) {
    if (![URL isKindOfClass:NSURL.class]) return NO;
    NSURLComponents* components =
        [NSURLComponents componentsWithURL:URL
                   resolvingAgainstBaseURL:NO];
    if (![[components.scheme lowercaseString] isEqualToString:@"https"] ||
        components.user.length > 0 || components.password.length > 0) {
        return NO;
    }
    NSNumber* port = components.port;
    if (port && port.unsignedIntegerValue != 443) return NO;
    NSString* host = components.host.lowercaseString ?: @"";
    return BHTWebSessionHostMatchesDomain(host, @"x.com") ||
           BHTWebSessionHostMatchesDomain(host, @"twitter.com");
}

NSString* BHTWebSessionNormalizedHandle(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString* handle = [(NSString*)value
        stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([handle hasPrefix:@"@"]) {
        handle = [handle substringFromIndex:1];
    }
    if (handle.length == 0 || handle.length > 15) return nil;
    NSCharacterSet* allowed = [NSCharacterSet
        characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"];
    if ([[handle stringByTrimmingCharactersInSet:allowed] length] != 0) {
        return nil;
    }
    return handle;
}

uint64_t BHTWebSessionUserIDFromTWID(NSString* value) {
    if (![value isKindOfClass:NSString.class] ||
        value.length == 0 || value.length > 128) {
        return 0;
    }
    NSString* decoded = value.stringByRemovingPercentEncoding ?: value;
    if ([decoded hasPrefix:@"u="]) {
        decoded = [decoded substringFromIndex:2];
    }
    if (decoded.length == 0 || decoded.length > 20) return 0;
    NSCharacterSet* digits = NSCharacterSet.decimalDigitCharacterSet;
    if ([[decoded stringByTrimmingCharactersInSet:digits] length] != 0) {
        return 0;
    }
    errno = 0;
    char* end = NULL;
    unsigned long long result =
        strtoull(decoded.UTF8String, &end, 10);
    return errno == 0 && end && *end == '\0' && result > 0
               ? (uint64_t)result
               : 0;
}

BOOL BHTWebSessionCredentialValueIsValid(NSString* value) {
    if (![value isKindOfClass:NSString.class] ||
        value.length < 8 || value.length > 512) {
        return NO;
    }
    NSCharacterSet* allowed = [NSCharacterSet
        characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789%._~-+"];
    return [[value stringByTrimmingCharactersInSet:allowed] length] == 0;
}

NSString* BHTWebSessionCookieHeader(
    NSString* existingHeader,
    NSString* authToken,
    NSString* csrfToken,
    uint64_t userID) {
    NSMutableArray<NSString*>* pieces = [NSMutableArray array];
    NSSet<NSString*>* replacedNames = [NSSet setWithArray:@[
        @"auth_token", @"ct0", @"twid"
    ]];
    if ([existingHeader isKindOfClass:NSString.class]) {
        for (NSString* rawPiece in
                 [existingHeader componentsSeparatedByString:@";"]) {
            NSString* piece = [rawPiece
                stringByTrimmingCharactersInSet:
                    NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSRange equals = [piece rangeOfString:@"="];
            if (equals.location == NSNotFound ||
                equals.location == 0) {
                continue;
            }
            NSString* name = [[piece substringToIndex:equals.location]
                lowercaseString];
            if (![replacedNames containsObject:name] &&
                piece.length <= 2048) {
                [pieces addObject:piece];
            }
        }
    }
    [pieces addObject:[@"auth_token=" stringByAppendingString:authToken]];
    [pieces addObject:[@"ct0=" stringByAppendingString:csrfToken]];
    [pieces addObject:[NSString
        stringWithFormat:@"twid=u%%3D%llu",
                         (unsigned long long)userID]];
    return [pieces componentsJoinedByString:@"; "];
}
