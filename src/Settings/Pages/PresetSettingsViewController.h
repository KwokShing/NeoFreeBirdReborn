#import <UIKit/UIKit.h>

@class TFNTwitterAccount;

@interface PresetSettingsViewController
    : UIViewController <UITableViewDataSource, UITableViewDelegate,
                        UIDocumentPickerDelegate>

- (instancetype)initWithAccount:(TFNTwitterAccount*)account;

@end
