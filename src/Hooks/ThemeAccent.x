//
//  ThemeAccent.x
//  NeoFreeBird
//
//  Applies NeoFreeBird's optional accent and full theme presets through X's
//  active palette. The concrete palette class changes between light/dark
//  appearances and X releases, so every hook validates the live method first.
//

#import "HookHelpers.h"
#import "ThemeColor/BHTThemePresets.h"
#include <string.h>

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

    // Native X and accent-only custom swatches never install these hooks.
    // If a full preset was previously active, the already-installed getters
    // simply fall through to their preserved original IMPs after colors clear.
    if (colors.count == 0) return;

    Class cls = object_getClass(palette);
    BHTInstallColorGetterGroup(
        cls,
        @[
            @"backgroundColor",
            @"defaultBackgroundColor",
            @"rowBackgroundColor",
            @"statusBackgroundColor"
        ],
        (IMP)BHTThemedBackgroundColor);
    BHTInstallColorGetterGroup(
        cls,
        @[
            @"alternateBackgroundColor",
            @"secondaryBackgroundColor",
            @"faintBackgroundColor",
            @"cardBackgroundColor",
            @"cardDetailsBackgroundColor",
            @"cardHeaderBackgroundColor",
            @"compositionBackgroundColor",
            @"composeInlineReplyBackgroundColor"
        ],
        (IMP)BHTThemedSurfaceColor);
    BHTInstallColorGetterGroup(
        cls, @[@"elevatedBackgroundColor"],
        (IMP)BHTThemedElevatedSurfaceColor);
    BHTInstallColorGetterGroup(
        cls,
        @[
            @"textColor",
            @"baseTextColor",
            @"defaultTextColor",
            @"boldTextColor"
        ],
        (IMP)BHTThemedTextColor);
    BHTInstallColorGetterGroup(
        cls,
        @[
            @"detailTextColor",
            @"placeholderTextColor",
            @"tabBarItemColor"
        ],
        (IMP)BHTThemedSecondaryTextColor);
    BHTInstallColorGetterGroup(
        cls,
        @[
            @"navigationBarShadowColor",
            @"separatorColor",
            @"promptSeparatorColor"
        ],
        (IMP)BHTThemedSeparatorColor);
}

static id BHTPaletteFromSettingInfo(id info) {
    SEL selector = @selector(colorPalette);
    if (!info || ![info respondsToSelector:selector]) return nil;
    NSMethodSignature* signature = [info methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2) return nil;
    const char* returnType =
        BHTUnqualifiedThemeType(signature.methodReturnType);
    if (!returnType || returnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(info, selector);
}

static BOOL BHTSettingInfoUsesDarkAppearance(id info) {
    SEL selector = @selector(isDark);
    if (!info || ![info respondsToSelector:selector]) {
        return UITraitCollection.currentTraitCollection
                   .userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    NSMethodSignature* signature =
        [info methodSignatureForSelector:selector];
    const char* returnType =
        BHTUnqualifiedThemeType(signature.methodReturnType);
    if (signature.numberOfArguments != 2 || !returnType ||
        strchr("BcC", returnType[0]) == NULL) {
        return UITraitCollection.currentTraitCollection
                   .userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return ((BOOL (*)(id, SEL))objc_msgSend)(info, selector);
}

static void BHTInstallThemeHookForPalette(id palette,
                                          BOOL darkAppearance) {
    if (!palette) return;
    Class cls = object_getClass(palette);
    BHTConfigureFullThemeForPalette(palette, darkAppearance);

    SEL selector = @selector(primaryColorForOption:);
    Method method = class_getInstanceMethod(cls, selector);
    if (!BHTPrimaryColorMethodIsCompatible(method)) return;

    UIColor* accent = [Palette customAccentColor];
    id storedOption = [NSUserDefaults.standardUserDefaults
        objectForKey:@"bh_color_theme_selectedColor"];
    NSInteger option =
        [storedOption isKindOfClass:NSNumber.class]
            ? [storedOption integerValue]
            : 1;
    NSNumber* selectedOption = @(MIN(6, MAX(1, option)));
    objc_setAssociatedObject(cls, &kBHTPaletteAccentColorKey, accent,
                             OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(cls, &kBHTPaletteAccentOptionKey,
                             selectedOption ?: @1,
                             OBJC_ASSOCIATION_RETAIN);

    @synchronized(cls) {
        if ([objc_getAssociatedObject(cls, &kBHTPaletteHookInstalledKey)
                boolValue]) {
            return;
        }

        IMP replacement = (IMP)BHTThemedPrimaryColorForOption;
        IMP current = method_getImplementation(method);
        if (current != replacement) {
            objc_setAssociatedObject(
                cls, &kBHTPaletteOriginalPrimaryColorIMPKey,
                [NSValue valueWithPointer:(const void*)current],
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            // Add an override when the implementation is inherited so sibling
            // palettes are untouched. If the class owns the method, replace
            // only that validated implementation and preserve the current
            // chain (including any earlier tweak).
            if (!class_addMethod(cls, selector, replacement,
                                 method_getTypeEncoding(method))) {
                Method ownedMethod =
                    class_getInstanceMethod(cls, selector);
                IMP ownedCurrent =
                    ownedMethod ? method_getImplementation(ownedMethod) : NULL;
                if (ownedCurrent && ownedCurrent != replacement) {
                    objc_setAssociatedObject(
                        cls, &kBHTPaletteOriginalPrimaryColorIMPKey,
                        [NSValue valueWithPointer:(const void*)ownedCurrent],
                        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    method_setImplementation(ownedMethod, replacement);
                }
            }
        }
        objc_setAssociatedObject(cls, &kBHTPaletteHookInstalledKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void BHTRefreshActiveThemePalette(BOOL reapplyColor) {
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
    BHTInstallThemeHookForPalette(
        BHTPaletteFromSettingInfo(info),
        BHTSettingInfoUsesDarkAppearance(info));

    Class colorSettingsClass = objc_getClass("T1ColorSettings");
    if (reapplyColor) {
        BOOL appliedFullTheme = NO;
        NSArray<NSString*>* applySelectors = @[
            @"_t1_applyTheme",
            @"_t1_applyPrimaryColorOption"
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
            ((void (*)(id, SEL))objc_msgSend)(colorSettingsClass,
                                              selector);
            if ([selectorName isEqualToString:@"_t1_applyTheme"]) {
                appliedFullTheme = YES;
            }
        }

        if (!appliedFullTheme && info) {
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
                ((void (*)(id, SEL, id))objc_msgSend)(
                    settings, setter, info);
            }
        }
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
    %orig(info);
    BHTInstallThemeHookForPalette(
        BHTPaletteFromSettingInfo(info),
        BHTSettingInfoUsesDarkAppearance(info));
}

%end

%ctor {
    @autoreleasepool {
        %init;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSNotificationCenter* center =
                NSNotificationCenter.defaultCenter;
            NSArray<NSString*>* names = @[
                BHTThemeDidChangeNotification,
                BHTSettingsProfileDidApplyNotification,
                UIApplicationDidBecomeActiveNotification
            ];
            for (NSString* name in names) {
                [center
                    addObserverForName:name
                                object:nil
                                 queue:NSOperationQueue.mainQueue
                            usingBlock:^(__unused NSNotification* note) {
                                // Profile import changes UserDefaults before
                                // posting. Invalidate first so observer ordering
                                // can never reinstall the previous cached color.
                                [Palette invalidateCustomAccentColorCache];
                                BHTRefreshActiveThemePalette(YES);
                            }];
            }
            BHTRefreshActiveThemePalette(YES);
        });
    }
}
