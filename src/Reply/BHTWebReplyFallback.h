#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, BHTWebReplyRouteResult) {
    BHTWebReplyRouteResultDisabled = 0,
    BHTWebReplyRouteResultMissingOrInvalidStatus,
    BHTWebReplyRouteResultOffMainThread,
    BHTWebReplyRouteResultPresentationUnavailable,
    BHTWebReplyRouteResultPresented,
    BHTWebReplyRouteResultAlreadyPresented,
};

// The source object is inspected only while this opt-in route is being
// evaluated. Native-account context is compared only by process-local object
// identity so switching X accounts can trigger a visible web-account check.
// No native host model, native account identifier, or draft text is persisted
// or added to diagnostics. The reply URL exists only while the visible
// composer or its account-boundary prompt is open.
BHTWebReplyRouteResult BHTTryPresentWebReplyFallback(
    id _Nullable sourceObject,
    id _Nullable nativeAccount,
    UIViewController* _Nullable presenter);

// Primary inline-reply variant. It first tries X 12.9's own visible web
// controller bound to the exact account object supplied by X, then falls back
// to the custom visible shared-session screen if any runtime guard fails.
BHTWebReplyRouteResult
BHTTryPresentAccountBoundWebReplyFallback(
    id _Nullable sourceObject,
    id _Nullable nativeAccount,
    UIViewController* _Nullable presenter);

// Opens a visible x.com session using the same persistent WebKit data store
// as the compatibility reply screen. This lets the user sign in once without
// NeoFreeBird reading or copying cookies, credentials, or account data.
BOOL BHTPresentWebReplySignInSetup(
    UIViewController* _Nullable presenter);

// Opens the guarded x.com sign-in/account route in the same visible persistent
// session so the user can review or switch the web account without NeoFreeBird
// reading that account or its cookies.
BOOL BHTPresentWebReplyAccountManager(
    UIViewController* _Nullable presenter);

// Optional, user-confirmed label for the shared web-reply session. NeoFreeBird
// never derives this from cookies, tokens, or the native X account. The label
// stays in local preferences and is excluded from profiles and diagnostics.
FOUNDATION_EXPORT NSNotificationName const
    BHTWebReplyAccountLabelDidChangeNotification;
NSString* _Nullable BHTWebReplyAccountLabel(void);

BOOL BHTWebReplyRouteResultConsumesTap(
    BHTWebReplyRouteResult result);

// Fixed counters and privacy capabilities only. This snapshot never contains
// a URL, post identifier, account, reply text, or raw error.
NSDictionary* BHTWebReplyFallbackDiagnosticSnapshot(void);
