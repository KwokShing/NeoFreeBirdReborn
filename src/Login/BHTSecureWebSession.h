#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

BOOL BHTSecureWebSessionSignInIsAvailable(void);
BOOL BHTSecureWebSessionHasActiveSession(void);

// Presents an explicit x.com-owned sign-in screen. NeoFreeBird never receives
// the password. Session cookies are read only after the user taps the native
// confirmation button.
void BHTPresentSecureWebSessionSignIn(
    UIViewController* _Nullable presenter,
    UIViewController* _Nullable addAccountController);

// Returns the original request unless a saved session exists and the request
// is HTTPS to an exact x.com/twitter.com host or one of their subdomains.
NSURLRequest* BHTSecureWebSessionAuthenticatedRequest(
    NSURLRequest* request);

// Used only to make the locally-created account shell pass X's account gate.
// The comparison is against the validated, Keychain-backed screen name.
BOOL BHTSecureWebSessionOwnsNativeAccount(id _Nullable account);

// Deletes the Keychain item, the matching WebKit/URL-loading cookies, and the
// locally-created X account shell when that private API is available.
void BHTRevokeSecureWebSession(
    void (^_Nullable completion)(BOOL accountShellRemoved));

// Fixed capabilities and counters only. No handles, IDs, URLs, cookie values,
// headers, Keychain data, or errors are included.
NSDictionary<NSString*, id>*
BHTSecureWebSessionDiagnosticSnapshot(void);

NS_ASSUME_NONNULL_END
