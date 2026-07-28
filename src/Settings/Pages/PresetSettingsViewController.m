#import "Settings/Pages/PresetSettingsViewController.h"

#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"
#import "ThemeColor/BHTThemeBuilderViewController.h"
#import "ThemeColor/BHTThemePresets.h"
#import "ThemeColor/Palette.h"

static const NSUInteger kBHTMaximumProfileBytes = 512 * 1024;

@interface PresetSettingsViewController ()
@property (nonatomic, strong) TFNTwitterAccount* account;
@property (nonatomic, strong) UITableView* tableView;
@property (nonatomic, copy) NSArray<NSDictionary*>* themePresets;
@property (nonatomic, copy) NSArray<NSDictionary*>* userThemes;
- (void)applyCurrentTheme;
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
    NSString* title = [[BHTBundle sharedBundle]
        localizedStringForKey:@"MODERN_SETTINGS_PRESETS_TITLE"];
    if (self.account) {
        NSString* username = self.account.displayUsername;
        self.navigationItem.titleView =
            [objc_getClass("TFNTitleView") titleViewWithTitle:title
                                                    subtitle:username];
    } else {
        self.title = title;
    }
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                 target:self
                                 action:@selector(createTheme)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel =
        [[BHTBundle sharedBundle]
            localizedStringForKey:@"THEME_LIBRARY_CREATE"];

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

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView*)tableView
 numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.themePresets.count;
    if (section == 1) return self.userThemes.count + 1;
    return 2;
}

- (NSString*)tableView:(UITableView*)tableView
    titleForHeaderInSection:(NSInteger)section {
    NSString* key = nil;
    if (section == 0) {
        key = @"THEME_PRESETS_SECTION_TITLE";
    } else if (section == 1) {
        key = @"THEME_LIBRARY_MY_THEMES";
    } else {
        key = @"PREFERENCE_PROFILES_SECTION_TITLE";
    }
    return [[BHTBundle sharedBundle] localizedStringForKey:key];
}

- (NSString*)tableView:(UITableView*)tableView
    titleForFooterInSection:(NSInteger)section {
    NSString* key = nil;
    if (section == 1) {
        key = @"THEME_LIBRARY_MY_THEMES_FOOTER";
    } else if (section == 2) {
        key = @"PREFERENCE_PROFILES_FOOTER";
    }
    return key ? [[BHTBundle sharedBundle] localizedStringForKey:key]
               : nil;
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    BOOL createRow = indexPath.section == 1 && indexPath.row == 0;
    NSString* reuseIdentifier =
        indexPath.section == 2
            ? @"ProfileActionCell"
            : (createRow ? @"CreateThemeCell" : @"ThemePresetCell");
    UITableViewCell* cell =
        [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc]
              initWithStyle:UITableViewCellStyleSubtitle
            reuseIdentifier:reuseIdentifier];
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
    cell.accessibilityTraits = UIAccessibilityTraitButton;

    if (indexPath.section == 0 ||
        (indexPath.section == 1 && !createRow)) {
        NSDictionary* preset =
            indexPath.section == 0
                ? self.themePresets[indexPath.row]
                : self.userThemes[indexPath.row - 1];
        cell.textLabel.text =
            [BHTThemePresets displayNameForPreset:preset];
        cell.detailTextLabel.text =
            [BHTThemePresets displayDetailForPreset:preset];
        BOOL active =
            [preset[@"identifier"]
                isEqualToString:[BHTThemePresets activePresetIdentifier]];
        cell.accessoryType =
            active ? UITableViewCellAccessoryCheckmark
                   : UITableViewCellAccessoryNone;
        cell.imageView.image = [self previewImageForPreset:preset];
        cell.accessibilityTraits =
            active ? UIAccessibilityTraitButton |
                         UIAccessibilityTraitSelected
                   : UIAccessibilityTraitButton;
        cell.accessibilityHint = indexPath.section == 1
                                     ? [[BHTBundle sharedBundle]
                                           localizedStringForKey:
                                               @"THEME_LIBRARY_CUSTOM_HINT"]
                                     : nil;
    } else if (createRow) {
        cell.textLabel.text = [[BHTBundle sharedBundle]
            localizedStringForKey:@"THEME_LIBRARY_CREATE"];
        cell.detailTextLabel.text = [[BHTBundle sharedBundle]
            localizedStringForKey:@"THEME_LIBRARY_CREATE_DETAIL"];
        cell.imageView.image =
            [UIImage systemImageNamed:@"plus.circle.fill"];
        cell.imageView.tintColor =
            [Palette customAccentColor] ?: UIColor.systemBlueColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        BOOL exporting = indexPath.row == 0;
        cell.textLabel.text =
            [[BHTBundle sharedBundle]
                localizedStringForKey:
                    exporting ? @"EXPORT_PREFERENCE_PROFILE_TITLE"
                              : @"IMPORT_PREFERENCE_PROFILE_TITLE"];
        cell.detailTextLabel.text =
            [[BHTBundle sharedBundle]
                localizedStringForKey:
                    exporting ? @"EXPORT_PREFERENCE_PROFILE_DETAIL"
                              : @"IMPORT_PREFERENCE_PROFILE_DETAIL"];
        cell.imageView.image =
            [UIImage systemImageNamed:exporting ? @"square.and.arrow.up"
                                                   : @"square.and.arrow.down"];
        cell.imageView.tintColor =
            [Palette customAccentColor] ?: UIColor.systemBlueColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return cell;
}

- (UIImage*)previewImageForPreset:(NSDictionary*)preset {
    BOOL dark = [Palette currentPaletteUsesDarkAppearance];
    NSDictionary* raw =
        [preset[dark ? @"darkColors" : @"lightColors"]
            isKindOfClass:NSDictionary.class]
            ? preset[dark ? @"darkColors" : @"lightColors"]
            : nil;
    UIColor* background =
        [Palette colorFromHexString:
                     raw[BHTThemeColorBackgroundKey]] ?:
        [Palette currentBackgroundColor];
    UIColor* surface =
        [Palette colorFromHexString:raw[BHTThemeColorSurfaceKey]] ?:
        [Palette currentSurfaceColor];
    UIColor* accent =
        [BHTThemePresets previewAccentColorForPreset:preset
                                     darkAppearance:dark];
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

- (void)tableView:(UITableView*)tableView
    didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        NSDictionary* preset = self.themePresets[indexPath.row];
        if ([BHTThemePresets
                applyPresetIdentifier:preset[@"identifier"]]) {
            [self applyCurrentTheme];
            [tableView reloadData];
        }
        return;
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            [self createTheme];
            return;
        }
        NSDictionary* theme = self.userThemes[indexPath.row - 1];
        if ([BHTThemePresets
                applyPresetIdentifier:theme[@"identifier"]]) {
            [self applyCurrentTheme];
            [tableView reloadData];
        }
        return;
    }
    if (indexPath.row == 0) {
        [self exportProfile];
    } else {
        [self importProfile];
    }
}

- (void)createTheme {
    NSDictionary* active = [BHTThemePresets
        presetForIdentifier:[BHTThemePresets activePresetIdentifier]];
    BHTThemeBuilderViewController* builder =
        [[BHTThemeBuilderViewController alloc]
            initWithTheme:
                [BHTThemePresets
                    newUserThemeDraftBasedOnPreset:active]];
    [self.navigationController pushViewController:builder
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

- (UISwipeActionsConfiguration*)tableView:(UITableView*)tableView
    leadingSwipeActionsConfigurationForRowAtIndexPath:
        (NSIndexPath*)indexPath {
    NSDictionary* theme = nil;
    if (indexPath.section == 0) {
        theme = self.themePresets[indexPath.row];
    } else if (indexPath.section == 1 && indexPath.row > 0) {
        theme = self.userThemes[indexPath.row - 1];
    }
    if (!theme) return nil;
    UIContextualAction* duplicate =
        [UIContextualAction
            contextualActionWithStyle:UIContextualActionStyleNormal
                                 title:[[BHTBundle sharedBundle]
                                           localizedStringForKey:
                                               @"THEME_LIBRARY_DUPLICATE"]
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
    if (indexPath.section != 1 || indexPath.row == 0) return nil;
    NSDictionary* theme = self.userThemes[indexPath.row - 1];
    UIContextualAction* edit =
        [UIContextualAction
            contextualActionWithStyle:UIContextualActionStyleNormal
                                 title:[[BHTBundle sharedBundle]
                                           localizedStringForKey:
                                               @"THEME_LIBRARY_EDIT"]
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
                                 title:[[BHTBundle sharedBundle]
                                           localizedStringForKey:
                                               @"THEME_LIBRARY_DELETE"]
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
        alertControllerWithTitle:[[BHTBundle sharedBundle]
                                     localizedStringForKey:
                                         @"THEME_LIBRARY_DELETE"]
                         message:[NSString
                                     stringWithFormat:
                                         [[BHTBundle sharedBundle]
                                             localizedStringForKey:
                                                 @"THEME_LIBRARY_DELETE_CONFIRM"],
                                         [BHTThemePresets
                                             displayNameForPreset:theme]]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:[[BHTBundle sharedBundle]
                                       localizedStringForKey:
                                           @"THEME_BUILDER_CANCEL"]
                             style:UIAlertActionStyleCancel
                           handler:nil]];
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:[[BHTBundle sharedBundle]
                                       localizedStringForKey:
                                           @"THEME_LIBRARY_DELETE"]
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

- (void)exportProfile {
    NSError* error = nil;
    NSData* data = [BHTSettings preferenceProfileJSONDataWithError:&error];
    if (!data) {
        [self showError:error];
        return;
    }
    NSURL* destination =
        [[BHTManager temporaryDirectoryURL]
            URLByAppendingPathComponent:@"NeoFreeBird-Preferences.json"];
    if (![data writeToURL:destination
                  options:NSDataWritingAtomic
                    error:&error]) {
        [self showError:error];
        return;
    }
    [BHTManager showSaveVC:destination];
}

- (void)importProfile {
    UIDocumentPickerViewController* picker =
        [[UIDocumentPickerViewController alloc]
            initWithDocumentTypes:@[@"public.json", @"public.text"]
                           inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller
    didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
    NSURL* url = urls.firstObject;
    if (!url) return;
    BOOL securityScoped = [url startAccessingSecurityScopedResource];
    NSError* error = nil;
    NSData* data = [NSData dataWithContentsOfURL:url
                                        options:NSDataReadingMappedIfSafe
                                          error:&error];
    if (securityScoped) [url stopAccessingSecurityScopedResource];
    if (!data || data.length == 0 ||
        data.length > kBHTMaximumProfileBytes) {
        if (!error) {
            error = [NSError
                errorWithDomain:@"com.neofreebird.preference-profile"
                           code:10
                       userInfo:@{
                           NSLocalizedDescriptionKey:
                               [[BHTBundle sharedBundle]
                                   localizedStringForKey:
                                       @"IMPORT_PREFERENCE_PROFILE_SIZE_ERROR"]
                       }];
        }
        [self showError:error];
        return;
    }

    id profile = [NSJSONSerialization JSONObjectWithData:data
                                                 options:0
                                                   error:&error];
    if (![profile isKindOfClass:NSDictionary.class] ||
        ![BHTSettings applyPreferenceProfile:profile error:&error]) {
        [self showError:error];
        return;
    }

    [BHTThemePresets reapplyCurrentAccent];
    self.themePresets = [BHTThemePresets availablePresets];
    self.userThemes = [BHTThemePresets userThemes];
    [self applyCurrentTheme];
    [self.tableView reloadData];
    [self showAlertWithTitleKey:@"IMPORT_PREFERENCE_PROFILE_SUCCESS_TITLE"
                    messageKey:@"IMPORT_PREFERENCE_PROFILE_SUCCESS_DETAIL"];
}

- (void)showError:(NSError*)error {
    NSString* fallback = [[BHTBundle sharedBundle]
        localizedStringForKey:@"PREFERENCE_PROFILE_GENERIC_ERROR"];
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[[BHTBundle sharedBundle]
                                     localizedStringForKey:
                                         @"PREFERENCE_PROFILE_ERROR_TITLE"]
                         message:error.localizedDescription ?: fallback
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:[[BHTBundle sharedBundle]
                                       localizedStringForKey:
                                           @"PREFERENCE_PROFILE_OK"]
                             style:UIAlertActionStyleDefault
                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAlertWithTitleKey:(NSString*)titleKey
                   messageKey:(NSString*)messageKey {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[[BHTBundle sharedBundle]
                                     localizedStringForKey:titleKey]
                         message:[[BHTBundle sharedBundle]
                                     localizedStringForKey:messageKey]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:[[BHTBundle sharedBundle]
                                       localizedStringForKey:
                                           @"PREFERENCE_PROFILE_OK"]
                             style:UIAlertActionStyleDefault
                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
