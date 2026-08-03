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

typedef NS_ENUM(NSUInteger, BHTNativeReplyPreparedErrorState) {
    BHTNativeReplyPreparedErrorStateNone = 0,
    BHTNativeReplyPreparedErrorStateOperationOnly,
    BHTNativeReplyPreparedErrorStateParseOnly,
    BHTNativeReplyPreparedErrorStateAPIOnly,
    BHTNativeReplyPreparedErrorStateMultiple,
    BHTNativeReplyPreparedErrorStateCount,
};

typedef NS_ENUM(NSUInteger, BHTNativeReplyFinalValueState) {
    BHTNativeReplyFinalValueStateUnset = 0,
    BHTNativeReplyFinalValueStateExplicitlyAbsent,
    BHTNativeReplyFinalValueStateObjectPresent,
    BHTNativeReplyFinalValueStateCount,
};

typedef NS_ENUM(NSUInteger, BHTNativeReplyFinalAPIErrorState) {
    BHTNativeReplyFinalAPIErrorStateUnset = 0,
    BHTNativeReplyFinalAPIErrorStateExplicitlyAbsent,
    BHTNativeReplyFinalAPIErrorStateEmptyCollection,
    BHTNativeReplyFinalAPIErrorStateNonemptyCollection,
    BHTNativeReplyFinalAPIErrorStateUnexpectedPresentObject,
    BHTNativeReplyFinalAPIErrorStateCount,
};

typedef NS_ENUM(NSUInteger, BHTNativeReplyPreparedObservationState) {
    BHTNativeReplyPreparedObservationStateComplete = 0,
    BHTNativeReplyPreparedObservationStateGetterFailed,
    BHTNativeReplyPreparedObservationStateCount,
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
static NSString* const BHTNativeReplyModelStructureStateNames[] = {
    @"layoutUnavailable",
    @"unexpectedModelClass",
    @"missingCreateTweet",
    @"unexpectedCreateTweetClass",
    @"missingTweetResults",
    @"structuralPayloadPresent",
};
static NSString* const BHTNativeReplyPreparedErrorStateNames[] = {
    @"none",
    @"operationOnly",
    @"parseOnly",
    @"apiOnly",
    @"multiple",
};
static NSString* const BHTNativeReplyFinalValueStateNames[] = {
    @"unset",
    @"explicitlyAbsent",
    @"objectPresent",
};
static NSString* const BHTNativeReplyFinalAPIErrorStateNames[] = {
    @"unset",
    @"explicitlyAbsent",
    @"emptyCollection",
    @"nonemptyCollection",
    @"unexpectedPresentObject",
};
static NSString* const BHTNativeReplyPreparedObservationStateNames[] = {
    @"complete",
    @"getterFailed",
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
    sizeof(BHTNativeReplyModelStructureStateNames) /
            sizeof(BHTNativeReplyModelStructureStateNames[0]) ==
        BHTNativeReplyModelStructureStateCount,
    "Native reply model structure names must match the enum");
_Static_assert(
    sizeof(BHTNativeReplyPreparedErrorStateNames) /
            sizeof(BHTNativeReplyPreparedErrorStateNames[0]) ==
        BHTNativeReplyPreparedErrorStateCount,
    "Native reply prepared error names must match the enum");
_Static_assert(
    sizeof(BHTNativeReplyFinalValueStateNames) /
            sizeof(BHTNativeReplyFinalValueStateNames[0]) ==
        BHTNativeReplyFinalValueStateCount,
    "Native reply final value names must match the enum");
_Static_assert(
    sizeof(BHTNativeReplyFinalAPIErrorStateNames) /
            sizeof(BHTNativeReplyFinalAPIErrorStateNames[0]) ==
        BHTNativeReplyFinalAPIErrorStateCount,
    "Native reply final API error names must match the enum");
_Static_assert(
    sizeof(BHTNativeReplyPreparedObservationStateNames) /
            sizeof(BHTNativeReplyPreparedObservationStateNames[0]) ==
        BHTNativeReplyPreparedObservationStateCount,
    "Native reply prepared observation names must match the enum");
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
static atomic_bool BHTNativeReplyPreparedHookInstalled;
static atomic_bool BHTNativeReplyModelStructureLayoutAvailable;
static atomic_ulong BHTNativeReplyApplicationCandidateCalls;
static atomic_ulong BHTNativeReplyApplicationAcceptedCalls;
static atomic_ulong BHTNativeReplyPreparedCandidateCalls;
static atomic_ulong BHTNativeReplyPreparedAcceptedCalls;
static atomic_ulong BHTNativeReplyApplicationOutcomeCounters[
    BHTNativeReplyDecodedOutcomeCount];
static atomic_ulong BHTNativeReplyApplicationOperationCounters[
    BHTNativeReplyApplicationOperationCount];
static atomic_ulong BHTNativeReplyModelStructureCounters[
    BHTNativeReplyModelStructureStateCount];
static atomic_ulong BHTNativeReplyApplicationRejectionCounters[
    BHTNativeReplyApplicationRejectionCount];
static atomic_ulong BHTNativeReplyPreparedRejectionCounters[
    BHTNativeReplyApplicationRejectionCount];
static atomic_ulong BHTNativeReplyPreparedErrorCounters[
    BHTNativeReplyPreparedErrorStateCount];
static atomic_ulong BHTNativeReplyPreparedObservationCounters[
    BHTNativeReplyPreparedObservationStateCount];
static NSMutableArray<NSDictionary*>*
    BHTNativeReplyApplicationRecentAttempts;
static NSMutableArray<NSDictionary*>*
    BHTNativeReplyPreparedRecentAttempts;
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

BOOL BHTNativeReplyApplicationRequestURLIsEligible(
    NSURL* requestURL) {
    BHTNativeReplyApplicationOperation operation;
    return BHTNativeReplyApplicationOperationForURL(
               requestURL, &operation) &&
           BHTNativeReplyApplicationHostIsAllowed(requestURL);
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

static BHTNativeReplyPreparedErrorState
BHTNativeReplyPreparedErrorStateFor(
    BOOL operationErrorPresent,
    BOOL parseErrorPresent,
    BOOL APIErrorsPresent) {
    NSUInteger errorCount =
        (operationErrorPresent ? 1 : 0) +
        (parseErrorPresent ? 1 : 0) +
        (APIErrorsPresent ? 1 : 0);
    if (errorCount > 1) {
        return BHTNativeReplyPreparedErrorStateMultiple;
    }
    if (operationErrorPresent) {
        return BHTNativeReplyPreparedErrorStateOperationOnly;
    }
    if (parseErrorPresent) {
        return BHTNativeReplyPreparedErrorStateParseOnly;
    }
    if (APIErrorsPresent) {
        return BHTNativeReplyPreparedErrorStateAPIOnly;
    }
    return BHTNativeReplyPreparedErrorStateNone;
}

static BHTNativeReplyFinalValueState
BHTNativeReplyFinalValueStateForObject(id value) {
    if (!value) return BHTNativeReplyFinalValueStateUnset;
    if (value == NSNull.null) {
        return BHTNativeReplyFinalValueStateExplicitlyAbsent;
    }
    return BHTNativeReplyFinalValueStateObjectPresent;
}

static BHTNativeReplyFinalAPIErrorState
BHTNativeReplyFinalAPIErrorStateForObject(id value) {
    if (!value) return BHTNativeReplyFinalAPIErrorStateUnset;
    if (value == NSNull.null) {
        return BHTNativeReplyFinalAPIErrorStateExplicitlyAbsent;
    }
    if (![value isKindOfClass:NSArray.class]) {
        return
            BHTNativeReplyFinalAPIErrorStateUnexpectedPresentObject;
    }
    return [(NSArray*)value count] == 0
        ? BHTNativeReplyFinalAPIErrorStateEmptyCollection
        : BHTNativeReplyFinalAPIErrorStateNonemptyCollection;
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
    id APIErrors,
    BHTNativeReplyModelStructureState modelStructureState) {
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
    if (modelStructureState >=
        BHTNativeReplyModelStructureStateCount) {
        modelStructureState =
            BHTNativeReplyModelStructureStateLayoutUnavailable;
    }

    atomic_fetch_add_explicit(
        &BHTNativeReplyApplicationAcceptedCalls, 1,
        memory_order_relaxed);
    atomic_fetch_add_explicit(
        &BHTNativeReplyApplicationOutcomeCounters[outcome],
        1, memory_order_relaxed);
    atomic_fetch_add_explicit(
        &BHTNativeReplyApplicationOperationCounters[operation],
        1, memory_order_relaxed);
    atomic_fetch_add_explicit(
        &BHTNativeReplyModelStructureCounters[modelStructureState],
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
        @"modelStructureState":
            BHTNativeReplyModelStructureStateNames[
                modelStructureState],
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

void BHTRecordNativeReplyPreparedResponse(
    NSUInteger sessionGeneration,
    NSURL* requestURL,
    BOOL observationComplete,
    id effectiveModel,
    id effectiveParseError,
    id effectiveOperationError,
    id effectiveAPIErrors,
    id finalModel,
    id finalParseError,
    id finalOperationError,
    id finalAPIErrors) {
    atomic_fetch_add_explicit(
        &BHTNativeReplyPreparedCandidateCalls, 1,
        memory_order_relaxed);
    if (sessionGeneration == 0) {
        atomic_fetch_add_explicit(
            &BHTNativeReplyPreparedRejectionCounters[
                BHTNativeReplyApplicationRejectionZeroGeneration],
            1, memory_order_relaxed);
        return;
    }
    if (![requestURL isKindOfClass:NSURL.class]) {
        atomic_fetch_add_explicit(
            &BHTNativeReplyPreparedRejectionCounters[
                BHTNativeReplyApplicationRejectionInvalidURL],
            1, memory_order_relaxed);
        return;
    }

    BHTNativeReplyApplicationOperation operation;
    if (!BHTNativeReplyApplicationOperationForURL(
            requestURL, &operation)) {
        atomic_fetch_add_explicit(
            &BHTNativeReplyPreparedRejectionCounters[
                BHTNativeReplyApplicationRejectionOperationMismatch],
            1, memory_order_relaxed);
        return;
    }
    if (!BHTNativeReplyApplicationHostIsAllowed(requestURL)) {
        atomic_fetch_add_explicit(
            &BHTNativeReplyPreparedRejectionCounters[
                BHTNativeReplyApplicationRejectionHostMismatch],
            1, memory_order_relaxed);
        return;
    }

    atomic_fetch_add_explicit(
        &BHTNativeReplyPreparedAcceptedCalls, 1,
        memory_order_relaxed);
    BHTNativeReplyPreparedObservationState observationState =
        observationComplete
            ? BHTNativeReplyPreparedObservationStateComplete
            : BHTNativeReplyPreparedObservationStateGetterFailed;
    atomic_fetch_add_explicit(
        &BHTNativeReplyPreparedObservationCounters[
            observationState],
        1, memory_order_relaxed);

    NSMutableDictionary* attempt = [@{
        @"sessionGeneration": @(sessionGeneration),
        @"operation":
            BHTNativeReplyApplicationOperationNames[operation],
        @"observationState":
            BHTNativeReplyPreparedObservationStateNames[
                observationState],
    } mutableCopy];
    if (observationComplete) {
        BOOL effectiveModelPresent = effectiveModel != nil;
        BOOL effectiveParseErrorPresent =
            effectiveParseError != nil;
        BOOL effectiveOperationErrorPresent =
            effectiveOperationError != nil;
        BHTNativeReplyAPIErrorState effectiveAPIErrorState =
            BHTNativeReplyAPIErrorStateForObject(
                effectiveAPIErrors);
        BOOL effectiveAPIErrorsPresent =
            BHTNativeReplyAPIErrorStateHasErrors(
                effectiveAPIErrorState);
        BHTNativeReplyPreparedErrorState effectiveErrorState =
            BHTNativeReplyPreparedErrorStateFor(
                effectiveOperationErrorPresent,
                effectiveParseErrorPresent,
                effectiveAPIErrorsPresent);
        BHTNativeReplyFinalValueState finalModelState =
            BHTNativeReplyFinalValueStateForObject(finalModel);
        BHTNativeReplyFinalValueState finalParseErrorState =
            BHTNativeReplyFinalValueStateForObject(
                finalParseError);
        BHTNativeReplyFinalValueState finalOperationErrorState =
            BHTNativeReplyFinalValueStateForObject(
                finalOperationError);
        BHTNativeReplyFinalAPIErrorState finalAPIErrorState =
            BHTNativeReplyFinalAPIErrorStateForObject(
                finalAPIErrors);

        atomic_fetch_add_explicit(
            &BHTNativeReplyPreparedErrorCounters[
                effectiveErrorState],
            1, memory_order_relaxed);
        [attempt addEntriesFromDictionary:@{
            @"effectiveModelPresent": @(effectiveModelPresent),
            @"effectiveParseErrorPresent":
                @(effectiveParseErrorPresent),
            @"effectiveOperationErrorPresent":
                @(effectiveOperationErrorPresent),
            @"effectiveAPIErrorsState":
                BHTNativeReplyAPIErrorStateNames[
                    effectiveAPIErrorState],
            @"effectiveErrorState":
                BHTNativeReplyPreparedErrorStateNames[
                    effectiveErrorState],
            @"finalModelState":
                BHTNativeReplyFinalValueStateNames[finalModelState],
            @"finalParseErrorState":
                BHTNativeReplyFinalValueStateNames[
                    finalParseErrorState],
            @"finalOperationErrorState":
                BHTNativeReplyFinalValueStateNames[
                    finalOperationErrorState],
            @"finalAPIErrorsState":
                BHTNativeReplyFinalAPIErrorStateNames[
                    finalAPIErrorState],
        }];
    }
    @synchronized(BHTNativeReplyApplicationLock()) {
        if (!BHTNativeReplyPreparedRecentAttempts) {
            BHTNativeReplyPreparedRecentAttempts =
                [NSMutableArray arrayWithCapacity:
                    BHTNativeReplyApplicationAttemptLimit];
        }
        if (BHTNativeReplyPreparedRecentAttempts.count >=
            BHTNativeReplyApplicationAttemptLimit) {
            [BHTNativeReplyPreparedRecentAttempts
                removeObjectAtIndex:0];
        }
        [BHTNativeReplyPreparedRecentAttempts
            addObject:attempt];
    }
}

void BHTMarkNativeReplyApplicationHookInstalled(void) {
    atomic_store_explicit(
        &BHTNativeReplyApplicationHookInstalled,
        true, memory_order_release);
}

void BHTMarkNativeReplyPreparedHookInstalled(void) {
    atomic_store_explicit(
        &BHTNativeReplyPreparedHookInstalled,
        true, memory_order_release);
}

void BHTMarkNativeReplyModelStructureLayoutAvailable(void) {
    atomic_store_explicit(
        &BHTNativeReplyModelStructureLayoutAvailable,
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
    NSArray* preparedAttempts;
    @synchronized(BHTNativeReplyApplicationLock()) {
        attempts =
            [BHTNativeReplyApplicationRecentAttempts copy] ?: @[];
        preparedAttempts =
            [BHTNativeReplyPreparedRecentAttempts copy] ?: @[];
    }
    return @{
        @"decodeHookInstalled":
            @(atomic_load_explicit(
                &BHTNativeReplyApplicationHookInstalled,
                memory_order_acquire)),
        @"prepareHookInstalled":
            @(atomic_load_explicit(
                &BHTNativeReplyPreparedHookInstalled,
                memory_order_acquire)),
        @"modelStructureLayoutAvailable":
            @(atomic_load_explicit(
                &BHTNativeReplyModelStructureLayoutAvailable,
                memory_order_acquire)),
        @"candidateCallsDuringForwardedReply":
            @(atomic_load_explicit(
                &BHTNativeReplyApplicationCandidateCalls,
                memory_order_relaxed)),
        @"acceptedCreateTweetResults":
            @(atomic_load_explicit(
                &BHTNativeReplyApplicationAcceptedCalls,
                memory_order_relaxed)),
        @"preparedCandidateCallsDuringForwardedReply":
            @(atomic_load_explicit(
                &BHTNativeReplyPreparedCandidateCalls,
                memory_order_relaxed)),
        @"acceptedPreparedCreateTweetResults":
            @(atomic_load_explicit(
                &BHTNativeReplyPreparedAcceptedCalls,
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
        @"modelStructureCounters":
            BHTNativeReplyApplicationCounterDictionary(
                BHTNativeReplyModelStructureStateNames,
                BHTNativeReplyModelStructureCounters,
                BHTNativeReplyModelStructureStateCount),
        @"rejectionCounters":
            BHTNativeReplyApplicationCounterDictionary(
                BHTNativeReplyApplicationRejectionNames,
                BHTNativeReplyApplicationRejectionCounters,
                BHTNativeReplyApplicationRejectionCount),
        @"preparedErrorCounters":
            BHTNativeReplyApplicationCounterDictionary(
                BHTNativeReplyPreparedErrorStateNames,
                BHTNativeReplyPreparedErrorCounters,
                BHTNativeReplyPreparedErrorStateCount),
        @"preparedObservationCounters":
            BHTNativeReplyApplicationCounterDictionary(
                BHTNativeReplyPreparedObservationStateNames,
                BHTNativeReplyPreparedObservationCounters,
                BHTNativeReplyPreparedObservationStateCount),
        @"preparedRejectionCounters":
            BHTNativeReplyApplicationCounterDictionary(
                BHTNativeReplyApplicationRejectionNames,
                BHTNativeReplyPreparedRejectionCounters,
                BHTNativeReplyApplicationRejectionCount),
        @"recentAttempts": attempts,
        @"recentPreparedAttempts": preparedAttempts,
        @"recentAttemptLimit":
            @(BHTNativeReplyApplicationAttemptLimit),
        @"source":
            @"x_decoded_and_prepared_graphql_response_presence",
        @"http2xxDoesNotImplyApplicationSuccess": @YES,
        @"correlationScope": @"process_temporal_operation_only",
        @"requestIdentityBound": @NO,
        @"applicationSuccessIsNotInferred": @YES,
        @"preparedResponseSuccessIsNotInferred": @YES,
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
        @"inspectsErrorDomainsOrCodes": @NO,
        @"inspectsCreateTweetObjectPresence": @YES,
        @"inspectsTweetResultsUnionPayload": @NO,
        @"persistsDecodedObjects": @NO,
        @"exportsDecodedObjects": @NO,
    };
}
