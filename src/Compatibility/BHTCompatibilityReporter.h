#pragma once

#import <Foundation/Foundation.h>

@class UIImageView;
@class UIView;

typedef NS_ENUM(NSUInteger, BHTForYouFilterDiagnosticEvent) {
    BHTForYouFilterDiagnosticControllerPrimary = 0,
    BHTForYouFilterDiagnosticControllerNonForYou,
    BHTForYouFilterDiagnosticControllerUnknown,
    BHTForYouFilterDiagnosticControllerOwnerMissing,
    BHTForYouFilterDiagnosticDirectOwnerResolved,
    BHTForYouFilterDiagnosticDirectOwnerMissing,
    BHTForYouFilterDiagnosticControllerNonHome,
    BHTForYouFilterDiagnosticTimelineObjectResolved,
    BHTForYouFilterDiagnosticTimelineObjectMissing,
    BHTForYouFilterDiagnosticMissingStatus,
    BHTForYouFilterDiagnosticDecisionCacheHit,
    BHTForYouFilterDiagnosticUsernameMatch,
    BHTForYouFilterDiagnosticPostTextMatch,
    BHTForYouFilterDiagnosticNoMatch,
    BHTForYouFilterDiagnosticEventCount,
};

typedef NS_ENUM(NSUInteger, BHTReplyWorkflowDiagnosticEvent) {
    BHTReplyWorkflowDiagnosticReplyActionTapped = 0,
    BHTReplyWorkflowDiagnosticReplyActionForwarded,
    BHTReplyWorkflowDiagnosticWebFallbackPresented,
    BHTReplyWorkflowDiagnosticPersistentComposerPresented,
    BHTReplyWorkflowDiagnosticComposerPresented,
    BHTReplyWorkflowDiagnosticComposerDisappeared,
    BHTReplyWorkflowDiagnosticComposerClosed,
    BHTReplyWorkflowDiagnosticSendButtonTapped,
    BHTReplyWorkflowDiagnosticSendForwardedToX,
    BHTReplyWorkflowDiagnosticValidationEntered,
    BHTReplyWorkflowDiagnosticValidationReturned,
    BHTReplyWorkflowDiagnosticSendCompositionsEntered,
    BHTReplyWorkflowDiagnosticSendCompositionsReturned,
    BHTReplyWorkflowDiagnosticContainerCompleted,
    BHTReplyWorkflowDiagnosticContainerCancelled,
    BHTReplyWorkflowDiagnosticOutboxQueued,
    BHTReplyWorkflowDiagnosticOutboxProcessing,
    BHTReplyWorkflowDiagnosticOutboxProcessed,
    BHTReplyWorkflowDiagnosticSendCompleted,
    BHTReplyWorkflowDiagnosticOutboxProcessFailed,
    BHTReplyWorkflowDiagnosticCompositionSendFailed,
    BHTReplyWorkflowDiagnosticUnattributedPersistentComposerPresented,
    BHTReplyWorkflowDiagnosticUnattributedComposerPresented,
    BHTReplyWorkflowDiagnosticUnattributedSendButtonTapped,
    BHTReplyWorkflowDiagnosticUnattributedSendForwardedToX,
    BHTReplyWorkflowDiagnosticEventCount,
};

NSURL* BHTCompatibilityReportURL(void);
void BHTWriteCompatibilityReport(void);
void BHTWriteCompatibilityReportAsync(
    void (^completion)(NSURL* _Nullable reportURL));
void BHTRecordForYouFilterDiagnostic(
    BHTForYouFilterDiagnosticEvent event);
// Records fixed workflow stages only. Tweet/reply text, users, IDs, URLs,
// account objects, notification payloads, and raw errors are never inspected.
void BHTRecordReplyWorkflowDiagnostic(
    BHTReplyWorkflowDiagnosticEvent event);
void BHTInstallReplyWorkflowDiagnosticObservers(void);
// Returns only whether a native reply send is currently inside the guarded
// diagnostic window, plus its process-local generation. No account,
// composition, status, or request object crosses this boundary.
BOOL BHTReplyWorkflowDiagnosticSessionForNetworkRequest(
    NSUInteger* _Nullable generation);
// Captures the active reply generation for X's decoded response seam. Its
// 30-second bound is longer than request construction because Undo Tweet can
// defer the decoded application result until the outbox runs. It returns only
// a process-local generation and exposes no reply or account.
BOOL BHTReplyWorkflowDiagnosticSessionForApplicationResponse(
    NSUInteger* _Nullable generation);
// Lock-free hint used by the app-global GraphQL decoder hook so ordinary
// timeline responses do not contend on reply workflow state.
BOOL BHTReplyWorkflowApplicationDiagnosticWindowMayBeActive(void);
// Cheap lock-free gate for app-global task-constructor hooks. A true result
// is only a hint; the strict correlation function above still revalidates the
// reply session before any task is tagged.
BOOL BHTReplyWorkflowNetworkDiagnosticWindowMayBeActive(void);
void BHTRecordNavigationEntryClasses(NSArray* entries);
void BHTRecordTimelineItemObservation(id item, NSString* location, BOOL hidden);
void BHTRecordMediaActionObservation(NSString* stage,
                                     NSString* kind,
                                     NSUInteger originalCount,
                                     NSUInteger configuredCount,
                                     NSUInteger mediaEntityCount);
void BHTRecordRailBrandingObservation(NSString* resolution,
                                      UIView* hostView,
                                      UIImageView* logoView,
                                      NSUInteger candidateCount);
void BHTRecordThemeRuntimeObservation(
    NSString* presetIdentifier,
    NSString* paletteClass,
    BOOL darkAppearance,
    NSArray<NSString*>* installedGetterNames,
    NSUInteger refreshAttempts,
    NSUInteger configurationGeneration,
    NSUInteger seenPaletteCount,
    NSArray<NSString*>* providerClasses,
    BOOL applyCurrentColorPaletteUsed,
    NSArray<NSString*>* t1RefreshSelectorsUsed,
    BOOL paletteSetterFallbackUsed,
    BOOL dynamicColorsDidReloadObserved,
    NSUInteger visibleViewsVisited,
    NSUInteger dynamicColorViewsUpdated);
