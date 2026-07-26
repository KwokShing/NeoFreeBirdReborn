#import "ThemeColor/BHTThemePresets.h"

#import "Headers/TWHeaders.h"
#import "ThemeColor/Palette.h"

NSString* const BHTThemeDidChangeNotification =
    @"BHTThemeDidChangeNotification";

@implementation BHTThemePresets

+ (NSArray<NSDictionary*>*)availablePresets {
    static NSArray<NSDictionary*>* presets;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        presets = @[
            @{
                @"identifier": @"apollo_inspired",
                @"titleKey": @"THEME_PRESET_APOLLO_TITLE",
                @"detailKey": @"THEME_PRESET_APOLLO_DETAIL",
                // Apollo-inspired, not an assertion that this is Apollo's
                // proprietary exact palette.
                @"accentHex": @"#0A84FF"
            },
            @{
                @"identifier": @"classic_twitter",
                @"titleKey": @"THEME_PRESET_CLASSIC_TWITTER_TITLE",
                @"detailKey": @"THEME_PRESET_CLASSIC_TWITTER_DETAIL",
                @"accentHex": @"#1DA1F2"
            },
            @{
                @"identifier": @"native_blue",
                @"titleKey": @"THEME_PRESET_NATIVE_BLUE_TITLE",
                @"detailKey": @"THEME_PRESET_NATIVE_BLUE_DETAIL",
                @"accentHex": NSNull.null
            }
        ];
    });
    return presets;
}

+ (NSDictionary*)presetForIdentifier:(NSString*)identifier {
    for (NSDictionary* preset in [self availablePresets]) {
        if ([preset[@"identifier"] isEqualToString:identifier]) {
            return preset;
        }
    }
    return nil;
}

+ (NSString*)activePresetIdentifier {
    NSString* stored = [NSUserDefaults.standardUserDefaults
        stringForKey:@"bht_theme_preset_identifier"];
    NSDictionary* preset = [self presetForIdentifier:stored];
    if (!preset) return nil;

    NSString* storedHex = [Palette normalizedHexString:
        [NSUserDefaults.standardUserDefaults
            stringForKey:@"bht_custom_accent_hex"]];
    id presetHex = preset[@"accentHex"];
    if (presetHex == NSNull.null) {
        return storedHex ? nil : stored;
    }
    return [storedHex isEqualToString:
                          [Palette normalizedHexString:presetHex]]
               ? stored
               : nil;
}

+ (BOOL)applyPresetIdentifier:(NSString*)identifier {
    NSDictionary* preset = [self presetForIdentifier:identifier];
    if (!preset) return NO;

    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    id accentHex = preset[@"accentHex"];
    if (accentHex == NSNull.null) {
        [defaults removeObjectForKey:@"bht_custom_accent_hex"];
    } else {
        NSString* normalized = [Palette normalizedHexString:accentHex];
        if (!normalized) return NO;
        [defaults setObject:normalized forKey:@"bht_custom_accent_hex"];
    }
    [defaults setInteger:1 forKey:@"bh_color_theme_selectedColor"];
    [defaults setObject:identifier forKey:@"bht_theme_preset_identifier"];
    [Palette invalidateCustomAccentColorCache];

    // Let X run its normal live theme update. CurrentAccentColor then supplies
    // the optional custom color to NeoFreeBird-owned accents and branding.
    [self reapplyCurrentAccent];
    [NSNotificationCenter.defaultCenter
        postNotificationName:BHTThemeDidChangeNotification
                      object:nil];
    return YES;
}

+ (void)reapplyCurrentAccent {
    Class settingsClass = objc_getClass("TAEColorSettings");
    if (![settingsClass respondsToSelector:@selector(sharedSettings)]) return;
    id settings = [settingsClass sharedSettings];
    if (![settings respondsToSelector:@selector(setPrimaryColorOption:)]) {
        return;
    }
    NSInteger option = [NSUserDefaults.standardUserDefaults
        integerForKey:@"bh_color_theme_selectedColor"];
    changeTwitterColor(MIN(6, MAX(1, option)));
}

+ (void)clearPresetSelection {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:@"bht_theme_preset_identifier"];
    [defaults removeObjectForKey:@"bht_custom_accent_hex"];
    [Palette invalidateCustomAccentColorCache];
    [NSNotificationCenter.defaultCenter
        postNotificationName:BHTThemeDidChangeNotification
                      object:nil];
}

@end
