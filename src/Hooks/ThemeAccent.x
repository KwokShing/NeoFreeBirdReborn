//
//  ThemeAccent.x
//  NeoFreeBird
//
//  Applies NeoFreeBird's optional custom accent through X's active palette.
//  The concrete palette class changes between light/dark appearances and X
//  releases, so the hook is installed only after validating the live method.
//

#import "HookHelpers.h"
#import "ThemeColor/BHTThemePresets.h"
#include <string.h>

static char kBHTPaletteAccentColorKey;
static char kBHTPaletteAccentOptionKey;
static char kBHTPaletteHookInstalledKey;
static char kBHTPaletteOriginalPrimaryColorIMPKey;

typedef UIColor* (*BHTPrimaryColorForOptionIMP)(id, SEL, NSUInteger);

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

static id BHTPaletteFromSettingInfo(id info) {
    SEL selector = @selector(colorPalette);
    if (!info || ![info respondsToSelector:selector]) return nil;
    NSMethodSignature* signature = [info methodSignatureForSelector:selector];
    const char* returnType =
        BHTUnqualifiedThemeType(signature.methodReturnType);
    if (!returnType || returnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(info, selector);
}

static void BHTInstallThemeHookForPalette(id palette) {
    if (!palette) return;
    Class cls = object_getClass(palette);
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
    BHTInstallThemeHookForPalette(BHTPaletteFromSettingInfo(info));

    Class colorSettingsClass = objc_getClass("T1ColorSettings");
    SEL applySelector =
        NSSelectorFromString(@"_t1_applyPrimaryColorOption");
    if (reapplyColor &&
        [colorSettingsClass respondsToSelector:applySelector]) {
        ((void (*)(id, SEL))objc_msgSend)(colorSettingsClass, applySelector);
    }
}

%hook TAEColorSettings

- (TAETwitterColorPaletteSettingInfo*)currentColorPalette {
    TAETwitterColorPaletteSettingInfo* info = %orig;
    BHTInstallThemeHookForPalette(BHTPaletteFromSettingInfo(info));
    return info;
}

- (void)setCurrentColorPalette:(TAETwitterColorPaletteSettingInfo*)info {
    %orig(info);
    BHTInstallThemeHookForPalette(BHTPaletteFromSettingInfo(info));
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
