#import "Login/BHTCompatibilityLogin.h"

#import "Core/BHTBundle.h"

#import <WebKit/WebKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <string.h>

static NSString* const BHTCompatibilityTargetVersion = @"12.9";
static NSString* const BHTMetricsHandlerName = @"bht";

@protocol BHTXAuthPasswordCommandInitializing <NSObject>
// X 12.9 encodes this completion block as v28@?0B8@12@20.
- (instancetype)
    initWithContext:(id)context
          accountID:(id)accountID
        authContext:(id)authContext
         identifier:(NSString*)identifier
           password:(NSString*)password
     simCountryCode:(id)simCountryCode
httpRequestConfiguration:(id)requestConfiguration
supportOneFactorAuthorization:(BOOL)supportOneFactorAuthorization
   knownDeviceToken:(id)knownDeviceToken
          uiMetrics:(NSString* _Nullable)metrics
   authTokenStorage:(id)authTokenStorage
             source:(id _Nullable)source
responseModelBuilder:(id)responseBuilder
    completionBlock:
        (void (^)(BOOL success, id response, id error))completion;
@end

@protocol BHTNativeAccountInitializing <NSObject>
- (instancetype)initWithUsername:(NSString*)username
                          userID:(uint64_t)userID;
- (void)updateUserInfoAndCredentialsWithToken:(NSString*)token
                                       secret:(NSString*)secret
                                     username:(NSString*)username;
@end

typedef NS_ENUM(NSUInteger, BHTCompatibilityLoginEvent) {
    BHTCompatibilityLoginEventPresented = 0,
    BHTCompatibilityLoginEventAttempted,
    BHTCompatibilityLoginEventMetricsResolved,
    BHTCompatibilityLoginEventMetricsTimedOut,
    BHTCompatibilityLoginEventCommandStarted,
    BHTCompatibilityLoginEventAuthenticated,
    BHTCompatibilityLoginEventChallengeRequired,
    BHTCompatibilityLoginEventChallengePresented,
    BHTCompatibilityLoginEventAccountRegistered,
    BHTCompatibilityLoginEventFailed,
    BHTCompatibilityLoginEventCount,
};

static atomic_ulong
    BHTCompatibilityLoginCounters[BHTCompatibilityLoginEventCount];
static NSString* BHTCompatibilityLoginLastStage = @"idle";
static NSString* BHTCompatibilityLoginLastFailure = @"none";
static char BHTCompatibilityEntryButtonKey;
static char BHTCompatibilityEntryTargetKey;
static void* BHTCompatibilityFrameworkHandle;

static NSObject* BHTCompatibilityLoginLock(void) {
    static NSObject* lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static NSString* BHTCompatibilityLocalized(NSString* key) {
    return [[BHTBundle sharedBundle] localizedStringForKey:key];
}

static void BHTCompatibilityRecord(
    BHTCompatibilityLoginEvent event,
    NSString* stage,
    NSString* failureCategory) {
    if (event < BHTCompatibilityLoginEventCount) {
        atomic_fetch_add_explicit(
            &BHTCompatibilityLoginCounters[event], 1,
            memory_order_relaxed);
    }
    @synchronized(BHTCompatibilityLoginLock()) {
        if (stage.length > 0) {
            BHTCompatibilityLoginLastStage = [stage copy];
        }
        if (failureCategory.length > 0) {
            BHTCompatibilityLoginLastFailure =
                [failureCategory copy];
        }
    }
}

static NSString* BHTAppVersion(void) {
    id value = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static BOOL BHTCompatibilityVersionIsSupported(void) {
    return [BHTAppVersion()
        isEqualToString:BHTCompatibilityTargetVersion];
}

static void BHTLoadCompatibilityFrameworkIfNeeded(void) {
    if (NSClassFromString(
            @"TFSTwitterAPIXAuthPasswordCommand")) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* frameworksPath =
            NSBundle.mainBundle.privateFrameworksPath;
        NSString* binaryPath = [[frameworksPath
            stringByAppendingPathComponent:
                @"TwitterSPMMigration.framework"]
            stringByAppendingPathComponent:
                @"TwitterSPMMigration"];
        if (binaryPath.length > 0) {
            BHTCompatibilityFrameworkHandle = dlopen(
                binaryPath.fileSystemRepresentation,
                RTLD_LAZY | RTLD_LOCAL);
        }
    });
}

static BOOL BHTClassResponds(
    NSString* className, NSString* selectorName) {
    Class cls = NSClassFromString(className);
    return cls &&
           [cls respondsToSelector:NSSelectorFromString(selectorName)];
}

static id BHTGuestAccountIdentifier(void) {
    void* address =
        dlsym(RTLD_DEFAULT, "TFSTwitterAPIGuestAccountID");
    if (!address && BHTCompatibilityFrameworkHandle) {
        address = dlsym(
            BHTCompatibilityFrameworkHandle,
            "TFSTwitterAPIGuestAccountID");
    }
    if (!address) return nil;
    __unsafe_unretained id* value =
        (__unsafe_unretained id*)address;
    return value ? *value : nil;
}

static const char* BHTUnqualifiedObjCType(const char* type) {
    while (type && strchr("rnNoORV", type[0]) != NULL) {
        type++;
    }
    return type;
}

static BOOL BHTSignatureArgumentIsObject(
    NSMethodSignature* signature, NSUInteger index) {
    if (!signature || index >= signature.numberOfArguments) {
        return NO;
    }
    const char* type = BHTUnqualifiedObjCType(
        [signature getArgumentTypeAtIndex:index]);
    return type && type[0] == '@';
}

static BOOL BHTSignatureArgumentIsInteger(
    NSMethodSignature* signature, NSUInteger index) {
    if (!signature || index >= signature.numberOfArguments) {
        return NO;
    }
    const char* type = BHTUnqualifiedObjCType(
        [signature getArgumentTypeAtIndex:index]);
    return type && strchr("qQlL", type[0]) != NULL;
}

static BOOL BHTSignatureArgumentIsBoolean(
    NSMethodSignature* signature, NSUInteger index) {
    if (!signature || index >= signature.numberOfArguments) {
        return NO;
    }
    const char* type = BHTUnqualifiedObjCType(
        [signature getArgumentTypeAtIndex:index]);
    return type &&
           (type[0] == 'B' || type[0] == 'c' || type[0] == 'C');
}

static NSMethodSignature* BHTInstanceMethodSignature(
    Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    const char* typeEncoding =
        method ? method_getTypeEncoding(method) : NULL;
    return typeEncoding
               ? [NSMethodSignature
                     signatureWithObjCTypes:typeEncoding]
               : nil;
}

static BOOL BHTPasswordCommandSignatureIsSupported(void) {
    Class commandClass =
        NSClassFromString(@"TFSTwitterAPIXAuthPasswordCommand");
    SEL initializer = NSSelectorFromString(
        @"initWithContext:accountID:authContext:identifier:"
         @"password:simCountryCode:httpRequestConfiguration:"
         @"supportOneFactorAuthorization:knownDeviceToken:"
         @"uiMetrics:authTokenStorage:source:responseModelBuilder:"
         @"completionBlock:");
    NSMethodSignature* signature =
        BHTInstanceMethodSignature(commandClass, initializer);
    if (!signature || signature.numberOfArguments != 16) return NO;

    const char* returnType =
        BHTUnqualifiedObjCType(signature.methodReturnType);
    if (!returnType || returnType[0] != '@') return NO;

    for (NSUInteger index = 2; index <= 8; index++) {
        if (!BHTSignatureArgumentIsObject(signature, index)) {
            return NO;
        }
    }
    if (!BHTSignatureArgumentIsBoolean(signature, 9)) {
        return NO;
    }
    for (NSUInteger index = 10; index <= 15; index++) {
        if (!BHTSignatureArgumentIsObject(signature, index)) {
            return NO;
        }
    }
    return YES;
}

static BOOL BHTNativeAccountSignaturesAreSupported(void) {
    Class accountClass = NSClassFromString(@"TFNTwitterAccount");
    NSMethodSignature* initializer =
        BHTInstanceMethodSignature(
            accountClass,
            NSSelectorFromString(@"initWithUsername:userID:"));
    const char* initializerReturn = BHTUnqualifiedObjCType(
        initializer.methodReturnType);
    if (!initializer || initializer.numberOfArguments != 4 ||
        !initializerReturn || initializerReturn[0] != '@' ||
        !BHTSignatureArgumentIsObject(initializer, 2) ||
        !BHTSignatureArgumentIsInteger(initializer, 3)) {
        return NO;
    }

    NSMethodSignature* update =
        BHTInstanceMethodSignature(
            accountClass,
            NSSelectorFromString(
                @"updateUserInfoAndCredentialsWithToken:"
                 @"secret:username:"));
    const char* updateReturn =
        BHTUnqualifiedObjCType(update.methodReturnType);
    return update && update.numberOfArguments == 5 &&
           updateReturn && updateReturn[0] == 'v' &&
           BHTSignatureArgumentIsObject(update, 2) &&
           BHTSignatureArgumentIsObject(update, 3) &&
           BHTSignatureArgumentIsObject(update, 4);
}

static BOOL BHTLoginChallengeFactorySignatureIsSupported(
    Class factoryClass, SEL selector) {
    Method method = class_getClassMethod(factoryClass, selector);
    const char* typeEncoding =
        method ? method_getTypeEncoding(method) : NULL;
    NSMethodSignature* signature =
        typeEncoding
            ? [NSMethodSignature signatureWithObjCTypes:typeEncoding]
            : nil;
    const char* returnType =
        BHTUnqualifiedObjCType(signature.methodReturnType);
    return signature && signature.numberOfArguments == 9 &&
           returnType && returnType[0] == '@' &&
           BHTSignatureArgumentIsInteger(signature, 2) &&
           BHTSignatureArgumentIsInteger(signature, 3) &&
           BHTSignatureArgumentIsObject(signature, 4) &&
           BHTSignatureArgumentIsObject(signature, 5) &&
           BHTSignatureArgumentIsInteger(signature, 6) &&
           BHTSignatureArgumentIsObject(signature, 7) &&
           BHTSignatureArgumentIsInteger(signature, 8);
}

static BOOL BHTHostAccountSwitchSignatureIsSupported(void) {
    Class hostClass =
        NSClassFromString(@"T1HostViewController");
    SEL selector =
        NSSelectorFromString(@"viewAccount:animated:");
    NSMethodSignature* signature =
        BHTInstanceMethodSignature(hostClass, selector);
    const char* returnType =
        BHTUnqualifiedObjCType(signature.methodReturnType);
    return hostClass &&
           [hostClass respondsToSelector:
                          NSSelectorFromString(
                              @"sharedHostViewController")] &&
           signature && signature.numberOfArguments == 4 &&
           returnType && returnType[0] == 'v' &&
           BHTSignatureArgumentIsObject(signature, 2) &&
           BHTSignatureArgumentIsBoolean(signature, 3);
}

static BOOL BHTCompatibilityRuntimeIsAvailable(void) {
    if (!BHTCompatibilityVersionIsSupported()) return NO;
    BHTLoadCompatibilityFrameworkIfNeeded();
    if (!BHTGuestAccountIdentifier()) return NO;

    NSArray<NSString*>* classes = @[
        @"TFSTwitterAPIXAuthPasswordCommand",
        @"TFSTwitterServiceRunner",
        @"TNUServiceHTTPConfiguration",
        @"T1OnboardingAuthTokenStorage",
        @"TFSTwitterXAuthPasswordResponseBuilder",
        @"TFNTwitterAccount",
        @"TFNTwitter",
        @"T1HostViewController",
        @"T1LoginChallengeFactory",
    ];
    for (NSString* className in classes) {
        if (!NSClassFromString(className)) return NO;
    }

    return
        BHTClassResponds(
            @"TFSTwitterServiceRunner", @"APICommandContext") &&
        BHTClassResponds(
            @"TFSTwitterServiceRunner", @"APICommandLoader") &&
        BHTClassResponds(
            @"TNUServiceHTTPConfiguration",
            @"configurationForForegroundRetriableRequest") &&
        BHTClassResponds(
            @"TFNTwitterAccount", @"knownDeviceToken") &&
        BHTNativeAccountSignaturesAreSupported() &&
        BHTClassResponds(@"TFNTwitter", @"sharedTwitter") &&
        BHTClassResponds(@"TFNTwitter", @"saveSharedTwitter") &&
        BHTHostAccountSwitchSignatureIsSupported() &&
        BHTPasswordCommandSignatureIsSupported();
}

BOOL BHTCompatibilitySignInIsAvailable(void) {
    return BHTCompatibilityRuntimeIsAvailable();
}

static id BHTSendObject(id target, SEL selector) {
    if (!target || !selector ||
        ![target respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static uint64_t BHTSendUnsignedValue(id target, SEL selector) {
    if (!target || !selector ||
        ![target respondsToSelector:selector]) {
        return 0;
    }

    NSMethodSignature* signature =
        [target methodSignatureForSelector:selector];
    const char* returnType = signature.methodReturnType;
    while (returnType &&
           strchr("rnNoORV", returnType[0]) != NULL) {
        returnType++;
    }
    if (returnType && returnType[0] == '@') {
        id value = BHTSendObject(target, selector);
        return [value respondsToSelector:@selector(unsignedLongLongValue)]
                   ? [value unsignedLongLongValue]
                   : 0;
    }
    return ((uint64_t (*)(id, SEL))objc_msgSend)(
        target, selector);
}

static NSInteger BHTSendIntegerValue(
    id target, SEL selector) {
    return (NSInteger)BHTSendUnsignedValue(target, selector);
}

static UIViewController* BHTTopViewController(
    UIViewController* controller) {
    UIViewController* current = controller;
    while (current) {
        if (current.presentedViewController &&
            !current.presentedViewController.isBeingDismissed) {
            current = current.presentedViewController;
            continue;
        }
        if ([current isKindOfClass:UINavigationController.class]) {
            UIViewController* visible =
                [(UINavigationController*)current visibleViewController];
            if (visible && visible != current) {
                current = visible;
                continue;
            }
        }
        if ([current isKindOfClass:UITabBarController.class]) {
            UIViewController* selected =
                [(UITabBarController*)current selectedViewController];
            if (selected && selected != current) {
                current = selected;
                continue;
            }
        }
        break;
    }
    return current;
}

static UIViewController* BHTActiveViewController(void) {
    UIWindow* activeWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState !=
                UISceneActivationStateForegroundActive ||
                ![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }
            for (UIWindow* window in ((UIWindowScene*)scene).windows) {
                if (window.isKeyWindow) {
                    activeWindow = window;
                    break;
                }
            }
            if (activeWindow) break;
        }
    }
    if (!activeWindow) {
        activeWindow = UIApplication.sharedApplication.keyWindow;
    }
    return BHTTopViewController(activeWindow.rootViewController);
}

@interface BHTCompatibilityMetricsCollector
    : NSObject <WKScriptMessageHandler>
@property(nonatomic, strong) WKWebView* webView;
@property(nonatomic, copy)
    void (^completion)(NSString* _Nullable metrics);
@property(nonatomic) BOOL finished;
- (void)startWithCompletion:
    (void (^)(NSString* _Nullable metrics))completion;
- (void)cancel;
@end

@implementation BHTCompatibilityMetricsCollector

- (void)startWithCompletion:
    (void (^)(NSString* _Nullable metrics))completion {
    self.completion = completion;

    WKWebViewConfiguration* configuration =
        [WKWebViewConfiguration new];
    configuration.websiteDataStore =
        [WKWebsiteDataStore nonPersistentDataStore];

    WKUserContentController* contentController =
        [WKUserContentController new];
    NSString* source =
        @"(function(){function rep(u){try{var p=new URL(String(u),"
         @"window.location.href);var r=p.searchParams.get('result');"
         @"if(typeof r==='string'&&r.length>0&&r.length<=65536){"
         @"window.webkit.messageHandlers.bht.postMessage(r);}}catch(e){}}"
         @"var of=window.fetch;if(of){window.fetch=function(){try{"
         @"rep(arguments[0]&&arguments[0].url?arguments[0].url:"
         @"arguments[0]);}catch(e){}return of.apply(this,arguments);"
         @"};}var oo=XMLHttpRequest.prototype.open;"
         @"XMLHttpRequest.prototype.open=function(m,u){try{rep(u);}"
         @"catch(e){}return oo.apply(this,arguments);};"
         @"if(navigator.sendBeacon){var sb=navigator.sendBeacon.bind("
         @"navigator);navigator.sendBeacon=function(u,d){try{rep(u);}"
         @"catch(e){}return sb(u,d);};}})();";
    WKUserScript* script = [[WKUserScript alloc]
        initWithSource:source
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
      forMainFrameOnly:YES];
    [contentController addUserScript:script];
    [contentController addScriptMessageHandler:self
                                          name:BHTMetricsHandlerName];
    configuration.userContentController = contentController;

    self.webView =
        [[WKWebView alloc] initWithFrame:CGRectZero
                           configuration:configuration];
    NSURL* endpoint =
        [NSURL URLWithString:@"https://x.com/i/js_inst?native=true"];
    if (!endpoint) {
        [self finishWithMetrics:nil];
        return;
    }
    NSURLRequest* request = [NSURLRequest
        requestWithURL:endpoint
           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
       timeoutInterval:12.0];
    [self.webView loadRequest:request];

    __weak typeof(self) weakSelf = self;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(12.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            if (!weakSelf || weakSelf.finished) return;
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventMetricsTimedOut,
                @"metrics_timeout", nil);
            [weakSelf finishWithMetrics:nil];
        });
}

- (void)userContentController:
            (WKUserContentController*)userContentController
      didReceiveScriptMessage:(WKScriptMessage*)message {
    if (self.finished ||
        ![message.name isEqualToString:BHTMetricsHandlerName] ||
        ![message.body isKindOfClass:NSString.class]) {
        return;
    }

    NSString* metrics = (NSString*)message.body;
    if (metrics.length > 0 && metrics.length <= 65536) {
        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventMetricsResolved,
            @"metrics_resolved", nil);
        [self finishWithMetrics:metrics];
    }
}

- (void)cancel {
    if (self.finished) return;
    self.finished = YES;
    [self.webView stopLoading];
    [self.webView.configuration.userContentController
        removeScriptMessageHandlerForName:BHTMetricsHandlerName];
    self.webView = nil;
    self.completion = nil;
}

- (void)finishWithMetrics:(NSString*)metrics {
    if (self.finished) return;
    self.finished = YES;
    [self.webView stopLoading];
    [self.webView.configuration.userContentController
        removeScriptMessageHandlerForName:BHTMetricsHandlerName];
    self.webView = nil;

    void (^completion)(NSString*) = self.completion;
    self.completion = nil;
    if (completion) completion(metrics);
}

- (void)dealloc {
    [self.webView.configuration.userContentController
        removeScriptMessageHandlerForName:BHTMetricsHandlerName];
}

@end

static id BHTCreatePasswordCommand(
    NSString* identifier,
    NSString* password,
    NSString* metrics,
    void (^completion)(BOOL success, id response, id error)) {
    Class serviceRunner =
        NSClassFromString(@"TFSTwitterServiceRunner");
    Class configurationClass =
        NSClassFromString(@"TNUServiceHTTPConfiguration");
    Class accountClass =
        NSClassFromString(@"TFNTwitterAccount");
    Class storageClass =
        NSClassFromString(@"T1OnboardingAuthTokenStorage");
    Class builderClass =
        NSClassFromString(@"TFSTwitterXAuthPasswordResponseBuilder");
    Class commandClass =
        NSClassFromString(@"TFSTwitterAPIXAuthPasswordCommand");

    id context = BHTSendObject(
        serviceRunner, NSSelectorFromString(@"APICommandContext"));
    id accountID = BHTGuestAccountIdentifier();
    id authContext = nil;
    id simCountryCode = nil;
    id requestConfiguration = BHTSendObject(
        configurationClass,
        NSSelectorFromString(
            @"configurationForForegroundRetriableRequest"));
    BOOL supportOneFactorAuthorization = NO;
    id knownDeviceToken = BHTSendObject(
        accountClass, NSSelectorFromString(@"knownDeviceToken"));
    id authTokenStorage = [[storageClass alloc] init];
    id source = nil;
    id responseBuilder = [[builderClass alloc] init];
    id completionBlock = [completion copy];

    if (!context || !accountID || !requestConfiguration ||
        !authTokenStorage || !responseBuilder ||
        identifier.length == 0 || password.length == 0) {
        return nil;
    }

    if (!BHTPasswordCommandSignatureIsSupported()) {
        return nil;
    }

    id<BHTXAuthPasswordCommandInitializing> allocatedCommand =
        (id)[commandClass alloc];
    return [allocatedCommand
        initWithContext:context
              accountID:accountID
            authContext:authContext
             identifier:identifier
               password:password
         simCountryCode:simCountryCode
httpRequestConfiguration:requestConfiguration
supportOneFactorAuthorization:supportOneFactorAuthorization
       knownDeviceToken:knownDeviceToken
              uiMetrics:metrics
       authTokenStorage:authTokenStorage
                 source:source
   responseModelBuilder:responseBuilder
        completionBlock:completionBlock];
}

static BOOL BHTStartPasswordCommand(id command) {
    if (!command) return NO;
    Class serviceRunner =
        NSClassFromString(@"TFSTwitterServiceRunner");
    id loader = BHTSendObject(
        serviceRunner, NSSelectorFromString(@"APICommandLoader"));
    SEL start = NSSelectorFromString(@"startCommand:");
    if (!loader || ![loader respondsToSelector:start]) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(
        loader, start, command);
    return YES;
}

static id BHTBuildNativeAccount(
    NSString* token,
    NSString* secret,
    NSString* screenName,
    uint64_t userID) {
    if (token.length == 0 || secret.length == 0 ||
        screenName.length == 0 || userID == 0) {
        return nil;
    }

    Class accountClass =
        NSClassFromString(@"TFNTwitterAccount");
    SEL initializer =
        NSSelectorFromString(@"initWithUsername:userID:");
    SEL update = NSSelectorFromString(
        @"updateUserInfoAndCredentialsWithToken:secret:username:");
    if (!accountClass ||
        ![accountClass instancesRespondToSelector:initializer] ||
        ![accountClass instancesRespondToSelector:update]) {
        return nil;
    }

    id<BHTNativeAccountInitializing> account =
        [(id<BHTNativeAccountInitializing>)[accountClass alloc]
            initWithUsername:screenName
                     userID:userID];
    if (!account) return nil;
    [account updateUserInfoAndCredentialsWithToken:token
                                           secret:secret
                                         username:screenName];
    return account;
}

static BOOL BHTRegisterNativeAccount(id account) {
    if (!account) return NO;
    Class twitterClass = NSClassFromString(@"TFNTwitter");
    id twitter = BHTSendObject(
        twitterClass, NSSelectorFromString(@"sharedTwitter"));
    id accountService = BHTSendObject(
        twitter, NSSelectorFromString(@"accountService"));
    SEL addAccount = NSSelectorFromString(@"addAccount:");
    SEL save = NSSelectorFromString(@"saveSharedTwitter");
    if (!twitter || !accountService ||
        ![accountService respondsToSelector:addAccount] ||
        ![twitterClass respondsToSelector:save]) {
        return NO;
    }

    ((void (*)(id, SEL, id))objc_msgSend)(
        accountService, addAccount, account);
    ((void (*)(id, SEL))objc_msgSend)(twitterClass, save);

    SEL refresh = NSSelectorFromString(@"refreshForced:source:");
    if ([account respondsToSelector:refresh]) {
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(
            account, refresh, NO, nil);
    }

    Class notificationClass =
        NSClassFromString(@"TFSAccountNotification");
    NSString* notificationName = BHTSendObject(
        notificationClass,
        NSSelectorFromString(@"TFSAccountsDidChange"));
    if ([notificationName isKindOfClass:NSString.class] &&
        notificationName.length > 0) {
        [NSNotificationCenter.defaultCenter
            postNotificationName:notificationName
                          object:twitter
                        userInfo:nil];
    }
    BHTCompatibilityRecord(
        BHTCompatibilityLoginEventAccountRegistered,
        @"account_registered", nil);
    return YES;
}

static BOOL BHTSwitchToNativeAccount(id account) {
    if (!account ||
        !BHTHostAccountSwitchSignatureIsSupported()) {
        return NO;
    }
    Class hostClass =
        NSClassFromString(@"T1HostViewController");
    id host = BHTSendObject(
        hostClass,
        NSSelectorFromString(@"sharedHostViewController"));
    SEL viewAccount =
        NSSelectorFromString(@"viewAccount:animated:");
    if (host && [host respondsToSelector:viewAccount]) {
        @try {
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(
                host, viewAccount, account, YES);
            return YES;
        } @catch (__unused NSException* exception) {
            return NO;
        }
    }
    return NO;
}

typedef void (^BHTCompatibilityResult)(
    BOOL success, NSString* _Nullable failureCategory);

static void BHTCompleteSignedOutFlowAndSwitchAccount(
    id account,
    UIViewController* compatibilityController,
    BHTCompatibilityResult result) {
    Class hostClass =
        NSClassFromString(@"T1HostViewController");
    id host = BHTSendObject(
        hostClass,
        NSSelectorFromString(@"sharedHostViewController"));
    if (!host ||
        ![host respondsToSelector:
                   NSSelectorFromString(@"viewAccount:animated:")]) {
        if (result) result(NO, @"account_switch_failed");
        return;
    }

    void (^switchAccount)(void) = ^{
        BOOL switched = BHTSwitchToNativeAccount(account);
        if (result) {
            result(
                switched,
                switched ? nil : @"account_switch_failed");
        }
    };

    id signedOutFlow = BHTSendObject(
        host, NSSelectorFromString(@"signedOutOnboardingFlow"));
    SEL completeSelector =
        NSSelectorFromString(@"completeFlowAnimated:completion:");
    if (signedOutFlow &&
        [signedOutFlow respondsToSelector:completeSelector]) {
        // Let X tear down its full signed-out flow before switching. This
        // avoids depending on a private presenter hierarchy.
        @try {
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(
                signedOutFlow, completeSelector, YES,
                [switchAccount copy]);
        } @catch (__unused NSException* exception) {
            if (result) result(NO, @"account_switch_failed");
        }
        return;
    }

    UIViewController* modal =
        compatibilityController.navigationController ?:
        compatibilityController;
    if (modal.presentingViewController) {
        [modal dismissViewControllerAnimated:YES
                                  completion:switchAccount];
    } else {
        switchAccount();
    }
}

static BOOL BHTPresentNativeLoginChallenge(
    id response,
    NSString* fallbackUsername,
    BHTCompatibilityResult result) {
    SEL requestIDSelector =
        NSSelectorFromString(@"loginVerificationRequestId");
    SEL challengeURLSelector =
        NSSelectorFromString(@"challengeURLString");
    id requestID = BHTSendObject(response, requestIDSelector);
    id challengeURL =
        BHTSendObject(response, challengeURLSelector);
    if (!requestID || !challengeURL) return NO;

    Class factoryClass =
        NSClassFromString(@"T1LoginChallengeFactory");
    Class hostClass =
        NSClassFromString(@"T1HostViewController");
    SEL factorySelector = NSSelectorFromString(
        @"loginChallengeWithMode:loginType:requestID:user:"
         @"userID:URLString:loginCause:");
    id host = BHTSendObject(
        hostClass,
        NSSelectorFromString(@"sharedHostViewController"));
    if (!factoryClass ||
        !BHTLoginChallengeFactorySignatureIsSupported(
            factoryClass, factorySelector) ||
        !host) {
        if (result) result(NO, @"challenge_runtime_missing");
        return YES;
    }

    BOOL securityKeyEnabled = NO;
    Class switchesClass =
        NSClassFromString(@"TPSDeviceFeatureSwitches");
    SEL securityKeySelector =
        NSSelectorFromString(@"isSecurityKeyAuthEnabled");
    if ([switchesClass respondsToSelector:securityKeySelector]) {
        securityKeyEnabled =
            ((BOOL (*)(id, SEL))objc_msgSend)(
                switchesClass, securityKeySelector);
    }
    NSInteger mode = securityKeyEnabled ? 1 : 0;
    NSInteger loginType = BHTSendIntegerValue(
        response,
        NSSelectorFromString(@"loginVerificationRequestType"));
    NSInteger loginCause = BHTSendIntegerValue(
        response,
        NSSelectorFromString(@"loginVerificationRequestCause"));
    uint64_t userID = BHTSendUnsignedValue(
        response,
        NSSelectorFromString(@"loginVerificationUserId"));
    if (userID == 0) {
        userID = BHTSendUnsignedValue(
            response, NSSelectorFromString(@"userId"));
    }

    id challenge =
        ((id (*)(id, SEL, NSInteger, NSInteger, id, id,
                 uint64_t, id, NSInteger))objc_msgSend)(
            factoryClass, factorySelector, mode, loginType,
            requestID, fallbackUsername ?: @"", userID,
            challengeURL, loginCause);
    if (!challenge) {
        if (result) result(NO, @"challenge_creation_failed");
        return YES;
    }

    SEL didAddSelector =
        NSSelectorFromString(@"setDidAddAccountBlock:");
    if (![challenge respondsToSelector:didAddSelector]) {
        if (result) result(NO, @"challenge_completion_missing");
        return YES;
    }
    {
        void (^didAddAccount)(id, id) =
            ^(__unused id firstValue, id account) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    BOOL registered = NO;
                    @try {
                        registered =
                            BHTRegisterNativeAccount(account);
                    } @catch (__unused NSException* exception) {
                        registered = NO;
                    }
                    if (!registered) {
                        if (result) {
                            result(
                                NO,
                                @"account_registration_failed");
                        }
                        return;
                    }

                    void (^switchAccount)(void) = ^{
                        BOOL switched =
                            BHTSwitchToNativeAccount(account);
                        if (result) {
                            result(
                                switched,
                                switched
                                    ? nil
                                    : @"account_switch_failed");
                        }
                    };
                    if (host.presentedViewController &&
                        !host.presentedViewController.isBeingDismissed) {
                        [host
                            dismissViewControllerAnimated:YES
                                               completion:switchAccount];
                    } else {
                        switchAccount();
                    }
                });
            };
        ((void (*)(id, SEL, id))objc_msgSend)(
            challenge, didAddSelector, [didAddAccount copy]);
    }

    SEL setProvider =
        NSSelectorFromString(@"setLoginChallengeProvider:");
    if ([host respondsToSelector:setProvider]) {
        ((void (*)(id, SEL, id))objc_msgSend)(
            host, setProvider, challenge);
    }

    SEL presentSelector = NSSelectorFromString(
        @"presentLoginChallengeFromViewController:animated:completion:");
    if (![challenge respondsToSelector:presentSelector]) {
        if (result) result(NO, @"challenge_presentation_missing");
        return YES;
    }

    void (^presentChallenge)(void) = ^{
        @try {
            ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(
                challenge, presentSelector, host, YES, nil);
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventChallengePresented,
                @"challenge_presented", nil);
        } @catch (__unused NSException* exception) {
            if (result) {
                result(NO, @"challenge_presentation_failed");
            }
        }
    };

    SEL flowSelector =
        NSSelectorFromString(@"signedOutOnboardingFlow");
    id signedOutFlow = BHTSendObject(host, flowSelector);
    SEL completeSelector =
        NSSelectorFromString(@"completeFlowAnimated:completion:");
    if (signedOutFlow &&
        [signedOutFlow respondsToSelector:completeSelector]) {
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(
            signedOutFlow, completeSelector, NO,
            [presentChallenge copy]);
    } else {
        presentChallenge();
    }
    return YES;
}

@interface BHTCompatibilityLoginViewController
    : UIViewController <UITextFieldDelegate>
@property(nonatomic, strong) UITextField* usernameField;
@property(nonatomic, strong) UITextField* passwordField;
@property(nonatomic, strong) UIButton* signInButton;
@property(nonatomic, strong) UIActivityIndicatorView* activity;
@property(nonatomic, strong) UILabel* statusLabel;
@property(nonatomic, strong)
    BHTCompatibilityMetricsCollector* metricsCollector;
@property(nonatomic) BOOL cancelled;
@property(nonatomic) BOOL requestStarted;
@end

@implementation BHTCompatibilityLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title =
        BHTCompatibilityLocalized(@"COMPATIBILITY_SIGN_IN_TITLE");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                 target:self
                                 action:@selector(cancelTapped)];

    UILabel* heading = [UILabel new];
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    heading.text =
        BHTCompatibilityLocalized(@"COMPATIBILITY_SIGN_IN_HEADING");
    heading.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    heading.adjustsFontForContentSizeCategory = YES;
    heading.numberOfLines = 0;

    UILabel* detail = [UILabel new];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.text =
        BHTCompatibilityLocalized(@"COMPATIBILITY_SIGN_IN_DETAIL");
    detail.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    detail.textColor = UIColor.secondaryLabelColor;
    detail.adjustsFontForContentSizeCategory = YES;
    detail.numberOfLines = 0;

    self.usernameField = [UITextField new];
    self.usernameField.translatesAutoresizingMaskIntoConstraints = NO;
    self.usernameField.placeholder =
        BHTCompatibilityLocalized(
            @"COMPATIBILITY_SIGN_IN_USERNAME_PLACEHOLDER");
    self.usernameField.textContentType = UITextContentTypeUsername;
    self.usernameField.autocapitalizationType =
        UITextAutocapitalizationTypeNone;
    self.usernameField.autocorrectionType =
        UITextAutocorrectionTypeNo;
    self.usernameField.returnKeyType = UIReturnKeyNext;
    self.usernameField.delegate = self;
    self.usernameField.borderStyle = UITextBorderStyleRoundedRect;

    self.passwordField = [UITextField new];
    self.passwordField.translatesAutoresizingMaskIntoConstraints = NO;
    self.passwordField.placeholder =
        BHTCompatibilityLocalized(
            @"COMPATIBILITY_SIGN_IN_PASSWORD_PLACEHOLDER");
    self.passwordField.textContentType = UITextContentTypePassword;
    self.passwordField.secureTextEntry = YES;
    self.passwordField.returnKeyType = UIReturnKeyGo;
    self.passwordField.delegate = self;
    self.passwordField.borderStyle = UITextBorderStyleRoundedRect;

    self.signInButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.signInButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.signInButton
        setTitle:BHTCompatibilityLocalized(
                     @"COMPATIBILITY_SIGN_IN_ACTION")
        forState:UIControlStateNormal];
    self.signInButton.titleLabel.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.signInButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.signInButton.backgroundColor = UIColor.systemBlueColor;
    [self.signInButton setTitleColor:UIColor.whiteColor
                           forState:UIControlStateNormal];
    self.signInButton.layer.cornerRadius = 12.0;
    [self.signInButton addTarget:self
                          action:@selector(signInTapped)
                forControlEvents:UIControlEventTouchUpInside];

    self.activity =
        [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:
                UIActivityIndicatorViewStyleMedium];
    self.activity.translatesAutoresizingMaskIntoConstraints = NO;
    self.activity.hidesWhenStopped = YES;

    self.statusLabel = [UILabel new];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.adjustsFontForContentSizeCategory = YES;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;

    UILabel* privacy = [UILabel new];
    privacy.translatesAutoresizingMaskIntoConstraints = NO;
    privacy.text =
        BHTCompatibilityLocalized(@"COMPATIBILITY_SIGN_IN_PRIVACY");
    privacy.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    privacy.textColor = UIColor.tertiaryLabelColor;
    privacy.adjustsFontForContentSizeCategory = YES;
    privacy.numberOfLines = 0;
    privacy.textAlignment = NSTextAlignmentCenter;

    UIStackView* stack = [[UIStackView alloc]
        initWithArrangedSubviews:@[
            heading, detail, self.usernameField,
            self.passwordField, self.signInButton,
            self.activity, self.statusLabel, privacy
        ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14.0;
    [stack setCustomSpacing:24.0 afterView:detail];
    [stack setCustomSpacing:20.0
                 afterView:self.passwordField];
    [self.view addSubview:stack];

    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor
            constraintEqualToAnchor:safe.leadingAnchor
                           constant:24.0],
        [stack.trailingAnchor
            constraintEqualToAnchor:safe.trailingAnchor
                           constant:-24.0],
        [stack.topAnchor
            constraintGreaterThanOrEqualToAnchor:safe.topAnchor
                                        constant:24.0],
        [stack.centerYAnchor
            constraintEqualToAnchor:safe.centerYAnchor
                           constant:-20.0],
        [self.usernameField.heightAnchor constraintEqualToConstant:48.0],
        [self.passwordField.heightAnchor constraintEqualToConstant:48.0],
        [self.signInButton.heightAnchor constraintEqualToConstant:50.0],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.usernameField becomeFirstResponder];
}

- (void)cancelTapped {
    if (self.requestStarted) return;
    self.cancelled = YES;
    [self.metricsCollector cancel];
    self.metricsCollector = nil;
    self.passwordField.text = @"";
    [self.view endEditing:YES];
    UIViewController* modal = self.navigationController ?: self;
    [modal dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField {
    if (textField == self.usernameField) {
        [self.passwordField becomeFirstResponder];
    } else {
        [self signInTapped];
    }
    return YES;
}

- (void)setBusy:(BOOL)busy status:(NSString*)status {
    self.usernameField.enabled = !busy;
    self.passwordField.enabled = !busy;
    self.signInButton.enabled = !busy;
    self.signInButton.alpha = busy ? 0.55 : 1.0;
    self.navigationItem.leftBarButtonItem.enabled =
        !self.requestStarted;
    if (busy) {
        [self.activity startAnimating];
    } else {
        [self.activity stopAnimating];
    }
    self.statusLabel.textColor =
        busy ? UIColor.secondaryLabelColor : UIColor.systemRedColor;
    self.statusLabel.text = status ?: @"";
}

- (NSString*)messageForFailureCategory:(NSString*)category {
    if ([category isEqualToString:@"unsupported_version"]) {
        return BHTCompatibilityLocalized(
            @"COMPATIBILITY_SIGN_IN_VERSION_ERROR");
    }
    if ([category isEqualToString:@"missing_runtime"]) {
        return BHTCompatibilityLocalized(
            @"COMPATIBILITY_SIGN_IN_RUNTIME_ERROR");
    }
    if ([category isEqualToString:@"authentication_rejected"]) {
        return BHTCompatibilityLocalized(
            @"COMPATIBILITY_SIGN_IN_REJECTED_ERROR");
    }
    return BHTCompatibilityLocalized(
        @"COMPATIBILITY_SIGN_IN_GENERIC_ERROR");
}

- (void)finishWithSuccess:
            (BOOL)success
          failureCategory:(NSString*)failureCategory {
    if (success) {
        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventAuthenticated,
            @"completed", nil);
        self.passwordField.text = @"";
        UIViewController* modal =
            self.navigationController ?: self;
        if (modal.presentingViewController) {
            [modal dismissViewControllerAnimated:YES
                                      completion:nil];
        }
        return;
    }

    NSString* category =
        failureCategory.length > 0
            ? failureCategory
            : @"unknown";
    BHTCompatibilityRecord(
        BHTCompatibilityLoginEventFailed,
        @"failed", category);
    self.requestStarted = NO;
    [self setBusy:NO
           status:[self messageForFailureCategory:category]];
}

- (void)handlePasswordResponse:
            (BOOL)success
                        response:(id)response
                           error:(__unused id)error
                fallbackUsername:(NSString*)fallbackUsername {
    if (!success || !response) {
        [self finishWithSuccess:NO
               failureCategory:@"authentication_rejected"];
        return;
    }

    NSString* token =
        BHTSendObject(response, NSSelectorFromString(@"token"));
    NSString* secret =
        BHTSendObject(response, NSSelectorFromString(@"tokenSecret"));
    NSString* screenName =
        BHTSendObject(response, NSSelectorFromString(@"screenName"));
    if (screenName.length == 0) {
        screenName =
            BHTSendObject(response, NSSelectorFromString(@"username"));
    }
    uint64_t userID = BHTSendUnsignedValue(
        response, NSSelectorFromString(@"userId"));

    if (token.length > 0 && secret.length > 0) {
        BOOL registered = NO;
        id account = nil;
        @try {
            account = BHTBuildNativeAccount(
                token, secret,
                screenName.length > 0
                    ? screenName
                    : fallbackUsername,
                userID);
            registered = BHTRegisterNativeAccount(account);
        } @catch (__unused NSException* exception) {
            registered = NO;
        }
        if (!registered) {
            [self
                finishWithSuccess:NO
                 failureCategory:@"account_registration_failed"];
            return;
        }

        self.passwordField.text = @"";
        BHTCompleteSignedOutFlowAndSwitchAccount(
            account, self,
            ^(BOOL switched, NSString* switchFailure) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self
                        finishWithSuccess:switched
                         failureCategory:switchFailure];
                });
            });
        return;
    }

    id requestID = BHTSendObject(
        response,
        NSSelectorFromString(@"loginVerificationRequestId"));
    if (requestID) {
        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventChallengeRequired,
            @"challenge_required", nil);
        __weak typeof(self) weakSelf = self;
        BOOL handled = NO;
        @try {
            handled = BHTPresentNativeLoginChallenge(
                response, fallbackUsername,
                ^(BOOL challengeSuccess,
                  NSString* challengeFailure) {
                    dispatch_async(
                        dispatch_get_main_queue(), ^{
                            [weakSelf
                                finishWithSuccess:challengeSuccess
                                 failureCategory:challengeFailure];
                        });
                });
        } @catch (__unused NSException* exception) {
            handled = YES;
            [self finishWithSuccess:NO
                   failureCategory:@"challenge_exception"];
        }
        if (handled) return;
    }

    [self finishWithSuccess:NO
           failureCategory:@"unsupported_response"];
}

- (void)startPasswordCommandForUsername:
            (NSString*)username
                                 password:(NSString*)password
                                  metrics:(NSString*)metrics {
    if (self.cancelled) return;
    self.requestStarted = YES;
    self.navigationItem.leftBarButtonItem.enabled = NO;
    __weak typeof(self) weakSelf = self;
    void (^completion)(BOOL, id, id) =
        ^(BOOL success, id response, id error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                BHTCompatibilityLoginViewController* strongSelf =
                    weakSelf;
                if (!strongSelf || strongSelf.cancelled) return;
                @try {
                    [strongSelf
                        handlePasswordResponse:success
                                      response:response
                                         error:error
                              fallbackUsername:username];
                } @catch (__unused NSException* exception) {
                    [strongSelf
                        finishWithSuccess:NO
                         failureCategory:@"response_exception"];
                }
            });
        };

    id command = nil;
    @try {
        command = BHTCreatePasswordCommand(
            username, password, metrics, completion);
        if (!command || !BHTStartPasswordCommand(command)) {
            self.requestStarted = NO;
            [self finishWithSuccess:NO
                   failureCategory:@"command_start_failed"];
            return;
        }
    } @catch (__unused NSException* exception) {
        self.requestStarted = NO;
        [self finishWithSuccess:NO
               failureCategory:@"command_exception"];
        return;
    }
    BHTCompatibilityRecord(
        BHTCompatibilityLoginEventCommandStarted,
        @"command_started", nil);
    self.statusLabel.text =
        BHTCompatibilityLocalized(
            @"COMPATIBILITY_SIGN_IN_CONTACTING_X");
}

- (void)signInTapped {
    if (self.cancelled || self.requestStarted ||
        self.metricsCollector) {
        return;
    }
    if (!BHTCompatibilityVersionIsSupported()) {
        [self finishWithSuccess:NO
               failureCategory:@"unsupported_version"];
        return;
    }
    if (!BHTCompatibilityRuntimeIsAvailable()) {
        [self finishWithSuccess:NO
               failureCategory:@"missing_runtime"];
        return;
    }

    NSString* username = [self.usernameField.text
        stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString* password = [self.passwordField.text copy];
    if (username.length == 0 || password.length == 0) {
        [self setBusy:NO
               status:BHTCompatibilityLocalized(
                          @"COMPATIBILITY_SIGN_IN_REQUIRED_ERROR")];
        return;
    }

    BHTCompatibilityRecord(
        BHTCompatibilityLoginEventAttempted,
        @"preparing_metrics", nil);
    self.passwordField.text = @"";
    [self.view endEditing:YES];
    [self setBusy:YES
           status:BHTCompatibilityLocalized(
                      @"COMPATIBILITY_SIGN_IN_PREPARING")];

    self.metricsCollector =
        [BHTCompatibilityMetricsCollector new];
    __weak typeof(self) weakSelf = self;
    [self.metricsCollector
        startWithCompletion:^(NSString* metrics) {
            BHTCompatibilityLoginViewController* strongSelf =
                weakSelf;
            if (!strongSelf || strongSelf.cancelled) return;
            strongSelf.metricsCollector = nil;
            [strongSelf
                startPasswordCommandForUsername:username
                                       password:password
                                        metrics:metrics];
        }];
}

@end

void BHTPresentCompatibilitySignIn(
    UIViewController* presenter) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController* source =
            BHTTopViewController(presenter) ?:
            BHTActiveViewController();
        if (!source) return;

        if (!BHTCompatibilityRuntimeIsAvailable()) {
            NSString* message =
                BHTCompatibilityVersionIsSupported()
                    ? BHTCompatibilityLocalized(
                          @"COMPATIBILITY_SIGN_IN_RUNTIME_ERROR")
                    : BHTCompatibilityLocalized(
                          @"COMPATIBILITY_SIGN_IN_VERSION_ERROR");
            UIAlertController* alert = [UIAlertController
                alertControllerWithTitle:
                    BHTCompatibilityLocalized(
                        @"COMPATIBILITY_SIGN_IN_TITLE")
                                 message:message
                          preferredStyle:
                              UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction
                actionWithTitle:
                    BHTCompatibilityLocalized(
                        @"COMPATIBILITY_SIGN_IN_OK")
                          style:UIAlertActionStyleDefault
                        handler:nil]];
            [source presentViewController:alert
                                 animated:YES
                               completion:nil];
            return;
        }

        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventPresented,
            @"presented", @"none");
        BHTCompatibilityLoginViewController* login =
            [BHTCompatibilityLoginViewController new];
        UINavigationController* navigation =
            [[UINavigationController alloc]
                initWithRootViewController:login];
        navigation.modalPresentationStyle =
            UIModalPresentationFormSheet;
        navigation.preferredContentSize =
            CGSizeMake(520.0, 620.0);
        [source presentViewController:navigation
                            animated:YES
                          completion:nil];
    });
}

@interface BHTCompatibilityEntryTarget : NSObject
@property(nonatomic, weak) UIViewController* presenter;
- (void)openCompatibilitySignIn;
@end

@implementation BHTCompatibilityEntryTarget
- (void)openCompatibilitySignIn {
    BHTPresentCompatibilitySignIn(self.presenter);
}
@end

void BHTInstallCompatibilitySignInEntry(
    UIViewController* onboardingController) {
    if (!onboardingController ||
        !BHTCompatibilityRuntimeIsAvailable()) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (objc_getAssociatedObject(
                onboardingController,
                &BHTCompatibilityEntryButtonKey)) {
            return;
        }

        UIView* hostView = onboardingController.view;
        if (!hostView) return;

        BHTCompatibilityEntryTarget* target =
            [BHTCompatibilityEntryTarget new];
        target.presenter = onboardingController;

        UIButton* button =
            [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button
            setTitle:BHTCompatibilityLocalized(
                         @"COMPATIBILITY_SIGN_IN_TITLE")
            forState:UIControlStateNormal];
        button.titleLabel.font =
            [UIFont preferredFontForTextStyle:
                        UIFontTextStyleFootnote];
        button.titleLabel.adjustsFontForContentSizeCategory = YES;
        button.backgroundColor =
            [UIColor.secondarySystemBackgroundColor
                colorWithAlphaComponent:0.92];
        button.layer.cornerRadius = 15.0;
        button.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        button.layer.borderColor =
            UIColor.separatorColor.CGColor;
        button.contentEdgeInsets =
            UIEdgeInsetsMake(7.0, 12.0, 7.0, 12.0);
        button.accessibilityIdentifier =
            @"NeoFreeBird.CompatibilitySignIn";
        button.layer.zPosition = CGFLOAT_MAX;
        [button addTarget:target
                   action:@selector(openCompatibilitySignIn)
         forControlEvents:UIControlEventTouchUpInside];
        [hostView addSubview:button];

        [NSLayoutConstraint activateConstraints:@[
            [button.topAnchor
                constraintEqualToAnchor:
                    hostView.safeAreaLayoutGuide.topAnchor
                               constant:10.0],
            [button.trailingAnchor
                constraintEqualToAnchor:
                    hostView.safeAreaLayoutGuide.trailingAnchor
                               constant:-12.0],
        ]];
        [hostView bringSubviewToFront:button];

        objc_setAssociatedObject(
            onboardingController,
            &BHTCompatibilityEntryButtonKey, button,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            onboardingController,
            &BHTCompatibilityEntryTargetKey, target,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

NSDictionary<NSString*, id*>*
BHTCompatibilitySignInDiagnosticSnapshot(void) {
    NSArray<NSString*>* names = @[
        @"presented",
        @"attempted",
        @"metricsResolved",
        @"metricsTimedOut",
        @"commandStarted",
        @"authenticated",
        @"challengeRequired",
        @"challengePresented",
        @"accountRegistered",
        @"failed",
    ];
    NSMutableDictionary* counters =
        [NSMutableDictionary dictionaryWithCapacity:names.count];
    [names enumerateObjectsUsingBlock:^(
               NSString* name, NSUInteger index, BOOL* stop) {
        counters[name] =
            @(atomic_load_explicit(
                &BHTCompatibilityLoginCounters[index],
                memory_order_relaxed));
    }];

    NSString* lastStage;
    NSString* lastFailure;
    @synchronized(BHTCompatibilityLoginLock()) {
        lastStage = [BHTCompatibilityLoginLastStage copy] ?: @"idle";
        lastFailure =
            [BHTCompatibilityLoginLastFailure copy] ?: @"none";
    }
    return @{
        @"targetAppVersion": BHTCompatibilityTargetVersion,
        @"appVersionSupported":
            @(BHTCompatibilityVersionIsSupported()),
        @"runtimeAvailable":
            @(BHTCompatibilityRuntimeIsAvailable()),
        @"lastStage": lastStage,
        @"lastFailureCategory": lastFailure,
        @"counters": [counters copy],
        @"nativeSignInRemainsDefault": @YES,
        @"credentialPersistence": @"x_native_account_storage",
        @"attestationOverridesIncluded": @NO,
        @"credentialBackupIncluded": @NO,
    };
}
