#import "Reply/BHTReplyRequestDiagnostics.h"

#import "Compatibility/BHTCompatibilityReporter.h"

#import <objc/runtime.h>
#import <stdatomic.h>

typedef NS_ENUM(NSUInteger, BHTReplyRequestOperationKind) {
    BHTReplyRequestOperationCreateTweet = 0,
    BHTReplyRequestOperationCreateTweetWithUndo,
    BHTReplyRequestOperationKindCount,
};

typedef NS_ENUM(NSUInteger, BHTReplyRequestHostKind) {
    BHTReplyRequestHostAPI = 0,
    BHTReplyRequestHostWeb,
    BHTReplyRequestHostKindCount,
};

typedef NS_ENUM(NSUInteger, BHTReplyRequestHTTPResultKind) {
    BHTReplyRequestHTTPResultNone = 0,
    BHTReplyRequestHTTPResultNonHTTP,
    BHTReplyRequestHTTPResultInformational,
    BHTReplyRequestHTTPResultSuccess,
    BHTReplyRequestHTTPResultRedirect,
    BHTReplyRequestHTTPResultClientFailure,
    BHTReplyRequestHTTPResultServerFailure,
    BHTReplyRequestHTTPResultKindCount,
};

typedef NS_ENUM(NSUInteger, BHTReplyRequestErrorKind) {
    BHTReplyRequestErrorNone = 0,
    BHTReplyRequestErrorCancelled,
    BHTReplyRequestErrorTimedOut,
    BHTReplyRequestErrorOfflineOrConnectivity,
    BHTReplyRequestErrorDNS,
    BHTReplyRequestErrorTLSOrTrust,
    BHTReplyRequestErrorTransportOther,
    BHTReplyRequestErrorNonURLError,
    BHTReplyRequestErrorKindCount,
};

static NSString* const BHTReplyRequestConstructorNames[] = {
    @"dataRequest",
    @"dataRequestCompletion",
    @"uploadData",
    @"uploadDataCompletion",
    @"uploadFile",
    @"uploadFileCompletion",
};
static NSString* const BHTReplyRequestCompletionHookNames[] = {
    @"none",
    @"privateFinalizer",
    @"URLSessionDelegate",
};
static NSString* const BHTReplyRequestOperationNames[] = {
    @"createTweet",
    @"createTweetWithUndo",
};
static NSString* const BHTReplyRequestHostNames[] = {
    @"api",
    @"web",
};
static NSString* const BHTReplyRequestHTTPResultNames[] = {
    @"none",
    @"nonHTTP",
    @"informational1xx",
    @"success2xx",
    @"redirect3xx",
    @"clientFailure4xx",
    @"serverFailure5xx",
};
static NSString* const BHTReplyRequestErrorNames[] = {
    @"none",
    @"cancelled",
    @"timedOut",
    @"offlineOrConnectivity",
    @"dns",
    @"tlsOrTrust",
    @"transportOther",
    @"nonURLError",
};

_Static_assert(
    sizeof(BHTReplyRequestConstructorNames) /
            sizeof(BHTReplyRequestConstructorNames[0]) ==
        BHTReplyRequestConstructorKindCount,
    "Reply request constructor names must match the enum");
_Static_assert(
    sizeof(BHTReplyRequestCompletionHookNames) /
            sizeof(BHTReplyRequestCompletionHookNames[0]) ==
        BHTReplyRequestCompletionHookKindCount,
    "Reply completion hook names must match the enum");
_Static_assert(
    sizeof(BHTReplyRequestOperationNames) /
            sizeof(BHTReplyRequestOperationNames[0]) ==
        BHTReplyRequestOperationKindCount,
    "Reply request operation names must match the enum");
_Static_assert(
    sizeof(BHTReplyRequestHostNames) /
            sizeof(BHTReplyRequestHostNames[0]) ==
        BHTReplyRequestHostKindCount,
    "Reply request host names must match the enum");
_Static_assert(
    sizeof(BHTReplyRequestHTTPResultNames) /
            sizeof(BHTReplyRequestHTTPResultNames[0]) ==
        BHTReplyRequestHTTPResultKindCount,
    "Reply HTTP result names must match the enum");
_Static_assert(
    sizeof(BHTReplyRequestErrorNames) /
            sizeof(BHTReplyRequestErrorNames[0]) ==
        BHTReplyRequestErrorKindCount,
    "Reply request error names must match the enum");

@interface BHTNativeReplyRequestTag : NSObject
@property(nonatomic) BHTReplyRequestConstructorKind constructorKind;
@property(nonatomic) BHTReplyRequestOperationKind operationKind;
@property(nonatomic) BHTReplyRequestHostKind hostKind;
@property(nonatomic) NSUInteger sessionGeneration;
@property(nonatomic) NSTimeInterval startedAt;
@end

@implementation BHTNativeReplyRequestTag
@end

static char BHTNativeReplyRequestTagKey;
static atomic_bool BHTReplyRequestConstructorHooksInstalled;
static atomic_uint BHTReplyRequestCompletionHookInstalled;
static atomic_bool BHTReplyRequestConstructorHookAvailability[
    BHTReplyRequestConstructorKindCount];
static atomic_ulong BHTReplyRequestConstructorCounters[
    BHTReplyRequestConstructorKindCount];
static atomic_ulong BHTReplyRequestOperationCounters[
    BHTReplyRequestOperationKindCount];
static atomic_ulong BHTReplyRequestHostCounters[
    BHTReplyRequestHostKindCount];
static atomic_ulong BHTReplyRequestHTTPResultCounters[
    BHTReplyRequestHTTPResultKindCount];
static atomic_ulong BHTReplyRequestErrorCounters[
    BHTReplyRequestErrorKindCount];
static atomic_ulong BHTReplyRequestTagged;
static atomic_ulong BHTReplyRequestCompleted;
static atomic_ulong BHTReplyRequestObservedInsideWindow;

typedef NS_ENUM(NSUInteger, BHTReplyRequestRejectionKind) {
    BHTReplyRequestRejectionCorrelationExpired = 0,
    BHTReplyRequestRejectionInvalidArguments,
    BHTReplyRequestRejectionNonPOST,
    BHTReplyRequestRejectionOperationMismatch,
    BHTReplyRequestRejectionHostMismatch,
    BHTReplyRequestRejectionDuplicateTask,
    BHTReplyRequestRejectionKindCount,
};

static NSString* const BHTReplyRequestRejectionNames[] = {
    @"correlationExpiredOrInactive",
    @"invalidArguments",
    @"nonPOST",
    @"operationMismatch",
    @"hostMismatch",
    @"duplicateTaskAlreadyTagged",
};

_Static_assert(
    sizeof(BHTReplyRequestRejectionNames) /
            sizeof(BHTReplyRequestRejectionNames[0]) ==
        BHTReplyRequestRejectionKindCount,
    "Reply request rejection names must match the enum");

static atomic_ulong BHTReplyRequestRejectionCounters[
    BHTReplyRequestRejectionKindCount];
static NSMutableArray<NSDictionary*>* BHTReplyRequestRecentAttempts;
static const NSUInteger BHTReplyRequestRecentAttemptLimit = 16;

static NSObject* BHTReplyRequestLock(void) {
    static NSObject* lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static BOOL BHTReplyRequestHostKindForURL(
    NSURL* URL,
    BHTReplyRequestHostKind* kind) {
    if (![URL isKindOfClass:NSURL.class] ||
        ![URL.scheme.lowercaseString isEqualToString:@"https"]) {
        return NO;
    }
    NSString* host = URL.host.lowercaseString;
    if ([host isEqualToString:@"api.twitter.com"] ||
        [host isEqualToString:@"api.x.com"]) {
        if (kind) *kind = BHTReplyRequestHostAPI;
        return YES;
    }
    if ([host isEqualToString:@"twitter.com"] ||
        [host isEqualToString:@"www.twitter.com"] ||
        [host isEqualToString:@"x.com"] ||
        [host isEqualToString:@"www.x.com"]) {
        if (kind) *kind = BHTReplyRequestHostWeb;
        return YES;
    }
    return NO;
}

static BOOL BHTReplyRequestOperationKindForURL(
    NSURL* URL,
    BHTReplyRequestOperationKind* kind) {
    NSString* operation = URL.lastPathComponent;
    if ([operation isEqualToString:@"CreateTweet"]) {
        if (kind) *kind = BHTReplyRequestOperationCreateTweet;
        return YES;
    }
    if ([operation isEqualToString:@"CreateTweetWithUndo"]) {
        if (kind) {
            *kind = BHTReplyRequestOperationCreateTweetWithUndo;
        }
        return YES;
    }
    return NO;
}

static BHTReplyRequestHTTPResultKind BHTReplyRequestHTTPResult(
    NSURLResponse* response) {
    if (!response) return BHTReplyRequestHTTPResultNone;
    if (![response isKindOfClass:NSHTTPURLResponse.class]) {
        return BHTReplyRequestHTTPResultNonHTTP;
    }
    NSInteger statusClass =
        ((NSHTTPURLResponse*)response).statusCode / 100;
    switch (statusClass) {
        case 1:
            return BHTReplyRequestHTTPResultInformational;
        case 2:
            return BHTReplyRequestHTTPResultSuccess;
        case 3:
            return BHTReplyRequestHTTPResultRedirect;
        case 4:
            return BHTReplyRequestHTTPResultClientFailure;
        case 5:
            return BHTReplyRequestHTTPResultServerFailure;
        default:
            return BHTReplyRequestHTTPResultNonHTTP;
    }
}

static BHTReplyRequestErrorKind BHTReplyRequestError(
    NSError* error) {
    if (!error) return BHTReplyRequestErrorNone;
    if (![error isKindOfClass:NSError.class] ||
        ![error.domain isEqualToString:NSURLErrorDomain]) {
        return BHTReplyRequestErrorNonURLError;
    }
    switch (error.code) {
        case NSURLErrorCancelled:
            return BHTReplyRequestErrorCancelled;
        case NSURLErrorTimedOut:
            return BHTReplyRequestErrorTimedOut;
        case NSURLErrorNotConnectedToInternet:
        case NSURLErrorCannotConnectToHost:
        case NSURLErrorNetworkConnectionLost:
            return BHTReplyRequestErrorOfflineOrConnectivity;
        case NSURLErrorCannotFindHost:
        case NSURLErrorDNSLookupFailed:
            return BHTReplyRequestErrorDNS;
        case NSURLErrorSecureConnectionFailed:
        case NSURLErrorServerCertificateHasBadDate:
        case NSURLErrorServerCertificateUntrusted:
        case NSURLErrorServerCertificateHasUnknownRoot:
        case NSURLErrorServerCertificateNotYetValid:
        case NSURLErrorClientCertificateRejected:
        case NSURLErrorClientCertificateRequired:
            return BHTReplyRequestErrorTLSOrTrust;
        default:
            return BHTReplyRequestErrorTransportOther;
    }
}

static NSString* BHTReplyRequestDurationBucket(
    NSTimeInterval elapsed) {
    if (elapsed < 0.25) return @"under250ms";
    if (elapsed < 1.0) return @"250msTo999ms";
    if (elapsed < 3.0) return @"1sTo2.999s";
    if (elapsed < 10.0) return @"3sTo9.999s";
    return @"10sOrMore";
}

void BHTTagPotentialNativeReplyRequest(
    NSURLRequest* request,
    NSURLSessionTask* task,
    BHTReplyRequestConstructorKind constructorKind) {
    if (!BHTReplyWorkflowNetworkDiagnosticWindowMayBeActive()) {
        return;
    }
    if (constructorKind >= BHTReplyRequestConstructorKindCount) {
        return;
    }
    atomic_fetch_add_explicit(
        &BHTReplyRequestObservedInsideWindow, 1,
        memory_order_relaxed);

    NSUInteger sessionGeneration = 0;
    if (!BHTReplyWorkflowDiagnosticSessionForNetworkRequest(
            &sessionGeneration)) {
        atomic_fetch_add_explicit(
            &BHTReplyRequestRejectionCounters[
                BHTReplyRequestRejectionCorrelationExpired],
            1, memory_order_relaxed);
        return;
    }
    if (![request isKindOfClass:NSURLRequest.class] ||
        ![task isKindOfClass:NSURLSessionTask.class] ||
        ![request.URL isKindOfClass:NSURL.class]) {
        atomic_fetch_add_explicit(
            &BHTReplyRequestRejectionCounters[
                BHTReplyRequestRejectionInvalidArguments],
            1, memory_order_relaxed);
        return;
    }
    if (![request.HTTPMethod.uppercaseString
            isEqualToString:@"POST"]) {
        atomic_fetch_add_explicit(
            &BHTReplyRequestRejectionCounters[
                BHTReplyRequestRejectionNonPOST],
            1, memory_order_relaxed);
        return;
    }

    BHTReplyRequestOperationKind operationKind;
    if (!BHTReplyRequestOperationKindForURL(
            request.URL, &operationKind)) {
        atomic_fetch_add_explicit(
            &BHTReplyRequestRejectionCounters[
                BHTReplyRequestRejectionOperationMismatch],
            1, memory_order_relaxed);
        return;
    }
    BHTReplyRequestHostKind hostKind;
    if (!BHTReplyRequestHostKindForURL(
            request.URL, &hostKind)) {
        atomic_fetch_add_explicit(
            &BHTReplyRequestRejectionCounters[
                BHTReplyRequestRejectionHostMismatch],
            1, memory_order_relaxed);
        return;
    }
    if ([objc_getAssociatedObject(
            task, &BHTNativeReplyRequestTagKey)
            isKindOfClass:BHTNativeReplyRequestTag.class]) {
        atomic_fetch_add_explicit(
            &BHTReplyRequestRejectionCounters[
                BHTReplyRequestRejectionDuplicateTask],
            1, memory_order_relaxed);
        return;
    }

    BHTNativeReplyRequestTag* tag =
        [BHTNativeReplyRequestTag new];
    tag.constructorKind = constructorKind;
    tag.operationKind = operationKind;
    tag.hostKind = hostKind;
    tag.sessionGeneration = sessionGeneration;
    tag.startedAt = NSProcessInfo.processInfo.systemUptime;
    objc_setAssociatedObject(
        task, &BHTNativeReplyRequestTagKey, tag,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    atomic_fetch_add_explicit(
        &BHTReplyRequestTagged, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(
        &BHTReplyRequestConstructorCounters[constructorKind], 1,
        memory_order_relaxed);
    atomic_fetch_add_explicit(
        &BHTReplyRequestOperationCounters[operationKind], 1,
        memory_order_relaxed);
    atomic_fetch_add_explicit(
        &BHTReplyRequestHostCounters[hostKind], 1,
        memory_order_relaxed);
}

void BHTCompletePotentialNativeReplyRequest(
    NSURLSessionTask* task,
    NSError* error) {
    if (![task isKindOfClass:NSURLSessionTask.class]) return;
    BHTNativeReplyRequestTag* tag =
        objc_getAssociatedObject(
            task, &BHTNativeReplyRequestTagKey);
    if (![tag isKindOfClass:BHTNativeReplyRequestTag.class]) {
        return;
    }
    objc_setAssociatedObject(
        task, &BHTNativeReplyRequestTagKey, nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    BHTReplyRequestHTTPResultKind HTTPResult =
        BHTReplyRequestHTTPResult(task.response);
    BHTReplyRequestErrorKind errorResult =
        BHTReplyRequestError(error);
    NSTimeInterval elapsed = MAX(
        0.0,
        NSProcessInfo.processInfo.systemUptime - tag.startedAt);
    unsigned long completedSequence =
        atomic_fetch_add_explicit(
            &BHTReplyRequestCompleted, 1,
            memory_order_relaxed) + 1;
    atomic_fetch_add_explicit(
        &BHTReplyRequestHTTPResultCounters[HTTPResult], 1,
        memory_order_relaxed);
    atomic_fetch_add_explicit(
        &BHTReplyRequestErrorCounters[errorResult], 1,
        memory_order_relaxed);

    NSDictionary* attempt = @{
        @"sequence":
            @(completedSequence),
        @"operation":
            BHTReplyRequestOperationNames[tag.operationKind],
        @"taskConstructor":
            BHTReplyRequestConstructorNames[tag.constructorKind],
        @"hostCategory":
            BHTReplyRequestHostNames[tag.hostKind],
        @"activeForwardedReplyWindow": @YES,
        @"sessionGeneration": @(tag.sessionGeneration),
        @"durationBucket":
            BHTReplyRequestDurationBucket(elapsed),
        @"httpClass":
            BHTReplyRequestHTTPResultNames[HTTPResult],
        @"errorCategory":
            BHTReplyRequestErrorNames[errorResult],
    };
    @synchronized(BHTReplyRequestLock()) {
        if (!BHTReplyRequestRecentAttempts) {
            BHTReplyRequestRecentAttempts =
                [NSMutableArray arrayWithCapacity:
                    BHTReplyRequestRecentAttemptLimit];
        }
        if (BHTReplyRequestRecentAttempts.count >=
            BHTReplyRequestRecentAttemptLimit) {
            [BHTReplyRequestRecentAttempts
                removeObjectAtIndex:0];
        }
        [BHTReplyRequestRecentAttempts addObject:attempt];
    }
}

void BHTMarkReplyRequestConstructorHookInstalled(
    BHTReplyRequestConstructorKind constructorKind) {
    if (constructorKind >= BHTReplyRequestConstructorKindCount) {
        return;
    }
    atomic_store_explicit(
        &BHTReplyRequestConstructorHookAvailability[constructorKind],
        true, memory_order_release);
    atomic_store_explicit(
        &BHTReplyRequestConstructorHooksInstalled,
        true, memory_order_release);
}

void BHTMarkReplyRequestCompletionHookInstalled(
    BHTReplyRequestCompletionHookKind completionHookKind) {
    if (completionHookKind <= BHTReplyRequestCompletionHookNone ||
        completionHookKind >=
            BHTReplyRequestCompletionHookKindCount) {
        return;
    }
    atomic_store_explicit(
        &BHTReplyRequestCompletionHookInstalled,
        (unsigned int)completionHookKind,
        memory_order_release);
}

static NSDictionary* BHTReplyRequestCounterDictionary(
    NSString* const names[],
    atomic_ulong counters[],
    NSUInteger count) {
    NSMutableDictionary* snapshot =
        [NSMutableDictionary dictionaryWithCapacity:count];
    for (NSUInteger index = 0; index < count; index++) {
        snapshot[names[index]] =
            @(atomic_load_explicit(
                &counters[index], memory_order_relaxed));
    }
    return [snapshot copy];
}

static NSDictionary* BHTReplyRequestAvailabilityDictionary(void) {
    NSMutableDictionary* snapshot =
        [NSMutableDictionary dictionaryWithCapacity:
            BHTReplyRequestConstructorKindCount];
    for (NSUInteger index = 0;
         index < BHTReplyRequestConstructorKindCount; index++) {
        snapshot[BHTReplyRequestConstructorNames[index]] =
            @(atomic_load_explicit(
                &BHTReplyRequestConstructorHookAvailability[index],
                memory_order_acquire));
    }
    return [snapshot copy];
}

NSDictionary* BHTReplyRequestDiagnosticSnapshot(void) {
    NSArray* attempts;
    @synchronized(BHTReplyRequestLock()) {
        attempts = [BHTReplyRequestRecentAttempts copy] ?: @[];
    }
    unsigned int completionHook = atomic_load_explicit(
        &BHTReplyRequestCompletionHookInstalled,
        memory_order_acquire);
    if (completionHook >=
        BHTReplyRequestCompletionHookKindCount) {
        completionHook = BHTReplyRequestCompletionHookNone;
    }
    return @{
        @"constructorHooksInstalled":
            @(atomic_load_explicit(
                &BHTReplyRequestConstructorHooksInstalled,
                memory_order_acquire)),
        @"constructorHookAvailability":
            BHTReplyRequestAvailabilityDictionary(),
        @"completionHookInstalled":
            @(completionHook !=
                BHTReplyRequestCompletionHookNone),
        @"completionHook":
            BHTReplyRequestCompletionHookNames[completionHook],
        @"policy":
            @"known_create_operation_active_forwarded_reply_window",
        @"constructorCounters":
            BHTReplyRequestCounterDictionary(
                BHTReplyRequestConstructorNames,
                BHTReplyRequestConstructorCounters,
                BHTReplyRequestConstructorKindCount),
        @"constructorCallsWhileWindowHintOpen":
            @(atomic_load_explicit(
                &BHTReplyRequestObservedInsideWindow,
                memory_order_relaxed)),
        @"candidateRejectionCounters":
            BHTReplyRequestCounterDictionary(
                BHTReplyRequestRejectionNames,
                BHTReplyRequestRejectionCounters,
                BHTReplyRequestRejectionKindCount),
        @"operationCounters":
            BHTReplyRequestCounterDictionary(
                BHTReplyRequestOperationNames,
                BHTReplyRequestOperationCounters,
                BHTReplyRequestOperationKindCount),
        @"hostCategoryCounters":
            BHTReplyRequestCounterDictionary(
                BHTReplyRequestHostNames,
                BHTReplyRequestHostCounters,
                BHTReplyRequestHostKindCount),
        @"httpClassCounters":
            BHTReplyRequestCounterDictionary(
                BHTReplyRequestHTTPResultNames,
                BHTReplyRequestHTTPResultCounters,
                BHTReplyRequestHTTPResultKindCount),
        @"errorCategoryCounters":
            BHTReplyRequestCounterDictionary(
                BHTReplyRequestErrorNames,
                BHTReplyRequestErrorCounters,
                BHTReplyRequestErrorKindCount),
        @"tasksTagged":
            @(atomic_load_explicit(
                &BHTReplyRequestTagged,
                memory_order_relaxed)),
        @"tasksCompleted":
            @(atomic_load_explicit(
                &BHTReplyRequestCompleted,
                memory_order_relaxed)),
        @"taggedTasksWithoutObservedCompletion":
            @(MAX(
                (long)atomic_load_explicit(
                    &BHTReplyRequestTagged,
                    memory_order_relaxed) -
                    (long)atomic_load_explicit(
                        &BHTReplyRequestCompleted,
                        memory_order_relaxed),
                0L)),
        @"recentAttempts": attempts,
        @"recentAttemptLimit":
            @(BHTReplyRequestRecentAttemptLimit),
        @"correlationScope": @"process_temporal_strict",
        @"constructorToCompletionTimingIncludesQueueDelay": @YES,
        @"graphQLApplicationErrorsInsideHTTP2xxAreUnobservedByThisLayer":
            @YES,
        @"graphQLApplicationDiagnosticIncludedSeparately": @YES,
        @"strictHTTPSHostAllowlist": @YES,
        @"requestForwardedUnchanged": @YES,
        @"capturesRequestBodies": @NO,
        @"capturesUploadDataOrFileURLs": @NO,
        @"capturesRequestHeaders": @NO,
        @"capturesCookiesOrTokens": @NO,
        @"capturesURLs": @NO,
        @"capturesResponseContents": @NO,
        @"capturesAccountData": @NO,
        @"capturesIdentifiers": @NO,
        @"capturesRawErrors": @NO,
    };
}
