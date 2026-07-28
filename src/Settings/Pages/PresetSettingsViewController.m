#import "Settings/Pages/PresetSettingsViewController.h"

#import "Core/BHTBundle.h"
#import "Headers/TWHeaders.h"
#import "ThemeColor/BHTThemeBuilderViewController.h"
#import "ThemeColor/BHTThemePresets.h"
#import "ThemeColor/ColorThemeViewController.h"
#import "ThemeColor/Palette.h"

extern UIColor* CurrentAccentColor(void);

typedef NS_ENUM(NSInteger, BHTThemesSection) {
    BHTThemesSectionCurrent = 0,
    BHTThemesSectionBuiltIn,
    BHTThemesSectionMyThemes,
    BHTThemesSectionAdvanced,
    BHTThemesSectionCount
};

static NSString* BHTThemeLibraryLocalized(NSString* key,
                                          NSString* fallback) {
    NSString* value =
        [[BHTBundle sharedBundle] localizedStringForKey:key];
    return value.length > 0 && ![value isEqualToString:key]
               ? value
               : fallback;
}

@interface PresetSettingsViewController ()
@property(nonatomic, strong) TFNTwitterAccount* account;
@property(nonatomic, strong) UITableView* tableView;
@property(nonatomic, copy) NSArray<NSDictionary*>* themePresets;
@property(nonatomic, copy) NSArray<NSDictionary*>* userThemes;
@end

@implementation PresetSettingsViewController

- (instancetype)initWithAccount:(TFNTwitterAccount*)account {
    if ((self = [super init])) {
        _account = account;
        _themePresets = [BHTThemePresets availablePresets];
        _userThemes = [BHTThemePresets userThemes];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [Palette currentBackgroundColor];
    NSString* title = BHTThemeLibraryLocalized(
        @"MODERN_SETTINGS_PRESETS_TITLE", @"Themes");
    if (self.account) {
        self.navigationItem.titleView =
            [objc_getClass("TFNTitleView")
                titleViewWithTitle:title
                          subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }

    self.tableView =
        [[UITableView alloc] initWithFrame:self.view.bounds
                                    style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    [self.view addSubview:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.themePresets = [BHTThemePresets availablePresets];
    self.userThemes = [BHTThemePresets userThemes];
    [self applyCurrentTheme];
    [self.tableView reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self revealSettingsSearchTargetIfNeeded];
}

- (void)traitCollectionDidChange:
    (UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (previousTraitCollection.userInterfaceStyle !=
        self.traitCollection.userInterfaceStyle) {
        [self applyCurrentTheme];
        [self.tableView reloadData];
    }
}

- (void)applyCurrentTheme {
    self.view.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.separatorColor = [Palette currentSeparatorColor];
    self.view.tintColor =
        [Palette customAccentColor] ?: UIColor.systemBlueColor;
}

#pragma mark - Sections

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return BHTThemesSectionCount;
}

- (NSInteger)tableView:(UITableView*)tableView
 numberOfRowsInSection:(NSInteger)section {
    switch ((BHTThemesSection)section) {
        case BHTThemesSectionCurrent:
            return 1;
        case BHTThemesSectionBuiltIn:
            return self.themePresets.count;
        case BHTThemesSectionMyThemes:
            return self.userThemes.count + 1;
        case BHTThemesSectionAdvanced:
            return 1;
        case BHTThemesSectionCount:
            return 0;
    }
    return 0;
}

- (NSString*)tableView:(UITableView*)tableView
    titleForHeaderInSection:(NSInteger)section {
    switch ((BHTThemesSection)section) {
        case BHTThemesSectionCurrent:
            return BHTThemeLibraryLocalized(
                @"THEME_LIBRARY_CURRENT", @"Current Theme");
        case BHTThemesSectionBuiltIn:
            return BHTThemeLibraryLocalized(
                @"THEME_PRESETS_SECTION_TITLE", @"Built-in Themes");
        case BHTThemesSectionMyThemes:
            return BHTThemeLibraryLocalized(
                @"THEME_LIBRARY_MY_THEMES", @"My Themes");
        case BHTThemesSectionAdvanced:
            return BHTThemeLibraryLocalized(
                @"THEME_LIBRARY_ADVANCED", @"Advanced");
        case BHTThemesSectionCount:
            return nil;
    }
    return nil;
}

- (NSString*)tableView:(UITableView*)tableView
    titleForFooterInSection:(NSInteger)section {
    if (section == BHTThemesSectionMyThemes) {
        return BHTThemeLibraryLocalized(
            @"THEME_LIBRARY_MY_THEMES_FOOTER",
            @"Create personal themes, then swipe a theme to edit, duplicate, "
             @"or delete it.");
    }
    if (section == BHTThemesSectionAdvanced) {
        return BHTThemeLibraryLocalized(
            @"THEME_ACCENT_ONLY_FOOTER",
            @"For a coordinated background, surface, text, and accent palette, "
             @"select or create a full theme above.");
    }
    return nil;
}

- (BOOL)isCreateRowAtIndexPath:(NSIndexPath*)indexPath {
    return indexPath.section == BHTThemesSectionMyThemes &&
           indexPath.row == 0;
}

- (BOOL)isAccentOnlyRowAtIndexPath:(NSIndexPath*)indexPath {
    return indexPath.section == BHTThemesSectionAdvanced &&
           indexPath.row == 0;
}

- (NSDictionary*)themeAtIndexPath:(NSIndexPath*)indexPath {
    if (indexPath.section == BHTThemesSectionBuiltIn &&
        indexPath.row >= 0 &&
        indexPath.row < (NSInteger)self.themePresets.count) {
        return self.themePresets[indexPath.row];
    }
    if (indexPath.section == BHTThemesSectionMyThemes &&
        indexPath.row > 0 &&
        indexPath.row <= (NSInteger)self.userThemes.count) {
        return self.userThemes[indexPath.row - 1];
    }
    return nil;
}

- (NSDictionary*)currentTheme {
    return [BHTThemePresets
        presetForIdentifier:[BHTThemePresets activePresetIdentifier]];
}

#pragma mark - Cells

- (UITableViewCell*)reusableCellWithIdentifier:(NSString*)identifier
                                     tableView:(UITableView*)tableView {
    UITableViewCell* cell =
        [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc]
              initWithStyle:UITableViewCellStyleSubtitle
            reuseIdentifier:identifier];
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.numberOfLines = 0;
    }
    cell.backgroundColor = [Palette currentSurfaceColor];
    cell.textLabel.textColor = [Palette currentTextColor];
    cell.detailTextLabel.textColor =
        [Palette currentSecondaryTextColor];
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;
    cell.imageView.tintColor = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessibilityHint = nil;
    cell.accessibilityIdentifier = nil;
    cell.accessibilityTraits = UIAccessibilityTraitButton;
    return cell;
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    if (indexPath.section == BHTThemesSectionCurrent) {
        UITableViewCell* cell =
            [self reusableCellWithIdentifier:@"CurrentThemeCell"
                                   tableView:tableView];
        NSDictionary* current = [self currentTheme];
        if (current) {
            cell.textLabel.text =
                [BHTThemePresets displayNameForPreset:current];
            cell.detailTextLabel.text =
                [BHTThemePresets displayDetailForPreset:current];
        } else {
            cell.textLabel.text = BHTThemeLibraryLocalized(
                @"THEME_ACCENT_ONLY_TITLE", @"Accent Only");
            cell.detailTextLabel.text = BHTThemeLibraryLocalized(
                @"THEME_CURRENT_ACCENT_ONLY_DETAIL",
                @"X's native surfaces with your selected accent color.");
        }
        cell.imageView.image = [self previewImageForPreset:current];
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessibilityIdentifier = @"theme-library-current";
        cell.accessibilityTraits = UIAccessibilityTraitSelected;
        return cell;
    }

    NSDictionary* theme = [self themeAtIndexPath:indexPath];
    if (theme) {
        UITableViewCell* cell =
            [self reusableCellWithIdentifier:@"ThemePresetCell"
                                   tableView:tableView];
        cell.textLabel.text =
            [BHTThemePresets displayNameForPreset:theme];
        cell.detailTextLabel.text =
            [BHTThemePresets displayDetailForPreset:theme];
        BOOL active =
            [theme[@"identifier"]
                isEqualToString:[BHTThemePresets activePresetIdentifier]];
        cell.accessoryType =
            active ? UITableViewCellAccessoryCheckmark
                   : UITableViewCellAccessoryNone;
        cell.imageView.image = [self previewImageForPreset:theme];
        cell.accessibilityIdentifier =
            [@"theme-preset-" stringByAppendingString:
                                  theme[@"identifier"] ?: @""];
        cell.accessibilityTraits =
            active ? UIAccessibilityTraitButton |
                         UIAccessibilityTraitSelected
                   : UIAccessibilityTraitButton;
        if (indexPath.section == BHTThemesSectionMyThemes) {
            cell.accessibilityHint = BHTThemeLibraryLocalized(
                @"THEME_LIBRARY_CUSTOM_HINT",
                @"Swipe for edit, duplicate, and delete actions.");
        }
        return cell;
    }

    if ([self isCreateRowAtIndexPath:indexPath]) {
        UITableViewCell* cell =
            [self reusableCellWithIdentifier:@"CreateThemeCell"
                                   tableView:tableView];
        cell.textLabel.text = BHTThemeLibraryLocalized(
            @"THEME_LIBRARY_CREATE", @"Create Theme");
        cell.detailTextLabel.text = BHTThemeLibraryLocalized(
            @"THEME_LIBRARY_CREATE_DETAIL",
            @"Build a coordinated light and dark palette with a live preview.");
        cell.imageView.image =
            [UIImage systemImageNamed:@"plus.circle.fill"];
        cell.imageView.tintColor =
            [Palette customAccentColor] ?: UIColor.systemBlueColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityIdentifier = @"theme-library-create";
        return cell;
    }

    UITableViewCell* cell =
        [self reusableCellWithIdentifier:@"AccentOnlyCell"
                               tableView:tableView];
    cell.textLabel.text = BHTThemeLibraryLocalized(
        @"THEME_ACCENT_ONLY_TITLE", @"Accent Only");
    cell.detailTextLabel.text = BHTThemeLibraryLocalized(
        @"THEME_ACCENT_ONLY_DETAIL",
        @"Use one of X's native accent colors without changing backgrounds or "
         @"surfaces.");
    cell.imageView.image =
        [UIImage systemImageNamed:@"paintpalette.fill"];
    cell.imageView.tintColor =
        [Palette customAccentColor] ?: UIColor.systemBlueColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.accessibilityIdentifier = @"theme-library-accent-only";
    return cell;
}

- (UIImage*)previewImageForPreset:(NSDictionary*)preset {
    BOOL dark = [Palette currentPaletteUsesDarkAppearance];
    NSString* mapKey = dark ? @"darkColors" : @"lightColors";
    NSDictionary* raw =
        [preset[mapKey] isKindOfClass:NSDictionary.class]
            ? preset[mapKey]
            : nil;
    UIColor* background =
        [Palette colorFromHexString:
                     raw[BHTThemeColorBackgroundKey]] ?:
        [Palette currentBackgroundColor];
    UIColor* surface =
        [Palette colorFromHexString:raw[BHTThemeColorSurfaceKey]] ?:
        [Palette currentSurfaceColor];
    UIColor* accent =
        preset
            ? [BHTThemePresets previewAccentColorForPreset:preset
                                           darkAppearance:dark]
            : (CurrentAccentColor() ?: UIColor.systemBlueColor);
    UIColor* text =
        [Palette colorFromHexString:raw[BHTThemeColorTextKey]] ?:
        [Palette currentTextColor];
    UIColor* separator =
        [Palette colorFromHexString:
                     raw[BHTThemeColorSeparatorKey]] ?:
        [Palette currentSeparatorColor];

    UIGraphicsImageRendererFormat* format =
        [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer* renderer =
        [[UIGraphicsImageRenderer alloc]
            initWithSize:CGSizeMake(32, 32)
                  format:format];
    return [renderer imageWithActions:^(
                         UIGraphicsImageRendererContext* context) {
        CGContextRef graphics = context.CGContext;
        CGRect bounds = CGRectMake(1, 1, 30, 30);
        CGContextSaveGState(graphics);
        CGContextAddEllipseInRect(graphics, bounds);
        CGContextClip(graphics);
        [background setFill];
        UIRectFill(CGRectMake(1, 1, 15, 30));
        [surface setFill];
        UIRectFill(CGRectMake(16, 1, 15, 15));
        [accent setFill];
        UIRectFill(CGRectMake(16, 16, 15, 15));
        [text setFill];
        UIRectFill(CGRectMake(8, 11, 8, 10));
        CGContextRestoreGState(graphics);
        [separator setStroke];
        UIBezierPath* outline =
            [UIBezierPath bezierPathWithOvalInRect:bounds];
        outline.lineWidth = 1;
        [outline stroke];
    }];
}

#pragma mark - Selection

- (void)tableView:(UITableView*)tableView
    didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == BHTThemesSectionCurrent) return;

    if ([self isCreateRowAtIndexPath:indexPath]) {
        [self createTheme];
        return;
    }
    if ([self isAccentOnlyRowAtIndexPath:indexPath]) {
        [self openAccentOnly];
        return;
    }

    NSDictionary* theme = [self themeAtIndexPath:indexPath];
    if (theme &&
        [BHTThemePresets
            applyPresetIdentifier:theme[@"identifier"]]) {
        [self applyCurrentTheme];
        [tableView reloadData];
    }
}

- (void)createTheme {
    NSDictionary* active = [self currentTheme];
    BHTThemeBuilderViewController* builder =
        [[BHTThemeBuilderViewController alloc]
            initWithTheme:
                [BHTThemePresets
                    newUserThemeDraftBasedOnPreset:active]];
    [self.navigationController pushViewController:builder
                                         animated:YES];
}

- (void)openAccentOnly {
    ColorThemeViewController* controller =
        [[ColorThemeViewController alloc] init];
    [self.navigationController pushViewController:controller
                                         animated:YES];
}

- (void)editTheme:(NSDictionary*)theme {
    BHTThemeBuilderViewController* builder =
        [[BHTThemeBuilderViewController alloc] initWithTheme:theme];
    [self.navigationController pushViewController:builder
                                         animated:YES];
}

- (void)duplicateTheme:(NSDictionary*)theme {
    [self editTheme:
              [BHTThemePresets duplicateDraftForPreset:theme]];
}

#pragma mark - Swipe actions

- (UISwipeActionsConfiguration*)tableView:(UITableView*)tableView
    leadingSwipeActionsConfigurationForRowAtIndexPath:
        (NSIndexPath*)indexPath {
    NSDictionary* theme = [self themeAtIndexPath:indexPath];
    if (!theme) return nil;
    UIContextualAction* duplicate =
        [UIContextualAction
            contextualActionWithStyle:UIContextualActionStyleNormal
                                 title:BHTThemeLibraryLocalized(
                                           @"THEME_LIBRARY_DUPLICATE",
                                           @"Duplicate")
                               handler:^(
                                   __unused UIContextualAction* action,
                                   __unused UIView* source,
                                   void (^completion)(BOOL)) {
        [self duplicateTheme:theme];
        completion(YES);
    }];
    duplicate.image =
        [UIImage systemImageNamed:@"plus.square.on.square"];
    return [UISwipeActionsConfiguration
        configurationWithActions:@[duplicate]];
}

- (UISwipeActionsConfiguration*)tableView:(UITableView*)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:
        (NSIndexPath*)indexPath {
    if (indexPath.section != BHTThemesSectionMyThemes ||
        indexPath.row == 0) {
        return nil;
    }
    NSDictionary* theme = [self themeAtIndexPath:indexPath];
    if (!theme) return nil;
    UIContextualAction* edit =
        [UIContextualAction
            contextualActionWithStyle:UIContextualActionStyleNormal
                                 title:BHTThemeLibraryLocalized(
                                           @"THEME_LIBRARY_EDIT",
                                           @"Edit")
                               handler:^(
                                   __unused UIContextualAction* action,
                                   __unused UIView* source,
                                   void (^completion)(BOOL)) {
        [self editTheme:theme];
        completion(YES);
    }];
    edit.image = [UIImage systemImageNamed:@"pencil"];
    UIContextualAction* delete =
        [UIContextualAction
            contextualActionWithStyle:UIContextualActionStyleDestructive
                                 title:BHTThemeLibraryLocalized(
                                           @"THEME_LIBRARY_DELETE",
                                           @"Delete")
                               handler:^(
                                   __unused UIContextualAction* action,
                                   __unused UIView* source,
                                   void (^completion)(BOOL)) {
        [self confirmDeleteTheme:theme];
        completion(YES);
    }];
    delete.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration
        configurationWithActions:@[delete, edit]];
}

- (void)confirmDeleteTheme:(NSDictionary*)theme {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:BHTThemeLibraryLocalized(
                                     @"THEME_LIBRARY_DELETE", @"Delete")
                         message:[NSString
                                     stringWithFormat:
                                         BHTThemeLibraryLocalized(
                                             @"THEME_LIBRARY_DELETE_CONFIRM",
                                             @"Delete \"%@\"? This cannot be "
                                              @"undone."),
                                         [BHTThemePresets
                                             displayNameForPreset:theme]]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:BHTThemeLibraryLocalized(
                                       @"THEME_BUILDER_CANCEL", @"Cancel")
                             style:UIAlertActionStyleCancel
                           handler:nil]];
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:BHTThemeLibraryLocalized(
                                       @"THEME_LIBRARY_DELETE", @"Delete")
                             style:UIAlertActionStyleDestructive
                           handler:^(__unused UIAlertAction* action) {
        NSError* error = nil;
        if (![BHTThemePresets
                deleteUserThemeIdentifier:theme[@"identifier"]
                                      error:&error]) {
            [self showError:error];
            return;
        }
        self.userThemes = [BHTThemePresets userThemes];
        [self applyCurrentTheme];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showError:(NSError*)error {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:BHTThemeLibraryLocalized(
                                     @"THEME_LIBRARY_ERROR_TITLE",
                                     @"Couldn't Update Theme")
                         message:error.localizedDescription ?:
                                     BHTThemeLibraryLocalized(
                                         @"PREFERENCE_PROFILE_GENERIC_ERROR",
                                         @"Something went wrong.")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:BHTThemeLibraryLocalized(
                                       @"PREFERENCE_PROFILE_OK", @"OK")
                             style:UIAlertActionStyleDefault
                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Settings search

- (BOOL)isCreateSearchTarget:(NSString*)target {
    return [target isEqualToString:@"themes.create"] ||
           [target isEqualToString:@"THEME_LIBRARY_CREATE"] ||
           [target caseInsensitiveCompare:@"create_theme"] ==
               NSOrderedSame ||
           [target caseInsensitiveCompare:@"theme_create"] ==
               NSOrderedSame;
}

- (BOOL)isAccentOnlySearchTarget:(NSString*)target {
    return [target isEqualToString:@"themes.accent_only"] ||
           [target isEqualToString:@"THEME_ACCENT_ONLY_TITLE"] ||
           [target isEqualToString:@"THEME_LIBRARY_ACCENT_ONLY"] ||
           [target isEqualToString:@"THEME_OPTION_TITLE"] ||
           [target caseInsensitiveCompare:@"accent_only"] ==
               NSOrderedSame ||
           [target caseInsensitiveCompare:@"theme_accent_only"] ==
               NSOrderedSame;
}

- (NSIndexPath*)indexPathForSettingsSearchTarget:(NSString*)target {
    if (target.length == 0) return nil;
    if ([self isCreateSearchTarget:target]) {
        return [NSIndexPath indexPathForRow:0
                                 inSection:BHTThemesSectionMyThemes];
    }
    if ([self isAccentOnlySearchTarget:target]) {
        return [NSIndexPath indexPathForRow:0
                                 inSection:BHTThemesSectionAdvanced];
    }
    if ([target isEqualToString:@"themes.current"] ||
        [target isEqualToString:@"THEME_LIBRARY_CURRENT"] ||
        [target caseInsensitiveCompare:@"current_theme"] ==
            NSOrderedSame) {
        return [NSIndexPath indexPathForRow:0
                                 inSection:BHTThemesSectionCurrent];
    }
    for (NSUInteger row = 0; row < self.themePresets.count; row++) {
        if ([self.themePresets[row][@"identifier"]
                isEqualToString:target]) {
            return [NSIndexPath
                indexPathForRow:(NSInteger)row
                      inSection:BHTThemesSectionBuiltIn];
        }
    }
    for (NSUInteger row = 0; row < self.userThemes.count; row++) {
        if ([self.userThemes[row][@"identifier"]
                isEqualToString:target]) {
            return [NSIndexPath
                indexPathForRow:(NSInteger)row + 1
                      inSection:BHTThemesSectionMyThemes];
        }
    }
    return nil;
}

- (void)revealSettingsSearchTargetIfNeeded {
    NSString* target = self.settingsSearchTargetIdentifier;
    if (target.length == 0 || !self.tableView.window) return;

    NSIndexPath* indexPath =
        [self indexPathForSettingsSearchTarget:target];
    BOOL openCreate =
        self.settingsSearchShouldOpenTarget &&
        [self isCreateSearchTarget:target];
    BOOL openAccent =
        self.settingsSearchShouldOpenTarget &&
        [self isAccentOnlySearchTarget:target];
    self.settingsSearchTargetIdentifier = nil;
    self.settingsSearchShouldOpenTarget = NO;
    if (!indexPath) return;

    [self.tableView scrollToRowAtIndexPath:indexPath
                          atScrollPosition:UITableViewScrollPositionMiddle
                                  animated:YES];
    [self.tableView selectRowAtIndexPath:indexPath
                                animated:YES
                          scrollPosition:UITableViewScrollPositionNone];

    if (openCreate || openAccent) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(0.2 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf ||
                    strongSelf.navigationController.topViewController !=
                        strongSelf) {
                    return;
                }
                [strongSelf.tableView
                    deselectRowAtIndexPath:indexPath
                                  animated:YES];
                if (openCreate) {
                    [strongSelf createTheme];
                } else {
                    [strongSelf openAccentOnly];
                }
            });
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(0.65 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            [weakSelf.tableView deselectRowAtIndexPath:indexPath
                                              animated:YES];
        });
}

@end
