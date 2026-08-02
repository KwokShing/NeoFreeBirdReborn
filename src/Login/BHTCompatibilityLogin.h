#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Reports whether X 12.9's own native onboarding sign-in route can run.
// NeoFreeBird never receives the credentials entered on that route.
BOOL BHTCompatibilitySignInIsAvailable(void);
void BHTPresentCompatibilitySignIn(
    UIViewController* _Nullable presenter);
void BHTPresentCompatibilitySignInForAddingAccount(
    UIViewController* _Nullable accountsController);

// Adds native compatibility sign-in and privacy-safe report actions to X's
// signed-out onboarding surface. Tapping sign-in asks X's host controller to
// present its native JetX/Jetfuel login flow.
void BHTInstallCompatibilitySignInEntry(
    UIViewController* _Nullable onboardingController);

// Adds a separate action to X's signed-in account-management screen. It
// delegates to X's native existing-account action so X retains its normal
// account registration, dismissal, and switching callbacks.
void BHTInstallCompatibilityAddAccountSignInEntry(
    UIViewController* _Nullable accountsController);

// Aggregate stages, counters, and fixed capability identifiers only.
// Credentials, tokens, URLs, response bodies, account identifiers, and raw
// errors are never included.
NSDictionary<NSString*, id>*
BHTCompatibilitySignInDiagnosticSnapshot(void);

NS_ASSUME_NONNULL_END
