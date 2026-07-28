#import "Timeline/BHTForYouKeywordFilter.h"

#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"

NSString* const BHTForYouUsernameFilterKeywordsKey =
    @"bht_for_you_username_filter_keywords";
NSString* const BHTForYouPostTextFilterKeywordsKey =
    @"bht_for_you_post_text_filter_keywords";
NSString* const BHTForYouKeywordFiltersDidChangeNotification =
    @"BHTForYouKeywordFiltersDidChangeNotification";

const NSUInteger BHTForYouKeywordMaximumCount = 64;
const NSUInteger BHTForYouKeywordMaximumLength = 128;

static NSString* const BHTForYouKeywordFilterErrorDomain =
    @"com.neofreebird.for-you-keyword-filter";

typedef NS_ENUM(NSInteger, BHTForYouKeywordFilterErrorCode) {
    BHTForYouKeywordFilterErrorInvalidList = 1,
    BHTForYouKeywordFilterErrorTooManyKeywords,
    BHTForYouKeywordFilterErrorInvalidKeyword,
    BHTForYouKeywordFilterErrorKeywordTooLong,
    BHTForYouKeywordFilterErrorDuplicateKeyword,
    BHTForYouKeywordFilterErrorInvalidIndex,
};

static NSArray<NSString*>* BHTUsernameKeywords;
static NSArray<NSString*>* BHTUsernameNeedles;
static NSArray<NSString*>* BHTPostTextKeywords;
static NSArray<NSString*>* BHTPostTextNeedles;
static NSUInteger BHTKeywordFilterGeneration;
static BOOL BHTKeywordSnapshotsLoaded;

static NSLocale* BHTKeywordMatchingLocale(void) {
    static NSLocale* locale;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        locale =
            [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return locale;
}

static NSString* BHTPreferenceKeyForKind(
    BHTForYouKeywordFilterKind kind) {
    return kind == BHTForYouKeywordFilterKindPostText
               ? BHTForYouPostTextFilterKeywordsKey
               : BHTForYouUsernameFilterKeywordsKey;
}

static NSError* BHTKeywordError(BHTForYouKeywordFilterErrorCode code,
                                NSString* description) {
    return [NSError errorWithDomain:BHTForYouKeywordFilterErrorDomain
                               code:code
                           userInfo:@{
                               NSLocalizedDescriptionKey:
                                   description ?: @"The keyword is invalid."
                           }];
}

static NSString* BHTKeywordLocalized(NSString* key,
                                     NSString* fallback) {
    NSString* value =
        [[BHTBundle sharedBundle] localizedStringForKey:key];
    return value.length > 0 && ![value isEqualToString:key]
               ? value
               : fallback;
}

static NSString* BHTCanonicalKeyword(
    NSString* value, BHTForYouKeywordFilterKind kind) {
    if (![value isKindOfClass:NSString.class]) return nil;

    NSString* canonical =
        [value stringByTrimmingCharactersInSet:
                   NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (kind == BHTForYouKeywordFilterKindUsername &&
        [canonical hasPrefix:@"@"]) {
        canonical = [[canonical substringFromIndex:1]
            stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    if (canonical.length == 0) return nil;

    canonical =
        [canonical stringByFoldingWithOptions:
                       NSCaseInsensitiveSearch |
                       NSDiacriticInsensitiveSearch |
                       NSWidthInsensitiveSearch
                                       locale:BHTKeywordMatchingLocale()];
    return canonical.lowercaseString;
}

static NSArray<NSString*>* BHTSanitizedKeywords(
    id rawKeywords, BHTForYouKeywordFilterKind kind, BOOL strict,
    NSError** error) {
    if (!rawKeywords) return @[];
    if (![rawKeywords isKindOfClass:NSArray.class]) {
        if (error) {
            *error = BHTKeywordError(
                BHTForYouKeywordFilterErrorInvalidList,
                BHTKeywordLocalized(
                    @"FOR_YOU_FILTERS_INVALID_LIST_ERROR",
                    @"The keyword list is not in a supported format."));
        }
        return strict ? nil : @[];
    }

    NSArray* rawArray = rawKeywords;
    if (strict && rawArray.count > BHTForYouKeywordMaximumCount) {
        if (error) {
            *error = BHTKeywordError(
                BHTForYouKeywordFilterErrorTooManyKeywords,
                [NSString
                    stringWithFormat:
                        BHTKeywordLocalized(
                            @"FOR_YOU_FILTERS_TOO_MANY_ERROR_FORMAT",
                            @"Each filter can contain up to %lu keywords."),
                        (unsigned long)BHTForYouKeywordMaximumCount]);
        }
        return nil;
    }

    NSMutableArray<NSString*>* sanitized = [NSMutableArray array];
    NSMutableSet<NSString*>* normalizedValues =
        [NSMutableSet set];
    NSCharacterSet* unsupportedCharacters =
        NSCharacterSet.controlCharacterSet;

    for (id rawValue in rawArray) {
        if (![rawValue isKindOfClass:NSString.class]) {
            if (strict && error) {
                *error = BHTKeywordError(
                    BHTForYouKeywordFilterErrorInvalidKeyword,
                    BHTKeywordLocalized(
                        @"FOR_YOU_FILTERS_TEXT_ONLY_ERROR",
                        @"Keywords must be text."));
            }
            if (strict) return nil;
            continue;
        }

        NSString* value =
            [(NSString*)rawValue
                stringByTrimmingCharactersInSet:
                    NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (kind == BHTForYouKeywordFilterKindUsername &&
            [value hasPrefix:@"@"]) {
            value = [[value substringFromIndex:1]
                stringByTrimmingCharactersInSet:
                    NSCharacterSet.whitespaceAndNewlineCharacterSet];
        }

        if (value.length == 0 ||
            [value rangeOfCharacterFromSet:unsupportedCharacters].location !=
                NSNotFound) {
            if (strict && error) {
                *error = BHTKeywordError(
                    BHTForYouKeywordFilterErrorInvalidKeyword,
                    BHTKeywordLocalized(
                        @"FOR_YOU_FILTERS_INVALID_KEYWORD_ERROR",
                        @"Enter a keyword without line breaks or control "
                         @"characters."));
            }
            if (strict) return nil;
            continue;
        }
        if (value.length > BHTForYouKeywordMaximumLength) {
            if (strict && error) {
                *error = BHTKeywordError(
                    BHTForYouKeywordFilterErrorKeywordTooLong,
                    [NSString
                        stringWithFormat:
                            BHTKeywordLocalized(
                                @"FOR_YOU_FILTERS_TOO_LONG_ERROR_FORMAT",
                                @"Keywords can contain up to %lu "
                                 @"characters."),
                            (unsigned long)BHTForYouKeywordMaximumLength]);
            }
            if (strict) return nil;
            continue;
        }

        NSString* normalized = BHTCanonicalKeyword(value, kind);
        if (normalized.length == 0 ||
            [normalizedValues containsObject:normalized]) {
            // Bulk writes and imported profiles are canonicalized
            // deterministically. Interactive add/edit methods return a more
            // specific duplicate error before reaching this path.
            continue;
        }
        if (sanitized.count >= BHTForYouKeywordMaximumCount) {
            if (strict && error) {
                *error = BHTKeywordError(
                    BHTForYouKeywordFilterErrorTooManyKeywords,
                    [NSString
                        stringWithFormat:
                            BHTKeywordLocalized(
                                @"FOR_YOU_FILTERS_TOO_MANY_ERROR_FORMAT",
                                @"Each filter can contain up to %lu "
                                 @"keywords."),
                            (unsigned long)BHTForYouKeywordMaximumCount]);
            }
            if (strict) return nil;
            break;
        }
        [normalizedValues addObject:normalized];
        [sanitized addObject:value];
    }

    return [sanitized copy];
}

static NSArray<NSString*>* BHTNeedlesForKeywords(
    NSArray<NSString*>* keywords, BHTForYouKeywordFilterKind kind) {
    NSMutableArray<NSString*>* needles =
        [NSMutableArray arrayWithCapacity:keywords.count];
    for (NSString* keyword in keywords) {
        NSString* needle = BHTCanonicalKeyword(keyword, kind);
        if (needle.length > 0) [needles addObject:needle];
    }
    return [needles copy];
}

static void BHTLoadKeywordSnapshotsLocked(void) {
    if (BHTKeywordSnapshotsLoaded) return;

    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    BHTUsernameKeywords =
        BHTSanitizedKeywords(
            [defaults objectForKey:BHTForYouUsernameFilterKeywordsKey],
            BHTForYouKeywordFilterKindUsername, NO, nil) ?: @[];
    BHTPostTextKeywords =
        BHTSanitizedKeywords(
            [defaults objectForKey:BHTForYouPostTextFilterKeywordsKey],
            BHTForYouKeywordFilterKindPostText, NO, nil) ?: @[];
    BHTUsernameNeedles =
        BHTNeedlesForKeywords(BHTUsernameKeywords,
                              BHTForYouKeywordFilterKindUsername);
    BHTPostTextNeedles =
        BHTNeedlesForKeywords(BHTPostTextKeywords,
                              BHTForYouKeywordFilterKindPostText);
    BHTKeywordSnapshotsLoaded = YES;
    BHTKeywordFilterGeneration =
        MAX((NSUInteger)1, BHTKeywordFilterGeneration + 1);
}

static NSArray<NSString*>* BHTKeywordsForKindLocked(
    BHTForYouKeywordFilterKind kind) {
    BHTLoadKeywordSnapshotsLocked();
    return kind == BHTForYouKeywordFilterKindPostText
               ? BHTPostTextKeywords
               : BHTUsernameKeywords;
}

static void BHTSetKeywordSnapshotLocked(
    NSArray<NSString*>* keywords, BHTForYouKeywordFilterKind kind) {
    if (kind == BHTForYouKeywordFilterKindPostText) {
        BHTPostTextKeywords = [keywords copy];
        BHTPostTextNeedles =
            BHTNeedlesForKeywords(
                BHTPostTextKeywords,
                BHTForYouKeywordFilterKindPostText);
    } else {
        BHTUsernameKeywords = [keywords copy];
        BHTUsernameNeedles =
            BHTNeedlesForKeywords(
                BHTUsernameKeywords,
                BHTForYouKeywordFilterKindUsername);
    }
    BHTKeywordSnapshotsLoaded = YES;
    BHTKeywordFilterGeneration =
        MAX((NSUInteger)1, BHTKeywordFilterGeneration + 1);
}

static void BHTPostKeywordChangeNotification(
    BHTForYouKeywordFilterKind kind) {
    void (^post)(void) = ^{
        [NSNotificationCenter.defaultCenter
            postNotificationName:
                BHTForYouKeywordFiltersDidChangeNotification
                          object:nil
                        userInfo:@{
                            @"kind": @(kind),
                            @"key": BHTPreferenceKeyForKind(kind)
                        }];
    };
    if (NSThread.isMainThread) {
        post();
    } else {
        dispatch_async(dispatch_get_main_queue(), post);
    }
}

static BOOL BHTNormalizedArrayContainsValue(
    NSArray<NSString*>* keywords, NSString* candidate,
    BHTForYouKeywordFilterKind kind, NSUInteger ignoredIndex) {
    NSString* normalizedCandidate =
        BHTCanonicalKeyword(candidate, kind);
    if (normalizedCandidate.length == 0) return NO;
    for (NSUInteger index = 0; index < keywords.count; index++) {
        if (index == ignoredIndex) continue;
        NSString* normalized =
            BHTCanonicalKeyword(keywords[index], kind);
        if ([normalized isEqualToString:normalizedCandidate]) return YES;
    }
    return NO;
}

@implementation BHTForYouKeywordFilter

+ (void)initialize {
    if (self != BHTForYouKeywordFilter.class) return;
    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(preferenceProfileDidApply:)
               name:BHTSettingsProfileDidApplyNotification
             object:nil];
}

+ (void)preferenceProfileDidApply:(NSNotification*)notification {
    NSArray* changedKeys = notification.userInfo[@"keys"];
    if ([changedKeys isKindOfClass:NSArray.class] &&
        ![changedKeys containsObject:BHTForYouUsernameFilterKeywordsKey] &&
        ![changedKeys containsObject:BHTForYouPostTextFilterKeywordsKey]) {
        return;
    }

    @synchronized(self) {
        BHTKeywordSnapshotsLoaded = NO;
        BHTLoadKeywordSnapshotsLocked();
    }
    BHTPostKeywordChangeNotification(
        BHTForYouKeywordFilterKindUsername);
    BHTPostKeywordChangeNotification(
        BHTForYouKeywordFilterKindPostText);
}

+ (NSArray<NSString*>*)keywordsForKind:
    (BHTForYouKeywordFilterKind)kind {
    @synchronized(self) {
        return [BHTKeywordsForKindLocked(kind) copy];
    }
}

+ (NSArray<NSString*>*)usernameKeywords {
    return [self keywordsForKind:BHTForYouKeywordFilterKindUsername];
}

+ (NSArray<NSString*>*)postTextKeywords {
    return [self keywordsForKind:BHTForYouKeywordFilterKindPostText];
}

+ (BOOL)setKeywords:(NSArray<NSString*>*)keywords
            forKind:(BHTForYouKeywordFilterKind)kind
              error:(NSError**)error {
    NSArray<NSString*>* sanitized =
        BHTSanitizedKeywords(keywords, kind, YES, error);
    if (!sanitized) return NO;

    BOOL changed = NO;
    @synchronized(self) {
        NSArray<NSString*>* current = BHTKeywordsForKindLocked(kind);
        if (![current isEqualToArray:sanitized]) {
            [NSUserDefaults.standardUserDefaults
                setObject:sanitized
                   forKey:BHTPreferenceKeyForKind(kind)];
            BHTSetKeywordSnapshotLocked(sanitized, kind);
            changed = YES;
        }
    }
    if (changed) BHTPostKeywordChangeNotification(kind);
    return YES;
}

+ (BOOL)addKeyword:(NSString*)keyword
           forKind:(BHTForYouKeywordFilterKind)kind
             error:(NSError**)error {
    NSArray<NSString*>* one =
        BHTSanitizedKeywords(@[keyword ?: @""], kind, YES, error);
    if (!one || one.count == 0) return NO;

    NSArray<NSString*>* updated = nil;
    @synchronized(self) {
        NSArray<NSString*>* current = BHTKeywordsForKindLocked(kind);
        if (current.count >= BHTForYouKeywordMaximumCount) {
            if (error) {
                *error = BHTKeywordError(
                    BHTForYouKeywordFilterErrorTooManyKeywords,
                    [NSString
                        stringWithFormat:
                            BHTKeywordLocalized(
                                @"FOR_YOU_FILTERS_TOO_MANY_ERROR_FORMAT",
                                @"Each filter can contain up to %lu "
                                 @"keywords."),
                            (unsigned long)BHTForYouKeywordMaximumCount]);
            }
            return NO;
        }
        if (BHTNormalizedArrayContainsValue(
                current, one.firstObject, kind, NSNotFound)) {
            if (error) {
                *error = BHTKeywordError(
                    BHTForYouKeywordFilterErrorDuplicateKeyword,
                    BHTKeywordLocalized(
                        @"FOR_YOU_FILTERS_DUPLICATE_ERROR",
                        @"That keyword is already in this filter."));
            }
            return NO;
        }
        updated = [current arrayByAddingObject:one.firstObject];
    }
    return [self setKeywords:updated forKind:kind error:error];
}

+ (BOOL)replaceKeywordAtIndex:(NSUInteger)index
                 withKeyword:(NSString*)keyword
                     forKind:(BHTForYouKeywordFilterKind)kind
                       error:(NSError**)error {
    NSArray<NSString*>* one =
        BHTSanitizedKeywords(@[keyword ?: @""], kind, YES, error);
    if (!one || one.count == 0) return NO;

    NSArray<NSString*>* updated = nil;
    @synchronized(self) {
        NSArray<NSString*>* current = BHTKeywordsForKindLocked(kind);
        if (index >= current.count) {
            if (error) {
                *error = BHTKeywordError(
                    BHTForYouKeywordFilterErrorInvalidIndex,
                    BHTKeywordLocalized(
                        @"FOR_YOU_FILTERS_MISSING_ERROR",
                        @"That keyword is no longer in the filter."));
            }
            return NO;
        }
        if (BHTNormalizedArrayContainsValue(
                current, one.firstObject, kind, index)) {
            if (error) {
                *error = BHTKeywordError(
                    BHTForYouKeywordFilterErrorDuplicateKeyword,
                    BHTKeywordLocalized(
                        @"FOR_YOU_FILTERS_DUPLICATE_ERROR",
                        @"That keyword is already in this filter."));
            }
            return NO;
        }
        NSMutableArray<NSString*>* mutable = [current mutableCopy];
        mutable[index] = one.firstObject;
        updated = [mutable copy];
    }
    return [self setKeywords:updated forKind:kind error:error];
}

+ (BOOL)removeKeywordAtIndex:(NSUInteger)index
                     forKind:(BHTForYouKeywordFilterKind)kind {
    NSArray<NSString*>* updated = nil;
    @synchronized(self) {
        NSArray<NSString*>* current = BHTKeywordsForKindLocked(kind);
        if (index >= current.count) return NO;
        NSMutableArray<NSString*>* mutable = [current mutableCopy];
        [mutable removeObjectAtIndex:index];
        updated = [mutable copy];
    }
    return [self setKeywords:updated forKind:kind error:nil];
}

+ (BOOL)hasUsernameFilters {
    @synchronized(self) {
        BHTLoadKeywordSnapshotsLocked();
        return BHTUsernameNeedles.count > 0;
    }
}

+ (BOOL)hasPostTextFilters {
    @synchronized(self) {
        BHTLoadKeywordSnapshotsLocked();
        return BHTPostTextNeedles.count > 0;
    }
}

+ (BOOL)hasActiveFilters {
    @synchronized(self) {
        BHTLoadKeywordSnapshotsLocked();
        return BHTUsernameNeedles.count > 0 ||
               BHTPostTextNeedles.count > 0;
    }
}

+ (BOOL)matchesUsername:(NSString*)username
            displayName:(NSString*)displayName {
    NSMutableArray<NSString*>* candidates =
        [NSMutableArray arrayWithCapacity:2];
    if (username.length > 0) [candidates addObject:username];
    if (displayName.length > 0) [candidates addObject:displayName];
    return [self matchesAnyUsernameCandidate:candidates];
}

+ (BOOL)matchesAnyUsernameCandidate:
    (NSArray<NSString*>*)candidates {
    if (candidates.count == 0) return NO;
    NSArray<NSString*>* needles = nil;
    @synchronized(self) {
        BHTLoadKeywordSnapshotsLocked();
        needles = BHTUsernameNeedles;
    }
    if (needles.count == 0) return NO;

    for (id candidate in candidates) {
        NSString* normalized =
            BHTCanonicalKeyword(candidate,
                                BHTForYouKeywordFilterKindUsername);
        if (normalized.length == 0) continue;
        for (NSString* needle in needles) {
            if ([normalized containsString:needle]) return YES;
        }
    }
    return NO;
}

+ (BOOL)matchesPostText:(NSString*)postText {
    if (postText.length == 0) return NO;
    NSArray<NSString*>* needles = nil;
    @synchronized(self) {
        BHTLoadKeywordSnapshotsLocked();
        needles = BHTPostTextNeedles;
    }
    if (needles.count == 0) return NO;

    NSString* normalized =
        BHTCanonicalKeyword(postText,
                            BHTForYouKeywordFilterKindPostText);
    if (normalized.length == 0) return NO;
    for (NSString* needle in needles) {
        if ([normalized containsString:needle]) return YES;
    }
    return NO;
}

+ (NSUInteger)filterGeneration {
    return [self filterGenerationWithUsernameFilters:NULL
                                     postTextFilters:NULL];
}

+ (NSUInteger)filterGenerationWithUsernameFilters:
                    (BOOL*)hasUsernameFilters
                                  postTextFilters:
                    (BOOL*)hasPostTextFilters {
    @synchronized(self) {
        BHTLoadKeywordSnapshotsLocked();
        if (hasUsernameFilters) {
            *hasUsernameFilters = BHTUsernameNeedles.count > 0;
        }
        if (hasPostTextFilters) {
            *hasPostTextFilters = BHTPostTextNeedles.count > 0;
        }
        return BHTKeywordFilterGeneration;
    }
}

@end
