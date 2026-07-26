//
//  Palette.h
//  NeoFreeBird
//
//  Created by nyaathea
//

#import <UIKit/UIKit.h>

@interface Palette : NSObject

/**
 * Twitter's current app background color, read straight from the active
 * TAEColorPalette so it always matches the app chrome.
 */
+ (UIColor*)currentBackgroundColor;

// NeoFreeBird's optional custom accent. A nil result means the native X color
// picker remains authoritative.
+ (nullable UIColor*)customAccentColor;
+ (void)invalidateCustomAccentColorCache;
+ (nullable UIColor*)colorFromHexString:(nullable NSString*)hexString;
+ (nullable NSString*)normalizedHexString:(nullable NSString*)hexString;

@end
