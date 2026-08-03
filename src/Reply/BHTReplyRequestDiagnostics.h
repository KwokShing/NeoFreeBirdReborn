#pragma once

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, BHTReplyRequestConstructorKind) {
    BHTReplyRequestConstructorData = 0,
    BHTReplyRequestConstructorDataCompletion,
    BHTReplyRequestConstructorUploadData,
    BHTReplyRequestConstructorUploadDataCompletion,
    BHTReplyRequestConstructorUploadFile,
    BHTReplyRequestConstructorUploadFileCompletion,
    BHTReplyRequestConstructorKindCount,
};

typedef NS_ENUM(NSUInteger, BHTReplyRequestCompletionHookKind) {
    BHTReplyRequestCompletionHookNone = 0,
    BHTReplyRequestCompletionHookPrivateFinalizer,
    BHTReplyRequestCompletionHookURLSessionDelegate,
    BHTReplyRequestCompletionHookKindCount,
};

// Tags only tasks created inside a tightly correlated native reply window and
// matching an exact first-party host plus CreateTweet operation. The request
// and upload arguments are forwarded unchanged; bodies, headers, cookies,
// tokens, URLs, identifiers, and account objects are never retained or
// exported. URL components and the HTTP method are inspected transiently only
// while the strict native-reply correlation window is active.
void BHTTagPotentialNativeReplyRequest(
    NSURLRequest* _Nullable request,
    NSURLSessionTask* _Nullable task,
    BHTReplyRequestConstructorKind constructorKind);

// Called from X 12.9's guarded TNL completion seam. Only fixed status/error
// categories are recorded; response content and raw errors are never read.
void BHTCompletePotentialNativeReplyRequest(
    NSURLSessionTask* _Nullable task,
    NSError* _Nullable error);

void BHTMarkReplyRequestConstructorHookInstalled(
    BHTReplyRequestConstructorKind constructorKind);
void BHTMarkReplyRequestCompletionHookInstalled(
    BHTReplyRequestCompletionHookKind completionHookKind);
NSDictionary* BHTReplyRequestDiagnosticSnapshot(void);
