#import "Likes/BHTLikesTab.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <ImageIO/ImageIO.h>
#import <mach-o/dyld.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <string.h>

#import "Core/BHTBundle.h"
#import "CustomTabBar/CustomTabBarUtility.h"
#import "Headers/TWHeaders.h"
#import "Hooks/HookHelpers.h"
#import "Likes/BHTLikesNavigationUtility.h"
#import "MediaActions/BHTMediaActionUtility.h"
#import "ThemeColor/BHTThemePresets.h"
#import "ThemeColor/Palette.h"

static NSString* const kBHTLikesPage = @"likes";
static char kBHTLikesEntryKey;
static char kBHTRetainedNativeLikesEntryKey;
static char kBHTNativeLikesEntryMarkerKey;
static char kBHTInjectedNativeLikesEntryKey;
static char kBHTOriginalNativePageKey;
static char kBHTNativeLikesNavigationMarkerKey;
static char kBHTNativeLikesControllerKey;
static char kBHTNativeLikesNavigationKey;
static char kBHTNativeLikesTabViewKey;
static char kBHTInitialResetPanMarkerKey;
static const long long kBHTLikesPanelID = 6; // Audited Bookmarks panel
static const uintptr_t kBHTAuditedEntryFactoryOffset = 0x6CAFE8;
static const uintptr_t kBHTAuditedEntryFactoryJumpTableOffset = 0x1329880;
static const uintptr_t kBHTAuditedBookmarksFactoryCaseOffset = 0x6CB26C;

static NSObject* BHTLikesDiagnosticsLock(void) {
    static NSObject* lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static NSMutableDictionary* BHTMutableLikesDiagnostics(void) {
    static NSMutableDictionary* diagnostics;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        diagnostics = [@{
            @"activityHistoryInitialTab": @4,
            @"navigationMode": @"nativeBookmarksCarrier",
            @"photoRequestVariant": @"orig",
            @"waterfallPreviewVariant": @"medium",
            @"waterfallImageScaling": @"completeAspectFitWithDecodedRatioCorrection",
            @"waterfallAspectRatioPolicy": @"metadataThenDecodedImageAdaptiveMasonry",
            @"waterfallColumnSpanPolicy": @"wideMediaMaySpanAdjacentColumns",
            @"waterfallDecodedRatioCorrections": @0,
            @"waterfallAnchorPreservations": @0,
            @"waterfallSelectorInstalls": @0,
            @"waterfallSelectorOwned": @NO,
            @"waterfallSelectorSizingPolicy":
                @"nativeArtworkMinimum216x32",
            @"waterfallSelectorGeometryState": @"notCreated",
            @"waterfallSelectorHeight": @0,
            @"waterfallSelectorIntrinsicHeight": @0,
            @"waterfallSelectorFittingHeight": @0,
            @"waterfallSelectorHidden": @YES,
            @"waterfallSelectorAlpha": @0,
            @"waterfallSelectorWindowAttached": @NO,
            @"waterfallSelectorSuperviewClass": @"none",
            @"waterfallSelectorCustomBackgroundArtwork": @NO,
            @"waterfallNavigationBarHidden": @NO,
            @"waterfallNavigationBarHeight": @0,
            @"waterfallNavigationTopControllerMatches": @NO,
            @"waterfallActionSheet": @"UIContextMenuInteraction",
            @"waterfallActionFallback": @"TFNMenuSheetViewController",
            @"viewerDismissal": @"percentDrivenModal",
            @"viewerPresentation": @"windowFullScreen",
            @"viewerRotationPolicy": @"deviceAndHostSupported",
            @"viewerFullScreenAttempts": @0,
            @"viewerFullScreenActivations": @0,
            @"viewerFullScreenMeasured": @NO,
            @"viewerFullScreenCoverage": @NO,
            @"decodedImageCacheLimitMB": @128,
            @"imageRequestPolicy": @"coalescedByURLAndPixelBucket",
            @"imageRequestsStarted": @0,
            @"imageRequestsCoalesced": @0,
            @"imageRequestsCancelled": @0,
            @"videoVariantPolicy": @"highestBitrateMP4",
            @"rootHookInstalled": @YES,
            @"nativeRootCreations": @0,
            @"nativeSurfaceCreations": @0,
            @"nativeEntryFactoryAttempts": @0,
            @"nativeEntryFactorySuccesses": @0,
            @"nativeNavigationInstalls": @0,
            @"factoryRequests": @0,
            @"contentControllerRequests": @0,
            @"tabActivations": @0,
            @"topResets": @0,
            @"capturedMediaItems": @0,
            @"postRouteAttempts": @0,
            @"postURLAcceptances": @0
        } mutableCopy];
    });
    return diagnostics;
}

static void BHTSetLikesDiagnostic(NSString* key, id value) {
    if (key.length == 0 || !value) return;
    @synchronized(BHTLikesDiagnosticsLock()) {
        BHTMutableLikesDiagnostics()[key] = value;
    }
}

static void BHTIncrementLikesDiagnostic(NSString* key) {
    if (key.length == 0) return;
    @synchronized(BHTLikesDiagnosticsLock()) {
        NSMutableDictionary* diagnostics = BHTMutableLikesDiagnostics();
        diagnostics[key] = @([diagnostics[key] unsignedIntegerValue] + 1);
    }
}

NSDictionary* BHTLikesDiagnosticsSnapshot(void) {
    @synchronized(BHTLikesDiagnosticsLock()) {
        NSMutableDictionary* snapshot =
            [BHTMutableLikesDiagnostics() mutableCopy];
        snapshot[@"tabEnabledByCustomNavigation"] =
            @([CustomTabBarUtility likesTabEnabled]);
        snapshot[@"configuredActivityHistoryTabs"] =
            [BHTLikesNavigationUtility visiblePageIDsInOrder];
        snapshot[@"waterfallEnabled"] =
            @([BHTLikesNavigationUtility waterfallEnabled]);
        return [snapshot copy];
    }
}

NSString* BHTLikesPageID(void) {
    return kBHTLikesPage;
}

static id BHTSafeValue(id object, NSString* key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

static id BHTCallObject(id receiver, NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return [receiver respondsToSelector:selector]
               ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector)
               : nil;
}

static UIViewController* BHTFindController(UIViewController* root, Class wanted) {
    if (!root || !wanted) return nil;
    if ([root isKindOfClass:wanted]) return root;
    for (UIViewController* child in root.childViewControllers) {
        UIViewController* result = BHTFindController(child, wanted);
        if (result) return result;
    }
    return BHTFindController(root.presentedViewController, wanted);
}

void BHTRefreshVisibleAppTabs(void) {
    Class navigationClass = NSClassFromString(@"T1TabbedAppNavigationViewController");
    if (!navigationClass) return;
    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        UIViewController* controller =
            BHTFindController(window.rootViewController, navigationClass);
        if ([controller respondsToSelector:@selector(recalculateVisiblePanels)]) {
            ((void (*)(id, SEL))objc_msgSend)(controller,
                                              @selector(recalculateVisiblePanels));
            return;
        }
    }
}

#pragma mark - Native Likes timeline construction

static id BHTCurrentAccount(void) {
    Class hostClass = NSClassFromString(@"T1HostViewController");
    id host = [hostClass respondsToSelector:@selector(sharedHostViewController)]
                  ? ((id (*)(id, SEL))objc_msgSend)(hostClass,
                                                    @selector(sharedHostViewController))
                  : nil;
    return [host respondsToSelector:@selector(currentAccount)]
               ? ((id (*)(id, SEL))objc_msgSend)(host, @selector(currentAccount))
               : nil;
}

static id BHTInvokeAccountFactory(id receiver, SEL selector, id account) {
    if (!receiver || !selector || ![receiver respondsToSelector:selector]) return nil;
    NSMethodSignature* signature = [receiver methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 3 ||
        signature.methodReturnLength == 0) {
        return nil;
    }
    NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = receiver;
    invocation.selector = selector;
    id argument = account;
    [invocation setArgument:&argument atIndex:2];
    [invocation invoke];
    __unsafe_unretained id result = nil;
    [invocation getReturnValue:&result];
    return result;
}

static UIViewController* BHTMakeNativeLikesController(id account) {
    Class factoryClass = NSClassFromString(@"T1URTFavoritesViewControllerFactory");
    NSArray<NSString*>* selectors = @[
        @"makeViewControllerWithAccount:",
        @"viewControllerWithAccount:",
        @"makeFavoritesViewControllerWithAccount:",
        @"favoritesViewControllerWithAccount:"
    ];
    // Prefer the dedicated Favorites factory: unlike Activity History it needs
    // no guessed tab enum.
    for (NSString* name in selectors) {
        id result = BHTInvokeAccountFactory(factoryClass,
                                            NSSelectorFromString(name), account);
        if ([result isKindOfClass:UIViewController.class]) return result;
    }

    id factory = [factoryClass respondsToSelector:@selector(new)]
                     ? [factoryClass new]
                     : nil;
    for (NSString* name in selectors) {
        id result = BHTInvokeAccountFactory(factory,
                                            NSSelectorFromString(name), account);
        if ([result isKindOfClass:UIViewController.class]) return result;
    }

    // The compatible host runtime also exposes Likes through Activity History. Keep this as the
    // compatibility fallback and report the selector so device logs can
    // confirm whether it remains available.
    Class bridge = NSClassFromString(@"T1ActivityHistoryBridge");
    SEL bridgeSelector =
        NSSelectorFromString(@"makeActivityHistoryViewControllerWithAccount:initialTab:");
    if ([bridge respondsToSelector:bridgeSelector]) {
        NSMethodSignature* signature = [bridge methodSignatureForSelector:bridgeSelector];
        if (signature.numberOfArguments == 4) {
            NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
            invocation.target = bridge;
            invocation.selector = bridgeSelector;
            id accountArgument = account;
            // The audited runtime's bridge enum is one-based even though its segmented
            // control is zero-based: 3 opens Articles and 4 opens Likes. The
            // device report confirms this bridge is the available factory.
            NSInteger likesTab = 4;
            [invocation setArgument:&accountArgument atIndex:2];
            [invocation setArgument:&likesTab atIndex:3];
            [invocation invoke];
            __unsafe_unretained id result = nil;
            [invocation getReturnValue:&result];
            if ([result isKindOfClass:UIViewController.class]) return result;
        }
    }
    return nil;
}

#pragma mark - Media model extraction

@interface BHTLikedMediaItem : NSObject
@property(nonatomic, copy) NSString* identifier;
@property(nonatomic, strong) NSURL* previewURL;
@property(nonatomic, strong) NSURL* originalURL;
@property(nonatomic, strong) NSURL* videoURL;
@property(nonatomic, strong) id mediaEntity;
@property(nonatomic) BHTMediaActionKind mediaActionKind;
@property(nonatomic) CGFloat aspectRatio;
@property(nonatomic) BOOL aspectRatioConfirmedByImage;
@property(nonatomic) long long statusID;
@property(nonatomic, copy) NSString* statusText;
@property(nonatomic, strong) NSURL* statusURL;
@end

@implementation BHTLikedMediaItem
@end

static CGFloat BHTBoundedMediaAspectRatio(CGFloat ratio) {
    if (!isfinite(ratio) || ratio <= 0) return 1.0;
    // Keep pathological or corrupt metadata from producing unbounded layout
    // attributes while still accommodating long screenshots and panoramas.
    return MAX(0.10, MIN(10.0, ratio));
}

static CGFloat BHTDecodedImageAspectRatio(UIImage* image) {
    if (!image) return 0;
    CGSize size = image.size;
    if (!isfinite(size.width) || !isfinite(size.height) ||
        size.width <= 0 || size.height <= 0) {
        return 0;
    }
    return BHTBoundedMediaAspectRatio(size.width / size.height);
}

static NSURL* BHTPhotoURLForVariant(NSString* rawURL,
                                    NSString* variant) {
    if (rawURL.length == 0) return nil;
    NSURLComponents* components = [NSURLComponents componentsWithString:rawURL];
    if (!components) return [NSURL URLWithString:rawURL];

    NSString* extension = components.path.pathExtension.lowercaseString;
    if (extension.length > 0) {
        components.path = [components.path stringByDeletingPathExtension];
    }

    NSMutableArray<NSURLQueryItem*>* items = [NSMutableArray array];
    BOOL hasFormat = NO;
    for (NSURLQueryItem* item in components.queryItems ?: @[]) {
        if ([item.name isEqualToString:@"name"]) continue;
        if ([item.name isEqualToString:@"format"]) hasFormat = YES;
        [items addObject:item];
    }
    if (!hasFormat && extension.length > 0) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"format" value:extension]];
    }
    [items addObject:
        [NSURLQueryItem queryItemWithName:@"name"
                                    value:variant.length ? variant : @"orig"]];
    components.queryItems = items;
    return components.URL ?: [NSURL URLWithString:rawURL];
}

static NSURL* BHTOriginalPhotoURL(NSString* rawURL) {
    return BHTPhotoURLForVariant(rawURL, @"orig");
}

static NSURL* BHTWaterfallPreviewURL(NSString* rawURL) {
    // 1200 px is sharp enough for a two-column iPad grid while avoiding an
    // original-size network transfer and decode for every thumbnail.
    return BHTPhotoURLForVariant(rawURL, @"medium");
}

static BHTMediaActionKind BHTMediaActionKindForEntity(id media) {
    NSInteger mediaType = [BHTSafeValue(media, @"mediaType") integerValue];
    if (mediaType == 2) return BHTMediaActionKindGIF;
    id videoInfo = BHTSafeValue(media, @"videoInfo");
    NSArray* variants = BHTSafeValue(videoInfo, @"variants");
    if (mediaType == 3 || variants.count > 0) {
        for (id variant in variants) {
            NSString* URLString = BHTSafeValue(variant, @"url");
            if ([URLString containsString:@"/tweet_video/"]) {
                return BHTMediaActionKindGIF;
            }
        }
        return BHTMediaActionKindVideo;
    }
    return BHTMediaActionKindPhoto;
}

static long long BHTVariantScore(id variant) {
    id bitrate = BHTSafeValue(variant, @"bitrate");
    if ([bitrate respondsToSelector:@selector(longLongValue)] &&
        [bitrate longLongValue] > 0) {
        return [bitrate longLongValue];
    }
    NSString* url = BHTSafeValue(variant, @"url");
    NSRegularExpression* regex =
        [NSRegularExpression regularExpressionWithPattern:@"/(\\d+)x(\\d+)/"
                                                  options:0
                                                    error:nil];
    NSTextCheckingResult* match =
        [regex firstMatchInString:url ?: @"" options:0 range:NSMakeRange(0, url.length)];
    if (match.numberOfRanges == 3) {
        return [[url substringWithRange:[match rangeAtIndex:1]] longLongValue] *
               [[url substringWithRange:[match rangeAtIndex:2]] longLongValue];
    }
    return 0;
}

static NSURL* BHTHighestVideoURL(id media) {
    id videoInfo = BHTSafeValue(media, @"videoInfo");
    NSArray* variants = BHTSafeValue(videoInfo, @"variants");
    id best = nil;
    long long bestScore = -1;
    for (id variant in variants) {
        NSString* type = BHTSafeValue(variant, @"contentType");
        NSString* url = BHTSafeValue(variant, @"url");
        if (![type isEqualToString:@"video/mp4"] || url.length == 0) continue;
        long long score = BHTVariantScore(variant);
        if (!best || score > bestScore) {
            best = variant;
            bestScore = score;
        }
    }
    NSString* url = BHTSafeValue(best, @"url");
    return url.length ? [NSURL URLWithString:url] : nil;
}

static id BHTStatusFromItem(id item) {
    if (!item) return nil;
    if ([item respondsToSelector:@selector(entities)] &&
        [item respondsToSelector:@selector(statusID)]) {
        return item;
    }
    for (NSString* selectorName in @[@"status", @"tweet", @"twitterStatus", @"displayedStatus"]) {
        id result = BHTCallObject(item, selectorName);
        if (result) return result;
    }
    for (NSString* ivarName in @[@"status", @"_status", @"tweet", @"_tweet"]) {
        Ivar ivar = class_getInstanceVariable([item class], ivarName.UTF8String);
        if (ivar) {
            id result = object_getIvar(item, ivar);
            if (result) return result;
        }
    }
    return nil;
}

static NSString* BHTReadableStatusText(id status) {
    for (NSString* key in @[@"fullText", @"text", @"displayText", @"tweetText"]) {
        id value = BHTSafeValue(status, key);
        if ([value isKindOfClass:NSString.class] && [value length] > 0) {
            return value;
        }
        if ([value isKindOfClass:NSAttributedString.class] &&
            ((NSAttributedString*)value).string.length > 0) {
            return ((NSAttributedString*)value).string;
        }
        id string = BHTSafeValue(value, @"string");
        if ([string isKindOfClass:NSString.class] && [string length] > 0) {
            return string;
        }
    }
    return nil;
}

static NSURL* BHTStatusURL(long long statusID) {
    if (statusID <= 0) return nil;
    return [NSURL URLWithString:
        [NSString stringWithFormat:@"https://x.com/i/status/%lld", statusID]];
}

static NSArray<BHTLikedMediaItem*>* BHTMediaItemsFromSections(NSArray* sections) {
    NSMutableArray<BHTLikedMediaItem*>* result = [NSMutableArray array];
    NSMutableSet<NSString*>* identifiers = [NSMutableSet set];

    for (id section in sections) {
        NSArray* items = [section isKindOfClass:NSArray.class] ? section : @[section];
        for (id wrappedItem in items) {
            id item = unwrapDataViewItem(wrappedItem);
            id status = BHTStatusFromItem(item);
            id entitySet = BHTSafeValue(status, @"entities");
            NSArray* mediaEntities = BHTSafeValue(entitySet, @"media");
            long long statusID = [BHTSafeValue(status, @"statusID") longLongValue];

            [mediaEntities enumerateObjectsUsingBlock:^(id media, NSUInteger index, BOOL* stop) {
                NSString* mediaURL = BHTSafeValue(media, @"mediaURLHttps");
                if (mediaURL.length == 0) mediaURL = BHTSafeValue(media, @"mediaURL");
                NSURL* originalURL = BHTOriginalPhotoURL(mediaURL);
                NSURL* videoURL = BHTHighestVideoURL(media);
                if (!originalURL && !videoURL) return;

                NSString* identifier = [NSString stringWithFormat:@"%lld-%lu-%@",
                                                                   statusID,
                                                                   (unsigned long)index,
                                                                   mediaURL ?: videoURL.absoluteString];
                if ([identifiers containsObject:identifier]) return;
                [identifiers addObject:identifier];

                CGFloat width = [BHTSafeValue(BHTSafeValue(media, @"originalInfo"), @"width") doubleValue];
                CGFloat height = [BHTSafeValue(BHTSafeValue(media, @"originalInfo"), @"height") doubleValue];
                if (width <= 0 || height <= 0) {
                    width = [BHTSafeValue(media, @"width") doubleValue];
                    height = [BHTSafeValue(media, @"height") doubleValue];
                }

                BHTLikedMediaItem* model = [BHTLikedMediaItem new];
                model.identifier = identifier;
                model.previewURL =
                    BHTWaterfallPreviewURL(mediaURL) ?:
                    (mediaURL.length ? [NSURL URLWithString:mediaURL] : nil);
                model.originalURL = originalURL ?: model.previewURL;
                model.videoURL = videoURL;
                model.mediaEntity = media;
                model.mediaActionKind =
                    BHTMediaActionKindForEntity(media);
                model.aspectRatio =
                    BHTBoundedMediaAspectRatio(
                        (width > 0 && height > 0)
                            ? width / height
                            : 1.0);
                model.statusID = statusID;
                model.statusText = BHTReadableStatusText(status);
                model.statusURL = BHTStatusURL(statusID);
                [result addObject:model];
            }];
        }
    }
    return result;
}

#pragma mark - Waterfall UI

@protocol BHTWaterfallLayoutDelegate <NSObject>
- (CGFloat)waterfallAspectRatioAtIndexPath:(NSIndexPath*)indexPath;
@end

@interface BHTWaterfallLayout : UICollectionViewLayout
@property(nonatomic) NSInteger columns;
@property(nonatomic) CGFloat spacing;
@property(nonatomic, strong) NSArray<UICollectionViewLayoutAttributes*>* attributes;
@property(nonatomic) CGSize contentSize;
@end

@implementation BHTWaterfallLayout

- (instancetype)init {
    if ((self = [super init])) {
        _columns = 3;
        _spacing = 2;
    }
    return self;
}

- (void)prepareLayout {
    [super prepareLayout];
    NSInteger count = [self.collectionView numberOfItemsInSection:0];
    NSInteger columns = MAX(2, MIN(5, self.columns));
    CGFloat width = CGRectGetWidth(self.collectionView.bounds);
    if (count <= 0 || width <= 0) {
        self.attributes = @[];
        self.contentSize = CGSizeMake(MAX(0, width), 0);
        return;
    }
    CGFloat columnWidth =
        MAX(1, width - self.spacing * (columns - 1)) /
        columns;
    NSMutableArray<NSNumber*>* heights = [NSMutableArray array];
    for (NSInteger i = 0; i < columns; i++) [heights addObject:@0];
    NSMutableArray* attributes = [NSMutableArray arrayWithCapacity:count];
    id<BHTWaterfallLayoutDelegate> delegate = (id)self.collectionView.delegate;

    for (NSInteger item = 0; item < count; item++) {
        NSIndexPath* indexPath = [NSIndexPath indexPathForItem:item inSection:0];
        CGFloat ratio = [delegate respondsToSelector:@selector(waterfallAspectRatioAtIndexPath:)]
                            ? [delegate waterfallAspectRatioAtIndexPath:indexPath]
                            : 1;
        ratio = BHTBoundedMediaAspectRatio(ratio);

        // Portrait and square media retain a single masonry column. Landscape
        // media can span neighboring columns so it stays legible instead of
        // becoming a very short strip. The decoded image later corrects stale
        // or absent API dimensions and this same layout adapts to the result.
        NSInteger desiredSpan = 1;
        if (ratio >= 3.0 && columns >= 3) {
            desiredSpan = MIN(3, columns);
        } else if (ratio >= 1.55) {
            desiredSpan = MIN(2, columns);
        }

        NSInteger span = desiredSpan;
        NSInteger column = 0;
        CGFloat y = 0;
        while (span >= 1) {
            CGFloat bestY = CGFLOAT_MAX;
            CGFloat bestGap = CGFLOAT_MAX;
            NSInteger bestColumn = 0;
            for (NSInteger candidate = 0;
                 candidate <= columns - span; candidate++) {
                CGFloat candidateY = 0;
                for (NSInteger offset = 0; offset < span;
                     offset++) {
                    CGFloat columnHeight =
                        heights[candidate + offset].doubleValue;
                    candidateY =
                        MAX(candidateY, columnHeight);
                }
                CGFloat gap = 0;
                for (NSInteger offset = 0; offset < span;
                     offset++) {
                    CGFloat columnHeight =
                        heights[candidate + offset].doubleValue;
                    gap +=
                        candidateY - columnHeight;
                }
                if (candidateY < bestY ||
                    (candidateY == bestY && gap < bestGap)) {
                    bestColumn = candidate;
                    bestY = candidateY;
                    bestGap = gap;
                }
            }

            // A multi-column tile should not bridge a large vertical hole.
            // If adjacent columns are too uneven, progressively fall back to
            // a narrower tile and preserve the dense waterfall.
            CGFloat acceptedGap =
                MAX(self.spacing * span,
                    columnWidth * 0.35 * (span - 1));
            if (span == 1 || bestGap <= acceptedGap) {
                column = bestColumn;
                y = bestY;
                break;
            }
            span--;
        }

        CGFloat itemWidth =
            columnWidth * span + self.spacing * (span - 1);
        CGFloat itemHeight = itemWidth / ratio;
        CGFloat x = column * (columnWidth + self.spacing);
        UICollectionViewLayoutAttributes* attribute =
            [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
        attribute.frame =
            CGRectMake(x, y, itemWidth, MAX(1, itemHeight));
        [attributes addObject:attribute];
        CGFloat nextHeight =
            CGRectGetMaxY(attribute.frame) + self.spacing;
        for (NSInteger offset = 0; offset < span; offset++) {
            heights[column + offset] = @(nextHeight);
        }
    }

    self.attributes = attributes;
    CGFloat maximumHeight =
        [[heights valueForKeyPath:@"@max.self"] doubleValue];
    self.contentSize =
        CGSizeMake(width, MAX(0, maximumHeight - self.spacing));
}

- (NSArray*)layoutAttributesForElementsInRect:(CGRect)rect {
    NSMutableArray* visible = [NSMutableArray array];
    for (UICollectionViewLayoutAttributes* attribute in self.attributes) {
        if (CGRectIntersectsRect(rect, attribute.frame)) [visible addObject:attribute];
    }
    return visible;
}

- (UICollectionViewLayoutAttributes*)layoutAttributesForItemAtIndexPath:(NSIndexPath*)indexPath {
    return indexPath.item < self.attributes.count ? self.attributes[indexPath.item] : nil;
}

- (CGSize)collectionViewContentSize {
    return self.contentSize;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return fabs(CGRectGetWidth(newBounds) - CGRectGetWidth(self.collectionView.bounds)) > 0.5;
}

@end


@class BHTMediaImageRequestToken;
static void BHTCancelMediaImageRequest(
    BHTMediaImageRequestToken* token);

@interface BHTLikedMediaCell : UICollectionViewCell
@property(nonatomic, strong) UIImageView* imageView;
@property(nonatomic, strong) UIImageView* videoBadge;
@property(nonatomic, strong) BHTMediaImageRequestToken* imageRequest;
@property(nonatomic, strong) NSURL* representedURL;
- (void)applyCurrentThemeSurface;
@end

@implementation BHTLikedMediaCell

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _imageView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        // The adaptive masonry frame follows the media's decoded dimensions.
        // Aspect Fit remains a final safety net so corrupt metadata can never
        // silently cut off an edge.
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        _imageView.clipsToBounds = YES;
        [self applyCurrentThemeSurface];
        [self.contentView addSubview:_imageView];

        _videoBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"play.circle.fill"]];
        _videoBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _videoBadge.tintColor = UIColor.whiteColor;
        _videoBadge.layer.shadowOpacity = 0.4;
        _videoBadge.layer.shadowRadius = 2;
        [self.contentView addSubview:_videoBadge];
        [NSLayoutConstraint activateConstraints:@[
            [_videoBadge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-7],
            [_videoBadge.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-7],
            [_videoBadge.widthAnchor constraintEqualToConstant:24],
            [_videoBadge.heightAnchor constraintEqualToConstant:24]
        ]];
    }
    return self;
}

- (void)applyCurrentThemeSurface {
    UIColor* surfaceColor = [Palette currentSurfaceColor];
    self.backgroundColor = surfaceColor;
    self.contentView.backgroundColor = surfaceColor;
    self.imageView.backgroundColor = surfaceColor;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    BHTCancelMediaImageRequest(self.imageRequest);
    self.imageRequest = nil;
    self.representedURL = nil;
    self.imageView.image = nil;
    [self applyCurrentThemeSurface];
}

@end

@interface BHTCachedMediaImageEntry : NSObject
@property(nonatomic, strong) UIImage* image;
@property(nonatomic) NSUInteger pixelBucket;
@end

@implementation BHTCachedMediaImageEntry
@end

static NSCache<NSURL*, BHTCachedMediaImageEntry*>*
BHTMediaImageCache(void) {
    static NSCache* cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 160;
        cache.totalCostLimit = 128 * 1024 * 1024;
    });
    return cache;
}

static NSUInteger BHTDecodedImageCost(UIImage* image) {
    CGImageRef CGImage = image.CGImage;
    return CGImage
               ? CGImageGetBytesPerRow(CGImage) *
                     CGImageGetHeight(CGImage)
               : 0;
}

static UIImage* BHTAnyCachedMediaImage(NSURL* URL) {
    if (!URL) return nil;
    return [BHTMediaImageCache() objectForKey:URL].image;
}

static UIImage* BHTCachedMediaImage(NSURL* URL,
                                    NSUInteger minimumPixelBucket) {
    if (!URL) return nil;
    BHTCachedMediaImageEntry* entry =
        [BHTMediaImageCache() objectForKey:URL];
    return entry.pixelBucket >= minimumPixelBucket
               ? entry.image
               : nil;
}

static void BHTCacheImage(UIImage* image, NSURL* URL,
                          NSUInteger pixelBucket) {
    if (!image || !URL) return;
    @synchronized(BHTMediaImageCache()) {
        BHTCachedMediaImageEntry* existing =
            [BHTMediaImageCache() objectForKey:URL];
        if (existing.pixelBucket >= pixelBucket) return;
        BHTCachedMediaImageEntry* entry =
            [BHTCachedMediaImageEntry new];
        entry.image = image;
        entry.pixelBucket = pixelBucket;
        [BHTMediaImageCache() setObject:entry
                                forKey:URL
                                  cost:BHTDecodedImageCost(image)];
    }
}

static UIImage* BHTDownsampledImage(NSData* data,
                                    CGFloat maximumPixelDimension) {
    if (data.length == 0) return nil;
    NSDictionary* sourceOptions = @{
        (NSString*)kCGImageSourceShouldCache: @NO
    };
    CGImageSourceRef source =
        CGImageSourceCreateWithData((__bridge CFDataRef)data,
                                    (__bridge CFDictionaryRef)sourceOptions);
    if (!source) return nil;

    CGFloat maximum =
        MAX(320.0, MIN(maximumPixelDimension, 4096.0));
    NSDictionary* thumbnailOptions = @{
        (NSString*)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (NSString*)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (NSString*)kCGImageSourceShouldCacheImmediately: @YES,
        (NSString*)kCGImageSourceThumbnailMaxPixelSize: @(maximum)
    };
    CGImageRef thumbnail =
        CGImageSourceCreateThumbnailAtIndex(
            source, 0, (__bridge CFDictionaryRef)thumbnailOptions);
    CFRelease(source);
    if (!thumbnail) return nil;
    UIImage* image = [UIImage imageWithCGImage:thumbnail
                                         scale:UIScreen.mainScreen.scale
                                   orientation:UIImageOrientationUp];
    CGImageRelease(thumbnail);
    return image;
}

static CGFloat BHTTargetPixelsForView(UIView* view,
                                      CGFloat qualityMultiplier) {
    CGFloat points = MAX(CGRectGetWidth(view.bounds),
                         CGRectGetHeight(view.bounds));
    UIScreen* screen = view.window.screen ?: UIScreen.mainScreen;
    if (points < 1.0) {
        points = MAX(CGRectGetWidth(screen.bounds),
                     CGRectGetHeight(screen.bounds));
    }
    CGFloat scale = screen.scale;
    return MAX(640.0, points * scale * qualityMultiplier);
}

typedef void (^BHTMediaImageCompletion)(UIImage* image);

@interface BHTMediaImageRequestToken : NSObject
@property(nonatomic, copy) NSString* requestKey;
@property(nonatomic, strong) NSUUID* identifier;
@property(nonatomic) BOOL cancelled;
@end

@implementation BHTMediaImageRequestToken
@end

@interface BHTPendingMediaImageRequest : NSObject
@property(nonatomic, strong) NSURLSessionDataTask* task;
@property(nonatomic, strong) NSMutableDictionary<NSUUID*, id>* completions;
@end

@implementation BHTPendingMediaImageRequest
@end

static NSObject* BHTMediaImageRequestLock(void) {
    static NSObject* lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static NSMutableDictionary<NSString*, BHTPendingMediaImageRequest*>*
BHTPendingMediaImageRequests(void) {
    static NSMutableDictionary* requests;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        requests = [NSMutableDictionary dictionary];
    });
    return requests;
}

static NSUInteger BHTMediaImagePixelBucket(
    CGFloat maximumPixelDimension) {
    CGFloat bounded =
        MAX(320.0, MIN(maximumPixelDimension, 4096.0));
    return (NSUInteger)(
        ceil(bounded / 256.0) *
        256.0);
}

static NSString* BHTMediaImageRequestKey(NSURL* URL,
                                         NSUInteger pixelBucket) {
    // Requests in the same 256-pixel bucket share both their network transfer
    // and ImageIO decode. Preview and original URLs remain distinct.
    return [NSString stringWithFormat:@"%@#%lu",
                                      URL.absoluteString ?: @"",
                                      (unsigned long)pixelBucket];
}

static void BHTCancelMediaImageRequest(
    BHTMediaImageRequestToken* token) {
    if (!token || token.cancelled) return;
    token.cancelled = YES;
    @synchronized(BHTMediaImageRequestLock()) {
        BHTPendingMediaImageRequest* pending =
            BHTPendingMediaImageRequests()[token.requestKey];
        [pending.completions removeObjectForKey:token.identifier];
        if (pending && pending.completions.count == 0) {
            [pending.task cancel];
            [BHTPendingMediaImageRequests()
                removeObjectForKey:token.requestKey];
            BHTIncrementLikesDiagnostic(
                @"imageRequestsCancelled");
        }
    }
}

static BHTMediaImageRequestToken* BHTRequestMediaImage(
    NSURL* URL,
    CGFloat maximumPixelDimension,
    BHTMediaImageCompletion completion) {
    if (!URL || !completion) return nil;
    NSUInteger pixelBucket =
        BHTMediaImagePixelBucket(maximumPixelDimension);
    UIImage* cached =
        BHTCachedMediaImage(URL, pixelBucket);
    if (cached) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(cached);
        });
        return nil;
    }

    NSString* key =
        BHTMediaImageRequestKey(URL, pixelBucket);
    BHTMediaImageRequestToken* token =
        [BHTMediaImageRequestToken new];
    token.requestKey = key;
    token.identifier = [NSUUID UUID];
    // A transfer can finish between a consumer cancelling and the queued
    // main-thread callbacks running. Keep the token with its callback and
    // re-check cancellation at delivery time so a reused cell/prefetch slot
    // never receives a stale completion.
    BHTMediaImageCompletion guardedCompletion =
        ^(UIImage* image) {
            if (!token.cancelled) completion(image);
        };

    @synchronized(BHTMediaImageRequestLock()) {
        BHTPendingMediaImageRequest* pending =
            BHTPendingMediaImageRequests()[key];
        if (pending) {
            pending.completions[token.identifier] =
                [guardedCompletion copy];
            BHTIncrementLikesDiagnostic(
                @"imageRequestsCoalesced");
            return token;
        }

        pending = [BHTPendingMediaImageRequest new];
        pending.completions = [NSMutableDictionary dictionary];
        pending.completions[token.identifier] =
            [guardedCompletion copy];
        BHTPendingMediaImageRequests()[key] = pending;
        BHTIncrementLikesDiagnostic(@"imageRequestsStarted");

        __weak BHTPendingMediaImageRequest* weakPending = pending;
        pending.task = [[NSURLSession sharedSession]
            dataTaskWithURL:URL
          completionHandler:^(NSData* data,
                              NSURLResponse* response,
                              NSError* error) {
            UIImage* image =
                (!error && data.length > 0)
                    ? BHTDownsampledImage(
                          data, pixelBucket)
                    : nil;
            BHTCacheImage(image, URL, pixelBucket);

            __block NSArray* completions = nil;
            @synchronized(BHTMediaImageRequestLock()) {
                BHTPendingMediaImageRequest* current =
                    BHTPendingMediaImageRequests()[key];
                if (current == weakPending) {
                    completions =
                        current.completions.allValues;
                    [BHTPendingMediaImageRequests()
                        removeObjectForKey:key];
                }
            }
            if (completions.count == 0) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                for (id value in completions) {
                    BHTMediaImageCompletion callback = value;
                    callback(image);
                }
            });
        }];
        [pending.task resume];
    }
    return token;
}

static void BHTOpenLikedMediaPost(BHTLikedMediaItem* item) {
    if (!item) return;
    BHTIncrementLikesDiagnostic(@"postRouteAttempts");
    NSURL* appURL =
        item.statusID > 0
            ? [NSURL URLWithString:
                  [NSString stringWithFormat:@"twitter://status?id=%lld",
                                             item.statusID]]
            : nil;
    NSURL* fallback = item.statusURL;
    UIApplication* application = UIApplication.sharedApplication;
    if (!appURL) {
        if (fallback) {
            [application openURL:fallback
                          options:@{}
                completionHandler:^(BOOL success) {
                    if (success) {
                        BHTIncrementLikesDiagnostic(
                            @"postURLAcceptances");
                    }
                }];
        }
        return;
    }
    [application openURL:appURL
                  options:@{}
        completionHandler:^(BOOL success) {
            if (success) {
                BHTIncrementLikesDiagnostic(@"postURLAcceptances");
            } else if (fallback) {
                [application openURL:fallback
                              options:@{}
                    completionHandler:^(BOOL fallbackSuccess) {
                        if (fallbackSuccess) {
                            BHTIncrementLikesDiagnostic(
                                @"postURLAcceptances");
                        }
                    }];
            }
        }];
}

static void BHTPresentActivityItemsAttempt(
    NSArray* activityItems,
    UIViewController* presenter,
    UIView* sourceView,
    NSUInteger attempt) {
    if (activityItems.count == 0) return;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)((attempt == 0 ? 0.18 : 0.08) *
                                NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
        UIViewController* top = topMostController();
        Class menuSheetClass =
            NSClassFromString(@"TFNMenuSheetViewController");
        BOOL menuStillClosing =
            (menuSheetClass &&
             [top isKindOfClass:menuSheetClass]) ||
            top.isBeingDismissed;
        UIViewController* visiblePresenter =
            presenter.view.window ? presenter : top;
        BOOL presenterBusy =
            visiblePresenter.presentedViewController != nil ||
            visiblePresenter.isBeingPresented ||
            visiblePresenter.isBeingDismissed;
        if (menuStillClosing || presenterBusy) {
            if (attempt < 8) {
                BHTPresentActivityItemsAttempt(
                    activityItems, presenter, sourceView,
                    attempt + 1);
            }
            return;
        }
        if (!visiblePresenter) return;
        UIActivityViewController* share =
            [[UIActivityViewController alloc]
                initWithActivityItems:activityItems
                applicationActivities:nil];
        UIPopoverPresentationController* popover =
            share.popoverPresentationController;
        if (popover) {
            UIView* anchor = sourceView.window ? sourceView
                                              : visiblePresenter.view;
            popover.sourceView = anchor;
            popover.sourceRect = anchor.bounds;
        }
        [visiblePresenter presentViewController:share
                                       animated:YES
                                     completion:nil];
    });
}

static void BHTPresentActivityItems(NSArray* activityItems,
                                    UIViewController* presenter,
                                    UIView* sourceView) {
    BHTPresentActivityItemsAttempt(
        activityItems, presenter, sourceView, 0);
}

static void BHTPresentLikedMediaActionSheet(
    UIViewController* presenter,
    BHTLikedMediaItem* item,
    UIView* sourceView) {
    if (!presenter || !item || !sourceView ||
        presenter.presentedViewController) {
        return;
    }

    Class actionClass = NSClassFromString(@"TFNActionItem");
    if (!actionClass ||
        ![actionClass
            respondsToSelector:
                @selector(actionItemWithTitle:action:)] ||
        ![actionClass
            respondsToSelector:
                @selector(actionItemWithTitle:imageName:action:)]) {
        return;
    }

    BHTBundle* bundle = [BHTBundle sharedBundle];
    DownloadInlineButton* downloader = [DownloadInlineButton new];
    NSMutableArray<TFNActionItem*>* actions =
        [NSMutableArray array];
    NSArray* mediaEntities =
        item.mediaEntity ? @[item.mediaEntity] : @[];
    BOOL photo = item.mediaActionKind == BHTMediaActionKindPhoto;
    BOOL GIF = item.mediaActionKind == BHTMediaActionKindGIF;

    if (mediaEntities.count > 0 &&
        (photo ||
         [BHTSettings boolForKey:@"download_videos"])) {
        TFNActionItem* download =
            [actionClass
                actionItemWithTitle:
                    [bundle localizedStringForKey:
                        photo
                            ? @"MEDIA_ACTION_DOWNLOAD_PHOTO_MENU_TITLE"
                            : (GIF
                                   ? @"MEDIA_ACTION_DOWNLOAD_GIF_MENU_TITLE"
                                   : @"MEDIA_ACTION_DOWNLOAD_VIDEO_MENU_TITLE")]
                           imageName:@"arrow_down_circle_stroke"
                              action:^{
                                  dispatch_async(
                                      dispatch_get_main_queue(), ^{
                                      if (photo) {
                                          [downloader
                                              downloadOriginalPhotoMediaEntities:
                                                  mediaEntities];
                                      } else {
                                          [downloader
                                              presentDownloadOptionsForMediaEntities:
                                                  mediaEntities];
                                      }
                                  });
                              }];
        if (download) {
            BHTMediaActionSetIdentifier(
                download, BHTMediaActionDownloadIdentifier);
            [actions addObject:download];
        }
    }

    if (mediaEntities.count > 0) {
        TFNActionItem* shareFile =
            [actionClass
                actionItemWithTitle:
                    [bundle localizedStringForKey:
                        photo
                            ? @"MEDIA_ACTION_SHARE_PHOTO_FILE_MENU_TITLE"
                            : (GIF
                                   ? @"MEDIA_ACTION_SHARE_GIF_FILE_MENU_TITLE"
                                   : @"MEDIA_ACTION_SHARE_VIDEO_FILE_MENU_TITLE")]
                           imageName:@"share_stroke_bold"
                              action:^{
                                  dispatch_async(
                                      dispatch_get_main_queue(), ^{
                                      if (photo) {
                                          [downloader
                                              shareOriginalPhotoMediaEntities:
                                                  mediaEntities];
                                      } else {
                                          [downloader
                                              shareHighestQualityMediaEntities:
                                                  mediaEntities];
                                      }
                                  });
                              }];
        if (shareFile) {
            BHTMediaActionSetIdentifier(
                shareFile, BHTMediaActionShareFileIdentifier);
            [actions addObject:shareFile];
        }
    }

    if (item.statusURL) {
        TFNActionItem* copyLink =
            [actionClass
                actionItemWithTitle:
                    [bundle localizedStringForKey:
                                @"MEDIA_ACTION_COPY_LINK_TITLE"]
                              action:^{
                                  UIPasteboard.generalPasteboard.URL =
                                      item.statusURL;
                              }];
        if (copyLink) {
            BHTMediaActionSetIdentifier(
                copyLink, BHTMediaActionCopyLinkIdentifier);
            [actions addObject:copyLink];
        }

        __weak UIViewController* weakPresenter = presenter;
        __weak UIView* weakSourceView = sourceView;
        TFNActionItem* shareVia =
            [actionClass
                actionItemWithTitle:
                    [bundle localizedStringForKey:
                                @"MEDIA_ACTION_SHARE_VIA_TITLE"]
                           imageName:@"share_stroke_bold"
                              action:^{
                                  BHTPresentActivityItems(
                                      @[item.statusURL],
                                      weakPresenter,
                                      weakSourceView);
                              }];
        if (shareVia) {
            BHTMediaActionSetIdentifier(
                shareVia, BHTMediaActionShareViaIdentifier);
            [actions addObject:shareVia];
        }

        TFNActionItem* viewPost =
            [actionClass
                actionItemWithTitle:
                    [bundle localizedStringForKey:
                                @"LIKES_VIEW_POST_ACTION_TITLE"]
                              action:^{
                                  BHTOpenLikedMediaPost(item);
                              }];
        if (viewPost) {
            [actions insertObject:viewPost atIndex:0];
        }
    }

    NSArray* configured =
        BHTMediaActionApplyPreferences(actions,
                                       item.mediaActionKind);
    if (configured.count == 0) return;

    Class sheetClass =
        NSClassFromString(@"TFNMenuSheetViewController");
    if (!sheetClass ||
        ![sheetClass
            instancesRespondToSelector:
                @selector(initWithTitle:actionItems:)]) {
        return;
    }

    TFNMenuSheetViewController* sheet =
        [[sheetClass alloc]
            initWithTitle:
                [bundle localizedStringForKey:
                            @"LIKES_MEDIA_ACTIONS_TITLE"]
              actionItems:configured];
    if (!sheet ||
        ![sheet
            respondsToSelector:
                @selector(tfnPresentedCustomPresentFromViewController:animated:completion:)]) {
        return;
    }
    if ([sheet respondsToSelector:@selector(setShouldPresentAsMenu:)]) {
        sheet.shouldPresentAsMenu = YES;
    }
    if ([sheet respondsToSelector:@selector(setSourceView:)]) {
        sheet.sourceView = sourceView;
    }
    UIImpactFeedbackGenerator* haptic =
        [[UIImpactFeedbackGenerator alloc]
            initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    [sheet tfnPresentedCustomPresentFromViewController:presenter
                                              animated:YES
                                            completion:nil];
}

static BOOL BHTNativeTimelineMediaPreviewAvailable(
    UIViewController* presenter) {
    SEL builder = NSSelectorFromString(
        @"t1_mediaActivityViewActionItemsForStatus:account:image:mediaInfo:shortTitles:sourceView:");
    Class previewClass =
        NSClassFromString(@"TFNPreviewConfiguration");
    SEL configuration = NSSelectorFromString(
        @"configurationWithPreviewViewControllerBlock:actionItems:sourceView:sourceRect:");
    BOOL available =
        [presenter respondsToSelector:builder] &&
        [previewClass respondsToSelector:configuration];
    BHTSetLikesDiagnostic(
        @"nativeTimelineMediaPreviewAvailable", @(available));
    return available;
}

static void BHTCopyLikedPhoto(BHTLikedMediaItem* item,
                              UIView* sourceView) {
    NSURL* URL = item.originalURL ?: item.previewURL;
    if (!URL) return;
    CGFloat targetPixels =
        BHTTargetPixelsForView(sourceView, 2.0);
    NSUInteger pixelBucket =
        BHTMediaImagePixelBucket(targetPixels);
    UIImage* cached =
        BHTCachedMediaImage(URL, pixelBucket);
    void (^copyImage)(UIImage*) = ^(UIImage* image) {
        if (!image) return;
        UIPasteboard.generalPasteboard.image = image;
        UINotificationFeedbackGenerator* feedback =
            [UINotificationFeedbackGenerator new];
        [feedback
            notificationOccurred:
                UINotificationFeedbackTypeSuccess];
    };
    if (cached) {
        copyImage(cached);
        return;
    }
    BHTRequestMediaImage(URL, targetPixels, copyImage);
}

static UIMenu* BHTLikedMediaContextMenu(
    UIViewController* presenter,
    BHTLikedMediaItem* item,
    UIView* sourceView) API_AVAILABLE(ios(13.0)) {
    if (!presenter || !item || !sourceView) return nil;

    // Record whether X's exact private builder is still present. Its
    // TFNPreviewConfiguration has no safe public presentation entry point for
    // a custom collection, so the waterfall uses UIKit's native context-menu
    // presentation while sharing the same actions/download implementation.
    BHTNativeTimelineMediaPreviewAvailable(presenter);

    BHTBundle* bundle = [BHTBundle sharedBundle];
    DownloadInlineButton* downloader =
        [DownloadInlineButton new];
    NSMutableArray<UIMenuElement*>* actions =
        [NSMutableArray array];
    NSArray* entities =
        item.mediaEntity ? @[item.mediaEntity] : @[];
    BOOL photo =
        item.mediaActionKind == BHTMediaActionKindPhoto;
    BOOL GIF =
        item.mediaActionKind == BHTMediaActionKindGIF;

    if (photo) {
        UIAction* copy = [UIAction
            actionWithTitle:
                [bundle localizedStringForKey:
                            @"MEDIA_ACTION_COPY_PHOTO_TITLE"]
                      image:[UIImage
                                systemImageNamed:@"doc.on.doc"]
                 identifier:nil
                    handler:^(__kindof UIAction* action) {
            BHTCopyLikedPhoto(item, sourceView);
        }];
        BHTMediaActionSetIdentifier(
            copy, BHTMediaActionCopyLinkIdentifier);
        [actions addObject:copy];
    } else {
        NSURL* copyURL = item.videoURL ?: item.statusURL;
        if (copyURL) {
            UIAction* copy = [UIAction
                actionWithTitle:
                    [bundle localizedStringForKey:
                                GIF
                                    ? @"MEDIA_ACTION_COPY_GIF_LINK_TITLE"
                                    : @"MEDIA_ACTION_COPY_VIDEO_LINK_TITLE"]
                          image:[UIImage
                                    systemImageNamed:@"doc.on.doc"]
                     identifier:nil
                        handler:^(__kindof UIAction* action) {
                UIPasteboard.generalPasteboard.URL = copyURL;
            }];
            BHTMediaActionSetIdentifier(
                copy, BHTMediaActionCopyLinkIdentifier);
            [actions addObject:copy];
        }
    }

    if (entities.count > 0 &&
        (photo ||
         [BHTSettings boolForKey:@"download_videos"])) {
        UIAction* download = [UIAction
            actionWithTitle:
                [bundle localizedStringForKey:
                    photo
                        ? @"MEDIA_ACTION_DOWNLOAD_PHOTO_MENU_TITLE"
                        : (GIF
                               ? @"MEDIA_ACTION_DOWNLOAD_GIF_MENU_TITLE"
                               : @"MEDIA_ACTION_DOWNLOAD_VIDEO_MENU_TITLE")]
                      image:[UIImage
                                systemImageNamed:@"arrow.down.circle"]
                 identifier:nil
                    handler:^(__kindof UIAction* action) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (photo) {
                    [downloader
                        downloadOriginalPhotoMediaEntities:
                            entities];
                } else {
                    [downloader
                        presentDownloadOptionsForMediaEntities:
                            entities];
                }
            });
        }];
        BHTMediaActionSetIdentifier(
            download, BHTMediaActionDownloadIdentifier);
        [actions addObject:download];
    }

    if (entities.count > 0) {
        UIAction* shareFile = [UIAction
            actionWithTitle:
                [bundle localizedStringForKey:
                    photo
                        ? @"MEDIA_ACTION_SHARE_PHOTO_FILE_MENU_TITLE"
                        : (GIF
                               ? @"MEDIA_ACTION_SHARE_GIF_FILE_MENU_TITLE"
                               : @"MEDIA_ACTION_SHARE_VIDEO_FILE_MENU_TITLE")]
                      image:[UIImage
                                systemImageNamed:@"square.and.arrow.up"]
                 identifier:nil
                    handler:^(__kindof UIAction* action) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (photo) {
                    [downloader
                        shareOriginalPhotoMediaEntities:
                            entities];
                } else {
                    [downloader
                        shareHighestQualityMediaEntities:
                            entities];
                }
            });
        }];
        BHTMediaActionSetIdentifier(
            shareFile, BHTMediaActionShareFileIdentifier);
        [actions addObject:shareFile];
    }

    NSURL* shareURL =
        item.statusURL ?: item.videoURL ?: item.originalURL;
    if (shareURL) {
        __weak UIViewController* weakPresenter = presenter;
        __weak UIView* weakSource = sourceView;
        UIAction* shareVia = [UIAction
            actionWithTitle:
                [bundle localizedStringForKey:
                            @"MEDIA_ACTION_SHARE_VIA_TITLE"]
                      image:[UIImage
                                systemImageNamed:@"square.and.arrow.up"]
                 identifier:nil
                    handler:^(__kindof UIAction* action) {
            BHTPresentActivityItems(
                @[shareURL], weakPresenter, weakSource);
        }];
        BHTMediaActionSetIdentifier(
            shareVia, BHTMediaActionShareViaIdentifier);
        [actions addObject:shareVia];
    }

    NSArray* configured =
        BHTMediaActionApplyPreferences(
            actions, item.mediaActionKind);
    return configured.count > 0
               ? [UIMenu menuWithTitle:@""
                              children:configured]
               : nil;
}

@interface BHTMediaContextPreviewController : UIViewController
- (instancetype)initWithItem:(BHTLikedMediaItem*)item;
@property(nonatomic, strong) BHTLikedMediaItem* item;
@property(nonatomic, strong) UIImageView* imageView;
@property(nonatomic, strong)
    BHTMediaImageRequestToken* imageRequest;
@end

@implementation BHTMediaContextPreviewController

- (instancetype)initWithItem:(BHTLikedMediaItem*)item {
    if ((self = [super init])) {
        _item = item;
        CGFloat ratio =
            MAX(0.35, MIN(item.aspectRatio, 2.2));
        CGFloat maxWidth =
            MIN(720, UIScreen.mainScreen.bounds.size.width - 32);
        CGFloat maxHeight =
            UIScreen.mainScreen.bounds.size.height * 0.68;
        CGFloat width =
            MIN(maxWidth, maxHeight * ratio);
        self.preferredContentSize =
            CGSizeMake(width, width / ratio);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.imageView =
        [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.imageView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    self.imageView.contentMode =
        UIViewContentModeScaleAspectFit;
    self.imageView.clipsToBounds = YES;
    [self.view addSubview:self.imageView];

    NSURL* URL = self.item.previewURL ?:
                 self.item.originalURL;
    CGFloat targetPixels =
        BHTTargetPixelsForView(self.view, 1.5);
    NSUInteger pixelBucket =
        BHTMediaImagePixelBucket(targetPixels);
    UIImage* cached =
        BHTCachedMediaImage(URL, pixelBucket);
    UIImage* placeholder =
        BHTAnyCachedMediaImage(self.item.originalURL) ?:
        BHTAnyCachedMediaImage(self.item.previewURL);
    self.imageView.image = cached ?: placeholder;
    if (!cached && URL) {
        __weak typeof(self) weakSelf = self;
        self.imageRequest =
            BHTRequestMediaImage(
                URL, targetPixels,
                ^(UIImage* image) {
                    weakSelf.imageView.image = image;
                });
    }
}

- (void)dealloc {
    BHTCancelMediaImageRequest(self.imageRequest);
}

@end

static UIContextMenuConfiguration*
BHTLikedMediaContextConfiguration(
    UIViewController* presenter,
    BHTLikedMediaItem* item,
    UIView* sourceView) API_AVAILABLE(ios(13.0)) {
    if (!presenter || !item || !sourceView) return nil;
    return [UIContextMenuConfiguration
        configurationWithIdentifier:item.identifier
                    previewProvider:^UIViewController* {
        return [[BHTMediaContextPreviewController alloc]
            initWithItem:item];
    }
                     actionProvider:^UIMenu*(
                         NSArray<UIMenuElement*>*
                             suggestedActions) {
        return BHTLikedMediaContextMenu(
            presenter, item, sourceView);
    }];
}

@interface BHTMediaPageController
    : UIViewController <UIScrollViewDelegate,
                        UIContextMenuInteractionDelegate>
- (instancetype)initWithItem:(BHTLikedMediaItem*)item index:(NSUInteger)index;
@property(nonatomic, strong) BHTLikedMediaItem* item;
@property(nonatomic) NSUInteger index;
@property(nonatomic, strong) UIScrollView* scrollView;
@property(nonatomic, strong) UIImageView* imageView;
@property(nonatomic, strong) UIButton* playButton;
@property(nonatomic, strong) BHTMediaImageRequestToken* imageRequest;
@property(nonatomic, strong) UIContextMenuInteraction* contextMenuInteraction;
@end

@implementation BHTMediaPageController

- (instancetype)initWithItem:(BHTLikedMediaItem*)item index:(NSUInteger)index {
    if ((self = [super init])) {
        _item = item;
        _index = index;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.edgesForExtendedLayout = UIRectEdgeAll;
    self.extendedLayoutIncludesOpaqueBars = YES;
    self.view.backgroundColor = UIColor.blackColor;
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if (@available(iOS 11.0, *)) {
        self.scrollView.contentInsetAdjustmentBehavior =
            UIScrollViewContentInsetAdjustmentNever;
    }
    self.scrollView.minimumZoomScale = 1;
    self.scrollView.maximumZoomScale = 6;
    self.scrollView.directionalLockEnabled = YES;
    self.scrollView.delegate = self;
    [self.view addSubview:self.scrollView];
    self.imageView = [[UIImageView alloc] initWithFrame:self.scrollView.bounds];
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.userInteractionEnabled = YES;
    [self.scrollView addSubview:self.imageView];

    NSURL* imageURL = self.item.originalURL ?: self.item.previewURL;
    CGFloat targetPixels =
        BHTTargetPixelsForView(self.view, 2.0);
    NSUInteger pixelBucket =
        BHTMediaImagePixelBucket(targetPixels);
    UIImage* cached =
        BHTCachedMediaImage(imageURL, pixelBucket);
    UIImage* placeholder =
        BHTAnyCachedMediaImage(self.item.previewURL);
    if (cached) {
        self.imageView.image = cached;
    } else if (placeholder) {
        self.imageView.image = placeholder;
    }
    if (imageURL && !cached) {
        __weak typeof(self) weakSelf = self;
        self.imageRequest =
            BHTRequestMediaImage(
                imageURL, targetPixels, ^(UIImage* image) {
                    if (image) weakSelf.imageView.image = image;
                });
    }

    if (self.item.videoURL) {
        self.scrollView.maximumZoomScale = 1;
        self.playButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.playButton.translatesAutoresizingMaskIntoConstraints = NO;
        UIImageSymbolConfiguration* configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:56
                                                            weight:UIImageSymbolWeightRegular];
        [self.playButton setImage:
             [UIImage systemImageNamed:@"play.circle.fill"
                         withConfiguration:configuration]
                         forState:UIControlStateNormal];
        self.playButton.tintColor = UIColor.whiteColor;
        self.playButton.accessibilityLabel = @"Play video";
        [self.playButton addTarget:self
                            action:@selector(playVideo:)
                  forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:self.playButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.playButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [self.playButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
        ]];
    }

    if (@available(iOS 13.0, *)) {
        self.contextMenuInteraction =
            [[UIContextMenuInteraction alloc]
                initWithDelegate:(id<UIContextMenuInteractionDelegate>)self];
        [self.imageView addInteraction:self.contextMenuInteraction];
    } else {
        UILongPressGestureRecognizer* longPress =
            [[UILongPressGestureRecognizer alloc]
                initWithTarget:self
                        action:@selector(mediaLongPressed:)];
        longPress.minimumPressDuration = 0.45;
        longPress.cancelsTouchesInView = NO;
        [self.view addGestureRecognizer:longPress];
    }
}

- (void)dealloc {
    BHTCancelMediaImageRequest(self.imageRequest);
}

- (void)playVideo:(id)sender {
    if (!self.item.videoURL) return;
    AVPlayerViewController* player = [AVPlayerViewController new];
    player.player = [AVPlayer playerWithURL:self.item.videoURL];
    [self presentViewController:player
                       animated:YES
                     completion:^{ [player.player play]; }];
}

- (void)mediaLongPressed:(UILongPressGestureRecognizer*)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan ||
        self.presentedViewController || !self.view.window) {
        return;
    }
    BHTPresentLikedMediaActionSheet(
        self, self.item, self.imageView);
}

- (UIContextMenuConfiguration*)contextMenuInteraction:
        (UIContextMenuInteraction*)interaction
                  configurationForMenuAtLocation:
        (CGPoint)location API_AVAILABLE(ios(13.0)) {
    if (self.presentedViewController || !self.view.window) {
        return nil;
    }
    return BHTLikedMediaContextConfiguration(
        self, self.item, self.imageView);
}

- (UIView*)viewForZoomingInScrollView:(UIScrollView*)scrollView {
    return self.item.videoURL ? nil : self.imageView;
}

@end

@interface BHTMediaViewerAnimator
    : NSObject <UIViewControllerAnimatedTransitioning>
@property(nonatomic) BOOL presenting;
@end

@implementation BHTMediaViewerAnimator

- (NSTimeInterval)transitionDuration:
    (id<UIViewControllerContextTransitioning>)transitionContext {
    return self.presenting ? 0.28 : 0.34;
}

- (void)animateTransition:
    (id<UIViewControllerContextTransitioning>)transitionContext {
    UIView* container = transitionContext.containerView;
    UIView* fromView =
        [transitionContext viewForKey:UITransitionContextFromViewKey];
    UIView* toView =
        [transitionContext viewForKey:UITransitionContextToViewKey];
    NSTimeInterval duration =
        [self transitionDuration:transitionContext];

    if (self.presenting) {
        // A host controller embedded in X's iPad column hierarchy can supply
        // an adaptive final frame even for a full-screen modal. The media
        // viewer is intentionally window-level, so its custom transition must
        // use the presentation container rather than inherit that column.
        toView.frame = container.bounds;
        toView.autoresizingMask =
            UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;
        toView.alpha = 0;
        toView.transform =
            CGAffineTransformConcat(
                CGAffineTransformMakeTranslation(0, 18),
                CGAffineTransformMakeScale(0.985, 0.985));
        [container addSubview:toView];
        [UIView animateWithDuration:duration
                              delay:0
                            options:
                                UIViewAnimationOptionCurveEaseOut
                         animations:^{
            toView.alpha = 1;
            toView.transform = CGAffineTransformIdentity;
        }
                         completion:^(__unused BOOL finished) {
            BOOL completed =
                !transitionContext.transitionWasCancelled;
            if (!completed) [toView removeFromSuperview];
            [transitionContext
                completeTransition:completed];
        }];
        return;
    }

    if (toView && !toView.superview) {
        [container insertSubview:toView belowSubview:fromView];
    } else if (toView) {
        [container sendSubviewToBack:toView];
    }
    UIViewController* toController =
        [transitionContext
            viewControllerForKey:
                UITransitionContextToViewControllerKey];
    if (toController && toView) {
        toView.frame =
            [transitionContext finalFrameForViewController:
                                   toController];
    }
    if (toView) {
        toView.transform =
            CGAffineTransformMakeScale(0.985, 0.985);
        toView.alpha = 0.92;
    }

    fromView.layer.masksToBounds = YES;
    [UIView animateWithDuration:duration
                          delay:0
                        options:
                            UIViewAnimationOptionCurveLinear
                     animations:^{
        CGFloat height =
            MAX(CGRectGetHeight(container.bounds),
                CGRectGetHeight(fromView.bounds));
        fromView.transform =
            CGAffineTransformMakeTranslation(0, height + 24);
        fromView.layer.cornerRadius = 24;
        toView.transform = CGAffineTransformIdentity;
        toView.alpha = 1;
    }
                     completion:^(__unused BOOL finished) {
        BOOL completed =
            !transitionContext.transitionWasCancelled;
        fromView.transform = CGAffineTransformIdentity;
        fromView.layer.cornerRadius = 0;
        fromView.layer.masksToBounds = NO;
        toView.transform = CGAffineTransformIdentity;
        toView.alpha = 1;
        [transitionContext
            completeTransition:completed];
    }];
}

@end

@interface BHTMediaPagerController : UIViewController <UIPageViewControllerDataSource,
                                                        UIPageViewControllerDelegate,
                                                        UIGestureRecognizerDelegate,
                                                        UIViewControllerTransitioningDelegate>
- (instancetype)initWithItems:(NSArray<BHTLikedMediaItem*>*)items
                  initialIndex:(NSUInteger)index;
@property(nonatomic, copy) NSArray<BHTLikedMediaItem*>* items;
@property(nonatomic, copy) NSArray<BHTLikedMediaItem*>* pendingItems;
@property(nonatomic) NSUInteger currentIndex;
@property(nonatomic) NSUInteger knownItemCount;
@property(nonatomic, strong) UIPageViewController* pageController;
@property(nonatomic, strong) UIButton* postButton;
@property(nonatomic, strong) UIButton* closeButton;
@property(nonatomic, strong) UIPanGestureRecognizer* dismissPan;
@property(nonatomic, strong)
    UIPercentDrivenInteractiveTransition* dismissalInteraction;
@property(nonatomic) BOOL completingDismissal;
@property(nonatomic) BOOL interactiveDismissal;
@property(nonatomic) BOOL pageTransitionInFlight;
@property(nonatomic) BOOL pendingMediaUpdate;
@property(nonatomic) BOOL recordedFullScreenActivation;
@property(nonatomic, copy) dispatch_block_t loadMoreHandler;
- (BHTMediaPageController*)pageAtIndex:(NSUInteger)index;
- (BHTLikedMediaItem*)currentItem;
- (void)updatePostButton;
- (void)requestMoreIfNeededAtIndex:(NSUInteger)index;
- (void)mediaItemsDidUpdateWithItems:
    (NSArray<BHTLikedMediaItem*>*)items;
- (void)applyMediaItemsUpdate;
- (void)recordFullScreenCoverage;
@end

@implementation BHTMediaPagerController

- (instancetype)initWithItems:(NSArray<BHTLikedMediaItem*>*)items
                  initialIndex:(NSUInteger)index {
    if ((self = [super init])) {
        _items = [items copy];
        _currentIndex = MIN(index, items.count > 0 ? items.count - 1 : 0);
        _knownItemCount = items.count;
        self.title = @"Liked media";
        self.modalPresentationStyle =
            UIModalPresentationFullScreen;
        self.modalPresentationCapturesStatusBarAppearance = YES;
        self.definesPresentationContext = YES;
        self.providesPresentationContextTransitionStyle = YES;
        self.transitioningDelegate = self;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.edgesForExtendedLayout = UIRectEdgeAll;
    self.extendedLayoutIncludesOpaqueBars = YES;
    self.view.backgroundColor = UIColor.blackColor;

    self.pageController = [[UIPageViewController alloc]
        initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll
          navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal
                        options:nil];
    self.pageController.dataSource = self;
    self.pageController.delegate = self;
    [self addChildViewController:self.pageController];
    self.pageController.view.frame = self.view.bounds;
    self.pageController.view.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.pageController.view];
    [self.pageController didMoveToParentViewController:self];

    self.dismissPan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self
                                               action:@selector(pannedDown:)];
    self.dismissPan.maximumNumberOfTouches = 1;
    self.dismissPan.delegate = self;
    [self.view addGestureRecognizer:self.dismissPan];
    for (UIView* subview in self.pageController.view.subviews) {
        if ([subview isKindOfClass:UIScrollView.class]) {
            // Direction is decided by dismissPan's delegate. A horizontal page
            // swipe proceeds as soon as that recognizer fails; a vertical drag
            // cannot move the horizontal pager underneath the dismissal.
            [((UIScrollView*)subview).panGestureRecognizer
                requireGestureRecognizerToFail:self.dismissPan];
            break;
        }
    }

    BHTMediaPageController* initial = [self pageAtIndex:self.currentIndex];
    if (initial) {
        [self.pageController setViewControllers:@[initial]
                                      direction:UIPageViewControllerNavigationDirectionForward
                                       animated:NO
                                     completion:nil];
    }

    self.postButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.postButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.postButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];
    self.postButton.tintColor = UIColor.whiteColor;
    [self.postButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.postButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.postButton.titleLabel.numberOfLines = 4;
    self.postButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.postButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.postButton.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
    self.postButton.layer.cornerRadius = 12;
    self.postButton.clipsToBounds = YES;
    [self.postButton addTarget:self
                        action:@selector(openCurrentPost:)
              forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.postButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.postButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.postButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.postButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [self.postButton.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [self.postButton.heightAnchor constraintLessThanOrEqualToConstant:116]
    ]];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.closeButton.backgroundColor =
        [UIColor colorWithWhite:0 alpha:0.62];
    self.closeButton.tintColor = UIColor.whiteColor;
    self.closeButton.layer.cornerRadius = 22;
    UIImageSymbolConfiguration* closeConfiguration =
        [UIImageSymbolConfiguration
            configurationWithPointSize:18
                                weight:UIImageSymbolWeightSemibold];
    [self.closeButton
        setImage:
            [UIImage systemImageNamed:@"xmark"
                        withConfiguration:closeConfiguration]
        forState:UIControlStateNormal];
    self.closeButton.accessibilityLabel = @"Close";
    self.closeButton.userInteractionEnabled = NO;
    [self.closeButton addTarget:self
                         action:@selector(closeTapped:)
               forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.closeButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.closeButton.leadingAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor
                           constant:12],
        [self.closeButton.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                           constant:8],
        [self.closeButton.widthAnchor constraintEqualToConstant:44],
        [self.closeButton.heightAnchor constraintEqualToConstant:44]
    ]];
    [self updatePostButton];
    [self requestMoreIfNeededAtIndex:self.currentIndex];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    UIInterfaceOrientationMask hostMask =
        self.presentingViewController.supportedInterfaceOrientations;
    if (hostMask != 0) return hostMask;
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad
               ? UIInterfaceOrientationMaskAll
               : UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.closeButton.userInteractionEnabled = YES;
    [self recordFullScreenCoverage];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Keep the pager edge-to-edge after iPad multitasking changes and device
    // rotation. Overlay controls remain pinned to the safe area.
    self.pageController.view.frame = self.view.bounds;
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:
           (id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size
          withTransitionCoordinator:coordinator];
    __weak typeof(self) weakSelf = self;
    [coordinator
        animateAlongsideTransition:
            ^(__unused id<UIViewControllerTransitionCoordinatorContext>
                  context) {
        typeof(self) strongSelf = weakSelf;
        strongSelf.pageController.view.frame =
            (CGRect){CGPointZero, size};
        [strongSelf.view layoutIfNeeded];
    }
                        completion:
            ^(__unused id<UIViewControllerTransitionCoordinatorContext>
                  context) {
        typeof(self) strongSelf = weakSelf;
        [strongSelf recordFullScreenCoverage];
    }];
}

- (void)recordFullScreenCoverage {
    UIWindow* window = self.view.window;
    if (!window || !self.view.superview) return;
    CGRect viewerRect =
        [self.view convertRect:self.view.bounds toView:window];
    CGRect intersection =
        CGRectIntersection(viewerRect, window.bounds);
    CGFloat tolerance = 1.0 / MAX(UIScreen.mainScreen.scale, 1);
    BOOL coversWindow =
        fabs(CGRectGetWidth(intersection) -
             CGRectGetWidth(window.bounds)) <= tolerance &&
        fabs(CGRectGetHeight(intersection) -
             CGRectGetHeight(window.bounds)) <= tolerance;
    BHTSetLikesDiagnostic(
        @"viewerFullScreenMeasured", @YES);
    BHTSetLikesDiagnostic(
        @"viewerFullScreenCoverage", @(coversWindow));
    BHTSetLikesDiagnostic(
        @"viewerEffectivePresentationStyle",
        @(self.modalPresentationStyle));
    if (coversWindow &&
        !self.recordedFullScreenActivation) {
        self.recordedFullScreenActivation = YES;
        BHTIncrementLikesDiagnostic(
            @"viewerFullScreenActivations");
    }
}

- (void)closeTapped:(id)sender {
    if (self.completingDismissal || self.isBeingPresented ||
        self.isBeingDismissed || !self.presentingViewController) {
        return;
    }
    self.completingDismissal = YES;
    [self dismissViewControllerAnimated:YES completion:nil];
    __weak typeof(self) weakSelf = self;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(0.45 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf.view.window &&
            strongSelf.presentingViewController &&
            !strongSelf.isBeingDismissed) {
            strongSelf.completingDismissal = NO;
            strongSelf.closeButton.userInteractionEnabled = YES;
        }
    });
}

- (id<UIViewControllerAnimatedTransitioning>)
    animationControllerForPresentedController:
        (UIViewController*)presented
                         presentingController:
        (UIViewController*)presenting
                             sourceController:
        (UIViewController*)source {
    BHTMediaViewerAnimator* animator =
        [BHTMediaViewerAnimator new];
    animator.presenting = YES;
    return animator;
}

- (id<UIViewControllerAnimatedTransitioning>)
    animationControllerForDismissedController:
        (UIViewController*)dismissed {
    BHTMediaViewerAnimator* animator =
        [BHTMediaViewerAnimator new];
    animator.presenting = NO;
    return animator;
}

- (id<UIViewControllerInteractiveTransitioning>)
    interactionControllerForDismissal:
        (id<UIViewControllerAnimatedTransitioning>)animator {
    return self.interactiveDismissal
               ? self.dismissalInteraction
               : nil;
}

- (BHTMediaPageController*)visibleMediaPage {
    UIViewController* visible =
        self.pageController.viewControllers.firstObject;
    return [visible isKindOfClass:BHTMediaPageController.class]
               ? (BHTMediaPageController*)visible
               : nil;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gestureRecognizer {
    if (gestureRecognizer != self.dismissPan || self.completingDismissal ||
        self.presentedViewController || self.pageTransitionInFlight ||
        self.isBeingPresented || self.isBeingDismissed ||
        !self.presentingViewController) {
        return gestureRecognizer != self.dismissPan;
    }
    BHTMediaPageController* visible = [self visibleMediaPage];
    if (visible.scrollView.zoomScale >
        visible.scrollView.minimumZoomScale + 0.01) {
        return NO;
    }
    CGPoint velocity =
        [(UIPanGestureRecognizer*)gestureRecognizer velocityInView:self.view];
    return velocity.y > 0 && fabs(velocity.y) > fabs(velocity.x) * 1.2;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:
        (UIGestureRecognizer*)otherGestureRecognizer {
    if (gestureRecognizer != self.dismissPan &&
        otherGestureRecognizer != self.dismissPan) {
        return NO;
    }
    UIGestureRecognizer* other =
        gestureRecognizer == self.dismissPan ? otherGestureRecognizer
                                             : gestureRecognizer;
    BHTMediaPageController* visible = [self visibleMediaPage];
    return other == visible.scrollView.panGestureRecognizer &&
           visible.scrollView.zoomScale <=
               visible.scrollView.minimumZoomScale + 0.01;
}

- (void)pannedDown:(UIPanGestureRecognizer*)pan {
    CGFloat translation =
        MAX(0, [pan translationInView:self.view].y);
    CGFloat height = MAX(1, CGRectGetHeight(self.view.bounds));

    if (pan.state == UIGestureRecognizerStateBegan) {
        self.completingDismissal = YES;
        self.interactiveDismissal = YES;
        [self visibleMediaPage].scrollView.scrollEnabled = NO;
        self.dismissalInteraction =
            [UIPercentDrivenInteractiveTransition new];
        self.dismissalInteraction.completionCurve =
            UIViewAnimationCurveEaseOut;
        self.dismissalInteraction.completionSpeed = 0.92;
        [self dismissViewControllerAnimated:YES completion:nil];

        id<UIViewControllerTransitionCoordinator> coordinator =
            self.transitionCoordinator;
        if (!coordinator) {
            [self.dismissalInteraction cancelInteractiveTransition];
            self.dismissalInteraction = nil;
            self.interactiveDismissal = NO;
            self.completingDismissal = NO;
            [self visibleMediaPage].scrollView.scrollEnabled = YES;
            return;
        }

        __weak typeof(self) weakSelf = self;
        [coordinator
            animateAlongsideTransition:nil
                            completion:
            ^(id<UIViewControllerTransitionCoordinatorContext> context) {
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf) return;
                BOOL cancelled = context.isCancelled;
                strongSelf.dismissalInteraction = nil;
                strongSelf.interactiveDismissal = NO;
                strongSelf.completingDismissal = !cancelled;
                if (cancelled) {
                    BHTMediaPageController* visiblePage =
                        [strongSelf visibleMediaPage];
                    visiblePage.scrollView.scrollEnabled = YES;
                    strongSelf.completingDismissal = NO;
                    if (strongSelf.pendingMediaUpdate) {
                        [strongSelf applyMediaItemsUpdate];
                    }
                }
            }];
        return;
    }

    if (pan.state == UIGestureRecognizerStateChanged) {
        CGFloat progress =
            MIN(1, translation / (height * 0.62));
        [self.dismissalInteraction
            updateInteractiveTransition:progress];
        return;
    }

    if (pan.state == UIGestureRecognizerStateCancelled ||
        pan.state == UIGestureRecognizerStateFailed) {
        self.interactiveDismissal = NO;
        [self.dismissalInteraction cancelInteractiveTransition];
        return;
    }
    if (pan.state != UIGestureRecognizerStateEnded) return;

    CGFloat velocity = [pan velocityInView:self.view].y;
    CGFloat projectedTranslation =
        translation + velocity * 0.20;
    BOOL reversing = velocity < -180;
    BOOL shouldDismiss =
        !reversing &&
        (projectedTranslation >= height * 0.22 ||
         (translation >= 24 && velocity >= 850));
    self.interactiveDismissal = NO;
    if (shouldDismiss) {
        [self.dismissalInteraction finishInteractiveTransition];
    } else {
        [self.dismissalInteraction cancelInteractiveTransition];
    }
}

- (BHTMediaPageController*)pageAtIndex:(NSUInteger)index {
    if (index >= self.items.count) return nil;
    return [[BHTMediaPageController alloc] initWithItem:self.items[index]
                                                  index:index];
}

- (BHTLikedMediaItem*)currentItem {
    return self.currentIndex < self.items.count ? self.items[self.currentIndex] : nil;
}

- (void)updatePostButton {
    BHTLikedMediaItem* item = [self currentItem];
    NSString* text = [item.statusText
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString* title = text.length > 0
                          ? [NSString stringWithFormat:@"%@\nView post and replies", text]
                          : @"View post and replies";
    [self.postButton setTitle:title forState:UIControlStateNormal];
    self.postButton.enabled = item.statusID > 0 || item.statusURL != nil;
    self.postButton.accessibilityHint = @"Opens the original liked post";
}

- (void)requestMoreIfNeededAtIndex:(NSUInteger)index {
    if (!self.loadMoreHandler || self.items.count == 0) return;
    if (self.items.count - MIN(index, self.items.count - 1) <= 8) {
        dispatch_async(dispatch_get_main_queue(), self.loadMoreHandler);
    }
}

- (void)mediaItemsDidUpdateWithItems:
    (NSArray<BHTLikedMediaItem*>*)items {
    self.pendingItems = [items copy];
    if (self.pageTransitionInFlight ||
        self.completingDismissal) {
        self.pendingMediaUpdate = YES;
        return;
    }
    [self applyMediaItemsUpdate];
}

- (void)applyMediaItemsUpdate {
    self.pendingMediaUpdate = NO;
    if (self.pendingItems) {
        self.items = self.pendingItems;
        self.pendingItems = nil;
    }
    if (!self.isViewLoaded || self.items.count == 0) return;
    NSUInteger previousCount = self.knownItemCount;
    BHTMediaPageController* visible =
        (BHTMediaPageController*)self.pageController.viewControllers.firstObject;
    NSString* visibleIdentifier = visible.item.identifier;
    self.knownItemCount = self.items.count;
    if (visibleIdentifier.length > 0) {
        NSUInteger updatedIndex =
            [self.items indexOfObjectPassingTest:^BOOL(
                BHTLikedMediaItem* candidate, NSUInteger index, BOOL* stop) {
                return [candidate.identifier isEqualToString:visibleIdentifier];
            }];
        if (updatedIndex != NSNotFound) {
            self.currentIndex = updatedIndex;
            visible.index = updatedIndex;
            visible.item = self.items[updatedIndex];
        }
    }
    self.currentIndex = MIN(self.currentIndex, self.items.count - 1);
    if (previousCount == 0 || self.currentIndex + 1 >= previousCount) {
        BHTMediaPageController* current = [self pageAtIndex:self.currentIndex];
        [self.pageController setViewControllers:@[current]
                                          direction:UIPageViewControllerNavigationDirectionForward
                                           animated:NO
                                         completion:nil];
    }
    [self updatePostButton];
}

- (void)openCurrentPost:(id)sender {
    BHTOpenLikedMediaPost([self currentItem]);
}

- (UIViewController*)pageViewController:(UIPageViewController*)pageViewController
      viewControllerBeforeViewController:(UIViewController*)viewController {
    NSUInteger index = ((BHTMediaPageController*)viewController).index;
    return index > 0 ? [self pageAtIndex:index - 1] : nil;
}

- (UIViewController*)pageViewController:(UIPageViewController*)pageViewController
       viewControllerAfterViewController:(UIViewController*)viewController {
    NSUInteger index = ((BHTMediaPageController*)viewController).index;
    [self requestMoreIfNeededAtIndex:index];
    return index + 1 < self.items.count ? [self pageAtIndex:index + 1] : nil;
}

- (void)pageViewController:(UIPageViewController*)pageViewController
    willTransitionToViewControllers:
        (NSArray<UIViewController*>*)pendingViewControllers {
    self.pageTransitionInFlight = YES;
}

- (void)pageViewController:(UIPageViewController*)pageViewController
        didFinishAnimating:(BOOL)finished
   previousViewControllers:(NSArray<UIViewController*>*)previousViewControllers
       transitionCompleted:(BOOL)completed {
    self.pageTransitionInFlight = NO;
    if (completed) {
        BHTMediaPageController* visible =
            (BHTMediaPageController*)
                pageViewController.viewControllers.firstObject;
        self.currentIndex = visible.index;
        [self updatePostButton];
        [self requestMoreIfNeededAtIndex:self.currentIndex];
    }
    if (self.pendingMediaUpdate) {
        [self applyMediaItemsUpdate];
    }
}

@end

#pragma mark - Likes container

static UIViewController*
BHTFullScreenPresenterForController(
    UIViewController* sourceController) {
    if (!sourceController) return nil;
    UIWindow* window =
        sourceController.viewIfLoaded.window;
    UIViewController* presenter =
        window.rootViewController ?: sourceController;
    while (presenter.presentedViewController &&
           !presenter.presentedViewController.isBeingDismissed) {
        presenter = presenter.presentedViewController;
    }
    return presenter.viewIfLoaded.window ? presenter
                                         : sourceController;
}

static void BHTRefreshNativeTabViewAppearance(T1TabView* tabView);

@interface BHTLikesModeSelector : UISegmentedControl
@end

@implementation BHTLikesModeSelector

- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    size.width = MAX(size.width, 216.0);
    size.height = MAX(size.height, 32.0);
    return size;
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize fitted = [super sizeThatFits:size];
    fitted.width = MAX(fitted.width, 216.0);
    fitted.height = MAX(fitted.height, 32.0);
    return fitted;
}

@end

@interface BHTLikesViewController : UIViewController <UICollectionViewDataSource,
                                                       UICollectionViewDelegate,
                                                       UICollectionViewDataSourcePrefetching,
                                                       BHTWaterfallLayoutDelegate>
@property(nonatomic, strong) UIViewController* postsController;
@property(nonatomic, strong) UISegmentedControl* selector;
@property(nonatomic, strong) UICollectionView* collectionView;
@property(nonatomic, strong) BHTWaterfallLayout* waterfallLayout;
@property(nonatomic, strong) UILabel* unavailableLabel;
@property(nonatomic, strong) NSMutableArray<BHTLikedMediaItem*>* mediaItems;
@property(nonatomic, strong) NSMutableSet<NSString*>* mediaIDs;
@property(nonatomic, strong)
    NSMutableDictionary<NSString*, BHTMediaImageRequestToken*>*
        prefetchRequests;
@property(nonatomic, weak) BHTMediaPagerController* activeMediaPager;
@property(nonatomic) BOOL requestedMore;
@property(nonatomic) BOOL needsInitialTopReset;
@property(nonatomic) BOOL initialResetMayRearm;
@property(nonatomic, strong) CADisplayLink* initialResetDisplayLink;
@property(nonatomic) CFTimeInterval initialResetDeadline;
@property(nonatomic) CFTimeInterval initialResetHardDeadline;
@property(nonatomic) NSUInteger loadRequestGeneration;
@property(nonatomic) BOOL waterfallLayoutInvalidationScheduled;
@property(nonatomic) BOOL waterfallLayoutInvalidationPendingUntilIdle;
@property(nonatomic) BOOL themeRefreshScheduled;
- (void)ingestSections:(NSArray*)sections;
- (void)loadMoreMedia;
- (void)resetToNewest;
- (void)activateForFirstPresentation;
- (void)configureWaterfallInterface;
- (void)ensureWaterfallSelectorInstalled;
- (void)restoreWaterfallSelectorVisibilityIfVisible;
- (void)recordWaterfallSelectorRuntimeState;
- (void)applyCurrentThemeSurfaces;
- (void)themeDidChange:(NSNotification*)notification;
- (void)updateAdaptiveAspectRatioForItem:(BHTLikedMediaItem*)item
                              fromImage:(UIImage*)image;
- (void)scheduleWaterfallLayoutInvalidation;
- (void)applyPendingWaterfallLayoutInvalidationIfIdle;
- (void)invalidateInitialResetDisplayLink;
- (void)cancelInitialResetGuard;
- (void)startInitialResetDisplayLinkIfNeeded;
@end

static void BHTFindVerticalScrollView(UIView* view, UIScrollView** best,
                                      CGFloat* bestScore) {
    if ([view isKindOfClass:UIScrollView.class]) {
        UIScrollView* scroll = (UIScrollView*)view;
        CGFloat range = scroll.contentSize.height - scroll.bounds.size.height;
        CGFloat score = MAX(0, range) + scroll.bounds.size.height / 1000.0;
        if (!*best || score > *bestScore) {
            *best = scroll;
            *bestScore = score;
        }
    }
    for (UIView* subview in view.subviews) {
        BHTFindVerticalScrollView(subview, best, bestScore);
    }
}

static UIScrollView* BHTFindScrollableView(UIView* view) {
    UIScrollView* best = nil;
    CGFloat bestScore = -1;
    BHTFindVerticalScrollView(view, &best, &bestScore);
    return best;
}

@implementation BHTLikesViewController

- (instancetype)init {
    if ((self = [super init])) {
        _postsController = BHTMakeNativeLikesController(BHTCurrentAccount());
        _mediaItems = [NSMutableArray array];
        _mediaIDs = [NSMutableSet set];
        _prefetchRequests = [NSMutableDictionary dictionary];
        _needsInitialTopReset = YES;
        self.title =
            [[BHTBundle sharedBundle] localizedStringForKey:@"MY_LIKES_TITLE"];
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(likesNavigationSettingsChanged:)
                   name:BHTLikesNavigationSettingsDidChangeNotification
                 object:nil];
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(themeDidChange:)
                   name:BHTThemeDidChangeNotification
                 object:nil];
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(themeDidChange:)
                   name:BHTSettingsProfileDidApplyNotification
                  object:nil];
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(themeDidChange:)
                   name:@"TFNDynamicColorsDidReloadNotification"
                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [self.initialResetDisplayLink invalidate];
    for (BHTMediaImageRequestToken* request in
         self.prefetchRequests.allValues) {
        BHTCancelMediaImageRequest(request);
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [Palette currentBackgroundColor];

    if (self.postsController) {
        [self addChildViewController:self.postsController];
        self.postsController.view.frame = self.view.bounds;
        self.postsController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:self.postsController.view];
        [self.postsController didMoveToParentViewController:self];
    } else {
        UILabel* unavailable = [[UILabel alloc] initWithFrame:self.view.bounds];
        unavailable.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        unavailable.numberOfLines = 0;
        unavailable.textAlignment = NSTextAlignmentCenter;
        unavailable.text = [[BHTBundle sharedBundle]
            localizedStringForKey:@"LIKES_UNAVAILABLE_MESSAGE"];
        self.unavailableLabel = unavailable;
        [self.view addSubview:unavailable];
    }

    [self configureWaterfallInterface];
    [self applyCurrentThemeSurfaces];
}

- (void)themeDidChange:(NSNotification*)notification {
    __weak typeof(self) weakSelf = self;
    void (^scheduleOnMain)(void) = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.themeRefreshScheduled) return;
        strongSelf.themeRefreshScheduled = YES;
        // Run after every observer of X's native reload signal has finished.
        // This keeps private host views from overwriting the custom surfaces
        // later in the same notification transaction.
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) refreshedSelf = weakSelf;
            if (!refreshedSelf) return;
            refreshedSelf.themeRefreshScheduled = NO;
            if (refreshedSelf.isViewLoaded) {
                [refreshedSelf applyCurrentThemeSurfaces];
            }
        });
    };
    if ([NSThread isMainThread]) {
        scheduleOnMain();
    } else {
        dispatch_async(dispatch_get_main_queue(), scheduleOnMain);
    }
}

- (void)applyCurrentThemeSurfaces {
    [self ensureWaterfallSelectorInstalled];
    UIColor* background = [Palette currentBackgroundColor];
    UIColor* surface = [Palette currentSurfaceColor];
    UIColor* elevated = [Palette currentElevatedSurfaceColor];
    UIColor* secondaryText = [Palette currentSecondaryTextColor];
    UIColor* separator = [Palette currentSeparatorColor];
    UIColor* accent = CurrentAccentColor() ?: UIColor.systemBlueColor;

    self.view.backgroundColor = background;
    self.view.tintColor = accent;
    // The retained Posts controller belongs to X. Its timeline, retweet, and
    // card surfaces are colored by the guarded provider hooks so transparent
    // or context-specific native backgrounds are never flattened here.
    self.collectionView.backgroundColor = background;
    self.collectionView.tintColor = accent;
    self.unavailableLabel.textColor = secondaryText;
    self.unavailableLabel.backgroundColor = background;

    // Keep UIKit's native segmented-control artwork. Supplying 1x1 custom
    // background images makes an unconstrained UINavigationItem titleView
    // advertise a roughly one-point fitting height on iOS 18.
    NSArray<NSNumber*>* selectorBackgroundStates = @[
        @(UIControlStateNormal),
        @(UIControlStateSelected),
        @(UIControlStateHighlighted),
        @(UIControlStateSelected | UIControlStateHighlighted)
    ];
    for (NSNumber* state in selectorBackgroundStates) {
        [self.selector
            setBackgroundImage:nil
                      forState:state.unsignedIntegerValue
                    barMetrics:UIBarMetricsDefault];
    }
    NSArray<NSNumber*>* selectorDividerStates = @[
        @(UIControlStateNormal), @(UIControlStateSelected)
    ];
    for (NSNumber* leftState in selectorDividerStates) {
        for (NSNumber* rightState in selectorDividerStates) {
            [self.selector
                setDividerImage:nil
                forLeftSegmentState:leftState.unsignedIntegerValue
                  rightSegmentState:rightState.unsignedIntegerValue
                        barMetrics:UIBarMetricsDefault];
        }
    }
    self.selector.backgroundColor = surface;
    self.selector.tintColor = accent;
    self.selector.selectedSegmentTintColor = elevated;
    self.selector.layer.borderColor = separator.CGColor;
    self.selector.layer.borderWidth = 0.5;
    self.selector.layer.cornerRadius = 8;
    self.selector.layer.masksToBounds = YES;
    [self.selector
        setTitleTextAttributes:@{
            NSForegroundColorAttributeName: secondaryText
        }
                    forState:UIControlStateNormal];
    [self.selector
        setTitleTextAttributes:@{
            NSForegroundColorAttributeName: accent
        }
                     forState:UIControlStateSelected];
    [self.selector invalidateIntrinsicContentSize];
    [self.selector sizeToFit];
    [self.selector setNeedsLayout];
    [self.selector setNeedsDisplay];
    [self.navigationController.navigationBar setNeedsLayout];

    // Shared navigation/tab bars and the native Posts controller are owned by
    // the global guarded theme hooks. Likes only writes its wrapper, selector,
    // waterfall, and custom cells.
    UIViewController* nativeNavigation =
        self.navigationController ?: self.parentViewController;
    T1TabView* nativeLikesTab =
        objc_getAssociatedObject(nativeNavigation,
                                 &kBHTNativeLikesTabViewKey);
    BHTRefreshNativeTabViewAppearance(nativeLikesTab);

    for (UICollectionViewCell* visibleCell
         in self.collectionView.visibleCells) {
        if ([visibleCell isKindOfClass:BHTLikedMediaCell.class]) {
            [(BHTLikedMediaCell*)visibleCell
                applyCurrentThemeSurface];
        }
    }
    [self.collectionView setNeedsDisplay];
    [self.view setNeedsDisplay];

    BHTIncrementLikesDiagnostic(@"themeRefreshes");
    NSString* activeTheme =
        [BHTThemePresets activePresetIdentifier];
    BHTSetLikesDiagnostic(
        @"themePreset",
        [BHTThemePresets isUserPresetIdentifier:activeTheme]
            ? @"user_theme"
            : (activeTheme ?: @"native"));
    BHTSetLikesDiagnostic(@"themeSegmentedControl",
                          @(self.selector != nil));
    BHTSetLikesDiagnostic(
        @"waterfallSelectorOwned",
        @(self.selector != nil &&
          self.navigationItem.titleView == self.selector));
    BHTSetLikesDiagnostic(@"themeSharedBarsOwnedByGlobalHook", @YES);
    BHTSetLikesDiagnostic(@"themeNativePostsOwnedByProviderHooks", @YES);
    BHTSetLikesDiagnostic(@"themeNativeLikesTab",
                          @(nativeLikesTab != nil));
}

- (void)traitCollectionDidChange:
    (UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!self.isViewLoaded) return;
    if (previousTraitCollection.userInterfaceStyle !=
        self.traitCollection.userInterfaceStyle) {
        [self applyCurrentThemeSurfaces];
    }
}

- (void)likesNavigationSettingsChanged:(NSNotification*)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isViewLoaded) [self configureWaterfallInterface];
        BHTRefreshLikesActivityHistoryConfiguration(
            self.postsController);
    });
}

- (void)configureWaterfallInterface {
    BOOL waterfallEnabled =
        [BHTLikesNavigationUtility waterfallEnabled];
    if (waterfallEnabled && !self.collectionView) {
        BHTBundle* bundle = [BHTBundle sharedBundle];
        self.selector = [[BHTLikesModeSelector alloc]
            initWithItems:@[
                [bundle localizedStringForKey:@"LIKES_POSTS_SEGMENT"],
                [bundle localizedStringForKey:@"LIKES_MEDIA_SEGMENT"]
            ]];
        self.selector.selectedSegmentIndex = 0;
        [self.selector
            setContentCompressionResistancePriority:
                UILayoutPriorityRequired
                                         forAxis:
                UILayoutConstraintAxisVertical];
        [self.selector sizeToFit];
        [self.selector addTarget:self
                          action:@selector(selectionChanged:)
                forControlEvents:UIControlEventValueChanged];
        [self ensureWaterfallSelectorInstalled];

        self.waterfallLayout = [BHTWaterfallLayout new];
        self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds
                                                 collectionViewLayout:self.waterfallLayout];
        self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.collectionView.backgroundColor =
            [Palette currentBackgroundColor];
        self.collectionView.dataSource = self;
        self.collectionView.delegate = self;
        self.collectionView.prefetchDataSource = self;
        self.collectionView.hidden = YES;
        [self.collectionView registerClass:BHTLikedMediaCell.class forCellWithReuseIdentifier:@"media"];
        [self.view addSubview:self.collectionView];

        UIPinchGestureRecognizer* pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinched:)];
        [self.collectionView addGestureRecognizer:pinch];
        if (!NSClassFromString(@"UIContextMenuInteraction")) {
            UILongPressGestureRecognizer* mediaActions =
                [[UILongPressGestureRecognizer alloc]
                    initWithTarget:self
                            action:
                                @selector(waterfallMediaLongPressed:)];
            mediaActions.minimumPressDuration = 0.45;
            mediaActions.cancelsTouchesInView = NO;
            [self.collectionView
                addGestureRecognizer:mediaActions];
        }
        [self.collectionView.panGestureRecognizer
            addTarget:self
               action:@selector(cancelInitialResetFromPan:)];
        [self applyCurrentThemeSurfaces];
    } else if (!waterfallEnabled && self.collectionView) {
        for (BHTMediaImageRequestToken* request in
             self.prefetchRequests.allValues) {
            BHTCancelMediaImageRequest(request);
        }
        [self.prefetchRequests removeAllObjects];
        self.postsController.view.hidden = NO;
        self.postsController.view.userInteractionEnabled = YES;
        self.postsController.view.accessibilityElementsHidden = NO;
        [self.collectionView removeFromSuperview];
        self.collectionView = nil;
        self.waterfallLayout = nil;
        self.waterfallLayoutInvalidationScheduled = NO;
        self.waterfallLayoutInvalidationPendingUntilIdle = NO;
        if (self.navigationItem.titleView == self.selector) {
            self.navigationItem.titleView = nil;
        }
        self.selector = nil;
        BHTSetLikesDiagnostic(@"waterfallSelectorOwned", @NO);
    }
}

- (void)ensureWaterfallSelectorInstalled {
    if (![BHTLikesNavigationUtility waterfallEnabled] ||
        !self.selector) {
        return;
    }
    if (self.navigationItem.titleView != self.selector) {
        self.navigationItem.titleView = self.selector;
        BHTIncrementLikesDiagnostic(
            @"waterfallSelectorInstalls");
    }
    BHTSetLikesDiagnostic(@"waterfallSelectorOwned", @YES);
}

- (void)restoreWaterfallSelectorVisibilityIfVisible {
    if (![BHTLikesNavigationUtility waterfallEnabled] ||
        !self.selector) {
        return;
    }
    if (!self.isViewLoaded || !self.view.window) {
        [self recordWaterfallSelectorRuntimeState];
        return;
    }
    UINavigationController* navigation =
        self.navigationController;
    if (navigation && navigation.topViewController != self) {
        [self recordWaterfallSelectorRuntimeState];
        return;
    }
    [self ensureWaterfallSelectorInstalled];
    self.selector.hidden = NO;
    self.selector.alpha = 1;
    [self.selector invalidateIntrinsicContentSize];
    [self.selector sizeToFit];
    [navigation.navigationBar setNeedsLayout];
    [navigation.navigationBar layoutIfNeeded];
    [self recordWaterfallSelectorRuntimeState];
}

- (void)recordWaterfallSelectorRuntimeState {
    UISegmentedControl* selector = self.selector;
    UINavigationController* navigation = self.navigationController;
    UINavigationBar* navigationBar = navigation.navigationBar;
    BOOL navigationBarHidden =
        navigationBar ? navigationBar.hidden : NO;
    CGFloat navigationBarHeight =
        navigationBar
            ? CGRectGetHeight(navigationBar.bounds)
            : 0;
    BOOL owned =
        selector && self.navigationItem.titleView == selector;
    BOOL topControllerMatches =
        !navigation || navigation.topViewController == self;
    CGFloat height = selector
        ? CGRectGetHeight(selector.bounds)
        : 0;
    CGSize intrinsicSize = selector
        ? selector.intrinsicContentSize
        : CGSizeZero;
    CGSize fittingSize = selector
        ? [selector sizeThatFits:CGSizeZero]
        : CGSizeZero;
    BOOL customBackgroundArtwork =
        selector &&
        [selector
            backgroundImageForState:UIControlStateNormal
                           barMetrics:UIBarMetricsDefault] != nil;

    NSString* geometryState = @"visibleGeometry";
    if (!selector) {
        geometryState = @"notCreated";
    } else if (!owned) {
        geometryState = @"notOwned";
    } else if (navigationBarHidden) {
        geometryState = @"navigationBarHidden";
    } else if (selector.hidden || selector.alpha <= 0.01) {
        geometryState = @"selectorHidden";
    } else if (height < 24.0 ||
               intrinsicSize.height < 24.0 ||
               fittingSize.height < 24.0) {
        geometryState = @"collapsedHeight";
    } else if (!selector.window) {
        geometryState = @"notInWindow";
    } else if (!topControllerMatches) {
        geometryState = @"notTopController";
    }

    BHTSetLikesDiagnostic(
        @"waterfallSelectorGeometryState", geometryState);
    BHTSetLikesDiagnostic(
        @"waterfallSelectorHeight", @(height));
    BHTSetLikesDiagnostic(
        @"waterfallSelectorIntrinsicHeight",
        @(intrinsicSize.height));
    BHTSetLikesDiagnostic(
        @"waterfallSelectorFittingHeight",
        @(fittingSize.height));
    BHTSetLikesDiagnostic(
        @"waterfallSelectorHidden", @(selector.hidden));
    BHTSetLikesDiagnostic(
        @"waterfallSelectorAlpha", @(selector.alpha));
    BHTSetLikesDiagnostic(
        @"waterfallSelectorWindowAttached",
        @(selector.window != nil));
    BHTSetLikesDiagnostic(
        @"waterfallSelectorSuperviewClass",
        selector.superview
            ? NSStringFromClass(selector.superview.class)
            : @"none");
    BHTSetLikesDiagnostic(
        @"waterfallSelectorCustomBackgroundArtwork",
        @(customBackgroundArtwork));
    BHTSetLikesDiagnostic(
        @"waterfallNavigationBarHidden",
        @(navigationBarHidden));
    BHTSetLikesDiagnostic(
        @"waterfallNavigationBarHeight",
        @(navigationBarHeight));
    BHTSetLikesDiagnostic(
        @"waterfallNavigationTopControllerMatches",
        @(topControllerMatches));
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self configureWaterfallInterface];
    [self ensureWaterfallSelectorInstalled];
    [self applyCurrentThemeSurfaces];
    [self applyPendingWaterfallLayoutInvalidationIfIdle];
    // Reset before UIKit presents the first Likes frame. This keeps X's
    // restored middle position off-screen without an artificial loading view.
    if (!self.needsInitialTopReset) return;
    [self activateForFirstPresentation];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Visibility normalization belongs after the transition so it cannot
    // override UINavigationBar's interactive title fading.
    [self restoreWaterfallSelectorVisibilityIfVisible];

    // BookmarksNavigationController can replace its title area after
    // forwarding the child's appearance callback. Reclaim it once at the end
    // of this run-loop turn, but only if Likes is still the visible root.
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf restoreWaterfallSelectorVisibilityIfVisible];
    });
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // The guard is strictly a first-presentation tool. Switching tabs or
    // opening the media viewer must freeze the current reading position.
    [self cancelInitialResetGuard];
}

- (void)activateForFirstPresentation {
    // Swift tab activation can reuse the retained root without forwarding a
    // fresh UIKit appearance callback. Reclaim the navigation title here too,
    // but never force the controller's view to load just for the selector.
    if (self.isViewLoaded) {
        [self ensureWaterfallSelectorInstalled];
    }
    if (!self.needsInitialTopReset) return;
    self.needsInitialTopReset = NO;
    [self resetToNewest];
}

- (void)invalidateInitialResetDisplayLink {
    [self.initialResetDisplayLink invalidate];
    self.initialResetDisplayLink = nil;
}

- (void)cancelInitialResetGuard {
    self.initialResetMayRearm = NO;
    [self invalidateInitialResetDisplayLink];
}

- (void)startInitialResetDisplayLinkIfNeeded {
    if (self.initialResetDisplayLink || !self.initialResetMayRearm) return;
    self.initialResetDisplayLink =
        [CADisplayLink displayLinkWithTarget:self
                                    selector:
            @selector(enforceInitialNewestPosition:)];
    self.initialResetDisplayLink.preferredFramesPerSecond = 30;
    [self.initialResetDisplayLink
        addToRunLoop:NSRunLoop.mainRunLoop
             forMode:NSRunLoopCommonModes];
}

- (void)enforceInitialNewestPosition:
    (__unused CADisplayLink*)displayLink {
    CFTimeInterval now = CACurrentMediaTime();
    if (now >= self.initialResetHardDeadline) {
        [self cancelInitialResetGuard];
        return;
    }
    if (now >= self.initialResetDeadline) {
        // Keep the one-shot eligible to rearm when the first real Activity
        // History sections arrive after a slow network response.
        [self invalidateInitialResetDisplayLink];
        return;
    }

    [self.postsController.view layoutIfNeeded];
    UIScrollView* nativeScroll =
        BHTFindScrollableView(self.postsController.view);
    UIPanGestureRecognizer* nativePan =
        nativeScroll.panGestureRecognizer;
    BOOL userInteracting =
        nativeScroll &&
        (nativeScroll.dragging || nativeScroll.tracking ||
         (nativePan.numberOfTouches > 0 &&
          (nativePan.state == UIGestureRecognizerStateBegan ||
           nativePan.state == UIGestureRecognizerStateChanged)));
    if (userInteracting) {
        [self cancelInitialResetGuard];
        return;
    }

    if (nativeScroll) {
        if (![objc_getAssociatedObject(nativePan,
                                       &kBHTInitialResetPanMarkerKey)
                boolValue]) {
            [nativePan addTarget:self
                          action:@selector(cancelInitialResetFromPan:)];
            objc_setAssociatedObject(nativePan,
                                     &kBHTInitialResetPanMarkerKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        CGFloat top = -nativeScroll.adjustedContentInset.top;
        [nativeScroll
            setContentOffset:CGPointMake(nativeScroll.contentOffset.x, top)
                    animated:NO];
    }
    if (self.collectionView) {
        CGFloat top = -self.collectionView.adjustedContentInset.top;
        [self.collectionView
            setContentOffset:
                CGPointMake(self.collectionView.contentOffset.x, top)
                    animated:NO];
    }
}

- (void)resetToNewest {
    if (!self.isViewLoaded) {
        self.needsInitialTopReset = YES;
        return;
    }
    BHTIncrementLikesDiagnostic(@"topResets");

    // The compatible host runtime restores Activity History's private content offset after several
    // asynchronous layout/data passes. Clamp it to the newest item during the
    // first presentation only, without hiding the timeline or showing a
    // loading cover. The first real user pan or leaving this controller ends
    // the guard immediately, so later tab visits retain the exact position.
    [self invalidateInitialResetDisplayLink];
    CFTimeInterval now = CACurrentMediaTime();
    self.initialResetMayRearm = YES;
    self.initialResetDeadline = now + 2.5;
    self.initialResetHardDeadline = now + 15.0;
    [self startInitialResetDisplayLinkIfNeeded];
    [self enforceInitialNewestPosition:nil];
}

- (void)cancelInitialResetFromPan:(UIPanGestureRecognizer*)pan {
    if (pan.numberOfTouches > 0 &&
        (pan.state == UIGestureRecognizerStateBegan ||
         pan.state == UIGestureRecognizerStateChanged)) {
        [self cancelInitialResetGuard];
    }
}

- (void)selectionChanged:(UISegmentedControl*)sender {
    // Changing the view is an explicit user action. Stop the first-open clamp
    // before Media pagination scrolls the hidden native timeline to its cursor.
    [self cancelInitialResetGuard];
    BOOL media = sender.selectedSegmentIndex == 1;
    // Keep the native Likes timeline alive behind the opaque media grid. X
    // pauses pagination for hidden controller views, which previously forced
    // users to return to Posts and scroll manually before more media appeared.
    self.postsController.view.hidden = NO;
    self.postsController.view.userInteractionEnabled = !media;
    self.postsController.view.accessibilityElementsHidden = media;
    self.collectionView.hidden = !media;
    if (media) {
        [self.view bringSubviewToFront:self.collectionView];
        [self applyPendingWaterfallLayoutInvalidationIfIdle];
        if (self.mediaItems.count < 12) [self loadMoreMedia];
    }
}

- (void)pinched:(UIPinchGestureRecognizer*)pinch {
    if (pinch.state != UIGestureRecognizerStateEnded) return;
    NSInteger delta = 0;
    if (pinch.scale > 1.08) {
        delta = -1;
    } else if (pinch.scale < 0.92) {
        delta = 1;
    } else {
        return;
    }
    NSInteger columns = MAX(
        2, MIN(5, self.waterfallLayout.columns + delta));
    if (columns == self.waterfallLayout.columns) return;
    self.waterfallLayout.columns = columns;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf scheduleWaterfallLayoutInvalidation];
        [weakSelf applyPendingWaterfallLayoutInvalidationIfIdle];
    });
}

- (void)updateAdaptiveAspectRatioForItem:(BHTLikedMediaItem*)item
                              fromImage:(UIImage*)image {
    if (!item || !image) return;
    if (![NSThread isMainThread]) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf updateAdaptiveAspectRatioForItem:item
                                             fromImage:image];
        });
        return;
    }

    CGFloat decodedRatio = BHTDecodedImageAspectRatio(image);
    if (decodedRatio <= 0) return;
    CGFloat suppliedRatio =
        BHTBoundedMediaAspectRatio(item.aspectRatio);
    if (item.aspectRatioConfirmedByImage &&
        fabs(decodedRatio - suppliedRatio) /
                MAX(decodedRatio, suppliedRatio) <
            0.01) {
        return;
    }

    NSUInteger currentIndex =
        [self.mediaItems
            indexOfObjectPassingTest:^BOOL(
                BHTLikedMediaItem* candidate,
                __unused NSUInteger index,
                __unused BOOL* stop) {
        return candidate == item ||
               (item.identifier.length > 0 &&
                [candidate.identifier
                    isEqualToString:item.identifier]);
    }];
    if (currentIndex == NSNotFound) return;
    item = self.mediaItems[currentIndex];

    CGFloat previousRatio =
        BHTBoundedMediaAspectRatio(item.aspectRatio);
    item.aspectRatioConfirmedByImage = YES;
    CGFloat relativeDifference =
        fabs(decodedRatio - previousRatio) /
        MAX(decodedRatio, previousRatio);
    // Ignore rounding noise from thumbnail decodes. Meaningful differences
    // are applied once and coalesced into a single next-run-loop layout pass.
    if (relativeDifference < 0.01) return;

    item.aspectRatio = decodedRatio;
    BHTIncrementLikesDiagnostic(
        @"waterfallDecodedRatioCorrections");
    [self scheduleWaterfallLayoutInvalidation];
}

- (void)scheduleWaterfallLayoutInvalidation {
    if (!self.waterfallLayout ||
        self.waterfallLayoutInvalidationScheduled) {
        return;
    }
    if (self.collectionView.tracking ||
        self.collectionView.dragging ||
        self.collectionView.decelerating) {
        self.waterfallLayoutInvalidationPendingUntilIdle = YES;
        return;
    }
    self.waterfallLayoutInvalidationPendingUntilIdle = NO;
    self.waterfallLayoutInvalidationScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.waterfallLayoutInvalidationScheduled = NO;
        if (!strongSelf.waterfallLayout ||
            !strongSelf.collectionView) {
            return;
        }
        if (strongSelf.collectionView.tracking ||
            strongSelf.collectionView.dragging ||
            strongSelf.collectionView.decelerating) {
            strongSelf
                .waterfallLayoutInvalidationPendingUntilIdle = YES;
            return;
        }

        UICollectionView* collectionView =
            strongSelf.collectionView;
        NSIndexPath* anchorIndexPath = nil;
        UICollectionViewLayoutAttributes* anchorAttributes = nil;
        CGFloat viewportTop = collectionView.contentOffset.y;
        CGFloat nearestDistance = CGFLOAT_MAX;
        for (NSIndexPath* indexPath in
             collectionView.indexPathsForVisibleItems) {
            UICollectionViewLayoutAttributes* attributes =
                [strongSelf.waterfallLayout
                    layoutAttributesForItemAtIndexPath:indexPath];
            if (!attributes) continue;
            CGFloat distance =
                fabs(CGRectGetMinY(attributes.frame) - viewportTop);
            if (distance < nearestDistance) {
                nearestDistance = distance;
                anchorIndexPath = indexPath;
                anchorAttributes = attributes;
            }
        }
        CGFloat anchorOffset = anchorAttributes
            ? viewportTop - CGRectGetMinY(anchorAttributes.frame)
            : 0;

        [strongSelf.waterfallLayout invalidateLayout];
        [collectionView layoutIfNeeded];

        UICollectionViewLayoutAttributes* updatedAnchor =
            anchorIndexPath
                ? [strongSelf.waterfallLayout
                      layoutAttributesForItemAtIndexPath:
                          anchorIndexPath]
                : nil;
        if (updatedAnchor) {
            UIEdgeInsets inset = collectionView.adjustedContentInset;
            CGFloat minimumY = -inset.top;
            CGFloat maximumY = MAX(
                minimumY,
                collectionView.contentSize.height -
                    CGRectGetHeight(collectionView.bounds) +
                    inset.bottom);
            CGFloat targetY =
                CGRectGetMinY(updatedAnchor.frame) + anchorOffset;
            if (isfinite(targetY)) {
                targetY = MIN(maximumY, MAX(minimumY, targetY));
                [collectionView
                    setContentOffset:
                        CGPointMake(collectionView.contentOffset.x,
                                    targetY)
                             animated:NO];
                BHTIncrementLikesDiagnostic(
                    @"waterfallAnchorPreservations");
            }
        }
    });
}

- (void)applyPendingWaterfallLayoutInvalidationIfIdle {
    if (!self.waterfallLayoutInvalidationPendingUntilIdle ||
        self.collectionView.tracking ||
        self.collectionView.dragging ||
        self.collectionView.decelerating) {
        return;
    }
    self.waterfallLayoutInvalidationPendingUntilIdle = NO;
    [self scheduleWaterfallLayoutInvalidation];
}

- (void)waterfallMediaLongPressed:
    (UILongPressGestureRecognizer*)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan ||
        self.collectionView.hidden || self.presentedViewController) {
        return;
    }
    CGPoint location =
        [gesture locationInView:self.collectionView];
    NSIndexPath* indexPath =
        [self.collectionView indexPathForItemAtPoint:location];
    if (!indexPath ||
        indexPath.item >= (NSInteger)self.mediaItems.count) {
        return;
    }
    UICollectionViewCell* cell =
        [self.collectionView cellForItemAtIndexPath:indexPath];
    UIView* sourceView = cell.contentView ?: self.collectionView;
    BHTPresentLikedMediaActionSheet(
        self, self.mediaItems[indexPath.item], sourceView);
}

- (UIContextMenuConfiguration*)collectionView:
        (UICollectionView*)collectionView
    contextMenuConfigurationForItemAtIndexPath:
        (NSIndexPath*)indexPath
                                      point:
        (CGPoint)point API_AVAILABLE(ios(13.0)) {
    if (collectionView != self.collectionView ||
        collectionView.hidden ||
        self.presentedViewController ||
        indexPath.item >= (NSInteger)self.mediaItems.count) {
        return nil;
    }
    UICollectionViewCell* cell =
        [collectionView cellForItemAtIndexPath:indexPath];
    UIView* sourceView =
        cell.contentView ?: collectionView;
    return BHTLikedMediaContextConfiguration(
        self, self.mediaItems[indexPath.item], sourceView);
}

- (void)ingestSections:(NSArray*)sections {
    if (sections.count > 0 && self.initialResetMayRearm &&
        self.view.window &&
        CACurrentMediaTime() < self.initialResetHardDeadline) {
        // X may deliver/restores its Activity History content well after
        // viewWillAppear. Clamp for a short period after every first-load
        // section update so a slow response still lands on the newest Like.
        CFTimeInterval extendedDeadline = CACurrentMediaTime() + 1.5;
        self.initialResetDeadline =
            MIN(self.initialResetHardDeadline,
                MAX(self.initialResetDeadline, extendedDeadline));
        [self startInitialResetDisplayLinkIfNeeded];
        [self enforceInitialNewestPosition:nil];
    }
    NSArray* incoming = BHTMediaItemsFromSections(sections);
    if (incoming.count == 0) {
        self.loadRequestGeneration++;
        self.requestedMore = NO;
        return;
    }

    NSMutableDictionary<NSString*, BHTLikedMediaItem*>*
        existingMediaByID = [NSMutableDictionary dictionary];
    for (BHTLikedMediaItem* existingItem in self.mediaItems) {
        if (existingItem.identifier.length > 0) {
            existingMediaByID[existingItem.identifier] =
                existingItem;
        }
    }
    for (BHTLikedMediaItem* incomingItem in incoming) {
        BHTLikedMediaItem* existingItem =
            existingMediaByID[incomingItem.identifier];
        if (existingItem.aspectRatioConfirmedByImage) {
            incomingItem.aspectRatio = existingItem.aspectRatio;
            incomingItem.aspectRatioConfirmedByImage = YES;
        }
    }

    NSMutableSet<NSString*>* incomingIDs = [NSMutableSet set];
    BOOL overlapsExisting = NO;
    for (BHTLikedMediaItem* item in incoming) {
        if (item.identifier.length == 0 ||
            [incomingIDs containsObject:item.identifier]) {
            continue;
        }
        [incomingIDs addObject:item.identifier];
        if ([self.mediaIDs containsObject:item.identifier]) {
            overlapsExisting = YES;
        }
    }

    // X normally sends the complete ordered section snapshot. Rebuild from
    // that order so newly liked media moves to the top. If it sends a page-only
    // delta, a pending pagination request identifies it as older content and
    // appends it instead; a refresh delta is prepended.
    NSMutableArray<BHTLikedMediaItem*>* ordered = [NSMutableArray array];
    NSMutableSet<NSString*>* orderedIDs = [NSMutableSet set];
    void (^appendUnique)(NSArray<BHTLikedMediaItem*>*) =
        ^(NSArray<BHTLikedMediaItem*>* items) {
            for (BHTLikedMediaItem* item in items) {
                if (item.identifier.length == 0 ||
                    [orderedIDs containsObject:item.identifier]) {
                    continue;
                }
                [orderedIDs addObject:item.identifier];
                [ordered addObject:item];
            }
        };

    BOOL pageOnlyPagination = self.requestedMore && !overlapsExisting;
    if (pageOnlyPagination) {
        appendUnique(self.mediaItems);
        appendUnique(incoming);
    } else {
        appendUnique(incoming);
        appendUnique(self.mediaItems);
    }

    NSArray<NSString*>* previousOrder =
        [self.mediaItems valueForKey:@"identifier"];
    NSArray<NSString*>* nextOrder = [ordered valueForKey:@"identifier"];
    BOOL changed = ![previousOrder isEqualToArray:nextOrder];
    BOOL geometryChanged = changed;
    if (!geometryChanged &&
        self.mediaItems.count == ordered.count) {
        for (NSUInteger index = 0; index < ordered.count;
             index++) {
            CGFloat previousRatio = BHTBoundedMediaAspectRatio(
                self.mediaItems[index].aspectRatio);
            CGFloat nextRatio = BHTBoundedMediaAspectRatio(
                ordered[index].aspectRatio);
            CGFloat relativeDifference =
                fabs(previousRatio - nextRatio) /
                MAX(previousRatio, nextRatio);
            if (relativeDifference >= 0.01) {
                geometryChanged = YES;
                break;
            }
        }
    }
    [self.mediaItems setArray:ordered];
    [self.mediaIDs setSet:orderedIDs];
    BHTSetLikesDiagnostic(@"capturedMediaItems", @(self.mediaItems.count));
    self.loadRequestGeneration++;
    self.requestedMore = NO;
    if (changed && self.isViewLoaded) {
        [self.collectionView reloadData];
        [self.activeMediaPager
            mediaItemsDidUpdateWithItems:self.mediaItems];
    } else if (geometryChanged && self.isViewLoaded) {
        [self scheduleWaterfallLayoutInvalidation];
        [self.activeMediaPager
            mediaItemsDidUpdateWithItems:self.mediaItems];
    }
}

- (NSInteger)collectionView:(UICollectionView*)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.mediaItems.count;
}

- (UICollectionViewCell*)collectionView:(UICollectionView*)collectionView
                 cellForItemAtIndexPath:(NSIndexPath*)indexPath {
    BHTLikedMediaCell* cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"media" forIndexPath:indexPath];
    BHTLikedMediaItem* item = self.mediaItems[indexPath.item];
    [cell applyCurrentThemeSurface];
    cell.videoBadge.hidden = item.videoURL == nil;
    cell.representedURL = item.previewURL;
    CGFloat targetPixels =
        BHTTargetPixelsForView(cell.contentView, 1.2);
    UIImage* cached =
        BHTCachedMediaImage(
            item.previewURL,
            BHTMediaImagePixelBucket(targetPixels));
    if (cached) {
        cell.imageView.image = cached;
        [self updateAdaptiveAspectRatioForItem:item
                                     fromImage:cached];
    } else if (item.previewURL) {
        __weak BHTLikedMediaCell* weakCell = cell;
        __weak typeof(self) weakSelf = self;
        NSURL* url = item.previewURL;
        cell.imageRequest =
            BHTRequestMediaImage(
                url, targetPixels, ^(UIImage* image) {
                    [weakSelf
                        updateAdaptiveAspectRatioForItem:item
                                               fromImage:image];
                    if ([weakCell.representedURL
                            isEqual:url]) {
                        weakCell.imageView.image = image;
                    }
                });
    }
    return cell;
}

- (void)collectionView:(UICollectionView*)collectionView
    prefetchItemsAtIndexPaths:
        (NSArray<NSIndexPath*>*)indexPaths {
    CGFloat width =
        CGRectGetWidth(collectionView.bounds);
    NSInteger columns =
        MAX(2, self.waterfallLayout.columns);
    CGFloat points =
        MAX(160, width / columns);
    UIScreen* screen =
        collectionView.window.screen ?:
        UIScreen.mainScreen;
    CGFloat pixels =
        points * screen.scale * 1.2;
    for (NSIndexPath* indexPath in indexPaths) {
        if (indexPath.item >=
            (NSInteger)self.mediaItems.count) {
            continue;
        }
        BHTLikedMediaItem* item =
            self.mediaItems[indexPath.item];
        NSString* identifier = item.identifier;
        NSURL* URL = item.previewURL;
        if (!URL || identifier.length == 0 ||
            self.prefetchRequests[identifier] ||
            BHTCachedMediaImage(
                URL,
                BHTMediaImagePixelBucket(pixels))) {
            continue;
        }
        __weak typeof(self) weakSelf = self;
        BHTLikedMediaItem* requestedItem = item;
        self.prefetchRequests[identifier] =
            BHTRequestMediaImage(
                URL, pixels, ^(UIImage* image) {
                    [weakSelf.prefetchRequests
                        removeObjectForKey:identifier];
                    [weakSelf
                        updateAdaptiveAspectRatioForItem:
                            requestedItem
                                               fromImage:image];
                });
    }
}

- (void)collectionView:(UICollectionView*)collectionView
    cancelPrefetchingForItemsAtIndexPaths:
        (NSArray<NSIndexPath*>*)indexPaths {
    for (NSIndexPath* indexPath in indexPaths) {
        if (indexPath.item >=
            (NSInteger)self.mediaItems.count) {
            continue;
        }
        NSString* identifier =
            self.mediaItems[indexPath.item].identifier;
        BHTMediaImageRequestToken* request =
            self.prefetchRequests[identifier];
        BHTCancelMediaImageRequest(request);
        [self.prefetchRequests
            removeObjectForKey:identifier];
    }
}

- (CGFloat)waterfallAspectRatioAtIndexPath:(NSIndexPath*)indexPath {
    return indexPath.item < (NSInteger)self.mediaItems.count
               ? self.mediaItems[indexPath.item].aspectRatio
               : 1.0;
}

- (void)collectionView:(UICollectionView*)collectionView didSelectItemAtIndexPath:(NSIndexPath*)indexPath {
    BHTMediaPagerController* activeViewer =
        self.activeMediaPager;
    if (activeViewer &&
        (activeViewer.isBeingPresented ||
         activeViewer.isBeingDismissed ||
         activeViewer.presentingViewController ||
         activeViewer.viewIfLoaded.window)) {
        return;
    }
    BHTMediaPagerController* viewer =
        [[BHTMediaPagerController alloc] initWithItems:self.mediaItems
                                          initialIndex:indexPath.item];
    __weak typeof(self) weakSelf = self;
    viewer.loadMoreHandler = ^{ [weakSelf loadMoreMedia]; };
    self.activeMediaPager = viewer;
    UIViewController* presenter =
        BHTFullScreenPresenterForController(self);
    BHTIncrementLikesDiagnostic(
        @"viewerFullScreenAttempts");
    [presenter presentViewController:viewer
                            animated:YES
                          completion:^{
        [viewer recordFullScreenCoverage];
    }];
}

- (void)collectionView:(UICollectionView*)collectionView
        willDisplayCell:(UICollectionViewCell*)cell
  forItemAtIndexPath:(NSIndexPath*)indexPath {
    if (self.mediaItems.count - indexPath.item <= 8) [self loadMoreMedia];
}

- (void)loadMoreMedia {
    if (self.requestedMore || !self.postsController) return;
    self.postsController.view.hidden = NO;
    UIScrollView* nativeScroll = BHTFindScrollableView(self.postsController.view);
    if (!nativeScroll) return;

    CGFloat top = -nativeScroll.adjustedContentInset.top;
    CGFloat bottom = MAX(top,
        nativeScroll.contentSize.height - nativeScroll.bounds.size.height +
            nativeScroll.adjustedContentInset.bottom);
    if (bottom <= top + 1) return;

    self.requestedMore = YES;
    NSUInteger generation = ++self.loadRequestGeneration;
    void (^scrollToBottom)(void) = ^{
        [nativeScroll setContentOffset:
            CGPointMake(nativeScroll.contentOffset.x, bottom) animated:NO];
    };
    if (fabs(nativeScroll.contentOffset.y - bottom) < 1) {
        CGFloat nudge = MAX(top, bottom - MAX(80, nativeScroll.bounds.size.height * 0.2));
        [nativeScroll setContentOffset:
            CGPointMake(nativeScroll.contentOffset.x, nudge) animated:NO];
        dispatch_async(dispatch_get_main_queue(), scrollToBottom);
    } else {
        scrollToBottom();
    }

    // A cursor can legitimately return no new posts. Release the throttle so
    // another end-of-grid/page gesture can retry instead of getting stuck.
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        if (weakSelf.loadRequestGeneration == generation) {
            weakSelf.requestedMore = NO;
        }
    });
}

- (void)scrollViewDidScroll:(UIScrollView*)scrollView {
    if (scrollView != self.collectionView || self.requestedMore || self.mediaItems.count == 0) return;
    CGFloat remaining = scrollView.contentSize.height - CGRectGetMaxY((CGRect){scrollView.contentOffset, scrollView.bounds.size});
    if (remaining <= 900) [self loadMoreMedia];
}

- (void)scrollViewDidEndDragging:(UIScrollView*)scrollView
                  willDecelerate:(BOOL)decelerate {
    if (scrollView == self.collectionView && !decelerate) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf applyPendingWaterfallLayoutInvalidationIfIdle];
        });
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView*)scrollView {
    if (scrollView == self.collectionView) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf applyPendingWaterfallLayoutInvalidationIfIdle];
        });
    }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView*)scrollView {
    if (scrollView == self.collectionView) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf applyPendingWaterfallLayoutInvalidationIfIdle];
        });
    }
}

@end

BOOL BHTIsManagedLikesActivityHistoryController(
    UIViewController* controller) {
    UIViewController* current = controller;
    while (current) {
        if ([current isKindOfClass:BHTLikesViewController.class]) {
            return YES;
        }
        current = current.parentViewController;
    }
    return NO;
}

static Class BHTNativeBookmarksEntryClass(void) {
    return NSClassFromString(
        @"T1TwitterSwift.BookmarksAppNavigationTabEntry");
}

static Class BHTNativeBookmarksNavigationClass(void) {
    return NSClassFromString(
        @"T1TwitterSwift.BookmarksNavigationController");
}

static uintptr_t BHTT1TwitterImageBase(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t index = 0; index < count; index++) {
        const char* name = _dyld_get_image_name(index);
        if (name &&
            strstr(name, "/T1Twitter.framework/T1Twitter") != NULL) {
            return (uintptr_t)_dyld_get_image_header(index);
        }
    }
    return 0;
}

static id BHTMakeNativeBookmarksEntry(void) {
    BHTIncrementLikesDiagnostic(@"nativeEntryFactoryAttempts");
    uintptr_t imageBase = BHTT1TwitterImageBase();
    if (imageBase == 0) {
        BHTSetLikesDiagnostic(@"nativeEntryFactoryFailure",
                              @"T1TwitterImageNotFound");
        return nil;
    }

    // The audited runtime's own panel-entry switch has case 6 allocate and
    // initialize BookmarksAppNavigationTabEntry with the current account.
    // Validate the switch prologue, panel-6 jump-table target, and invariant
    // case instructions before calling so another X build is skipped safely
    // instead of jumping into a changed private function.
    uintptr_t factoryAddress = imageBase + kBHTAuditedEntryFactoryOffset;
    const uint32_t* instructions = (const uint32_t*)factoryAddress;
    const uint8_t* jumpTable =
        (const uint8_t*)(imageBase +
                         kBHTAuditedEntryFactoryJumpTableOffset);
    const uint32_t* bookmarksCase =
        (const uint32_t*)(imageBase +
                          kBHTAuditedBookmarksFactoryCaseOffset);
    if (instructions[0] != 0xD10203FF ||
        instructions[6] != 0xF1005C1F ||
        jumpTable[kBHTLikesPanelID] != 0x91 ||
        bookmarksCase[0] != 0xD2800000 ||
        bookmarksCase[3] != 0xAA0003F4 ||
        bookmarksCase[4] != 0xAA1303E0 ||
        bookmarksCase[6] != 0xAA0003F3) {
        BHTSetLikesDiagnostic(@"nativeEntryFactoryFailure",
                              @"AuditedFactorySignatureMismatch");
        return nil;
    }

    id account = BHTCurrentAccount();
    if (!account) {
        BHTSetLikesDiagnostic(@"nativeEntryFactoryFailure",
                              @"CurrentAccountUnavailable");
        return nil;
    }

    typedef id (*BHTNativeEntryFactory)(long long, id, id);
    BHTNativeEntryFactory factory =
        (BHTNativeEntryFactory)factoryAddress;
    id entry = factory(kBHTLikesPanelID, account, nil);
    Class expectedClass = BHTNativeBookmarksEntryClass();
    T1TabView* tabView = BHTCallObject(entry, @"tabView");
    if (!entry || !expectedClass ||
        ![entry isKindOfClass:expectedClass] || !tabView) {
        BHTSetLikesDiagnostic(@"nativeEntryFactoryFailure",
                              @"NativeBookmarksEntryValidationFailed");
        return nil;
    }

    BHTIncrementLikesDiagnostic(@"nativeEntryFactorySuccesses");
    BHTSetLikesDiagnostic(@"nativeCarrierClass",
                          NSStringFromClass([entry class]));
    BHTSetLikesDiagnostic(@"nativeCarrierPanelID",
                          @(tabView.panelID));
    return entry;
}

BOOL BHTIsNativeLikesEntry(id entry) {
    return [objc_getAssociatedObject(entry,
                                     &kBHTNativeLikesEntryMarkerKey)
        boolValue];
}

static void BHTRefreshNativeTabViewAppearance(T1TabView* tabView) {
    if (!tabView) return;
    SEL titleSelector = @selector(_t1_updateTitleLabel);
    Method titleMethod =
        class_getInstanceMethod([tabView class], titleSelector);
    char titleReturnType[16] = {0};
    if ([tabView respondsToSelector:titleSelector] &&
        titleMethod &&
        method_getNumberOfArguments(titleMethod) == 2) {
        method_getReturnType(
            titleMethod, titleReturnType,
            sizeof(titleReturnType));
        if (titleReturnType[0] == 'v') {
            @try {
                ((void (*)(id, SEL))objc_msgSend)(
                    tabView, titleSelector);
            } @catch (__unused NSException* exception) {
            }
        }
    }

    SEL imageSelector = @selector(_t1_updateImageViewAnimated:);
    Method imageMethod =
        class_getInstanceMethod([tabView class], imageSelector);
    char imageReturnType[16] = {0};
    char animatedType[16] = {0};
    if ([tabView respondsToSelector:imageSelector] &&
        imageMethod &&
        method_getNumberOfArguments(imageMethod) == 3) {
        method_getReturnType(
            imageMethod, imageReturnType,
            sizeof(imageReturnType));
        method_getArgumentType(
            imageMethod, 2, animatedType,
            sizeof(animatedType));
        if (imageReturnType[0] == 'v' &&
            (animatedType[0] == 'c' ||
             animatedType[0] == 'B')) {
            @try {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(
                    tabView, imageSelector, NO);
            } @catch (__unused NSException* exception) {
            }
        }
    }
    [tabView setNeedsLayout];
}

static void BHTConfigureNativeLikesEntry(id entry, BOOL injected) {
    T1TabView* tabView = BHTCallObject(entry, @"tabView");
    if (!entry || !tabView) return;
    if (!objc_getAssociatedObject(tabView, &kBHTOriginalNativePageKey)) {
        objc_setAssociatedObject(
            tabView, &kBHTOriginalNativePageKey,
            tabView.scribePage.length ? tabView.scribePage : @"bookmarks",
            OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    objc_setAssociatedObject(entry, &kBHTNativeLikesEntryMarkerKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(entry, &kBHTInjectedNativeLikesEntryKey,
                             @(injected),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(tabView, &kBHTLikesEntryKey, entry,
                             OBJC_ASSOCIATION_ASSIGN);
    tabView.scribePage = kBHTLikesPage;
    // Bookmarks is a native carrier, so its label and glyph may already have
    // been rendered before the scribe page is changed. Force the hooked
    // refresh paths now; otherwise the first frame can still say Bookmarks
    // until the user selects the tab.
    tabView.titleLabel.text = @"Likes";
    tabView.accessibilityLabel = @"Likes";
    BHTRefreshNativeTabViewAppearance(tabView);
}

static void BHTRestoreNativeEntryPage(id entry) {
    T1TabView* tabView = BHTCallObject(entry, @"tabView");
    UIViewController* navigation =
        objc_getAssociatedObject(tabView, &kBHTNativeLikesNavigationKey);
    NSString* original =
        objc_getAssociatedObject(tabView, &kBHTOriginalNativePageKey);
    if (original.length > 0) tabView.scribePage = original;
    BHTRefreshNativeTabViewAppearance(tabView);
    tabView.accessibilityLabel = tabView.title;
    objc_setAssociatedObject(tabView, &kBHTLikesEntryKey, nil,
                             OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(tabView, &kBHTNativeLikesNavigationKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (navigation) {
        objc_setAssociatedObject(navigation,
                                 &kBHTNativeLikesTabViewKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(entry, &kBHTNativeLikesEntryMarkerKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void BHTRecordNativeLikesFactoryRequest(BOOL contentController) {
    BHTIncrementLikesDiagnostic(contentController
                                    ? @"contentControllerRequests"
                                    : @"factoryRequests");
}

BOOL BHTIsNativeLikesNavigationController(UIViewController* controller) {
    return [objc_getAssociatedObject(
        controller, &kBHTNativeLikesNavigationMarkerKey) boolValue];
}

static void BHTMarkNativeLikesNavigationController(
    UIViewController* controller) {
    if (!controller) return;
    objc_setAssociatedObject(controller,
                             &kBHTNativeLikesNavigationMarkerKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BHTSetLikesDiagnostic(@"nativeNavigationClass",
                          NSStringFromClass([controller class]));
}

void BHTConnectNativeLikesNavigationController(
    UIViewController* controller, UIView* tabView) {
    if (!controller || !tabView) return;
    BHTMarkNativeLikesNavigationController(controller);
    objc_setAssociatedObject(tabView, &kBHTNativeLikesNavigationKey,
                             controller,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller, &kBHTNativeLikesTabViewKey,
                             tabView,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void BHTConnectNativeLikesNavigationTree(UIViewController* root, id entry) {
    UIViewController* navigation =
        BHTFindController(root, BHTNativeBookmarksNavigationClass());
    UIView* tabView = BHTCallObject(entry, @"tabView");
    if (navigation && tabView) {
        BHTConnectNativeLikesNavigationController(navigation, tabView);
    }
}

static BHTLikesViewController*
BHTLikesControllerForNativeNavigation(UIViewController* navigation,
                                      BOOL create) {
    BHTLikesViewController* likes =
        objc_getAssociatedObject(navigation, &kBHTNativeLikesControllerKey);
    if (!likes && create) {
        likes = [BHTLikesViewController new];
        objc_setAssociatedObject(navigation, &kBHTNativeLikesControllerKey,
                                 likes,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BHTIncrementLikesDiagnostic(@"nativeRootCreations");
        BHTIncrementLikesDiagnostic(@"nativeSurfaceCreations");
        BHTSetLikesDiagnostic(@"standaloneRootClass",
                              NSStringFromClass([likes class]));
        BHTSetLikesDiagnostic(@"postsControllerClass",
            likes.postsController
                ? NSStringFromClass([likes.postsController class])
                : @"");
    }
    return likes;
}

void BHTInstallNativeLikesNavigationController(
    UIViewController* navigation, BOOL resetToNewest) {
    if (![CustomTabBarUtility likesTabEnabled] ||
        !BHTIsNativeLikesNavigationController(navigation)) {
        return;
    }

    BHTLikesViewController* likes =
        BHTLikesControllerForNativeNavigation(navigation, YES);
    if (!likes) return;

    if ([navigation isKindOfClass:UINavigationController.class]) {
        UINavigationController* nativeNavigation =
            (UINavigationController*)navigation;
        // Keep native destinations opened from X's side menu (Profile,
        // History, Lists, and similar screens) on top of the retained Likes
        // root. Replacing the entire stack whenever this navigation
        // controller reappeared made every side-menu tap immediately fall
        // back to Likes.
        if (nativeNavigation.viewControllers.firstObject != likes) {
            [nativeNavigation setViewControllers:@[likes] animated:NO];
            BHTIncrementLikesDiagnostic(@"nativeNavigationInstalls");
        } else if (nativeNavigation.viewControllers.count > 1) {
            BHTIncrementLikesDiagnostic(
                @"nativeChildNavigationPreservations");
        }
    } else if (likes.parentViewController != navigation) {
        [navigation addChildViewController:likes];
        likes.view.frame = navigation.view.bounds;
        likes.view.autoresizingMask =
            UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;
        [navigation.view addSubview:likes.view];
        [likes didMoveToParentViewController:navigation];
        BHTIncrementLikesDiagnostic(@"nativeNavigationInstalls");
    }

    if (resetToNewest) [likes resetToNewest];
    T1TabView* tabView =
        objc_getAssociatedObject(navigation,
                                 &kBHTNativeLikesTabViewKey);
    BOOL likesIsVisible = YES;
    if ([navigation isKindOfClass:UINavigationController.class]) {
        likesIsVisible =
            ((UINavigationController*)navigation).topViewController ==
            likes;
    }
    if (tabView.isSelected && likesIsVisible) {
        [likes activateForFirstPresentation];
    }
}

static void BHTActivateLikesTabViewNow(T1TabView* view) {
    if (![CustomTabBarUtility likesTabEnabled] || !view.isSelected ||
        ![view.scribePage isEqualToString:kBHTLikesPage]) {
        return;
    }
    UIViewController* navigation =
        objc_getAssociatedObject(view, &kBHTNativeLikesNavigationKey);
    if (!navigation) return;
    BHTIncrementLikesDiagnostic(@"tabActivations");
    // Re-selecting the bottom destination must not jump the retained Likes
    // controller back to the top. Its one-time first-presentation reset is
    // owned by BHTLikesViewController.
    BHTInstallNativeLikesNavigationController(navigation, NO);
    BHTLikesViewController* likes =
        BHTLikesControllerForNativeNavigation(navigation, NO);
    BOOL likesIsVisible = YES;
    if ([navigation isKindOfClass:UINavigationController.class]) {
        likesIsVisible =
            ((UINavigationController*)navigation).topViewController ==
            likes;
    }
    if (likesIsVisible) {
        [likes activateForFirstPresentation];
    }
}

void BHTActivateLikesTabView(UIView* view) {
    // T1TabView changes selection while the Swift navigation owner is still
    // mutating its controller arrays. Defer root access/containment until that
    // transaction finishes to avoid re-entering the private selection path.
    __weak T1TabView* weakView = (T1TabView*)view;
    dispatch_async(dispatch_get_main_queue(), ^{
        BHTActivateLikesTabViewNow(weakView);
    });
}

NSArray* BHTEntriesByInstallingLikesDestination(NSArray* entries) {
    BOOL enabled = [CustomTabBarUtility likesTabEnabled];
    NSMutableArray* result = [entries mutableCopy] ?: [NSMutableArray array];
    id likesEntry = nil;
    id anchor = nil;
    Class nativeEntryClass = BHTNativeBookmarksEntryClass();

    for (id entry in [result copy]) {
        if (BHTIsNativeLikesEntry(entry)) {
            likesEntry = entry;
            if (!enabled) {
                BOOL injected =
                    [objc_getAssociatedObject(
                        entry, &kBHTInjectedNativeLikesEntryKey) boolValue];
                BHTRestoreNativeEntryPage(entry);
                if (injected) [result removeObjectIdenticalTo:entry];
            }
            continue;
        }
        if (enabled && nativeEntryClass &&
            [entry isKindOfClass:nativeEntryClass] && !likesEntry) {
            likesEntry = entry;
            BHTConfigureNativeLikesEntry(entry, NO);
            continue;
        }
        if (!anchor) anchor = entry;
    }

    if (enabled && !likesEntry) {
        likesEntry =
            objc_getAssociatedObject(anchor,
                                     &kBHTRetainedNativeLikesEntryKey);
        if (![likesEntry isKindOfClass:nativeEntryClass]) {
            likesEntry = BHTMakeNativeBookmarksEntry();
            if (anchor && likesEntry) {
                objc_setAssociatedObject(anchor,
                                         &kBHTRetainedNativeLikesEntryKey,
                                         likesEntry,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        if (likesEntry) {
            BHTConfigureNativeLikesEntry(likesEntry, YES);
            [result addObject:likesEntry];
        }
    }

    return result;
}

BOOL BHTCaptureLikesSections(UIViewController* dataViewController, NSArray* sections) {
    UIViewController* current = dataViewController;
    while (current && ![current isKindOfClass:BHTLikesViewController.class]) {
        current = current.parentViewController;
    }
    if ([current isKindOfClass:BHTLikesViewController.class]) {
        [(BHTLikesViewController*)current ingestSections:sections];
        return YES;
    }
    return NO;
}
