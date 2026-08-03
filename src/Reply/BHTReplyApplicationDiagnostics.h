#pragma once

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, BHTNativeReplyModelStructureState) {
    BHTNativeReplyModelStructureStateLayoutUnavailable = 0,
    BHTNativeReplyModelStructureStateUnexpectedModelClass,
    BHTNativeReplyModelStructureStateMissingCreateTweet,
    BHTNativeReplyModelStructureStateUnexpectedCreateTweetClass,
    BHTNativeReplyModelStructureStateMissingTweetResults,
    BHTNativeReplyModelStructureStatePayloadPresent,
    BHTNativeReplyModelStructureStateCount,
};

// Called only after X 12.9 has decoded a GraphQL endpoint response. The URL is
// used transiently to accept exact first-party CreateTweet operations. Model
// and error objects are reduced synchronously to fixed presence categories and
// are never stored in diagnostic state, logged, or exported.
void BHTRecordNativeReplyApplicationResult(
    NSUInteger sessionGeneration,
    NSURL* _Nullable requestURL,
    id _Nullable model,
    id _Nullable parseError,
    id _Nullable APIErrors,
    BHTNativeReplyModelStructureState modelStructureState);

// Transiently applies the same exact scheme/host/operation allowlist used by
// the recorder, so prepared-response getters are never invoked for unrelated
// GraphQL traffic during the short correlation window.
BOOL BHTNativeReplyApplicationRequestURLIsEligible(
    NSURL* _Nullable requestURL);

// Called after X 12.9 finishes preparing the endpoint response. Effective and
// final values are reduced synchronously to fixed presence categories. The
// objects themselves and all error contents remain local to the hook frame.
void BHTRecordNativeReplyPreparedResponse(
    NSUInteger sessionGeneration,
    NSURL* _Nullable requestURL,
    BOOL observationComplete,
    id _Nullable effectiveModel,
    id _Nullable effectiveParseError,
    id _Nullable effectiveOperationError,
    id _Nullable effectiveAPIErrors,
    id _Nullable finalModel,
    id _Nullable finalParseError,
    id _Nullable finalOperationError,
    id _Nullable finalAPIErrors);

void BHTMarkNativeReplyApplicationHookInstalled(void);
void BHTMarkNativeReplyPreparedHookInstalled(void);
void BHTMarkNativeReplyModelStructureLayoutAvailable(void);
NSDictionary* BHTNativeReplyApplicationDiagnosticSnapshot(void);
