//
//  ThemeAccent.x
//  NeoFreeBird
//
//  Applies NeoFreeBird's optional accent and full theme presets through X's
//  active palette. The concrete palette class changes between light/dark
//  appearances and X releases, so every hook validates the live method first.
//

#import "HookHelpers.h"
#import "Compatibility/BHTCompatibilityReporter.h"
#import "ThemeColor/BHTThemePresets.h"
#import <dlfcn.h>
#include <stdint.h>
#include <string.h>

@interface UIColor (BHTThemeColorProviders)
+ (id)twitterColors;
+ (id)tfnuiColors;
@end

static char kBHTPaletteAccentColorKey;
static char kBHTPaletteAccentOptionKey;
static char kBHTPaletteHookInstalledKey;
static char kBHTPaletteOriginalPrimaryColorIMPKey;
static char kBHTPaletteOriginalColorGetterIMPsKey;
static char kBHTPaletteInstalledColorGettersKey;
static char kBHTPaletteBackgroundColorKey;
static char kBHTPaletteSurfaceColorKey;
static char kBHTPaletteElevatedSurfaceColorKey;
static char kBHTPaletteTextColorKey;
static char kBHTPaletteSecondaryTextColorKey;
static char kBHTPaletteSeparatorColorKey;
static char kBHTPaletteActionColorKey;
static char kBHTPaletteConfigurationGenerationKey;
static char kBHTPaletteConfigurationDarkAppearanceKey;
static NSUInteger BHTThemeRefreshAttempts;
static NSUInteger BHTThemeRefreshGeneration;
static BOOL BHTLastApplyCurrentPaletteUsed;
static BOOL BHTLastPaletteSetterFallbackUsed;
static volatile uint8_t BHTLastDynamicColorsDidReloadObserved;
static volatile uint8_t BHTProviderAttachRefreshScheduled;
static volatile uint8_t BHTForcedProviderRedrawExecuting;
static volatile uint8_t BHTPostReloadProviderRedrawNeeded;
static volatile uint64_t BHTDynamicColorsReloadSequence;
static NSArray<NSString*>* BHTLastT1RefreshSelectorsUsed;
static NSUInteger BHTLastVisibleViewsVisited;
static NSUInteger BHTLastDynamicColorViewsUpdated;
static volatile uint64_t BHTThemeConfigurationGeneration = 1;
static __weak id BHTLastDiagnosticPalette;
static BOOL BHTLastDiagnosticDarkAppearance;
static NSArray<NSString*>* BHTLastThemeProviderClasses;

typedef UIColor* (*BHTPrimaryColorForOptionIMP)(id, SEL, NSUInteger);
typedef UIColor* (*BHTColorGetterIMP)(id, SEL);

static const char* BHTUnqualifiedThemeType(const char* type) {
    while (type && strchr("rnNoORV", type[0])) type++;
    return type;
}

static BOOL BHTPrimaryColorMethodIsCompatible(Method method) {
    if (!method || method_getNumberOfArguments(method) != 3) return NO;

    char returnType[32] = {0};
    char optionType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    method_getArgumentType(method, 2, optionType, sizeof(optionType));
    const char* unqualifiedReturn = BHTUnqualifiedThemeType(returnType);
    const char* unqualifiedOption = BHTUnqualifiedThemeType(optionType);
    return unqualifiedReturn && unqualifiedReturn[0] == '@' &&
           unqualifiedOption &&
           strchr("cCsSiIlLqQ", unqualifiedOption[0]) != NULL;
}

static BOOL BHTColorGetterMethodIsCompatible(Method method) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* unqualifiedReturn =
        BHTUnqualifiedThemeType(returnType);
    return unqualifiedReturn && unqualifiedReturn[0] == '@';
}

static BOOL BHTVoidObjectSetterIsCompatible(Method method) {
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char returnType[16] = {0};
    char valueType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    method_getArgumentType(method, 2, valueType, sizeof(valueType));
    const char* unqualifiedReturn =
        BHTUnqualifiedThemeType(returnType);
    const char* unqualifiedValue =
        BHTUnqualifiedThemeType(valueType);
    return unqualifiedReturn && unqualifiedReturn[0] == 'v' &&
           unqualifiedValue && unqualifiedValue[0] == '@';
}

static BOOL BHTVoidGetterIsCompatible(Method method) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* unqualifiedReturn =
        BHTUnqualifiedThemeType(returnType);
    return unqualifiedReturn && unqualifiedReturn[0] == 'v';
}

static BOOL BHTInvokeGuardedVoidGetter(id target, SEL selector) {
    if (!target || !selector ||
        ![target respondsToSelector:selector]) {
        return NO;
    }
    Method method =
        class_getInstanceMethod(object_getClass(target), selector);
    if (!BHTVoidGetterIsCompatible(method)) return NO;
    @try {
        ((void (*)(id, SEL))objc_msgSend)(target, selector);
        return YES;
    } @catch (__unused NSException* exception) {
        return NO;
    }
}

static NSNotificationName BHTDynamicColorNotificationName(
    const char* symbolName, NSNotificationName fallbackName) {
    // These notification constants are exported by TFNUI in X 12.9. Resolve
    // them dynamically so an older/newer host that omits the symbols still
    // gets the harmless string-name fallback rather than a load failure.
    void* address = dlsym(RTLD_DEFAULT, symbolName);
    if (address) {
        NSString* __unsafe_unretained* storage =
            (NSString* __unsafe_unretained*)address;
        NSString* value = *storage;
        if ([value isKindOfClass:NSString.class] && value.length > 0) {
            return value;
        }
    }
    return fallbackName;
}

static uint64_t BHTCurrentThemeConfigurationGeneration(void) {
    return __atomic_load_n(
        &BHTThemeConfigurationGeneration, __ATOMIC_ACQUIRE);
}

static uint64_t BHTAdvanceThemeConfigurationGeneration(void) {
    return __atomic_add_fetch(
        &BHTThemeConfigurationGeneration, 1, __ATOMIC_ACQ_REL);
}

static BOOL BHTDidObserveDynamicColorsReload(void) {
    return __atomic_load_n(
               &BHTLastDynamicColorsDidReloadObserved,
               __ATOMIC_ACQUIRE) != 0;
}

static void BHTResetDynamicColorsReloadObservation(void) {
    __atomic_store_n(
        &BHTLastDynamicColorsDidReloadObserved, 0,
        __ATOMIC_RELEASE);
}

static NSHashTable* BHTSeenThemePalettes(void) {
    static NSHashTable* palettes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        palettes = [NSHashTable weakObjectsHashTable];
    });
    return palettes;
}

static void BHTTrackSeenThemePalette(id palette) {
    if (!palette) return;
    NSHashTable* palettes = BHTSeenThemePalettes();
    @synchronized(palettes) {
        [palettes addObject:palette];
    }
}

static NSArray* BHTSeenThemePaletteSnapshot(void) {
    NSHashTable* palettes = BHTSeenThemePalettes();
    @synchronized(palettes) {
        return palettes.allObjects;
    }
}

static NSUInteger BHTSeenThemePaletteCount(void) {
    NSHashTable* palettes = BHTSeenThemePalettes();
    @synchronized(palettes) {
        return palettes.allObjects.count;
    }
}

static NSArray<NSString*>* BHTInstalledColorGetterNames(id palette) {
    if (!palette) return @[];
    NSMutableSet<NSString*>* names = [NSMutableSet set];
    for (Class cls = object_getClass(palette); cls;
         cls = class_getSuperclass(cls)) {
        NSDictionary<NSString*, NSNumber*>* installed =
            objc_getAssociatedObject(
                cls, &kBHTPaletteInstalledColorGettersKey);
        [installed enumerateKeysAndObjectsUsingBlock:^(
                       NSString* name, NSNumber* active,
                       BOOL* stop) {
            if (active.boolValue && name.length > 0) {
                [names addObject:name];
            }
        }];
    }
    return [[names allObjects]
        sortedArrayUsingSelector:@selector(compare:)];
}

static NSArray<NSString*>*
BHTInstalledColorGetterNamesForSeenProviders(id activePalette) {
    NSMutableSet<NSString*>* names = [NSMutableSet set];
    if (activePalette) {
        [names addObjectsFromArray:
                   BHTInstalledColorGetterNames(activePalette)];
    }
    for (id provider in BHTSeenThemePaletteSnapshot()) {
        [names addObjectsFromArray:
                   BHTInstalledColorGetterNames(provider)];
    }
    return [[names allObjects]
        sortedArrayUsingSelector:@selector(compare:)];
}

static NSString* BHTActiveThemeDiagnosticIdentifier(void) {
    NSString* preset = [BHTThemePresets activePresetIdentifier];
    if (preset.length > 0) return preset;
    return [Palette customAccentColor] ? @"custom_accent" : @"native";
}

static void BHTRecordCurrentThemeRuntime(
    id palette, BOOL darkAppearance) {
    BHTRecordThemeRuntimeObservation(
        BHTActiveThemeDiagnosticIdentifier(),
        palette ? NSStringFromClass(object_getClass(palette))
                : @"unavailable",
        darkAppearance,
        BHTInstalledColorGetterNamesForSeenProviders(palette),
        BHTThemeRefreshAttempts,
        (NSUInteger)BHTCurrentThemeConfigurationGeneration(),
        BHTSeenThemePaletteCount(),
        BHTLastThemeProviderClasses ?: @[],
        BHTLastApplyCurrentPaletteUsed,
        BHTLastT1RefreshSelectorsUsed ?: @[],
        BHTLastPaletteSetterFallbackUsed,
        BHTDidObserveDynamicColorsReload(),
        BHTLastVisibleViewsVisited,
        BHTLastDynamicColorViewsUpdated);
}

static void BHTRefreshActiveThemePalette(
    BOOL reapplyColor, BOOL forceProviderRedraw);

static void BHTScheduleProviderAttachRefresh(void) {
    uint8_t alreadyScheduled =
        __atomic_exchange_n(
            &BHTProviderAttachRefreshScheduled, 1,
            __ATOMIC_ACQ_REL);
    if (alreadyScheduled != 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        __atomic_store_n(
            &BHTProviderAttachRefreshScheduled, 0,
            __ATOMIC_RELEASE);
        BOOL forceProviderRedraw =
            __atomic_exchange_n(
                &BHTPostReloadProviderRedrawNeeded,
                0, __ATOMIC_ACQ_REL) != 0;
        BHTRefreshActiveThemePalette(
            NO, forceProviderRedraw);
    });
}

static void BHTInstallDynamicColorDiagnosticObserver(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSNotificationName name = BHTDynamicColorNotificationName(
            "TFNDynamicColorsDidReloadNotification",
            @"TFNDynamicColorsDidReloadNotification");
        [NSNotificationCenter.defaultCenter
            addObserverForName:name
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification* notification) {
                        __atomic_store_n(
                            &BHTLastDynamicColorsDidReloadObserved, 1,
                            __ATOMIC_RELEASE);
                        __atomic_add_fetch(
                            &BHTDynamicColorsReloadSequence, 1,
                            __ATOMIC_ACQ_REL);
                        if (__atomic_load_n(
                                &BHTForcedProviderRedrawExecuting,
                                __ATOMIC_ACQUIRE) != 0) {
                            // A private updater invoked by our bounded pass
                            // emitted another reload. Record it, but do not
                            // turn that synchronous signal into an async loop.
                            return;
                        }
                        // X can swap or retarget its UIColor singleton
                        // providers during a light/dark reload. Reattach role
                        // colors on the next main-loop turn without invoking
                        // X's apply methods or reposting its notification. A
                        // bounded redraw follows only if attachment happened
                        // after synchronous observers had already run.
                        BHTScheduleProviderAttachRefresh();
                    }];
    });
}

static void BHTUpdateDynamicColorsInVisibleView(
    UIView* view, NSUInteger depth, BOOL root,
    IMP baseUpdateImplementation, NSUInteger* visited,
    NSUInteger* updated) {
    static const NSUInteger kBHTMaximumThemeTraversalDepth = 80;
    static const NSUInteger kBHTMaximumThemeTraversalViews = 6000;
    if (!view || depth > kBHTMaximumThemeTraversalDepth ||
        *visited >= kBHTMaximumThemeTraversalViews) {
        return;
    }
    (*visited)++;

    SEL selector = NSSelectorFromString(@"_t1_updateDynamicColors");
    Method method =
        class_getInstanceMethod(object_getClass(view), selector);
    if ([view respondsToSelector:selector] &&
        BHTVoidGetterIsCompatible(method)) {
        IMP implementation = method_getImplementation(method);
        // If X ever adds a generic UIView implementation, call it once at
        // each visible root instead of multiplying a recursive/base update
        // across thousands of descendants. Subclass-specialized updates are
        // still invoked on their own instances.
        if (root || !baseUpdateImplementation ||
            implementation != baseUpdateImplementation) {
            @try {
                ((void (*)(id, SEL))objc_msgSend)(view, selector);
                (*updated)++;
            } @catch (__unused NSException* exception) {
                // A private class can disappear or change behavior between
                // releases. One failed optional refresh must not affect the
                // rest of the theme or the app.
            }
        }
    }

    NSArray<UIView*>* children = [view.subviews copy];
    for (UIView* child in children) {
        BHTUpdateDynamicColorsInVisibleView(
            child, depth + 1, NO, baseUpdateImplementation,
            visited, updated);
        if (*visited >= kBHTMaximumThemeTraversalViews) break;
    }
}

static void BHTScheduleVisibleDynamicColorRefresh(
    NSUInteger generation, id palette, BOOL darkAppearance,
    BOOL forceRefresh) {
    __weak id weakPalette = palette;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != BHTThemeRefreshGeneration) return;
        if (BHTDidObserveDynamicColorsReload() && !forceRefresh) {
            // X emitted its correctly populated private reload event, so its
            // registered UIKit/SwiftUI observers normally own the redraw.
            // forceRefresh is reserved for a provider attached after those
            // synchronous observers already resolved their colors.
            BHTRecordCurrentThemeRuntime(
                weakPalette, darkAppearance);
            return;
        }

        BOOL ownsForcedRedrawGuard = NO;
        if (forceRefresh) {
            uint8_t alreadyExecuting =
                __atomic_exchange_n(
                    &BHTForcedProviderRedrawExecuting, 1,
                    __ATOMIC_ACQ_REL);
            if (alreadyExecuting != 0) return;
            ownsForcedRedrawGuard = YES;
        }

        NSUInteger visited = 0;
        NSUInteger updated = 0;
        SEL selector =
            NSSelectorFromString(@"_t1_updateDynamicColors");
        Method baseMethod =
            class_getInstanceMethod(UIView.class, selector);
        IMP baseImplementation =
            BHTVoidGetterIsCompatible(baseMethod)
                ? method_getImplementation(baseMethod)
                : NULL;
        @try {
            for (UIWindow* window
                 in UIApplication.sharedApplication.windows) {
                if (window.hidden || window.alpha <= 0.01 ||
                    !window.rootViewController) {
                    continue;
                }
                UISceneActivationState state =
                    window.windowScene.activationState;
                if (window.windowScene &&
                    state !=
                        UISceneActivationStateForegroundActive &&
                    state !=
                        UISceneActivationStateForegroundInactive) {
                    continue;
                }
                BHTUpdateDynamicColorsInVisibleView(
                    window, 0, YES, baseImplementation,
                    &visited, &updated);
            }
        } @catch (__unused NSException* exception) {
            // The pass is a best-effort compatibility fallback.
        } @finally {
            if (ownsForcedRedrawGuard) {
                __atomic_store_n(
                    &BHTForcedProviderRedrawExecuting, 0,
                    __ATOMIC_RELEASE);
            }
        }

        if (generation != BHTThemeRefreshGeneration) return;
        BHTLastVisibleViewsVisited = visited;
        BHTLastDynamicColorViewsUpdated = updated;
        BHTRecordCurrentThemeRuntime(weakPalette, darkAppearance);
    });
}

static IMP BHTOriginalColorGetterIMP(id palette, SEL selector) {
    NSString* selectorName = NSStringFromSelector(selector);
    for (Class cls = object_getClass(palette); cls;
         cls = class_getSuperclass(cls)) {
        NSDictionary<NSString*, NSValue*>* originals =
            objc_getAssociatedObject(
                cls, &kBHTPaletteOriginalColorGetterIMPsKey);
        NSValue* value = originals[selectorName];
        if (value.pointerValue) return (IMP)value.pointerValue;
    }
    return NULL;
}

static UIColor* BHTThemedColorGetter(id palette, SEL selector,
                                     const void* colorKey,
                                     UIColor* fallback) {
    UIColor* color = objc_getAssociatedObject(palette, colorKey);
    if (color) return color;
    IMP original = BHTOriginalColorGetterIMP(palette, selector);
    return original ? ((BHTColorGetterIMP)original)(palette, selector)
                    : fallback;
}

static UIColor* BHTThemedBackgroundColor(id palette, SEL selector) {
    return BHTThemedColorGetter(
        palette, selector, &kBHTPaletteBackgroundColorKey,
        UIColor.systemBackgroundColor);
}

static UIColor* BHTThemedSurfaceColor(id palette, SEL selector) {
    return BHTThemedColorGetter(
        palette, selector, &kBHTPaletteSurfaceColorKey,
        UIColor.secondarySystemBackgroundColor);
}

static UIColor* BHTThemedElevatedSurfaceColor(id palette, SEL selector) {
    return BHTThemedColorGetter(
        palette, selector, &kBHTPaletteElevatedSurfaceColorKey,
        UIColor.tertiarySystemBackgroundColor);
}

static UIColor* BHTThemedTextColor(id palette, SEL selector) {
    return BHTThemedColorGetter(
        palette, selector, &kBHTPaletteTextColorKey,
        UIColor.labelColor);
}

static UIColor* BHTThemedSecondaryTextColor(id palette, SEL selector) {
    return BHTThemedColorGetter(
        palette, selector, &kBHTPaletteSecondaryTextColorKey,
        UIColor.secondaryLabelColor);
}

static UIColor* BHTThemedSeparatorColor(id palette, SEL selector) {
    return BHTThemedColorGetter(
        palette, selector, &kBHTPaletteSeparatorColorKey,
        UIColor.separatorColor);
}

static UIColor* BHTThemedActionColor(id palette, SEL selector) {
    return BHTThemedColorGetter(
        palette, selector, &kBHTPaletteActionColorKey,
        UIColor.systemBlueColor);
}

static IMP BHTOriginalPrimaryColorIMP(id palette) {
    for (Class cls = object_getClass(palette); cls;
         cls = class_getSuperclass(cls)) {
        NSValue* value = objc_getAssociatedObject(
            cls, &kBHTPaletteOriginalPrimaryColorIMPKey);
        if (value.pointerValue) return (IMP)value.pointerValue;
    }
    return NULL;
}

static UIColor* BHTThemedPrimaryColorForOption(id palette, SEL selector,
                                               NSUInteger option) {
    Class cls = object_getClass(palette);
    UIColor* accent =
        objc_getAssociatedObject(cls, &kBHTPaletteAccentColorKey);
    NSNumber* accentOption =
        objc_getAssociatedObject(cls, &kBHTPaletteAccentOptionKey);
    if (accent && option == accentOption.unsignedIntegerValue) {
        return accent;
    }

    IMP original = BHTOriginalPrimaryColorIMP(palette);
    if (original) {
        return ((BHTPrimaryColorForOptionIMP)original)(palette, selector,
                                                       option);
    }
    return UIColor.systemBlueColor;
}

static void BHTInstallColorGetter(Class cls, NSString* selectorName,
                                  IMP replacement) {
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(cls, selector);
    if (!BHTColorGetterMethodIsCompatible(method)) return;

    @synchronized(cls) {
        NSDictionary<NSString*, NSNumber*>* installed =
            objc_getAssociatedObject(
                cls, &kBHTPaletteInstalledColorGettersKey);
        if ([installed[selectorName] boolValue]) return;

        IMP current = method_getImplementation(method);
        if (current != replacement) {
            NSMutableDictionary<NSString*, NSValue*>* originals =
                [objc_getAssociatedObject(
                    cls, &kBHTPaletteOriginalColorGetterIMPsKey)
                    mutableCopy] ?:
                [NSMutableDictionary dictionary];
            originals[selectorName] =
                [NSValue valueWithPointer:(const void*)current];
            objc_setAssociatedObject(
                cls, &kBHTPaletteOriginalColorGetterIMPsKey,
                [originals copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            // Keep the override on the concrete active palette. Adding an
            // inherited getter avoids affecting sibling light/dark palettes.
            if (!class_addMethod(cls, selector, replacement,
                                 method_getTypeEncoding(method))) {
                Method ownedMethod =
                    class_getInstanceMethod(cls, selector);
                IMP ownedCurrent =
                    ownedMethod ? method_getImplementation(ownedMethod) : NULL;
                if (ownedCurrent && ownedCurrent != replacement) {
                    method_setImplementation(ownedMethod, replacement);
                }
            }
        }

        NSMutableDictionary<NSString*, NSNumber*>* updatedInstalled =
            [installed mutableCopy] ?:
            [NSMutableDictionary dictionary];
        updatedInstalled[selectorName] = @YES;
        objc_setAssociatedObject(
            cls, &kBHTPaletteInstalledColorGettersKey,
            [updatedInstalled copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void BHTInstallColorGetterGroup(Class cls,
                                       NSArray<NSString*>* selectorNames,
                                       IMP replacement) {
    for (NSString* selectorName in selectorNames) {
        BHTInstallColorGetter(cls, selectorName, replacement);
    }
}

static void BHTConfigureFullThemeForPalette(
    id palette, BOOL darkAppearance) {
    NSDictionary<NSString*, UIColor*>* colors =
        [Palette
            customThemeColorsForDarkAppearance:darkAppearance];
    objc_setAssociatedObject(
        palette, &kBHTPaletteBackgroundColorKey,
        colors[BHTThemeColorBackgroundKey], OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(
        palette, &kBHTPaletteSurfaceColorKey,
        colors[BHTThemeColorSurfaceKey], OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(
        palette, &kBHTPaletteElevatedSurfaceColorKey,
        colors[BHTThemeColorElevatedSurfaceKey],
        OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(
        palette, &kBHTPaletteTextColorKey,
        colors[BHTThemeColorTextKey], OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(
        palette, &kBHTPaletteSecondaryTextColorKey,
        colors[BHTThemeColorSecondaryTextKey],
        OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(
        palette, &kBHTPaletteSeparatorColorKey,
        colors[BHTThemeColorSeparatorKey], OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(
        palette, &kBHTPaletteActionColorKey,
        colors[BHTThemeColorAccentKey], OBJC_ASSOCIATION_RETAIN);

    // Native X and accent-only custom swatches never install these hooks.
    // If a full preset was previously active, the already-installed getters
    // simply fall through to their preserved original IMPs after colors clear.
    if (colors.count == 0) return;

    Class cls = object_getClass(palette);
    BHTInstallColorGetterGroup(
        cls,
        @[
            @"backgroundColor",
            @"articlesFloatingBarBackgroundColor",
            @"darkBackgroundColor",
            @"defaultBackgroundColor",
            @"messagingBackgroundColor",
            @"rowBackgroundColor",
            @"statusBackgroundColor",
            @"systemBackgroundColor",
            @"systemGroupedBackgroundColor",
            @"tileBackgroundColor",
            @"uiPickerBackgroundColor",
            @"xds_backgroundPrimary"
        ],
        (IMP)BHTThemedBackgroundColor);
    BHTInstallColorGetterGroup(
        cls,
        @[
            @"alternateBackgroundColor",
            @"bottomSegmentBackgroundColor",
            @"cardBackgroundColor",
            @"secondaryBackgroundColor",
            @"faintBackgroundColor",
            @"cardDetailsBackgroundColor",
            @"cardHeaderBackgroundColor",
            @"communityDefaultBackgroundColor",
            @"compositionBackgroundColor",
            @"composeInlineReplyBackgroundColor",
            @"highlightBackgroundColor",
            @"highlightedStatusBackgroundColor",
            @"infoBackgroundColor",
            @"pillDefaultBackgroundColor",
            @"shareMenuActionBackgroundColor",
            @"sharePromptBackgroundColor",
            @"toastsBackgroundColor",
            @"voiceTabCellBackgroundColor",
            @"dmTweetAttachmentBackgroundColor",
            @"xds_backgroundSecondary"
        ],
        (IMP)BHTThemedSurfaceColor);
    BHTInstallColorGetterGroup(
        cls,
        @[
            @"capsuleTabsSelectedBackgroundColor",
            @"chatReactionSelectedBackgroundColor",
            @"dmInboxCellSelectionBackgroundColor",
            @"elevatedBackgroundColor",
            @"modalSheetBackgroundColor",
            @"tabCustomizationInactiveGridCellContainerBackgroundColor",
            @"unreadBackgroundColor",
            @"capsuleTabsOnMediaSelectedBackgroundColor",
            @"xds_backgroundSheets"
        ],
        (IMP)BHTThemedElevatedSurfaceColor);
    BHTInstallColorGetterGroup(
        cls,
        @[
            @"capsuleTabsTextColor",
            @"capsuleTabsOnMediaTextColor",
            @"textColor",
            @"baseTextColor",
            @"defaultTextColor",
            @"textDefaultColor",
            @"pillControlTextColor",
            @"boldTextColor"
        ],
        (IMP)BHTThemedTextColor);
    BHTInstallColorGetterGroup(
        cls,
        @[
            @"detailTextColor",
            @"textDetailsColor",
            @"placeholderTextColor",
            @"promptSeparatorTextColor",
            @"tabBarItemColor",
            @"integralTweetActionColor"
        ],
        (IMP)BHTThemedSecondaryTextColor);
    BHTInstallColorGetterGroup(
        cls,
        @[
            @"capsuleTabsBorderColor",
            @"darkBackgroundDividerColor",
            @"drawerBackgroundBorderColor",
            @"elevatedBackgroundShadowColor",
            @"navigationBarHandleColor",
            @"navigationBarItemShadowColor",
            @"navigationBarShadowColor",
            @"separatorColor",
            @"promptSeparatorColor",
            @"voiceTabCellShadowColor",
            @"capsuleTabsOnMediaBorderColor",
            @"dividerColor",
            @"groupedDividerColor"
        ],
        (IMP)BHTThemedSeparatorColor);
    BHTInstallColorGetterGroup(
        cls,
        @[
            @"retweetButtonColor",
            @"retweetButtonOverDarkBackgroundColor",
            @"navigationBarLogoColor",
            @"highlightBarColor"
        ],
        (IMP)BHTThemedActionColor);
}

static id BHTPaletteFromSettingInfo(id info) {
    SEL selector = @selector(colorPalette);
    if (!info || ![info respondsToSelector:selector]) return nil;
    Method method =
        class_getInstanceMethod(object_getClass(info), selector);
    if (!BHTColorGetterMethodIsCompatible(method)) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(info, selector);
}

static BOOL BHTSettingInfoUsesDarkAppearance(id info) {
    SEL selector = @selector(isDark);
    if (!info || ![info respondsToSelector:selector]) {
        return UITraitCollection.currentTraitCollection
                   .userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    Method method =
        class_getInstanceMethod(object_getClass(info), selector);
    if (!method || method_getNumberOfArguments(method) != 2) {
        return UITraitCollection.currentTraitCollection
                   .userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    char rawReturnType[16] = {0};
    method_getReturnType(
        method, rawReturnType, sizeof(rawReturnType));
    const char* returnType =
        BHTUnqualifiedThemeType(rawReturnType);
    if (!returnType ||
        strchr("BcC", returnType[0]) == NULL) {
        return UITraitCollection.currentTraitCollection
                   .userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return ((BOOL (*)(id, SEL))objc_msgSend)(info, selector);
}

static BOOL BHTInstallThemeHookForPalette(id palette,
                                          BOOL darkAppearance) {
    if (!palette) return NO;
    uint64_t generation =
        BHTCurrentThemeConfigurationGeneration();
    NSNumber* configuredGeneration =
        objc_getAssociatedObject(
            palette, &kBHTPaletteConfigurationGenerationKey);
    NSNumber* configuredDarkAppearance =
        objc_getAssociatedObject(
            palette,
            &kBHTPaletteConfigurationDarkAppearanceKey);
    if (configuredGeneration.unsignedLongLongValue == generation &&
        configuredDarkAppearance &&
        configuredDarkAppearance.boolValue == darkAppearance) {
        return NO;
    }

    @synchronized(palette) {
        // Re-read after acquiring the per-instance lock. A theme notification
        // or another currentColorPalette caller may have completed the work
        // while this thread was waiting.
        generation = BHTCurrentThemeConfigurationGeneration();
        configuredGeneration = objc_getAssociatedObject(
            palette, &kBHTPaletteConfigurationGenerationKey);
        configuredDarkAppearance = objc_getAssociatedObject(
            palette,
            &kBHTPaletteConfigurationDarkAppearanceKey);
        if (configuredGeneration.unsignedLongLongValue == generation &&
            configuredDarkAppearance &&
            configuredDarkAppearance.boolValue == darkAppearance) {
            return NO;
        }

        BHTTrackSeenThemePalette(palette);
        Class cls = object_getClass(palette);
        BHTConfigureFullThemeForPalette(palette, darkAppearance);

        SEL selector = @selector(primaryColorForOption:);
        Method method = class_getInstanceMethod(cls, selector);
        if (BHTPrimaryColorMethodIsCompatible(method)) {
            UIColor* accent = [Palette customAccentColor];
            id storedOption = [NSUserDefaults.standardUserDefaults
                objectForKey:@"bh_color_theme_selectedColor"];
            NSInteger option =
                [storedOption isKindOfClass:NSNumber.class]
                    ? [storedOption integerValue]
                    : 1;
            NSNumber* selectedOption =
                @(MIN(6, MAX(1, option)));
            objc_setAssociatedObject(
                cls, &kBHTPaletteAccentColorKey, accent,
                OBJC_ASSOCIATION_RETAIN);
            objc_setAssociatedObject(
                cls, &kBHTPaletteAccentOptionKey,
                selectedOption ?: @1, OBJC_ASSOCIATION_RETAIN);

            @synchronized(cls) {
                BOOL installed =
                    [objc_getAssociatedObject(
                        cls, &kBHTPaletteHookInstalledKey)
                        boolValue];
                if (!installed) {
                    IMP replacement =
                        (IMP)BHTThemedPrimaryColorForOption;
                    IMP current = method_getImplementation(method);
                    if (current != replacement) {
                        objc_setAssociatedObject(
                            cls,
                            &kBHTPaletteOriginalPrimaryColorIMPKey,
                            [NSValue
                                valueWithPointer:
                                    (const void*)current],
                            OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                        // Add an override when the implementation is inherited
                        // so sibling palettes are untouched. If the class owns
                        // it, preserve the current chain before replacement.
                        if (!class_addMethod(
                                cls, selector, replacement,
                                method_getTypeEncoding(method))) {
                            Method ownedMethod =
                                class_getInstanceMethod(cls, selector);
                            IMP ownedCurrent =
                                ownedMethod
                                    ? method_getImplementation(
                                          ownedMethod)
                                    : NULL;
                            if (ownedCurrent &&
                                ownedCurrent != replacement) {
                                objc_setAssociatedObject(
                                    cls,
                                    &kBHTPaletteOriginalPrimaryColorIMPKey,
                                    [NSValue
                                        valueWithPointer:
                                            (const void*)ownedCurrent],
                                    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                                method_setImplementation(
                                    ownedMethod, replacement);
                            }
                        }
                    }
                    objc_setAssociatedObject(
                        cls, &kBHTPaletteHookInstalledKey, @YES,
                        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
        }

        // Publish the dark marker before the generation marker. Readers treat
        // the generation as the commit point for this configuration.
        objc_setAssociatedObject(
            palette, &kBHTPaletteConfigurationDarkAppearanceKey,
            @(darkAppearance), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            palette, &kBHTPaletteConfigurationGenerationKey,
            @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return YES;
}

static id BHTThemeProviderFromUIColorSelector(SEL selector) {
    Class colorClass = UIColor.class;
    if (!selector || ![colorClass respondsToSelector:selector]) {
        return nil;
    }
    Method method = class_getClassMethod(colorClass, selector);
    if (!BHTColorGetterMethodIsCompatible(method)) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(colorClass, selector);
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

static BOOL BHTInstallThemeHooksForProviders(
    id activePalette, BOOL darkAppearance) {
    NSMutableArray* providers = [NSMutableArray array];
    if (activePalette) [providers addObject:activePalette];
    for (NSString* selectorName in @[
             @"twitterColors", @"tfnuiColors"
         ]) {
        id provider = BHTThemeProviderFromUIColorSelector(
            NSSelectorFromString(selectorName));
        if (!provider) continue;
        BOOL alreadyPresent = NO;
        for (id existing in providers) {
            if (existing == provider) {
                alreadyPresent = YES;
                break;
            }
        }
        if (!alreadyPresent) [providers addObject:provider];
    }

    NSMutableArray<NSString*>* providerClasses =
        [NSMutableArray arrayWithCapacity:providers.count];
    BOOL configuredProvider = NO;
    for (id provider in providers) {
        configuredProvider |=
            BHTInstallThemeHookForPalette(
                provider, darkAppearance);
        NSString* className =
            NSStringFromClass(object_getClass(provider));
        if (className.length > 0 &&
            ![providerClasses containsObject:className]) {
            [providerClasses addObject:className];
        }
    }
    BHTLastThemeProviderClasses =
        [[providerClasses
            sortedArrayUsingSelector:@selector(compare:)] copy];
    return configuredProvider;
}

static void BHTReconfigureSeenThemePalettes(void) {
    for (id palette in BHTSeenThemePaletteSnapshot()) {
        NSNumber* darkMarker =
            objc_getAssociatedObject(
                palette,
                &kBHTPaletteConfigurationDarkAppearanceKey);
        BHTInstallThemeHookForPalette(
            palette, darkMarker.boolValue);
    }
}

static void BHTRefreshActiveThemePalette(
    BOOL reapplyColor, BOOL forceProviderRedraw) {
    Class settingsClass = objc_getClass("TAEColorSettings");
    SEL sharedSelector = @selector(sharedSettings);
    SEL paletteSelector = @selector(currentColorPalette);
    if (!settingsClass ||
        ![settingsClass respondsToSelector:sharedSelector]) {
        return;
    }

    id settings =
        ((id (*)(id, SEL))objc_msgSend)(settingsClass, sharedSelector);
    if (!settings || ![settings respondsToSelector:paletteSelector]) return;
    id info =
        ((id (*)(id, SEL))objc_msgSend)(settings, paletteSelector);
    id palette = BHTPaletteFromSettingInfo(info);
    BOOL darkAppearance =
        BHTSettingInfoUsesDarkAppearance(info);
    BOOL configuredProvider =
        BHTInstallThemeHooksForProviders(
            palette, darkAppearance);

    if (!reapplyColor) {
        // Never invoke X's apply methods from a native reload/foreground
        // callback. If a provider was swapped while inactive, or X's
        // synchronous reload observers resolved it before our associations
        // were attached, one bounded redraw is needed after attachment.
        BHTRecordCurrentThemeRuntime(palette, darkAppearance);
        BOOL customThemeActive =
            [BHTThemePresets activePresetIdentifier].length > 0;
        if (customThemeActive &&
            (forceProviderRedraw || configuredProvider)) {
            NSUInteger refreshGeneration =
                ++BHTThemeRefreshGeneration;
            BHTLastVisibleViewsVisited = 0;
            BHTLastDynamicColorViewsUpdated = 0;
            BHTScheduleVisibleDynamicColorRefresh(
                refreshGeneration, palette, darkAppearance,
                YES);
        }
        return;
    }

    Class colorSettingsClass = objc_getClass("T1ColorSettings");
    if (reapplyColor) {
        BHTThemeRefreshAttempts++;
        NSUInteger refreshGeneration =
            ++BHTThemeRefreshGeneration;
        BHTLastVisibleViewsVisited = 0;
        BHTLastDynamicColorViewsUpdated = 0;
        BHTResetDynamicColorsReloadObservation();
        __atomic_store_n(
            &BHTPostReloadProviderRedrawNeeded, 0,
            __ATOMIC_RELEASE);
        BHTLastDiagnosticPalette = palette;
        BHTLastDiagnosticDarkAppearance = darkAppearance;

        BOOL appliedCurrentPalette =
            BHTInvokeGuardedVoidGetter(
                settings,
                NSSelectorFromString(@"applyCurrentColorPalette"));

        // applyCurrentColorPalette can replace the setting-info/palette
        // objects. Attach the role colors to the new live object before the
        // did-reload notification asks observers to resolve their colors.
        info = ((id (*)(id, SEL))objc_msgSend)(
            settings, paletteSelector);
        BOOL configuredAfterNativeApply =
            BHTInstallThemeHooksForProviders(
                BHTPaletteFromSettingInfo(info),
                BHTSettingInfoUsesDarkAppearance(info));
        if (configuredAfterNativeApply &&
            BHTDidObserveDynamicColorsReload()) {
            __atomic_store_n(
                &BHTPostReloadProviderRedrawNeeded, 1,
                __ATOMIC_RELEASE);
        }

        BOOL appliedFullTheme = NO;
        NSMutableArray<NSString*>* usedT1Selectors =
            [NSMutableArray array];
        NSArray<NSString*>* applySelectors = @[
            @"_t1_applyTheme",
            @"_t1_applyPrimaryColorOption",
            @"_t1_updateOverrideUserInterfaceStyle"
        ];
        for (NSString* selectorName in applySelectors) {
            SEL selector = NSSelectorFromString(selectorName);
            Method method =
                class_getClassMethod(colorSettingsClass, selector);
            if (![colorSettingsClass respondsToSelector:selector] ||
                !method || method_getNumberOfArguments(method) != 2) {
                continue;
            }
            char returnType[16] = {0};
            method_getReturnType(method, returnType,
                                 sizeof(returnType));
            const char* unqualifiedReturn =
                BHTUnqualifiedThemeType(returnType);
            if (!unqualifiedReturn ||
                unqualifiedReturn[0] != 'v') {
                continue;
            }
            @try {
                ((void (*)(id, SEL))objc_msgSend)(
                    colorSettingsClass, selector);
                [usedT1Selectors addObject:selectorName];
            } @catch (__unused NSException* exception) {
                continue;
            }
            if ([selectorName isEqualToString:@"_t1_applyTheme"]) {
                appliedFullTheme = YES;
            }
        }

        BOOL paletteSetterFallbackUsed = NO;
        if (!appliedFullTheme && !appliedCurrentPalette && info) {
            // Some compatible builds expose the palette setter but not the
            // dedicated class-level refresh. Reassigning the already-active
            // palette takes X's own guarded update path and refreshes visible
            // colors without walking or globally recoloring every UIView.
            SEL setter =
                @selector(setCurrentColorPalette:);
            Method setterMethod =
                class_getInstanceMethod(object_getClass(settings),
                                        setter);
            if ([settings respondsToSelector:setter] &&
                BHTVoidObjectSetterIsCompatible(setterMethod)) {
                @try {
                    ((void (*)(id, SEL, id))objc_msgSend)(
                        settings, setter, info);
                    paletteSetterFallbackUsed = YES;
                } @catch (__unused NSException* exception) {
                }
            }
        }

        // Re-read once more because either native apply path may swap the
        // concrete light/dark palette. This also makes Native Blue restoration
        // fall through to every preserved original getter before redraw.
        info = ((id (*)(id, SEL))objc_msgSend)(
            settings, paletteSelector);
        palette = BHTPaletteFromSettingInfo(info);
        darkAppearance =
            BHTSettingInfoUsesDarkAppearance(info);
        BOOL configuredAfterFinalNativeApply =
            BHTInstallThemeHooksForProviders(
                palette, darkAppearance);
        if (configuredAfterFinalNativeApply &&
            BHTDidObserveDynamicColorsReload()) {
            __atomic_store_n(
                &BHTPostReloadProviderRedrawNeeded, 1,
                __ATOMIC_RELEASE);
        }
        BHTLastDiagnosticPalette = palette;
        BHTLastDiagnosticDarkAppearance = darkAppearance;
        BHTLastApplyCurrentPaletteUsed =
            appliedCurrentPalette;
        BHTLastPaletteSetterFallbackUsed =
            paletteSetterFallbackUsed;
        BHTLastT1RefreshSelectorsUsed =
            [usedT1Selectors copy];
        // Never synthesize TFN's private reload notification. Its native
        // producer owns the object/userInfo contract. The scheduled bounded
        // view update normally defers to that signal; the notification
        // observer schedules one forced pass only if providers were attached
        // after synchronous observers had already run.
        BHTRecordCurrentThemeRuntime(palette, darkAppearance);
        BHTScheduleVisibleDynamicColorRefresh(
            refreshGeneration, palette, darkAppearance, NO);
    }
}

%hook TAEColorSettings

- (TAETwitterColorPaletteSettingInfo*)currentColorPalette {
    TAETwitterColorPaletteSettingInfo* info = %orig;
    BHTInstallThemeHookForPalette(
        BHTPaletteFromSettingInfo(info),
        BHTSettingInfoUsesDarkAppearance(info));
    return info;
}

- (void)setCurrentColorPalette:(TAETwitterColorPaletteSettingInfo*)info {
    uint64_t reloadSequenceBefore = __atomic_load_n(
        &BHTDynamicColorsReloadSequence, __ATOMIC_ACQUIRE);
    %orig(info);
    BOOL configuredProvider =
        BHTInstallThemeHooksForProviders(
            BHTPaletteFromSettingInfo(info),
            BHTSettingInfoUsesDarkAppearance(info));
    uint64_t reloadSequenceAfter = __atomic_load_n(
        &BHTDynamicColorsReloadSequence, __ATOMIC_ACQUIRE);
    if (configuredProvider &&
        reloadSequenceAfter != reloadSequenceBefore) {
        __atomic_store_n(
            &BHTPostReloadProviderRedrawNeeded, 1,
            __ATOMIC_RELEASE);
        BHTScheduleProviderAttachRefresh();
    }
}

%end

%ctor {
    @autoreleasepool {
        %init;
        dispatch_async(dispatch_get_main_queue(), ^{
            BHTInstallDynamicColorDiagnosticObserver();
            NSNotificationCenter* center =
                NSNotificationCenter.defaultCenter;
            NSArray<NSString*>* fullRefreshNames = @[
                BHTThemeDidChangeNotification,
                BHTSettingsProfileDidApplyNotification
            ];
            for (NSString* name in fullRefreshNames) {
                [center
                    addObserverForName:name
                                object:nil
                                 queue:NSOperationQueue.mainQueue
                            usingBlock:^(__unused NSNotification* note) {
                                // Profile import changes UserDefaults before
                                // posting. Invalidate first so observer ordering
                                // can never reinstall the previous cached color.
                                [Palette invalidateCustomAccentColorCache];
                                BHTAdvanceThemeConfigurationGeneration();
                                // Update every still-live palette, not only
                                // the currently selected one. This clears old
                                // associated role colors immediately when
                                // returning to Native Blue.
                                BHTReconfigureSeenThemePalettes();
                                BHTRefreshActiveThemePalette(YES, NO);
                            }];
            }
            [center
                addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification* note) {
                            BHTRefreshActiveThemePalette(NO, NO);
                        }];
            BHTRefreshActiveThemePalette(YES, NO);
        });
    }
}
