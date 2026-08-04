#pragma once

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, BHTNativeReplyFailureSource) {
    BHTNativeReplyFailureSourceOutboxProcess = 0,
    BHTNativeReplyFailureSourceCompositionSend,
    BHTNativeReplyFailureSourceCount,
};

// Resolves X 12.9's exact exported failure-error key and its fixed action-error
// classifier bridges. A partial classifier set is never used.
void BHTPrepareNativeReplyFailureDiagnostics(void);

// The caller must pass only a process-local reply generation. Generation zero
// is rejected before the notification or its user-info dictionary is touched.
// The notification and error remain transient; only fixed categories persist.
void BHTObserveNativeReplyFailureNotification(
    NSUInteger sessionGeneration,
    BHTNativeReplyFailureSource source,
    NSNotification* _Nullable notification);

NSDictionary* BHTNativeReplyFailureDiagnosticSnapshot(void);
