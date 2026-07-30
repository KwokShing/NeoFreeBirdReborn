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
// evaluated. No host model is retained and no identifier, account, or draft
// text is persisted or added to diagnostics. The reply URL exists only while
// the visible composer is open.
BHTWebReplyRouteResult BHTTryPresentWebReplyFallback(
    id _Nullable sourceObject,
    UIViewController* _Nullable presenter);

BOOL BHTWebReplyRouteResultConsumesTap(
    BHTWebReplyRouteResult result);

// Fixed counters and privacy capabilities only. This snapshot never contains
// a URL, post identifier, account, reply text, or raw error.
NSDictionary* BHTWebReplyFallbackDiagnosticSnapshot(void);
