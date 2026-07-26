//
//  CustomTabBarNativeColors.m
//  NeoFreeBird
//

#import "CustomTabBarNativeColors.h"
#import "ThemeColor/BHTThemePresets.h"
#import "ThemeColor/Palette.h"
#import <objc/runtime.h>

@interface UIColor (NativeTokens)
+ (id)twitterColors;
+ (id)tfnuiColors;
@end

@interface NSObject (NativeTokens)
- (UIColor*)subscriptionMarketingFeatureCardBackgroundColor;
- (UIColor*)subscriptionMarketingFeatureCardShadowColor;
- (UIColor*)tabCustomizationInactiveGridCellContainerBackgroundColor;
- (UIColor*)backgroundColor;
- (UIColor*)navigationBarShadowColor;
- (UIColor*)textColor;
+ (UIColor*)itemColor;
@end

static UIColor* Resolve(id provider, SEL selector, UIColor* fallback) {
    if (provider && [provider respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIColor* color = [provider performSelector:selector];
#pragma clang diagnostic pop
        if ([color isKindOfClass:[UIColor class]]) {
            return color;
        }
    }
    return fallback;
}

static id TwitterColors(void) {
    return [UIColor respondsToSelector:@selector(twitterColors)]
               ? [UIColor twitterColors]
               : nil;
}

static id FNUIColors(void) {
    return [UIColor respondsToSelector:@selector(tfnuiColors)]
               ? [UIColor tfnuiColors]
               : nil;
}

UIColor* CustomTabBarCardBackgroundColor(void) {
    UIColor* custom =
        [Palette customThemeColorForRole:BHTThemeColorSurfaceKey];
    if (custom) return custom;
    return Resolve(TwitterColors(),
                   @selector(subscriptionMarketingFeatureCardBackgroundColor),
                   [UIColor systemBackgroundColor]);
}

UIColor* CustomTabBarInactiveCardBackgroundColor(void) {
    UIColor* custom = [Palette
        customThemeColorForRole:BHTThemeColorElevatedSurfaceKey];
    if (custom) return custom;
    return Resolve(
        TwitterColors(),
        @selector(tabCustomizationInactiveGridCellContainerBackgroundColor),
        [UIColor secondarySystemBackgroundColor]);
}

UIColor* CustomTabBarCardShadowColor(void) {
    return Resolve(TwitterColors(),
                   @selector(subscriptionMarketingFeatureCardShadowColor),
                   [UIColor blackColor]);
}

UIColor* CustomTabBarShadowColor(void) {
    return CustomTabBarCardShadowColor();
}

UIColor* CustomTabBarIconColor(void) {
    UIColor* custom = [Palette
        customThemeColorForRole:BHTThemeColorSecondaryTextKey];
    if (custom) return custom;
    return Resolve(objc_getClass("T1TabView"), @selector(itemColor),
                   [UIColor labelColor]);
}

UIColor* CustomTabBarTitleColor(void) {
    UIColor* custom =
        [Palette customThemeColorForRole:BHTThemeColorTextKey];
    if (custom) return custom;
    return Resolve(FNUIColors(), @selector(textColor), [UIColor labelColor]);
}

UIColor* CustomTabBarScreenBackgroundColor(void) {
    UIColor* custom =
        [Palette customThemeColorForRole:BHTThemeColorBackgroundKey];
    if (custom) return custom;
    return Resolve(TwitterColors(), @selector(backgroundColor),
                   [UIColor systemBackgroundColor]);
}

UIColor* CustomTabBarSeparatorColor(void) {
    UIColor* custom =
        [Palette customThemeColorForRole:BHTThemeColorSeparatorKey];
    if (custom) return custom;
    return Resolve(TwitterColors(), @selector(navigationBarShadowColor),
                   [UIColor separatorColor]);
}
