#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// X 12.9-only, user-initiated fallback. Native X sign-in remains untouched.
BOOL BHTCompatibilitySignInIsAvailable(void);
void BHTPresentCompatibilitySignIn(
    UIViewController* _Nullable presenter);

// Adds a small alternate-sign-in entry to X's signed-out onboarding surface.
// The returned native onboarding controller is otherwise left intact.
void BHTInstallCompatibilitySignInEntry(
    UIViewController* _Nullable onboardingController);

// Aggregate stages and counters only. Credentials, tokens, URLs, response
// bodies, account identifiers, and raw errors are never included.
NSDictionary<NSString*, id*>*
BHTCompatibilitySignInDiagnosticSnapshot(void);

NS_ASSUME_NONNULL_END
