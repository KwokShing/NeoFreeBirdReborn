//
//  ModernSettingsViewController.m
//  NeoFreeBird
//
//  Created by BandarHelal on 25/11/2021.
//

#import "Settings/ModernSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "Settings/ModernSettingsCells.h"
#import "Settings/ModernSettingsPageViewController.h"
#import "Settings/Pages/AppearanceSettingsViewController.h"
#import "Settings/Pages/DebugSettingsViewController.h"
#import "Settings/Pages/MediaDownloadsSettingsViewController.h"
#import "Settings/Pages/ProfilesSettingsViewController.h"
#import "Settings/Pages/PresetSettingsViewController.h"
#import "Settings/Pages/TimelinesSettingsViewController.h"
#import "Settings/Pages/TweetsSettingsViewController.h"
#import "Settings/Pages/WebSettingsViewController.h"
#import "ThemeColor/BHTThemePresets.h"
#import "ThemeColor/Palette.h"

static char kBHTRepresentedAvatarURLKey;
static char kBHTAvatarTaskKey;
static char kBHTAvatarRequestTokenKey;

static NSCache<NSString*, UIImage*>* BHTDeveloperAvatarCache(void) {
    static NSCache<NSString*, UIImage*>* cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 32;
    });
    return cache;
}

@interface ModernSettingsViewController ()
    <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating,
     UISearchControllerDelegate>
@property (nonatomic, strong) TFNTwitterAccount* account;
@property (nonatomic, strong) UITableView* tableView;
@property (nonatomic, strong) NSArray* sections;
@property (nonatomic, strong) UISearchController* settingsSearchController;
@property (nonatomic, copy) NSArray<NSDictionary*>* settingsSearchIndex;
@property (nonatomic, copy) NSArray<NSDictionary*>* filteredSettingsResults;
@property (nonatomic, strong) NSArray* developerCells;
@property (nonatomic, strong) NSArray* coolKidsCells;
@property (nonatomic, strong) NSArray* specialThanksCells;
@property (nonatomic, strong) NSArray* officialPageCells;
- (void)themeDidChange:(NSNotification*)notification;
@end

@implementation ModernSettingsViewController

#pragma mark - Section Headers

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    if ([self isSettingsSearchActive]) {
        return nil;
    }
    if (section == 0) {
        UIView* headerView = [[UIView alloc] init];
        headerView.backgroundColor = [Palette currentBackgroundColor];

        UILabel* subtitleLabel = [[UILabel alloc] init];
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subtitleLabel.text = [[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_DETAIL"];
        subtitleLabel.numberOfLines = 0;
        subtitleLabel.textAlignment = NSTextAlignmentLeft;

        id fontGroup = [BHTManager sharedFontGroup];
        subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];

        subtitleLabel.textColor = [Palette currentSecondaryTextColor];

        [headerView addSubview:subtitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [subtitleLabel.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor
                                                        constant:20],
            [subtitleLabel.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor
                                                         constant:-20],
            [subtitleLabel.topAnchor constraintEqualToAnchor:headerView.topAnchor
                                                    constant:16],
            [subtitleLabel.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor
                                                       constant:-16]
        ]];

        return headerView;
    } else if (section == 1) {
        return [self headerViewWithTitle:[[BHTBundle sharedBundle]
                                             localizedStringForKey:@"DEVELOPER_SECTION_HEADER_TITLE"]];
    } else if (section == 2) {
        return [self headerViewWithTitle:[[BHTBundle sharedBundle]
                                             localizedStringForKey:@"COOL_KIDS_SECTION_HEADER_TITLE"]];
    } else if (section == 3) {
        return [self
            headerViewWithTitle:[[BHTBundle sharedBundle]
                                    localizedStringForKey:@"SPECIAL_THANKS_SECTION_HEADER_TITLE"]];
    } else if (section == 4) {
        return [self headerViewWithTitle:
                         [[BHTBundle sharedBundle]
                             localizedStringForKey:@"FOLLOW_OFFICIAL_PAGE_SECTION_HEADER_TITLE"]];
    }
    return nil;
}

- (UIView*)headerViewWithTitle:(NSString*)title {
    UIView* headerView = [[UIView alloc] init];
    headerView.backgroundColor = [Palette currentBackgroundColor];

    UILabel* titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;

    id fontGroup = [BHTManager sharedFontGroup];
    titleLabel.font = [fontGroup performSelector:@selector(headline1BoldFont)];

    titleLabel.textColor = [Palette currentTextColor];

    [headerView addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor
                                                 constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor
                                                  constant:-20],
        [titleLabel.topAnchor constraintEqualToAnchor:headerView.topAnchor
                                             constant:32],
        [titleLabel.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor
                                                constant:-16]
    ]];

    return headerView;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    if ([self isSettingsSearchActive]) {
        return CGFLOAT_MIN;
    }
    if (section == 0 || section == 1 || section == 2 || section == 3 || section == 4) {
        return UITableViewAutomaticDimension;
    }
    return 0;
}

#pragma mark - Section Footers

- (UIView*)tableView:(UITableView*)tableView viewForFooterInSection:(NSInteger)section {
    if ([self isSettingsSearchActive]) {
        return nil;
    }
    if (section == 0) {
        UIView* separator = [[UIView alloc] initWithFrame:CGRectZero];
        separator.backgroundColor = [Palette currentSeparatorColor];
        return separator;
    }
    return nil;
}

- (CGFloat)tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section {
    if ([self isSettingsSearchActive]) {
        return CGFLOAT_MIN;
    }
    if (section == 0) {
        return 1.0 / UIScreen.mainScreen.scale;
    }
    return CGFLOAT_MIN;
}

#pragma mark - Lifecycle & Setup

- (instancetype)initWithAccount:(TFNTwitterAccount*)account {
    self = [super init];
    if (self) {
        _account = account;
        [self setupSections];
        [self setupDeveloperCells];
    }
    return self;
}

- (void)setupSections {
    self.sections = @[
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAYOUT_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAYOUT_SUBTITLE"],
            @"icon": @"settings_stroke",
            @"action": @"showLayoutSettings",
            @"pageKey": @"general"
        },
        @{
            @"title":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_APPEARANCE_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_APPEARANCE_SUBTITLE"],
            @"icon": @"paintbrush_stroke",
            @"action": @"showAppearanceSettings",
            @"pageKey": @"appearance"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_GROK_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_GROK_SUBTITLE"],
            @"icon": @"grok_icon_stroke",
            @"action": @"showGrokSettings",
            @"pageKey": @"grok"
        },
        @{
            @"title":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TIMELINES_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TIMELINES_SUBTITLE"],
            @"icon": @"home_stroke",
            @"action": @"showTimelinesSettings",
            @"pageKey": @"timelines"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWEETS_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWEETS_SUBTITLE"],
            @"icon": @"quill",
            @"action": @"showTweetsSettings",
            @"pageKey": @"tweets"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_MEDIA_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_MEDIA_SUBTITLE"],
            @"icon": @"media_tab_stroke",
            @"action": @"showDownloadsSettings",
            @"pageKey": @"media_downloads"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PROFILES_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PROFILES_SUBTITLE"],
            @"icon": @"account",
            @"action": @"showProfilesSettings",
            @"pageKey": @"profiles"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_SEARCH_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_SEARCH_SUBTITLE"],
            @"icon": @"search_stroke",
            @"action": @"showSearchSettings",
            @"pageKey": @"search"
        },
        @{
            @"title": [[BHTBundle sharedBundle]
                localizedStringForKey:@"MODERN_SETTINGS_PRESETS_TITLE"],
            @"subtitle": [[BHTBundle sharedBundle]
                localizedStringForKey:@"MODERN_SETTINGS_PRESETS_SUBTITLE"],
            @"icon": @"settings_stroke",
            @"action": @"showPresetSettings",
            @"pageKey": @"presets"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_WEB_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_WEB_SUBTITLE"],
            @"icon": @"globe_stroke",
            @"action": @"showWebSettings",
            @"pageKey": @"web"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_BRANDING_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_BRANDING_SUBTITLE"],
            @"icon": @"hash_stroke",
            @"action": @"showBrandingSettings",
            @"pageKey": @"branding"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_DEBUG_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_DEBUG_SUBTITLE"],
            @"icon": @"code",
            @"action": @"showDebugSettings",
            @"pageKey": @"debug"
        }
    ];
}

- (void)setupDeveloperCells {
    self.developerCells = @[
        @{
            @"title": @"aridan",
            @"username": @"actuallyaridan",
            @"avatarURL": @"https://unavatar.io/x/actuallyaridan?fallback=https://neofreebird.com/"
                          @"images/actuallyaridan.png",
            @"userID": @"1351218086649720837"
        },
        @{
            @"title": @"Thea 🐾",
            @"username": @"nyaathea",
            @"avatarURL": @"https://unavatar.io/github/nyathea?fallback=https://neofreebird.com/images/"
                          @"theameoww.png",
            @"userID": @"1541742676009226241"
        },
        @{
            @"title": @"timi2506",
            @"username": @"timi2506",
            @"avatarURL": @"https://unavatar.io/github/timi2506?fallback=https://neofreebird.com/images/"
                          @"timi2506.png",
            @"userID": @"1684856685486063616"
        }
    ];

    self.coolKidsCells = @[
        @{
            @"title": @"Eevee",
            @"username": @"whoeevee1",
            @"avatarURL": @"https://unavatar.io/github/whoeevee?fallback=https://neofreebird.com/images/"
                          @"whoeevee.png",
            @"userID": @"1547956497342115844"
        },
        @{
            @"title": @"zxcvbn",
            @"username": @"zxxvbn0",
            @"avatarURL":
                @"https://unavatar.io/x/zxxvbn0?fallback=https://neofreebird.com/images/zxxvbn0.png",
            @"userID": @"1678444396717514760"
        }
    ];

    self.specialThanksCells = @[
        @{
            @"title": @"BandarHelal",
            @"username": @"BandarHL",
            @"avatarURL":
                @"https://unavatar.io/x/BandarHL?fallback=https://neofreebird.com/images/BandarHL.png",
            @"userID": @"827842200708853762"
        },
        @{
            @"title": @"YouGottaBillieve",
            @"username": @"ugottabillieve",
            @"avatarURL": @"https://unavatar.io/x/ugottabillieve?fallback=https://neofreebird.com/"
                          @"images/ugottabillieve.png",
            @"userID": @"1616194182187732992"
        }
    ];

    self.officialPageCells = @[@{
        @"title": @"NeoFreeBird",
        @"username": @"NeoFreeBird",
        @"avatarURL": @"https://unavatar.io/x/NeoFreeBird?fallback=https://neofreebird.com/images/"
                      @"NeoFreeBird.png",
        @"userID": @"1878595268255297537"
    }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNavigationBar];
    [self setupSettingsSearch];
    [self setupTableView];
    [self setupLayout];
    [self setupFooterLabel];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChange:)
                                                 name:UIContentSizeCategoryDidChangeNotification
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
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self themeDidChange:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)contentSizeCategoryDidChange:(NSNotification*)notification {
    [self.tableView reloadData];
}

- (void)themeDidChange:(NSNotification*)notification {
    [Palette invalidateCustomAccentColorCache];
    self.view.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.tableFooterView.backgroundColor =
        [Palette currentBackgroundColor];
    [self setupFooterLabel];
    [self.tableView reloadData];
}

- (void)setupNavigationBar {
    self.view.backgroundColor = [Palette currentBackgroundColor];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView")
            titleViewWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_TITLE"]
                      subtitle:self.account.displayUsername];
    } else {
        self.title = [[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_TITLE"];
    }
}

- (void)setupSettingsSearch {
    UISearchController* search =
        [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.delegate = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.autocapitalizationType =
        UITextAutocapitalizationTypeNone;
    search.searchBar.placeholder = [[BHTBundle sharedBundle]
        localizedStringForKey:@"SETTINGS_SEARCH_PLACEHOLDER"];
    self.settingsSearchController = search;
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    [self buildSettingsSearchIndex];
}

- (void)buildSettingsSearchIndex {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    NSMutableArray<NSDictionary*>* index = [NSMutableArray array];
    NSMutableDictionary<NSString*, NSDictionary*>* pagesByKey =
        [NSMutableDictionary dictionary];

    for (NSDictionary* page in self.sections) {
        NSString* pageKey = page[@"pageKey"];
        if (pageKey) pagesByKey[pageKey] = page;
        NSString* searchText =
            [@[page[@"title"] ?: @"", page[@"subtitle"] ?: @"",
               pageKey ?: @""]
                componentsJoinedByString:@" "];
        [index addObject:@{
            @"kind": @"page",
            @"pageKey": pageKey ?: @"",
            @"identifier": pageKey ?: @"",
            @"title": page[@"title"] ?: @"",
            @"subtitle": page[@"subtitle"] ?: @"",
            @"icon": page[@"icon"] ?: @"settings_stroke",
            @"searchText": searchText
        }];
    }

    for (NSDictionary* setting in [BHTSettings allSearchableSettings]) {
        NSString* pageKey = setting[@"pageKey"];
        NSDictionary* page = pagesByKey[pageKey];
        if (!page) continue;

        NSString* key = setting[@"key"];
        NSString* titleKey = setting[@"titleKey"];
        if (!titleKey && key.length > 0) {
            titleKey =
                [NSString stringWithFormat:@"%@_TITLE", key.uppercaseString];
        }
        NSString* title = [bundle localizedStringForKey:titleKey];
        if (title.length == 0 || [title isEqualToString:titleKey]) continue;

        NSString* detail = @"";
        if (key.length > 0) {
            NSString* detailKey =
                [NSString stringWithFormat:@"%@_DETAIL",
                                           key.uppercaseString];
            NSString* localized = [bundle localizedStringForKey:detailKey];
            if (![localized isEqualToString:detailKey]) detail = localized;
        }
        NSString* sectionTitle = @"";
        NSString* sectionKey = setting[@"sectionKey"];
        if (sectionKey.length > 0) {
            sectionTitle = [bundle localizedStringForKey:sectionKey];
        }
        NSString* categoryTitle = page[@"title"] ?: @"";
        NSString* categorySubtitle = page[@"subtitle"] ?: @"";
        NSString* resultSubtitle =
            detail.length > 0
                ? [NSString stringWithFormat:@"%@ — %@", categoryTitle,
                                             detail]
                : categoryTitle;
        NSString* identifier = key ?: setting[@"titleKey"];
        NSString* searchText =
            [@[title ?: @"", detail ?: @"", sectionTitle ?: @"",
               categoryTitle ?: @"", categorySubtitle ?: @"", key ?: @""]
                componentsJoinedByString:@" "];
        [index addObject:@{
            @"kind": @"setting",
            @"pageKey": pageKey,
            @"identifier": identifier ?: @"",
            @"title": title,
            @"subtitle": resultSubtitle,
            @"icon": page[@"icon"] ?: @"settings_stroke",
            @"searchText": searchText
        }];
    }

    NSDictionary* presetsPage = pagesByKey[@"presets"];
    NSString* presetsCategory = presetsPage[@"title"] ?: @"";
    NSString* themeSection =
        [bundle localizedStringForKey:@"THEME_PRESETS_SECTION_TITLE"];
    for (NSDictionary* preset in [BHTThemePresets availablePresets]) {
        NSString* title =
            [bundle localizedStringForKey:preset[@"titleKey"]];
        NSString* detail =
            [bundle localizedStringForKey:preset[@"detailKey"]];
        [index addObject:@{
            @"kind": @"page",
            @"pageKey": @"presets",
            @"identifier": preset[@"identifier"],
            @"title": title,
            @"subtitle":
                [NSString stringWithFormat:@"%@ — %@", presetsCategory,
                                           detail],
            @"icon": presetsPage[@"icon"] ?: @"settings_stroke",
            @"searchText":
                [@[title, detail, themeSection, presetsCategory]
                    componentsJoinedByString:@" "]
        }];
    }
    NSString* profileSection =
        [bundle localizedStringForKey:@"PREFERENCE_PROFILES_SECTION_TITLE"];
    for (NSDictionary* profileAction in @[
             @{
                 @"titleKey": @"EXPORT_PREFERENCE_PROFILE_TITLE",
                 @"detailKey": @"EXPORT_PREFERENCE_PROFILE_DETAIL"
             },
             @{
                 @"titleKey": @"IMPORT_PREFERENCE_PROFILE_TITLE",
                 @"detailKey": @"IMPORT_PREFERENCE_PROFILE_DETAIL"
             }
         ]) {
        NSString* title =
            [bundle localizedStringForKey:profileAction[@"titleKey"]];
        NSString* detail =
            [bundle localizedStringForKey:profileAction[@"detailKey"]];
        [index addObject:@{
            @"kind": @"page",
            @"pageKey": @"presets",
            @"identifier": profileAction[@"titleKey"],
            @"title": title,
            @"subtitle":
                [NSString stringWithFormat:@"%@ — %@", presetsCategory,
                                           detail],
            @"icon": presetsPage[@"icon"] ?: @"settings_stroke",
            @"searchText":
                [@[title, detail, profileSection, presetsCategory]
                    componentsJoinedByString:@" "]
        }];
    }
    self.settingsSearchIndex = [index copy];
    self.filteredSettingsResults = @[];
}

- (BOOL)isSettingsSearchActive {
    return self.settingsSearchController.isActive &&
           self.settingsSearchController.searchBar.text.length > 0;
}

- (void)updateSearchResultsForSearchController:
    (UISearchController*)searchController {
    NSString* query =
        [searchController.searchBar.text
            stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length == 0) {
        self.filteredSettingsResults = @[];
    } else {
        NSMutableArray<NSDictionary*>* matches = [NSMutableArray array];
        for (NSDictionary* result in self.settingsSearchIndex) {
            NSRange match =
                [result[@"searchText"]
                    rangeOfString:query
                         options:NSCaseInsensitiveSearch |
                                 NSDiacriticInsensitiveSearch];
            if (match.location != NSNotFound) {
                [matches addObject:result];
            }
        }
        self.filteredSettingsResults = [matches copy];
    }
    [self.tableView reloadData];
    if (query.length > 0 && self.filteredSettingsResults.count == 0) {
        UILabel* emptyLabel = [UILabel new];
        emptyLabel.text = [[BHTBundle sharedBundle]
            localizedStringForKey:@"SETTINGS_SEARCH_NO_RESULTS"];
        emptyLabel.textAlignment = NSTextAlignmentCenter;
        emptyLabel.textColor = [Palette currentSecondaryTextColor];
        emptyLabel.font =
            [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        emptyLabel.numberOfLines = 0;
        self.tableView.backgroundView = emptyLabel;
    } else {
        self.tableView.backgroundView = nil;
    }
}

- (void)didDismissSearchController:(UISearchController*)searchController {
    self.filteredSettingsResults = @[];
    self.tableView.backgroundView = nil;
    [self.tableView reloadData];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.estimatedRowHeight = 80;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight = 50;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    [self.tableView registerClass:[ModernSettingsTableViewCell class]
           forCellReuseIdentifier:@"SettingsCell"];
    [self.view addSubview:self.tableView];
}

- (void)setupLayout {
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupFooterLabel {
    UIView* footerView =
        [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 60)];
    footerView.backgroundColor = [Palette currentBackgroundColor];

    UILabel* footerLabel = [[UILabel alloc] init];
    footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    footerLabel.text = @NFB_VERSION_STRING " (" NFB_COMMIT_STRING ")";
    footerLabel.numberOfLines = 0;
    footerLabel.textAlignment = NSTextAlignmentLeft;

    footerLabel.font = TwitterChirpFont(TwitterFontStyleRegular);

    footerLabel.textColor = [Palette currentSecondaryTextColor];

    [footerView addSubview:footerLabel];

    [NSLayoutConstraint activateConstraints:@[
        [footerLabel.leadingAnchor constraintEqualToAnchor:footerView.leadingAnchor
                                                  constant:20], // match table cell padding
        [footerLabel.trailingAnchor constraintEqualToAnchor:footerView.trailingAnchor
                                                   constant:-20],
        [footerLabel.topAnchor constraintEqualToAnchor:footerView.topAnchor
                                              constant:8],
        [footerLabel.bottomAnchor constraintEqualToAnchor:footerView.bottomAnchor
                                                 constant:-8]
    ]];

    self.tableView.tableFooterView = footerView;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    if ([self isSettingsSearchActive]) {
        return 1;
    }
    return 5;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self isSettingsSearchActive]) {
        return self.filteredSettingsResults.count;
    }
    if (section == 0) {
        return self.sections.count;
    } else if (section == 1) {
        return self.developerCells.count;
    } else if (section == 2) {
        return self.coolKidsCells.count;
    } else if (section == 3) {
        return self.specialThanksCells.count;
    } else if (section == 4) {
        return self.officialPageCells.count;
    }
    return 0;
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    if ([self isSettingsSearchActive]) {
        ModernSettingsTableViewCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"SettingsCell"
                                            forIndexPath:indexPath];
        NSDictionary* result = self.filteredSettingsResults[indexPath.row];
        [cell configureWithTitle:result[@"title"]
                        subtitle:result[@"subtitle"]
                        iconName:result[@"icon"]];
        return cell;
    }
    if (indexPath.section == 0) {
        ModernSettingsTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"SettingsCell"
                                                                            forIndexPath:indexPath];
        NSDictionary* sectionData = self.sections[indexPath.row];
        [cell configureWithTitle:sectionData[@"title"]
                        subtitle:sectionData[@"subtitle"]
                        iconName:sectionData[@"icon"]];
        return cell;
    } else if (indexPath.section == 1) {
        return [self developerCellForTableView:tableView
                                   atIndexPath:indexPath
                                     fromArray:self.developerCells];
    } else if (indexPath.section == 2) {
        return [self developerCellForTableView:tableView
                                   atIndexPath:indexPath
                                     fromArray:self.coolKidsCells];
    } else if (indexPath.section == 3) {
        return [self developerCellForTableView:tableView
                                   atIndexPath:indexPath
                                     fromArray:self.specialThanksCells];
    } else if (indexPath.section == 4) {
        return [self developerCellForTableView:tableView
                                   atIndexPath:indexPath
                                     fromArray:self.officialPageCells];
    }

    return nil;
}

- (UITableViewCell*)developerCellForTableView:(UITableView*)tableView
                                  atIndexPath:(NSIndexPath*)indexPath
                                    fromArray:(NSArray*)array {
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"DeveloperCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"DeveloperCell"];
        [self setupDeveloperCell:cell];
    }
    NSDictionary* developer = array[indexPath.row];
    [self configureDeveloperCell:cell withDeveloper:developer];
    return cell;
}

#pragma mark - Developer Cell Setup

- (void)setupDeveloperCell:(UITableViewCell*)cell {
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;
    UIImageView* avatarImageView = [[UIImageView alloc] init];
    avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
    avatarImageView.layer.cornerRadius = 26;
    avatarImageView.clipsToBounds = YES;
    avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
    avatarImageView.tag = 100;
    [cell.contentView addSubview:avatarImageView];
    UILabel* nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.tag = 101;
    nameLabel.adjustsFontForContentSizeCategory = YES;
    [cell.contentView addSubview:nameLabel];
    UILabel* usernameLabel = [[UILabel alloc] init];
    usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    usernameLabel.tag = 102;
    usernameLabel.adjustsFontForContentSizeCategory = YES;
    [cell.contentView addSubview:usernameLabel];
    UIImageView* devChevron = [[UIImageView alloc] init];
    devChevron.translatesAutoresizingMaskIntoConstraints = NO;
    devChevron.tag = 103;
    devChevron.contentMode = UIViewContentModeScaleAspectFit;
    [cell.contentView addSubview:devChevron];
    [NSLayoutConstraint activateConstraints:@[
        [avatarImageView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor
                                                      constant:20],
        [avatarImageView.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [avatarImageView.widthAnchor constraintEqualToConstant:52],
        [avatarImageView.heightAnchor constraintEqualToConstant:52],
        [nameLabel.leadingAnchor constraintEqualToAnchor:avatarImageView.trailingAnchor
                                                constant:12],
        [nameLabel.trailingAnchor constraintEqualToAnchor:devChevron.leadingAnchor
                                                 constant:-12],
        [nameLabel.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor
                                            constant:16],
        [usernameLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [usernameLabel.trailingAnchor constraintEqualToAnchor:devChevron.leadingAnchor
                                                     constant:-12],
        [usernameLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor
                                                constant:2],
        [usernameLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor
                                                   constant:-16],
        [devChevron.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor
                                                  constant:-20],
        [devChevron.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [devChevron.widthAnchor constraintEqualToConstant:18],
        [devChevron.heightAnchor constraintEqualToConstant:18]
    ]];
    cell.backgroundColor = [Palette currentSurfaceColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
}

- (void)configureDeveloperCell:(UITableViewCell*)cell withDeveloper:(NSDictionary*)developer {
    UIImageView* avatarImageView = [cell.contentView viewWithTag:100];
    UILabel* nameLabel = [cell.contentView viewWithTag:101];
    UILabel* usernameLabel = [cell.contentView viewWithTag:102];
    id fontGroup = [BHTManager sharedFontGroup];
    UIColor* textColor = [Palette currentTextColor];
    UIColor* subtitleColor = [Palette currentSecondaryTextColor];
    cell.backgroundColor = [Palette currentSurfaceColor];
    nameLabel.text = developer[@"title"];
    nameLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    nameLabel.textColor = textColor;
    usernameLabel.text = [NSString stringWithFormat:@"@%@", developer[@"username"]];
    usernameLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    usernameLabel.textColor = subtitleColor;
    UIImageView* devChevron = [cell.contentView viewWithTag:103];
    devChevron.image = [UIImage tfn_vectorImageNamed:@"chevron_right"
                                            fitsSize:CGSizeMake(18, 18)
                                           fillColor:subtitleColor];
    NSString* avatarURL = developer[@"avatarURL"];
    UIImage* placeholder = [UIImage systemImageNamed:@"person.circle.fill"];
    NSURLSessionDataTask* previousTask =
        objc_getAssociatedObject(avatarImageView, &kBHTAvatarTaskKey);
    [previousTask cancel];
    objc_setAssociatedObject(avatarImageView, &kBHTAvatarTaskKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(avatarImageView, &kBHTAvatarRequestTokenKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    avatarImageView.image = placeholder;
    objc_setAssociatedObject(
        avatarImageView, &kBHTRepresentedAvatarURLKey, avatarURL,
        OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (avatarURL.length == 0) return;

    UIImage* cached = [BHTDeveloperAvatarCache() objectForKey:avatarURL];
    if (cached) {
        avatarImageView.image = cached;
        return;
    }

    NSURL* url = [NSURL URLWithString:avatarURL];
    if (!url) return;
    NSString* requestToken = NSUUID.UUID.UUIDString;
    objc_setAssociatedObject(avatarImageView, &kBHTAvatarRequestTokenKey,
                             requestToken,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSURLSessionDataTask* task =
        [[NSURLSession sharedSession]
        dataTaskWithURL:url
      completionHandler:^(NSData* data, NSURLResponse* response,
                          NSError* error) {
          UIImage* image =
              error ? nil : [UIImage imageWithData:data];
          if (image) {
              [BHTDeveloperAvatarCache() setObject:image
                                            forKey:avatarURL];
          }
          dispatch_async(dispatch_get_main_queue(), ^{
              NSString* represented = objc_getAssociatedObject(
                  avatarImageView, &kBHTRepresentedAvatarURLKey);
              NSString* activeToken = objc_getAssociatedObject(
                  avatarImageView, &kBHTAvatarRequestTokenKey);
              if ([represented isEqualToString:avatarURL] &&
                  [activeToken isEqualToString:requestToken]) {
                  avatarImageView.image = image ?: placeholder;
                  objc_setAssociatedObject(
                      avatarImageView, &kBHTAvatarTaskKey, nil,
                      OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                  objc_setAssociatedObject(
                      avatarImageView, &kBHTAvatarRequestTokenKey, nil,
                      OBJC_ASSOCIATION_RETAIN_NONATOMIC);
              }
          });
      }];
    objc_setAssociatedObject(avatarImageView, &kBHTAvatarTaskKey, task,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [task resume];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if ([self isSettingsSearchActive]) {
        NSDictionary* result = self.filteredSettingsResults[indexPath.row];
        [self openSettingsSearchResult:result];
        return;
    }

    if (indexPath.section == 0) {
        NSDictionary* sectionData = self.sections[indexPath.row];
        NSString* action = sectionData[@"action"];
        SEL selector = NSSelectorFromString(action);
        if ([self respondsToSelector:selector]) {
            IMP imp = [self methodForSelector:selector];
            void (*func)(id, SEL) = (void*)imp;
            func(self, selector);
        }
    } else if (indexPath.section == 1) {
        NSDictionary* developer = self.developerCells[indexPath.row];
        [self openTwitterProfileWithUserID:developer[@"userID"]];
    } else if (indexPath.section == 2) {
        NSDictionary* developer = self.coolKidsCells[indexPath.row];
        [self openTwitterProfileWithUserID:developer[@"userID"]];
    } else if (indexPath.section == 3) {
        NSDictionary* developer = self.specialThanksCells[indexPath.row];
        [self openTwitterProfileWithUserID:developer[@"userID"]];
    } else if (indexPath.section == 4) {
        NSDictionary* developer = self.officialPageCells[indexPath.row];
        [self openTwitterProfileWithUserID:developer[@"userID"]];
    }
}

- (void)openTwitterProfileWithUserID:(NSString*)userID {
    if (!userID.length) return;
    NSString* twitterURL = [NSString stringWithFormat:@"twitter://user?id=%@", userID];
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:twitterURL]
                                       options:@{}
                             completionHandler:nil];
}

#pragma mark - Navigation to Sub-pages

- (UIViewController*)settingsControllerForPageKey:(NSString*)pageKey {
    if ([pageKey isEqualToString:@"appearance"]) {
        return [[AppearanceSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"timelines"]) {
        return [[TimelinesSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"tweets"]) {
        return [[TweetsSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"media_downloads"]) {
        return [[MediaDownloadsSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"profiles"]) {
        return [[ProfilesSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"web"]) {
        return [[WebSettingsViewController alloc] initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"debug"]) {
        return [[DebugSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"presets"]) {
        return [[PresetSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([[BHTSettings allPageKeys] containsObject:pageKey]) {
        return [[ModernSettingsPageViewController alloc]
            initWithAccount:self.account
                    pageKey:pageKey];
    }
    return nil;
}

- (void)openSettingsSearchResult:(NSDictionary*)result {
    NSString* pageKey = result[@"pageKey"];
    UIViewController* controller =
        [self settingsControllerForPageKey:pageKey];
    if (!controller) return;

    if ([result[@"kind"] isEqualToString:@"setting"] &&
        [controller
            isKindOfClass:ModernSettingsPageViewController.class]) {
        ((ModernSettingsPageViewController*)controller)
            .settingsSearchTargetIdentifier = result[@"identifier"];
    }
    self.settingsSearchController.active = NO;
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)showLayoutSettings {
    UIViewController* vc = [self settingsControllerForPageKey:@"general"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showAppearanceSettings {
    UIViewController* vc =
        [self settingsControllerForPageKey:@"appearance"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showTimelinesSettings {
    UIViewController* vc =
        [self settingsControllerForPageKey:@"timelines"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showGrokSettings {
    UIViewController* vc = [self settingsControllerForPageKey:@"grok"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showDownloadsSettings {
    UIViewController* vc =
        [self settingsControllerForPageKey:@"media_downloads"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showProfilesSettings {
    UIViewController* vc =
        [self settingsControllerForPageKey:@"profiles"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showTweetsSettings {
    UIViewController* vc =
        [self settingsControllerForPageKey:@"tweets"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showBrandingSettings {
    UIViewController* vc =
        [self settingsControllerForPageKey:@"branding"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showDebugSettings {
    UIViewController* vc =
        [self settingsControllerForPageKey:@"debug"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showSearchSettings {
    UIViewController* vc = [self settingsControllerForPageKey:@"search"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showWebSettings {
    UIViewController* vc = [self settingsControllerForPageKey:@"web"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showPresetSettings {
    UIViewController* vc = [self settingsControllerForPageKey:@"presets"];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
