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

static char kBHTPaletteAccentStateKey;
static char kBHTXDSRoleSnapshotKey;
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
static char kBHTPaletteRoleStateKey;
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
static volatile uint64_t BHTThemeConfigurationToken = 4;
static const uint64_t BHTThemeDarkAppearanceBit = 1;
static const uint64_t BHTThemeAppearanceKnownBit = 2;
static const uint64_t BHTThemeGenerationIncrement = 4;
static __weak id BHTLastDiagnosticPalette;
static BOOL BHTLastDiagnosticDarkAppearance;
static NSArray<NSString*>* BHTLastThemeProviderClasses;

typedef UIColor* (*BHTPrimaryColorForOptionIMP)(id, SEL, NSUInteger);
typedef UIColor* (*BHTColorGetterIMP)(id, SEL);

@interface BHTThemeRoleState : NSObject {
@public
    uint64_t _configurationToken;
    UIColor* _backgroundColor;
    UIColor* _surfaceColor;
    UIColor* _elevatedSurfaceColor;
    UIColor* _textColor;
    UIColor* _secondaryTextColor;
    UIColor* _separatorColor;
    UIColor* _actionColor;
}
- (instancetype)initWithColors:(NSDictionary<NSString*, UIColor*>*)colors
            configurationToken:(uint64_t)configurationToken;
@end

@implementation BHTThemeRoleState

- (instancetype)initWithColors:(NSDictionary<NSString*, UIColor*>*)colors
            configurationToken:(uint64_t)configurationToken {
    if ((self = [super init])) {
        _configurationToken = configurationToken;
        _backgroundColor = colors[BHTThemeColorBackgroundKey];
        _surfaceColor = colors[BHTThemeColorSurfaceKey];
        _elevatedSurfaceColor =
            colors[BHTThemeColorElevatedSurfaceKey];
        _textColor = colors[BHTThemeColorTextKey];
        _secondaryTextColor =
            colors[BHTThemeColorSecondaryTextKey];
        _separatorColor = colors[BHTThemeColorSeparatorKey];
        _actionColor = colors[BHTThemeColorAccentKey];
    }
    return self;
}

@end

static inline UIColor* BHTColorFromRoleState(
    BHTThemeRoleState* state, uint64_t configurationToken,
    const void* roleKey) {
    if (!state ||
        state->_configurationToken != configurationToken) {
        return nil;
    }
    if (roleKey == &kBHTPaletteBackgroundColorKey) {
        return state->_backgroundColor;
    }
    if (roleKey == &kBHTPaletteSurfaceColorKey) {
        return state->_surfaceColor;
    }
    if (roleKey == &kBHTPaletteElevatedSurfaceColorKey) {
        return state->_elevatedSurfaceColor;
    }
    if (roleKey == &kBHTPaletteTextColorKey) {
        return state->_textColor;
    }
    if (roleKey == &kBHTPaletteSecondaryTextColorKey) {
        return state->_secondaryTextColor;
    }
    if (roleKey == &kBHTPaletteSeparatorColorKey) {
        return state->_separatorColor;
    }
    if (roleKey == &kBHTPaletteActionColorKey) {
        return state->_actionColor;
    }
    return nil;
}

@interface BHTThemeAccentState : NSObject {
@public
    uint64_t _configurationToken;
    UIColor* _accentColor;
    NSUInteger _accentOption;
}
- (instancetype)initWithConfigurationToken:(uint64_t)configurationToken
                                accentColor:(UIColor*)accentColor
                               accentOption:(NSUInteger)accentOption;
@end

@implementation BHTThemeAccentState

- (instancetype)initWithConfigurationToken:(uint64_t)configurationToken
                                accentColor:(UIColor*)accentColor
                               accentOption:(NSUInteger)accentOption {
    if ((self = [super init])) {
        _configurationToken = configurationToken;
        _accentColor = accentColor;
        _accentOption = accentOption;
    }
    return self;
}

@end

@interface BHTXDSRoleSnapshot : NSObject {
@public
    uint64_t _generation;
    NSDictionary<NSString*, UIColor*>* _lightColors;
    NSDictionary<NSString*, UIColor*>* _darkColors;
}
- (instancetype)initWithGeneration:(uint64_t)generation
                       lightColors:(NSDictionary<NSString*, UIColor*>*)lightColors
                        darkColors:(NSDictionary<NSString*, UIColor*>*)darkColors;
@end

@implementation BHTXDSRoleSnapshot

- (instancetype)initWithGeneration:(uint64_t)generation
                       lightColors:(NSDictionary<NSString*, UIColor*>*)lightColors
                        darkColors:(NSDictionary<NSString*, UIColor*>*)darkColors {
    if ((self = [super init])) {
        _generation = generation;
        _lightColors = [lightColors copy] ?: @{};
        _darkColors = [darkColors copy] ?: @{};
    }
    return self;
}

@end

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
    // These notification constants are exported by TFNUI in the audited runtime. Resolve
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

static uint64_t BHTRememberThemeAppearance(
    BOOL darkAppearance) {
    uint64_t previousToken = __atomic_load_n(
        &BHTThemeConfigurationToken, __ATOMIC_ACQUIRE);
    while (YES) {
        uint64_t nextToken =
            (previousToken &
             ~(BHTThemeDarkAppearanceBit |
               BHTThemeAppearanceKnownBit)) |
            BHTThemeAppearanceKnownBit |
            (darkAppearance ? BHTThemeDarkAppearanceBit : 0);
        if (__atomic_compare_exchange_n(
                &BHTThemeConfigurationToken, &previousToken,
                nextToken, NO, __ATOMIC_ACQ_REL,
                __ATOMIC_ACQUIRE)) {
            return nextToken;
        }
    }
}

static uint64_t BHTCurrentThemeConfigurationToken(void) {
    uint64_t token = __atomic_load_n(
        &BHTThemeConfigurationToken, __ATOMIC_ACQUIRE);
    if ((token & BHTThemeAppearanceKnownBit) != 0) {
        return token;
    }
    return BHTRememberThemeAppearance(
        [Palette currentPaletteUsesDarkAppearance]);
}

static uint64_t BHTCurrentThemeConfigurationGeneration(void) {
    return BHTCurrentThemeConfigurationToken() /
           BHTThemeGenerationIncrement;
}

static uint64_t BHTAdvanceThemeConfigurationGeneration(void) {
    uint64_t token = __atomic_add_fetch(
        &BHTThemeConfigurationToken,
        BHTThemeGenerationIncrement, __ATOMIC_ACQ_REL);
    return token / BHTThemeGenerationIncrement;
}

static BOOL BHTCurrentKnownThemeAppearance(void) {
    return (BHTCurrentThemeConfigurationToken() &
            BHTThemeDarkAppearanceBit) != 0;
}

static inline BHTThemeRoleState*
BHTThemeRoleStateForOwner(id owner) {
    return owner
        ? (BHTThemeRoleState*)objc_getAssociatedObject(
              owner, &kBHTPaletteRoleStateKey)
        : nil;
}

static BOOL BHTPaletteThemeConfigurationIsComplete(
    id palette, uint64_t configurationToken) {
    if (!palette) return NO;
    BHTThemeRoleState* instanceState =
        BHTThemeRoleStateForOwner(palette);
    if (!instanceState ||
        instanceState->_configurationToken != configurationToken) {
        return NO;
    }

    Class providerClass = object_getClass(palette);
    BHTThemeRoleState* classState =
        BHTThemeRoleStateForOwner(providerClass);
    if (!classState ||
        classState->_configurationToken != configurationToken) {
        return NO;
    }

    Method primaryColorMethod = class_getInstanceMethod(
        providerClass, @selector(primaryColorForOption:));
    if (BHTPrimaryColorMethodIsCompatible(primaryColorMethod)) {
        BHTThemeAccentState* accentState =
            (BHTThemeAccentState*)objc_getAssociatedObject(
                providerClass, &kBHTPaletteAccentStateKey);
        if (!accentState ||
            accentState->_configurationToken != configurationToken) {
            return NO;
        }
    }
    return YES;
}

static BHTXDSRoleSnapshot*
BHTXDSRoleSnapshotForCurrentGeneration(void) {
    uint64_t generation =
        BHTCurrentThemeConfigurationGeneration();
    BHTXDSRoleSnapshot* snapshot =
        (BHTXDSRoleSnapshot*)objc_getAssociatedObject(
            UIColor.class, &kBHTXDSRoleSnapshotKey);
    if (snapshot && snapshot->_generation == generation) {
        return snapshot;
    }

    @synchronized(UIColor.class) {
        generation =
            BHTCurrentThemeConfigurationGeneration();
        snapshot =
            (BHTXDSRoleSnapshot*)objc_getAssociatedObject(
                UIColor.class, &kBHTXDSRoleSnapshotKey);
        if (snapshot &&
            snapshot->_generation == generation) {
            return snapshot;
        }
        snapshot = [[BHTXDSRoleSnapshot alloc]
            initWithGeneration:generation
                   lightColors:
                       [Palette
                           customThemeColorsForDarkAppearance:NO]
                    darkColors:
                        [Palette
                            customThemeColorsForDarkAppearance:YES]];
        objc_setAssociatedObject(
            UIColor.class, &kBHTXDSRoleSnapshotKey,
            snapshot, OBJC_ASSOCIATION_RETAIN);
        return snapshot;
    }
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
    // UIColor owns the guarded twitterColors/tfnuiColors provider wrappers.
    [names addObjectsFromArray:
               BHTInstalledColorGetterNames(UIColor.class)];
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
static BOOL BHTInstallThemeHookForPalette(
    id palette, BOOL darkAppearance);
static void BHTInstallUIColorProviderGetterHooks(void);

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
    uint64_t configurationToken =
        BHTCurrentThemeConfigurationToken();
    BHTThemeRoleState* state =
        BHTThemeRoleStateForOwner(palette);
    if ((!state ||
         state->_configurationToken != configurationToken) &&
        palette && !object_isClass(palette)) {
        // Provider getters are hooked once per concrete class, while X may
        // replace the provider instance during a tab/detail transition. A
        // single immutable class snapshot keeps the replacement themed
        // immediately and cannot expose a mixed role/marker publication.
        state = BHTThemeRoleStateForOwner(
            object_getClass(palette));
    }
    UIColor* color = BHTColorFromRoleState(
        state, configurationToken, colorKey);
    if (color) {
        return color;
    }
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

static NSString* BHTThemeRoleForXDSNamedColor(
    NSString* colorName, NSBundle* bundle) {
    if (![colorName isKindOfClass:NSString.class] ||
        colorName.length == 0 || !bundle) {
        return nil;
    }

    // XDSUIColors is a Swift value type. Its initializer reads these exact
    // assets directly from the Swift-package resource bundle, bypassing both
    // UIColor.twitterColors and the xds_* Objective-C class methods.
    static NSDictionary<NSString*, NSString*>* roles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        roles = @{
            @"backgroundPrimary": BHTThemeColorBackgroundKey,
            @"backgroundSecondary": BHTThemeColorSurfaceKey,
            @"backgroundInputs": BHTThemeColorSurfaceKey,
            @"backgroundTertiary": BHTThemeColorElevatedSurfaceKey,
            @"backgroundSheets": BHTThemeColorElevatedSurfaceKey,
            @"foregroundPrimary": BHTThemeColorTextKey,
            @"foregroundSecondary": BHTThemeColorSecondaryTextKey,
            @"foregroundTertiary": BHTThemeColorSecondaryTextKey,
            @"foregroundTertiarySolid":
                BHTThemeColorSecondaryTextKey,
            @"borderNormal": BHTThemeColorSeparatorKey
        };
    });
    NSString* role = roles[colorName];
    if (!role) return nil;

    if ([bundle.bundleIdentifier
            isEqualToString:@"xcolorengine.XColorEngine.resources"]) {
        return role;
    }

    // Keep a narrowly scoped fallback for damaged/repacked resource bundles
    // whose identifier is missing. It still has to be the exact Swift-package
    // bundle placed directly inside Twitter.app.
    if (bundle.bundleIdentifier.length == 0 &&
        [bundle.bundleURL.lastPathComponent
            isEqualToString:@"XColorEngine_XColorEngine.bundle"]) {
        NSURL* parentURL =
            bundle.bundleURL.URLByDeletingLastPathComponent.standardizedURL;
        NSURL* appURL =
            NSBundle.mainBundle.bundleURL.standardizedURL;
        if ([parentURL isEqual:appURL]) return role;
    }
    return nil;
}

static UIColor* BHTDynamicXDSNamedColor(
    UIColor* nativeColor, NSString* role) {
    if (!nativeColor || role.length == 0) return nativeColor;
    if (@available(iOS 13.0, *)) {
        if (![UIColor
                respondsToSelector:@selector(colorWithDynamicProvider:)]) {
            return nativeColor;
        }
        return [UIColor
            colorWithDynamicProvider:^UIColor*(
                UITraitCollection* traitCollection) {
                UIUserInterfaceStyle style =
                    traitCollection.userInterfaceStyle;
                BOOL darkAppearance =
                    style == UIUserInterfaceStyleDark;
                if (style == UIUserInterfaceStyleUnspecified) {
                    darkAppearance =
                        BHTCurrentKnownThemeAppearance();
                }
                BHTXDSRoleSnapshot* snapshot =
                    BHTXDSRoleSnapshotForCurrentGeneration();
                NSDictionary<NSString*, UIColor*>* colors =
                    !snapshot ? nil
                              : (darkAppearance
                                     ? snapshot->_darkColors
                                     : snapshot->_lightColors);
                UIColor* customColor = colors[role];
                if (customColor) return customColor;

                // The wrapper remains cached inside XDSUIColors. Resolving
                // the captured native asset here makes switching back to
                // Native Blue restore X's original light/dark color without
                // rebuilding the Swift value.
                return [nativeColor
                    resolvedColorWithTraitCollection:
                        traitCollection] ?: nativeColor;
            }];
    }
    return nativeColor;
}

static id BHTThemedUIColorProviderGetter(
    id colorClass, SEL selector) {
    IMP original =
        BHTOriginalColorGetterIMP(colorClass, selector);
    id provider = original
        ? ((id (*)(id, SEL))original)(colorClass, selector)
        : nil;
    if (!provider) return nil;

    uint64_t configurationToken =
        BHTCurrentThemeConfigurationToken();
    if (!BHTPaletteThemeConfigurationIsComplete(
            provider, configurationToken)) {
        BHTInstallThemeHookForPalette(
            provider,
            (configurationToken &
             BHTThemeDarkAppearanceBit) != 0);
    }
    return provider;
}

static void BHTThemedUIColorProviderSetter(
    id colorClass, SEL selector, id provider) {
    if (provider) {
        BHTInstallThemeHookForPalette(
            provider, BHTCurrentKnownThemeAppearance());
    }
    IMP original =
        BHTOriginalColorGetterIMP(colorClass, selector);
    if (original) {
        ((void (*)(id, SEL, id))original)(
            colorClass, selector, provider);
    }
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
    uint64_t configurationToken =
        BHTCurrentThemeConfigurationToken();
    BHTThemeAccentState* state =
        (BHTThemeAccentState*)objc_getAssociatedObject(
            cls, &kBHTPaletteAccentStateKey);
    if (state &&
        state->_configurationToken == configurationToken &&
        state->_accentColor &&
        option == state->_accentOption) {
        return state->_accentColor;
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

static void BHTInstallObjectSetter(
    Class cls, NSString* selectorName, IMP replacement) {
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(cls, selector);
    if (!BHTVoidObjectSetterIsCompatible(method)) return;

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
                [originals copy],
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            if (!class_addMethod(
                    cls, selector, replacement,
                    method_getTypeEncoding(method))) {
                Method ownedMethod =
                    class_getInstanceMethod(cls, selector);
                IMP ownedCurrent = ownedMethod
                    ? method_getImplementation(ownedMethod)
                    : NULL;
                if (ownedCurrent &&
                    ownedCurrent != replacement) {
                    method_setImplementation(
                        ownedMethod, replacement);
                }
            }
        }

        NSMutableDictionary<NSString*, NSNumber*>* updatedInstalled =
            [installed mutableCopy] ?:
            [NSMutableDictionary dictionary];
        updatedInstalled[selectorName] = @YES;
        objc_setAssociatedObject(
            cls, &kBHTPaletteInstalledColorGettersKey,
            [updatedInstalled copy],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void BHTInstallUIColorProviderGetterHooks(void) {
    Class colorMetaClass = object_getClass(UIColor.class);
    if (!colorMetaClass) return;
    // Attach each replacement provider before its first caller can cache
    // native colors. The provider's per-generation marker makes repeated
    // UIColor.twitterColors/tfnuiColors reads a cheap pass-through.
    BHTInstallColorGetterGroup(
        colorMetaClass,
        @[@"twitterColors", @"tfnuiColors"],
        (IMP)BHTThemedUIColorProviderGetter);
    BHTInstallObjectSetter(
        colorMetaClass, @"setTwitterColors:",
        (IMP)BHTThemedUIColorProviderSetter);
}

static BHTThemeRoleState* BHTConfigureFullThemeForPalette(
    id palette, uint64_t configurationToken) {
    BOOL darkAppearance =
        (configurationToken &
         BHTThemeDarkAppearanceBit) != 0;
    NSDictionary<NSString*, UIColor*>* colors =
        [Palette
            customThemeColorsForDarkAppearance:darkAppearance];
    BHTThemeRoleState* state =
        [[BHTThemeRoleState alloc]
            initWithColors:colors
        configurationToken:configurationToken];

    // Native X and accent-only custom swatches never install these hooks.
    // If a full preset was previously active, the already-installed getters
    // simply fall through to their preserved original IMPs after colors clear.
    if (colors.count == 0) return state;

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
            @"uiPickerBackgroundColor"
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
            @"dmTweetAttachmentBackgroundColor"
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
            @"unreadBackgroundColor"
        ],
        (IMP)BHTThemedElevatedSurfaceColor);
    BHTInstallColorGetterGroup(
        cls,
        @[
            @"capsuleTabsTextColor",
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
            @"conversationLineColor",
            @"separatorColor",
            @"promptSeparatorColor",
            @"voiceTabCellShadowColor",
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
            @"highlightBarColor",
            @"textLinkColor"
        ],
        (IMP)BHTThemedActionColor);
    return state;
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
    uint64_t configurationToken =
        BHTRememberThemeAppearance(darkAppearance);
    if (BHTPaletteThemeConfigurationIsComplete(
            palette, configurationToken)) {
        return NO;
    }

    @synchronized(palette) {
        // Re-read after acquiring the per-instance lock. A theme notification
        // or another currentColorPalette caller may have completed the work
        // while this thread was waiting.
        configurationToken =
            BHTRememberThemeAppearance(darkAppearance);
        if (BHTPaletteThemeConfigurationIsComplete(
                palette, configurationToken)) {
            return NO;
        }

        BHTTrackSeenThemePalette(palette);
        Class cls = object_getClass(palette);
        BHTThemeRoleState* roleState =
            BHTConfigureFullThemeForPalette(
                palette, configurationToken);

        SEL selector = @selector(primaryColorForOption:);
        Method method = class_getInstanceMethod(cls, selector);
        BHTThemeAccentState* accentState = nil;
        if (BHTPrimaryColorMethodIsCompatible(method)) {
            // This runs inside currentColorPalette's hook. Reuse the known
            // provider appearance instead of asking that hook for it again.
            UIColor* accent =
                [Palette
                    customAccentColorForDarkAppearance:
                        darkAppearance];
            id storedOption = [NSUserDefaults.standardUserDefaults
                objectForKey:@"bh_color_theme_selectedColor"];
            NSInteger option =
                [storedOption isKindOfClass:NSNumber.class]
                    ? [storedOption integerValue]
                    : 1;
            NSUInteger selectedOption =
                (NSUInteger)MIN(6, MAX(1, option));
            accentState =
                [[BHTThemeAccentState alloc]
                    initWithConfigurationToken:configurationToken
                                   accentColor:accent
                                  accentOption:selectedOption];
        }

        @synchronized(cls) {
            if (BHTPrimaryColorMethodIsCompatible(method)) {
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

            // Publish the class fallback, accent, and instance role state as
            // one versioned transaction. The instance is the final commit
            // marker, so a rapid appearance change can never make a partial
            // install look complete on a later provider read.
            if (BHTCurrentThemeConfigurationToken() ==
                configurationToken) {
                objc_setAssociatedObject(
                    cls, &kBHTPaletteRoleStateKey, roleState,
                    OBJC_ASSOCIATION_RETAIN);
                if (accentState) {
                    objc_setAssociatedObject(
                        cls, &kBHTPaletteAccentStateKey,
                        accentState, OBJC_ASSOCIATION_RETAIN);
                }
                objc_setAssociatedObject(
                    palette, &kBHTPaletteRoleStateKey, roleState,
                    OBJC_ASSOCIATION_RETAIN);
            }
        }
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
    BHTInstallUIColorProviderGetterHooks();
    BOOL configuredProvider = NO;
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
    [providerClasses addObject:@"UIColor (XDS named colors)"];
    BHTLastThemeProviderClasses =
        [[providerClasses
            sortedArrayUsingSelector:@selector(compare:)] copy];
    return configuredProvider;
}

static void BHTReconfigureSeenThemePalettes(void) {
    for (id palette in BHTSeenThemePaletteSnapshot()) {
        BHTThemeRoleState* state =
            BHTThemeRoleStateForOwner(palette);
        BOOL darkAppearance = state
            ? (state->_configurationToken &
               BHTThemeDarkAppearanceBit) != 0
            : BHTCurrentKnownThemeAppearance();
        BHTInstallThemeHookForPalette(
            palette, darkAppearance);
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

%hook UIColor

+ (UIColor*)colorNamed:(NSString*)name
              inBundle:(NSBundle*)bundle
compatibleWithTraitCollection:(UITraitCollection*)traitCollection {
    UIColor* nativeColor = %orig;
    NSString* role =
        BHTThemeRoleForXDSNamedColor(name, bundle);
    return role ? BHTDynamicXDSNamedColor(nativeColor, role)
                : nativeColor;
}

%end

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
        // The exact XDS named-color bridge above is installed by %init.
        // Install provider wrappers synchronously too, before early timeline
        // models can cache an unthemed replacement provider.
        BHTInstallUIColorProviderGetterHooks();
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
                                 // Build the immutable light/dark XDS snapshot
                                 // before visible cells ask cached Swift colors
                                 // to resolve during the ensuing repaint.
                                 BHTXDSRoleSnapshotForCurrentGeneration();
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
