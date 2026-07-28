#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BHTForYouKeywordFilterKind) {
    BHTForYouKeywordFilterKindUsername = 0,
    BHTForYouKeywordFilterKindPostText,
};

FOUNDATION_EXPORT NSString* const BHTForYouUsernameFilterKeywordsKey;
FOUNDATION_EXPORT NSString* const BHTForYouPostTextFilterKeywordsKey;
FOUNDATION_EXPORT NSString* const
    BHTForYouKeywordFiltersDidChangeNotification;

FOUNDATION_EXPORT const NSUInteger BHTForYouKeywordMaximumCount;
FOUNDATION_EXPORT const NSUInteger BHTForYouKeywordMaximumLength;

// Stores the two For You-only filter lists and keeps immutable, normalized
// matching snapshots in memory. Callers on timeline rendering paths should use
// the matching methods rather than reading NSUserDefaults directly.
@interface BHTForYouKeywordFilter : NSObject

+ (NSArray<NSString*>*)keywordsForKind:(BHTForYouKeywordFilterKind)kind;
+ (NSArray<NSString*>*)usernameKeywords;
+ (NSArray<NSString*>*)postTextKeywords;

+ (BOOL)setKeywords:(NSArray<NSString*>*)keywords
            forKind:(BHTForYouKeywordFilterKind)kind
              error:(NSError* _Nullable* _Nullable)error;
+ (BOOL)addKeyword:(NSString*)keyword
           forKind:(BHTForYouKeywordFilterKind)kind
             error:(NSError* _Nullable* _Nullable)error;
+ (BOOL)replaceKeywordAtIndex:(NSUInteger)index
                 withKeyword:(NSString*)keyword
                     forKind:(BHTForYouKeywordFilterKind)kind
                       error:(NSError* _Nullable* _Nullable)error;
+ (BOOL)removeKeywordAtIndex:(NSUInteger)index
                     forKind:(BHTForYouKeywordFilterKind)kind;

+ (BOOL)hasUsernameFilters;
+ (BOOL)hasPostTextFilters;
+ (BOOL)hasActiveFilters;

// Username filtering is a literal substring match against both the @handle and
// display name. This array form is useful for reposts, where both the visible
// author and reposting account may be supplied.
+ (BOOL)matchesUsername:(nullable NSString*)username
            displayName:(nullable NSString*)displayName;
+ (BOOL)matchesAnyUsernameCandidate:
    (nullable NSArray<NSString*>*)candidates;

// Post-text matching is a literal substring match. The caller decides which
// native text models represent the primary visible post. The array form lets
// callers include both X's display text and raw full text, since display text
// may omit leading @mentions.
+ (BOOL)matchesPostText:(nullable NSString*)postText;
+ (BOOL)matchesAnyPostTextCandidate:
    (nullable NSArray<NSString*>*)candidates;

// Incremented whenever either cached keyword snapshot changes. Timeline item
// decision caches can include this value in their own cache key.
+ (NSUInteger)filterGeneration;
+ (NSUInteger)filterGenerationWithUsernameFilters:
                    (BOOL* _Nullable)hasUsernameFilters
                                  postTextFilters:
                    (BOOL* _Nullable)hasPostTextFilters;

@end

NS_ASSUME_NONNULL_END
