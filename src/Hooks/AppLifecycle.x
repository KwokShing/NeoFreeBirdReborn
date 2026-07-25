//
//  AppLifecycle.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// MARK: - Padlock helpers

static const NSInteger PadlockOverlayTag = 909;

static NSArray<UIWindow*>* allActiveWindows(void) {
    NSMutableArray<UIWindow*>* result = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene* ws = (UIWindowScene*)scene;
                for (UIWindow* w in ws.windows) {
                    if (!w.hidden)
                        [result addObject:w];
                }
            }
        }
    }
    if (result.count == 0) {
        for (UIWindow* w in UIApplication.sharedApplication.windows) {
            if (!w.hidden)
                [result addObject:w];
        }
    }
    return result;
}

static UIWindow* activeKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene* ws = (UIWindowScene*)scene;
                for (UIWindow* w in ws.windows) {
                    if (w.isKeyWindow)
                        return w;
                }
                for (UIWindow* w in ws.windows) {
                    if (!w.hidden)
                        return w;
                }
            }
        }
    }
    for (UIWindow* w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow)
            return w;
    }
    for (UIWindow* w in UIApplication.sharedApplication.windows) {
        if (!w.hidden)
            return w;
    }
    return nil;
}

static UIViewController* topViewController(UIViewController* root) {
    if (!root)
        return nil;
    UIViewController* vc = root;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        vc = ((UINavigationController*)vc).visibleViewController ?: vc;
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        UIViewController* sel = ((UITabBarController*)vc).selectedViewController;
        if (sel)
            vc = sel;
    }
    return vc;
}

static void showPadlockOverlay(void) {
    UIWindow* window = activeKeyWindow();
    if (!window)
        return;

    for (UIWindow* w in allActiveWindows()) {
        for (UIView* v in w.subviews) {
            if (v.tag == PadlockOverlayTag)
                [v removeFromSuperview];
        }
    }

    UIView* overlay = [[UIView alloc] initWithFrame:window.bounds];
    overlay.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = UIColor.systemBackgroundColor;
    overlay.userInteractionEnabled = YES;
    overlay.tag = PadlockOverlayTag;

    UIImageView* icon = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.labelColor;

    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text =
        [[BHTBundle sharedBundle] localizedStringForKey:@"PADLOCK_LOCKED_LABEL"];
    label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;

    [overlay addSubview:icon];
    [overlay addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor
                                           constant:-20],
        [label.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor
                                        constant:8]
    ]];

    [window addSubview:overlay];
}

static void removePadlockOverlay(void) {
    for (UIWindow* w in allActiveWindows()) {
        NSMutableArray<UIView*>* toRemove = [NSMutableArray array];
        for (UIView* v in w.subviews) {
            if (v.tag == PadlockOverlayTag)
                [toRemove addObject:v];
        }
        for (UIView* v in toRemove)
            [v removeFromSuperview];
    }
}

// Deliberately in-memory only: the padlock must always re-prompt after a
// relaunch, so persisting this would only risk skipping it.
static BOOL padlockAuthenticated = NO;
static BOOL padlockPresentationRetryScheduled = NO;
static NSUInteger padlockAuthenticationGeneration = 0;
static __weak AuthViewController* activePadlockController = nil;

static BOOL isAuthenticated(void) {
    return padlockAuthenticated;
}

static void setAuthenticated(BOOL yes) {
    padlockAuthenticated = yes;
}

static void presentAuthIfNeeded(void);

static void retryPadlockPresentation(void) {
    if (padlockPresentationRetryScheduled) return;
    padlockPresentationRetryScheduled = YES;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(250 * NSEC_PER_MSEC)),
        dispatch_get_main_queue(), ^{
            padlockPresentationRetryScheduled = NO;
            if ([BHTSettings boolForKey:@"padlock"] &&
                !isAuthenticated() &&
                UIApplication.sharedApplication.applicationState ==
                    UIApplicationStateActive) {
                presentAuthIfNeeded();
            }
        });
}

static void presentAuthIfNeeded(void) {
    if (isAuthenticated()) {
        removePadlockOverlay();
        return;
    }

    UIWindow* window = activeKeyWindow();
    UIViewController* root = window.rootViewController;
    if (!window || !root) {
        showPadlockOverlay();
        retryPadlockPresentation();
        return;
    }

    UIViewController* host = topViewController(root);
    if (!host || !host.view.window) {
        retryPadlockPresentation();
        return;
    }
    if ([host isKindOfClass:AuthViewController.class]) {
        activePadlockController = (AuthViewController*)host;
        // The full-screen authentication surface now protects the content.
        // Remove the separate app-switcher cover so a failed/cancelled attempt
        // can expose its retry button.
        removePadlockOverlay();
        return;
    }
    if (activePadlockController.presentingViewController ||
        activePadlockController.isBeingPresented) {
        return;
    }
    if (host.isBeingPresented || host.isBeingDismissed) {
        retryPadlockPresentation();
        return;
    }

    AuthViewController* auth = [[AuthViewController alloc] init];
    NSUInteger authenticationGeneration =
        padlockAuthenticationGeneration;
    activePadlockController = auth;
    auth.completion = ^(BOOL authenticated) {
        BOOL currentSuccess =
            authenticated &&
            authenticationGeneration ==
                padlockAuthenticationGeneration &&
            UIApplication.sharedApplication.applicationState ==
                UIApplicationStateActive &&
            [BHTSettings boolForKey:@"padlock"];
        setAuthenticated(currentSuccess);
        if (currentSuccess) {
            removePadlockOverlay();
        } else if (authenticated &&
                   UIApplication.sharedApplication.applicationState ==
                       UIApplicationStateActive) {
            showPadlockOverlay();
            retryPadlockPresentation();
        }
        activePadlockController = nil;
    };
    auth.modalPresentationStyle = UIModalPresentationFullScreen;
    if ([auth respondsToSelector:@selector(setModalInPresentation:)]) {
        auth.modalInPresentation = YES;
    }

    // topViewController already walks to the final presented controller. Never
    // dismiss an unrelated compose/share/settings modal just to show the lock;
    // present above it and leave the user's navigation state intact.
    [host presentViewController:auth
                       animated:NO
                     completion:^{
                         removePadlockOverlay();
                     }];
}

// MARK: - App Delegate hooks

%hook T1AppDelegate

- (_Bool)application:(__unsafe_unretained UIApplication*)application
    didFinishLaunchingWithOptions:(__unsafe_unretained id)arg2 {
    _Bool orig = %orig;

    [BHTManager cleanCache];
    if ([BHTSettings boolForKey:@"flex_twitter"]) {
        [[%c(FLEXManager) sharedManager] showExplorer];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        applySelectedThemeColor();
    });

    return orig;
}

- (void)applicationDidBecomeActive:(__unsafe_unretained id)arg1 {
    %orig;

    applySelectedThemeColor();

    if ([BHTSettings boolForKey:@"padlock"]) {
        if (isAuthenticated()) {
            removePadlockOverlay();
        } else {
            showPadlockOverlay();
            dispatch_async(dispatch_get_main_queue(), ^{
                presentAuthIfNeeded();
            });
        }
    } else {
        removePadlockOverlay();
    }
}

- (void)applicationWillResignActive:(__unsafe_unretained id)arg1 {
    %orig;

    if ([BHTSettings boolForKey:@"padlock"]) {
        // Cover the UI (and the app-switcher snapshot) and mark unauthenticated so
        // the next activation prompts again; the overlay persists into background.
        showPadlockOverlay();
        setAuthenticated(NO);
    }

    if ([BHTSettings boolForKey:@"flex_twitter"]) {
        [[%c(FLEXManager) sharedManager] showExplorer];
    }
}

- (void)applicationDidEnterBackground:(__unsafe_unretained id)arg1 {
    %orig;

    if ([BHTSettings boolForKey:@"padlock"]) {
        // A completed authentication attempt that belongs to a prior foreground
        // session must never unlock the next one.
        padlockAuthenticationGeneration++;
        setAuthenticated(NO);
        showPadlockOverlay();
    }
}

%end

// MARK: - Restore Launch Animation

// The launch animation reveals the app through a growing X-shaped mask
// (revealMaskLayer / holePathInView); detach it so the logo zoom is kept but
// the splash simply fades out.

static void stripLaunchRevealMask(UIView* view) {
    // The X-shaped hole lives on the container subview's layer.mask; the top
    // view itself is unmasked, but clear it too for safety.
    view.layer.mask = nil;
    for (UIView* sub in view.subviews) {
        sub.layer.mask = nil;
    }
}

%hook T1AnimatedLaunchScreenView

- (void)layoutSubviews {
    %orig;
    // layoutSubviews re-installs the mask each pass, so re-strip after %orig.
    if ([BHTSettings boolForKey:@"restore_launch_animation"]) {
        stripLaunchRevealMask((UIView*)self);
    }
}

- (void)animateRevealWithCompletion:(id)completion {
    if (![BHTSettings boolForKey:@"restore_launch_animation"]) {
        %orig;
        return;
    }
    stripLaunchRevealMask((UIView*)self);

    [UIView animateWithDuration:0.5
                     animations:^{
                         for (UIView* sub in ((UIView*)self).subviews) {
                             sub.backgroundColor = [UIColor clearColor];
                         }
                     }];

    %orig;
}

%end
