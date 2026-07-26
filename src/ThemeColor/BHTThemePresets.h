#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString* const BHTThemeDidChangeNotification;

@interface BHTThemePresets : NSObject

// Each entry contains identifier, titleKey, detailKey, and accentHex. A null
// accentHex selects X's native blue.
+ (NSArray<NSDictionary*>*)availablePresets;
+ (nullable NSString*)activePresetIdentifier;
+ (BOOL)applyPresetIdentifier:(NSString*)identifier;
+ (void)clearPresetSelection;
+ (void)reapplyCurrentAccent;

@end
