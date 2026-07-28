#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Pass nil to create a new theme based on the active full theme. Passing a
// user-theme dictionary edits it; passing a duplicate draft creates a copy.
@interface BHTThemeBuilderViewController : UIViewController

- (instancetype)initWithTheme:(nullable NSDictionary*)theme;

@end

NS_ASSUME_NONNULL_END
