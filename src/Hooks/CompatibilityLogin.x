#import "Login/BHTCompatibilityLogin.h"

// X creates its signed-out onboarding controller asynchronously. Wrap the
// completion only to attach an explicit alternate-sign-in entry; the native
// controller and native sign-in behavior otherwise remain unchanged.
%group BHTCompatibilityLoginHooks

%hook T1HostViewController

- (void)makeOnboardingViewControllerWithCompletion:
    (void (^)(UIViewController* controller))completion {
    if (!completion) {
        %orig;
        return;
    }

    void (^wrappedCompletion)(UIViewController*) =
        ^(UIViewController* controller) {
            BHTInstallCompatibilitySignInEntry(controller);
            completion(controller);
        };
    %orig(wrappedCompletion);
}

%end

%end

%ctor {
    NSString* version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if ([version isEqualToString:@"12.9"]) {
        %init(BHTCompatibilityLoginHooks);
    }
}
