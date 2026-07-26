#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString* const BHTThemeDidChangeNotification;
FOUNDATION_EXPORT NSString* const BHTThemeColorAccentKey;
FOUNDATION_EXPORT NSString* const BHTThemeColorBackgroundKey;
FOUNDATION_EXPORT NSString* const BHTThemeColorSurfaceKey;
FOUNDATION_EXPORT NSString* const BHTThemeColorElevatedSurfaceKey;
FOUNDATION_EXPORT NSString* const BHTThemeColorTextKey;
FOUNDATION_EXPORT NSString* const BHTThemeColorSecondaryTextKey;
FOUNDATION_EXPORT NSString* const BHTThemeColorSeparatorKey;

@interface BHTThemePresets : NSObject

// Each entry contains identifier, titleKey, detailKey, and accentHex. Presets
// that theme the full app also contain complete lightColors/darkColors maps.
// A null accentHex and absent color maps preserve X's native palette.
+ (NSArray<NSDictionary*>*)availablePresets;
+ (nullable NSString*)activePresetIdentifier;
+ (nullable NSDictionary<NSString*, UIColor*>*)
    activeAppColorsForDarkAppearance:(BOOL)darkAppearance;
+ (BOOL)applyPresetIdentifier:(NSString*)identifier;
+ (void)clearPresetSelection;
+ (void)reapplyCurrentAccent;

@end
