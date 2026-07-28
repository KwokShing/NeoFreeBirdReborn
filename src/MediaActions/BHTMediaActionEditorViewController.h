#import <UIKit/UIKit.h>
#import "MediaActions/BHTMediaActionUtility.h"

@class TFNTwitterAccount;

NS_ASSUME_NONNULL_BEGIN

@interface BHTMediaActionEditorViewController : UIViewController

- (instancetype)initWithKind:(BHTMediaActionKind)kind
                      account:(nullable TFNTwitterAccount*)account;

// Settings search supplies an action's stable TabPageKey. The matching grid
// item is revealed and highlighted without changing visibility or order.
@property(nonatomic, copy, nullable) NSString*
    settingsSearchTargetIdentifier;

@end

NS_ASSUME_NONNULL_END
