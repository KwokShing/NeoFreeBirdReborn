#import "Settings/Pages/BHTForYouKeywordFiltersViewController.h"

#import "Core/BHTBundle.h"
#import "Headers/TWHeaders.h"
#import "ThemeColor/Palette.h"
#import "Timeline/BHTForYouKeywordFilter.h"

NSString* const BHTForYouFiltersUsernamesSearchTarget =
    @"for_you_filters.usernames";
NSString* const BHTForYouFiltersPostTextSearchTarget =
    @"for_you_filters.post_text";

typedef NS_ENUM(NSInteger, BHTForYouFiltersSection) {
    BHTForYouFiltersSectionUsernames = 0,
    BHTForYouFiltersSectionPostText,
    BHTForYouFiltersSectionCount,
};

static NSString* BHTForYouFiltersLocalized(NSString* key,
                                           NSString* fallback) {
    NSString* value =
        [[BHTBundle sharedBundle] localizedStringForKey:key];
    return value.length > 0 && ![value isEqualToString:key]
               ? value
               : fallback;
}

static void BHTPulseForYouFilterTarget(UIView* target) {
    if (!target.window) return;
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,
                                    target);
    if (UIAccessibilityIsReduceMotionEnabled()) {
        UIColor* accent =
            [Palette customAccentColor] ?: UIColor.systemBlueColor;
        UIView* spotlight =
            [[UIView alloc] initWithFrame:CGRectInset(target.bounds, 3, 2)];
        spotlight.autoresizingMask =
            UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;
        spotlight.userInteractionEnabled = NO;
        spotlight.backgroundColor =
            [accent colorWithAlphaComponent:0.14];
        spotlight.layer.cornerRadius = 12;
        spotlight.layer.borderWidth = 2;
        spotlight.layer.borderColor = accent.CGColor;
        [target addSubview:spotlight];
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(0.9 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                [spotlight removeFromSuperview];
            });
        return;
    }
    CGAffineTransform original = target.transform;
    [UIView animateWithDuration:0.18
                          delay:0
                        options:UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionCurveEaseInOut
                     animations:^{
                         target.transform =
                             CGAffineTransformScale(original, 1.025, 1.025);
                     }
                     completion:^(__unused BOOL finished) {
                         [UIView animateWithDuration:0.18
                                               delay:0
                                             options:
                                                 UIViewAnimationOptionAllowUserInteraction |
                                                 UIViewAnimationOptionCurveEaseInOut
                                          animations:^{
                                              target.transform = original;
                                          }
                                          completion:nil];
                     }];
}

@interface BHTForYouKeywordFiltersViewController ()
@property(nonatomic, strong) TFNTwitterAccount* account;
@property(nonatomic, copy) NSArray<NSString*>* usernameKeywords;
@property(nonatomic, copy) NSArray<NSString*>* postTextKeywords;
@property(nonatomic, assign) BOOL applyingLocalKeywordMutation;
@end

@implementation BHTForYouKeywordFiltersViewController

- (instancetype)init {
    return [self initWithAccount:nil];
}

- (instancetype)initWithAccount:(TFNTwitterAccount*)account {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _account = account;
        [self reloadKeywordSnapshots];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSString* title =
        BHTForYouFiltersLocalized(@"FOR_YOU_KEYWORD_FILTERS_TITLE",
                                  @"For You filters");
    Class titleViewClass = objc_getClass("TFNTitleView");
    if (self.account &&
        [titleViewClass respondsToSelector:
                            @selector(titleViewWithTitle:subtitle:)]) {
        self.navigationItem.titleView =
            [titleViewClass
                titleViewWithTitle:title
                          subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }

    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52;
    [self applyCurrentTheme];

    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(keywordFiltersDidChange:)
               name:BHTForYouKeywordFiltersDidChangeNotification
             object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadKeywordSnapshots];
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

- (void)reloadKeywordSnapshots {
    self.usernameKeywords =
        [BHTForYouKeywordFilter usernameKeywords];
    self.postTextKeywords =
        [BHTForYouKeywordFilter postTextKeywords];
}

- (void)keywordFiltersDidChange:(NSNotification*)notification {
    if (self.applyingLocalKeywordMutation) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadKeywordSnapshots];
        if (self.isViewLoaded) [self.tableView reloadData];
    });
}

#pragma mark - Sections

- (BHTForYouKeywordFilterKind)kindForSection:(NSInteger)section {
    return section == BHTForYouFiltersSectionPostText
               ? BHTForYouKeywordFilterKindPostText
               : BHTForYouKeywordFilterKindUsername;
}

- (NSArray<NSString*>*)keywordsForSection:(NSInteger)section {
    return section == BHTForYouFiltersSectionPostText
               ? self.postTextKeywords
               : self.usernameKeywords;
}

- (BOOL)isAddRowAtIndexPath:(NSIndexPath*)indexPath {
    return indexPath.row ==
           (NSInteger)[self keywordsForSection:indexPath.section].count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return BHTForYouFiltersSectionCount;
}

- (NSInteger)tableView:(UITableView*)tableView
 numberOfRowsInSection:(NSInteger)section {
    return [self keywordsForSection:section].count + 1;
}

- (NSString*)tableView:(UITableView*)tableView
    titleForHeaderInSection:(NSInteger)section {
    if (section == BHTForYouFiltersSectionPostText) {
        return BHTForYouFiltersLocalized(
            @"FOR_YOU_FILTERS_POST_TEXT_SECTION_TITLE",
            @"Post text & @mentions");
    }
    return BHTForYouFiltersLocalized(
        @"FOR_YOU_FILTERS_USERNAMES_SECTION_TITLE",
        @"Accounts & @mentions");
}

- (NSString*)tableView:(UITableView*)tableView
    titleForFooterInSection:(NSInteger)section {
    if (section == BHTForYouFiltersSectionPostText) {
        return BHTForYouFiltersLocalized(
            @"FOR_YOU_FILTERS_POST_TEXT_SECTION_FOOTER",
            @"Hides a For You post when any version of its primary text, "
             @"including leading @mentions, contains one of these words or "
             @"phrases. Changes apply when you return to For You or it "
              @"refreshes. "
             @"Following is never filtered.");
    }
    return BHTForYouFiltersLocalized(
        @"FOR_YOU_FILTERS_USERNAMES_SECTION_FOOTER",
        @"Hides a For You post when the visible author or reposting "
         @"account's username or display name contains a match, or when "
         @"the post mentions a matching @handle. Changes apply when you "
         @"return to For You or it refreshes. Following is never filtered.");
}

- (UIView*)sectionTextViewWithText:(NSString*)text
                              font:(UIFont*)font
                             color:(UIColor*)color {
    UIView* container = [UIView new];
    container.backgroundColor = UIColor.clearColor;

    UILabel* label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.adjustsFontForContentSizeCategory = YES;
    label.font = font;
    label.textColor = color;
    label.text = text;
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor
            constraintEqualToAnchor:container.leadingAnchor
                           constant:20],
        [label.trailingAnchor
            constraintEqualToAnchor:container.trailingAnchor
                           constant:-20],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor
                                         constant:6],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor
                                            constant:-6]
    ]];
    return container;
}

- (UIView*)tableView:(UITableView*)tableView
    viewForHeaderInSection:(NSInteger)section {
    UIView* header = [self
        sectionTextViewWithText:
            [self tableView:tableView titleForHeaderInSection:section]
                           font:[UIFont
                                    preferredFontForTextStyle:
                                        UIFontTextStyleHeadline]
                          color:[Palette currentTextColor]];
    UIView* firstSubview = header.subviews.firstObject;
    if ([firstSubview isKindOfClass:UILabel.class]) {
        ((UILabel*)firstSubview).accessibilityTraits |=
            UIAccessibilityTraitHeader;
    }
    return header;
}

- (UIView*)tableView:(UITableView*)tableView
    viewForFooterInSection:(NSInteger)section {
    return [self
        sectionTextViewWithText:
            [self tableView:tableView titleForFooterInSection:section]
                           font:[UIFont
                                    preferredFontForTextStyle:
                                        UIFontTextStyleFootnote]
                          color:[Palette currentSecondaryTextColor]];
}

- (CGFloat)tableView:(UITableView*)tableView
    heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView*)tableView
    heightForFooterInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

#pragma mark - Cells

- (UITableViewCell*)reusableCellForTableView:(UITableView*)tableView {
    static NSString* const identifier = @"ForYouKeywordCell";
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
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessibilityIdentifier = nil;
    cell.accessibilityHint = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    UITableViewCell* cell =
        [self reusableCellForTableView:tableView];
    if ([self isAddRowAtIndexPath:indexPath]) {
        cell.textLabel.text =
            BHTForYouFiltersLocalized(@"FOR_YOU_FILTERS_ADD_KEYWORD",
                                      @"Add keyword...");
        cell.textLabel.textColor =
            [Palette customAccentColor] ?: UIColor.systemBlueColor;
        cell.imageView.image =
            [UIImage systemImageNamed:@"plus.circle.fill"];
        cell.imageView.tintColor = cell.textLabel.textColor;
        cell.accessibilityIdentifier =
            indexPath.section == BHTForYouFiltersSectionPostText
                ? BHTForYouFiltersPostTextSearchTarget
                : BHTForYouFiltersUsernamesSearchTarget;
        return cell;
    }

    NSString* keyword =
        [self keywordsForSection:indexPath.section][indexPath.row];
    cell.textLabel.text = keyword;
    cell.detailTextLabel.text =
        BHTForYouFiltersLocalized(@"FOR_YOU_FILTERS_TAP_TO_EDIT",
                                  @"Tap to edit");
    cell.accessibilityHint = cell.detailTextLabel.text;
    return cell;
}

#pragma mark - Editing

- (BOOL)tableView:(UITableView*)tableView
    canEditRowAtIndexPath:(NSIndexPath*)indexPath {
    return ![self isAddRowAtIndexPath:indexPath];
}

- (UITableViewCellEditingStyle)tableView:(UITableView*)tableView
    editingStyleForRowAtIndexPath:(NSIndexPath*)indexPath {
    return [self isAddRowAtIndexPath:indexPath]
               ? UITableViewCellEditingStyleNone
               : UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView*)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath*)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete ||
        [self isAddRowAtIndexPath:indexPath]) {
        return;
    }

    BHTForYouKeywordFilterKind kind =
        [self kindForSection:indexPath.section];
    self.applyingLocalKeywordMutation = YES;
    BOOL removed =
        [BHTForYouKeywordFilter removeKeywordAtIndex:indexPath.row
                                             forKind:kind];
    self.applyingLocalKeywordMutation = NO;
    if (removed) {
        [self reloadKeywordSnapshots];
        [tableView deleteRowsAtIndexPaths:@[indexPath]
                         withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)tableView:(UITableView*)tableView
    didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self isAddRowAtIndexPath:indexPath]) {
        [self presentKeywordEditorForKind:
                  [self kindForSection:indexPath.section]
                                  index:NSNotFound];
        return;
    }
    [self presentKeywordEditorForKind:
              [self kindForSection:indexPath.section]
                              index:indexPath.row];
}

- (void)presentKeywordEditorForKind:
            (BHTForYouKeywordFilterKind)kind
                              index:(NSUInteger)index {
    NSArray<NSString*>* keywords =
        [BHTForYouKeywordFilter keywordsForKind:kind];
    BOOL editing = index != NSNotFound && index < keywords.count;
    NSString* title = BHTForYouFiltersLocalized(
        editing ? @"FOR_YOU_FILTERS_EDIT_KEYWORD_TITLE"
                : @"FOR_YOU_FILTERS_ADD_KEYWORD_TITLE",
        editing ? @"Edit keyword" : @"Add keyword");
    NSString* message =
        kind == BHTForYouKeywordFilterKindUsername
            ? BHTForYouFiltersLocalized(
                  @"FOR_YOU_FILTERS_USERNAME_EDITOR_DETAIL",
                  @"Matches literal text in author and reposter usernames "
                   @"or display names, plus @handles mentioned in the post. "
                   @"An optional leading @ is ignored.")
            : BHTForYouFiltersLocalized(
                  @"FOR_YOU_FILTERS_POST_TEXT_EDITOR_DETAIL",
                  @"Matches literal text in the primary post, including "
                   @"@mentions.");

    UIAlertController* alert =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:
                                         UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField* textField) {
        textField.text = editing ? keywords[index] : nil;
        textField.placeholder =
            BHTForYouFiltersLocalized(
                @"FOR_YOU_FILTERS_KEYWORD_PLACEHOLDER", @"Word or phrase");
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocorrectionType =
            kind == BHTForYouKeywordFilterKindUsername
                ? UITextAutocorrectionTypeNo
                : UITextAutocorrectionTypeDefault;
        textField.autocapitalizationType =
            kind == BHTForYouKeywordFilterKindUsername
                ? UITextAutocapitalizationTypeNone
                : UITextAutocapitalizationTypeSentences;
        textField.returnKeyType = UIReturnKeyDone;
    }];
    UITextField* keywordField = alert.textFields.firstObject;

    __weak typeof(self) weakSelf = self;
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:
                       BHTForYouFiltersLocalized(
                           @"FOR_YOU_FILTERS_CANCEL", @"Cancel")
                             style:UIAlertActionStyleCancel
                           handler:nil]];
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:
                       BHTForYouFiltersLocalized(
                           @"FOR_YOU_FILTERS_SAVE", @"Save")
                             style:UIAlertActionStyleDefault
                           handler:^(__unused UIAlertAction* action) {
                               NSString* value =
                                   keywordField.text ?: @"";
                               NSError* error = nil;
                               weakSelf.applyingLocalKeywordMutation = YES;
                               BOOL saved =
                                   editing
                                       ? [BHTForYouKeywordFilter
                                             replaceKeywordAtIndex:index
                                                      withKeyword:value
                                                          forKind:kind
                                                            error:&error]
                                       : [BHTForYouKeywordFilter
                                             addKeyword:value
                                               forKind:kind
                                                 error:&error];
                               weakSelf.applyingLocalKeywordMutation = NO;
                               if (!saved) {
                                   // Wait for the text-entry alert to finish
                                   // dismissing before presenting validation
                                   // feedback. UIKit otherwise rejects the
                                   // second presentation on some iPad builds.
                                   dispatch_after(
                                       dispatch_time(
                                           DISPATCH_TIME_NOW,
                                           (int64_t)(0.3 *
                                                     NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{
                                           [weakSelf
                                               showKeywordError:error];
                                       });
                                   return;
                               }
                               [weakSelf reloadKeywordSnapshots];
                               [weakSelf.tableView reloadData];
                           }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showKeywordError:(NSError*)error {
    if (!self.view.window) return;
    UIAlertController* alert =
        [UIAlertController
            alertControllerWithTitle:
                BHTForYouFiltersLocalized(
                    @"FOR_YOU_FILTERS_ERROR_TITLE",
                    @"Could not save keyword")
                             message:error.localizedDescription ?:
                                 BHTForYouFiltersLocalized(
                                     @"FOR_YOU_FILTERS_GENERIC_ERROR",
                                     @"Check the keyword and try again.")
                      preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:
                       BHTForYouFiltersLocalized(
                           @"PREFERENCE_PROFILE_OK", @"OK")
                             style:UIAlertActionStyleDefault
                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Settings Search

- (void)revealSettingsSearchTargetIfNeeded {
    NSString* target = self.settingsSearchTargetIdentifier;
    if (target.length == 0 || !self.tableView.window) return;
    self.settingsSearchTargetIdentifier = nil;

    NSInteger section = -1;
    if ([target isEqualToString:
                    BHTForYouFiltersUsernamesSearchTarget]) {
        section = BHTForYouFiltersSectionUsernames;
    } else if ([target isEqualToString:
                           BHTForYouFiltersPostTextSearchTarget]) {
        section = BHTForYouFiltersSectionPostText;
    }
    if (section < 0) return;

    NSIndexPath* addPath =
        [NSIndexPath
            indexPathForRow:[self keywordsForSection:section].count
                  inSection:section];
    [self.tableView scrollToRowAtIndexPath:addPath
                         atScrollPosition:UITableViewScrollPositionMiddle
                                 animated:NO];
    [self.tableView layoutIfNeeded];
    UITableViewCell* cell =
        [self.tableView cellForRowAtIndexPath:addPath];
    if (cell) {
        BHTPulseForYouFilterTarget(cell);
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UITableViewCell* deferredCell =
            [weakSelf.tableView cellForRowAtIndexPath:addPath];
        BHTPulseForYouFilterTarget(deferredCell);
    });
}

@end
