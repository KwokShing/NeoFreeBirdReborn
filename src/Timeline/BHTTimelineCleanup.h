#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, BHTTimelineCleanupKind) {
    BHTTimelineCleanupKindNone = 0,
    BHTTimelineCleanupKindWhoToFollow = 1 << 0,
    BHTTimelineCleanupKindPrompt = 1 << 1,
    BHTTimelineCleanupKindDiscoverMore = 1 << 2,
    BHTTimelineCleanupKindTopicPost = 1 << 3,
    BHTTimelineCleanupKindTopicSuggestion = 1 << 4,
};

// Classifies X's stable URT identifiers. This is intentionally separate from
// visible labels so localization and wording changes cannot bypass cleanup.
FOUNDATION_EXPORT BHTTimelineCleanupKind
BHTTimelineCleanupKindsForIdentifiers(NSString* _Nullable className,
                                      NSString* _Nullable scribeComponent,
                                      NSString* _Nullable entryID);

// Classifies a live timeline item, including topic metadata stored on the
// underlying TFNTwitterStatus in current X builds.
FOUNDATION_EXPORT BHTTimelineCleanupKind
BHTTimelineCleanupKindsForItem(id _Nullable item);

FOUNDATION_EXPORT BHTTimelineCleanupKind
BHTEnabledTimelineCleanupKinds(void);

FOUNDATION_EXPORT BOOL BHTShouldHideTimelineCleanupItemForKinds(
    id _Nullable item, BHTTimelineCleanupKind enabledKinds);
FOUNDATION_EXPORT BOOL
BHTShouldHideTimelineCleanupItem(id _Nullable item);

NS_ASSUME_NONNULL_END
