#import <UIKit/UIKit.h>

@class TFNTwitterAccount;

@interface PresetSettingsViewController
    : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (instancetype)initWithAccount:(TFNTwitterAccount*)account;

// Settings search supplies one of the stable targets handled by the Themes
// screen: a built-in/user theme identifier, themes.create, or
// themes.accent_only. Only the two action rows are auto-opened.
@property(nonatomic, copy, nullable) NSString*
    settingsSearchTargetIdentifier;
@property(nonatomic, assign) BOOL settingsSearchShouldOpenTarget;

@end
