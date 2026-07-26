//
//  ModernSettingsPageViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/ModernSettingsPageViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"
#import "Settings/ModernSettingsCells.h"
#import "ThemeColor/Palette.h"

static char kBHTSettingsPreferenceKeyAssociation;
static char kBHTFontPickerTypeAssociation;

NSString* BHTSettingsKeyForSwitch(UISwitch* settingsSwitch) {
    return objc_getAssociatedObject(
        settingsSwitch, &kBHTSettingsPreferenceKeyAssociation);
}

void BHTMarkNeoFreeBirdFontPicker(UIFontPickerViewController* picker,
                                  NSString* fontType) {
    objc_setAssociatedObject(picker, &kBHTFontPickerTypeAssociation,
                             fontType, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

NSString* BHTFontTypeForPicker(UIFontPickerViewController* picker) {
    return objc_getAssociatedObject(picker,
                                    &kBHTFontPickerTypeAssociation);
}

@interface ModernSettingsPageViewController ()
@property (nonatomic, copy) NSString* registryPageKey;
@property (nonatomic, copy) NSArray<NSDictionary*>* visibleSections;
@end

@implementation ModernSettingsPageViewController

#pragma mark - Lifecycle

- (instancetype)initWithAccount:(TFNTwitterAccount*)account {
    return [self initWithAccount:account pageKey:nil];
}

- (instancetype)initWithAccount:(TFNTwitterAccount*)account pageKey:(NSString*)pageKey {
    if ((self = [super init])) {
        self.account = account;
        self.registryPageKey = pageKey;
        [self buildSettingsList];
        [self updateVisibleToggles];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupTable];
}

#pragma mark - Page Registry

- (NSString*)pageKey {
    return self.registryPageKey;
}

- (NSString*)pageTitleKey {
    return [BHTSettings titleKeyForPage:[self pageKey]];
}

- (NSString*)pageSubtitleKey {
    return [BHTSettings subtitleKeyForPage:[self pageKey]];
}

- (void)buildSettingsList {
    self.toggles = [BHTSettings settingsForPage:[self pageKey]];
}

#pragma mark - Setup

- (void)setupNav {
    NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:[self pageTitleKey]];
    if (self.account) {
        self.navigationItem.titleView =
            [objc_getClass("TFNTitleView") titleViewWithTitle:title
                                                     subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [Palette currentBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[ModernSettingsToggleCell class]
           forCellReuseIdentifier:@"ToggleCell"];
    [self.tableView registerClass:[ModernSettingsTableViewCell class]
           forCellReuseIdentifier:@"ButtonCell"];
    [self.tableView registerClass:[ModernSettingsCompactButtonCell class]
           forCellReuseIdentifier:@"CompactButtonCell"];
    [self.view addSubview:self.tableView];
}

#pragma mark - Visible Toggles

- (void)updateVisibleToggles {
    NSMutableArray* visible = [NSMutableArray array];
    for (NSDictionary* toggleData in self.toggles) {
        NSString* parentKey = toggleData[@"parentKey"];
        if (parentKey) {
            BOOL parentEnabled = [BHTSettings boolForKey:parentKey];
            if (parentEnabled) {
                [visible addObject:toggleData];
            }
        } else {
            [visible addObject:toggleData];
        }
    }
    self.visibleToggles = [visible copy];

    NSMutableArray<NSMutableDictionary*>* sections =
        [NSMutableArray array];
    NSMutableDictionary<NSString*, NSMutableDictionary*>* sectionsByKey =
        [NSMutableDictionary dictionary];
    for (NSDictionary* entry in visible) {
        NSString* sectionKey = entry[@"sectionKey"] ?: @"";
        NSMutableDictionary* section = sectionsByKey[sectionKey];
        if (!section) {
            section = [@{
                @"titleKey": sectionKey,
                @"settings": [NSMutableArray array]
            } mutableCopy];
            sectionsByKey[sectionKey] = section;
            [sections addObject:section];
        }
        [section[@"settings"] addObject:entry];
    }

    NSMutableArray* immutableSections = [NSMutableArray array];
    for (NSDictionary* section in sections) {
        [immutableSections addObject:@{
            @"titleKey": section[@"titleKey"],
            @"settings": [section[@"settings"] copy]
        }];
    }
    self.visibleSections = [immutableSections copy];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return self.visibleSections.count;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.visibleSections.count) {
        return 0;
    }
    return [self.visibleSections[section][@"settings"] count];
}

- (NSDictionary*)settingAtIndexPath:(NSIndexPath*)indexPath {
    if (indexPath.section >= self.visibleSections.count) return nil;
    NSArray* settings =
        self.visibleSections[indexPath.section][@"settings"];
    if (indexPath.row >= settings.count) return nil;
    return settings[indexPath.row];
}

// Title key defaults to KEY_TITLE; an explicit titleKey takes precedence.
- (NSString*)localizedTitleForEntry:(NSDictionary*)entry {
    NSString* titleKey = entry[@"titleKey"];
    if (!titleKey) {
        titleKey = [NSString stringWithFormat:@"%@_TITLE", [entry[@"key"] uppercaseString]];
    }
    return [[BHTBundle sharedBundle] localizedStringForKey:titleKey];
}

// The bundle returns the key itself when no string exists, which counts as no detail.
- (NSString*)localizedDetailForKey:(NSString*)key {
    NSString* detailKey = [NSString stringWithFormat:@"%@_DETAIL", [key uppercaseString]];
    NSString* detail = [[BHTBundle sharedBundle] localizedStringForKey:detailKey];
    return [detail isEqualToString:detailKey] ? @"" : detail;
}

// Localized at render time; the registry can't call localizedStringForKey
// without re-entering the settings lookup.
- (NSString*)defaultSubtitleForEntry:(NSDictionary*)entry {
    NSString* subtitleDefaultKey = entry[@"subtitleDefaultKey"];
    if (subtitleDefaultKey) {
        return [[BHTBundle sharedBundle] localizedStringForKey:subtitleDefaultKey];
    }
    return entry[@"subtitleDefault"];
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSDictionary* toggleData = [self settingAtIndexPath:indexPath];
    if (!toggleData) return [UITableViewCell new];
    NSString* type = toggleData[@"type"];
    if ([type isEqualToString:@"compactButton"]) {
        ModernSettingsCompactButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell"
                                            forIndexPath:indexPath];
        NSString* title = [self localizedTitleForEntry:toggleData];
        NSString* subtitle = @"";
        NSString* prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            NSString* defaultSubtitle = [self defaultSubtitleForEntry:toggleData];
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: defaultSubtitle;
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 &&
                ![subtitle isEqualToString:defaultSubtitle]) {
                subtitle = @"••••••••••••••••";
            }
        }
        [cell configureWithTitle:title subtitle:subtitle];
        return cell;
    } else if ([type isEqualToString:@"button"]) {
        ModernSettingsTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ButtonCell"
                                                                            forIndexPath:indexPath];
        NSString* title = [self localizedTitleForEntry:toggleData];
        NSString* subtitle = @"";
        NSString* prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            NSString* defaultSubtitle = [self defaultSubtitleForEntry:toggleData];
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: defaultSubtitle;
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 &&
                ![subtitle isEqualToString:defaultSubtitle]) {
                subtitle = @"••••••••••••••••";
            }
        }
        NSString* iconName = toggleData[@"icon"];
        [cell configureWithTitle:title subtitle:subtitle iconName:iconName];
        return cell;
    } else {
        ModernSettingsToggleCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ToggleCell"
                                                                         forIndexPath:indexPath];
        NSString* key = toggleData[@"key"];
        NSString* title = [self localizedTitleForEntry:toggleData];
        NSString* subtitle = [self localizedDetailForKey:key];
        [cell configureWithTitle:title subtitle:subtitle];
        BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key]
                              ?: toggleData[@"default"] boolValue];
        cell.toggleSwitch.on = isEnabled;
        objc_setAssociatedObject(
            cell.toggleSwitch, &kBHTSettingsPreferenceKeyAssociation, key,
            OBJC_ASSOCIATION_COPY_NONATOMIC);
        [cell.toggleSwitch removeTarget:self
                                 action:@selector(switchChanged:)
                       forControlEvents:UIControlEventValueChanged];
        [cell.toggleSwitch addTarget:self
                              action:@selector(switchChanged:)
                    forControlEvents:UIControlEventValueChanged];
        return cell;
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary* data = [self settingAtIndexPath:indexPath];
    if (!data) return;
    if ([data[@"type"] isEqualToString:@"button"] ||
        [data[@"type"] isEqualToString:@"compactButton"]) {
        NSString* actionName = data[@"action"];
        if (actionName) {
            SEL action = NSSelectorFromString(actionName);
            if ([self respondsToSelector:action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [self performSelector:action
                           withObject:data];
#pragma clang diagnostic pop
            }
        }
    }
}

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    UIView* header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UIView* previous = nil;

    if (section == 0) {
        UILabel* detail = [UILabel new];
        detail.translatesAutoresizingMaskIntoConstraints = NO;
        detail.text = [[BHTBundle sharedBundle]
            localizedStringForKey:[self pageSubtitleKey]];
        detail.numberOfLines = 0;
        detail.font =
            [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        detail.textColor = UIColor.secondaryLabelColor;
        [header addSubview:detail];
        [NSLayoutConstraint activateConstraints:@[
            [detail.leadingAnchor
                constraintEqualToAnchor:header.leadingAnchor
                               constant:20],
            [detail.trailingAnchor
                constraintEqualToAnchor:header.trailingAnchor
                               constant:-20],
            [detail.topAnchor constraintEqualToAnchor:header.topAnchor
                                              constant:8]
        ]];
        previous = detail;
    }

    NSString* sectionTitleKey =
        section < (NSInteger)self.visibleSections.count
            ? self.visibleSections[section][@"titleKey"]
            : nil;
    if (sectionTitleKey.length > 0) {
        UILabel* title = [UILabel new];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.text = [[BHTBundle sharedBundle]
            localizedStringForKey:sectionTitleKey];
        title.numberOfLines = 0;
        title.font =
            [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        title.textColor = UIColor.labelColor;
        [header addSubview:title];
        NSLayoutYAxisAnchor* topAnchor =
            previous ? previous.bottomAnchor : header.topAnchor;
        CGFloat topSpacing = previous ? 18.0 : 10.0;
        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor
                constraintEqualToAnchor:header.leadingAnchor
                               constant:20],
            [title.trailingAnchor
                constraintEqualToAnchor:header.trailingAnchor
                               constant:-20],
            [title.topAnchor
                constraintEqualToAnchor:topAnchor
                               constant:topSpacing]
        ]];
        previous = title;
    }

    if (previous) {
        [previous.bottomAnchor
            constraintEqualToAnchor:header.bottomAnchor
                           constant:-8]
            .active = YES;
    }
    return header;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    NSString* sectionTitleKey =
        section < (NSInteger)self.visibleSections.count
            ? self.visibleSections[section][@"titleKey"]
            : nil;
    return section == 0 || sectionTitleKey.length > 0
               ? UITableViewAutomaticDimension
               : CGFLOAT_MIN;
}

#pragma mark - Switch Handling

- (void)switchChanged:(UISwitch*)sender {
    NSString* key = BHTSettingsKeyForSwitch(sender);
    if (key) {
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
        [self updateAndAnimateChangesForKey:key];
    }
}

- (void)updateAndAnimateChangesForKey:(NSString*)key {
    [self updateVisibleToggles];
    [UIView transitionWithView:self.tableView
                      duration:0.2
                       options:UIViewAnimationOptionTransitionCrossDissolve |
                               UIViewAnimationOptionAllowAnimatedContent
                    animations:^{
                        [self.tableView reloadData];
                    }
                    completion:nil];
}

@end
