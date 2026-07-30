#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Reports whether the X 12.9-only credential fallback can run.
// Native X sign-in remains untouched. The pre-login diagnostic screen may
// still be shown when this returns NO.
BOOL BHTCompatibilitySignInIsAvailable(void);
void BHTPresentCompatibilitySignIn(
    UIViewController* _Nullable presenter);

// Adds a small alternate-sign-in entry to X's signed-out onboarding surface.
// The returned native onboarding controller is otherwise left intact.
void BHTInstallCompatibilitySignInEntry(
    UIViewController* _Nullable onboardingController);

// Aggregate stages, counters, and fixed capability identifiers only.
// Credentials, tokens, URLs, response bodies, account identifiers, and raw
// errors are never included.
NSDictionary<NSString*, id>*
BHTCompatibilitySignInDiagnosticSnapshot(void);

NS_ASSUME_NONNULL_END
