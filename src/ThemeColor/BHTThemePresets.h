#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString* const BHTThemeDidChangeNotification;
FOUNDATION_EXPORT NSString* const BHTThemeColorAccentKey;
FOUNDATION_EXPORT NSString* const BHTThemeColorBackgroundKey;
FOUNDATION_EXPORT NSString* const BHTThemeColorSurfaceKey;
FOUNDATION_EXPORT NSString* const BHTThemeColorElevatedSurfaceKey;
FOUNDATION_EXPORT NSString* const BHTThemeColorTextKey;
FOUNDATION_EXPORT NSString* const BHTThemeColorSecondaryTextKey;
FOUNDATION_EXPORT NSString* const BHTThemeColorSeparatorKey;
FOUNDATION_EXPORT NSString* const BHTThemeLibraryDidChangeNotification;
FOUNDATION_EXPORT NSString* const BHTUserThemeLibraryPreferenceKey;

@interface BHTThemePresets : NSObject

// Immutable built-ins. Full themes carry complete lightColors/darkColors maps;
// Native Blue deliberately omits those maps so X remains authoritative.
+ (NSArray<NSDictionary*>*)availablePresets;
+ (NSArray<NSDictionary*>*)userThemes;
+ (NSArray<NSDictionary*>*)allThemes;
+ (nullable NSDictionary*)presetForIdentifier:(nullable NSString*)identifier;
+ (NSString*)displayNameForPreset:(NSDictionary*)preset;
+ (NSString*)displayDetailForPreset:(NSDictionary*)preset;
+ (BOOL)isBuiltInPresetIdentifier:(nullable NSString*)identifier;
+ (BOOL)isUserPresetIdentifier:(nullable NSString*)identifier;
+ (UIColor*)previewAccentColorForPreset:(NSDictionary*)preset
                         darkAppearance:(BOOL)darkAppearance;

// Drafts are complete but remain local to the editor until saveUserTheme.
// Saving only updates the library; callers explicitly choose when to apply.
+ (NSDictionary*)newUserThemeDraftBasedOnPreset:
    (nullable NSDictionary*)preset;
+ (NSDictionary*)duplicateDraftForPreset:(NSDictionary*)preset;
+ (nullable NSDictionary*)saveUserTheme:(NSDictionary*)theme
                                   error:(NSError**)error;
+ (BOOL)deleteUserThemeIdentifier:(NSString*)identifier
                             error:(NSError**)error;

// Preference-profile support. Validation completes before storage changes.
+ (nullable NSArray<NSDictionary*>*)
    validatedUserThemesFromObject:(nullable id)object
                            error:(NSError**)error;
+ (nullable NSArray<NSDictionary*>*)
    userThemesByMergingImportedThemes:(NSArray<NSDictionary*>*)themes
                                error:(NSError**)error;
+ (BOOL)replaceUserThemes:(NSArray<NSDictionary*>*)themes
                    error:(NSError**)error;

+ (nullable NSString*)activePresetIdentifier;
+ (nullable NSDictionary<NSString*, UIColor*>*)
    activeAppColorsForDarkAppearance:(BOOL)darkAppearance;
+ (BOOL)applyPresetIdentifier:(NSString*)identifier;
+ (void)clearPresetSelection;
+ (void)reapplyCurrentAccent;

@end
