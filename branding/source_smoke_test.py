#!/usr/bin/env python3
"""Check source invariants that protect the X 12.9 compatibility fixes."""

from collections import Counter
from pathlib import Path
import re
import struct


ROOT = Path(__file__).resolve().parent.parent
SETTINGS = ROOT / "src" / "Core" / "BHTSettings.m"
ENGLISH = (
    ROOT
    / "layout"
    / "Library"
    / "Application Support"
    / "BHT"
    / "BHTwitter.bundle"
    / "en.lproj"
    / "Localizable.strings"
)
BUNDLE = ENGLISH.parents[1]


def png_size(path: Path) -> tuple[int, int]:
    raw = path.read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n" or raw[12:16] != b"IHDR":
        raise AssertionError(f"{path} is not a PNG")
    return struct.unpack(">II", raw[16:24])


def main() -> None:
    settings_source = SETTINGS.read_text(encoding="utf-8")
    english_source = ENGLISH.read_text(encoding="utf-8")
    localized_keys = set(
        re.findall(r'^\s*"([^"]+)"\s*=', english_source, re.MULTILINE)
    )
    localized_key_list = re.findall(
        r'^\s*"([^"]+)"\s*=', english_source, re.MULTILINE
    )
    duplicate_localizations = sorted(
        key
        for key, count in Counter(localized_key_list).items()
        if count > 1
    )
    if duplicate_localizations:
        raise AssertionError(
            f"Duplicate English localization keys: "
            f"{duplicate_localizations}"
        )

    setting_keys = re.findall(
        r'@"key"\s*:\s*@"([^"]+)"', settings_source
    )
    duplicates = sorted(
        key for key, count in Counter(setting_keys).items() if count > 1
    )
    if duplicates:
        raise AssertionError(f"Duplicate setting keys: {duplicates}")

    section_keys = set(
        re.findall(r'@"sectionKey"\s*:\s*@"([^"]+)"', settings_source)
    )
    missing_sections = sorted(section_keys - localized_keys)
    if missing_sections:
        raise AssertionError(
            f"Unlocalized settings sections: {missing_sections}"
        )

    compact_keys = {
        "regular_font_button",
        "bold_font_button",
        "undo_tweet_timeout",
    }
    missing_titles = sorted(
        key
        for key in setting_keys
        if key not in compact_keys
        and f"{key.upper()}_TITLE" not in localized_keys
    )
    missing_details = sorted(
        key
        for key in setting_keys
        if key not in compact_keys
        and f"{key.upper()}_DETAIL" not in localized_keys
    )
    if missing_titles or missing_details:
        raise AssertionError(
            f"Missing setting strings: titles={missing_titles}, "
            f"details={missing_details}"
        )

    parent_keys = set(
        re.findall(r'@"parentKey"\s*:\s*@"([^"]+)"', settings_source)
    )
    missing_parents = sorted(parent_keys - set(setting_keys))
    if missing_parents:
        raise AssertionError(
            f"Unknown parent setting keys: {missing_parents}"
        )

    expected_birds = {
        "twitter_bird.png": (24, 24),
        "twitter_bird@2x.png": (48, 48),
        "twitter_bird@3x.png": (72, 72),
    }
    for filename, expected_size in expected_birds.items():
        if png_size(BUNDLE / filename) != expected_size:
            raise AssertionError(f"{filename} has the wrong dimensions")

    source_files = list((ROOT / "src").rglob("*.m"))
    source_files.extend((ROOT / "src").rglob("*.x"))
    for path in source_files:
        source = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT).as_posix()
        if (
            "NSTemporaryDirectory()" in source
            and relative != "src/Core/BHTManager.m"
        ):
            raise AssertionError(
                f"Temporary exports must use BHTManager: {relative}"
            )
        if "performChangesAndWait" in source:
            raise AssertionError(f"Blocking Photos save remains in {relative}")

    profile_source = (ROOT / "src" / "Hooks" / "Profile.x").read_text(
        encoding="utf-8"
    )
    if "- (BOOL)isProfileTranslationEnabled" in profile_source:
        raise AssertionError("Unavailable X 12.9 profile selector is hooked")

    page_source = (
        ROOT / "src" / "Settings" / "ModernSettingsPageViewController.m"
    ).read_text(encoding="utf-8")
    for unsafe_key in ('@"prefKey"', '@"fontType"'):
        if unsafe_key in page_source:
            raise AssertionError(
                f"Associated-object literal key remains: {unsafe_key}"
            )

    theme_source = (ROOT / "src" / "Hooks" / "Theme.x").read_text(
        encoding="utf-8"
    )
    for required in (
        "UIUserInterfaceIdiomPad",
        "T1TabBarHostView",
        "BHTRailHeaderLogoImageView",
        "BHTGuardedRailHeaderImageScan",
        "BHTRailHeaderCandidateBelongsToTab",
        "kBHTRailResolvedLogoViewKey",
        "kBHTOriginalRailLogoStateCapturedKey",
        "kBHTOriginalRailLogoAccessibilityLabelKey",
        "CGRectGetMaxY(frame) > headerBottom",
        '@"guardedHeaderScan"',
        "BHTThemeDidChangeNotification",
        "logoView.hidden = enabled && usesPadRail",
    ):
        if required not in theme_source:
            raise AssertionError(f"Missing compatibility fix: {required}")
    if "BHTAdaptiveRailLogoView" in theme_source:
        raise AssertionError(
            "Geometry-based rail branding can replace the Home tab icon"
        )
    compatibility_source = (
        ROOT / "src" / "Compatibility" / "BHTCompatibilityReporter.m"
    ).read_text(encoding="utf-8")
    for required in (
        'BHTProbe(@"appearance", @"T1TabBarHostView", @"logoImageView", NO)',
        'BHTProbe(@"appearance", @"T1TabBarHostView", @"tabBarViewController", NO)',
        'BHTProbe(@"appearance", @"TAEColorSettings", @"currentColorPalette", NO)',
        'BHTProbe(@"appearance", @"T1ColorSettings", @"_t1_applyTheme", YES)',
        '@"railBrandingRuntime": BHTRailBrandingObservationSnapshot()',
        '@"themeRuntime": BHTThemeRuntimeObservationSnapshot()',
        '@"configurationGeneration"',
        '@"seenPaletteCount"',
        '@"providerClasses"',
        '@"dynamicColorsDidReloadObserved"',
        'BHTProbe(@"appearance", @"UIColor", @"twitterColors", YES)',
        'BHTProbe(@"appearance", @"UIColor", @"tfnuiColors", YES)',
        "BHTRailBrandingObservationState",
        "if (unchanged) return;",
    ):
        if required not in compatibility_source:
            raise AssertionError(
                f"Missing branding/theme compatibility probe: {required}"
            )

    branding_source = (
        ROOT / "src" / "Branding" / "BHTBranding.m"
    ).read_text(encoding="utf-8")
    if '@"twitter_bird"' not in branding_source:
        raise AssertionError("Central Twitter bird asset lookup is missing")

    ipa_branding_source = (
        ROOT / "branding" / "ipa_branding.py"
    ).read_text(encoding="utf-8")
    for required in (
        "_apply_builtin_launch_bird",
        'stock_name = b"xLogo"',
        '"tBird@3x.png"',
        "TWITTER_BLUE = (29, 161, 242)",
    ):
        if required not in ipa_branding_source:
            raise AssertionError(
                f"Missing pre-injection launch branding: {required}"
            )
    merged_car_source = (
        ROOT / "branding" / "build_merged_car.py"
    ).read_text(encoding="utf-8")
    for required in ('name.lower() == "xlogo"', "template-rendering-intent"):
        if required not in merged_car_source:
            raise AssertionError(
                f"Missing xLogo template invariant: {required}"
            )

    theme_preset_source = (
        ROOT / "src" / "ThemeColor" / "BHTThemePresets.m"
    ).read_text(encoding="utf-8")
    for required in (
        '@"apollo_inspired"',
        '@"#0A84FF"',
        '@"classic_twitter"',
        '@"#1DA1F2"',
        '@"native_blue"',
        '@"lightColors"',
        '@"darkColors"',
        "BHTThemeColorBackgroundKey",
        "BHTThemeColorSurfaceKey",
        "BHTThemeColorTextKey",
        "BHTThemeColorSeparatorKey",
        "activeAppColorsForDarkAppearance",
        "respondsToSelector:@selector(setPrimaryColorOption:)",
    ):
        if required not in theme_preset_source:
            raise AssertionError(f"Missing theme preset invariant: {required}")

    hook_helpers_source = (
        ROOT / "src" / "Hooks" / "HookHelpers.m"
    ).read_text(encoding="utf-8")
    if "[Palette customAccentColor]" not in hook_helpers_source:
        raise AssertionError("Custom theme accent is not resolved at runtime")
    theme_accent_source = (
        ROOT / "src" / "Hooks" / "ThemeAccent.x"
    ).read_text(encoding="utf-8")
    for required in (
        "BHTPrimaryColorMethodIsCompatible",
        "BHTColorGetterMethodIsCompatible",
        "BHTConfigureFullThemeForPalette",
        "BHTOriginalColorGetterIMP",
        "BHTVoidObjectSetterIsCompatible",
        "BHTInvokeGuardedVoidGetter",
        "TFNDynamicColorsDidReloadNotification",
        "BHTInstallDynamicColorDiagnosticObserver",
        "BHTDidObserveDynamicColorsReload",
        "kBHTPaletteConfigurationGenerationKey",
        "kBHTPaletteConfigurationDarkAppearanceKey",
        "BHTCurrentThemeConfigurationGeneration",
        "BHTAdvanceThemeConfigurationGeneration",
        "BHTSeenThemePalettes",
        "weakObjectsHashTable",
        "BHTReconfigureSeenThemePalettes",
        "BHTInstallThemeHooksForProviders",
        '@"twitterColors"',
        '@"tfnuiColors"',
        "BHTLastThemeProviderClasses",
        "BHTRecordThemeRuntimeObservation",
        '@"_t1_updateDynamicColors"',
        "kBHTMaximumThemeTraversalViews",
        "BHTScheduleProviderAttachRefresh",
        "BHTPostReloadProviderRedrawNeeded",
        "BHTForcedProviderRedrawExecuting",
        '@"cardBackgroundColor"',
        '@"darkBackgroundColor"',
        '@"capsuleTabsSelectedBackgroundColor"',
        '@"capsuleTabsOnMediaSelectedBackgroundColor"',
        '@"capsuleTabsOnMediaTextColor"',
        '@"capsuleTabsOnMediaBorderColor"',
        '@"textDetailsColor"',
        '@"retweetButtonColor"',
        "if (colors.count == 0) return;",
        "return original ?",
        '@"_t1_applyTheme"',
        '@"_t1_updateOverrideUserInterfaceStyle"',
        '@"applyCurrentColorPalette"',
        "@selector(setCurrentColorPalette:)",
        "method_getReturnType",
        "class_addMethod",
        "BHTSettingsProfileDidApplyNotification",
        "[Palette invalidateCustomAccentColorCache]",
    ):
        if required not in theme_accent_source:
            raise AssertionError(
                f"Missing guarded app-wide accent invariant: {required}"
            )
    if "postNotificationName" in theme_accent_source:
        raise AssertionError(
            "Theme hook must not synthesize X's private dynamic-color "
            "notifications"
        )
    theme_traversal_source = theme_accent_source.split(
        "static void BHTUpdateDynamicColorsInVisibleView", 1
    )[1].split(
        "static void BHTScheduleVisibleDynamicColorRefresh", 1
    )[0]
    if "view.hidden" in theme_traversal_source:
        raise AssertionError(
            "Theme fallback must include loaded hidden subviews"
        )
    palette_source = (
        ROOT / "src" / "ThemeColor" / "Palette.m"
    ).read_text(encoding="utf-8")
    for required in (
        "BHTCustomAccentCacheIsValid",
        "BHTAppThemeColorCacheIsValid",
        "customThemeColorsForDarkAppearance",
        "currentSurfaceColor",
        "currentTextColor",
        "currentSeparatorColor",
        "invalidateCustomAccentColorCache",
        "BHTSettingsProfileDidApplyNotification",
    ):
        if required not in palette_source:
            raise AssertionError(
                f"Missing custom-accent cache invariant: {required}"
            )

    theme_source = (
        ROOT / "src" / "Hooks" / "Theme.x"
    ).read_text(encoding="utf-8")
    for required in (
        "BHTApplyCurrentThemeToTabBarController",
        "BHTApplyThemeToNativeTabBar",
        '@"tabBarBackgroundView"',
        '@"tabBarDivider"',
        '@"nativeTabBar"',
        '@"_t1_configureNativeTabBar"',
        "BHTShouldThemeTabItems",
        "BHTTabChromeThemeGeneration",
        "BHTChromeBackgroundStillMatches",
        "BHTThemedTabBarAppearance",
    ):
        if required not in theme_source:
            raise AssertionError(
                f"Missing live tab-bar theme invariant: {required}"
            )

    likes_hook_source = (
        ROOT / "src" / "Hooks" / "Likes.x"
    ).read_text(encoding="utf-8")
    if "[Palette currentSecondaryTextColor]" not in likes_hook_source:
        raise AssertionError(
            "Likes tab must use the active theme's secondary text color"
        )

    editor_colors_source = (
        ROOT / "src" / "CustomTabBar" / "CustomTabBarNativeColors.m"
    ).read_text(encoding="utf-8")
    for required in (
        "BHTThemeColorBackgroundKey",
        "BHTThemeColorSurfaceKey",
        "BHTThemeColorTextKey",
        "BHTThemeColorSeparatorKey",
    ):
        if required not in editor_colors_source:
            raise AssertionError(
                f"Missing themed editor color invariant: {required}"
            )

    modern_settings_source = (
        ROOT / "src" / "Settings" / "ModernSettingsViewController.m"
    ).read_text(encoding="utf-8")
    for required in (
        "UISearchResultsUpdating",
        "allSearchableSettings",
        'setting[@"sectionKey"]',
        'page[@"subtitle"]',
        "showPresetSettings",
        "BHTThemeDidChangeNotification",
        "currentSurfaceColor",
    ):
        if required not in modern_settings_source:
            raise AssertionError(
                f"Missing settings search/profile UI invariant: {required}"
            )

    for required in (
        "NeoFreeBird Preference Profile",
        "exportablePreferenceKeys",
        "bht_custom_accent_hex",
        "bht_theme_preset_identifier",
        "BHTSettingsProfileDidApplyNotification",
        "[(NSArray*)value count] > 128",
        "[(NSString*)item length] > 128",
        '@"apollo_inspired"',
        '@"classic_twitter"',
        '@"native_blue"',
    ):
        if required not in settings_source:
            raise AssertionError(
                f"Missing preference-profile invariant: {required}"
            )
    for forbidden in ("password", "cookie", "auth_token", "session_token"):
        export_method = settings_source.split(
            "+ (NSSet<NSString*>*)exportablePreferenceKeys", 1
        )[1].split("+ (NSDictionary*)preferenceProfile", 1)[0]
        if f'@"{forbidden}"' in export_method:
            raise AssertionError(
                f"Sensitive key entered profile allow-list: {forbidden}"
            )

    for required_key in (
        "SETTINGS_SEARCH_PLACEHOLDER",
        "THEME_PRESET_APOLLO_TITLE",
        "EXPORT_PREFERENCE_PROFILE_TITLE",
        "IMPORT_PREFERENCE_PROFILE_TITLE",
    ):
        if required_key not in localized_keys:
            raise AssertionError(
                f"Missing settings/theme localization: {required_key}"
            )
    if "coordinated app palette" not in english_source.lower():
        raise AssertionError(
            "Theme settings still describe presets as accent-only"
        )

    launch_source = (
        ROOT / "src" / "Hooks" / "AppLifecycle.x"
    ).read_text(encoding="utf-8")
    if "applyClassicLaunchBird" not in launch_source:
        raise AssertionError("Classic launch bird replacement is missing")

    likes_source = (
        ROOT / "src" / "Likes" / "BHTLikesTab.m"
    ).read_text(encoding="utf-8")
    for required in (
        "BHTLikedMediaContextConfiguration",
        "UIContextMenuInteraction",
        "TFNMenuSheetViewController",
        "UIPercentDrivenInteractiveTransition",
        'BHTPhotoURLForVariant(rawURL, @"medium")',
        "totalCostLimit = 128 * 1024 * 1024",
        "BHTCachedMediaImageEntry",
        "pixelBucket",
        "BHTPendingMediaImageRequests",
        "imageRequestsCoalesced",
        "if (!token.cancelled) completion(image)",
        '"waterfallImageScaling": @"completeAspectFitWithDecodedRatioCorrection"',
        '"waterfallAspectRatioPolicy": @"metadataThenDecodedImageAdaptiveMasonry"',
        '"waterfallColumnSpanPolicy": @"wideMediaMaySpanAdjacentColumns"',
        "return MAX(0.10, MIN(10.0, ratio));",
        "waterfallDecodedRatioCorrections",
        "waterfallAnchorPreservations",
        "collectionView.indexPathsForVisibleItems",
        "waterfallLayoutInvalidationPendingUntilIdle",
        "applyPendingWaterfallLayoutInvalidationIfIdle",
        "aspectRatioConfirmedByImage",
        "updateAdaptiveAspectRatioForItem",
        "desiredSpan = MIN(2, columns);",
        "bestGap <= acceptedGap",
        "self.imageView.backgroundColor = surfaceColor;",
        "[cell applyCurrentThemeSurface];",
        "BHTThemeDidChangeNotification",
        "BHTSettingsProfileDidApplyNotification",
        "TFNDynamicColorsDidReloadNotification",
        "applyCurrentThemeSurfaces",
        "self.collectionView.visibleCells",
        "themeSharedBarsOwnedByGlobalHook",
        "BHTLikesSolidColorImage",
        "themeNativePostsOwnedByProviderHooks",
        "BHTRefreshNativeTabViewAppearance(nativeLikesTab)",
        "themeRefreshScheduled",
        '@"themeRefreshes"',
        '"viewerPresentation": @"windowFullScreen"',
        "BHTFullScreenPresenterForController",
        "UIModalPresentationFullScreen",
        "toView.frame = container.bounds",
        "UIScrollViewContentInsetAdjustmentNever",
        "supportedInterfaceOrientations",
        "viewerFullScreenCoverage",
    ):
        if required not in likes_source:
            raise AssertionError(
                f"Missing Likes media improvement: {required}"
            )

    print(
        f"Source smoke test passed ({len(setting_keys)} settings, "
        f"{len(section_keys)} localized subsections)."
    )


if __name__ == "__main__":
    main()
