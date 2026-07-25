//
//  BHTdownloadManager.h
//  BHT
//
//  Created by BandarHelal on 24/12/1441 AH.
//

#import "Headers/TWHeaders.h"

@interface BHTManager : NSObject
+ (void)cleanCache;
+ (NSURL*)temporaryDirectoryURL;
+ (NSURL*)temporaryFileURLWithExtension:(NSString*)extension;
+ (NSString*)getVideoQuality:(NSString*)url;
+ (id)sharedFontGroup;
+ (UIFont*)menuTitleFont;
+ (BOOL)doesContainDigitsOnly:(NSString*)string;
+ (UIViewController*)BHTSettingsWithAccount:(TFNTwitterAccount*)twAccount;
+ (void)showSaveVC:(NSURL*)url;
+ (void)save:(NSURL*)url;
+ (void)saveGIF:(NSURL*)url;
+ (void)save:(NSURL*)url
   completion:(void (^_Nullable)(BOOL success,
                                  NSError* _Nullable error))completion;
+ (void)saveGIF:(NSURL*)url
      completion:(void (^_Nullable)(BOOL success,
                                     NSError* _Nullable error))completion;
+ (MediaInformation*)getM3U8Information:(NSURL*)mediaURL;
+ (NSString*)getDownloadingPercent:(float)progress;

+ (BOOL)isTwitterBranded;

@end
