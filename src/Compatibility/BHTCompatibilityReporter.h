#import <Foundation/Foundation.h>

@class UIImageView;
@class UIView;

typedef NS_ENUM(NSUInteger, BHTForYouFilterDiagnosticEvent) {
    BHTForYouFilterDiagnosticControllerPrimary = 0,
    BHTForYouFilterDiagnosticControllerNonForYou,
    BHTForYouFilterDiagnosticControllerUnknown,
    BHTForYouFilterDiagnosticControllerOwnerMissing,
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

NSURL* BHTCompatibilityReportURL(void);
void BHTWriteCompatibilityReport(void);
void BHTWriteCompatibilityReportAsync(
    void (^completion)(NSURL* _Nullable reportURL));
void BHTRecordForYouFilterDiagnostic(
    BHTForYouFilterDiagnosticEvent event);
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
