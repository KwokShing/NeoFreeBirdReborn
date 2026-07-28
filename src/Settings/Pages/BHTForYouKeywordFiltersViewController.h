#import <UIKit/UIKit.h>

@class TFNTwitterAccount;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString* const
    BHTForYouFiltersUsernamesSearchTarget;
FOUNDATION_EXPORT NSString* const
    BHTForYouFiltersPostTextSearchTarget;

@interface BHTForYouKeywordFiltersViewController : UITableViewController

- (instancetype)initWithAccount:(nullable TFNTwitterAccount*)account;

// Global settings search supplies one of the two stable identifiers above.
// The matching section's Add row is scrolled into view and highlighted after
// the controller becomes visible.
@property(nonatomic, copy, nullable) NSString*
    settingsSearchTargetIdentifier;

@end

NS_ASSUME_NONNULL_END
