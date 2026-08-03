#pragma once

#import <Foundation/Foundation.h>

// Called only after X 12.9 has decoded a GraphQL endpoint response. The URL is
// used transiently to accept exact first-party CreateTweet operations. Model
// and error objects are reduced synchronously to fixed presence categories and
// are never stored in diagnostic state, logged, or exported.
void BHTRecordNativeReplyApplicationResult(
    NSUInteger sessionGeneration,
    NSURL* _Nullable requestURL,
    id _Nullable model,
    id _Nullable parseError,
    id _Nullable APIErrors);

void BHTMarkNativeReplyApplicationHookInstalled(void);
NSDictionary* BHTNativeReplyApplicationDiagnosticSnapshot(void);
