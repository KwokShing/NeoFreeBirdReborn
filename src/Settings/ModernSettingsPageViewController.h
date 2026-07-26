//
//  ModernSettingsPageViewController.h
//  NeoFreeBird
//
//  Created by nyaathea
//

#import <UIKit/UIKit.h>

@class TFNTwitterAccount;

NSString* BHTSettingsKeyForSwitch(UISwitch* settingsSwitch);
void BHTMarkNeoFreeBirdFontPicker(UIFontPickerViewController* picker,
                                  NSString* fontType);
NSString* BHTFontTypeForPicker(UIFontPickerViewController* picker);

@interface ModernSettingsPageViewController
    : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) TFNTwitterAccount* account;
@property (nonatomic, strong) UITableView* tableView;
@property (nonatomic, strong) NSArray<NSDictionary*>* toggles;
@property (nonatomic, strong) NSArray<NSDictionary*>* visibleToggles;
// Set before presentation by global settings search. The page scrolls to and
// briefly highlights the matching key or title key once its table is visible.
@property (nonatomic, copy, nullable) NSString* settingsSearchTargetIdentifier;

- (instancetype)initWithAccount:(TFNTwitterAccount*)account;

// Data-only pages are created directly with their registry key; pages with
// custom behaviour subclass this and override -pageKey instead.
- (instancetype)initWithAccount:(TFNTwitterAccount*)account pageKey:(NSString*)pageKey;

// Identifies the page's entry in the BHTSettings registry
- (NSString*)pageKey;

- (NSString*)pageTitleKey;
- (NSString*)pageSubtitleKey;
- (void)buildSettingsList;

- (void)updateVisibleToggles;
- (nullable NSDictionary*)settingAtIndexPath:(NSIndexPath*)indexPath;
- (void)switchChanged:(UISwitch*)sender;

@end
