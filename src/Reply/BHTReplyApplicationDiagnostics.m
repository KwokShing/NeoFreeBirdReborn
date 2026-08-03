#import "Reply/BHTReplyApplicationDiagnostics.h"

#import <stdatomic.h>

typedef NS_ENUM(NSUInteger, BHTNativeReplyApplicationOperation) {
    BHTNativeReplyApplicationOperationCreateTweet = 0,
    BHTNativeReplyApplicationOperationCreateTweetWithUndo,
    BHTNativeReplyApplicationOperationCount,
};

typedef NS_ENUM(NSUInteger, BHTNativeReplyAPIErrorState) {
    BHTNativeReplyAPIErrorStateAbsent = 0,
    BHTNativeReplyAPIErrorStateEmptyCollection,
    BHTNativeReplyAPIErrorStateNonemptyCollection,
    BHTNativeReplyAPIErrorStateUnexpectedPresentObject,
    BHTNativeReplyAPIErrorStateCount,
};

typedef NS_ENUM(NSUInteger, BHTNativeReplyDecodedOutcome) {
    BHTNativeReplyDecodedOutcomeModelPresent = 0,
    BHTNativeReplyDecodedOutcomeAPIErrors,
    BHTNativeReplyDecodedOutcomeParseError,
    BHTNativeReplyDecodedOutcomeParseAndAPIErrors,
    BHTNativeReplyDecodedOutcomeModelAndAPIErrors,
    BHTNativeReplyDecodedOutcomeModelAndParseError,
    BHTNativeReplyDecodedOutcomeModelParseAndAPIErrors,
    BHTNativeReplyDecodedOutcomeEmptyResult,
    BHTNativeReplyDecodedOutcomeCount,
};

typedef NS_ENUM(NSUInteger, BHTNativeReplyApplicationRejection) {
    BHTNativeReplyApplicationRejectionZeroGeneration = 0,
    BHTNativeReplyApplicationRejectionInvalidURL,
    BHTNativeReplyApplicationRejectionOperationMismatch,
    BHTNativeReplyApplicationRejectionHostMismatch,
    BHTNativeReplyApplicationRejectionCount,
};

static NSString* const BHTNativeReplyApplicationOperationNames[] = {
    @"createTweet",
    @"createTweetWithUndo",
};
static NSString* const BHTNativeReplyAPIErrorStateNames[] = {
    @"absent",
    @"emptyCollection",
    @"nonemptyCollection",
    @"unexpectedPresentObject",
};
static NSString* const BHTNativeReplyDecodedOutcomeNames[] = {
    @"modelPresentNoParseOrAPIOutParamError",
    @"apiErrorsOutParamPresent",
    @"parseErrorOutParamPresent",
    @"parseAndAPIErrorsOutParamsPresent",
    @"modelAndAPIErrorsOutParamPresent",
    @"modelAndParseErrorOutParamPresent",
    @"modelParseAndAPIErrorsOutParamsPresent",
    @"emptyDecodedResult",
};
static NSString* const BHTNativeReplyApplicationRejectionNames[] = {
    @"zeroGeneration",
    @"invalidURL",
    @"operationMismatch",
    @"hostMismatch",
};

_Static_assert(
    sizeof(BHTNativeReplyApplicationOperationNames) /
            sizeof(BHTNativeReplyApplicationOperationNames[0]) ==
        BHTNativeReplyApplicationOperationCount,
    "Native reply application operation names must match the enum");
_Static_assert(
    sizeof(BHTNativeReplyAPIErrorStateNames) /
            sizeof(BHTNativeReplyAPIErrorStateNames[0]) ==
        BHTNativeReplyAPIErrorStateCount,
    "Native reply API error state names must match the enum");
_Static_assert(
    sizeof(BHTNativeReplyDecodedOutcomeNames) /
            sizeof(BHTNativeReplyDecodedOutcomeNames[0]) ==
        BHTNativeReplyDecodedOutcomeCount,
    "Native reply decoded outcome names must match the enum");
_Static_assert(
    sizeof(BHTNativeReplyApplicationRejectionNames) /
            sizeof(BHTNativeReplyApplicationRejectionNames[0]) ==
        BHTNativeReplyApplicationRejectionCount,
    "Native reply application rejection names must match the enum");

static atomic_bool BHTNativeReplyApplicationHookInstalled;
static atomic_ulong BHTNativeReplyApplicationCandidateCalls;
static atomic_ulong BHTNativeReplyApplicationAcceptedCalls;
static atomic_ulong BHTNativeReplyApplicationOutcomeCounters[
    BHTNativeReplyDecodedOutcomeCount];
static atomic_ulong BHTNativeReplyApplicationOperationCounters[
    BHTNativeReplyApplicationOperationCount];
static atomic_ulong BHTNativeReplyApplicationRejectionCounters[
    BHTNativeReplyApplicationRejectionCount];
static NSMutableArray<NSDictionary*>*
    BHTNativeReplyApplicationRecentAttempts;
static const NSUInteger BHTNativeReplyApplicationAttemptLimit = 8;

static NSObject* BHTNativeReplyApplicationLock(void) {
    static NSObject* lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static BOOL BHTNativeReplyApplicationOperationForURL(
    NSURL* URL,
    BHTNativeReplyApplicationOperation* operation) {
    if (![URL isKindOfClass:NSURL.class] ||
        ![URL.scheme.lowercaseString isEqualToString:@"https"]) {
        return NO;
    }
    NSString* lastComponent = URL.lastPathComponent;
    if ([lastComponent isEqualToString:@"CreateTweet"]) {
        if (operation) {
            *operation =
                BHTNativeReplyApplicationOperationCreateTweet;
        }
        return YES;
    }
    if ([lastComponent
            isEqualToString:@"CreateTweetWithUndo"]) {
        if (operation) {
            *operation =
                BHTNativeReplyApplicationOperationCreateTweetWithUndo;
        }
        return YES;
    }
    return NO;
}

static BOOL BHTNativeReplyApplicationHostIsAllowed(
    NSURL* URL) {
    NSString* host = URL.host.lowercaseString;
    return [host isEqualToString:@"api.twitter.com"] ||
           [host isEqualToString:@"api.x.com"];
}

static BHTNativeReplyAPIErrorState
BHTNativeReplyAPIErrorStateForObject(id APIErrors) {
    if (!APIErrors) {
        return BHTNativeReplyAPIErrorStateAbsent;
    }
    if (![APIErrors isKindOfClass:NSArray.class]) {
        return BHTNativeReplyAPIErrorStateUnexpectedPresentObject;
    }
    return [(NSArray*)APIErrors count] == 0
        ? BHTNativeReplyAPIErrorStateEmptyCollection
        : BHTNativeReplyAPIErrorStateNonemptyCollection;
}

static BOOL BHTNativeReplyAPIErrorStateHasErrors(
    BHTNativeReplyAPIErrorState state) {
    return state == BHTNativeReplyAPIErrorStateNonemptyCollection ||
           state ==
               BHTNativeReplyAPIErrorStateUnexpectedPresentObject;
}

static BHTNativeReplyDecodedOutcome BHTNativeReplyDecodedOutcomeFor(
    BOOL modelPresent,
    BOOL parseErrorPresent,
    BOOL APIErrorsPresent) {
    if (modelPresent && parseErrorPresent && APIErrorsPresent) {
        return BHTNativeReplyDecodedOutcomeModelParseAndAPIErrors;
    }
    if (modelPresent && parseErrorPresent) {
        return BHTNativeReplyDecodedOutcomeModelAndParseError;
    }
    if (modelPresent && APIErrorsPresent) {
        return BHTNativeReplyDecodedOutcomeModelAndAPIErrors;
    }
    if (parseErrorPresent && APIErrorsPresent) {
        return BHTNativeReplyDecodedOutcomeParseAndAPIErrors;
    }
    if (parseErrorPresent) {
        return BHTNativeReplyDecodedOutcomeParseError;
    }
    if (APIErrorsPresent) {
        return BHTNativeReplyDecodedOutcomeAPIErrors;
    }
    if (modelPresent) {
        return BHTNativeReplyDecodedOutcomeModelPresent;
    }
    return BHTNativeReplyDecodedOutcomeEmptyResult;
}

void BHTRecordNativeReplyApplicationResult(
    NSUInteger sessionGeneration,
    NSURL* requestURL,
    id model,
    id parseError,
    id APIErrors) {
    atomic_fetch_add_explicit(
        &BHTNativeReplyApplicationCandidateCalls, 1,
        memory_order_relaxed);
    if (sessionGeneration == 0) {
        atomic_fetch_add_explicit(
            &BHTNativeReplyApplicationRejectionCounters[
                BHTNativeReplyApplicationRejectionZeroGeneration],
            1, memory_order_relaxed);
        return;
    }
    if (![requestURL isKindOfClass:NSURL.class]) {
        atomic_fetch_add_explicit(
            &BHTNativeReplyApplicationRejectionCounters[
                BHTNativeReplyApplicationRejectionInvalidURL],
            1, memory_order_relaxed);
        return;
    }

    BHTNativeReplyApplicationOperation operation;
    if (!BHTNativeReplyApplicationOperationForURL(
            requestURL, &operation)) {
        atomic_fetch_add_explicit(
            &BHTNativeReplyApplicationRejectionCounters[
                BHTNativeReplyApplicationRejectionOperationMismatch],
            1, memory_order_relaxed);
        return;
    }
    if (!BHTNativeReplyApplicationHostIsAllowed(requestURL)) {
        atomic_fetch_add_explicit(
            &BHTNativeReplyApplicationRejectionCounters[
                BHTNativeReplyApplicationRejectionHostMismatch],
            1, memory_order_relaxed);
        return;
    }

    BOOL modelPresent = model != nil;
    BOOL parseErrorPresent = parseError != nil;
    BHTNativeReplyAPIErrorState APIErrorState =
        BHTNativeReplyAPIErrorStateForObject(APIErrors);
    BOOL APIErrorsPresent =
        BHTNativeReplyAPIErrorStateHasErrors(APIErrorState);
    BHTNativeReplyDecodedOutcome outcome =
        BHTNativeReplyDecodedOutcomeFor(
            modelPresent, parseErrorPresent, APIErrorsPresent);

    atomic_fetch_add_explicit(
        &BHTNativeReplyApplicationAcceptedCalls, 1,
        memory_order_relaxed);
    atomic_fetch_add_explicit(
        &BHTNativeReplyApplicationOutcomeCounters[outcome],
        1, memory_order_relaxed);
    atomic_fetch_add_explicit(
        &BHTNativeReplyApplicationOperationCounters[operation],
        1, memory_order_relaxed);

    NSDictionary* attempt = @{
        @"sessionGeneration": @(sessionGeneration),
        @"operation":
            BHTNativeReplyApplicationOperationNames[operation],
        @"decodedOutcome":
            BHTNativeReplyDecodedOutcomeNames[outcome],
        @"modelPresent": @(modelPresent),
        @"parseErrorPresent": @(parseErrorPresent),
        @"apiErrorsState":
            BHTNativeReplyAPIErrorStateNames[APIErrorState],
    };
    @synchronized(BHTNativeReplyApplicationLock()) {
        if (!BHTNativeReplyApplicationRecentAttempts) {
            BHTNativeReplyApplicationRecentAttempts =
                [NSMutableArray arrayWithCapacity:
                    BHTNativeReplyApplicationAttemptLimit];
        }
        if (BHTNativeReplyApplicationRecentAttempts.count >=
            BHTNativeReplyApplicationAttemptLimit) {
            [BHTNativeReplyApplicationRecentAttempts
                removeObjectAtIndex:0];
        }
        [BHTNativeReplyApplicationRecentAttempts
            addObject:attempt];
    }
}

void BHTMarkNativeReplyApplicationHookInstalled(void) {
    atomic_store_explicit(
        &BHTNativeReplyApplicationHookInstalled,
        true, memory_order_release);
}

static NSDictionary* BHTNativeReplyApplicationCounterDictionary(
    NSString* const names[],
    atomic_ulong counters[],
    NSUInteger count) {
    NSMutableDictionary* result =
        [NSMutableDictionary dictionaryWithCapacity:count];
    for (NSUInteger index = 0; index < count; index++) {
        result[names[index]] =
            @(atomic_load_explicit(
                &counters[index], memory_order_relaxed));
    }
    return [result copy];
}

NSDictionary* BHTNativeReplyApplicationDiagnosticSnapshot(void) {
    NSArray* attempts;
    @synchronized(BHTNativeReplyApplicationLock()) {
        attempts =
            [BHTNativeReplyApplicationRecentAttempts copy] ?: @[];
    }
    return @{
        @"decodeHookInstalled":
            @(atomic_load_explicit(
                &BHTNativeReplyApplicationHookInstalled,
                memory_order_acquire)),
        @"candidateCallsDuringForwardedReply":
            @(atomic_load_explicit(
                &BHTNativeReplyApplicationCandidateCalls,
                memory_order_relaxed)),
        @"acceptedCreateTweetResults":
            @(atomic_load_explicit(
                &BHTNativeReplyApplicationAcceptedCalls,
                memory_order_relaxed)),
        @"outcomeCounters":
            BHTNativeReplyApplicationCounterDictionary(
                BHTNativeReplyDecodedOutcomeNames,
                BHTNativeReplyApplicationOutcomeCounters,
                BHTNativeReplyDecodedOutcomeCount),
        @"operationCounters":
            BHTNativeReplyApplicationCounterDictionary(
                BHTNativeReplyApplicationOperationNames,
                BHTNativeReplyApplicationOperationCounters,
                BHTNativeReplyApplicationOperationCount),
        @"rejectionCounters":
            BHTNativeReplyApplicationCounterDictionary(
                BHTNativeReplyApplicationRejectionNames,
                BHTNativeReplyApplicationRejectionCounters,
                BHTNativeReplyApplicationRejectionCount),
        @"recentAttempts": attempts,
        @"recentAttemptLimit":
            @(BHTNativeReplyApplicationAttemptLimit),
        @"source": @"x_decoded_graphql_out_parameters",
        @"http2xxDoesNotImplyApplicationSuccess": @YES,
        @"correlationScope": @"process_temporal_operation_only",
        @"requestIdentityBound": @NO,
        @"applicationSuccessIsNotInferred": @YES,
        @"strictHTTPSAPIHostAndOperationAllowlist": @YES,
        @"sanitizedAttemptsPersistWhenReportIsWritten": @YES,
        @"capturesResponseBodies": @NO,
        @"capturesResponseMessages": @NO,
        @"capturesRawErrors": @NO,
        @"capturesErrorDescriptionsOrUserInfo": @NO,
        @"capturesURLs": @NO,
        @"capturesHeadersCookiesOrTokens": @NO,
        @"capturesTweetOrReplyText": @NO,
        @"capturesIdentifiers": @NO,
        @"capturesAccountData": @NO,
        @"inspectsAPIErrorCollectionElements": @NO,
        @"persistsDecodedObjects": @NO,
        @"exportsDecodedObjects": @NO,
    };
}
