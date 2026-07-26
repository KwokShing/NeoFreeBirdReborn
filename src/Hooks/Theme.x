//
//  Theme.x
//  NeoFreeBird
//

#import "HookHelpers.h"
#import "Branding/BHTBranding.h"
#import "Compatibility/BHTCompatibilityReporter.h"
#import "Likes/BHTLikesTab.h"
#import "ThemeColor/BHTThemePresets.h"

// MARK: - Custom accent color

static NSNumber* selectedThemeColor(void) {
    return [NSUserDefaults.standardUserDefaults objectForKey:@"bh_color_theme_selectedColor"];
}

// Every apply path (launch re-apply, trait changes, both settings pickers)
// funnels through this setter, so coercing here keeps the custom color pinned.
%hook TAEColorSettings

- (void)setPrimaryColorOption:(NSInteger)colorOption {
    NSNumber* selectedColor = selectedThemeColor();
    %orig(selectedColor ? selectedColor.integerValue : colorOption);
}

- (NSInteger)primaryColorOption {
    NSNumber* selectedColor = selectedThemeColor();
    return selectedColor ? selectedColor.integerValue : %orig;
}

%end

void applySelectedThemeColor(void) {
    NSNumber* selectedColor = selectedThemeColor();
    if (selectedColor) {
        [[objc_getClass("TAEColorSettings") sharedSettings]
            setPrimaryColorOption:selectedColor.integerValue];
    }
}

// MARK: - Custom tab bar order and visibility

static NSString* scribePageForEntry(id<T1AppNavigationTabEntry> entry) {
    if (![entry respondsToSelector:@selector(tabView)]) {
        return nil;
    }
    return [entry tabView].scribePage;
}

// Operates on the tab ENTRIES, not the button views: the app derives both the
// buttons and their content view controllers from this one array.
static NSArray* orderedTabEntries(NSArray* entries) {
    entries = BHTEntriesByInstallingLikesDestination(entries);
    BHTRecordNavigationEntryClasses(entries);

    // Record the underlying tab views so the editor can show real titles and icons.
    NSMutableArray* tabViews = [NSMutableArray new];
    for (id<T1AppNavigationTabEntry> entry in entries) {
        T1TabView* tabView = [entry respondsToSelector:@selector(tabView)] ? [entry tabView] : nil;
        if (tabView) {
            [tabViews addObject:tabView];
        }
    }
    [CustomTabBarUtility recordTabViews:tabViews];

    NSArray<NSString*>* savedVisibleOrder =
        [CustomTabBarUtility visiblePageIDsInOrder];
    BOOL hasCustomOrder = savedVisibleOrder != nil;
    NSMutableArray<NSString*>* visibleOrder =
        [(savedVisibleOrder ?: [CustomTabBarUtility defaultVisiblePageIDs])
            mutableCopy];
    BOOL likesEnabled = [CustomTabBarUtility likesTabEnabled];
    NSUInteger likesIndex = [visibleOrder indexOfObject:BHTLikesPageID()];
    if (likesEnabled) {
        // Likes is its own entry. Keep Grok exactly where the user placed it
        // and add Likes to the default layout without replacing any native tab.
        if (!hasCustomOrder && likesIndex == NSNotFound) {
            [visibleOrder addObject:BHTLikesPageID()];
        }
    } else if (likesIndex != NSNotFound) {
        [visibleOrder removeObjectAtIndex:likesIndex];
    }

    NSMutableDictionary<NSString*, id>* entriesByPage = [NSMutableDictionary new];
    for (id<T1AppNavigationTabEntry> entry in entries) {
        NSString* page = scribePageForEntry(entry);
        if (page && !entriesByPage[page]) {
            entriesByPage[page] = entry;
        }
    }

    // Not customised yet: show the default set (Home, Search, Notifications, Chats)
    // in that order, hiding everything else the app builds.
    if (!hasCustomOrder) {
        NSMutableArray* defaultEntries = [NSMutableArray new];
        for (NSString* pageID in visibleOrder) {
            id entry = entriesByPage[pageID];
            if (entry) {
                [defaultEntries addObject:entry];
            }
        }
        return defaultEntries;
    }

    // Only the chosen tabs show; anything the editor hasn't been told to show
    // (including tabs unlocked after the user last saved) stays hidden.
    NSMutableArray* orderedEntries = [NSMutableArray new];
    NSMutableSet* placed = [NSMutableSet new];
    for (NSString* pageID in visibleOrder) {
        id entry = entriesByPage[pageID];
        if (entry && ![placed containsObject:pageID]) {
            [orderedEntries addObject:entry];
            [placed addObject:pageID];
        }
    }

    return orderedEntries;
}

// The single ordered spine that feeds both the tab buttons and their content, so
// filtering/reordering here keeps taps mapped to the right panel.
%hook T1TabbedAppNavigationViewController

- (void)setVisibleTabEntries:(NSArray*)entries {
    %orig(orderedTabEntries(entries));
}

%end

// MARK: - Keep tab bar visible

static BOOL shouldPinCollapsibleTabBar(
    T1TabBarViewController* controller) {
    if (![BHTSettings boolForKey:@"no_tab_bar_hiding"]) {
        return NO;
    }

    UIUserInterfaceIdiom idiom =
        controller.traitCollection.userInterfaceIdiom;
    if (idiom == UIUserInterfaceIdiomUnspecified) {
        idiom = UIDevice.currentDevice.userInterfaceIdiom;
    }

    // On iPad the same "collapse ratio" drives the vertical rail between its
    // compact and expanded widths; it is not the phone's scroll-to-hide
    // animation. Pinning that value locks the rail in its narrow icon-only
    // state and can fight X's split-view relayouts. The iPad rail already stays
    // on-screen, so preserve its native expansion state.
    return idiom != UIUserInterfaceIdiomPad;
}

%hook T1TabBarViewController

// X 12.9 consults these capabilities before sending collapse-ratio updates.
- (BOOL)tfn_supportsTabBarCollapsing {
    return shouldPinCollapsibleTabBar(self) ? NO : %orig;
}

- (BOOL)tfn_prefersTabBarPinned {
    return shouldPinCollapsibleTabBar(self) ? YES : %orig;
}

// The scroll-driven hide only reaches the tab bar as a collapse ratio, so
// clamping it spares the deliberate hides (fullscreen media, immersive player).
- (void)setTabBarCollapseRatio:(double)ratio {
    if (shouldPinCollapsibleTabBar(self)) {
        %orig(0.0);
    } else {
        %orig(ratio);
    }
}

%end

// MARK: - Tab bar icon and label theming

static BOOL updatingTabIconColor = NO;

static UIColor* tabItemColor(BOOL selected) {
    return selected ? CurrentAccentColor()
                    : [Palette currentSecondaryTextColor];
}

%hook T1TabView

- (void)_t1_updateImageViewAnimated:(BOOL)animated {
    // setIconColor: re-enters this method, so swallow the inner call and let
    // %orig below render once with the new color
    if (updatingTabIconColor) {
        return;
    }

    updatingTabIconColor = YES;
    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        self.iconColor = tabItemColor(self.selected);
    } else if (self.iconColor) {
        self.iconColor = nil;
    }
    updatingTabIconColor = NO;

    %orig(animated);
}

- (void)_t1_updateTitleLabel {
    %orig;

    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        self.titleLabel.textColor = tabItemColor(self.selected);
    }
}

- (BOOL)showsTitleInDisplayMode:(long long)displayMode {
    if ([BHTSettings boolForKey:@"restore_tab_labels"]) {
        return YES;
    }
    return %orig;
}

%new
- (void)applyCurrentThemeToIcon {
    [self _t1_updateImageViewAnimated:NO];
    [self _t1_updateTitleLabel];
}

%end

// MARK: - Home and iPad rail branding

static char kBHTOriginalRailLogoImageKey;
static char kBHTOriginalRailLogoTintKey;
static char kBHTOriginalRailLogoContentModeKey;
static char kBHTOriginalRailLogoAccessibilityLabelKey;
static char kBHTOriginalRailLogoStateCapturedKey;
static char kBHTRailDeferredUpdatePendingKey;
static char kBHTRailResolvedLogoViewKey;

static BOOL BHTUsesPadNavigation(UITraitCollection* traits) {
    UIUserInterfaceIdiom idiom = traits.userInterfaceIdiom;
    if (idiom == UIUserInterfaceIdiomUnspecified) {
        idiom = UIDevice.currentDevice.userInterfaceIdiom;
    }
    return idiom == UIUserInterfaceIdiomPad;
}

static NSHashTable<UIImageView*>* BHTBrandedLogoViews(void) {
    static NSHashTable* views = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        views = [NSHashTable weakObjectsHashTable];
    });
    return views;
}

static void BHTApplyCurrentBirdToImageView(UIImageView* imageView) {
    if (!imageView) return;
    BHTApplyTwitterBirdToImageView(imageView, CurrentAccentColor());
    [BHTBrandedLogoViews() addObject:imageView];
}

static void BHTInstallBrandingThemeObserver(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [NSNotificationCenter.defaultCenter
            addObserverForName:BHTThemeDidChangeNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification* notification) {
                        if (![BHTSettings
                                boolForKey:
                                    @"color_twitter_icon_in_top_bar"]) {
                            return;
                        }
                        UIColor* accent = CurrentAccentColor();
                        for (UIImageView* imageView
                             in BHTBrandedLogoViews().allObjects) {
                            BHTApplyTwitterBirdToImageView(imageView, accent);
                        }
                    }];
    });
}

static BOOL BHTRailHeaderCandidateIsVisible(UIView* candidate,
                                            UIView* hostView) {
    for (UIView* current = candidate; current;
         current = current.superview) {
        if (current.hidden || current.alpha <= 0.01) return NO;
        if (current == hostView) break;
    }
    return YES;
}

static BOOL BHTRailHeaderCandidateBelongsToTab(UIView* candidate,
                                               UIView* hostView) {
    Class tabViewClass = NSClassFromString(@"T1TabView");
    if (!tabViewClass) return NO;
    for (UIView* current = candidate.superview;
         current && current != hostView;
         current = current.superview) {
        if ([current isKindOfClass:tabViewClass]) {
            // The Home house and every other navigation item live inside a
            // T1TabView. The rail header mark does not, so this is a stronger
            // guard than comparing icon pixels or relying on view order.
            return YES;
        }
    }
    return NO;
}

static BOOL BHTIsSafeRailHeaderCandidate(UIImageView* candidate,
                                         UIView* hostView,
                                         CGRect* resolvedFrame) {
    if (!candidate || !hostView ||
        ![candidate isDescendantOfView:hostView] ||
        BHTRailHeaderCandidateBelongsToTab(candidate, hostView) ||
        !BHTRailHeaderCandidateIsVisible(candidate, hostView)) {
        return NO;
    }

    CGRect frame = [candidate convertRect:candidate.bounds toView:hostView];
    if (CGRectIsNull(frame) || CGRectIsInfinite(frame) ||
        CGRectIsEmpty(frame)) {
        return NO;
    }
    CGFloat width = CGRectGetWidth(frame);
    CGFloat height = CGRectGetHeight(frame);
    if (!isfinite(width) || !isfinite(height) ||
        width < 16.0 || height < 16.0 ||
        width > 56.0 || height > 56.0) {
        return NO;
    }
    CGFloat aspectRatio = width / MAX(height, 1.0);
    if (aspectRatio < 0.65 || aspectRatio > 1.35) return NO;

    // FLEX identified the X 12.9 rail header as a 28x28 UIImageView at
    // {34,35}. Keep the fallback inside the safe-area header band so the
    // first Home tab can never qualify even if its internal class changes.
    UIEdgeInsets safeAreaInsets = hostView.safeAreaInsets;
    CGFloat headerBottom = MAX(72.0, safeAreaInsets.top + 48.0);
    if (CGRectGetMinY(frame) < -1.0 ||
        CGRectGetMaxY(frame) > headerBottom) {
        return NO;
    }

    CGFloat hostWidth = CGRectGetWidth(hostView.bounds);
    if (hostWidth <= 0.0) return NO;
    CGFloat edgeBand =
        MIN(144.0, MAX(80.0, hostWidth * 0.18));
    UIUserInterfaceLayoutDirection direction =
        [UIView userInterfaceLayoutDirectionForSemanticContentAttribute:
                    hostView.semanticContentAttribute];
    BOOL inRailColumn =
        direction == UIUserInterfaceLayoutDirectionRightToLeft
            ? CGRectGetMinX(frame) >= hostWidth - edgeBand
            : CGRectGetMaxX(frame) <= edgeBand;
    if (!inRailColumn) return NO;

    if (resolvedFrame) *resolvedFrame = frame;
    return YES;
}

static UIImageView* BHTGuardedRailHeaderImageScan(UIView* hostView,
                                                   NSUInteger* matchCount) {
    __block UIImageView* best = nil;
    __block CGFloat bestScore = CGFLOAT_MAX;
    __block NSUInteger matches = 0;
    EnumerateSubviewsRecursively(hostView, ^(UIView* view) {
        if (![view isKindOfClass:UIImageView.class]) return;
        CGRect frame = CGRectZero;
        UIImageView* imageView = (UIImageView*)view;
        if (!BHTIsSafeRailHeaderCandidate(imageView, hostView, &frame)) {
            return;
        }
        matches++;
        CGFloat iconSize =
            (CGRectGetWidth(frame) + CGRectGetHeight(frame)) / 2.0;
        CGFloat edgeDistance =
            MIN(CGRectGetMinX(frame),
                MAX(0.0, CGRectGetWidth(hostView.bounds) -
                             CGRectGetMaxX(frame)));
        CGFloat score = CGRectGetMidY(frame) * 10.0 +
                        fabs(iconSize - 28.0) * 2.0 +
                        edgeDistance;
        if (score < bestScore) {
            bestScore = score;
            best = imageView;
        }
    });
    if (matchCount) *matchCount = matches;
    return best;
}

static UIImageView* BHTRailHeaderLogoImageView(UIView* hostView,
                                               NSString** resolution,
                                               NSUInteger* matchCount) {
    UIImageView* cached =
        objc_getAssociatedObject(hostView,
                                 &kBHTRailResolvedLogoViewKey);
    if (BHTIsSafeRailHeaderCandidate(cached, hostView, NULL)) {
        if (resolution) *resolution = @"cachedGuardedHeader";
        if (matchCount) *matchCount = 1;
        return cached;
    }
    if (cached) {
        objc_setAssociatedObject(
            hostView, &kBHTRailResolvedLogoViewKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // X 12.9 owns the actual iPad header mark in T1TabBarHostView. Resolve its
    // semantic logo property/ivar first.
    SEL selector = NSSelectorFromString(@"logoImageView");
    if ([hostView respondsToSelector:selector]) {
        id candidate = nil;
        @try {
            candidate =
                ((id (*)(id, SEL))objc_msgSend)(hostView, selector);
        } @catch (__unused NSException* exception) {
        }
        if ([candidate isKindOfClass:UIImageView.class] &&
            BHTIsSafeRailHeaderCandidate(candidate, hostView, NULL)) {
            if (resolution) *resolution = @"semanticSelector";
            if (matchCount) *matchCount = 1;
            objc_setAssociatedObject(
                hostView, &kBHTRailResolvedLogoViewKey, candidate,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return candidate;
        }
    }

    for (Class currentClass = hostView.class;
         currentClass && currentClass != UIView.class;
         currentClass = class_getSuperclass(currentClass)) {
        unsigned int ivarCount = 0;
        Ivar* ivars = class_copyIvarList(currentClass, &ivarCount);
        for (unsigned int index = 0; index < ivarCount; index++) {
            Ivar ivar = ivars[index];
            const char* rawName = ivar_getName(ivar);
            const char* encoding = ivar_getTypeEncoding(ivar);
            NSString* name =
                rawName ? [NSString stringWithUTF8String:rawName] : @"";
            if (!encoding || encoding[0] != '@' ||
                [name.lowercaseString rangeOfString:@"logo"].location ==
                    NSNotFound) {
                continue;
            }
            id candidate = nil;
            @try {
                candidate = object_getIvar(hostView, ivar);
            } @catch (__unused NSException* exception) {
            }
            if ([candidate isKindOfClass:UIImageView.class] &&
                BHTIsSafeRailHeaderCandidate(candidate, hostView, NULL)) {
                free(ivars);
                if (resolution) {
                    *resolution =
                        [@"semanticIvar:" stringByAppendingString:name];
                }
                if (matchCount) *matchCount = 1;
                objc_setAssociatedObject(
                    hostView, &kBHTRailResolvedLogoViewKey, candidate,
                    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                return candidate;
            }
        }
        free(ivars);
    }

    UIImageView* fallback =
        BHTGuardedRailHeaderImageScan(hostView, matchCount);
    if (resolution) {
        *resolution =
            fallback ? @"guardedHeaderScan" : @"unresolved";
    }
    if (fallback) {
        objc_setAssociatedObject(
            hostView, &kBHTRailResolvedLogoViewKey, fallback,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return fallback;
}

static void BHTUpdateRailHostBranding(UIView* hostView) {
    if (!BHTUsesPadNavigation(hostView.traitCollection)) return;
    NSString* resolution = nil;
    NSUInteger matchCount = 0;
    UIImageView* logoView =
        BHTRailHeaderLogoImageView(hostView, &resolution, &matchCount);
    if (!logoView) {
        BHTRecordRailBrandingObservation(
            resolution ?: @"unresolved", hostView, nil, matchCount);
        return;
    }

    BOOL enabled =
        [BHTSettings boolForKey:@"color_twitter_icon_in_top_bar"];
    BOOL capturedOriginalState =
        [objc_getAssociatedObject(
            logoView, &kBHTOriginalRailLogoStateCapturedKey)
            boolValue];
    if (enabled) {
        // Wait until X has supplied its stock image so disabling the setting
        // can restore every property exactly instead of leaving a bird behind
        // on an initially-empty image view.
        if (!capturedOriginalState && !logoView.image) {
            BHTRecordRailBrandingObservation(
                resolution ?: @"unresolved", hostView, logoView,
                matchCount);
            return;
        }
        if (!capturedOriginalState) {
            objc_setAssociatedObject(
                logoView, &kBHTOriginalRailLogoImageKey,
                logoView.image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(
                logoView, &kBHTOriginalRailLogoTintKey,
                logoView.tintColor ?: NSNull.null,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(
                logoView, &kBHTOriginalRailLogoContentModeKey,
                @(logoView.contentMode),
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(
                logoView,
                &kBHTOriginalRailLogoAccessibilityLabelKey,
                logoView.accessibilityLabel ?: NSNull.null,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(
                logoView, &kBHTOriginalRailLogoStateCapturedKey, @YES,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        BHTInstallBrandingThemeObserver();
        BHTApplyCurrentBirdToImageView(logoView);
    } else if (capturedOriginalState) {
        [BHTBrandedLogoViews() removeObject:logoView];
        logoView.image =
            objc_getAssociatedObject(logoView,
                                     &kBHTOriginalRailLogoImageKey);
        id originalTint =
            objc_getAssociatedObject(logoView,
                                     &kBHTOriginalRailLogoTintKey);
        logoView.tintColor =
            originalTint == NSNull.null ? nil : originalTint;
        NSNumber* originalContentMode =
            objc_getAssociatedObject(
                logoView, &kBHTOriginalRailLogoContentModeKey);
        if (originalContentMode) {
            logoView.contentMode =
                (UIViewContentMode)originalContentMode.integerValue;
        }
        id originalAccessibilityLabel =
            objc_getAssociatedObject(
                logoView,
                &kBHTOriginalRailLogoAccessibilityLabelKey);
        logoView.accessibilityLabel =
            originalAccessibilityLabel == NSNull.null
                ? nil
                : originalAccessibilityLabel;
        objc_setAssociatedObject(
            logoView, &kBHTOriginalRailLogoImageKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            logoView, &kBHTOriginalRailLogoTintKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            logoView, &kBHTOriginalRailLogoContentModeKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            logoView,
            &kBHTOriginalRailLogoAccessibilityLabelKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            logoView, &kBHTOriginalRailLogoStateCapturedKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BHTRecordRailBrandingObservation(
        resolution ?: @"unresolved", hostView, logoView, matchCount);
}

static void BHTScheduleDeferredRailHostBranding(UIView* hostView) {
    if (!hostView ||
        objc_getAssociatedObject(
            hostView, &kBHTRailDeferredUpdatePendingKey)) {
        return;
    }
    objc_setAssociatedObject(
        hostView, &kBHTRailDeferredUpdatePendingKey, @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView* weakHostView = hostView;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView* strongHostView = weakHostView;
        if (!strongHostView) return;
        objc_setAssociatedObject(
            strongHostView, &kBHTRailDeferredUpdatePendingKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BHTUpdateRailHostBranding(strongHostView);
    });
}

%hook T1TabBarHostView

- (void)didMoveToWindow {
    %orig;
    BHTUpdateRailHostBranding((UIView*)self);
    BHTScheduleDeferredRailHostBranding((UIView*)self);
}

- (void)layoutSubviews {
    %orig;
    BHTUpdateRailHostBranding((UIView*)self);
    // The stock rail may assign its X image from a child layout later in the
    // same pass. Re-apply once at the end of the main run loop without a
    // timer, polling, or a process-wide UIImageView hook.
    BHTScheduleDeferredRailHostBranding((UIView*)self);
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraits {
    %orig(previousTraits);
    BHTUpdateRailHostBranding((UIView*)self);
    BHTScheduleDeferredRailHostBranding((UIView*)self);
}

- (void)didAddSubview:(UIView*)subview {
    %orig(subview);
    BHTScheduleDeferredRailHostBranding((UIView*)self);
}

- (void)setTabBarViewController:(id)controller {
    %orig(controller);
    BHTScheduleDeferredRailHostBranding((UIView*)self);
}

%end

%hook _TtC11TwitterHome39HomeDefaultNavigationBarTitleViewPlugin

- (UIView*)titleView {
    UIView* titleView = %orig;

    if ([titleView isKindOfClass:[UIImageView class]]) {
        UIImageView* logoView = (UIImageView*)titleView;
        BOOL enabled =
            [BHTSettings boolForKey:@"color_twitter_icon_in_top_bar"];
        BOOL usesPadRail =
            BHTUsesPadNavigation(titleView.traitCollection);
        // iPad already has the branded rail header. Suppress this second Home
        // title mark there; on iPhone it remains the single themed bird.
        logoView.hidden = enabled && usesPadRail;
        logoView.accessibilityElementsHidden = logoView.hidden;
        if (enabled && !usesPadRail) {
            BHTInstallBrandingThemeObserver();
            BHTApplyCurrentBirdToImageView(logoView);
        }
    }

    return titleView;
}

%end
