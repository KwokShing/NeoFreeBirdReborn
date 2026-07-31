#import "Reply/BHTWebReplyFallback.h"

#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "ThemeColor/Palette.h"

#import <WebKit/WebKit.h>
#import <limits.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>

typedef NS_ENUM(NSUInteger, BHTWebReplyDiagnosticEvent) {
    BHTWebReplyDiagnosticRouteAttempt = 0,
    BHTWebReplyDiagnosticDisabled,
    BHTWebReplyDiagnosticMissingOrInvalidStatus,
    BHTWebReplyDiagnosticOffMainThread,
    BHTWebReplyDiagnosticPresentationUnavailable,
    BHTWebReplyDiagnosticPresented,
    BHTWebReplyDiagnosticAlreadyPresented,
    BHTWebReplyDiagnosticTransitionPendingBlocked,
    BHTWebReplyDiagnosticNavigationStarted,
    BHTWebReplyDiagnosticNavigationCommitted,
    BHTWebReplyDiagnosticNavigationFinished,
    BHTWebReplyDiagnosticLoaderHiddenOnCommit,
    BHTWebReplyDiagnosticNavigationFailed,
    BHTWebReplyDiagnosticNavigationFailedProvisional,
    BHTWebReplyDiagnosticNavigationFailedCommitted,
    BHTWebReplyDiagnosticFailureOfflineOrCannotConnect,
    BHTWebReplyDiagnosticFailureDNS,
    BHTWebReplyDiagnosticFailureTLS,
    BHTWebReplyDiagnosticFailureTimedOut,
    BHTWebReplyDiagnosticFailureUnsupportedURL,
    BHTWebReplyDiagnosticFailureNetworkOther,
    BHTWebReplyDiagnosticFailureWebKitOther,
    BHTWebReplyDiagnosticFailureOther,
    BHTWebReplyDiagnosticNavigationCancellationIgnored,
    BHTWebReplyDiagnosticPolicyInterruptionIgnored,
    BHTWebReplyDiagnosticAppHandoffIgnored,
    BHTWebReplyDiagnosticAutomaticPopupIgnored,
    BHTWebReplyDiagnosticBlankPopupIgnored,
    BHTWebReplyDiagnosticBlankMainFramePrevented,
    BHTWebReplyDiagnosticBlankMainFrameFinished,
    BHTWebReplyDiagnosticUserPopupRerouted,
    BHTWebReplyDiagnosticMainFrameHTTPClientError,
    BHTWebReplyDiagnosticMainFrameHTTPServerError,
    BHTWebReplyDiagnosticMainFrameEmptyResponse,
    BHTWebReplyDiagnosticMainFrameUnsupportedMIMEType,
    BHTWebReplyDiagnosticLoadWatchdogExpired,
    BHTWebReplyDiagnosticNavigationBlocked,
    BHTWebReplyDiagnosticNavigationBlockedUserInitiated,
    BHTWebReplyDiagnosticNavigationBlockedAutomatic,
    BHTWebReplyDiagnosticWebProcessTerminated,
    BHTWebReplyDiagnosticSignInSetupAttempt,
    BHTWebReplyDiagnosticSignInSetupPresented,
    BHTWebReplyDiagnosticSignInSetupUnavailable,
    BHTWebReplyDiagnosticSignInLandingRecognized,
    BHTWebReplyDiagnosticSetupCompletedManually,
    BHTWebReplyDiagnosticAccountManagerCompleted,
    BHTWebReplyDiagnosticNativeAccountContextAvailable,
    BHTWebReplyDiagnosticNativeAccountContextUnavailable,
    BHTWebReplyDiagnosticNativeAccountChanged,
    BHTWebReplyDiagnosticAccountBoundaryWarningShown,
    BHTWebReplyDiagnosticAccountBoundaryContinued,
    BHTWebReplyDiagnosticAccountBoundaryReviewOpened,
    BHTWebReplyDiagnosticAccountBoundaryCancelled,
    BHTWebReplyDiagnosticManageWebAccountOpened,
    BHTWebReplyDiagnosticWebViewCloseReceived,
    BHTWebReplyDiagnosticClosed,
    BHTWebReplyDiagnosticIgnoredNavigationBeforeCommit,
    BHTWebReplyDiagnosticAccountManagerFallbackStarted,
    BHTWebReplyDiagnosticAccountManagerFallbackCommitted,
    BHTWebReplyDiagnosticAccountManagerFallbackFailed,
    BHTWebReplyDiagnosticPageNavigationWatchdogArmed,
    BHTWebReplyDiagnosticEventCount,
};

static atomic_ulong
    BHTWebReplyDiagnosticCounters[BHTWebReplyDiagnosticEventCount];
static NSString* const BHTWebReplyDiagnosticNames[] = {
    @"routeAttempt",
    @"disabled",
    @"missingOrInvalidStatus",
    @"offMainThread",
    @"presentationUnavailable",
    @"presented",
    @"alreadyPresented",
    @"transitionPendingBlocked",
    @"navigationStarted",
    @"navigationCommitted",
    @"navigationFinished",
    @"loaderHiddenOnCommit",
    @"navigationFailed",
    @"navigationFailedProvisional",
    @"navigationFailedCommitted",
    @"failureOfflineOrCannotConnect",
    @"failureDNS",
    @"failureTLS",
    @"failureTimedOut",
    @"failureUnsupportedURL",
    @"failureNetworkOther",
    @"failureWebKitOther",
    @"failureOther",
    @"navigationCancellationIgnored",
    @"policyInterruptionIgnored",
    @"appHandoffIgnored",
    @"automaticPopupIgnored",
    @"blankPopupIgnored",
    @"blankMainFramePrevented",
    @"blankMainFrameFinished",
    @"userPopupRerouted",
    @"mainFrameHTTPClientError",
    @"mainFrameHTTPServerError",
    @"mainFrameEmptyResponse",
    @"mainFrameUnsupportedMIMEType",
    @"loadWatchdogExpired",
    @"navigationBlocked",
    @"navigationBlockedUserInitiated",
    @"navigationBlockedAutomatic",
    @"webProcessTerminated",
    @"signInSetupAttempt",
    @"signInSetupPresented",
    @"signInSetupUnavailable",
    @"signInLandingRecognized",
    @"setupCompletedManually",
    @"accountManagerCompleted",
    @"nativeAccountContextAvailable",
    @"nativeAccountContextUnavailable",
    @"nativeAccountChanged",
    @"accountBoundaryWarningShown",
    @"accountBoundaryContinued",
    @"accountBoundaryReviewOpened",
    @"accountBoundaryCancelled",
    @"manageWebAccountOpened",
    @"webViewCloseReceived",
    @"closed",
    @"ignoredNavigationBeforeCommit",
    @"accountManagerFallbackStarted",
    @"accountManagerFallbackCommitted",
    @"accountManagerFallbackFailed",
    @"pageNavigationWatchdogArmed",
};
_Static_assert(
    sizeof(BHTWebReplyDiagnosticNames) /
            sizeof(BHTWebReplyDiagnosticNames[0]) ==
        BHTWebReplyDiagnosticEventCount,
    "Every web reply diagnostic needs a fixed name");

static __weak UINavigationController*
    BHTActiveWebReplyNavigationController;
static __weak UIAlertController*
    BHTActiveWebReplyBoundaryAlert;
static __weak id BHTLastWebReplyNativeAccount;
static atomic_bool
    BHTWebReplyAccountBoundaryAcknowledged;
static atomic_bool BHTWebReplyTransitionPending;
static void* BHTWebReplyProgressObservationContext =
    &BHTWebReplyProgressObservationContext;
static void* BHTWebReplyURLObservationContext =
    &BHTWebReplyURLObservationContext;
// WebKit's public legacy frame-policy interruption is error 102. Keep a
// local name so the tweak also builds with SDKs that omit its deprecated
// WebKitErrorFrameLoadInterruptedByPolicyChange declaration.
static NSInteger const
    BHTWebKitFrameLoadInterruptedByPolicyChangeErrorCode = 102;
static NSString* const BHTWebReplyAccountLabelDefaultsKey =
    @"bht_web_reply_account_label";

NSNotificationName const
    BHTWebReplyAccountLabelDidChangeNotification =
        @"BHTWebReplyAccountLabelDidChangeNotification";

typedef NS_ENUM(NSUInteger, BHTWebReplyScreenMode) {
    BHTWebReplyScreenModeReply = 0,
    BHTWebReplyScreenModeSignInSetup,
    BHTWebReplyScreenModeAccountManagement,
};

static void BHTRecordWebReplyDiagnostic(
    BHTWebReplyDiagnosticEvent event) {
    if (event >= BHTWebReplyDiagnosticEventCount) return;
    atomic_fetch_add_explicit(
        &BHTWebReplyDiagnosticCounters[event], 1,
        memory_order_relaxed);
}

static void BHTSetWebReplyTransitionPending(BOOL pending) {
    atomic_store_explicit(
        &BHTWebReplyTransitionPending, pending,
        memory_order_relaxed);
}

static NSString* BHTWebReplyLocalized(NSString* key) {
    return [[BHTBundle sharedBundle] localizedStringForKey:key];
}

static NSString* BHTNormalizedWebReplyAccountLabel(
    NSString* value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString* handle = [value
        stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([handle hasPrefix:@"@"]) {
        handle = [handle substringFromIndex:1];
    }
    if (handle.length == 0 || handle.length > 15) return nil;

    static NSCharacterSet* invalidHandleCharacters;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSCharacterSet* allowed =
            [NSCharacterSet
                characterSetWithCharactersInString:
                    @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"];
        invalidHandleCharacters = allowed.invertedSet;
    });
    if ([handle rangeOfCharacterFromSet:
                    invalidHandleCharacters].location !=
        NSNotFound) {
        return nil;
    }
    return [@"@" stringByAppendingString:handle];
}

NSString* BHTWebReplyAccountLabel(void) {
    NSString* stored = [NSUserDefaults.standardUserDefaults
        stringForKey:BHTWebReplyAccountLabelDefaultsKey];
    return BHTNormalizedWebReplyAccountLabel(stored);
}

static void BHTSetWebReplyAccountLabel(NSString* label) {
    NSUserDefaults* defaults =
        NSUserDefaults.standardUserDefaults;
    NSString* normalized =
        BHTNormalizedWebReplyAccountLabel(label);
    NSString* previous = BHTWebReplyAccountLabel();
    if (normalized.length > 0) {
        [defaults setObject:normalized
                    forKey:BHTWebReplyAccountLabelDefaultsKey];
    } else {
        [defaults
            removeObjectForKey:
                BHTWebReplyAccountLabelDefaultsKey];
    }
    if ((previous == nil && normalized == nil) ||
        [previous isEqualToString:normalized]) {
        return;
    }
    [NSNotificationCenter.defaultCenter
        postNotificationName:
            BHTWebReplyAccountLabelDidChangeNotification
                      object:nil];
}

static const char* BHTSkipObjectiveCTypeQualifiers(
    const char* type) {
    if (!type) return "";
    while (*type == 'r' || *type == 'n' || *type == 'N' ||
           *type == 'o' || *type == 'O' || *type == 'R' ||
           *type == 'V') {
        type++;
    }
    return type;
}

static Method BHTZeroArgumentMethod(id object, SEL selector) {
    if (!object || !selector) return NULL;
    Method method =
        class_getInstanceMethod(object_getClass(object), selector);
    return method && method_getNumberOfArguments(method) == 2
               ? method
               : NULL;
}

static BOOL BHTMethodReturnsObject(Method method) {
    if (!method) return NO;
    char returnType[16] = {0};
    method_getReturnType(
        method, returnType, sizeof(returnType));
    return *BHTSkipObjectiveCTypeQualifiers(returnType) == '@';
}

static BOOL BHTReadPositiveStatusIdentifier(
    id object, long long* identifier) {
    if (!object || !identifier) return NO;
    SEL selector = NSSelectorFromString(@"statusID");
    Method method = BHTZeroArgumentMethod(object, selector);
    if (!method) return NO;

    char returnType[16] = {0};
    method_getReturnType(
        method, returnType, sizeof(returnType));
    const char* type =
        BHTSkipObjectiveCTypeQualifiers(returnType);
    long long value = 0;
    @try {
        if (*type == 'q') {
            value =
                ((long long (*)(id, SEL))objc_msgSend)(
                    object, selector);
        } else if (*type == 'Q') {
            unsigned long long unsignedValue =
                ((unsigned long long (*)(id, SEL))objc_msgSend)(
                    object, selector);
            if (unsignedValue > LLONG_MAX) return NO;
            value = (long long)unsignedValue;
        } else {
            return NO;
        }
    } @catch (__unused NSException* exception) {
        return NO;
    }

    if (value <= 0) return NO;
    *identifier = value;
    return YES;
}

static BOOL BHTObjectLooksLikeStatus(id object) {
    if (!object) return NO;
    Class statusClass =
        NSClassFromString(@"TFNTwitterStatus");
    if (statusClass &&
        [object isKindOfClass:statusClass]) {
        return YES;
    }

    Method usernameGetter = BHTZeroArgumentMethod(
        object, NSSelectorFromString(@"fromUserName"));
    Method identifierGetter = BHTZeroArgumentMethod(
        object, NSSelectorFromString(@"statusID"));
    return BHTMethodReturnsObject(usernameGetter) &&
           identifierGetter != NULL;
}

static id BHTInvokeObjectGetter(id object, SEL selector) {
    Method method = BHTZeroArgumentMethod(object, selector);
    if (!BHTMethodReturnsObject(method)) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(
            object, selector);
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

static BOOL BHTResolveStatusIdentifier(
    id sourceObject, long long* identifier) {
    if (!sourceObject || !identifier) return NO;

    NSMutableArray* objects =
        [NSMutableArray arrayWithObject:sourceObject];
    NSMutableArray<NSNumber*>* depths =
        [NSMutableArray arrayWithObject:@0];
    NSHashTable* visited = [NSHashTable
        hashTableWithOptions:
            NSPointerFunctionsStrongMemory |
            NSPointerFunctionsObjectPointerPersonality];
    SEL relatedSelectors[] = {
        NSSelectorFromString(@"status"),
        NSSelectorFromString(@"tweet"),
        NSSelectorFromString(@"representedStatus"),
        NSSelectorFromString(@"retweetedStatus"),
        NSSelectorFromString(@"statusViewModel"),
        NSSelectorFromString(@"viewModel"),
    };
    const NSUInteger selectorCount =
        sizeof(relatedSelectors) / sizeof(relatedSelectors[0]);
    NSUInteger cursor = 0;
    const NSUInteger maximumObjects = 24;
    const NSUInteger maximumDepth = 4;

    while (cursor < objects.count &&
           cursor < maximumObjects) {
        id object = objects[cursor];
        NSUInteger depth =
            [depths[cursor] unsignedIntegerValue];
        cursor++;
        if (!object || [visited containsObject:object]) {
            continue;
        }
        [visited addObject:object];

        if (BHTObjectLooksLikeStatus(object) &&
            BHTReadPositiveStatusIdentifier(
                object, identifier)) {
            return YES;
        }
        if (depth >= maximumDepth) continue;

        for (NSUInteger index = 0;
             index < selectorCount; index++) {
            id related =
                BHTInvokeObjectGetter(
                    object, relatedSelectors[index]);
            if (!related ||
                [visited containsObject:related]) {
                continue;
            }
            [objects addObject:related];
            [depths addObject:@(depth + 1)];
            if (objects.count >= maximumObjects) break;
        }
    }
    return NO;
}

static NSURL* BHTWebReplyURL(long long identifier) {
    NSURLComponents* components =
        [NSURLComponents
            componentsWithString:
                @"https://x.com/intent/tweet"];
    components.queryItems = @[
        [NSURLQueryItem
            queryItemWithName:@"in_reply_to"
                        value:[NSString
                                  stringWithFormat:
                                      @"%lld", identifier]]
    ];
    NSURL* URL = components.URL;
    return [URL.scheme isEqualToString:@"https"] &&
                   [URL.host isEqualToString:@"x.com"]
               ? URL
               : nil;
}

static NSURL* BHTWebReplySignInURL(void) {
    NSURLComponents* components =
        [NSURLComponents
            componentsWithString:
                @"https://x.com/i/flow/login"];
    components.queryItems = @[
        [NSURLQueryItem
            queryItemWithName:@"redirect_after_login"
                        value:@"/home"]
    ];
    NSURL* URL = components.URL;
    return [URL.scheme isEqualToString:@"https"] &&
                   [URL.host isEqualToString:@"x.com"]
               ? URL
               : nil;
}

static NSURL* BHTWebReplyAccountURL(void) {
    // Direct /home loads are interrupted by WebKit policy changes on some
    // sideloaded X 12.9 installs. Enter through the same supported sign-in
    // flow that already succeeds for compatibility-reply setup.
    NSURL* URL = BHTWebReplySignInURL();
    return [URL.scheme isEqualToString:@"https"] &&
                   [URL.host isEqualToString:@"x.com"]
               ? URL
               : nil;
}

static NSURL* BHTWebReplyAccountFallbackURL(void) {
    // The official intent shell is the route users already confirmed loads
    // successfully. It contains no status identifier or draft and cannot post
    // without a visible user action.
    NSURL* URL =
        [NSURL URLWithString:@"https://x.com/intent/tweet"];
    return [URL.scheme isEqualToString:@"https"] &&
                   [URL.host isEqualToString:@"x.com"]
               ? URL
               : nil;
}

static BOOL BHTHostIsExactOrSubdomain(
    NSString* host, NSString* domain) {
    NSString* normalizedHost = host.lowercaseString;
    NSString* normalizedDomain = domain.lowercaseString;
    if (normalizedHost.length == 0 ||
        normalizedDomain.length == 0) {
        return NO;
    }
    return [normalizedHost isEqualToString:normalizedDomain] ||
           [normalizedHost
               hasSuffix:[@"." stringByAppendingString:
                                    normalizedDomain]];
}

static BOOL BHTWebReplyURLIsAboutBlank(NSURL* URL) {
    return [URL.scheme.lowercaseString
               isEqualToString:@"about"] &&
           [URL.absoluteString.lowercaseString
               isEqualToString:@"about:blank"];
}

static BOOL BHTWebReplyAllowsTopLevelURL(NSURL* URL) {
    if (!URL) return NO;
    if ([URL.scheme.lowercaseString isEqualToString:@"about"]) {
        return NO;
    }
    if (![URL.scheme.lowercaseString
            isEqualToString:@"https"]) {
        return NO;
    }

    NSString* host = URL.host.lowercaseString;
    return BHTHostIsExactOrSubdomain(host, @"x.com") ||
           BHTHostIsExactOrSubdomain(host, @"twitter.com") ||
           [host isEqualToString:@"accounts.google.com"] ||
           [host isEqualToString:@"appleid.apple.com"];
}

static BOOL BHTWebReplyURLIsSignedInLanding(NSURL* URL) {
    if (!URL ||
        ![URL.scheme.lowercaseString isEqualToString:@"https"]) {
        return NO;
    }
    NSString* host = URL.host.lowercaseString;
    if (!BHTHostIsExactOrSubdomain(host, @"x.com") &&
        !BHTHostIsExactOrSubdomain(host, @"twitter.com")) {
        return NO;
    }
    NSString* path = URL.path.lowercaseString;
    return [path isEqualToString:@"/home"] ||
           [path hasPrefix:@"/home/"];
}

static BOOL BHTWebReplyIsExpectedAppHandoffURL(
    NSURL* URL) {
    NSString* scheme = URL.scheme.lowercaseString;
    return [scheme isEqualToString:@"x"] ||
           [scheme isEqualToString:@"twitter"];
}

static BOOL BHTWebReplyNavigationIsUserInitiated(
    WKNavigationAction* navigationAction) {
    if (!navigationAction) return NO;
    switch (navigationAction.navigationType) {
        case WKNavigationTypeLinkActivated:
        case WKNavigationTypeFormSubmitted:
        case WKNavigationTypeFormResubmitted:
            return YES;
        default:
            return NO;
    }
}

static BOOL BHTWebReplyIsWebKitErrorDomain(
    NSString* domain) {
    return [domain isEqualToString:WKErrorDomain] ||
           [domain isEqualToString:@"WebKitErrorDomain"];
}

static BOOL BHTWebReplyShouldIgnoreNavigationError(
    NSError* error) {
    if (!error) return NO;
    if ([error.domain isEqualToString:NSURLErrorDomain] &&
        error.code == NSURLErrorCancelled) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticNavigationCancellationIgnored);
        return YES;
    }
    if (BHTWebReplyIsWebKitErrorDomain(error.domain) &&
        error.code ==
            BHTWebKitFrameLoadInterruptedByPolicyChangeErrorCode) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticPolicyInterruptionIgnored);
        return YES;
    }
    return NO;
}

static void BHTRecordWebReplyNavigationFailure(
    NSError* error, BOOL provisional) {
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticNavigationFailed);
    BHTRecordWebReplyDiagnostic(
        provisional
            ? BHTWebReplyDiagnosticNavigationFailedProvisional
            : BHTWebReplyDiagnosticNavigationFailedCommitted);

    BHTWebReplyDiagnosticEvent category =
        BHTWebReplyDiagnosticFailureOther;
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case NSURLErrorNotConnectedToInternet:
            case NSURLErrorCannotConnectToHost:
                category =
                    BHTWebReplyDiagnosticFailureOfflineOrCannotConnect;
                break;
            case NSURLErrorCannotFindHost:
            case NSURLErrorDNSLookupFailed:
                category = BHTWebReplyDiagnosticFailureDNS;
                break;
            case NSURLErrorSecureConnectionFailed:
            case NSURLErrorServerCertificateHasBadDate:
            case NSURLErrorServerCertificateUntrusted:
            case NSURLErrorServerCertificateHasUnknownRoot:
            case NSURLErrorServerCertificateNotYetValid:
            case NSURLErrorClientCertificateRejected:
            case NSURLErrorClientCertificateRequired:
                category = BHTWebReplyDiagnosticFailureTLS;
                break;
            case NSURLErrorTimedOut:
                category =
                    BHTWebReplyDiagnosticFailureTimedOut;
                break;
            case NSURLErrorUnsupportedURL:
                category =
                    BHTWebReplyDiagnosticFailureUnsupportedURL;
                break;
            default:
                category =
                    BHTWebReplyDiagnosticFailureNetworkOther;
                break;
        }
    } else if (BHTWebReplyIsWebKitErrorDomain(error.domain)) {
        category =
            BHTWebReplyDiagnosticFailureWebKitOther;
    }
    BHTRecordWebReplyDiagnostic(category);
}

@interface BHTWebReplyViewController
    : UIViewController <WKNavigationDelegate, WKUIDelegate,
                        UIAdaptivePresentationControllerDelegate>
@property(nonatomic, strong) NSURL* initialURL;
@property(nonatomic, copy) NSString* screenTitleKey;
@property(nonatomic, copy) NSString* loadFailureKey;
@property(nonatomic) BHTWebReplyScreenMode screenMode;
@property(nonatomic, strong) WKWebView* webView;
@property(nonatomic, strong) UIProgressView* progressView;
@property(nonatomic, strong) UIView* loadingView;
@property(nonatomic, strong) UIView* errorView;
@property(nonatomic, strong) UIView* setupReadyView;
@property(nonatomic, strong) UIBarButtonItem* doneItem;
@property(nonatomic, strong) UIBarButtonItem* moreItem;
@property(nonatomic, strong) UIBarButtonItem* accountLabelItem;
@property(nonatomic) BOOL observingProgress;
@property(nonatomic) BOOL observingURL;
@property(nonatomic) BOOL didRecordClose;
@property(nonatomic) BOOL blockedAlertVisible;
@property(nonatomic) BOOL hasVisibleCommittedContent;
@property(nonatomic, strong) WKNavigation*
    latestMainFrameNavigation;
@property(nonatomic, strong) WKNavigation*
    mainFrameProvisionalNavigationInFlight;
@property(nonatomic, strong) WKNavigation*
    explicitMainFrameNavigationAwaitingStart;
@property(nonatomic) BOOL setupReady;
@property(nonatomic) NSUInteger loadAttemptGeneration;
@property(nonatomic) BOOL loadAttemptComplete;
@property(nonatomic) BOOL accountManagerFallbackScheduled;
@property(nonatomic) BOOL accountManagerFallbackAttempted;
@property(nonatomic) BOOL accountManagerFallbackCommitted;
@property(nonatomic) BOOL accountManagerFallbackFailureRecorded;
@property(nonatomic, copy) dispatch_block_t doneCompletion;
@property(nonatomic) BOOL beginsReplyTransitionOnDone;
- (instancetype)initWithURL:(NSURL*)URL
                    titleKey:(NSString*)titleKey
              loadFailureKey:(NSString*)loadFailureKey
                        mode:(BHTWebReplyScreenMode)mode;
- (void)loadRequestWithWatchdog:(NSURLRequest*)request;
- (void)armLoadWatchdogForNavigation:
    (WKNavigation*)navigation;
- (void)scheduleUserPopupRequest:(NSURLRequest*)request;
- (void)showWebAccountManager;
- (void)editAccountLabel;
- (BOOL)scheduleAccountManagerFallbackIfNeeded;
- (void)recordAccountManagerFallbackFailureIfNeeded;
- (BOOL)settleMainFrameProvisionalNavigationForCallback:
    (WKNavigation*)navigation;
- (BOOL)finishMainFrameNavigationForCallback:
    (WKNavigation*)navigation;
@end

typedef void (^BHTWebReplyPresenterReadyAction)(
    UIViewController* presenter);

static void BHTPerformWhenWebReplyPresenterIsReady(
    UIViewController* presenter,
    NSUInteger retriesRemaining,
    BHTWebReplyPresenterReadyAction action,
    dispatch_block_t failure) {
    if (!action) return;
    __weak UIViewController* weakPresenter = presenter;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController* strongPresenter = weakPresenter;
        if (!strongPresenter) {
            BHTRecordWebReplyDiagnostic(
                BHTWebReplyDiagnosticPresentationUnavailable);
            if (failure) failure();
            return;
        }
        BOOL ready =
            strongPresenter.viewIfLoaded.window &&
            !strongPresenter.isBeingDismissed &&
            strongPresenter.presentedViewController == nil;
        if (ready) {
            action(strongPresenter);
            return;
        }
        if (retriesRemaining == 0) {
            BHTRecordWebReplyDiagnostic(
                BHTWebReplyDiagnosticPresentationUnavailable);
            if (failure) failure();
            return;
        }
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)(0.05 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                BHTPerformWhenWebReplyPresenterIsReady(
                    weakPresenter,
                    retriesRemaining - 1,
                    action,
                    failure);
            });
    });
}

@implementation BHTWebReplyViewController

- (instancetype)initWithURL:(NSURL*)URL
                    titleKey:(NSString*)titleKey
              loadFailureKey:(NSString*)loadFailureKey
                        mode:(BHTWebReplyScreenMode)mode {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _initialURL = URL;
        _screenTitleKey = [titleKey copy];
        _loadFailureKey = [loadFailureKey copy];
        _screenMode = mode;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title =
        BHTWebReplyLocalized(self.screenTitleKey);
    self.view.backgroundColor =
        [Palette currentBackgroundColor];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:
                UIBarButtonSystemItemClose
                                 target:self
                                 action:@selector(closeTapped)];
    self.doneItem = [[UIBarButtonItem alloc]
        initWithTitle:BHTWebReplyLocalized(@"WEB_REPLY_DONE")
                style:UIBarButtonItemStyleDone
               target:self
               action:@selector(doneTapped)];
    self.moreItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(moreTapped)];
    self.moreItem.accessibilityLabel =
        BHTWebReplyLocalized(@"WEB_REPLY_MORE");
    self.accountLabelItem = [[UIBarButtonItem alloc]
        initWithTitle:
            BHTWebReplyLocalized(
                @"WEB_REPLY_ACCOUNT_LABEL_BUTTON")
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(editAccountLabel)];
    self.accountLabelItem.accessibilityLabel =
        BHTWebReplyLocalized(@"WEB_REPLY_ACCOUNT_LABEL_ACTION");
    if (self.screenMode == BHTWebReplyScreenModeReply) {
        self.navigationItem.rightBarButtonItem = self.moreItem;
    } else if (
        self.screenMode ==
        BHTWebReplyScreenModeAccountManagement) {
        // Keep both the local label action and a Done escape hatch available
        // even if X interrupts navigation before the first page commits.
        self.navigationItem.rightBarButtonItems =
            @[self.doneItem, self.accountLabelItem];
    }

    WKWebViewConfiguration* configuration =
        [WKWebViewConfiguration new];
    configuration.websiteDataStore =
        WKWebsiteDataStore.defaultDataStore;
    configuration.allowsInlineMediaPlayback = YES;
    if (@available(iOS 13.0, *)) {
        configuration.defaultWebpagePreferences
            .preferredContentMode = WKContentModeMobile;
    }
    if (@available(iOS 14.0, *)) {
        configuration.defaultWebpagePreferences
            .allowsContentJavaScript = YES;
    }

    self.webView = [[WKWebView alloc]
        initWithFrame:CGRectZero
        configuration:configuration];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.allowsBackForwardNavigationGestures = YES;
    self.webView.backgroundColor =
        [Palette currentBackgroundColor];
    self.webView.opaque = NO;
    [self.view addSubview:self.webView];

    self.progressView = [[UIProgressView alloc]
        initWithProgressViewStyle:UIProgressViewStyleBar];
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressView.progressTintColor =
        [Palette customAccentColor] ?:
        UIColor.systemBlueColor;
    [self.view addSubview:self.progressView];

    self.loadingView = [self buildLoadingView];
    self.loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.loadingView];

    self.errorView = [self buildErrorView];
    self.errorView.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorView.hidden = YES;
    [self.view addSubview:self.errorView];

    self.setupReadyView = [self buildSetupReadyView];
    self.setupReadyView.translatesAutoresizingMaskIntoConstraints = NO;
    self.setupReadyView.hidden = YES;
    [self.view addSubview:self.setupReadyView];

    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.progressView.topAnchor
            constraintEqualToAnchor:safe.topAnchor],
        [self.progressView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.progressView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.topAnchor
            constraintEqualToAnchor:self.progressView.bottomAnchor],
        [self.webView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor
            constraintEqualToAnchor:self.view.bottomAnchor],
        [self.loadingView.topAnchor
            constraintEqualToAnchor:self.webView.topAnchor],
        [self.loadingView.leadingAnchor
            constraintEqualToAnchor:self.webView.leadingAnchor],
        [self.loadingView.trailingAnchor
            constraintEqualToAnchor:self.webView.trailingAnchor],
        [self.loadingView.bottomAnchor
            constraintEqualToAnchor:self.webView.bottomAnchor],
        [self.errorView.topAnchor
            constraintEqualToAnchor:self.webView.topAnchor],
        [self.errorView.leadingAnchor
            constraintEqualToAnchor:self.webView.leadingAnchor],
        [self.errorView.trailingAnchor
            constraintEqualToAnchor:self.webView.trailingAnchor],
        [self.errorView.bottomAnchor
            constraintEqualToAnchor:self.webView.bottomAnchor],
        [self.setupReadyView.topAnchor
            constraintEqualToAnchor:self.webView.topAnchor],
        [self.setupReadyView.leadingAnchor
            constraintEqualToAnchor:self.webView.leadingAnchor],
        [self.setupReadyView.trailingAnchor
            constraintEqualToAnchor:self.webView.trailingAnchor],
        [self.setupReadyView.bottomAnchor
            constraintEqualToAnchor:self.webView.bottomAnchor],
    ]];

    [self applyNativeTheme];
    [self.webView addObserver:self
                   forKeyPath:@"estimatedProgress"
                      options:NSKeyValueObservingOptionNew
                      context:
                          BHTWebReplyProgressObservationContext];
    self.observingProgress = YES;
    [self.webView addObserver:self
                   forKeyPath:@"URL"
                      options:NSKeyValueObservingOptionNew
                      context:BHTWebReplyURLObservationContext];
    self.observingURL = YES;
    [self retryLoad];
}

- (UIView*)buildLoadingView {
    UIView* container = [UIView new];
    container.backgroundColor =
        [Palette currentBackgroundColor];

    UIActivityIndicatorView* indicator =
        [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:
                UIActivityIndicatorViewStyleMedium];
    indicator.color =
        [Palette customAccentColor] ?:
        UIColor.systemBlueColor;
    [indicator startAnimating];

    UILabel* label = [UILabel new];
    label.text =
        BHTWebReplyLocalized(
            self.screenMode !=
                    BHTWebReplyScreenModeReply
                ? @"WEB_REPLY_SIGN_IN_LOADING"
                : @"WEB_REPLY_PREPARING");
    label.textColor =
        [Palette currentSecondaryTextColor];
    label.font =
        [UIFont preferredFontForTextStyle:
                    UIFontTextStyleBody];
    label.adjustsFontForContentSizeCategory = YES;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;

    UIStackView* stack = [[UIStackView alloc]
        initWithArrangedSubviews:@[indicator, label]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 14.0;
    [container addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor
            constraintGreaterThanOrEqualToAnchor:
                container.leadingAnchor
                                     constant:28.0],
        [stack.trailingAnchor
            constraintLessThanOrEqualToAnchor:
                container.trailingAnchor
                                  constant:-28.0],
        [stack.centerXAnchor
            constraintEqualToAnchor:container.centerXAnchor],
        [stack.centerYAnchor
            constraintEqualToAnchor:container.centerYAnchor],
    ]];
    return container;
}

- (UIView*)buildErrorView {
    UIView* container = [UIView new];
    container.backgroundColor =
        [Palette currentBackgroundColor];

    UIImageView* imageView = [[UIImageView alloc]
        initWithImage:[UIImage
                          systemImageNamed:
                              @"exclamationmark.arrow.triangle.2.circlepath"]];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.tintColor =
        [Palette currentSecondaryTextColor];
    imageView.contentMode = UIViewContentModeScaleAspectFit;

    UILabel* label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text =
        BHTWebReplyLocalized(self.loadFailureKey);
    label.textColor = [Palette currentTextColor];
    label.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.adjustsFontForContentSizeCategory = YES;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;

    UIButton* retry = [UIButton buttonWithType:UIButtonTypeSystem];
    retry.translatesAutoresizingMaskIntoConstraints = NO;
    [retry setTitle:
               BHTWebReplyLocalized(@"WEB_REPLY_RETRY")
          forState:UIControlStateNormal];
    retry.titleLabel.font =
        [UIFont preferredFontForTextStyle:
                    UIFontTextStyleHeadline];
    retry.titleLabel.adjustsFontForContentSizeCategory = YES;
    [retry addTarget:self
              action:@selector(retryLoad)
    forControlEvents:UIControlEventTouchUpInside];

    UIStackView* stack = [[UIStackView alloc]
        initWithArrangedSubviews:@[imageView, label, retry]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 16.0;
    [container addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [imageView.widthAnchor constraintEqualToConstant:36.0],
        [imageView.heightAnchor constraintEqualToConstant:36.0],
        [stack.leadingAnchor
            constraintGreaterThanOrEqualToAnchor:
                container.leadingAnchor
                                     constant:28.0],
        [stack.trailingAnchor
            constraintLessThanOrEqualToAnchor:
                container.trailingAnchor
                                  constant:-28.0],
        [stack.centerXAnchor
            constraintEqualToAnchor:container.centerXAnchor],
        [stack.centerYAnchor
            constraintEqualToAnchor:container.centerYAnchor],
    ]];
    return container;
}

- (UIView*)buildSetupReadyView {
    UIView* container = [UIView new];
    container.backgroundColor =
        [Palette currentBackgroundColor];

    UIImageView* imageView = [[UIImageView alloc]
        initWithImage:[UIImage
                          systemImageNamed:@"checkmark.circle.fill"]];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.tintColor =
        [Palette customAccentColor] ?:
        UIColor.systemBlueColor;
    imageView.contentMode = UIViewContentModeScaleAspectFit;

    UILabel* title = [UILabel new];
    title.text =
        BHTWebReplyLocalized(@"WEB_REPLY_SIGN_IN_READY_TITLE");
    title.textColor = [Palette currentTextColor];
    title.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    title.adjustsFontForContentSizeCategory = YES;
    title.textAlignment = NSTextAlignmentCenter;
    title.numberOfLines = 0;

    UILabel* detail = [UILabel new];
    detail.text =
        BHTWebReplyLocalized(@"WEB_REPLY_SIGN_IN_READY_DETAIL");
    detail.textColor =
        [Palette currentSecondaryTextColor];
    detail.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    detail.adjustsFontForContentSizeCategory = YES;
    detail.textAlignment = NSTextAlignmentCenter;
    detail.numberOfLines = 0;

    UIButton* done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:BHTWebReplyLocalized(@"WEB_REPLY_DONE")
          forState:UIControlStateNormal];
    done.titleLabel.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    done.titleLabel.adjustsFontForContentSizeCategory = YES;
    done.contentEdgeInsets =
        UIEdgeInsetsMake(12.0, 28.0, 12.0, 28.0);
    done.layer.cornerRadius = 20.0;
    done.backgroundColor =
        [Palette customAccentColor] ?:
        UIColor.systemBlueColor;
    [done setTitleColor:UIColor.whiteColor
               forState:UIControlStateNormal];
    [done addTarget:self
             action:@selector(doneTapped)
   forControlEvents:UIControlEventTouchUpInside];

    UIStackView* stack = [[UIStackView alloc]
        initWithArrangedSubviews:@[imageView, title, detail, done]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 16.0;
    [stack setCustomSpacing:24.0 afterView:detail];
    [container addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [imageView.widthAnchor constraintEqualToConstant:56.0],
        [imageView.heightAnchor constraintEqualToConstant:56.0],
        [stack.leadingAnchor
            constraintGreaterThanOrEqualToAnchor:
                container.leadingAnchor
                                     constant:32.0],
        [stack.trailingAnchor
            constraintLessThanOrEqualToAnchor:
                container.trailingAnchor
                                  constant:-32.0],
        [stack.centerXAnchor
            constraintEqualToAnchor:container.centerXAnchor],
        [stack.centerYAnchor
            constraintEqualToAnchor:container.centerYAnchor],
        [detail.widthAnchor
            constraintLessThanOrEqualToConstant:420.0],
    ]];
    return container;
}

- (void)applyNativeTheme {
    UIColor* accent =
        [Palette customAccentColor] ?:
        UIColor.systemBlueColor;
    UIColor* surface = [Palette currentSurfaceColor];
    UIColor* text = [Palette currentTextColor];
    self.navigationController.navigationBar.tintColor = accent;

    UINavigationBarAppearance* navigationAppearance =
        [UINavigationBarAppearance new];
    [navigationAppearance configureWithOpaqueBackground];
    navigationAppearance.backgroundColor = surface;
    navigationAppearance.titleTextAttributes =
        @{NSForegroundColorAttributeName: text};
    self.navigationController.navigationBar.standardAppearance =
        navigationAppearance;
    self.navigationController.navigationBar.scrollEdgeAppearance =
        navigationAppearance;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController
        setToolbarHidden:YES animated:NO];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed ||
        self.navigationController.isBeingDismissed ||
        !self.navigationController.presentingViewController) {
        [self recordCloseIfNeeded];
    }
}

- (void)dealloc {
    if (self.observingProgress) {
        [self.webView removeObserver:self
                          forKeyPath:@"estimatedProgress"
                             context:
                                 BHTWebReplyProgressObservationContext];
    }
    if (self.observingURL) {
        [self.webView removeObserver:self
                          forKeyPath:@"URL"
                             context:
                                 BHTWebReplyURLObservationContext];
    }
    self.webView.navigationDelegate = nil;
    self.webView.UIDelegate = nil;
    [self.webView stopLoading];
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context {
    if (context == BHTWebReplyURLObservationContext) {
        [self considerSetupLandingURL:self.webView.URL];
        return;
    }
    if (context != BHTWebReplyProgressObservationContext) {
        [super observeValueForKeyPath:keyPath
                            ofObject:object
                              change:change
                             context:context];
        return;
    }
    float progress =
        (float)self.webView.estimatedProgress;
    if (self.setupReady) {
        self.progressView.hidden = YES;
        return;
    }
    [self.progressView setProgress:progress animated:YES];
    self.progressView.hidden = progress >= 1.0;
    if (progress >= 0.8) {
        [self considerSetupLandingURL:self.webView.URL];
    }
}

- (void)closeTapped {
    // A boundary-review controller may retain a continuation that references
    // its presenter. Dropping it before either pop or dismissal prevents the
    // visible presentation chain from keeping itself alive after cancellation.
    self.doneCompletion = nil;
    if (self.navigationController.viewControllers.firstObject !=
        self) {
        [self.navigationController
            popViewControllerAnimated:YES];
        return;
    }
    [self recordCloseIfNeeded];
    [self.navigationController
        dismissViewControllerAnimated:YES completion:nil];
}

- (void)doneTapped {
    if (self.screenMode ==
            BHTWebReplyScreenModeSignInSetup &&
        !self.setupReady) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticSetupCompletedManually);
    } else if (
        self.screenMode ==
        BHTWebReplyScreenModeAccountManagement) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticAccountManagerCompleted);
    }
    dispatch_block_t completion = [self.doneCompletion copy];
    self.doneCompletion = nil;
    if (self.beginsReplyTransitionOnDone && completion) {
        BHTSetWebReplyTransitionPending(YES);
    }
    if (self.navigationController.viewControllers.firstObject !=
        self) {
        UINavigationController* navigation =
            self.navigationController;
        [navigation popViewControllerAnimated:YES];
        if (completion) {
            id<UIViewControllerTransitionCoordinator> coordinator =
                navigation.transitionCoordinator;
            BOOL scheduled = coordinator &&
                [coordinator
                    animateAlongsideTransition:nil
                                    completion:
                        ^(__unused id<UIViewControllerTransitionCoordinatorContext>
                              context) {
                            completion();
                        }];
            if (!scheduled) {
                dispatch_async(
                    dispatch_get_main_queue(), completion);
            }
        }
        return;
    }
    [self recordCloseIfNeeded];
    [self.navigationController
        dismissViewControllerAnimated:YES
                           completion:completion];
}

- (void)recordCloseIfNeeded {
    if (self.didRecordClose) return;
    self.didRecordClose = YES;
    self.loadAttemptComplete = YES;
    self.loadAttemptGeneration++;
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticClosed);
    if (BHTActiveWebReplyNavigationController ==
        self.navigationController) {
        BHTActiveWebReplyNavigationController = nil;
    }
}

- (void)presentationControllerDidDismiss:
    (__unused UIPresentationController*)presentationController {
    [self recordCloseIfNeeded];
}

- (void)moreTapped {
    if (self.presentedViewController) return;
    UIAlertController* options = [UIAlertController
        alertControllerWithTitle:nil
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [options addAction:[UIAlertAction
        actionWithTitle:
            BHTWebReplyLocalized(
                @"WEB_REPLY_MANAGE_ACCOUNT")
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction* action) {
                    BHTPerformWhenWebReplyPresenterIsReady(
                        weakSelf, 20,
                        ^(UIViewController* presenter) {
                            BHTWebReplyViewController*
                                replyController =
                                    (BHTWebReplyViewController*)
                                        presenter;
                            [replyController
                                showWebAccountManager];
                        },
                        nil);
                }]];
    [options addAction:[UIAlertAction
        actionWithTitle:BHTWebReplyLocalized(@"WEB_REPLY_RELOAD")
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction* action) {
                    [weakSelf retryLoad];
                }]];
    [options addAction:[UIAlertAction
        actionWithTitle:
            BHTWebReplyLocalized(@"WEB_REPLY_ABOUT")
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction* action) {
                    BHTPerformWhenWebReplyPresenterIsReady(
                        weakSelf, 20,
                        ^(UIViewController* presenter) {
                            BHTWebReplyViewController*
                                replyController =
                                    (BHTWebReplyViewController*)
                                        presenter;
                            [replyController
                                showCompatibilityInfo];
                        },
                        nil);
                }]];
    [options addAction:[UIAlertAction
        actionWithTitle:
            BHTWebReplyLocalized(@"WEB_REPLY_CANCEL")
                  style:UIAlertActionStyleCancel
                handler:nil]];
    options.popoverPresentationController.barButtonItem =
        self.moreItem;
    [self presentViewController:options
                       animated:YES
                     completion:nil];
}

- (void)editAccountLabel {
    if (self.presentedViewController) return;
    UIAlertController* editor = [UIAlertController
        alertControllerWithTitle:
            BHTWebReplyLocalized(
                @"WEB_REPLY_ACCOUNT_LABEL_TITLE")
                         message:
            BHTWebReplyLocalized(
                @"WEB_REPLY_ACCOUNT_LABEL_DETAIL")
                  preferredStyle:UIAlertControllerStyleAlert];
    [editor addTextFieldWithConfigurationHandler:
                ^(UITextField* textField) {
                    NSString* current =
                        BHTWebReplyAccountLabel();
                    textField.text =
                        [current hasPrefix:@"@"]
                            ? [current substringFromIndex:1]
                            : current;
                    textField.placeholder =
                        BHTWebReplyLocalized(
                            @"WEB_REPLY_ACCOUNT_LABEL_PLACEHOLDER");
                    textField.autocapitalizationType =
                        UITextAutocapitalizationTypeNone;
                    textField.autocorrectionType =
                        UITextAutocorrectionTypeNo;
                    textField.spellCheckingType =
                        UITextSpellCheckingTypeNo;
                    textField.clearButtonMode =
                        UITextFieldViewModeWhileEditing;
                }];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController* weakEditor = editor;
    [editor addAction:[UIAlertAction
        actionWithTitle:
            BHTWebReplyLocalized(
                @"WEB_REPLY_ACCOUNT_LABEL_SAVE")
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction* action) {
                    NSString* value =
                        weakEditor.textFields.firstObject.text;
                    NSString* normalized =
                        BHTNormalizedWebReplyAccountLabel(
                            value);
                    if (normalized.length > 0) {
                        BHTSetWebReplyAccountLabel(
                            normalized);
                        return;
                    }
                    BHTPerformWhenWebReplyPresenterIsReady(
                        weakSelf, 20,
                        ^(UIViewController* presenter) {
                            UIAlertController* invalid =
                                [UIAlertController
                                    alertControllerWithTitle:
                                        BHTWebReplyLocalized(
                                            @"WEB_REPLY_ACCOUNT_LABEL_INVALID_TITLE")
                                                     message:
                                        BHTWebReplyLocalized(
                                            @"WEB_REPLY_ACCOUNT_LABEL_INVALID_DETAIL")
                                              preferredStyle:
                                                  UIAlertControllerStyleAlert];
                            [invalid addAction:
                                [UIAlertAction
                                    actionWithTitle:
                                        BHTWebReplyLocalized(
                                            @"WEB_REPLY_OK")
                                              style:
                                                  UIAlertActionStyleDefault
                                            handler:nil]];
                            [presenter
                                presentViewController:
                                    invalid
                                             animated:YES
                                           completion:nil];
                        },
                        nil);
                }]];
    if (BHTWebReplyAccountLabel().length > 0) {
        [editor addAction:[UIAlertAction
            actionWithTitle:
                BHTWebReplyLocalized(
                    @"WEB_REPLY_ACCOUNT_LABEL_FORGET")
                      style:UIAlertActionStyleDestructive
                    handler:^(__unused UIAlertAction* action) {
                        BHTSetWebReplyAccountLabel(nil);
                    }]];
    }
    [editor addAction:[UIAlertAction
        actionWithTitle:
            BHTWebReplyLocalized(@"WEB_REPLY_CANCEL")
                  style:UIAlertActionStyleCancel
                handler:nil]];
    [self presentViewController:editor
                       animated:YES
                     completion:nil];
}

- (void)showWebAccountManager {
    if (self.screenMode != BHTWebReplyScreenModeReply ||
        self.presentedViewController ||
        self.navigationController.topViewController != self) {
        return;
    }
    NSURL* accountURL = BHTWebReplyAccountURL();
    if (!accountURL) return;

    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticManageWebAccountOpened);
    BHTWebReplyViewController* manager =
        [[BHTWebReplyViewController alloc]
            initWithURL:accountURL
               titleKey:@"WEB_REPLY_MANAGE_ACCOUNT"
         loadFailureKey:@"WEB_REPLY_SIGN_IN_LOAD_FAILED"
                   mode:
                       BHTWebReplyScreenModeAccountManagement];
    __weak typeof(self) weakSelf = self;
    manager.doneCompletion = ^{
        [weakSelf retryLoad];
    };
    [self.navigationController
        pushViewController:manager
                  animated:YES];
}

- (void)showCompatibilityInfo {
    if (self.presentedViewController) return;
    UIAlertController* info = [UIAlertController
        alertControllerWithTitle:
            BHTWebReplyLocalized(@"WEB_REPLY_FALLBACK_TITLE")
                         message:
            BHTWebReplyLocalized(
                @"WEB_REPLY_FALLBACK_DISCLOSURE")
                  preferredStyle:UIAlertControllerStyleAlert];
    [info addAction:[UIAlertAction
        actionWithTitle:BHTWebReplyLocalized(@"WEB_REPLY_OK")
                  style:UIAlertActionStyleDefault
                handler:nil]];
    [self presentViewController:info
                       animated:YES
                     completion:nil];
}

- (void)retryLoad {
    if (self.setupReady) return;
    if (self.screenMode ==
            BHTWebReplyScreenModeAccountManagement &&
        self.loadAttemptComplete &&
        !self.hasVisibleCommittedContent) {
        // A user-requested retry gets one fresh chance at the known-working
        // fallback route.
        self.accountManagerFallbackScheduled = NO;
        self.accountManagerFallbackAttempted = NO;
        self.accountManagerFallbackCommitted = NO;
        self.accountManagerFallbackFailureRecorded =
            NO;
        self.title =
            BHTWebReplyLocalized(self.screenTitleKey);
    }
    self.errorView.hidden = YES;
    [self.loadingView.layer removeAllAnimations];
    self.loadingView.alpha = 1.0;
    self.loadingView.userInteractionEnabled = YES;
    self.loadingView.hidden =
        self.hasVisibleCommittedContent;
    self.progressView.hidden = NO;
    [self loadRequestWithWatchdog:
        [NSURLRequest requestWithURL:self.initialURL]];
}

- (BOOL)scheduleAccountManagerFallbackIfNeeded {
    if (self.screenMode !=
            BHTWebReplyScreenModeAccountManagement ||
        self.accountManagerFallbackScheduled ||
        self.accountManagerFallbackAttempted ||
        self.hasVisibleCommittedContent ||
        self.setupReady) {
        return NO;
    }
    NSURL* fallbackURL =
        BHTWebReplyAccountFallbackURL();
    if (!fallbackURL) return NO;

    self.accountManagerFallbackScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf =
            weakSelf;
        if (!strongSelf) return;
        strongSelf.accountManagerFallbackScheduled = NO;
        if (!strongSelf.viewIfLoaded.window) {
            [strongSelf showLoadFailure];
            return;
        }
        if (strongSelf.hasVisibleCommittedContent ||
            strongSelf.setupReady ||
            strongSelf
                .mainFrameProvisionalNavigationInFlight) {
            return;
        }
        strongSelf.accountManagerFallbackAttempted =
            YES;
        strongSelf.title =
            BHTWebReplyLocalized(
                @"WEB_REPLY_ACCOUNT_SESSION_CHECK");
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticAccountManagerFallbackStarted);
        [strongSelf loadRequestWithWatchdog:
            [NSURLRequest
                requestWithURL:fallbackURL]];
    });
    return YES;
}

- (void)recordAccountManagerFallbackFailureIfNeeded {
    if (!self.accountManagerFallbackAttempted ||
        self.accountManagerFallbackCommitted ||
        self.accountManagerFallbackFailureRecorded) {
        return;
    }
    self.accountManagerFallbackFailureRecorded = YES;
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticAccountManagerFallbackFailed);
}

- (void)loadRequestWithWatchdog:
    (NSURLRequest*)request {
    if (!request.URL) {
        [self showLoadFailure];
        return;
    }
    self.loadAttemptComplete = NO;
    self.errorView.hidden = YES;
    [self.loadingView.layer removeAllAnimations];
    self.loadingView.alpha = 1.0;
    self.loadingView.userInteractionEnabled = YES;
    self.loadingView.hidden =
        self.hasVisibleCommittedContent;
    self.progressView.hidden = NO;
    WKNavigation* requestedNavigation =
        [self.webView loadRequest:request];
    self.latestMainFrameNavigation =
        requestedNavigation;
    self.mainFrameProvisionalNavigationInFlight =
        requestedNavigation;
    self.explicitMainFrameNavigationAwaitingStart =
        requestedNavigation;
    if (!requestedNavigation) {
        self.loadAttemptComplete = YES;
        [self showLoadFailure];
        return;
    }
    [self
        armLoadWatchdogForNavigation:
            requestedNavigation];
}

- (void)armLoadWatchdogForNavigation:
    (WKNavigation*)navigation {
    if (!navigation) return;
    NSUInteger generation =
        ++self.loadAttemptGeneration;
    self.loadAttemptComplete = NO;
    __weak typeof(self) weakSelf = self;
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(20.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf =
                weakSelf;
            if (!strongSelf ||
                strongSelf.loadAttemptGeneration !=
                    generation ||
                strongSelf.loadAttemptComplete ||
                strongSelf.latestMainFrameNavigation !=
                    navigation ||
                strongSelf.mainFrameProvisionalNavigationInFlight !=
                    navigation ||
                !strongSelf.viewIfLoaded.window) {
                return;
            }
            strongSelf.loadAttemptComplete = YES;
            if (strongSelf.explicitMainFrameNavigationAwaitingStart ==
                navigation) {
                strongSelf.explicitMainFrameNavigationAwaitingStart = nil;
            }
            strongSelf.latestMainFrameNavigation = nil;
            strongSelf.mainFrameProvisionalNavigationInFlight = nil;
            BHTRecordWebReplyDiagnostic(
                BHTWebReplyDiagnosticLoadWatchdogExpired);
            [strongSelf.webView stopLoading];
            if (strongSelf.hasVisibleCommittedContent) {
                [strongSelf.loadingView.layer
                    removeAllAnimations];
                strongSelf.loadingView.alpha = 1.0;
                strongSelf.loadingView.userInteractionEnabled = YES;
                strongSelf.loadingView.hidden = YES;
                strongSelf.progressView.hidden = YES;
                strongSelf.errorView.hidden = YES;
                return;
            }
            [strongSelf showLoadFailure];
        });
}

- (void)scheduleUserPopupRequest:
    (NSURLRequest*)request {
    NSURLRequest* requestCopy = [request copy];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf =
            weakSelf;
        if (!strongSelf ||
            !strongSelf.viewIfLoaded.window ||
            !BHTWebReplyAllowsTopLevelURL(
                requestCopy.URL)) {
            return;
        }
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticUserPopupRerouted);
        [strongSelf loadRequestWithWatchdog:requestCopy];
    });
}

- (void)showLoadFailure {
    if (self.setupReady) return;
    [self
        recordAccountManagerFallbackFailureIfNeeded];
    self.loadAttemptComplete = YES;
    self.loadingView.hidden = YES;
    self.progressView.hidden = YES;
    self.errorView.hidden = NO;
}

- (void)showBlockedNavigationAlert {
    if (self.blockedAlertVisible ||
        self.presentedViewController) {
        return;
    }
    self.blockedAlertVisible = YES;
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:
            BHTWebReplyLocalized(
                @"WEB_REPLY_BLOCKED_LINK_TITLE")
                         message:
            BHTWebReplyLocalized(
                @"WEB_REPLY_BLOCKED_LINK_DETAIL")
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction
        actionWithTitle:
            BHTWebReplyLocalized(@"WEB_REPLY_OK")
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction* action) {
                    weakSelf.blockedAlertVisible = NO;
                }]];
    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

- (void)revealCommittedContent {
    self.loadAttemptComplete = YES;
    self.errorView.hidden = YES;
    if (self.loadingView.hidden) return;
    NSUInteger generation = self.loadAttemptGeneration;
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticLoaderHiddenOnCommit);
    [self.loadingView.layer removeAllAnimations];
    self.loadingView.userInteractionEnabled = NO;
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.16
        animations:^{
            self.loadingView.alpha = 0.0;
        }
        completion:^(__unused BOOL finished) {
            __strong typeof(weakSelf) strongSelf =
                weakSelf;
            if (!strongSelf) return;
            strongSelf.loadingView.userInteractionEnabled = YES;
            if (strongSelf.loadAttemptGeneration !=
                generation) {
                return;
            }
            strongSelf.loadingView.hidden = YES;
            strongSelf.loadingView.alpha = 1.0;
        }];
}

- (void)considerSetupLandingURL:(NSURL*)URL {
    if (self.screenMode !=
            BHTWebReplyScreenModeSignInSetup ||
        self.mainFrameProvisionalNavigationInFlight ||
        self.setupReady) {
        return;
    }
    // A committed /home document is enough to prove that X accepted the
    // visible sign-in flow. Waiting for a later 99%-progress callback can hang
    // forever when X finishes with a same-document SPA transition.
    if (self.hasVisibleCommittedContent &&
        BHTWebReplyURLIsSignedInLanding(URL)) {
        [self showSetupReady];
    }
}

- (void)showSetupReady {
    if (self.setupReady ||
        self.screenMode !=
            BHTWebReplyScreenModeSignInSetup ||
        self.mainFrameProvisionalNavigationInFlight ||
        !self.hasVisibleCommittedContent ||
        !BHTWebReplyURLIsSignedInLanding(
            self.webView.URL)) {
        return;
    }
    self.setupReady = YES;
    self.loadAttemptComplete = YES;
    self.loadAttemptGeneration++;
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticSignInLandingRecognized);
    [self.loadingView.layer removeAllAnimations];
    self.loadingView.alpha = 1.0;
    self.webView.hidden = YES;
    self.progressView.hidden = YES;
    self.loadingView.hidden = YES;
    self.errorView.hidden = YES;
    self.setupReadyView.hidden = NO;
    self.navigationItem.rightBarButtonItem = self.doneItem;
}

- (void)recoverFromIgnoredNavigationError {
    if (!self.hasVisibleCommittedContent &&
        !self.setupReady) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticIgnoredNavigationBeforeCommit);
        if ([self
                scheduleAccountManagerFallbackIfNeeded]) {
            return;
        }
        [self
            recordAccountManagerFallbackFailureIfNeeded];
        [self showLoadFailure];
        return;
    }
    self.loadAttemptComplete = YES;
    [self.loadingView.layer removeAllAnimations];
    self.loadingView.hidden = YES;
    self.loadingView.alpha = 1.0;
    self.loadingView.userInteractionEnabled = YES;
    self.progressView.hidden = YES;
    self.errorView.hidden = YES;
}

- (BOOL)settleMainFrameProvisionalNavigationForCallback:
    (WKNavigation*)navigation {
    WKNavigation* currentNavigation =
        self.latestMainFrameNavigation;
    if (!navigation ||
        currentNavigation != navigation) {
        // A newer load has already replaced this navigation. Its late commit,
        // finish, or failure must not make the newer provisional URL look
        // settled to the setup URL observer.
        return NO;
    }
    if (currentNavigation == navigation &&
        self.mainFrameProvisionalNavigationInFlight ==
            navigation) {
        self.mainFrameProvisionalNavigationInFlight = nil;
    }
    if (self.explicitMainFrameNavigationAwaitingStart ==
        navigation) {
        self.explicitMainFrameNavigationAwaitingStart = nil;
    }
    return YES;
}

- (BOOL)finishMainFrameNavigationForCallback:
    (WKNavigation*)navigation {
    if (![self
            settleMainFrameProvisionalNavigationForCallback:
                navigation]) {
        return NO;
    }
    self.latestMainFrameNavigation = nil;
    return YES;
}

- (void)webView:(__unused WKWebView*)webView
        didStartProvisionalNavigation:
            (WKNavigation*)navigation {
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticNavigationStarted);
    WKNavigation* explicitNavigation =
        self.explicitMainFrameNavigationAwaitingStart;
    BOOL pageInitiatedNavigation =
        explicitNavigation == nil;
    if (explicitNavigation &&
        explicitNavigation != navigation) {
        // loadRequest: installs its returned token before WebKit delivers the
        // corresponding start callback. Ignore an older delayed start while
        // that explicit retry is pending; otherwise it could replace the retry
        // token and let its own later failure settle the newer navigation.
        return;
    }
    if (explicitNavigation == navigation) {
        self.explicitMainFrameNavigationAwaitingStart = nil;
    }
    // With no explicit start pending, the newest delivered token is
    // authoritative. This keeps page-initiated main-frame navigations tracked.
    self.latestMainFrameNavigation =
        navigation;
    self.mainFrameProvisionalNavigationInFlight =
        navigation;
    if (self.setupReady) return;
    if (pageInitiatedNavigation) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticPageNavigationWatchdogArmed);
        [self
            armLoadWatchdogForNavigation:
                navigation];
    }
    self.errorView.hidden = YES;
    self.loadingView.hidden =
        self.hasVisibleCommittedContent;
    self.progressView.hidden = NO;
}

- (void)webView:(WKWebView*)webView
        didCommitNavigation:
            (WKNavigation*)navigation {
    if (![self
            settleMainFrameProvisionalNavigationForCallback:
                navigation]) {
        return;
    }
    if (self.setupReady) return;
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticNavigationCommitted);
    if (self.screenMode ==
            BHTWebReplyScreenModeAccountManagement &&
        self.accountManagerFallbackAttempted &&
        !self.accountManagerFallbackCommitted) {
        self.accountManagerFallbackCommitted = YES;
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticAccountManagerFallbackCommitted);
    }
    self.hasVisibleCommittedContent = YES;
    [self revealCommittedContent];
    if (self.screenMode != BHTWebReplyScreenModeReply &&
        !self.navigationItem.rightBarButtonItem) {
        // Keep setup usable even if X completes sign-in through a route that
        // does not produce the expected /home callback.
        self.navigationItem.rightBarButtonItem = self.doneItem;
    }
    [self considerSetupLandingURL:webView.URL];
}

- (void)webView:(WKWebView*)webView
        didFinishNavigation:
            (WKNavigation*)navigation {
    if (![self
            finishMainFrameNavigationForCallback:
                navigation]) {
        return;
    }
    if (self.setupReady) return;
    if (BHTWebReplyURLIsAboutBlank(webView.URL)) {
        self.loadAttemptComplete = YES;
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticBlankMainFrameFinished);
        [self showLoadFailure];
        return;
    }
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticNavigationFinished);
    self.loadAttemptComplete = YES;
    self.errorView.hidden = YES;
    self.loadingView.hidden = YES;
    self.progressView.hidden = YES;
    [self considerSetupLandingURL:webView.URL];
}

- (void)webView:(__unused WKWebView*)webView
        didFailProvisionalNavigation:
            (WKNavigation*)navigation
                       withError:
            (NSError*)error {
    if (![self
            finishMainFrameNavigationForCallback:
                navigation]) {
        return;
    }
    if (BHTWebReplyShouldIgnoreNavigationError(error)) {
        [self recoverFromIgnoredNavigationError];
        return;
    }
    self.loadAttemptComplete = YES;
    BHTRecordWebReplyNavigationFailure(error, YES);
    [self showLoadFailure];
}

- (void)webView:(__unused WKWebView*)webView
        didFailNavigation:
            (WKNavigation*)navigation
                 withError:(NSError*)error {
    if (![self
            finishMainFrameNavigationForCallback:
                navigation]) {
        return;
    }
    if (BHTWebReplyShouldIgnoreNavigationError(error)) {
        [self recoverFromIgnoredNavigationError];
        [self considerSetupLandingURL:self.webView.URL];
        return;
    }
    self.loadAttemptComplete = YES;
    BHTRecordWebReplyNavigationFailure(error, NO);
    [self showLoadFailure];
}

- (void)webViewWebContentProcessDidTerminate:
    (__unused WKWebView*)webView {
    self.loadAttemptComplete = YES;
    self.explicitMainFrameNavigationAwaitingStart = nil;
    self.latestMainFrameNavigation = nil;
    self.mainFrameProvisionalNavigationInFlight = nil;
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticWebProcessTerminated);
    [self showLoadFailure];
}

- (void)webView:(__unused WKWebView*)webView
        decidePolicyForNavigationResponse:
            (WKNavigationResponse*)navigationResponse
        decisionHandler:
            (void (^)(WKNavigationResponsePolicy))
                decisionHandler {
    if (![navigationResponse isForMainFrame]) {
        decisionHandler(
            WKNavigationResponsePolicyAllow);
        return;
    }

    BHTWebReplyDiagnosticEvent responseFailure =
        BHTWebReplyDiagnosticEventCount;
    if (!navigationResponse.canShowMIMEType) {
        responseFailure =
            BHTWebReplyDiagnosticMainFrameUnsupportedMIMEType;
    } else if ([navigationResponse.response
                   isKindOfClass:
                       [NSHTTPURLResponse class]]) {
        NSInteger statusCode =
            ((NSHTTPURLResponse*)
                 navigationResponse.response)
                .statusCode;
        if (statusCode == 204 || statusCode == 205) {
            responseFailure =
                BHTWebReplyDiagnosticMainFrameEmptyResponse;
        } else if (statusCode >= 400 &&
                   statusCode < 500) {
            responseFailure =
                BHTWebReplyDiagnosticMainFrameHTTPClientError;
        } else if (statusCode >= 500) {
            responseFailure =
                BHTWebReplyDiagnosticMainFrameHTTPServerError;
        }
    }

    if (responseFailure !=
        BHTWebReplyDiagnosticEventCount) {
        self.loadAttemptComplete = YES;
        BHTRecordWebReplyDiagnostic(responseFailure);
        decisionHandler(
            WKNavigationResponsePolicyCancel);
        [self showLoadFailure];
        return;
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(__unused WKWebView*)webView
        decidePolicyForNavigationAction:
            (WKNavigationAction*)navigationAction
        decisionHandler:
            (void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL* destination = navigationAction.request.URL;
    BOOL opensNewWindow =
        navigationAction.targetFrame == nil;
    BOOL userInitiated =
        BHTWebReplyNavigationIsUserInitiated(
            navigationAction);
    BOOL isTopLevel =
        opensNewWindow ||
        navigationAction.targetFrame.isMainFrame;
    if (isTopLevel &&
        BHTWebReplyIsExpectedAppHandoffURL(destination)) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticAppHandoffIgnored);
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    if (isTopLevel &&
        BHTWebReplyURLIsAboutBlank(destination)) {
        BHTRecordWebReplyDiagnostic(
            opensNewWindow
                ? BHTWebReplyDiagnosticBlankPopupIgnored
                : BHTWebReplyDiagnosticBlankMainFramePrevented);
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    if (opensNewWindow && !userInitiated) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticAutomaticPopupIgnored);
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    BOOL allowed = isTopLevel
        ? BHTWebReplyAllowsTopLevelURL(destination)
        : ([destination.scheme.lowercaseString
               isEqualToString:@"https"] ||
           ([destination.scheme.lowercaseString
                isEqualToString:@"about"] &&
            [destination.absoluteString.lowercaseString
                isEqualToString:@"about:blank"]));
    if (!allowed) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticNavigationBlocked);
        BHTRecordWebReplyDiagnostic(
            userInitiated
                ? BHTWebReplyDiagnosticNavigationBlockedUserInitiated
                : BHTWebReplyDiagnosticNavigationBlockedAutomatic);
        decisionHandler(WKNavigationActionPolicyCancel);
        if (isTopLevel && userInitiated) {
            [self showBlockedNavigationAlert];
        }
        return;
    }

    if (opensNewWindow) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (WKWebView*)webView:
        (__unused WKWebView*)webView
        createWebViewWithConfiguration:
            (__unused WKWebViewConfiguration*)configuration
              forNavigationAction:
            (WKNavigationAction*)navigationAction
                   windowFeatures:
            (__unused WKWindowFeatures*)windowFeatures {
    NSURL* destination = navigationAction.request.URL;
    if (BHTWebReplyIsExpectedAppHandoffURL(destination)) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticAppHandoffIgnored);
        return nil;
    }
    if (BHTWebReplyURLIsAboutBlank(destination)) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticBlankPopupIgnored);
        return nil;
    }
    BOOL userInitiated =
        BHTWebReplyNavigationIsUserInitiated(
            navigationAction);
    if (!userInitiated) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticAutomaticPopupIgnored);
        return nil;
    }
    if (BHTWebReplyAllowsTopLevelURL(destination)) {
        [self scheduleUserPopupRequest:
            navigationAction.request];
    } else {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticNavigationBlocked);
        BHTRecordWebReplyDiagnostic(
            userInitiated
                ? BHTWebReplyDiagnosticNavigationBlockedUserInitiated
                : BHTWebReplyDiagnosticNavigationBlockedAutomatic);
        if (userInitiated) {
            [self showBlockedNavigationAlert];
        }
    }
    return nil;
}

- (void)webViewDidClose:(__unused WKWebView*)webView {
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticWebViewCloseReceived);
    [self closeTapped];
}

@end

static BOOL BHTPresentWebReplyScreen(
    UIViewController* presenter,
    NSURL* URL,
    NSString* titleKey,
    NSString* loadFailureKey,
    BHTWebReplyScreenMode mode,
    dispatch_block_t doneCompletion) {
    BOOL presenterUnavailable =
        !presenter || !presenter.viewIfLoaded.window ||
        presenter.isBeingDismissed ||
        presenter.presentedViewController != nil;
    if (presenterUnavailable || !URL) return NO;

    BHTWebReplyViewController* screen =
        [[BHTWebReplyViewController alloc]
            initWithURL:URL
               titleKey:titleKey
             loadFailureKey:loadFailureKey
                        mode:mode];
    screen.doneCompletion = doneCompletion;
    screen.beginsReplyTransitionOnDone =
        mode == BHTWebReplyScreenModeAccountManagement &&
        doneCompletion != nil;
    UINavigationController* navigation =
        [[UINavigationController alloc]
            initWithRootViewController:screen];
    if (UI_USER_INTERFACE_IDIOM() ==
        UIUserInterfaceIdiomPad) {
        navigation.modalPresentationStyle =
            UIModalPresentationFormSheet;
        CGFloat availableHeight =
            MAX(520.0,
                UIScreen.mainScreen.bounds.size.height -
                    96.0);
        navigation.preferredContentSize =
            CGSizeMake(640.0, MIN(780.0, availableHeight));
    } else {
        navigation.modalPresentationStyle =
            mode == BHTWebReplyScreenModeReply
                ? UIModalPresentationFullScreen
                : UIModalPresentationPageSheet;
    }
    @try {
        BHTActiveWebReplyNavigationController = navigation;
        [presenter presentViewController:navigation
                               animated:YES
                             completion:nil];
        BOOL presentationAccepted =
            presenter.presentedViewController == navigation ||
            navigation.presentingViewController == presenter;
        if (!presentationAccepted) {
            BHTActiveWebReplyNavigationController = nil;
            return NO;
        }
        navigation.presentationController.delegate = screen;
    } @catch (__unused NSException* exception) {
        BHTActiveWebReplyNavigationController = nil;
        return NO;
    }
    return YES;
}

static void BHTAcknowledgeWebReplyAccountBoundary(
    id nativeAccount) {
    // A missing context cannot prove that the native account stayed the same.
    // Keep warning on each such reply instead of silently losing switch
    // detection for the rest of the process.
    if (!nativeAccount) return;
    BHTLastWebReplyNativeAccount = nativeAccount;
    atomic_store_explicit(
        &BHTWebReplyAccountBoundaryAcknowledged, YES,
        memory_order_relaxed);
}

static BOOL BHTPresentWebReplyAccountBoundary(
    UIViewController* presenter,
    NSURL* replyURL,
    id nativeAccount,
    BOOL nativeAccountChanged) {
    BOOL presenterUnavailable =
        !presenter || !presenter.viewIfLoaded.window ||
        presenter.isBeingDismissed ||
        presenter.presentedViewController != nil;
    if (presenterUnavailable || !replyURL) return NO;

    NSString* detailKey = nativeAccountChanged
        ? @"WEB_REPLY_ACCOUNT_CHANGED_DETAIL"
        : @"WEB_REPLY_ACCOUNT_BOUNDARY_DETAIL";
    NSString* detail =
        BHTWebReplyLocalized(detailKey);
    NSString* accountLabel =
        BHTWebReplyAccountLabel();
    if (accountLabel.length > 0) {
        detail = [detail
            stringByAppendingFormat:
                @"\n\n%@",
                [NSString
                    stringWithFormat:
                        BHTWebReplyLocalized(
                            @"WEB_REPLY_ACCOUNT_LABEL_CONTEXT_FORMAT"),
                        accountLabel]];
    }
    UIAlertController* boundary = [UIAlertController
        alertControllerWithTitle:
            BHTWebReplyLocalized(
                @"WEB_REPLY_ACCOUNT_BOUNDARY_TITLE")
                         message:detail
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak UIViewController* weakPresenter = presenter;
    __weak id weakNativeAccount = nativeAccount;

    [boundary addAction:[UIAlertAction
        actionWithTitle:
            BHTWebReplyLocalized(
                @"WEB_REPLY_REVIEW_ACCOUNT")
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction* action) {
                    BHTActiveWebReplyBoundaryAlert = nil;
                    BHTSetWebReplyTransitionPending(YES);
                    BHTPerformWhenWebReplyPresenterIsReady(
                        weakPresenter, 20,
                        ^(UIViewController* readyPresenter) {
                            __weak UIViewController*
                                weakReadyPresenter =
                                    readyPresenter;
                            dispatch_block_t continueToReply = ^{
                                BHTPerformWhenWebReplyPresenterIsReady(
                                    weakReadyPresenter, 20,
                                    ^(UIViewController*
                                          replyPresenter) {
                                        if (BHTPresentWebReplyScreen(
                                                replyPresenter,
                                                replyURL,
                                                @"WEB_REPLY_TITLE",
                                                @"WEB_REPLY_LOAD_FAILED",
                                                BHTWebReplyScreenModeReply,
                                                nil)) {
                                            BHTAcknowledgeWebReplyAccountBoundary(
                                                weakNativeAccount);
                                            BHTRecordWebReplyDiagnostic(
                                                BHTWebReplyDiagnosticPresented);
                                        } else {
                                            BHTRecordWebReplyDiagnostic(
                                                BHTWebReplyDiagnosticPresentationUnavailable);
                                        }
                                        BHTSetWebReplyTransitionPending(
                                            NO);
                                    },
                                    ^{
                                        BHTSetWebReplyTransitionPending(
                                            NO);
                                    });
                            };
                            if (BHTPresentWebReplyScreen(
                                    readyPresenter,
                                    BHTWebReplyAccountURL(),
                                    @"WEB_REPLY_MANAGE_ACCOUNT",
                                    @"WEB_REPLY_SIGN_IN_LOAD_FAILED",
                                    BHTWebReplyScreenModeAccountManagement,
                                    continueToReply)) {
                                BHTRecordWebReplyDiagnostic(
                                    BHTWebReplyDiagnosticAccountBoundaryReviewOpened);
                            } else {
                                BHTRecordWebReplyDiagnostic(
                                    BHTWebReplyDiagnosticPresentationUnavailable);
                            }
                            BHTSetWebReplyTransitionPending(NO);
                        },
                        ^{
                            BHTSetWebReplyTransitionPending(NO);
                        });
                }]];
    [boundary addAction:[UIAlertAction
        actionWithTitle:
            BHTWebReplyLocalized(
                @"WEB_REPLY_CONTINUE_TO_REPLY")
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction* action) {
                    BHTActiveWebReplyBoundaryAlert = nil;
                    BHTSetWebReplyTransitionPending(YES);
                    BHTRecordWebReplyDiagnostic(
                        BHTWebReplyDiagnosticAccountBoundaryContinued);
                    BHTPerformWhenWebReplyPresenterIsReady(
                        weakPresenter, 20,
                        ^(UIViewController* readyPresenter) {
                            if (BHTPresentWebReplyScreen(
                                    readyPresenter,
                                    replyURL,
                                    @"WEB_REPLY_TITLE",
                                    @"WEB_REPLY_LOAD_FAILED",
                                    BHTWebReplyScreenModeReply,
                                    nil)) {
                                BHTAcknowledgeWebReplyAccountBoundary(
                                    weakNativeAccount);
                                BHTRecordWebReplyDiagnostic(
                                    BHTWebReplyDiagnosticPresented);
                            } else {
                                BHTRecordWebReplyDiagnostic(
                                    BHTWebReplyDiagnosticPresentationUnavailable);
                            }
                            BHTSetWebReplyTransitionPending(NO);
                        },
                        ^{
                            BHTSetWebReplyTransitionPending(NO);
                        });
                }]];
    [boundary addAction:[UIAlertAction
        actionWithTitle:
            BHTWebReplyLocalized(@"WEB_REPLY_CANCEL")
                  style:UIAlertActionStyleCancel
                handler:^(__unused UIAlertAction* action) {
                    BHTActiveWebReplyBoundaryAlert = nil;
                    BHTSetWebReplyTransitionPending(YES);
                    BHTRecordWebReplyDiagnostic(
                        BHTWebReplyDiagnosticAccountBoundaryCancelled);
                    BHTPerformWhenWebReplyPresenterIsReady(
                        weakPresenter, 20,
                        ^(__unused UIViewController*
                              readyPresenter) {
                            BHTSetWebReplyTransitionPending(NO);
                        },
                        ^{
                            BHTSetWebReplyTransitionPending(NO);
                        });
                }]];

    @try {
        [presenter presentViewController:boundary
                               animated:YES
                             completion:nil];
        BOOL accepted =
            presenter.presentedViewController == boundary ||
            boundary.presentingViewController == presenter;
        if (!accepted) return NO;
        BHTActiveWebReplyBoundaryAlert = boundary;
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticAccountBoundaryWarningShown);
        return YES;
    } @catch (__unused NSException* exception) {
        BHTActiveWebReplyBoundaryAlert = nil;
        return NO;
    }
}

BHTWebReplyRouteResult BHTTryPresentWebReplyFallback(
    id sourceObject,
    id nativeAccount,
    UIViewController* presenter) {
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticRouteAttempt);
    if (![BHTSettings boolForKey:@"web_reply_fallback"]) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticDisabled);
        return BHTWebReplyRouteResultDisabled;
    }
    if (!NSThread.isMainThread) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticOffMainThread);
        return BHTWebReplyRouteResultOffMainThread;
    }

    if (atomic_load_explicit(
            &BHTWebReplyTransitionPending,
            memory_order_relaxed)) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticTransitionPendingBlocked);
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticAlreadyPresented);
        return BHTWebReplyRouteResultAlreadyPresented;
    }

    UIAlertController* boundary =
        BHTActiveWebReplyBoundaryAlert;
    if (boundary && boundary.viewIfLoaded.window &&
        !boundary.isBeingDismissed) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticAlreadyPresented);
        return BHTWebReplyRouteResultAlreadyPresented;
    }
    BHTActiveWebReplyBoundaryAlert = nil;

    UINavigationController* active =
        BHTActiveWebReplyNavigationController;
    if (active && active.viewIfLoaded.window &&
        !active.isBeingDismissed) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticAlreadyPresented);
        return BHTWebReplyRouteResultAlreadyPresented;
    }
    BHTActiveWebReplyNavigationController = nil;

    long long identifier = 0;
    if (!BHTResolveStatusIdentifier(
            sourceObject, &identifier)) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticMissingOrInvalidStatus);
        return BHTWebReplyRouteResultMissingOrInvalidStatus;
    }
    NSURL* replyURL = BHTWebReplyURL(identifier);
    identifier = 0;
    if (!replyURL) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticMissingOrInvalidStatus);
        return BHTWebReplyRouteResultMissingOrInvalidStatus;
    }

    BHTRecordWebReplyDiagnostic(
        nativeAccount
            ? BHTWebReplyDiagnosticNativeAccountContextAvailable
            : BHTWebReplyDiagnosticNativeAccountContextUnavailable);
    if (!nativeAccount) {
        BHTLastWebReplyNativeAccount = nil;
        atomic_store_explicit(
            &BHTWebReplyAccountBoundaryAcknowledged, NO,
            memory_order_relaxed);
    }
    BOOL accountBoundaryAcknowledged =
        atomic_load_explicit(
            &BHTWebReplyAccountBoundaryAcknowledged,
            memory_order_relaxed);
    BOOL nativeAccountChanged =
        accountBoundaryAcknowledged &&
        nativeAccount &&
        BHTLastWebReplyNativeAccount != nativeAccount;
    if (nativeAccountChanged) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticNativeAccountChanged);
    }
    if (!accountBoundaryAcknowledged ||
        !nativeAccount ||
        nativeAccountChanged) {
        if (BHTPresentWebReplyAccountBoundary(
                presenter, replyURL, nativeAccount,
                nativeAccountChanged)) {
            return BHTWebReplyRouteResultPresented;
        }
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticPresentationUnavailable);
        return BHTWebReplyRouteResultPresentationUnavailable;
    }

    if (!BHTPresentWebReplyScreen(
            presenter, replyURL,
            @"WEB_REPLY_TITLE",
            @"WEB_REPLY_LOAD_FAILED",
            BHTWebReplyScreenModeReply,
            nil)) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticPresentationUnavailable);
        return BHTWebReplyRouteResultPresentationUnavailable;
    }

    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticPresented);
    return BHTWebReplyRouteResultPresented;
}

BOOL BHTPresentWebReplySignInSetup(
    UIViewController* presenter) {
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticSignInSetupAttempt);
    if (!NSThread.isMainThread) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticSignInSetupUnavailable);
        return NO;
    }

    UINavigationController* active =
        BHTActiveWebReplyNavigationController;
    if (active && active.viewIfLoaded.window &&
        !active.isBeingDismissed) {
        return YES;
    }
    BHTActiveWebReplyNavigationController = nil;

    BOOL presented = BHTPresentWebReplyScreen(
        presenter, BHTWebReplySignInURL(),
        @"WEB_REPLY_SIGN_IN_TITLE",
        @"WEB_REPLY_SIGN_IN_LOAD_FAILED",
        BHTWebReplyScreenModeSignInSetup,
        nil);
    BHTRecordWebReplyDiagnostic(
        presented
            ? BHTWebReplyDiagnosticSignInSetupPresented
            : BHTWebReplyDiagnosticSignInSetupUnavailable);
    return presented;
}

BOOL BHTPresentWebReplyAccountManager(
    UIViewController* presenter) {
    if (!NSThread.isMainThread) return NO;

    UINavigationController* active =
        BHTActiveWebReplyNavigationController;
    if (active && active.viewIfLoaded.window &&
        !active.isBeingDismissed) {
        return YES;
    }
    BHTActiveWebReplyNavigationController = nil;

    BOOL presented = BHTPresentWebReplyScreen(
        presenter, BHTWebReplyAccountURL(),
        @"WEB_REPLY_MANAGE_ACCOUNT",
        @"WEB_REPLY_SIGN_IN_LOAD_FAILED",
        BHTWebReplyScreenModeAccountManagement,
        nil);
    if (presented) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticManageWebAccountOpened);
    }
    return presented;
}

BOOL BHTWebReplyRouteResultConsumesTap(
    BHTWebReplyRouteResult result) {
    return result == BHTWebReplyRouteResultPresented ||
           result ==
               BHTWebReplyRouteResultAlreadyPresented;
}

NSDictionary* BHTWebReplyFallbackDiagnosticSnapshot(void) {
    NSMutableDictionary* counters =
        [NSMutableDictionary
            dictionaryWithCapacity:
                BHTWebReplyDiagnosticEventCount];
    for (NSUInteger index = 0;
         index < BHTWebReplyDiagnosticEventCount;
         index++) {
        counters[BHTWebReplyDiagnosticNames[index]] =
            @(atomic_load_explicit(
                &BHTWebReplyDiagnosticCounters[index],
                memory_order_relaxed));
    }
    return @{
        @"counters": [counters copy],
        @"usesOfficialWebIntent": @YES,
        @"usesDefaultWebsiteDataStore": @YES,
        @"offersVisiblePersistentSignInSetup": @YES,
        @"revealsContentOnFirstMainFrameCommit": @YES,
        @"usesModeSpecificNativeChrome": @YES,
        @"showsPersistentBrowserToolbar": @NO,
        @"recognizesSignedInLandingWithoutCookieInspection": @YES,
        @"requiresCommittedOrSameDocumentSignedInLanding": @YES,
        @"supportsManualSetupCompletion": @YES,
        @"guardsAccountBoundaryTransitions": @YES,
        @"usesSingleSharedWebAccountSession": @YES,
        @"usesLoginFlowForAccountManagement": @YES,
        @"usesOneShotAccountManagerIntentFallback": @YES,
        @"precommitPolicyInterruptionsCannotLeaveLoaderVisible": @YES,
        @"warnsWhenNativeAccountObjectChanges": @YES,
        @"rechecksEveryReplyWithoutNativeAccountContext": @YES,
        @"remembersNativeAccountOnlyInProcess": @YES,
        @"persistsNativeAccountAssociation": @NO,
        @"storesUserConfirmedAccountLabel": @YES,
        @"automaticallyDetectsWebAccount": @NO,
        @"accountLabelIsUserProvided": @YES,
        @"exportsAccountLabelInReports": @NO,
        @"exportsAccountLabelInPreferenceProfiles": @NO,
        @"knownNativeContextBoundaryAcknowledged":
            @(atomic_load_explicit(
                &BHTWebReplyAccountBoundaryAcknowledged,
                memory_order_relaxed)),
        @"accountBoundaryTransitionPending":
            @(atomic_load_explicit(
                &BHTWebReplyTransitionPending,
                memory_order_relaxed)),
        @"usesPrivateStatusIdentifierTransiently": @YES,
        @"retainsReplyURLOnlyWhilePresented": @YES,
        @"tweakReadsOrWritesCookies": @NO,
        @"injectsPageScripts": @NO,
        @"inspectsRequestBodies": @NO,
        @"capturesReplyText": @NO,
        @"capturesStatusIdentifiers": @NO,
        @"capturesAccountData": @NO,
        @"observesSendCompletion": @NO,
        @"postsThroughHiddenWebView": @NO,
        @"verifiesWebAccountMatchesAppAccount": @NO,
        @"capturesRawErrors": @NO,
    };
}
