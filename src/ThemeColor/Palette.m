//
//  Palette.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "ThemeColor/Palette.h"
#import <objc/runtime.h>

@protocol AEColorPalette <NSObject>
- (UIColor*)backgroundColor;
@end

@interface TAETwitterColorPaletteSettingInfo : NSObject
- (id<AEColorPalette>)colorPalette;
@end

@interface TAEColorSettings : NSObject
+ (instancetype)sharedSettings;
- (TAETwitterColorPaletteSettingInfo*)currentColorPalette;
@end

@implementation Palette

static UIColor* BHTCachedCustomAccent;
static BOOL BHTCustomAccentCacheIsValid = NO;

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

+ (UIColor*)currentBackgroundColor {
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
    }
}

@end
