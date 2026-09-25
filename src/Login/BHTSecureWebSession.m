#import "Login/BHTSecureWebSession.h"

#import "Core/BHTBundle.h"
#import "Login/BHTCompatibilityLogin.h"
#import "Login/BHTWebSessionSecurity.h"

#import <Security/Security.h>
#import <WebKit/WebKit.h>
#import <objc/message.h>
#import <stdatomic.h>

static NSString* const BHTWebSessionKeychainService =
    @"com.neofreebird.secure-web-session.v1";
static NSString* const BHTWebSessionKeychainAccount = @"active";
static NSString* const BHTWebSessionTargetVersion = @"12.24.1";

// X ships this public web-client bearer value in browser code. It identifies
// the web client; the user's private authentication remains in auth/CSRF
// cookies protected by the Keychain.
static NSString* const BHTWebSessionPublicBearer =
    @"AAAAAAAAAAAAAAAAAAAAAAj4AQAAAAAAPraK64zCZ9CSzdLesbE7LB%2Bw4uE%3DVJQREvQNCZJNiz3rHO7lOXlkVOQkzzdsgu6wWgcazdMUaGoUGm";

typedef NS_ENUM(NSUInteger, BHTWebSessionEvent) {
    BHTWebSessionEventPresented = 0,
    BHTWebSessionEventConfirmationTapped,
    BHTWebSessionEventCookieSetComplete,
    BHTWebSessionEventCookieSetIncomplete,
    BHTWebSessionEventHandleDetected,
    BHTWebSessionEventHandleEntered,
    BHTWebSessionEventKeychainSaved,
    BHTWebSessionEventKeychainSaveFailed,
    BHTWebSessionEventAccountInstallStarted,
    BHTWebSessionEventAccountInstallFailed,
    BHTWebSessionEventRequestEligible,
    BHTWebSessionEventRequestAuthenticated,
    BHTWebSessionEventRevoked,
    BHTWebSessionEventCount,
};

static atomic_ulong BHTWebSessionCounters[BHTWebSessionEventCount];
static NSObject* BHTWebSessionLock;
static NSDictionary<NSString*, id>* BHTWebSessionCachedSession;
static BOOL BHTWebSessionCacheLoaded;
static __weak UIViewController* BHTWebSessionPresentedController;

static void BHTWebSessionRecord(BHTWebSessionEvent event) {
    if (event < BHTWebSessionEventCount) {
        atomic_fetch_add_explicit(
            &BHTWebSessionCounters[event], 1,
            memory_order_relaxed);
    }
}

static NSObject* BHTSecureWebSessionLock(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ BHTWebSessionLock = [NSObject new]; });
    return BHTWebSessionLock;
}

static NSString* BHTWebSessionLocalized(NSString* key) {
    return [[BHTBundle sharedBundle] localizedStringForKey:key];
}

static BOOL BHTWebSessionVersionIsSupported(void) {
    NSString* version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [version isEqualToString:BHTWebSessionTargetVersion];
}

static NSDictionary* BHTWebSessionKeychainQuery(BOOL returnData) {
    NSMutableDictionary* query = [@{
        (__bridge id)kSecClass:
            (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:
            BHTWebSessionKeychainService,
        (__bridge id)kSecAttrAccount:
            BHTWebSessionKeychainAccount,
    } mutableCopy];
    if (returnData) {
        query[(__bridge id)kSecReturnData] = @YES;
        query[(__bridge id)kSecMatchLimit] =
            (__bridge id)kSecMatchLimitOne;
    }
    return query;
}

static NSDictionary<NSString*, id>*
BHTWebSessionValidatedSession(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary* candidate = value;
    NSString* auth = candidate[@"auth"];
    NSString* csrf = candidate[@"csrf"];
    NSString* handle =
        BHTWebSessionNormalizedHandle(candidate[@"screenName"]);
    NSNumber* userIDValue = candidate[@"userID"];
    uint64_t userID =
        [userIDValue isKindOfClass:NSNumber.class] &&
        CFGetTypeID((__bridge CFTypeRef)userIDValue) !=
            CFBooleanGetTypeID()
            ? userIDValue.unsignedLongLongValue
            : 0;
    if (!BHTWebSessionCredentialValueIsValid(auth) ||
        !BHTWebSessionCredentialValueIsValid(csrf) ||
        handle.length == 0 || userID == 0) {
        return nil;
    }
    return @{
        @"version": @1,
        @"auth": [auth copy],
        @"csrf": [csrf copy],
        @"screenName": handle,
        @"userID": @(userID),
    };
}

static NSDictionary<NSString*, id>*
BHTWebSessionReadKeychain(void) {
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching(
        (__bridge CFDictionaryRef)
            BHTWebSessionKeychainQuery(YES),
        &result);
    if (status != errSecSuccess || !result) return nil;
    NSData* data = CFBridgingRelease(result);
    if (![data isKindOfClass:NSData.class] || data.length > 8192) {
        return nil;
    }
    id propertyList = [NSPropertyListSerialization
        propertyListWithData:data
                     options:NSPropertyListImmutable
                      format:NULL
                       error:nil];
    return BHTWebSessionValidatedSession(propertyList);
}

static NSDictionary<NSString*, id>*
BHTWebSessionCopySession(void) {
    @synchronized(BHTSecureWebSessionLock()) {
        if (!BHTWebSessionCacheLoaded) {
            BHTWebSessionCachedSession =
                BHTWebSessionReadKeychain();
            BHTWebSessionCacheLoaded = YES;
        }
        return [BHTWebSessionCachedSession copy];
    }
}

static BOOL BHTWebSessionSaveSession(NSDictionary* value) {
    NSDictionary* session = BHTWebSessionValidatedSession(value);
    if (!session) return NO;
    NSData* data = [NSPropertyListSerialization
        dataWithPropertyList:session
                      format:NSPropertyListBinaryFormat_v1_0
                     options:0
                       error:nil];
    if (!data || data.length > 8192) return NO;

    NSDictionary* query = BHTWebSessionKeychainQuery(NO);
    NSDictionary* update = @{
        (__bridge id)kSecValueData: data,
        (__bridge id)kSecAttrAccessible:
            (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    };
    OSStatus status = SecItemUpdate(
        (__bridge CFDictionaryRef)query,
        (__bridge CFDictionaryRef)update);
    if (status == errSecItemNotFound) {
        NSMutableDictionary* item = [query mutableCopy];
        [item addEntriesFromDictionary:update];
        status = SecItemAdd(
            (__bridge CFDictionaryRef)item, NULL);
    }
    if (status != errSecSuccess) return NO;

    @synchronized(BHTSecureWebSessionLock()) {
        BHTWebSessionCachedSession = session;
        BHTWebSessionCacheLoaded = YES;
    }
    return YES;
}

static BOOL BHTWebSessionDeleteKeychain(void) {
    OSStatus status = SecItemDelete(
        (__bridge CFDictionaryRef)
            BHTWebSessionKeychainQuery(NO));
    @synchronized(BHTSecureWebSessionLock()) {
        BHTWebSessionCachedSession = nil;
        BHTWebSessionCacheLoaded = YES;
    }
    return status == errSecSuccess || status == errSecItemNotFound;
}

BOOL BHTSecureWebSessionSignInIsAvailable(void) {
    return BHTWebSessionVersionIsSupported() &&
           NSClassFromString(@"WKWebView") != Nil &&
           BHTCompatibilityWebSessionAccountRuntimeIsAvailable();
}

BOOL BHTSecureWebSessionHasActiveSession(void) {
    return BHTWebSessionCopySession() != nil;
}

NSURLRequest* BHTSecureWebSessionAuthenticatedRequest(
    NSURLRequest* request) {
    if (![request isKindOfClass:NSURLRequest.class] ||
        !BHTWebSessionURLIsAllowed(request.URL)) {
        return request;
    }
    NSDictionary* session = BHTWebSessionCopySession();
    if (!session) return request;
    BHTWebSessionRecord(BHTWebSessionEventRequestEligible);

    NSString* auth = session[@"auth"];
    NSString* csrf = session[@"csrf"];
    uint64_t userID = [session[@"userID"] unsignedLongLongValue];
    if (!BHTWebSessionCredentialValueIsValid(auth) ||
        !BHTWebSessionCredentialValueIsValid(csrf) || userID == 0) {
        return request;
    }

    NSMutableURLRequest* result = [request mutableCopy];
    NSString* authorization =
        [result valueForHTTPHeaderField:@"Authorization"];
    BOOL replaceAuthorization = authorization.length == 0 ||
        [authorization rangeOfString:@"OAuth "
                              options:(NSAnchoredSearch |
                                       NSCaseInsensitiveSearch)].location !=
            NSNotFound;
    if (replaceAuthorization) {
        [result setValue:[@"Bearer "
            stringByAppendingString:BHTWebSessionPublicBearer]
            forHTTPHeaderField:@"Authorization"];
    }
    [result setValue:csrf forHTTPHeaderField:@"x-csrf-token"];
    [result setValue:@"OAuth2Session"
        forHTTPHeaderField:@"x-twitter-auth-type"];
    [result setValue:@"yes"
        forHTTPHeaderField:@"x-twitter-active-user"];
    [result setValue:BHTWebSessionCookieHeader(
                         [result valueForHTTPHeaderField:@"Cookie"],
                         auth, csrf, userID)
        forHTTPHeaderField:@"Cookie"];
    BHTWebSessionRecord(BHTWebSessionEventRequestAuthenticated);
    return result;
}

BOOL BHTSecureWebSessionOwnsNativeAccount(id account) {
    NSDictionary* session = BHTWebSessionCopySession();
    if (!session || !account) return NO;
    SEL usernameSelector = NSSelectorFromString(@"username");
    if (![account respondsToSelector:usernameSelector]) return NO;
    id value = ((id (*)(id, SEL))objc_msgSend)(
        account, usernameSelector);
    NSString* username = BHTWebSessionNormalizedHandle(value);
    return username.length > 0 &&
           [username caseInsensitiveCompare:session[@"screenName"]] ==
               NSOrderedSame;
}

static BOOL BHTWebSessionCookieDomainIsAllowed(NSString* domain) {
    NSString* host = domain.lowercaseString ?: @"";
    while ([host hasPrefix:@"."]) {
        host = [host substringFromIndex:1];
    }
    return [host isEqualToString:@"x.com"] ||
           [host hasSuffix:@".x.com"] ||
           [host isEqualToString:@"twitter.com"] ||
           [host hasSuffix:@".twitter.com"];
}

static BOOL BHTWebSessionCookieIsAuthenticationCookie(
    NSHTTPCookie* cookie) {
    static NSSet<NSString*>* names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = [NSSet setWithArray:@[
            @"auth_token", @"ct0", @"twid"
        ]];
    });
    return [cookie isKindOfClass:NSHTTPCookie.class] &&
           [names containsObject:cookie.name.lowercaseString] &&
           BHTWebSessionCookieDomainIsAllowed(cookie.domain);
}

static NSString* BHTWebSessionCookieFamily(NSHTTPCookie* cookie) {
    NSString* domain = cookie.domain.lowercaseString ?: @"";
    while ([domain hasPrefix:@"."]) {
        domain = [domain substringFromIndex:1];
    }
    if ([domain isEqualToString:@"x.com"] ||
        [domain hasSuffix:@".x.com"]) {
        return @"x";
    }
    if ([domain isEqualToString:@"twitter.com"] ||
        [domain hasSuffix:@".twitter.com"]) {
        return @"twitter";
    }
    return nil;
}

static NSDictionary<NSString*, id>*
BHTWebSessionComponentsFromCookies(
    NSArray<NSHTTPCookie*>* cookies) {
    NSMutableDictionary* families = [@{
        @"x": [NSMutableDictionary dictionary],
        @"twitter": [NSMutableDictionary dictionary],
    } mutableCopy];
    for (NSHTTPCookie* cookie in cookies) {
        if (!BHTWebSessionCookieIsAuthenticationCookie(cookie)) {
            continue;
        }
        NSString* family = BHTWebSessionCookieFamily(cookie);
        if (family.length == 0) continue;
        NSMutableDictionary* values = families[family];
        if (!values) continue;
        NSString* name = cookie.name.lowercaseString;
        if ([name isEqualToString:@"auth_token"] &&
            BHTWebSessionCredentialValueIsValid(cookie.value)) {
            values[@"auth"] = cookie.value;
        } else if ([name isEqualToString:@"ct0"] &&
                   BHTWebSessionCredentialValueIsValid(cookie.value)) {
            values[@"csrf"] = cookie.value;
        } else if ([name isEqualToString:@"twid"]) {
            uint64_t userID =
                BHTWebSessionUserIDFromTWID(cookie.value);
            if (userID > 0) values[@"userID"] = @(userID);
        }
    }
    for (NSString* family in @[@"x", @"twitter"]) {
        NSDictionary* values = families[family];
        if ([values[@"auth"] length] > 0 &&
            [values[@"csrf"] length] > 0 &&
            [values[@"userID"] unsignedLongLongValue] > 0) {
            return [values copy];
        }
    }
    return nil;
}

static void BHTWebSessionClearWebsiteData(
    dispatch_block_t completion) {
    for (NSHTTPCookie* cookie in
             NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies) {
        if (BHTWebSessionCookieIsAuthenticationCookie(cookie)) {
            [NSHTTPCookieStorage.sharedHTTPCookieStorage
                deleteCookie:cookie];
        }
    }

    WKWebsiteDataStore* store =
        WKWebsiteDataStore.defaultDataStore;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    [store.httpCookieStore getAllCookies:^(
        NSArray<NSHTTPCookie*>* cookies) {
        dispatch_group_t cookieGroup = dispatch_group_create();
        for (NSHTTPCookie* cookie in cookies) {
            if (!BHTWebSessionCookieIsAuthenticationCookie(cookie)) {
                continue;
            }
            dispatch_group_enter(cookieGroup);
            [store.httpCookieStore deleteCookie:cookie
                              completionHandler:^{
                                  dispatch_group_leave(cookieGroup);
                              }];
        }
        dispatch_group_notify(
            cookieGroup, dispatch_get_main_queue(), ^{
                dispatch_group_leave(group);
            });
    }];

    NSSet<NSString*>* dataTypes =
        WKWebsiteDataStore.allWebsiteDataTypes;
    dispatch_group_enter(group);
    [store fetchDataRecordsOfTypes:dataTypes
                 completionHandler:^(
        NSArray<WKWebsiteDataRecord*>* records) {
        NSMutableArray<WKWebsiteDataRecord*>* matching =
            [NSMutableArray array];
        for (WKWebsiteDataRecord* record in records) {
            if (BHTWebSessionCookieDomainIsAllowed(
                    record.displayName)) {
                [matching addObject:record];
            }
        }
        if (matching.count == 0) {
            dispatch_group_leave(group);
            return;
        }
        [store removeDataOfTypes:dataTypes
                  forDataRecords:matching
               completionHandler:^{
                   dispatch_group_leave(group);
               }];
    }];

    dispatch_group_notify(
        group, dispatch_get_main_queue(), completion ?: ^{});
}

void BHTRevokeSecureWebSession(
    void (^completion)(BOOL accountShellRemoved)) {
    NSDictionary* session = BHTWebSessionCopySession();
    NSString* screenName = session[@"screenName"];
    BOOL removed = screenName.length > 0 &&
        BHTCompatibilityRemoveWebSessionAccount(screenName);
    BHTWebSessionDeleteKeychain();
    BHTWebSessionRecord(BHTWebSessionEventRevoked);
    BHTWebSessionClearWebsiteData(^{
        if (completion) completion(removed);
    });
}

static UIViewController* BHTWebSessionTopController(
    UIViewController* controller) {
    UIViewController* current = controller;
    while (current) {
        if (current.presentedViewController &&
            !current.presentedViewController.isBeingDismissed) {
            current = current.presentedViewController;
            continue;
        }
        if ([current isKindOfClass:UINavigationController.class]) {
            current = ((UINavigationController*)current)
                .visibleViewController;
            continue;
        }
        if ([current isKindOfClass:UITabBarController.class]) {
            current = ((UITabBarController*)current)
                .selectedViewController;
            continue;
        }
        break;
    }
    return current;
}

static UIViewController* BHTWebSessionActiveController(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState !=
            UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (window.isKeyWindow && window.rootViewController) {
                return BHTWebSessionTopController(
                    window.rootViewController);
            }
        }
    }
    return nil;
}

static BOOL BHTWebSessionNavigationURLIsAllowed(NSURL* URL) {
    if (BHTWebSessionURLIsAllowed(URL)) return YES;
    NSURLComponents* components =
        [NSURLComponents componentsWithURL:URL
                   resolvingAgainstBaseURL:NO];
    if (![[components.scheme lowercaseString]
            isEqualToString:@"https"] ||
        components.user.length > 0 || components.password.length > 0) {
        return NO;
    }
    NSString* host = components.host.lowercaseString ?: @"";
    return [host isEqualToString:@"accounts.google.com"] ||
           [host isEqualToString:@"appleid.apple.com"];
}

@interface BHTSecureWebSessionViewController
    : UIViewController <WKNavigationDelegate>
@property(nonatomic, strong) WKWebView* webView;
@property(nonatomic, strong) UILabel* statusLabel;
@property(nonatomic, strong) UIButton* useAccountButton;
@property(nonatomic, strong) UIActivityIndicatorView* activity;
@property(nonatomic, weak) UIViewController* addAccountController;
@property(nonatomic) BOOL busy;
@end

@implementation BHTSecureWebSessionViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = BHTWebSessionLocalized(
        @"SECURE_WEB_SIGN_IN_TITLE");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                 target:self
                                 action:@selector(closeTapped)];
    if (BHTSecureWebSessionHasActiveSession()) {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc]
                initWithTitle:BHTWebSessionLocalized(
                    @"SECURE_WEB_SIGN_IN_REMOVE")
                         style:UIBarButtonItemStylePlain
                        target:self
                        action:@selector(removeTapped)];
    }

    UILabel* privacy = [UILabel new];
    privacy.translatesAutoresizingMaskIntoConstraints = NO;
    privacy.text = BHTWebSessionLocalized(
        @"SECURE_WEB_SIGN_IN_PRIVACY");
    privacy.font = [UIFont
        preferredFontForTextStyle:UIFontTextStyleFootnote];
    privacy.textColor = UIColor.secondaryLabelColor;
    privacy.adjustsFontForContentSizeCategory = YES;
    privacy.numberOfLines = 0;

    WKWebViewConfiguration* configuration =
        [WKWebViewConfiguration new];
    configuration.websiteDataStore =
        WKWebsiteDataStore.defaultDataStore;
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    self.webView = [[WKWebView alloc]
        initWithFrame:CGRectZero configuration:configuration];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.allowsBackForwardNavigationGestures = YES;

    self.statusLabel = [UILabel new];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.text = BHTWebSessionLocalized(
        @"SECURE_WEB_SIGN_IN_STATUS");
    self.statusLabel.font = [UIFont
        preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.adjustsFontForContentSizeCategory = YES;
    self.statusLabel.numberOfLines = 0;

    self.useAccountButton =
        [UIButton buttonWithType:UIButtonTypeSystem];
    self.useAccountButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.useAccountButton setTitle:BHTWebSessionLocalized(
        @"SECURE_WEB_SIGN_IN_USE_ACCOUNT")
                            forState:UIControlStateNormal];
    self.useAccountButton.titleLabel.font = [UIFont
        preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.useAccountButton.backgroundColor = UIColor.systemBlueColor;
    [self.useAccountButton setTitleColor:UIColor.whiteColor
                               forState:UIControlStateNormal];
    self.useAccountButton.layer.cornerRadius = 12.0;
    [self.useAccountButton addTarget:self
                              action:@selector(useAccountTapped)
                    forControlEvents:UIControlEventTouchUpInside];

    self.activity = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activity.translatesAutoresizingMaskIntoConstraints = NO;
    self.activity.hidesWhenStopped = YES;

    [self.view addSubview:privacy];
    [self.view addSubview:self.webView];
    [self.view addSubview:self.statusLabel];
    [self.view addSubview:self.useAccountButton];
    [self.view addSubview:self.activity];
    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [privacy.topAnchor constraintEqualToAnchor:safe.topAnchor
                                          constant:10.0],
        [privacy.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor
                                              constant:14.0],
        [privacy.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor
                                               constant:-14.0],
        [self.webView.topAnchor constraintEqualToAnchor:privacy.bottomAnchor
                                               constant:10.0],
        [self.webView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.webView.bottomAnchor
                                                   constant:8.0],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor
                                                       constant:14.0],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.activity.leadingAnchor
                                                        constant:-8.0],
        [self.activity.centerYAnchor constraintEqualToAnchor:self.statusLabel.centerYAnchor],
        [self.activity.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor
                                                     constant:-14.0],
        [self.useAccountButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor
                                                        constant:10.0],
        [self.useAccountButton.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor
                                                            constant:14.0],
        [self.useAccountButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor
                                                             constant:-14.0],
        [self.useAccountButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor
                                                           constant:-12.0],
        [self.useAccountButton.heightAnchor constraintEqualToConstant:48.0],
    ]];

    NSURL* URL = [NSURL URLWithString:@"https://x.com/i/flow/login"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:URL]];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed ||
        self.navigationController.isBeingDismissed) {
        BHTWebSessionPresentedController = nil;
    }
}

- (void)setBusy:(BOOL)busy message:(NSString*)message {
    self.busy = busy;
    self.useAccountButton.enabled = !busy;
    self.navigationItem.leftBarButtonItem.enabled = !busy;
    self.navigationItem.rightBarButtonItem.enabled = !busy;
    self.statusLabel.text = message ?: @"";
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    if (busy) [self.activity startAnimating];
    else [self.activity stopAnimating];
}

- (void)showErrorKey:(NSString*)key {
    [self setBusy:NO message:BHTWebSessionLocalized(key)];
    self.statusLabel.textColor = UIColor.systemRedColor;
}

- (void)closeTapped {
    if (self.busy) return;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)removeTapped {
    if (self.busy) return;
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_REMOVE_TITLE")
                         message:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_REMOVE_DETAIL")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction
        actionWithTitle:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_CANCEL")
                  style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction
        actionWithTitle:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_REMOVE")
                  style:UIAlertActionStyleDestructive
                handler:^(__unused UIAlertAction* action) {
        BHTSecureWebSessionViewController* strongSelf = weakSelf;
        [strongSelf setBusy:YES message:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_REMOVING")];
        BHTRevokeSecureWebSession(^(BOOL removed) {
            strongSelf.navigationItem.rightBarButtonItem = nil;
            [strongSelf setBusy:NO message:BHTWebSessionLocalized(
                removed
                    ? @"SECURE_WEB_SIGN_IN_REMOVED"
                    : @"SECURE_WEB_SIGN_IN_REMOVED_ACCOUNT_REMAINS")];
            NSURL* URL = [NSURL URLWithString:
                @"https://x.com/i/flow/login"];
            [strongSelf.webView loadRequest:
                [NSURLRequest requestWithURL:URL]];
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)finishWithCookies:(NSArray<NSHTTPCookie*>*)cookies
              screenName:(NSString*)screenName {
    NSDictionary* components =
        BHTWebSessionComponentsFromCookies(cookies);
    if (!components) {
        BHTWebSessionRecord(BHTWebSessionEventCookieSetIncomplete);
        [self showErrorKey:@"SECURE_WEB_SIGN_IN_NOT_READY"];
        return;
    }
    BHTWebSessionRecord(BHTWebSessionEventCookieSetComplete);
    NSString* handle = BHTWebSessionNormalizedHandle(screenName);
    if (handle.length == 0) {
        [self promptForHandleWithCookies:cookies];
        return;
    }

    NSDictionary* session = @{
        @"version": @1,
        @"auth": components[@"auth"],
        @"csrf": components[@"csrf"],
        @"screenName": handle,
        @"userID": components[@"userID"],
    };
    if (!BHTWebSessionSaveSession(session)) {
        BHTWebSessionRecord(BHTWebSessionEventKeychainSaveFailed);
        [self showErrorKey:@"SECURE_WEB_SIGN_IN_KEYCHAIN_ERROR"];
        return;
    }
    BHTWebSessionRecord(BHTWebSessionEventKeychainSaved);
    BHTWebSessionRecord(BHTWebSessionEventAccountInstallStarted);
    [self setBusy:YES message:BHTWebSessionLocalized(
        @"SECURE_WEB_SIGN_IN_CONNECTING")];
    __weak typeof(self) weakSelf = self;
    BOOL started = BHTCompatibilityInstallWebSessionAccount(
        handle, [components[@"userID"] unsignedLongLongValue],
        self, self.addAccountController,
        ^(BOOL success, __unused NSString* failureCategory) {
            if (success) return;
            BHTSecureWebSessionViewController* strongSelf = weakSelf;
            if (strongSelf.viewIfLoaded.window) {
                BHTWebSessionRecord(
                    BHTWebSessionEventAccountInstallFailed);
                [strongSelf showErrorKey:
                    @"SECURE_WEB_SIGN_IN_ACCOUNT_ERROR"];
            }
        });
    if (!started) {
        BHTWebSessionDeleteKeychain();
        BHTWebSessionRecord(BHTWebSessionEventAccountInstallFailed);
        [self showErrorKey:@"SECURE_WEB_SIGN_IN_ACCOUNT_ERROR"];
    }
}

- (void)promptForHandleWithCookies:(NSArray<NSHTTPCookie*>*)cookies {
    [self setBusy:NO message:BHTWebSessionLocalized(
        @"SECURE_WEB_SIGN_IN_HANDLE_REQUIRED")];
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_HANDLE_TITLE")
                         message:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_HANDLE_DETAIL")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField* field) {
        field.placeholder = @"@username";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.textContentType = UITextContentTypeUsername;
    }];
    [alert addAction:[UIAlertAction
        actionWithTitle:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_CANCEL")
                  style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction
        actionWithTitle:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_CONTINUE")
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction* action) {
        BHTSecureWebSessionViewController* strongSelf = weakSelf;
        NSString* handle = BHTWebSessionNormalizedHandle(
            alert.textFields.firstObject.text);
        if (handle.length == 0) {
            [strongSelf showErrorKey:
                @"SECURE_WEB_SIGN_IN_HANDLE_INVALID"];
            return;
        }
        BHTWebSessionRecord(BHTWebSessionEventHandleEntered);
        [strongSelf finishWithCookies:cookies screenName:handle];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)useAccountTapped {
    if (self.busy) return;
    BHTWebSessionRecord(BHTWebSessionEventConfirmationTapped);
    if (!BHTWebSessionURLIsAllowed(self.webView.URL)) {
        [self showErrorKey:@"SECURE_WEB_SIGN_IN_RETURN_TO_X"];
        return;
    }
    [self setBusy:YES message:BHTWebSessionLocalized(
        @"SECURE_WEB_SIGN_IN_CHECKING")];
    __weak typeof(self) weakSelf = self;
    [self.webView.configuration.websiteDataStore.httpCookieStore
        getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BHTSecureWebSessionViewController* strongSelf = weakSelf;
            if (!strongSelf) return;
            if (!BHTWebSessionComponentsFromCookies(cookies)) {
                BHTWebSessionRecord(
                    BHTWebSessionEventCookieSetIncomplete);
                [strongSelf showErrorKey:
                    @"SECURE_WEB_SIGN_IN_NOT_READY"];
                return;
            }

            // Query only X's stable profile-navigation link. The script does
            // not read document text, forms, storage, or cookies.
            NSString* script =
                @"(() => { const a = document.querySelector('a[data-testid=\"AppTabBar_Profile_Link\"]'); if (!a) return null; const h = a.getAttribute('href') || ''; const m = h.match(/^\\/([A-Za-z0-9_]{1,15})(?:\\/|$)/); return m ? m[1] : null; })()";
            [strongSelf.webView evaluateJavaScript:script
                                 completionHandler:^(id result,
                                                     __unused NSError* error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString* handle =
                        BHTWebSessionNormalizedHandle(result);
                    if (handle.length > 0) {
                        BHTWebSessionRecord(
                            BHTWebSessionEventHandleDetected);
                    }
                    [strongSelf finishWithCookies:cookies
                                       screenName:handle];
                });
            }];
        });
    }];
}

- (void)webView:(WKWebView*)webView
    didStartProvisionalNavigation:(WKNavigation*)navigation {
    if (!self.busy) {
        self.statusLabel.text = BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_LOADING");
    }
}

- (void)webView:(WKWebView*)webView
    didFinishNavigation:(WKNavigation*)navigation {
    if (!self.busy) {
        self.statusLabel.text = BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_STATUS");
    }
}

- (void)webView:(WKWebView*)webView
    didFailProvisionalNavigation:(WKNavigation*)navigation
                       withError:(NSError*)error {
    if (!self.busy && error.code != NSURLErrorCancelled) {
        [self showErrorKey:@"SECURE_WEB_SIGN_IN_LOAD_ERROR"];
    }
}

- (void)webView:(WKWebView*)webView
    decidePolicyForNavigationAction:(WKNavigationAction*)action
                    decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    if (!action.targetFrame.isMainFrame ||
        BHTWebSessionNavigationURLIsAllowed(action.request.URL)) {
        handler(WKNavigationActionPolicyAllow);
    } else {
        handler(WKNavigationActionPolicyCancel);
        if (!self.busy) {
            [self showErrorKey:@"SECURE_WEB_SIGN_IN_BLOCKED_HOST"];
        }
    }
}

@end

static void BHTPresentSecureWebSessionBrowser(
    UIViewController* source,
    UIViewController* addAccountController) {
    if (BHTWebSessionPresentedController) return;
    BHTSecureWebSessionViewController* controller =
        [BHTSecureWebSessionViewController new];
    controller.addAccountController = addAccountController;
    UINavigationController* navigation =
        [[UINavigationController alloc]
            initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    navigation.preferredContentSize = CGSizeMake(620.0, 760.0);
    BHTWebSessionPresentedController = navigation;
    BHTWebSessionRecord(BHTWebSessionEventPresented);
    [source presentViewController:navigation
                        animated:YES completion:nil];
}

void BHTPresentSecureWebSessionSignIn(
    UIViewController* presenter,
    UIViewController* addAccountController) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController* source = BHTWebSessionTopController(presenter) ?:
            BHTWebSessionActiveController();
        if (!source || BHTWebSessionPresentedController) return;
        if (!BHTSecureWebSessionSignInIsAvailable()) {
            UIAlertController* unavailable = [UIAlertController
                alertControllerWithTitle:BHTWebSessionLocalized(
                    @"SECURE_WEB_SIGN_IN_TITLE")
                                 message:BHTWebSessionLocalized(
                    @"SECURE_WEB_SIGN_IN_UNAVAILABLE")
                          preferredStyle:UIAlertControllerStyleAlert];
            [unavailable addAction:[UIAlertAction
                actionWithTitle:BHTWebSessionLocalized(
                    @"COMPATIBILITY_SIGN_IN_OK")
                          style:UIAlertActionStyleCancel handler:nil]];
            [source presentViewController:unavailable
                                 animated:YES completion:nil];
            return;
        }
        BHTPresentSecureWebSessionBrowser(
            source, addAccountController);
    });
}

NSDictionary<NSString*, id>*
BHTSecureWebSessionDiagnosticSnapshot(void) {
    NSArray<NSString*>* names = @[
        @"presented",
        @"confirmationTapped",
        @"cookieSetComplete",
        @"cookieSetIncomplete",
        @"handleDetected",
        @"handleEntered",
        @"keychainSaved",
        @"keychainSaveFailed",
        @"accountInstallStarted",
        @"accountInstallFailed",
        @"requestEligible",
        @"requestAuthenticated",
        @"revoked",
    ];
    NSMutableDictionary* counters =
        [NSMutableDictionary dictionaryWithCapacity:names.count];
    [names enumerateObjectsUsingBlock:^(
        NSString* name, NSUInteger index, __unused BOOL* stop) {
        counters[name] = @(atomic_load_explicit(
            &BHTWebSessionCounters[index], memory_order_relaxed));
    }];
    return @{
        @"available": @(BHTSecureWebSessionSignInIsAvailable()),
        @"activeSessionPresent":
            @(BHTSecureWebSessionHasActiveSession()),
        @"passwordReadByTweak": @NO,
        @"cookieReadRequiresUserConfirmation": @YES,
        @"sessionStoredInDeviceOnlyKeychain": @YES,
        @"sessionStoredInUserDefaults": @NO,
        @"sessionStoredInPlaintextFile": @NO,
        @"credentialLoggingIncluded": @NO,
        @"requestHostPolicy": @"https_exact_domain_or_subdomain",
        @"requestDomains": @[@"x.com", @"twitter.com"],
        @"requestMutationLayer": @"NSURLSession_task_constructors",
        @"globalMutableRequestHooksIncluded": @NO,
        @"hiddenGestureEntryIncluded": @NO,
        @"nativeAccountUsesSessionSecrets": @NO,
        @"revocationClearsKeychainAndWebData": @YES,
        @"counters": [counters copy],
    };
}
