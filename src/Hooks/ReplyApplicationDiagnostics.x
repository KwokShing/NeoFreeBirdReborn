//
//  ReplyApplicationDiagnostics.x
//  NeoFreeBird
//
//  X 12.9-only observation of decoded CreateTweet results. X's decoder runs
//  first. The diagnostic then records fixed presence categories only; decoded
//  objects, error contents, URLs, identifiers, and account data never leave
//  this stack frame.
//

#import "Compatibility/BHTCompatibilityReporter.h"
#import "Reply/BHTReplyApplicationDiagnostics.h"

#import <objc/message.h>
#import <objc/runtime.h>

static Class BHTReplyApplicationRequestClass;

static const char* BHTReplyApplicationUnqualifiedType(
    const char* type) {
    while (type &&
           (*type == 'r' || *type == 'n' || *type == 'N' ||
            *type == 'o' || *type == 'O' || *type == 'R' ||
            *type == 'V')) {
        type++;
    }
    return type;
}

static BOOL BHTReplyApplicationMethodHasDecoderABI(
    Class cls, SEL selector) {
    if (!cls || !selector) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 4) {
        return NO;
    }

    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* result =
        BHTReplyApplicationUnqualifiedType(returnType);
    if (!result || result[0] != '@' || result[1] != '\0') {
        return NO;
    }

    for (unsigned int index = 2; index < 4; index++) {
        char argumentType[16] = {0};
        method_getArgumentType(
            method, index, argumentType,
            sizeof(argumentType));
        const char* argument =
            BHTReplyApplicationUnqualifiedType(argumentType);
        if (!argument || argument[0] != '^' ||
            argument[1] != '@' || argument[2] != '\0') {
            return NO;
        }
    }
    return YES;
}

static BOOL BHTReplyApplicationMethodReturnsObjectWithNoArguments(
    Class cls, SEL selector) {
    if (!cls || !selector) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 2) {
        return NO;
    }
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* result =
        BHTReplyApplicationUnqualifiedType(returnType);
    return result && result[0] == '@' && result[1] == '\0';
}

%group BHTNativeReplyApplicationHooks

%hook _TtC14GraphQLActions23GraphQLEndpointResponse

- (id)modelWithParseError:(id __autoreleasing*)parseError
                APIErrors:(id __autoreleasing*)APIErrors {
    NSUInteger sessionGeneration = 0;
    BOOL correlated = NO;
    if (BHTReplyWorkflowApplicationDiagnosticWindowMayBeActive()) {
        @try {
            correlated =
                BHTReplyWorkflowDiagnosticSessionForApplicationResponse(
                    &sessionGeneration);
        } @catch (__unused NSException* exception) {
        }
    }

    id model = %orig(parseError, APIErrors);
    if (!correlated) return model;

    @try {
        SEL originalRequestSelector =
            NSSelectorFromString(@"originalRequest");
        SEL URLSelector = NSSelectorFromString(@"URL");
        id originalRequest =
            ((id (*)(id, SEL))objc_msgSend)(
                self, originalRequestSelector);
        NSURL* requestURL = nil;
        if (BHTReplyApplicationRequestClass &&
            [originalRequest
                isKindOfClass:BHTReplyApplicationRequestClass]) {
            id candidateURL =
                ((id (*)(id, SEL))objc_msgSend)(
                    originalRequest, URLSelector);
            if ([candidateURL isKindOfClass:NSURL.class]) {
                requestURL = candidateURL;
            }
        }
        id decodedParseError = parseError ? *parseError : nil;
        id decodedAPIErrors = APIErrors ? *APIErrors : nil;
        BHTRecordNativeReplyApplicationResult(
            sessionGeneration, requestURL, model,
            decodedParseError, decodedAPIErrors);
    } @catch (__unused NSException* exception) {
    }
    return model;
}

%end

%end

%ctor {
    NSString* version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (![version isKindOfClass:NSString.class] ||
        ![version isEqualToString:@"12.9"]) {
        return;
    }

    Class responseClass = NSClassFromString(
        @"_TtC14GraphQLActions23GraphQLEndpointResponse");
    Class requestClass = NSClassFromString(@"TFSAPIRequest");
    SEL decoderSelector = NSSelectorFromString(
        @"modelWithParseError:APIErrors:");
    SEL originalRequestSelector =
        NSSelectorFromString(@"originalRequest");
    SEL URLSelector = NSSelectorFromString(@"URL");
    if (!BHTReplyApplicationMethodHasDecoderABI(
            responseClass, decoderSelector) ||
        !BHTReplyApplicationMethodReturnsObjectWithNoArguments(
            responseClass, originalRequestSelector) ||
        !BHTReplyApplicationMethodReturnsObjectWithNoArguments(
            requestClass, URLSelector)) {
        return;
    }

    BHTReplyApplicationRequestClass = requestClass;
    %init(BHTNativeReplyApplicationHooks);
    BHTMarkNativeReplyApplicationHookInstalled();
}
