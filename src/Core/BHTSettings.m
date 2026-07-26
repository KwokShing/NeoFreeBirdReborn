//
//  BHTSettings.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Core/BHTSettings.h"
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"

static NSDictionary<NSString*, NSDictionary*>* BHTSettingsPages(void) {
    static NSDictionary<NSString*, NSDictionary*>* pages;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pages = @{
            @"general": @{
                @"titleKey": @"MODERN_SETTINGS_LAYOUT_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_LAYOUT_SUBTITLE",
                @"settings": @[
                    @{@"key": @"padlock",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_APP_LOCK"},
                    @{@"key": @"disable_screenshot_detection",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_SCREENSHOTS"},
                    @{@"key": @"hide_screenshot_branding",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_SCREENSHOTS"}
                ]
            },
            @"appearance": @{
                @"titleKey": @"MODERN_SETTINGS_APPEARANCE_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_APPEARANCE_SUBTITLE",
                @"settings": @[
                    @{
                        @"titleKey": @"THEME_OPTION_TITLE",
                        @"action": @"showThemeViewController:",
                        @"type": @"button",
                        @"sectionKey": @"SETTINGS_SECTION_VISUALS"
                    },
                    @{
                        @"titleKey": @"APP_ICON_TITLE",
                        @"action": @"showAppIconViewController:",
                        @"type": @"button",
                        @"sectionKey": @"SETTINGS_SECTION_VISUALS"
                    },
                    @{
                        @"titleKey": @"CUSTOM_TAB_BAR_OPTION_TITLE",
                        @"action": @"showCustomTabBarVC:",
                        @"type": @"button",
                        @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"
                    },
                    @{
                        @"titleKey": @"LIKES_NAVIGATION_EDITOR_TITLE",
                        @"action": @"showLikesNavigationVC:",
                        @"type": @"button",
                        @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"
                    },
                    @{
                        @"titleKey": @"SIDEBAR_NAVIGATION_EDITOR_TITLE",
                        @"action": @"showSidebarNavigationVC:",
                        @"type": @"button",
                        @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"
                    },
                    @{@"key": @"tab_bar_theming",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"},
                    @{@"key": @"restore_tab_labels",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"},
                    @{@"key": @"no_tab_bar_hiding",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"},
                    @{@"key": @"disable_rtl",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"},
                    @{@"key": @"show_scroll_indicator",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"},
                    @{@"key": @"restore_launch_animation",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_MOTION_SOUND"},
                    @{@"key": @"restore_refresh_sounds",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_MOTION_SOUND"},
                    @{@"key": @"custom_fonts",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_FONTS"},
                    @{
                        @"type": @"compactButton",
                        @"parentKey": @"custom_fonts",
                        @"key": @"regular_font_button",
                        @"titleKey": @"REGULAR_FONTS_PICKER_OPTION_TITLE",
                        @"action": @"showRegularFontPicker:",
                        @"prefKeyForSubtitle": @"bhtwitter_font_1",
                        @"subtitleDefaultKey": @"FONT_SYSTEM_DEFAULT_SUBTITLE",
                        @"sectionKey": @"SETTINGS_SECTION_FONTS"
                    },
                    @{
                        @"type": @"compactButton",
                        @"parentKey": @"custom_fonts",
                        @"key": @"bold_font_button",
                        @"titleKey": @"BOLD_FONTS_PICKER_OPTION_TITLE",
                        @"action": @"showBoldFontPicker:",
                        @"prefKeyForSubtitle": @"bhtwitter_font_2",
                        @"subtitleDefaultKey": @"FONT_SYSTEM_DEFAULT_SUBTITLE",
                        @"sectionKey": @"SETTINGS_SECTION_FONTS"
                    }
                ]
            },
            @"timelines": @{
                @"titleKey": @"MODERN_SETTINGS_TIMELINES_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_TIMELINES_SUBTITLE",
                @"settings": @[
                    @{@"key": @"hide_promoted",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_ADS_OFFERS"},
                    @{@"key": @"hide_premium_offer",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_ADS_OFFERS"},
                    @{@"key": @"hide_who_to_follow",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_CLEANUP"},
                    @{@"key": @"hide_timeline_prompts",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_CLEANUP"},
                    @{@"key": @"hide_discover_more",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_CLEANUP"},
                    @{@"key": @"hide_topics",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_CLEANUP"},
                    @{@"key": @"hide_topics_to_follow",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_CLEANUP"},
                    @{@"key": @"hide_spaces",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_BEHAVIOR"},
                    @{@"key": @"hide_custom_timelines",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_BEHAVIOR"},
                    @{@"key": @"remember_timeline_tab",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_BEHAVIOR"}
                ]
            },
            @"grok": @{
                @"titleKey": @"MODERN_SETTINGS_GROK_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_GROK_SUBTITLE",
                @"settings": @[
                    @{
                        @"key": @"enable_grok_translations",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_grok_analyze",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_grok_sidebar",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_grok_create",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"disable_auto_translate",
                        @"default": @NO,
                        @"type": @"toggle"
                    }
                ]
            },
            @"media_downloads": @{
                @"titleKey": @"MODERN_SETTINGS_MEDIA_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_MEDIA_SUBTITLE",
                @"settings": @[
                    @{
                        @"titleKey": @"MEDIA_ACTION_MENU_EDITOR_TITLE",
                        @"action": @"showMediaActionMenus:",
                        @"type": @"button",
                        @"sectionKey": @"SETTINGS_SECTION_DOWNLOADS_ACTIONS"
                    },
                    @{
                        @"key": @"download_videos",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_DOWNLOADS_ACTIONS"
                    },
                    @{
                        @"key": @"dm_media_downloads",
                        @"parentKey": @"download_videos",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_DOWNLOADS_ACTIONS"
                    },
                    @{@"key": @"direct_save",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_DOWNLOADS_ACTIONS"
                    },
                    @{
                        @"key": @"voice_creation_enabled",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_MESSAGES_CREATION"
                    },
                    @{
                        @"key": @"no_voice_messages",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_MESSAGES_CREATION"
                    },
                    @{
                        @"key": @"old_compose_bar",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_MESSAGES_CREATION"
                    },
                    @{
                        @"key": @"dm_reply_later_enabled",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_MESSAGES_CREATION"
                    },
                    @{
                        @"key": @"media_upload_4k_enabled",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_MESSAGES_CREATION"
                    },
                    @{
                        @"key": @"custom_voice_upload",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_MESSAGES_CREATION"
                    },
                    @{
                        @"key": @"disable_video_captions",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_QUALITY_PLAYBACK"
                    },
                    @{
                        @"key": @"auto_highest_load",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_QUALITY_PLAYBACK"
                    },
                    @{
                        @"key": @"force_highest_video_quality",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_QUALITY_PLAYBACK"
                    },
                    @{
                        @"key": @"force_tweet_full_frame",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_QUALITY_PLAYBACK"
                    },
                    @{
                        @"key": @"restore_video_timestamp",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_QUALITY_PLAYBACK"
                    },
                    @{
                        @"key": @"disable_immersive_scroll",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_QUALITY_PLAYBACK"
                    }
                ]
            },
            @"profiles": @{
                @"titleKey": @"MODERN_SETTINGS_PROFILES_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_PROFILES_SUBTITLE",
                @"settings": @[
                    @{@"key": @"follow_confirm",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_PROFILE_ACTIONS"},
                    @{
                        @"key": @"copy_profile_info",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_PROFILE_ACTIONS"
                    },
                    @{
                        @"key": @"disable_articles",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_PROFILE_TABS"
                    },
                    @{
                        @"key": @"disable_highlights",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_PROFILE_TABS"
                    },
                    @{
                        @"key": @"hide_blue_verified",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_PROFILE_APPEARANCE"
                    },
                    @{
                        @"key": @"hide_follow_button",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_PROFILE_ACTIONS"
                    },
                    @{
                        @"key": @"restore_follow_button",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_PROFILE_ACTIONS"
                    },
                    @{@"key": @"square_avatars",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_PROFILE_APPEARANCE"},
                    @{
                        @"key": @"full_profile_counts",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_PROFILE_APPEARANCE"
                    }
                ]
            },
            @"tweets": @{
                @"titleKey": @"MODERN_SETTINGS_TWEETS_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_TWEETS_SUBTITLE",
                @"settings": @[
                    @{
                        @"key": @"enable_edit_tweet",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_COMPOSING"
                    },
                    @{
                        @"type": @"compactButton",
                        @"key": @"undo_tweet_timeout",
                        @"default": @10,
                        @"titleKey": @"UNDO_TWEET_TITLE",
                        @"action": @"showUndoTimeoutPicker:",
                        @"sectionKey": @"SETTINGS_SECTION_COMPOSING"
                    },
                    @{@"key": @"tweet_confirm",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_COMPOSING"},
                    @{@"key": @"like_confirm",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_INTERACTIONS"},
                    @{@"key": @"tweet_to_image",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_COMPOSING"},
                    @{
                        @"key": @"hide_view_count",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_INTERACTIONS"
                    },
                    @{
                        @"key": @"hide_bookmark_button",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_INTERACTIONS"
                    },
                    @{
                        @"key": @"hide_downvote_button",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_INTERACTIONS"
                    },
                    @{
                        @"key": @"disable_sensitive_tweet_warnings",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_SAFETY_CONTEXT"
                    },
                    @{
                        @"key": @"bypass_age_verification",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_SAFETY_CONTEXT"
                    },
                    @{@"key": @"reply_sorting",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_SAFETY_CONTEXT"},
                    @{
                        @"key": @"restore_reply_context",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_SAFETY_CONTEXT"
                    },
                    @{
                        @"key": @"restore_tweet_labels",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_SAFETY_CONTEXT"
                    }
                ]
            },
            @"search": @{
                @"titleKey": @"MODERN_SETTINGS_SEARCH_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_SEARCH_SUBTITLE",
                @"settings": @[
                    @{@"key": @"no_history",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_trends",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{
                        @"key": @"hide_trend_videos",
                        @"default": @NO,
                        @"type": @"toggle"
                    }
                ]
            },
            @"branding": @{
                @"titleKey": @"MODERN_SETTINGS_BRANDING_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_BRANDING_SUBTITLE",
                @"settings": @[
                    @{
                        @"key": @"restore_twitter_names",
                        @"default": @([BHTManager isTwitterBranded]),
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"refresh_pill_label",
                        @"default": @([BHTManager isTwitterBranded]),
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"color_twitter_icon_in_top_bar",
                        @"default": @([BHTManager isTwitterBranded]),
                        @"type": @"toggle"
                    }
                ]
            },
            @"experimental": @{
                @"titleKey": @"MODERN_SETTINGS_EXPERIMENTAL_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_EXPERIMENTAL_SUBTITLE",
                @"settings": @[]
            },
            @"web": @{
                @"titleKey": @"MODERN_SETTINGS_WEB_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_WEB_SUBTITLE",
                @"settings": @[
                    @{
                        @"type": @"compactButton",
                        @"key": @"sharing_domain",
                        @"action": @"showSharingDomainPrompt:",
                        @"prefKeyForSubtitle": @"sharing_domain",
                        @"subtitleDefault": @"x.com",
                        @"sectionKey": @"SETTINGS_SECTION_LINKS_SHARING"
                    },
                    @{@"key": @"strip_share_tracking",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_LINKS_SHARING"},
                    @{@"key": @"expand_tco_links",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_LINKS_SHARING"},
                    @{@"key": @"always_open_safari",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_BROWSER"},
                    @{@"key": @"new_inapp_webview",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_BROWSER"}
                ]
            },
            @"debug": @{
                @"titleKey": @"MODERN_SETTINGS_DEBUG_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_DEBUG_SUBTITLE",
                @"settings": @[
                    @{
                        @"titleKey": @"EXPORT_COMPATIBILITY_REPORT_TITLE",
                        @"action": @"exportCompatibilityReport:",
                        @"type": @"button"
                    },
                    @{@"key": @"flex_twitter",
                      @"default": @NO,
                      @"type": @"toggle"}
                ]
            }
        };
    });
    return pages;
}

static NSDictionary<NSString*, NSDictionary*>* BHTSettingsIndex(void) {
    static NSDictionary<NSString*, NSDictionary*>* index;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<NSString*, NSDictionary*>* map =
            [NSMutableDictionary dictionary];
        for (NSDictionary* page in BHTSettingsPages().allValues) {
            for (NSDictionary* setting in page[@"settings"]) {
                NSString* key = setting[@"key"];
                if (key) {
                    map[key] = setting;
                }
            }
        }
        index = [map copy];
    });
    return index;
}

@implementation BHTSettings

#pragma mark - Migration

// One-time migration of preferences saved under the old (inconsistent) key
// names to the normalised keys, so existing installs keep their settings.
+ (void)load {
    [self migrateUndoTweetToggle];

    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"nfb_key_migration_v2_done"]) {
        NSDictionary<NSString*, NSString*>* x129RenamedKeys = @{
            @"dis_VODCaptions": @"disable_video_captions",
            @"strip_tracking_params": @"strip_share_tracking",
            // X 12.9 exposes bio translation through the same native Grok
            // translation controls as posts, polls and Community Notes.
            @"bio_translate": @"enable_grok_translations",
        };
        [x129RenamedKeys enumerateKeysAndObjectsUsingBlock:^(
                            NSString* oldKey, NSString* newKey, BOOL* stop) {
            id value = [defaults objectForKey:oldKey];
            if (value != nil && [defaults objectForKey:newKey] == nil) {
                [defaults setObject:value forKey:newKey];
            }
            if (value != nil) {
                [defaults removeObjectForKey:oldKey];
            }
        }];
        [defaults setBool:YES forKey:@"nfb_key_migration_v2_done"];
    }

    if ([defaults boolForKey:@"nfb_key_migration_v1_done"]) {
        return;
    }

    NSDictionary<NSString*, NSString*>* renamedKeys = @{
        @"dis_rtl": @"disable_rtl",
        @"showScollIndicator": @"show_scroll_indicator",
        @"en_font": @"custom_fonts",
        @"dw_v": @"download_videos",
        @"video_layer_caption": @"disable_video_captions",
        @"autoHighestLoad": @"auto_highest_load",
        @"follow_con": @"follow_confirm",
        @"CopyProfileInfo": @"copy_profile_info",
        @"disableArticles": @"disable_articles",
        @"disableHighlights": @"disable_highlights",
        @"TweetToImage": @"tweet_to_image",
        @"like_con": @"like_confirm",
        @"tweet_con": @"tweet_confirm",
        @"disableSensitiveTweetWarnings": @"disable_sensitive_tweet_warnings",
        @"no_his": @"no_history",
        @"openInBrowser": @"always_open_safari",
        @"reply_sorting_enabled": @"reply_sorting",
        @"ios_in_app_article_webview_enabled": @"new_inapp_webview",
        @"tweet_url_host": @"sharing_domain",
    };

    // These old names double as Twitter's own feature-switch keys, so copy the
    // value across but leave the original in place rather than risk removing it.
    NSSet<NSString*>* sharedWithTwitter = [NSSet setWithArray:@[
        @"reply_sorting_enabled",
        @"ios_in_app_article_webview_enabled",
    ]];

    [renamedKeys enumerateKeysAndObjectsUsingBlock:^(
                     NSString* oldKey, NSString* newKey, BOOL* stop) {
        id value = [defaults objectForKey:oldKey];
        if (value == nil) {
            return;
        }
        if ([defaults objectForKey:newKey] == nil) {
            [defaults setObject:value forKey:newKey];
        }
        if (![sharedWithTwitter containsObject:oldKey]) {
            [defaults removeObjectForKey:oldKey];
        }
    }];

    [defaults setBool:YES forKey:@"nfb_key_migration_v1_done"];
}

// The Undo Tweet on/off toggle was merged into the timeout picker, where a
// timeout of 0 means off. Carry a prior "off" state across as a 0 timeout.
+ (void)migrateUndoTweetToggle {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"nfb_undo_timeout_migration_done"]) {
        return;
    }

    id oldToggle = [defaults objectForKey:@"undo_tweet"];
    if (oldToggle != nil && ![oldToggle boolValue] &&
        [defaults objectForKey:@"undo_tweet_timeout"] == nil) {
        [defaults setInteger:0 forKey:@"undo_tweet_timeout"];
    }
    [defaults removeObjectForKey:@"undo_tweet"];
    [defaults setBool:YES forKey:@"nfb_undo_timeout_migration_done"];
}

#pragma mark - Accessors

+ (NSArray<NSDictionary*>*)settingsForPage:(NSString*)pageKey {
    return pageKey ? BHTSettingsPages()[pageKey][@"settings"] : nil;
}

+ (NSString*)titleKeyForPage:(NSString*)pageKey {
    return pageKey ? BHTSettingsPages()[pageKey][@"titleKey"] : nil;
}

+ (NSString*)subtitleKeyForPage:(NSString*)pageKey {
    return pageKey ? BHTSettingsPages()[pageKey][@"subtitleKey"] : nil;
}

+ (NSDictionary*)settingForKey:(NSString*)key {
    NSDictionary* setting = key ? BHTSettingsIndex()[key] : nil;
    if (setting) return setting;
    // Retain defaults for the two beta.8 keys after moving their user-facing
    // controls into the navigation editors.
    if ([key isEqualToString:@"enable_likes_tab"]) {
        return @{@"key": key, @"default": @NO};
    }
    if ([key isEqualToString:@"likes_media_waterfall"]) {
        return @{@"key": key, @"default": @YES};
    }
    return nil;
}

+ (BOOL)boolForKey:(NSString*)key {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (value != nil) {
        return [value boolValue];
    }
    return [[self settingForKey:key][@"default"] boolValue];
}

+ (NSInteger)integerForKey:(NSString*)key {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (value != nil) {
        return [value integerValue];
    }
    return [[self settingForKey:key][@"default"] integerValue];
}

@end
