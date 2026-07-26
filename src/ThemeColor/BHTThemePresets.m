#import "ThemeColor/BHTThemePresets.h"

#import "Headers/TWHeaders.h"
#import "ThemeColor/Palette.h"

NSString* const BHTThemeDidChangeNotification =
    @"BHTThemeDidChangeNotification";
NSString* const BHTThemeColorAccentKey = @"accent";
NSString* const BHTThemeColorBackgroundKey = @"background";
NSString* const BHTThemeColorSurfaceKey = @"surface";
NSString* const BHTThemeColorElevatedSurfaceKey = @"elevatedSurface";
NSString* const BHTThemeColorTextKey = @"text";
NSString* const BHTThemeColorSecondaryTextKey = @"secondaryText";
NSString* const BHTThemeColorSeparatorKey = @"separator";

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
                @"accentHex": @"#0A84FF",
                @"lightColors": @{
                    BHTThemeColorBackgroundKey: @"#F6F7F9",
                    BHTThemeColorSurfaceKey: @"#FFFFFF",
                    BHTThemeColorElevatedSurfaceKey: @"#E9EEF3",
                    BHTThemeColorTextKey: @"#121417",
                    BHTThemeColorSecondaryTextKey: @"#68717D",
                    BHTThemeColorSeparatorKey: @"#D8DEE5"
                },
                @"darkColors": @{
                    BHTThemeColorBackgroundKey: @"#0B0E11",
                    BHTThemeColorSurfaceKey: @"#151A20",
                    BHTThemeColorElevatedSurfaceKey: @"#202832",
                    BHTThemeColorTextKey: @"#F5F7FA",
                    BHTThemeColorSecondaryTextKey: @"#9AA6B2",
                    BHTThemeColorSeparatorKey: @"#2A3540"
                }
            },
            @{
                @"identifier": @"classic_twitter",
                @"titleKey": @"THEME_PRESET_CLASSIC_TWITTER_TITLE",
                @"detailKey": @"THEME_PRESET_CLASSIC_TWITTER_DETAIL",
                @"accentHex": @"#1DA1F2",
                @"lightColors": @{
                    BHTThemeColorBackgroundKey: @"#FFFFFF",
                    BHTThemeColorSurfaceKey: @"#F5F8FA",
                    BHTThemeColorElevatedSurfaceKey: @"#E1E8ED",
                    BHTThemeColorTextKey: @"#14171A",
                    BHTThemeColorSecondaryTextKey: @"#657786",
                    BHTThemeColorSeparatorKey: @"#E1E8ED"
                },
                @"darkColors": @{
                    BHTThemeColorBackgroundKey: @"#15202B",
                    BHTThemeColorSurfaceKey: @"#192734",
                    BHTThemeColorElevatedSurfaceKey: @"#253341",
                    BHTThemeColorTextKey: @"#FFFFFF",
                    BHTThemeColorSecondaryTextKey: @"#8899A6",
                    BHTThemeColorSeparatorKey: @"#38444D"
                }
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

+ (NSDictionary<NSString*, UIColor*>*)
    activeAppColorsForDarkAppearance:(BOOL)darkAppearance {
    NSDictionary* preset =
        [self presetForIdentifier:[self activePresetIdentifier]];
    NSString* mapKey =
        darkAppearance ? @"darkColors" : @"lightColors";
    NSDictionary* rawColors =
        [preset[mapKey] isKindOfClass:NSDictionary.class]
            ? preset[mapKey]
            : nil;
    if (!rawColors) return nil;

    NSArray<NSString*>* requiredRoles = @[
        BHTThemeColorBackgroundKey,
        BHTThemeColorSurfaceKey,
        BHTThemeColorElevatedSurfaceKey,
        BHTThemeColorTextKey,
        BHTThemeColorSecondaryTextKey,
        BHTThemeColorSeparatorKey
    ];
    NSMutableDictionary<NSString*, UIColor*>* colors =
        [NSMutableDictionary dictionaryWithCapacity:requiredRoles.count + 1];
    for (NSString* role in requiredRoles) {
        UIColor* color = [Palette colorFromHexString:rawColors[role]];
        // Reject an incomplete preset atomically. A partial palette could
        // combine incompatible native and custom text/background colors.
        if (!color) return nil;
        colors[role] = color;
    }

    id accentHex = preset[@"accentHex"];
    if ([accentHex isKindOfClass:NSString.class]) {
        UIColor* accent = [Palette colorFromHexString:accentHex];
        if (!accent) return nil;
        colors[BHTThemeColorAccentKey] = accent;
    }
    return [colors copy];
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
