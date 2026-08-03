#import "Login/BHTCompatibilityLogin.h"
#import "Sidebar/BHTSidebarNavigationUtility.h"

#import <objc/runtime.h>
#import <string.h>

static const char* BHTCompatibilityHookUnqualifiedType(
    const char* type) {
    while (type && strchr("rnNoORV", type[0]) != NULL) {
        type++;
    }
    return type;
}

static BOOL BHTCompatibilityHookMethodReturnsVoid(
    Method method) {
    if (!method) return NO;
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* type =
        BHTCompatibilityHookUnqualifiedType(returnType);
    return type && type[0] == 'v';
}

static BOOL BHTCompatibilityHookMethodHasBlockArgument(
    Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!BHTCompatibilityHookMethodReturnsVoid(method) ||
        method_getNumberOfArguments(method) != 3) {
        return NO;
    }
    char argumentType[16] = {0};
    method_getArgumentType(
        method, 2, argumentType, sizeof(argumentType));
    const char* type =
        BHTCompatibilityHookUnqualifiedType(argumentType);
    return type && strcmp(type, "@?") == 0;
}

static BOOL BHTCompatibilityHookMethodHasBooleanArgument(
    Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!BHTCompatibilityHookMethodReturnsVoid(method) ||
        method_getNumberOfArguments(method) != 3) {
        return NO;
    }
    char argumentType[16] = {0};
    method_getArgumentType(
        method, 2, argumentType, sizeof(argumentType));
    const char* type =
        BHTCompatibilityHookUnqualifiedType(argumentType);
    return type &&
           (type[0] == 'B' || type[0] == 'c' || type[0] == 'C');
}

// X creates its signed-out onboarding controller asynchronously. Attach the
// opt-in compatibility entry without replacing X's normal sign-in controls.
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

// The signed-in account manager uses a different controller. Its compatibility
// action opens the same dedicated flow with an Add Account handoff context.
%group BHTCompatibilityAddAccountHooks

%hook T1AccountsViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BHTInstallCompatibilityAddAccountSignInEntry(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // Reconcile once more after X finishes configuring its navigation
    // items so a late native update cannot hide the compatibility action.
    BHTInstallCompatibilityAddAccountSignInEntry(self);
    // X also republishes its TwitterDash rows as the account manager settles.
    // Rebuild the registered drawers once, then let the sidebar hook reapply
    // the saved hidden/order configuration after that native transition.
    BHTRecordSidebarAddAccountRefreshRequested();
    [BHTSidebarNavigationUtility
        refreshRegisteredDashContentControllers];
}

%end

%end

%ctor {
    Class hostController =
        NSClassFromString(@"T1HostViewController");
    SEL onboardingSelector = NSSelectorFromString(
        @"makeOnboardingViewControllerWithCompletion:");
    if (BHTCompatibilityHookMethodHasBlockArgument(
            hostController, onboardingSelector)) {
        %init(BHTCompatibilityLoginHooks);
    }

    Class accountsController =
        NSClassFromString(@"T1AccountsViewController");
    if (BHTCompatibilityHookMethodHasBooleanArgument(
            accountsController, @selector(viewWillAppear:)) &&
        BHTCompatibilityHookMethodHasBooleanArgument(
            accountsController, @selector(viewDidAppear:))) {
        %init(BHTCompatibilityAddAccountHooks);
    }
}
