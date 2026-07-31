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
    BHTWebReplyDiagnosticWebViewCloseReceived,
    BHTWebReplyDiagnosticClosed,
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
    @"webViewCloseReceived",
    @"closed",
};
_Static_assert(
    sizeof(BHTWebReplyDiagnosticNames) /
            sizeof(BHTWebReplyDiagnosticNames[0]) ==
        BHTWebReplyDiagnosticEventCount,
    "Every web reply diagnostic needs a fixed name");

static __weak UINavigationController*
    BHTActiveWebReplyNavigationController;
static void* BHTWebReplyProgressObservationContext =
    &BHTWebReplyProgressObservationContext;
static void* BHTWebReplyURLObservationContext =
    &BHTWebReplyURLObservationContext;
// WebKit's public legacy frame-policy interruption is error 102. Keep a
// local name so the tweak also builds with SDKs that omit its deprecated
// WebKitErrorFrameLoadInterruptedByPolicyChange declaration.
static NSInteger const
    BHTWebKitFrameLoadInterruptedByPolicyChangeErrorCode = 102;

typedef NS_ENUM(NSUInteger, BHTWebReplyScreenMode) {
    BHTWebReplyScreenModeReply = 0,
    BHTWebReplyScreenModeSignInSetup,
};

static void BHTRecordWebReplyDiagnostic(
    BHTWebReplyDiagnosticEvent event) {
    if (event >= BHTWebReplyDiagnosticEventCount) return;
    atomic_fetch_add_explicit(
        &BHTWebReplyDiagnosticCounters[event], 1,
        memory_order_relaxed);
}

static NSString* BHTWebReplyLocalized(NSString* key) {
    return [[BHTBundle sharedBundle] localizedStringForKey:key];
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
@property(nonatomic) BOOL observingProgress;
@property(nonatomic) BOOL observingURL;
@property(nonatomic) BOOL didRecordClose;
@property(nonatomic) BOOL blockedAlertVisible;
@property(nonatomic) BOOL hasVisibleCommittedContent;
@property(nonatomic) BOOL setupReady;
@property(nonatomic) NSUInteger setupLandingGeneration;
@property(nonatomic) NSUInteger loadAttemptGeneration;
@property(nonatomic) BOOL loadAttemptComplete;
- (instancetype)initWithURL:(NSURL*)URL
                    titleKey:(NSString*)titleKey
              loadFailureKey:(NSString*)loadFailureKey
                        mode:(BHTWebReplyScreenMode)mode;
- (void)loadRequestWithWatchdog:(NSURLRequest*)request;
- (void)scheduleUserPopupRequest:(NSURLRequest*)request;
@end

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
               action:@selector(closeTapped)];
    self.moreItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(moreTapped)];
    self.moreItem.accessibilityLabel =
        BHTWebReplyLocalized(@"WEB_REPLY_MORE");
    if (self.screenMode == BHTWebReplyScreenModeReply) {
        self.navigationItem.rightBarButtonItem = self.moreItem;
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
            self.screenMode ==
                    BHTWebReplyScreenModeSignInSetup
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
             action:@selector(closeTapped)
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
    [self recordCloseIfNeeded];
    [self.navigationController
        dismissViewControllerAnimated:YES completion:nil];
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
                    dispatch_after(
                        dispatch_time(
                            DISPATCH_TIME_NOW,
                            (int64_t)(0.25 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{
                            [weakSelf
                                showCompatibilityInfo];
                        });
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

- (void)loadRequestWithWatchdog:
    (NSURLRequest*)request {
    if (!request.URL) {
        [self showLoadFailure];
        return;
    }
    NSUInteger generation =
        ++self.loadAttemptGeneration;
    self.loadAttemptComplete = NO;
    self.errorView.hidden = YES;
    [self.loadingView.layer removeAllAnimations];
    self.loadingView.alpha = 1.0;
    self.loadingView.userInteractionEnabled = YES;
    self.loadingView.hidden =
        self.hasVisibleCommittedContent;
    self.progressView.hidden = NO;
    [self.webView loadRequest:request];

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
                !strongSelf.viewIfLoaded.window) {
                return;
            }
            strongSelf.loadAttemptComplete = YES;
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
                [strongSelf considerSetupLandingURL:
                    strongSelf.webView.URL];
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
        self.setupReady) {
        return;
    }
    if (!BHTWebReplyURLIsSignedInLanding(URL)) {
        self.setupLandingGeneration++;
        return;
    }
    NSUInteger generation =
        ++self.setupLandingGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.65 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf =
                weakSelf;
            if (!strongSelf ||
                strongSelf.setupReady ||
                strongSelf.setupLandingGeneration !=
                    generation ||
                !strongSelf.viewIfLoaded.window ||
                !strongSelf.hasVisibleCommittedContent ||
                !BHTWebReplyURLIsSignedInLanding(
                    strongSelf.webView.URL)) {
                return;
            }
            BOOL pageSettled =
                !strongSelf.webView.loading ||
                strongSelf.webView.estimatedProgress >=
                    0.99;
            if (pageSettled) {
                [strongSelf showSetupReady];
            }
        });
}

- (void)showSetupReady {
    if (self.setupReady ||
        self.screenMode !=
            BHTWebReplyScreenModeSignInSetup ||
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

- (void)webView:(__unused WKWebView*)webView
        didStartProvisionalNavigation:
            (__unused WKNavigation*)navigation {
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticNavigationStarted);
    if (self.setupReady) return;
    self.errorView.hidden = YES;
    self.loadingView.hidden =
        self.hasVisibleCommittedContent;
    self.progressView.hidden = NO;
}

- (void)webView:(WKWebView*)webView
        didCommitNavigation:
            (__unused WKNavigation*)navigation {
    if (self.setupReady) return;
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticNavigationCommitted);
    self.hasVisibleCommittedContent = YES;
    [self revealCommittedContent];
    [self considerSetupLandingURL:webView.URL];
}

- (void)webView:(WKWebView*)webView
        didFinishNavigation:
            (__unused WKNavigation*)navigation {
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
            (__unused WKNavigation*)navigation
                       withError:
            (NSError*)error {
    if (BHTWebReplyShouldIgnoreNavigationError(error)) {
        [self recoverFromIgnoredNavigationError];
        [self considerSetupLandingURL:self.webView.URL];
        return;
    }
    self.loadAttemptComplete = YES;
    BHTRecordWebReplyNavigationFailure(error, YES);
    [self showLoadFailure];
}

- (void)webView:(__unused WKWebView*)webView
        didFailNavigation:
            (__unused WKNavigation*)navigation
                 withError:(NSError*)error {
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
    BHTWebReplyScreenMode mode) {
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

BHTWebReplyRouteResult BHTTryPresentWebReplyFallback(
    id sourceObject, UIViewController* presenter) {
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

    if (!BHTPresentWebReplyScreen(
            presenter, replyURL,
            @"WEB_REPLY_TITLE",
            @"WEB_REPLY_LOAD_FAILED",
            BHTWebReplyScreenModeReply)) {
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
        BHTWebReplyScreenModeSignInSetup);
    BHTRecordWebReplyDiagnostic(
        presented
            ? BHTWebReplyDiagnosticSignInSetupPresented
            : BHTWebReplyDiagnosticSignInSetupUnavailable);
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
