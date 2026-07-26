//
//  Palette.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "ThemeColor/Palette.h"
#import "ThemeColor/BHTThemePresets.h"
#import <objc/message.h>
#import <objc/runtime.h>
#include <string.h>

@protocol AEColorPalette <NSObject>
- (UIColor*)backgroundColor;
- (UIColor*)alternateBackgroundColor;
- (UIColor*)secondaryBackgroundColor;
- (UIColor*)elevatedBackgroundColor;
- (UIColor*)textColor;
- (UIColor*)detailTextColor;
- (UIColor*)tabBarItemColor;
- (UIColor*)navigationBarShadowColor;
@end

@interface TAETwitterColorPaletteSettingInfo : NSObject
- (id<AEColorPalette>)colorPalette;
- (BOOL)isDark;
@end

@interface TAEColorSettings : NSObject
+ (instancetype)sharedSettings;
- (TAETwitterColorPaletteSettingInfo*)currentColorPalette;
@end

@implementation Palette

static UIColor* BHTCachedCustomAccent;
static BOOL BHTCustomAccentCacheIsValid = NO;
static NSDictionary<NSString*, UIColor*>* BHTCachedLightAppThemeColors;
static NSDictionary<NSString*, UIColor*>* BHTCachedDarkAppThemeColors;
static BOOL BHTAppThemeColorCacheIsValid = NO;

static const char* BHTUnqualifiedPaletteType(const char* type) {
    while (type && strchr("rnNoORV", type[0])) type++;
    return type;
}

static BOOL BHTPaletteObjectGetterIsCompatible(id object, SEL selector) {
    Method method =
        class_getInstanceMethod(object_getClass(object), selector);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* unqualified =
        BHTUnqualifiedPaletteType(returnType);
    return unqualified && unqualified[0] == '@';
}

static BOOL BHTPaletteBoolGetterIsCompatible(id object, SEL selector) {
    Method method =
        class_getInstanceMethod(object_getClass(object), selector);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* unqualified =
        BHTUnqualifiedPaletteType(returnType);
    return unqualified && strchr("BcC", unqualified[0]) != NULL;
}

+ (TAETwitterColorPaletteSettingInfo*)currentPaletteInfo {
    Class settingsClass = objc_getClass("TAEColorSettings");
    if (![settingsClass respondsToSelector:@selector(sharedSettings)]) {
        return nil;
    }

    id settings = [settingsClass sharedSettings];
    if (![settings respondsToSelector:@selector(currentColorPalette)]) {
        return nil;
    }

    return [settings currentColorPalette];
}

+ (UIColor*)nativeCurrentBackgroundColor {
    TAETwitterColorPaletteSettingInfo* info = [self currentPaletteInfo];
    if ([info respondsToSelector:@selector(colorPalette)]) {
        id<AEColorPalette> palette = [info colorPalette];
        if ([palette respondsToSelector:@selector(backgroundColor)]) {
            UIColor* background = [palette backgroundColor];
            if (background) {
                return background;
            }
        }
    }
    return [UIColor systemBackgroundColor];
}

+ (BOOL)currentPaletteUsesDarkAppearance {
    id info = [self currentPaletteInfo];
    SEL darkSelector = @selector(isDark);
    if (info && [info respondsToSelector:darkSelector] &&
        BHTPaletteBoolGetterIsCompatible(info, darkSelector)) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(info, darkSelector);
    }

    UIUserInterfaceStyle style =
        UITraitCollection.currentTraitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) {
        style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    }
    return style == UIUserInterfaceStyleDark;
}

+ (id<AEColorPalette>)currentNativePalette {
    id info = [self currentPaletteInfo];
    SEL paletteSelector = @selector(colorPalette);
    if (!info || ![info respondsToSelector:paletteSelector] ||
        !BHTPaletteObjectGetterIsCompatible(info, paletteSelector)) {
        return nil;
    }
    id palette =
        ((id (*)(id, SEL))objc_msgSend)(info, paletteSelector);
    return [palette isKindOfClass:NSObject.class] ? palette : nil;
}

+ (UIColor*)nativeColorForSelectorNames:(NSArray<NSString*>*)selectorNames
                               fallback:(UIColor*)fallback {
    id palette = [self currentNativePalette];
    for (NSString* selectorName in selectorNames) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![palette respondsToSelector:selector] ||
            !BHTPaletteObjectGetterIsCompatible(palette, selector)) {
            continue;
        }
        id value =
            ((id (*)(id, SEL))objc_msgSend)(palette, selector);
        if ([value isKindOfClass:UIColor.class]) {
            return value;
        }
    }
    return fallback;
}

+ (NSDictionary<NSString*, UIColor*>*)
    customThemeColorsForDarkAppearance:(BOOL)darkAppearance {
    @synchronized(self) {
        if (!BHTAppThemeColorCacheIsValid) {
            BHTCachedLightAppThemeColors =
                [BHTThemePresets
                    activeAppColorsForDarkAppearance:NO];
            BHTCachedDarkAppThemeColors =
                [BHTThemePresets
                    activeAppColorsForDarkAppearance:YES];
            BHTAppThemeColorCacheIsValid = YES;
        }
        return darkAppearance ? BHTCachedDarkAppThemeColors
                              : BHTCachedLightAppThemeColors;
    }
}

+ (UIColor*)customThemeColorForRole:(NSString*)role {
    if (![role isKindOfClass:NSString.class]) return nil;
    return [self
        customThemeColorsForDarkAppearance:
            [self currentPaletteUsesDarkAppearance]][role];
}

+ (UIColor*)currentBackgroundColor {
    return [self customThemeColorForRole:BHTThemeColorBackgroundKey] ?:
        [self nativeCurrentBackgroundColor];
}

+ (UIColor*)currentSurfaceColor {
    return [self customThemeColorForRole:BHTThemeColorSurfaceKey] ?:
        [self nativeColorForSelectorNames:@[
            @"secondaryBackgroundColor",
            @"alternateBackgroundColor",
            @"cardBackgroundColor",
            @"backgroundColor"
        ]
                                 fallback:
                                     UIColor.secondarySystemBackgroundColor];
}

+ (UIColor*)currentElevatedSurfaceColor {
    return [self
               customThemeColorForRole:BHTThemeColorElevatedSurfaceKey] ?:
        [self nativeColorForSelectorNames:@[
            @"elevatedBackgroundColor",
            @"cardBackgroundColor",
            @"secondaryBackgroundColor",
            @"backgroundColor"
        ]
                                 fallback:
                                     UIColor.tertiarySystemBackgroundColor];
}

+ (UIColor*)currentTextColor {
    return [self customThemeColorForRole:BHTThemeColorTextKey] ?:
        [self nativeColorForSelectorNames:@[
            @"textColor",
            @"baseTextColor",
            @"defaultTextColor",
            @"textDefaultColor"
        ]
                                 fallback:UIColor.labelColor];
}

+ (UIColor*)currentSecondaryTextColor {
    return [self
               customThemeColorForRole:BHTThemeColorSecondaryTextKey] ?:
        [self nativeColorForSelectorNames:@[
            @"detailTextColor",
            @"textDetailsColor",
            @"tabBarItemColor",
            @"placeholderTextColor"
        ]
                                 fallback:UIColor.secondaryLabelColor];
}

+ (UIColor*)currentSeparatorColor {
    return [self customThemeColorForRole:BHTThemeColorSeparatorKey] ?:
        [self nativeColorForSelectorNames:@[
            @"navigationBarShadowColor",
            @"separatorColor"
        ]
                                 fallback:UIColor.separatorColor];
}

+ (NSString*)normalizedHexString:(NSString*)hexString {
    if (![hexString isKindOfClass:NSString.class]) return nil;
    NSString* candidate =
        [[hexString stringByTrimmingCharactersInSet:
                        NSCharacterSet.whitespaceAndNewlineCharacterSet]
            uppercaseString];
    if ([candidate hasPrefix:@"#"]) {
        candidate = [candidate substringFromIndex:1];
    }
    if (candidate.length != 6 && candidate.length != 8) return nil;
    NSCharacterSet* allowed =
        [NSCharacterSet
            characterSetWithCharactersInString:@"0123456789ABCDEF"];
    NSCharacterSet* invalid = [allowed invertedSet];
    if ([candidate rangeOfCharacterFromSet:invalid].location != NSNotFound) {
        return nil;
    }
    return [@"#" stringByAppendingString:candidate];
}

+ (UIColor*)colorFromHexString:(NSString*)hexString {
    NSString* normalized = [self normalizedHexString:hexString];
    if (!normalized) return nil;
    NSString* digits = [normalized substringFromIndex:1];
    unsigned long long raw = 0;
    [[NSScanner scannerWithString:digits] scanHexLongLong:&raw];
    CGFloat red = 0;
    CGFloat green = 0;
    CGFloat blue = 0;
    CGFloat alpha = 1;
    if (digits.length == 8) {
        red = ((raw >> 24) & 0xFF) / 255.0;
        green = ((raw >> 16) & 0xFF) / 255.0;
        blue = ((raw >> 8) & 0xFF) / 255.0;
        alpha = (raw & 0xFF) / 255.0;
    } else {
        red = ((raw >> 16) & 0xFF) / 255.0;
        green = ((raw >> 8) & 0xFF) / 255.0;
        blue = (raw & 0xFF) / 255.0;
    }
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

+ (UIColor*)customAccentColor {
    static dispatch_once_t observerToken;
    dispatch_once(&observerToken, ^{
        [NSNotificationCenter.defaultCenter
            addObserverForName:@"BHTSettingsProfileDidApplyNotification"
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification* note) {
                        [self invalidateCustomAccentColorCache];
                    }];
    });
    @synchronized(self) {
        if (!BHTCustomAccentCacheIsValid) {
            NSString* stored = [NSUserDefaults.standardUserDefaults
                stringForKey:@"bht_custom_accent_hex"];
            BHTCachedCustomAccent = [self colorFromHexString:stored];
            BHTCustomAccentCacheIsValid = YES;
        }
        return BHTCachedCustomAccent;
    }
}

+ (void)invalidateCustomAccentColorCache {
    @synchronized(self) {
        BHTCachedCustomAccent = nil;
        BHTCustomAccentCacheIsValid = NO;
        BHTCachedLightAppThemeColors = nil;
        BHTCachedDarkAppThemeColors = nil;
        BHTAppThemeColorCacheIsValid = NO;
    }
}

@end
