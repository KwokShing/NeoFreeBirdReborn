//
//  ReplyDiagnostics.x
//  NeoFreeBird
//
//  Privacy-preserving checkpoints for the X 12.9 reply workflow. Hook
//  arguments are deliberately forwarded without being inspected or retained.
//

#import "Compatibility/BHTCompatibilityReporter.h"
#import "HookHelpers.h"

#import <objc/runtime.h>

static BOOL BHTReplyDiagnosticMethodHasShape(
    Class cls, SEL selector, unsigned int explicitArgumentCount) {
    if (!cls || !selector) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method ||
        method_getNumberOfArguments(method) !=
            explicitArgumentCount + 2) {
        return NO;
    }

    char returnType[8] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    return returnType[0] == 'v';
}

static BOOL BHTReplyDiagnosticMethodHasObjectArguments(
    Class cls, SEL selector, unsigned int explicitArgumentCount) {
    if (!BHTReplyDiagnosticMethodHasShape(
            cls, selector, explicitArgumentCount)) {
        return NO;
    }
    Method method = class_getInstanceMethod(cls, selector);
    for (unsigned int index = 0;
         index < explicitArgumentCount; index++) {
        char argumentType[16] = {0};
        method_getArgumentType(
            method, index + 2, argumentType,
            sizeof(argumentType));
        const char* type = argumentType;
        while (*type == 'r' || *type == 'n' || *type == 'N' ||
               *type == 'o' || *type == 'O' || *type == 'R' ||
               *type == 'V') {
            type++;
        }
        if (*type != '@') return NO;
    }
    return YES;
}

%group BHTReplyButtonDiagnosticHooks

%hook TTAStatusInlineReplyButton

- (void)didTap {
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticReplyActionTapped);
    %orig;
}

%end

%end

%group BHTReplyActionDiagnosticHooks

%hook T1StatusViewInlineActionTapEventHandler

- (void)performReplyActionWithAccount:(__unsafe_unretained id)account
                                event:(__unsafe_unretained id)event
                           controller:(__unsafe_unretained id)controller
                        scribeContext:(__unsafe_unretained id)scribeContext
                        scribeElement:(__unsafe_unretained id)scribeElement
                           parameters:(__unsafe_unretained id)parameters
                       originalStatus:(__unsafe_unretained id)originalStatus {
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticReplyActionForwarded);
    %orig(
        account, event, controller, scribeContext, scribeElement,
        parameters, originalStatus);
}

%end

%end

%group BHTReplyComposerDiagnosticHooks

%hook T1TweetComposeViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticComposerPresented);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticComposerDisappeared);
    BOOL closing =
        self.isBeingDismissed ||
        self.isMovingFromParentViewController ||
        self.navigationController.isBeingDismissed ||
        self.navigationController.isMovingFromParentViewController;
    if (closing) {
        BHTRecordReplyWorkflowDiagnostic(
            BHTReplyWorkflowDiagnosticComposerClosed);
    }
}

%end

%end

%group BHTPersistentReplyComposerDiagnosticHooks

%hook T1PersistentComposeViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticPersistentComposerPresented);
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

    BHTInstallReplyWorkflowDiagnosticObservers();

    Class replyButton =
        NSClassFromString(@"TTAStatusInlineReplyButton");
    if (BHTReplyDiagnosticMethodHasShape(
            replyButton, @selector(didTap), 0)) {
        %init(BHTReplyButtonDiagnosticHooks);
    }

    Class replyHandler = NSClassFromString(
        @"T1StatusViewInlineActionTapEventHandler");
    SEL replySelector = NSSelectorFromString(
        @"performReplyActionWithAccount:event:controller:scribeContext:scribeElement:parameters:originalStatus:");
    if (BHTReplyDiagnosticMethodHasObjectArguments(
            replyHandler, replySelector, 7)) {
        %init(BHTReplyActionDiagnosticHooks);
    }

    Class composer =
        NSClassFromString(@"T1TweetComposeViewController");
    if (BHTReplyDiagnosticMethodHasShape(
            composer, @selector(viewDidAppear:), 1) &&
        BHTReplyDiagnosticMethodHasShape(
            composer, @selector(viewDidDisappear:), 1)) {
        %init(BHTReplyComposerDiagnosticHooks);
    }

    Class persistentComposer =
        NSClassFromString(@"T1PersistentComposeViewController");
    if (BHTReplyDiagnosticMethodHasShape(
            persistentComposer, @selector(viewDidAppear:), 1)) {
        %init(BHTPersistentReplyComposerDiagnosticHooks);
    }
}
