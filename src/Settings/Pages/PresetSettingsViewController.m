#import "Settings/Pages/PresetSettingsViewController.h"

#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"
#import "ThemeColor/BHTThemePresets.h"
#import "ThemeColor/Palette.h"

static const NSUInteger kBHTMaximumProfileBytes = 512 * 1024;

@interface PresetSettingsViewController ()
@property (nonatomic, strong) TFNTwitterAccount* account;
@property (nonatomic, strong) UITableView* tableView;
@property (nonatomic, copy) NSArray<NSDictionary*>* themePresets;
@end

@implementation PresetSettingsViewController

- (instancetype)initWithAccount:(TFNTwitterAccount*)account {
    if ((self = [super init])) {
        _account = account;
        _themePresets = [BHTThemePresets availablePresets];
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

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView*)tableView
 numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? self.themePresets.count : 2;
}

- (NSString*)tableView:(UITableView*)tableView
    titleForHeaderInSection:(NSInteger)section {
    NSString* key = section == 0 ? @"THEME_PRESETS_SECTION_TITLE"
                                 : @"PREFERENCE_PROFILES_SECTION_TITLE";
    return [[BHTBundle sharedBundle] localizedStringForKey:key];
}

- (NSString*)tableView:(UITableView*)tableView
    titleForFooterInSection:(NSInteger)section {
    if (section != 1) return nil;
    return [[BHTBundle sharedBundle]
        localizedStringForKey:@"PREFERENCE_PROFILES_FOOTER"];
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSString* reuseIdentifier =
        indexPath.section == 0 ? @"ThemePresetCell" : @"ProfileActionCell";
    UITableViewCell* cell =
        [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc]
              initWithStyle:UITableViewCellStyleSubtitle
            reuseIdentifier:reuseIdentifier];
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.numberOfLines = 0;
        cell.backgroundColor = [Palette currentBackgroundColor];
    }

    if (indexPath.section == 0) {
        NSDictionary* preset = self.themePresets[indexPath.row];
        cell.textLabel.text = [[BHTBundle sharedBundle]
            localizedStringForKey:preset[@"titleKey"]];
        cell.detailTextLabel.text = [[BHTBundle sharedBundle]
            localizedStringForKey:preset[@"detailKey"]];
        BOOL active =
            [preset[@"identifier"]
                isEqualToString:[BHTThemePresets activePresetIdentifier]];
        cell.accessoryType =
            active ? UITableViewCellAccessoryCheckmark
                   : UITableViewCellAccessoryNone;
        id hex = preset[@"accentHex"];
        cell.imageView.image =
            [UIImage systemImageNamed:@"circle.fill"];
        cell.imageView.tintColor =
            hex == NSNull.null
                ? UIColor.systemBlueColor
                : ([Palette colorFromHexString:hex] ?:
                                                   UIColor.systemBlueColor);
        cell.accessibilityTraits =
            active ? UIAccessibilityTraitButton |
                         UIAccessibilityTraitSelected
                   : UIAccessibilityTraitButton;
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
        cell.imageView.tintColor = UIColor.systemBlueColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return cell;
}

- (void)tableView:(UITableView*)tableView
    didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        NSDictionary* preset = self.themePresets[indexPath.row];
        if ([BHTThemePresets
                applyPresetIdentifier:preset[@"identifier"]]) {
            [tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                     withRowAnimation:UITableViewRowAnimationAutomatic];
        }
        return;
    }
    if (indexPath.row == 0) {
        [self exportProfile];
    } else {
        [self importProfile];
    }
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
