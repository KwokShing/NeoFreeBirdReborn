#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, BHTAccountBoundWebReplyResult) {
    BHTAccountBoundWebReplyResultUnavailable = 0,
    BHTAccountBoundWebReplyResultPresented,
    BHTAccountBoundWebReplyResultAlreadyPresented,
};

// Attempts X 12.9's own visible web controller, passes the exact account object
// delivered to the inline reply handler, and requests X authentication. Object
// identity verifies controller wiring but not the server-side web account.
// NeoFreeBird does not inspect account details, credentials, cookies, request
// contents, or page contents and does not separately persist or export them.
BHTAccountBoundWebReplyResult BHTTryPresentAccountBoundWebReply(
    NSURL* _Nullable replyURL,
    id _Nullable account,
    UIViewController* _Nullable presenter);

BOOL BHTAccountBoundWebReplyOwnsController(id _Nullable controller);
void BHTMarkAccountBoundWebReplyKeepInWebviewHookInstalled(void);
void BHTRecordAccountBoundWebReplyCustomFallback(BOOL presented);
NSDictionary* BHTAccountBoundWebReplyDiagnosticSnapshot(void);
