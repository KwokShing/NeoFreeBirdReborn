# X 12.9 feature audit

Target inspected during the compatibility pass: X 12.9 (build 10), bundle
`com.atebits.Tweetie2`, minimum iOS 15.0. The supplied IPA contained 62 Mach-O
images and no encrypted executable images.

This branch uses NeoFreeBird v6's modular source layout while keeping the X
12.9-specific hook decisions from the earlier BHTwitter audit. All user-visible
new behavior has a setting. Compatibility shims and runtime reporting are the
only unconditional code paths.

## Safety boundary

- No attestation bypass is implemented.
- No login replacement, cookie harvesting, session-token extraction, or web
  GraphQL credential reuse is compiled.
- Subscription state is not spoofed. Native/server-backed eligibility remains
  authoritative.
- Tweet source labels use X 12.9's on-device `TFNTwitterStatus-composerSource`
  path.

## Ad blocking

The blocker is deliberately layered because X now inserts promoted material at
several points:

1. `TFNTwitterAPICommandContext-allowPromotedContent` prevents promoted results
   from being requested where the API honors the flag.
2. X 12.9 feature switches disable SSP, dynamic-video, unified-card, article
   webview, and promoted-profile paths.
3. `TFNItemsDataViewAdapterRegistry-dataViewAdapterForItem:` rejects promoted
   statuses plus the exact Google-native, `PromotableTrend`, immersive-card,
   and Explore-promoted models before adapter creation.
4. `T1PlayerMediaEntitySessionProducible` keeps the real playable media entity
   but removes only its separate `promotedContent` session payload.
5. `TFSTwitterSspMetadata` disables preroll eligibility and ad-tag URLs.
6. `TFNItemsDataViewController` section filtering removes promoted statuses,
   promoted Explore trends/heroes, and their orphaned module chrome without
   leaving blank cells.
7. `TFNTwitterStatus` ad flags, SSP metadata, dynamic-ad permission, and
   `isCardHidden` form the final card/video fallback.

The obsolete `TFSTwitterAPICommandAccountStateProvider-allowPromotedContent`
hook is intentionally absent.

## Feature matrix

Status meanings:

- **Updated**: retargeted or behavior corrected for the newer app.
- **Ported**: adopted from the newer NeoFreeBird/Theacrat architecture.
- **Combined**: uses both the X 12.9-specific and newer modular approaches.
- **Runtime check**: compiled defensively and included in the exported report;
  it needs an on-device pass because the private Swift surface can move.

| Area | Setting | Status | X 12.9 implementation |
|---|---|---|---|
| General | `hide_promoted` | Combined | Layered request, model, section, player, metadata, status, and feature-switch blocker described above |
| General | `hide_premium_offer` | Updated | Upsells only; genuine subscription state is preserved |
| General | `padlock` | Ported | In-memory relock and app-switcher cover |
| General | `no_tab_bar_hiding` | Updated | X 12.9 pin/collapse capabilities plus ratio clamp on iPhone; iPad keeps its native adaptive rail width and fullscreen hides remain intact |
| General | `disable_rtl` | Ported | Rebuilds paragraph styles with LTR direction |
| General | `strip_share_tracking` | Updated | Removes `s`/`t` parameters only when enabled |
| General | `expand_tco_links` | Updated | No longer unconditional |
| General | `show_scroll_indicator` | Ported | Typed account feature-switch accessor |
| Appearance | theme and app icon controls | Updated | Modern settings pages and guarded live theme reapply; Apollo-inspired and classic Twitter presets carry coordinated light/dark background, tweet/card/status/tab/unread/surface, elevated, text, secondary-text, separator, and accent colors. Themes attach to the validated active, Twitter, and TFNUI palette providers. A narrow public named-color bridge covers only matching neutral assets from `XColorEngine_XColorEngine.bundle`, which keeps both Objective-C XDS and Swift Following/detail surfaces themed while preserving destructive, media-overlay, and other context-sensitive native colors. NeoFreeBird uses X's guarded native palette apply and observes—never synthesizes—its private dynamic-colors-did-reload event. A coalesced, bounded loaded-view-tree refresh runs only when that native event is absent or a replacement provider is attached after its synchronous observers, so changes apply without a force quit and never add scrolling-path work. Immutable per-provider generation/dark snapshots prevent mixed or stale colors while keeping hot palette reads cheap, and weak tracking clears every still-live provider when Native Blue is restored. Sideloaded/TrollStore packages preserve X's stock icon choices and add the supplied loose Twitter-bird alternate |
| Settings | search and preference profiles | New | Localized global search covers setting titles, details, subsections, and categories; versioned JSON export/import uses a strict NeoFreeBird-only preference allow-list and never includes Twitter account state |
| Appearance | custom navigation | Combined | Captures/reorders native tab entries; Grok remains native while opt-in Likes is an independent movable entry; selected editor tiles and the preview row both support drag reordering |
| Appearance | sidebar navigation | New/runtime check | Reorders or hides Profile, Blue, History, Communities, News, Lists, Chat, Notifications, Spaces, and Follower Requests through X 12.9's observable `TwitterDash` array setters while preserving unknown/native rows |
| Appearance | `tab_bar_theming` | Ported | Native selected/unselected colors |
| Appearance | `restore_tab_labels` | Updated | Current `T1TabView` title path; the Likes carrier is relabeled before its first selection |
| Appearance | `restore_launch_animation` | Updated | No longer forced on; replaces the animated X with the bundled Twitter bird and removes only the X-shaped reveal mask |
| Appearance | `restore_refresh_sounds` | Updated | No longer always on |
| Appearance | `custom_fonts` | Updated | Persists concrete PostScript faces, migrates former family-name selections, and covers both legacy `TFNUIDefaultFontGroup` and X 12.9's SwiftUI `XFontCatalog` |
| Timeline | `hide_who_to_follow` | Combined | Section model filter plus targeted iPad controller |
| Timeline | `hide_timeline_prompts` | Combined | Prompt/module filter plus targeted update pill |
| Timeline | `hide_discover_more` | Updated | Exact related-post entry IDs; no broad footer/header deletion |
| Timeline | `hide_topics` | Updated | Exact topic banners and topic-marked prompts |
| Timeline | `hide_topics_to_follow` | Updated | Exact profile topic collections/suggestion identifiers |
| Timeline | `hide_spaces` | Updated | Fleet-line visibility seam; runtime checked |
| Timeline | `hide_custom_timelines` | Updated | Hides without persisting an empty pinned list |
| Timeline | `remember_timeline_tab` | Updated | Disabled preference now leaves X's native value alone |
| Timeline | `enable_likes_tab` | New/runtime check | Independent bottom destination backed by native Likes history; opens raw Activity History tab 4 on X 12.9, guards against delayed native offset restoration on its first presentation without a loading cover, and preserves position on later tab switches |
| Timeline | `likes_media_waterfall` | New/runtime check | Newest-first native-section media extraction, continuous pagination, medium-size grid previews plus original-quality close-up/download URLs, highest-bitrate MP4 selection, 2–5 columns, a window-level edge-to-edge viewer on iPhone and iPad, a Posts/Media selector with native segmented-control artwork and a guarded 32-point minimum navigation-title height, Apple-style contextual Photo/Video/GIF previews and action menus in both surfaces (with the guarded TFN sheet retained only as a legacy fallback), and percent-driven modal swipe-down dismissal |
| Grok | `enable_grok_translations` | Updated | Manual translation gates are no longer forced globally |
| Grok | `hide_grok_analyze` | Updated | Backend switch plus current button paths |
| Grok | `hide_grok_sidebar` | Ported | Current navigation model filtering |
| Grok | `hide_grok_create` | Updated | Composer, photo, timeline and immersive gates |
| Grok | `disable_auto_translate` | Ported | Leaves manual translation available |
| Media | `download_videos` | Updated | Modern MP4/HLS/GIF quality sheet across X 12.9's `MultiMediaView`, separate carousel, legacy inline-video, overflow, and exact native media-action path; replaces X's Blue-gated duplicate with working Download Video/GIF and temporary-file Share actions |
| Media | media action editors | New/runtime check | Independent Photo, Video, and GIF tap-to-hide/drag-to-reorder editors; recognized native actions are reordered safely, explicitly tagged Neo actions win duplicate IDs, and unknown/future X actions plus Cancel are preserved |
| Media | `dm_media_downloads` | Updated/runtime check | Default-off opt-in; Swift attachment view and save-plugin availability are reported |
| Media | `voice_creation_enabled` | Updated/runtime check | X 12.9 keyed voice-post and voice-reply gates |
| Media | `no_voice_messages` | Corrected/runtime check | Turns legacy DM and XChat voice creation/rendering off when enabled |
| Media | `old_compose_bar` | Corrected/runtime check | Disables the XChat v2 composer when enabled |
| Media | `dm_reply_later_enabled` | Updated/runtime check | Native keyed gate; server/account support remains authoritative |
| Media | `media_upload_4k_enabled` | Updated/runtime check | Legacy and X Lite 4K keyed gates; upload server limits remain authoritative |
| Media | `custom_voice_upload` | Updated | Previously always on; now opt-in |
| Media | `direct_save` | Ported | Share sheet or direct Photos save |
| Media | `disable_video_captions` | Ported | Current switch family |
| Media | `auto_highest_load` | Updated | X 12.9 `isLoadingHighestQualityImageVariantPermitted` plus timeline image and slideshow paths; default on |
| Media | `force_highest_video_quality` | New/runtime check | Sorts variants and prefers the highest MP4 primary URL |
| Media | `force_tweet_full_frame` | Updated | Photo attachment adapter display type |
| Media | `restore_video_timestamp` | Ported | Current immersive progress plugin |
| Media | `disable_immersive_scroll` | Ported | Feature threshold and gesture fallback |
| Profile | `follow_confirm` | Ported | Current `TUIFollowControl` action |
| Profile | `copy_profile_info` | Ported | Native-style profile action provider |
| Profile | `disable_articles` | Corrected | Off now preserves X's native gate |
| Profile | `disable_highlights` | Corrected | Off now preserves X's native gate |
| Profile | `hide_blue_verified` | Updated | User, source, typeahead, DM and cached status-model paths |
| Profile | `hide_follow_button` | Updated | Current author view |
| Profile | `restore_follow_button` | Updated | Keeps genuine active subscriptions intact |
| Profile | `square_avatars` | Ported | Live avatar/image/shadow restyling |
| Profile | `full_profile_counts` | Updated | Previously always on; now opt-in |
| Profile/Grok | bio translation | Combined | Old `bio_translate` preference migrates to native Grok translations; only X 12.9's available canonical-user selector is hooked |
| Tweets | `enable_edit_tweet` | Updated | Exposes native UI only; server eligibility still applies |
| Tweets | undo timeout | Ported | Unified timeout picker and old-key migration |
| Tweets | `tweet_confirm` / `like_confirm` | Updated | Current composer plus X 12.9 `TTAStatusInlineActionButton-didTap`, slideshow, and immersive actions |
| Tweets | `tweet_to_image` | Ported | Long-press share with table/collection fallback |
| Tweets | inline-button hides | Updated | `TTAStatusInlineAnalyticsButton` and current class list |
| Tweets | sensitive/age controls | Ported | Explicit toggles; age bypass defaults off |
| Tweets | `reply_sorting` | Corrected | Covers `reply_sorting_enabled` and X 12.9's minimal-detail v2 switch; off preserves native behavior |
| Tweets | `restore_reply_context` | Corrected | Off leaves X's native switch untouched |
| Tweets | `restore_tweet_labels` | Updated | Native `composerSource`; no account/session web request |
| Search | `no_history` | Updated | Read and write paths on recent-search datastore |
| Search | `hide_trends` | Combined | Phone Explore controller and targeted iPad sidebar |
| Search | `hide_trend_videos` | Ported | Explore carousel model filter |
| Web | sharing domain | Ported | Applied independently of tracking removal |
| Web | `always_open_safari` | Updated | Keeps login/2FA flows in-app |
| Web | `new_inapp_webview` | Ported | Current feature-switch path |
| Branding | terminology, pill label, bird logos | Updated | Modern bundle/text/tab paths; the Home title, adaptive iPad rail, and optional classic launch animation use one bundled tintable bird, while sideloaded/TrollStore packaging sets localized display names to Twitter and registers the supplied bird as a loose alternate icon without replacing stock icons |
| Privacy | screenshot toggles | Ported/updated | Detection and branding cleanup are opt-in and grouped with app lock |
| Debug | FLEX | Ported | Explicit toggle |
| Debug | compatibility report | New | Exports a non-sensitive JSON runtime probe report |

## Selected newer-source ports

Worthwhile pieces taken from the newer Theacrat/NeoFreeBird work include the
central settings registry and migration, structural timeline filtering, modern
Swift DM media discovery, native tab-entry ordering, configurable undo timing,
Grok surface cleanup, reply context restoration, video timestamps, square
avatars, full count formatting, and the modular build/FFmpeg layout.

From the Orion-derived changes, this branch keeps only targeted versions of the
refresh-pill, iPad trends/recommendations, and screenshot-overlay cleanup. It
does not use the broad global `UIView-didMoveToWindow` hook, and it does not
change the FFmpeg TLS backend without a demonstrated build need.

## Intentionally retired or deferred

- The old custom DM background hooked
  `T1DirectMessageConversationEntriesViewController`, a controller removed by
  X's Swift DM rewrite. A global view/background hook would be fragile and could
  obscure message content, so it is not ported.
- The dormant `always_following_page` preference was never exposed in the last
  BHTwitter settings screen. The X 12.9 audit found the current
  `selectTimelineVariant:shouldRefresh:` path but not a stable enum value; the
  branch does not guess one.
- Web reply/login replacements, stored cookies, embedded credentials,
  subscription spoofing, and attestation evasion remain excluded.

## Device validation

After launching a test build, open:

`Settings > NeoFreeBird > Debug > Export compatibility report`

The JSON is also written to:

`Library/Caches/BHTwitter-X12.9-Compatibility.json`

The first device pass should focus on Photo/Video/GIF action ordering, Download
and temporary-file Share, first-open Likes position, waterfall and close-up
contextual previews, interactive swipe-down cancellation/completion, theme
presets in both light and dark appearance, switching back to Native Blue,
profile round-tripping, global settings search, the single iPad
rail bird and pre-injection launch bird, sidebar hiding/reordering, the native
Likes post route, DM save-action plugin, Home/Spaces Swift aliases,
source-label model access, highest-video preference, and the Likes viewer's
`viewerFullScreenCoverage` result after opening media. The report's
privacy-safe `likesRuntime` section
records root creation, selection/reset counts, media count, and URL acceptance.
Missing private selectors degrade to native behavior and are listed in the
report rather than being guessed silently.

Beta 14 also restricts launch cleanup to NeoFreeBird's own temporary directory,
uses asynchronous Photos saves, scopes the font-picker customization, avoids
stacked app-lock presentations, caches and cancels settings-avatar requests,
and debounces automatic compatibility reports off the main thread.

Beta 15 introduced a 128 MB cost-aware decoded-image cache, ImageIO
downsampling, and deferred pager refreshes during horizontal transitions. Beta
16 added Apple-style contextual previews and menus for consistent iPhone/iPad
media actions plus coalesced image requests. Beta 17 targets the guarded iPad
rail-header image path, adds complete light/dark theme palettes, and presents
waterfall close-ups at full app-window size. Beta 18 expands coverage to X
12.9's dark timeline, tweet, card, modal, and capsule-tab palette tokens,
reapplies presets through its guarded dynamic-color refresh paths, and changes
waterfall thumbnails to complete-image aspect fit. Beta 19 also attaches those
roles to X's separate Twitter/TFNUI providers, themes repost and top/bottom tab
chrome, and makes the Likes waterfall adapt its tile height and span from the
decoded media dimensions. Beta 20 adds the narrowly scoped XDS named-color path
used by both Objective-C and Swift Following, Tweet Details, and reused
timeline cells, and restores the Likes Posts/Media selector after native
navigation rebuilds. Beta 21 removes the one-pixel segmented-control artwork
that could collapse that selector on iPhone, preserves native sizing with a
minimum intrinsic height, and exports its live geometry for diagnosis. Beta 22
stops painting X's independently mounted tab-bar host and divider, and retains
the native tab-bar appearance's background material while theming only its
items. This keeps the selected palette without leaving an opaque strip when X
collapses the lower navigation controls during scrolling. Full themes hook only
validated zero-argument color getters on X's concrete provider instances plus
the exact neutral XColorEngine named assets, cache provider colors away from
scrolling paths, and fall through to preserved native implementations when
Native Blue or a standalone accent is selected. The
close-up viewer is forced to the app window instead of an
adaptive iPad column while keeping its safe-area controls, rotation, paging,
zoom, video playback, and percent-driven dismissal. Equal URL/size-bucket
requests are coalesced across prefetching, visible cells, contextual previews,
and the close-up viewer; each consumer can cancel independently, and the shared
transfer is cancelled only when no consumer remains.
