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
    BHTWebReplyDiagnosticNavigationFinished,
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
    BHTWebReplyDiagnosticNavigationBlocked,
    BHTWebReplyDiagnosticNavigationBlockedUserInitiated,
    BHTWebReplyDiagnosticNavigationBlockedAutomatic,
    BHTWebReplyDiagnosticWebProcessTerminated,
    BHTWebReplyDiagnosticSignInSetupAttempt,
    BHTWebReplyDiagnosticSignInSetupPresented,
    BHTWebReplyDiagnosticSignInSetupUnavailable,
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
    @"navigationFinished",
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
    @"navigationBlocked",
    @"navigationBlockedUserInitiated",
    @"navigationBlockedAutomatic",
    @"webProcessTerminated",
    @"signInSetupAttempt",
    @"signInSetupPresented",
    @"signInSetupUnavailable",
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
// WebKit's public legacy frame-policy interruption is error 102. Keep a
// local name so the tweak also builds with SDKs that omit its deprecated
// WebKitErrorFrameLoadInterruptedByPolicyChange declaration.
static NSInteger const
    BHTWebKitFrameLoadInterruptedByPolicyChangeErrorCode = 102;

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
    NSURL* URL = [NSURL URLWithString:@"https://x.com/home"];
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

static BOOL BHTWebReplyAllowsTopLevelURL(NSURL* URL) {
    if (!URL) return NO;
    if ([URL.scheme.lowercaseString isEqualToString:@"about"]) {
        return [URL.absoluteString.lowercaseString
            isEqualToString:@"about:blank"];
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
@property(nonatomic, copy) NSString* screenPromptKey;
@property(nonatomic, copy) NSString* loadFailureKey;
@property(nonatomic, strong) WKWebView* webView;
@property(nonatomic, strong) UIProgressView* progressView;
@property(nonatomic, strong) UIView* errorView;
@property(nonatomic, strong) UIBarButtonItem* backItem;
@property(nonatomic, strong) UIBarButtonItem* forwardItem;
@property(nonatomic) BOOL observingProgress;
@property(nonatomic) BOOL didRecordClose;
@property(nonatomic) BOOL blockedAlertVisible;
- (instancetype)initWithURL:(NSURL*)URL
                    titleKey:(NSString*)titleKey
                   promptKey:(NSString*)promptKey
             loadFailureKey:(NSString*)loadFailureKey;
@end

@implementation BHTWebReplyViewController

- (instancetype)initWithURL:(NSURL*)URL
                    titleKey:(NSString*)titleKey
                   promptKey:(NSString*)promptKey
             loadFailureKey:(NSString*)loadFailureKey {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _initialURL = URL;
        _screenTitleKey = [titleKey copy];
        _screenPromptKey = [promptKey copy];
        _loadFailureKey = [loadFailureKey copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title =
        BHTWebReplyLocalized(self.screenTitleKey);
    self.navigationItem.prompt =
        BHTWebReplyLocalized(self.screenPromptKey);
    self.view.backgroundColor =
        [Palette currentBackgroundColor];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:
                UIBarButtonSystemItemClose
                                 target:self
                                 action:@selector(closeTapped)];

    WKWebViewConfiguration* configuration =
        [WKWebViewConfiguration new];
    configuration.websiteDataStore =
        WKWebsiteDataStore.defaultDataStore;
    configuration.allowsInlineMediaPlayback = YES;
    if (@available(iOS 13.0, *)) {
        configuration.defaultWebpagePreferences
            .preferredContentMode = WKContentModeMobile;
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

    self.errorView = [self buildErrorView];
    self.errorView.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorView.hidden = YES;
    [self.view addSubview:self.errorView];

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
        [self.errorView.topAnchor
            constraintEqualToAnchor:self.webView.topAnchor],
        [self.errorView.leadingAnchor
            constraintEqualToAnchor:self.webView.leadingAnchor],
        [self.errorView.trailingAnchor
            constraintEqualToAnchor:self.webView.trailingAnchor],
        [self.errorView.bottomAnchor
            constraintEqualToAnchor:self.webView.bottomAnchor],
    ]];

    self.backItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"chevron.left"]
                 style:UIBarButtonItemStylePlain
                target:self
                action:@selector(goBack)];
    self.backItem.accessibilityLabel =
        BHTWebReplyLocalized(@"WEB_REPLY_BACK");
    self.forwardItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"chevron.right"]
                 style:UIBarButtonItemStylePlain
                target:self
                action:@selector(goForward)];
    self.forwardItem.accessibilityLabel =
        BHTWebReplyLocalized(@"WEB_REPLY_FORWARD");
    UIBarButtonItem* reloadItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                 style:UIBarButtonItemStylePlain
                target:self
                action:@selector(retryLoad)];
    reloadItem.accessibilityLabel =
        BHTWebReplyLocalized(@"WEB_REPLY_RELOAD");
    UIBarButtonItem* firstFlexible = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:
            UIBarButtonSystemItemFlexibleSpace
                             target:nil
                             action:nil];
    UIBarButtonItem* secondFlexible = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:
            UIBarButtonSystemItemFlexibleSpace
                             target:nil
                             action:nil];
    self.toolbarItems = @[
        self.backItem, firstFlexible, self.forwardItem,
        secondFlexible, reloadItem
    ];

    [self applyNativeTheme];
    [self updateNavigationControls];
    [self.webView addObserver:self
                   forKeyPath:@"estimatedProgress"
                      options:NSKeyValueObservingOptionNew
                      context:
                          BHTWebReplyProgressObservationContext];
    self.observingProgress = YES;
    [self retryLoad];
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

- (void)applyNativeTheme {
    UIColor* accent =
        [Palette customAccentColor] ?:
        UIColor.systemBlueColor;
    UIColor* surface = [Palette currentSurfaceColor];
    UIColor* text = [Palette currentTextColor];
    self.navigationController.navigationBar.tintColor = accent;
    self.navigationController.toolbar.tintColor = accent;

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

    UIToolbarAppearance* toolbarAppearance =
        [UIToolbarAppearance new];
    [toolbarAppearance configureWithOpaqueBackground];
    toolbarAppearance.backgroundColor = surface;
    self.navigationController.toolbar.standardAppearance =
        toolbarAppearance;
    if (@available(iOS 15.0, *)) {
        self.navigationController.toolbar.scrollEdgeAppearance =
            toolbarAppearance;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController
        setToolbarHidden:NO animated:NO];
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
    self.webView.navigationDelegate = nil;
    self.webView.UIDelegate = nil;
    [self.webView stopLoading];
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context {
    if (context != BHTWebReplyProgressObservationContext) {
        [super observeValueForKeyPath:keyPath
                            ofObject:object
                              change:change
                             context:context];
        return;
    }
    float progress =
        (float)self.webView.estimatedProgress;
    [self.progressView setProgress:progress animated:YES];
    self.progressView.hidden = progress >= 1.0;
}

- (void)closeTapped {
    [self recordCloseIfNeeded];
    [self.navigationController
        dismissViewControllerAnimated:YES completion:nil];
}

- (void)recordCloseIfNeeded {
    if (self.didRecordClose) return;
    self.didRecordClose = YES;
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

- (void)goBack {
    if (self.webView.canGoBack) [self.webView goBack];
}

- (void)goForward {
    if (self.webView.canGoForward) [self.webView goForward];
}

- (void)retryLoad {
    self.errorView.hidden = YES;
    self.progressView.hidden = NO;
    [self.webView loadRequest:
        [NSURLRequest requestWithURL:self.initialURL]];
}

- (void)updateNavigationControls {
    self.backItem.enabled = self.webView.canGoBack;
    self.forwardItem.enabled = self.webView.canGoForward;
}

- (void)showLoadFailure {
    self.progressView.hidden = YES;
    self.errorView.hidden = NO;
    [self updateNavigationControls];
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

- (void)webView:(__unused WKWebView*)webView
        didStartProvisionalNavigation:
            (__unused WKNavigation*)navigation {
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticNavigationStarted);
    self.errorView.hidden = YES;
    self.progressView.hidden = NO;
    [self updateNavigationControls];
}

- (void)webView:(__unused WKWebView*)webView
        didFinishNavigation:
            (__unused WKNavigation*)navigation {
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticNavigationFinished);
    self.errorView.hidden = YES;
    self.progressView.hidden = YES;
    [self updateNavigationControls];
}

- (void)webView:(__unused WKWebView*)webView
        didFailProvisionalNavigation:
            (__unused WKNavigation*)navigation
                       withError:
            (NSError*)error {
    if (BHTWebReplyShouldIgnoreNavigationError(error)) {
        return;
    }
    BHTRecordWebReplyNavigationFailure(error, YES);
    [self showLoadFailure];
}

- (void)webView:(__unused WKWebView*)webView
        didFailNavigation:
            (__unused WKNavigation*)navigation
                 withError:(NSError*)error {
    if (BHTWebReplyShouldIgnoreNavigationError(error)) {
        return;
    }
    BHTRecordWebReplyNavigationFailure(error, NO);
    [self showLoadFailure];
}

- (void)webViewWebContentProcessDidTerminate:
    (__unused WKWebView*)webView {
    BHTRecordWebReplyDiagnostic(
        BHTWebReplyDiagnosticWebProcessTerminated);
    [self showLoadFailure];
}

- (void)webView:(WKWebView*)webView
        decidePolicyForNavigationAction:
            (WKNavigationAction*)navigationAction
        decisionHandler:
            (void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL* destination = navigationAction.request.URL;
    BOOL isTopLevel =
        navigationAction.targetFrame == nil ||
        navigationAction.targetFrame.isMainFrame;
    if (isTopLevel &&
        BHTWebReplyIsExpectedAppHandoffURL(destination)) {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticAppHandoffIgnored);
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
        BOOL userInitiated =
            BHTWebReplyNavigationIsUserInitiated(
                navigationAction);
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

    if (navigationAction.targetFrame == nil) {
        decisionHandler(WKNavigationActionPolicyCancel);
        [webView loadRequest:navigationAction.request];
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (WKWebView*)webView:(WKWebView*)webView
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
    if (BHTWebReplyAllowsTopLevelURL(destination)) {
        [webView loadRequest:navigationAction.request];
    } else {
        BHTRecordWebReplyDiagnostic(
            BHTWebReplyDiagnosticNavigationBlocked);
        BOOL userInitiated =
            BHTWebReplyNavigationIsUserInitiated(
                navigationAction);
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

@end

static BOOL BHTPresentWebReplyScreen(
    UIViewController* presenter,
    NSURL* URL,
    NSString* titleKey,
    NSString* promptKey,
    NSString* loadFailureKey) {
    BOOL presenterUnavailable =
        !presenter || !presenter.viewIfLoaded.window ||
        presenter.isBeingDismissed ||
        presenter.presentedViewController != nil;
    if (presenterUnavailable || !URL) return NO;

    BHTWebReplyViewController* screen =
        [[BHTWebReplyViewController alloc]
            initWithURL:URL
               titleKey:titleKey
              promptKey:promptKey
         loadFailureKey:loadFailureKey];
    UINavigationController* navigation =
        [[UINavigationController alloc]
            initWithRootViewController:screen];
    if (UI_USER_INTERFACE_IDIOM() ==
        UIUserInterfaceIdiomPad) {
        navigation.modalPresentationStyle =
            UIModalPresentationFormSheet;
        navigation.preferredContentSize =
            CGSizeMake(620.0, 760.0);
    } else {
        navigation.modalPresentationStyle =
            UIModalPresentationFullScreen;
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
            @"WEB_REPLY_ACCOUNT_PROMPT",
            @"WEB_REPLY_LOAD_FAILED")) {
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
        @"WEB_REPLY_SIGN_IN_PROMPT",
        @"WEB_REPLY_SIGN_IN_LOAD_FAILED");
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
