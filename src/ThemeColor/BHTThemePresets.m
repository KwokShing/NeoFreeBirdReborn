#import "ThemeColor/BHTThemePresets.h"

#import "Core/BHTBundle.h"
#import "Headers/TWHeaders.h"
#import "ThemeColor/Palette.h"

NSString* const BHTThemeDidChangeNotification =
    @"BHTThemeDidChangeNotification";
NSString* const BHTThemeLibraryDidChangeNotification =
    @"BHTThemeLibraryDidChangeNotification";
NSString* const BHTUserThemeLibraryPreferenceKey =
    @"bht_user_theme_library_v1";
NSString* const BHTThemeColorAccentKey = @"accent";
NSString* const BHTThemeColorBackgroundKey = @"background";
NSString* const BHTThemeColorSurfaceKey = @"surface";
NSString* const BHTThemeColorElevatedSurfaceKey = @"elevatedSurface";
NSString* const BHTThemeColorTextKey = @"text";
NSString* const BHTThemeColorSecondaryTextKey = @"secondaryText";
NSString* const BHTThemeColorSeparatorKey = @"separator";

static NSString* const BHTThemeStoreErrorDomain =
    @"com.neofreebird.theme-library";
static const NSUInteger BHTMaximumUserThemeCount = 64;
static const NSUInteger BHTMaximumUserThemeNameLength = 64;

static NSArray<NSString*>* BHTThemeRequiredRoles(void) {
    static NSArray<NSString*>* roles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        roles = @[
            BHTThemeColorAccentKey,
            BHTThemeColorBackgroundKey,
            BHTThemeColorSurfaceKey,
            BHTThemeColorElevatedSurfaceKey,
            BHTThemeColorTextKey,
            BHTThemeColorSecondaryTextKey,
            BHTThemeColorSeparatorKey
        ];
    });
    return roles;
}

static NSError* BHTThemeStoreError(NSInteger code, NSString* message) {
    return [NSError errorWithDomain:BHTThemeStoreErrorDomain
                               code:code
                           userInfo:@{
                               NSLocalizedDescriptionKey:
                                   message ?: @"The theme could not be saved."
                           }];
}

static NSString* BHTNewUserThemeIdentifier(void) {
    return [@"user."
        stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString];
}

static NSString* BHTNormalizedOpaqueThemeHex(id value) {
    NSString* normalized =
        [Palette normalizedHexString:
                     [value isKindOfClass:NSString.class] ? value : nil];
    return normalized.length == 7 ? normalized : nil;
}

static BOOL BHTThemeVersionIsExactly(id value, NSInteger expected) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) {
        return NO;
    }
    return [value doubleValue] == (double)expected;
}

@implementation BHTThemePresets

+ (NSArray<NSDictionary*>*)availablePresets {
    static NSArray<NSDictionary*>* presets;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        presets = @[
            @{
                @"identifier": @"apollo_inspired",
                @"titleKey": @"THEME_PRESET_APOLLO_TITLE",
                @"detailKey": @"THEME_PRESET_APOLLO_DETAIL",
                // Apollo-inspired, not an assertion that this is Apollo's
                // proprietary exact palette.
                @"lightColors": @{
                    BHTThemeColorAccentKey: @"#1767A8",
                    BHTThemeColorBackgroundKey: @"#F6F7F9",
                    BHTThemeColorSurfaceKey: @"#FFFFFF",
                    BHTThemeColorElevatedSurfaceKey: @"#E9EEF3",
                    BHTThemeColorTextKey: @"#121417",
                    BHTThemeColorSecondaryTextKey: @"#596675",
                    BHTThemeColorSeparatorKey: @"#D8DEE5"
                },
                @"darkColors": @{
                    BHTThemeColorAccentKey: @"#5AA9FF",
                    BHTThemeColorBackgroundKey: @"#0B0E11",
                    BHTThemeColorSurfaceKey: @"#151A20",
                    BHTThemeColorElevatedSurfaceKey: @"#202832",
                    BHTThemeColorTextKey: @"#F5F7FA",
                    BHTThemeColorSecondaryTextKey: @"#A5B0BC",
                    BHTThemeColorSeparatorKey: @"#2A3540"
                }
            },
            @{
                @"identifier": @"classic_twitter",
                @"titleKey": @"THEME_PRESET_CLASSIC_TWITTER_TITLE",
                @"detailKey": @"THEME_PRESET_CLASSIC_TWITTER_DETAIL",
                @"lightColors": @{
                    BHTThemeColorAccentKey: @"#096AA2",
                    BHTThemeColorBackgroundKey: @"#FFFFFF",
                    BHTThemeColorSurfaceKey: @"#F5F8FA",
                    BHTThemeColorElevatedSurfaceKey: @"#E1E8ED",
                    BHTThemeColorTextKey: @"#14171A",
                    BHTThemeColorSecondaryTextKey: @"#556773",
                    BHTThemeColorSeparatorKey: @"#D4DEE4"
                },
                @"darkColors": @{
                    BHTThemeColorAccentKey: @"#1DA1F2",
                    BHTThemeColorBackgroundKey: @"#15202B",
                    BHTThemeColorSurfaceKey: @"#192734",
                    BHTThemeColorElevatedSurfaceKey: @"#253341",
                    BHTThemeColorTextKey: @"#FFFFFF",
                    BHTThemeColorSecondaryTextKey: @"#A0AFBA",
                    BHTThemeColorSeparatorKey: @"#38444D"
                }
            },
            @{
                @"identifier": @"midnight_oled",
                @"titleKey": @"THEME_PRESET_MIDNIGHT_OLED_TITLE",
                @"detailKey": @"THEME_PRESET_MIDNIGHT_OLED_DETAIL",
                @"lightColors": @{
                    BHTThemeColorAccentKey: @"#2563B8",
                    BHTThemeColorBackgroundKey: @"#F7F9FC",
                    BHTThemeColorSurfaceKey: @"#FFFFFF",
                    BHTThemeColorElevatedSurfaceKey: @"#E8EEF7",
                    BHTThemeColorTextKey: @"#111827",
                    BHTThemeColorSecondaryTextKey: @"#566273",
                    BHTThemeColorSeparatorKey: @"#CBD5E1"
                },
                @"darkColors": @{
                    BHTThemeColorAccentKey: @"#62A0FF",
                    BHTThemeColorBackgroundKey: @"#000000",
                    BHTThemeColorSurfaceKey: @"#0D1117",
                    BHTThemeColorElevatedSurfaceKey: @"#161B22",
                    BHTThemeColorTextKey: @"#F4F7FB",
                    BHTThemeColorSecondaryTextKey: @"#A6B0BF",
                    BHTThemeColorSeparatorKey: @"#2A3442"
                }
            },
            @{
                @"identifier": @"evergreen",
                @"titleKey": @"THEME_PRESET_EVERGREEN_TITLE",
                @"detailKey": @"THEME_PRESET_EVERGREEN_DETAIL",
                @"lightColors": @{
                    BHTThemeColorAccentKey: @"#236B42",
                    BHTThemeColorBackgroundKey: @"#F4F8F3",
                    BHTThemeColorSurfaceKey: @"#FFFFFF",
                    BHTThemeColorElevatedSurfaceKey: @"#E5EFE4",
                    BHTThemeColorTextKey: @"#142018",
                    BHTThemeColorSecondaryTextKey: @"#53645A",
                    BHTThemeColorSeparatorKey: @"#C8D8CB"
                },
                @"darkColors": @{
                    BHTThemeColorAccentKey: @"#58B97E",
                    BHTThemeColorBackgroundKey: @"#08110C",
                    BHTThemeColorSurfaceKey: @"#101C15",
                    BHTThemeColorElevatedSurfaceKey: @"#19281E",
                    BHTThemeColorTextKey: @"#EFF7F1",
                    BHTThemeColorSecondaryTextKey: @"#A2B2A7",
                    BHTThemeColorSeparatorKey: @"#2B4032"
                }
            },
            @{
                @"identifier": @"rose_quartz",
                @"titleKey": @"THEME_PRESET_ROSE_QUARTZ_TITLE",
                @"detailKey": @"THEME_PRESET_ROSE_QUARTZ_DETAIL",
                @"lightColors": @{
                    BHTThemeColorAccentKey: @"#973458",
                    BHTThemeColorBackgroundKey: @"#FFF7FA",
                    BHTThemeColorSurfaceKey: @"#FFFFFF",
                    BHTThemeColorElevatedSurfaceKey: @"#F7E5EC",
                    BHTThemeColorTextKey: @"#25171D",
                    BHTThemeColorSecondaryTextKey: @"#6D5660",
                    BHTThemeColorSeparatorKey: @"#E4CAD4"
                },
                @"darkColors": @{
                    BHTThemeColorAccentKey: @"#E4749F",
                    BHTThemeColorBackgroundKey: @"#180D12",
                    BHTThemeColorSurfaceKey: @"#221219",
                    BHTThemeColorElevatedSurfaceKey: @"#311B25",
                    BHTThemeColorTextKey: @"#FFF3F7",
                    BHTThemeColorSecondaryTextKey: @"#C3A4B0",
                    BHTThemeColorSeparatorKey: @"#49303A"
                }
            },
            @{
                @"identifier": @"solarized_coast",
                @"titleKey": @"THEME_PRESET_SOLARIZED_COAST_TITLE",
                @"detailKey": @"THEME_PRESET_SOLARIZED_COAST_DETAIL",
                @"lightColors": @{
                    BHTThemeColorAccentKey: @"#17667F",
                    BHTThemeColorBackgroundKey: @"#FDF6E3",
                    BHTThemeColorSurfaceKey: @"#FFFDF5",
                    BHTThemeColorElevatedSurfaceKey: @"#EEE8D5",
                    BHTThemeColorTextKey: @"#253238",
                    BHTThemeColorSecondaryTextKey: @"#596B6F",
                    BHTThemeColorSeparatorKey: @"#D7CEB6"
                },
                @"darkColors": @{
                    BHTThemeColorAccentKey: @"#55B8CC",
                    BHTThemeColorBackgroundKey: @"#002B36",
                    BHTThemeColorSurfaceKey: @"#073642",
                    BHTThemeColorElevatedSurfaceKey: @"#0E4653",
                    BHTThemeColorTextKey: @"#F6F0DA",
                    BHTThemeColorSecondaryTextKey: @"#AAB7A6",
                    BHTThemeColorSeparatorKey: @"#275765"
                }
            },
            @{
                @"identifier": @"amethyst",
                @"titleKey": @"THEME_PRESET_AMETHYST_TITLE",
                @"detailKey": @"THEME_PRESET_AMETHYST_DETAIL",
                @"lightColors": @{
                    BHTThemeColorAccentKey: @"#6445B8",
                    BHTThemeColorBackgroundKey: @"#F8F6FC",
                    BHTThemeColorSurfaceKey: @"#FFFFFF",
                    BHTThemeColorElevatedSurfaceKey: @"#EDE8F7",
                    BHTThemeColorTextKey: @"#1D1825",
                    BHTThemeColorSecondaryTextKey: @"#625B70",
                    BHTThemeColorSeparatorKey: @"#D9D2E4"
                },
                @"darkColors": @{
                    BHTThemeColorAccentKey: @"#A98CF5",
                    BHTThemeColorBackgroundKey: @"#100D18",
                    BHTThemeColorSurfaceKey: @"#191526",
                    BHTThemeColorElevatedSurfaceKey: @"#241F34",
                    BHTThemeColorTextKey: @"#F6F2FC",
                    BHTThemeColorSecondaryTextKey: @"#ABA2BB",
                    BHTThemeColorSeparatorKey: @"#393249"
                }
            },
            @{
                @"identifier": @"cinder",
                @"titleKey": @"THEME_PRESET_CINDER_TITLE",
                @"detailKey": @"THEME_PRESET_CINDER_DETAIL",
                @"lightColors": @{
                    BHTThemeColorAccentKey: @"#914425",
                    BHTThemeColorBackgroundKey: @"#FBF7F0",
                    BHTThemeColorSurfaceKey: @"#FFFDF9",
                    BHTThemeColorElevatedSurfaceKey: @"#EFE6D9",
                    BHTThemeColorTextKey: @"#271C16",
                    BHTThemeColorSecondaryTextKey: @"#6E5E54",
                    BHTThemeColorSeparatorKey: @"#D9CDBE"
                },
                @"darkColors": @{
                    BHTThemeColorAccentKey: @"#E3815D",
                    BHTThemeColorBackgroundKey: @"#17110E",
                    BHTThemeColorSurfaceKey: @"#211915",
                    BHTThemeColorElevatedSurfaceKey: @"#30241E",
                    BHTThemeColorTextKey: @"#F8F1EA",
                    BHTThemeColorSecondaryTextKey: @"#B8A99F",
                    BHTThemeColorSeparatorKey: @"#44352D"
                }
            },
            @{
                @"identifier": @"native_blue",
                @"titleKey": @"THEME_PRESET_NATIVE_BLUE_TITLE",
                @"detailKey": @"THEME_PRESET_NATIVE_BLUE_DETAIL",
                @"accentHex": NSNull.null
            }
        ];
    });
    return presets;
}

+ (BOOL)isBuiltInPresetIdentifier:(NSString*)identifier {
    if (![identifier isKindOfClass:NSString.class]) return NO;
    for (NSDictionary* preset in [self availablePresets]) {
        if ([preset[@"identifier"] isEqualToString:identifier]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)isUserPresetIdentifier:(NSString*)identifier {
    if (![identifier isKindOfClass:NSString.class] ||
        identifier.length < 8 || identifier.length > 80 ||
        ![identifier hasPrefix:@"user."]) {
        return NO;
    }
    NSCharacterSet* allowed =
        [NSCharacterSet characterSetWithCharactersInString:
                            @"abcdefghijklmnopqrstuvwxyz0123456789-."];
    return [identifier
               rangeOfCharacterFromSet:allowed.invertedSet].location ==
           NSNotFound;
}

+ (NSDictionary*)normalizedUserTheme:(NSDictionary*)theme
                   generateIdentifier:(BOOL)generateIdentifier
                                error:(NSError**)error {
    if (![theme isKindOfClass:NSDictionary.class]) {
        if (error) {
            *error = BHTThemeStoreError(
                1, @"The custom theme is not a valid theme definition.");
        }
        return nil;
    }
    if (!BHTThemeVersionIsExactly(theme[@"schemaVersion"], 1)) {
        if (error) {
            *error = BHTThemeStoreError(
                11, @"This custom theme uses an unsupported format version.");
        }
        return nil;
    }

    NSString* identifier =
        [theme[@"identifier"] isKindOfClass:NSString.class]
            ? [theme[@"identifier"] lowercaseString]
            : nil;
    if (!identifier.length && generateIdentifier) {
        identifier = BHTNewUserThemeIdentifier();
    }
    if (![self isUserPresetIdentifier:identifier] ||
        [self isBuiltInPresetIdentifier:identifier]) {
        if (error) {
            *error = BHTThemeStoreError(
                2, @"The custom theme identifier is invalid.");
        }
        return nil;
    }

    NSString* name =
        [theme[@"name"] isKindOfClass:NSString.class]
            ? [theme[@"name"]
                  stringByTrimmingCharactersInSet:
                      NSCharacterSet.whitespaceAndNewlineCharacterSet]
            : nil;
    if (name.length == 0 ||
        name.length > BHTMaximumUserThemeNameLength ||
        [name rangeOfCharacterFromSet:
                  NSCharacterSet.newlineCharacterSet].location !=
            NSNotFound) {
        if (error) {
            *error = BHTThemeStoreError(
                3, @"Give the custom theme a name between 1 and 64 characters.");
        }
        return nil;
    }

    NSMutableDictionary* normalized =
        [NSMutableDictionary dictionaryWithDictionary:@{
            @"schemaVersion": @1,
            @"identifier": identifier,
            @"name": name,
            @"isUserPreset": @YES
        }];
    for (NSString* mapKey in @[@"lightColors", @"darkColors"]) {
        NSDictionary* raw =
            [theme[mapKey] isKindOfClass:NSDictionary.class]
                ? theme[mapKey]
                : nil;
        NSMutableDictionary* colors =
            [NSMutableDictionary dictionaryWithCapacity:
                                     BHTThemeRequiredRoles().count];
        for (NSString* role in BHTThemeRequiredRoles()) {
            NSString* hex = BHTNormalizedOpaqueThemeHex(raw[role]);
            if (!hex) {
                if (error) {
                    *error = BHTThemeStoreError(
                        4, [NSString stringWithFormat:
                                        @"The %@ color in %@ is invalid.",
                                        role,
                                        [mapKey isEqualToString:@"lightColors"]
                                            ? @"Light"
                                            : @"Dark"]);
                }
                return nil;
            }
            colors[role] = hex;
        }
        normalized[mapKey] = [colors copy];
    }

    NSNumber* createdAt =
        [theme[@"createdAt"] isKindOfClass:NSNumber.class]
            ? theme[@"createdAt"]
            : @([NSDate.date timeIntervalSince1970]);
    NSNumber* modifiedAt =
        [theme[@"modifiedAt"] isKindOfClass:NSNumber.class]
            ? theme[@"modifiedAt"]
            : createdAt;
    normalized[@"createdAt"] = createdAt;
    normalized[@"modifiedAt"] = modifiedAt;
    return [normalized copy];
}

+ (NSArray<NSDictionary*>*)userThemes {
    id library = [NSUserDefaults.standardUserDefaults
        objectForKey:BHTUserThemeLibraryPreferenceKey];
    if (![library isKindOfClass:NSDictionary.class] ||
        !BHTThemeVersionIsExactly(library[@"schemaVersion"], 1) ||
        ![library[@"themes"] isKindOfClass:NSArray.class]) {
        return @[];
    }

    NSMutableArray<NSDictionary*>* result =
        [NSMutableArray array];
    NSMutableSet<NSString*>* identifiers =
        [NSMutableSet set];
    for (id candidate in library[@"themes"]) {
        NSDictionary* normalized =
            [self normalizedUserTheme:candidate
                   generateIdentifier:NO
                                error:nil];
        NSString* identifier = normalized[@"identifier"];
        if (normalized && ![identifiers containsObject:identifier]) {
            [identifiers addObject:identifier];
            [result addObject:normalized];
        }
        if (result.count >= BHTMaximumUserThemeCount) break;
    }
    return [result copy];
}

+ (NSArray<NSDictionary*>*)allThemes {
    return [[self availablePresets]
        arrayByAddingObjectsFromArray:[self userThemes]];
}

+ (NSDictionary*)presetForIdentifier:(NSString*)identifier {
    if (![identifier isKindOfClass:NSString.class]) return nil;
    for (NSDictionary* preset in [self allThemes]) {
        if ([preset[@"identifier"] isEqualToString:identifier]) {
            return preset;
        }
    }
    return nil;
}

+ (NSString*)displayNameForPreset:(NSDictionary*)preset {
    NSString* name =
        [preset[@"name"] isKindOfClass:NSString.class]
            ? preset[@"name"]
            : nil;
    if (name.length > 0) return name;
    NSString* key =
        [preset[@"titleKey"] isKindOfClass:NSString.class]
            ? preset[@"titleKey"]
            : nil;
    return key.length > 0
               ? [[BHTBundle sharedBundle] localizedStringForKey:key]
               : @"Theme";
}

+ (NSString*)displayDetailForPreset:(NSDictionary*)preset {
    if ([preset[@"isUserPreset"] boolValue]) {
        return [[BHTBundle sharedBundle]
            localizedStringForKey:@"THEME_CUSTOM_DETAIL"];
    }
    NSString* key =
        [preset[@"detailKey"] isKindOfClass:NSString.class]
            ? preset[@"detailKey"]
            : nil;
    return key.length > 0
               ? [[BHTBundle sharedBundle] localizedStringForKey:key]
               : @"";
}

+ (NSDictionary<NSString*, UIColor*>*)colorsForPreset:
    (NSDictionary*)preset darkAppearance:(BOOL)darkAppearance {
    NSString* mapKey =
        darkAppearance ? @"darkColors" : @"lightColors";
    NSDictionary* rawColors =
        [preset[mapKey] isKindOfClass:NSDictionary.class]
            ? preset[mapKey]
            : nil;
    if (!rawColors) return nil;

    NSMutableDictionary<NSString*, UIColor*>* colors =
        [NSMutableDictionary dictionaryWithCapacity:
                                 BHTThemeRequiredRoles().count];
    for (NSString* role in BHTThemeRequiredRoles()) {
        UIColor* color =
            [Palette colorFromHexString:rawColors[role]];
        if (!color) return nil;
        colors[role] = color;
    }
    return [colors copy];
}

+ (UIColor*)previewAccentColorForPreset:(NSDictionary*)preset
                         darkAppearance:(BOOL)darkAppearance {
    UIColor* color =
        [self colorsForPreset:preset
               darkAppearance:darkAppearance][BHTThemeColorAccentKey];
    if (color) return color;
    id legacy = preset[@"accentHex"];
    return [legacy isKindOfClass:NSString.class]
               ? ([Palette colorFromHexString:legacy] ?:
                                            UIColor.systemBlueColor)
               : UIColor.systemBlueColor;
}

+ (NSDictionary*)newUserThemeDraftBasedOnPreset:(NSDictionary*)preset {
    NSDictionary* source = preset;
    if (![source[@"lightColors"] isKindOfClass:NSDictionary.class] ||
        ![source[@"darkColors"] isKindOfClass:NSDictionary.class]) {
        source = [self presetForIdentifier:@"apollo_inspired"];
    }
    return @{
        @"schemaVersion": @1,
        @"identifier": BHTNewUserThemeIdentifier(),
        @"name": [[BHTBundle sharedBundle]
            localizedStringForKey:@"THEME_BUILDER_DEFAULT_NAME"],
        @"isUserPreset": @YES,
        @"lightColors": [source[@"lightColors"] copy],
        @"darkColors": [source[@"darkColors"] copy],
        @"createdAt": @([NSDate.date timeIntervalSince1970]),
        @"modifiedAt": @([NSDate.date timeIntervalSince1970])
    };
}

+ (NSDictionary*)duplicateDraftForPreset:(NSDictionary*)preset {
    NSDictionary* source =
        [preset isKindOfClass:NSDictionary.class]
            ? preset
            : [self presetForIdentifier:@"apollo_inspired"];
    NSString* suffix = [[BHTBundle sharedBundle]
        localizedStringForKey:@"THEME_BUILDER_COPY_SUFFIX"];
    NSString* name = [NSString
        stringWithFormat:@"%@ %@", [self displayNameForPreset:source],
                         suffix.length > 0 ? suffix : @"Copy"];
    if (name.length > BHTMaximumUserThemeNameLength) {
        name = [name substringToIndex:BHTMaximumUserThemeNameLength];
    }
    NSMutableDictionary* draft =
        [[self newUserThemeDraftBasedOnPreset:source] mutableCopy];
    draft[@"name"] = name;
    return [draft copy];
}

+ (NSArray<NSDictionary*>*)validatedUserThemesFromObject:(id)object
                                                    error:(NSError**)error {
    if (![object isKindOfClass:NSArray.class] ||
        [(NSArray*)object count] > BHTMaximumUserThemeCount) {
        if (error) {
            *error = BHTThemeStoreError(
                5, @"The theme library contains too many themes.");
        }
        return nil;
    }
    NSMutableArray<NSDictionary*>* normalized =
        [NSMutableArray arrayWithCapacity:[(NSArray*)object count]];
    NSMutableSet<NSString*>* identifiers =
        [NSMutableSet set];
    for (id candidate in (NSArray*)object) {
        NSDictionary* theme =
            [self normalizedUserTheme:candidate
                   generateIdentifier:NO
                                error:error];
        if (!theme) return nil;
        NSString* identifier = theme[@"identifier"];
        if ([identifiers containsObject:identifier]) {
            if (error) {
                *error = BHTThemeStoreError(
                    6, @"The theme library contains a duplicate identifier.");
            }
            return nil;
        }
        [identifiers addObject:identifier];
        [normalized addObject:theme];
    }
    return [normalized copy];
}

+ (NSArray<NSDictionary*>*)
    userThemesByMergingImportedThemes:(NSArray<NSDictionary*>*)themes
                                error:(NSError**)error {
    NSArray<NSDictionary*>* imported =
        [self validatedUserThemesFromObject:themes error:error];
    if (!imported) return nil;
    NSMutableArray<NSDictionary*>* merged =
        [[self userThemes] mutableCopy];
    NSMutableDictionary<NSString*, NSNumber*>* positions =
        [NSMutableDictionary dictionary];
    [merged enumerateObjectsUsingBlock:^(
                NSDictionary* theme, NSUInteger index,
                __unused BOOL* stop) {
        positions[theme[@"identifier"]] = @(index);
    }];
    for (NSDictionary* theme in imported) {
        NSNumber* position = positions[theme[@"identifier"]];
        if (position) {
            merged[position.unsignedIntegerValue] = theme;
        } else {
            positions[theme[@"identifier"]] = @(merged.count);
            [merged addObject:theme];
        }
    }
    if (merged.count > BHTMaximumUserThemeCount) {
        if (error) {
            *error = BHTThemeStoreError(
                7, @"Importing this profile would exceed the 64-theme limit.");
        }
        return nil;
    }
    return [merged copy];
}

+ (BOOL)replaceUserThemes:(NSArray<NSDictionary*>*)themes
                    error:(NSError**)error {
    NSArray<NSDictionary*>* validated =
        [self validatedUserThemesFromObject:themes error:error];
    if (!validated) return NO;
    [NSUserDefaults.standardUserDefaults
        setObject:@{
            @"schemaVersion": @1,
            @"themes": validated
        }
          forKey:BHTUserThemeLibraryPreferenceKey];
    [NSNotificationCenter.defaultCenter
        postNotificationName:BHTThemeLibraryDidChangeNotification
                      object:nil];

    NSString* stored = [NSUserDefaults.standardUserDefaults
        stringForKey:@"bht_theme_preset_identifier"];
    if ([self isUserPresetIdentifier:stored]) {
        BOOL found = NO;
        for (NSDictionary* theme in validated) {
            if ([theme[@"identifier"] isEqualToString:stored]) {
                found = YES;
                break;
            }
        }
        if (!found) {
            [self applyPresetIdentifier:@"native_blue"];
        }
    }
    return YES;
}

+ (NSDictionary*)saveUserTheme:(NSDictionary*)theme
                          error:(NSError**)error {
    NSMutableDictionary* candidate = [theme mutableCopy];
    candidate[@"modifiedAt"] =
        @([NSDate.date timeIntervalSince1970]);
    NSDictionary* normalized =
        [self normalizedUserTheme:candidate
               generateIdentifier:YES
                            error:error];
    if (!normalized) return nil;
    NSMutableArray<NSDictionary*>* themes =
        [[self userThemes] mutableCopy];
    NSUInteger existing = [themes indexOfObjectPassingTest:^BOOL(
        NSDictionary* candidate, __unused NSUInteger index,
        __unused BOOL* stop) {
        return [candidate[@"identifier"]
            isEqualToString:normalized[@"identifier"]];
    }];
    if (existing != NSNotFound) {
        NSMutableDictionary* replacement = [normalized mutableCopy];
        replacement[@"createdAt"] =
            themes[existing][@"createdAt"] ?: normalized[@"createdAt"];
        normalized = [replacement copy];
        themes[existing] = normalized;
    } else {
        if (themes.count >= BHTMaximumUserThemeCount) {
            if (error) {
                *error = BHTThemeStoreError(
                    8, @"You can save up to 64 custom themes.");
            }
            return nil;
        }
        [themes addObject:normalized];
    }

    if (![self replaceUserThemes:themes error:error]) return nil;
    return normalized;
}

+ (BOOL)deleteUserThemeIdentifier:(NSString*)identifier
                             error:(NSError**)error {
    if (![self isUserPresetIdentifier:identifier]) {
        if (error) {
            *error = BHTThemeStoreError(
                9, @"Only custom themes can be deleted.");
        }
        return NO;
    }
    NSMutableArray<NSDictionary*>* themes =
        [[self userThemes] mutableCopy];
    NSIndexSet* matches =
        [themes indexesOfObjectsPassingTest:^BOOL(
                    NSDictionary* theme, __unused NSUInteger index,
                    __unused BOOL* stop) {
        return [theme[@"identifier"] isEqualToString:identifier];
    }];
    if (matches.count == 0) {
        if (error) {
            *error = BHTThemeStoreError(
                10, @"The custom theme no longer exists.");
        }
        return NO;
    }
    [themes removeObjectsAtIndexes:matches];
    return [self replaceUserThemes:themes error:error];
}

+ (NSString*)activePresetIdentifier {
    NSString* stored = [NSUserDefaults.standardUserDefaults
        stringForKey:@"bht_theme_preset_identifier"];
    NSDictionary* preset = [self presetForIdentifier:stored];
    if (!preset) return nil;

    if ([preset[@"lightColors"] isKindOfClass:NSDictionary.class] &&
        [preset[@"darkColors"] isKindOfClass:NSDictionary.class]) {
        return [self colorsForPreset:preset darkAppearance:NO] &&
                       [self colorsForPreset:preset darkAppearance:YES]
                   ? stored
                   : nil;
    }

    NSString* storedHex = [Palette normalizedHexString:
        [NSUserDefaults.standardUserDefaults
            stringForKey:@"bht_custom_accent_hex"]];
    id presetHex = preset[@"accentHex"];
    if (presetHex == NSNull.null) {
        return storedHex ? nil : stored;
    }
    return [storedHex isEqualToString:
                          [Palette normalizedHexString:presetHex]]
               ? stored
               : nil;
}

+ (NSDictionary<NSString*, UIColor*>*)
    activeAppColorsForDarkAppearance:(BOOL)darkAppearance {
    NSDictionary* preset =
        [self presetForIdentifier:[self activePresetIdentifier]];
    return [self colorsForPreset:preset
                  darkAppearance:darkAppearance];
}

+ (BOOL)applyPresetIdentifier:(NSString*)identifier {
    NSDictionary* preset = [self presetForIdentifier:identifier];
    if (!preset) return NO;

    BOOL fullTheme =
        [preset[@"lightColors"] isKindOfClass:NSDictionary.class] ||
        [preset[@"darkColors"] isKindOfClass:NSDictionary.class];
    if (fullTheme &&
        (![self colorsForPreset:preset darkAppearance:NO] ||
         ![self colorsForPreset:preset darkAppearance:YES])) {
        // Preflight both modes before the first write. An incomplete theme must
        // never leave a mixed native/custom palette active.
        return NO;
    }

    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    id legacyAccentHex = preset[@"accentHex"];
    if (fullTheme || legacyAccentHex == NSNull.null) {
        [defaults removeObjectForKey:@"bht_custom_accent_hex"];
    } else {
        NSString* normalized =
            BHTNormalizedOpaqueThemeHex(legacyAccentHex);
        if (!normalized) return NO;
        [defaults setObject:normalized
                     forKey:@"bht_custom_accent_hex"];
    }
    [defaults setInteger:1
                  forKey:@"bh_color_theme_selectedColor"];
    [defaults setObject:identifier
                 forKey:@"bht_theme_preset_identifier"];
    [Palette invalidateCustomAccentColorCache];

    [self reapplyCurrentAccent];
    [NSNotificationCenter.defaultCenter
        postNotificationName:BHTThemeDidChangeNotification
                      object:nil];
    return YES;
}

+ (void)reapplyCurrentAccent {
    Class settingsClass = objc_getClass("TAEColorSettings");
    if (![settingsClass respondsToSelector:@selector(sharedSettings)]) return;
    id settings = [settingsClass sharedSettings];
    if (![settings respondsToSelector:@selector(setPrimaryColorOption:)]) {
        return;
    }
    NSInteger option = [NSUserDefaults.standardUserDefaults
        integerForKey:@"bh_color_theme_selectedColor"];
    changeTwitterColor(MIN(6, MAX(1, option)));
}

+ (void)clearPresetSelection {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:@"bht_theme_preset_identifier"];
    [defaults removeObjectForKey:@"bht_custom_accent_hex"];
    [Palette invalidateCustomAccentColorCache];
    [NSNotificationCenter.defaultCenter
        postNotificationName:BHTThemeDidChangeNotification
                      object:nil];
}

@end
