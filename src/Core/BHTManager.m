//
//  BHTdownloadManager.m
//  BHTwitter
//
//  Created by BandarHelal.
//

#import "Core/BHTManager.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Settings/ModernSettingsViewController.h"

static NSURL* BHTOwnedTemporaryDirectoryURL(void) {
    return [[NSURL fileURLWithPath:NSTemporaryDirectory()
                      isDirectory:YES]
        URLByAppendingPathComponent:@"NeoFreeBird"
                       isDirectory:YES];
}

static BOOL BHTIsOwnedTemporaryURL(NSURL* url) {
    if (!url.isFileURL) return NO;
    NSString* directory =
        BHTOwnedTemporaryDirectoryURL().URLByStandardizingPath.path;
    NSString* candidate = url.URLByStandardizingPath.path;
    if (directory.length == 0 || candidate.length == 0) return NO;
    NSString* prefix = [directory stringByAppendingString:@"/"];
    return [candidate hasPrefix:prefix];
}

@implementation BHTManager

+ (NSURL*)temporaryDirectoryURL {
    NSURL* directory = BHTOwnedTemporaryDirectoryURL();
    @synchronized(self) {
        [[NSFileManager defaultManager]
            createDirectoryAtURL:directory
     withIntermediateDirectories:YES
                      attributes:nil
                           error:nil];
    }
    return directory;
}

+ (NSURL*)temporaryFileURLWithExtension:(NSString*)extension {
    NSString* candidate =
        [[extension ?: @"tmp"
            stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]]
            stringByTrimmingCharactersInSet:
                [NSCharacterSet characterSetWithCharactersInString:@"."]];
    NSCharacterSet* invalid =
        [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    NSString* safeExtension =
        [[candidate componentsSeparatedByCharactersInSet:invalid]
            componentsJoinedByString:@""];
    if (safeExtension.length == 0) safeExtension = @"tmp";

    NSString* filename =
        [NSString stringWithFormat:@"%@.%@",
                                   NSUUID.UUID.UUIDString,
                                   safeExtension.lowercaseString];
    return [[self temporaryDirectoryURL]
        URLByAppendingPathComponent:filename
                       isDirectory:NO];
}

+ (void)cleanCache {
    // Never sweep X's Documents directory or its shared temporary tree. Those
    // locations contain host-app state that can be live during launch. Every
    // NeoFreeBird export now lives under this owned directory, so cleanup is
    // both complete and isolated.
    NSURL* directory = BHTOwnedTemporaryDirectoryURL();
    @synchronized(self) {
        [[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
        [[NSFileManager defaultManager]
            createDirectoryAtURL:directory
     withIntermediateDirectories:YES
                      attributes:nil
                           error:nil];
    }
}
+ (id)sharedFontGroup {
    // The compatible host runtime uses TFNUIDefaultFontGroup. Keep the older name as a harmless
    // fallback so the settings UI can still render on nearby app versions.
    Class fontGroupClass = objc_getClass("TFNUIDefaultFontGroup");
    if (!fontGroupClass) {
        fontGroupClass = objc_getClass("TAEStandardFontGroup");
    }
    return [fontGroupClass sharedFontGroup];
}
+ (UIFont*)menuTitleFont {
    UIFont* font = [[self sharedFontGroup] headline2BoldFont];
    if (!font)
        font = [UIFont boldSystemFontOfSize:17.0];
    return font;
}
+ (NSString*)getVideoQuality:(NSString*)url {
    NSMutableArray* q = [NSMutableArray new];
    NSArray* splits = [url componentsSeparatedByString:@"/"];
    for (int i = 0; i < [splits count]; i++) {
        NSString* item = [splits objectAtIndex:i];
        NSArray* dir = [item componentsSeparatedByString:@"x"];
        for (int k = 0; k < [dir count]; k++) {
            NSString* item2 = [dir objectAtIndex:k];
            if (!(item2.length == 0)) {
                if ([BHTManager doesContainDigitsOnly:item2]) {
                    if (!(item2.integerValue > 10000)) {
                        if (!(q.count == 2)) {
                            [q addObject:item2];
                        }
                    }
                }
            }
        }
    }
    if (q.count == 0) {
        return @"GIF";
    }
    return [NSString stringWithFormat:@"%@x%@", q.firstObject, q.lastObject];
}
+ (void)save:(NSURL*)url {
    [self save:url completion:nil];
}
+ (void)saveGIF:(NSURL*)url {
    [self saveGIF:url completion:nil];
}
+ (void)save:(NSURL*)url
   completion:(void (^)(BOOL success, NSError* error))completion {
    if (!url) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"com.bhtwitter.media"
                                               code:1
                                           userInfo:@{
                                               NSLocalizedDescriptionKey:
                                                   @"The video file is unavailable."
                                           }]);
        }
        return;
    }
    [[PHPhotoLibrary sharedPhotoLibrary]
        performChanges:^{
            [PHAssetChangeRequest
                creationRequestForAssetFromVideoAtFileURL:url];
        }
        completionHandler:^(BOOL success, NSError* error) {
            if (!completion) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(success, error);
            });
        }];
}
+ (void)saveGIF:(NSURL*)url
      completion:(void (^)(BOOL success, NSError* error))completion {
    if (!url) {
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"com.bhtwitter.media"
                                               code:2
                                           userInfo:@{
                                               NSLocalizedDescriptionKey:
                                                   @"The image file is unavailable."
                                           }]);
        }
        return;
    }
    [[PHPhotoLibrary sharedPhotoLibrary]
        performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:url];
        }
        completionHandler:^(BOOL success, NSError* error) {
            if (!completion) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(success, error);
            });
        }];
}
+ (void)showSaveVC:(NSURL*)url {
    if (!url) return;
    dispatch_block_t presentation = ^{
        UIViewController* presenter = topMostController();
        if (!presenter) return;

        UIActivityViewController* activity =
            [[UIActivityViewController alloc]
                initWithActivityItems:@[url]
                applicationActivities:nil];
        activity.completionWithItemsHandler =
            ^(__unused UIActivityType activityType, __unused BOOL completed,
              __unused NSArray* returnedItems, __unused NSError* error) {
                if (BHTIsOwnedTemporaryURL(url)) {
                    [[NSFileManager defaultManager]
                        removeItemAtURL:url
                                 error:nil];
                }
            };
        if (is_iPad()) {
            UIView* sourceView = presenter.view;
            if (!sourceView) return;
            activity.popoverPresentationController.sourceView = sourceView;
            activity.popoverPresentationController.sourceRect =
                CGRectMake(CGRectGetMidX(sourceView.bounds),
                           CGRectGetMidY(sourceView.bounds), 1.0, 1.0);
        }
        [presenter presentViewController:activity
                               animated:YES
                             completion:nil];
    };
    if (NSThread.isMainThread) {
        presentation();
    } else {
        dispatch_async(dispatch_get_main_queue(), presentation);
    }
}

+ (MediaInformation*)getM3U8Information:(NSURL*)mediaURL {
    MediaInformationSession* mediaInformationSession =
        [FFprobeKit getMediaInformation:mediaURL.absoluteString];
    MediaInformation* mediaInformation =
        [mediaInformationSession getMediaInformation];
    return mediaInformation;
}
+ (NSString*)getDownloadingPercent:(float)progress {
    NSNumberFormatter* numberFormatter = [[NSNumberFormatter alloc] init];
    [numberFormatter setNumberStyle:NSNumberFormatterPercentStyle];
    return [numberFormatter stringFromNumber:[NSNumber numberWithFloat:progress]];
}

+ (BOOL)isTwitterBranded {
    static BOOL branded = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        branded = [[[NSBundle mainBundle] infoDictionary][@"CFBundleDisplayName"]
            isEqual:@"Twitter"];
    });
    return branded;
}

+ (UIViewController*)BHTSettingsWithAccount:(TFNTwitterAccount*)twAccount {
    return [[ModernSettingsViewController alloc] initWithAccount:twAccount];
}

// https://stackoverflow.com/a/45356575/9910699
+ (BOOL)doesContainDigitsOnly:(NSString*)string {
    NSCharacterSet* nonDigits =
        [[NSCharacterSet decimalDigitCharacterSet] invertedSet];

    BOOL containsDigitsOnly =
        [string rangeOfCharacterFromSet:nonDigits].location == NSNotFound;

    return containsDigitsOnly;
}

@end
