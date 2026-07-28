#import "ThemeColor/BHTThemeBuilderViewController.h"

#import <math.h>

#import "Core/BHTBundle.h"
#import "ThemeColor/BHTThemePresets.h"
#import "ThemeColor/Palette.h"

static const CGFloat BHTThemeBuilderMaximumReadableWidth = 720.0;
static const NSUInteger BHTThemeBuilderMaximumNameLength = 64;

typedef NS_ENUM(NSInteger, BHTThemeBuilderSection) {
    BHTThemeBuilderSectionPreview = 0,
    BHTThemeBuilderSectionName,
    BHTThemeBuilderSectionColors,
    BHTThemeBuilderSectionActions,
    BHTThemeBuilderSectionCount
};

static NSString* BHTThemeBuilderLocalized(NSString* key,
                                          NSString* fallback) {
    NSString* localized =
        [[BHTBundle sharedBundle] localizedStringForKey:key];
    if (localized.length == 0 || [localized isEqualToString:key]) {
        return fallback;
    }
    return localized;
}

static NSArray<NSString*>* BHTThemeBuilderRoles(void) {
    static NSArray<NSString*>* roles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        roles = @[
            BHTThemeColorAccentKey,
            BHTThemeColorBackgroundKey,
            BHTThemeColorSurfaceKey,
            BHTThemeColorElevatedSurfaceKey,
            BHTThemeColorTextKey,
            BHTThemeColorSecondaryTextKey,
            BHTThemeColorSeparatorKey
        ];
    });
    return roles;
}

static NSString* BHTThemeBuilderRoleName(NSString* role) {
    if ([role isEqualToString:BHTThemeColorAccentKey]) {
        return BHTThemeBuilderLocalized(
            @"THEME_BUILDER_ACCENT", @"Accent");
    }
    if ([role isEqualToString:BHTThemeColorBackgroundKey]) {
        return BHTThemeBuilderLocalized(
            @"THEME_BUILDER_BACKGROUND", @"Background");
    }
    if ([role isEqualToString:BHTThemeColorSurfaceKey]) {
        return BHTThemeBuilderLocalized(
            @"THEME_BUILDER_SURFACE", @"Surface");
    }
    if ([role isEqualToString:BHTThemeColorElevatedSurfaceKey]) {
        return BHTThemeBuilderLocalized(
            @"THEME_BUILDER_ELEVATED_SURFACE",
            @"Elevated surface");
    }
    if ([role isEqualToString:BHTThemeColorTextKey]) {
        return BHTThemeBuilderLocalized(
            @"THEME_BUILDER_TEXT", @"Primary text");
    }
    if ([role isEqualToString:BHTThemeColorSecondaryTextKey]) {
        return BHTThemeBuilderLocalized(
            @"THEME_BUILDER_SECONDARY_TEXT",
            @"Secondary text");
    }
    if ([role isEqualToString:BHTThemeColorSeparatorKey]) {
        return BHTThemeBuilderLocalized(
            @"THEME_BUILDER_SEPARATOR", @"Separator");
    }
    return role ?: @"Color";
}

static NSString* BHTThemeBuilderNormalizedOpaqueHex(NSString* value) {
    NSString* normalized = [Palette normalizedHexString:value];
    return normalized.length == 7 ? normalized : nil;
}

static CGFloat BHTThemeBuilderClampColorComponent(CGFloat value) {
    return MIN(1.0, MAX(0.0, value));
}

static NSString* BHTThemeBuilderHexFromColor(
    UIColor* color, UITraitCollection* traitCollection) {
    if (![color isKindOfClass:UIColor.class]) return nil;
    UIColor* resolved =
        [color resolvedColorWithTraitCollection:
                   traitCollection ?: UITraitCollection.currentTraitCollection];
    CGFloat red = 0;
    CGFloat green = 0;
    CGFloat blue = 0;
    CGFloat alpha = 1;
    if (![resolved getRed:&red
                    green:&green
                     blue:&blue
                    alpha:&alpha]) {
        CGFloat white = 0;
        if (![resolved getWhite:&white alpha:&alpha]) return nil;
        red = white;
        green = white;
        blue = white;
    }
    NSUInteger redByte =
        (NSUInteger)(BHTThemeBuilderClampColorComponent(red) * 255.0 + 0.5);
    NSUInteger greenByte =
        (NSUInteger)(BHTThemeBuilderClampColorComponent(green) * 255.0 + 0.5);
    NSUInteger blueByte =
        (NSUInteger)(BHTThemeBuilderClampColorComponent(blue) * 255.0 + 0.5);
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX",
                                      (unsigned long)redByte,
                                      (unsigned long)greenByte,
                                      (unsigned long)blueByte];
}

static CGFloat BHTThemeBuilderLinearComponent(CGFloat component) {
    component = BHTThemeBuilderClampColorComponent(component);
    return component <= 0.03928
               ? component / 12.92
               : pow((component + 0.055) / 1.055, 2.4);
}

static CGFloat BHTThemeBuilderRelativeLuminance(UIColor* color) {
    CGFloat red = 0;
    CGFloat green = 0;
    CGFloat blue = 0;
    CGFloat alpha = 1;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        CGFloat white = 0;
        if (![color getWhite:&white alpha:&alpha]) return 0;
        red = white;
        green = white;
        blue = white;
    }
    return 0.2126 * BHTThemeBuilderLinearComponent(red) +
           0.7152 * BHTThemeBuilderLinearComponent(green) +
           0.0722 * BHTThemeBuilderLinearComponent(blue);
}

static CGFloat BHTThemeBuilderContrastRatio(UIColor* first,
                                            UIColor* second) {
    CGFloat firstLuminance = BHTThemeBuilderRelativeLuminance(first);
    CGFloat secondLuminance = BHTThemeBuilderRelativeLuminance(second);
    CGFloat lighter = MAX(firstLuminance, secondLuminance);
    CGFloat darker = MIN(firstLuminance, secondLuminance);
    return (lighter + 0.05) / (darker + 0.05);
}

@interface BHTThemeBuilderHexField : UITextField
@property(nonatomic, copy) NSString* themeRole;
@property(nonatomic, copy) NSString* themeMapKey;
@end

@implementation BHTThemeBuilderHexField
@end

@interface BHTThemeBuilderColorWell : UIColorWell
@property(nonatomic, copy) NSString* themeRole;
@property(nonatomic, copy) NSString* themeMapKey;
@end

@implementation BHTThemeBuilderColorWell
@end

@interface BHTThemeBuilderNameCell : UITableViewCell
@property(nonatomic, strong) UITextField* nameField;
@end

@implementation BHTThemeBuilderNameCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    if ((self = [super initWithStyle:style
                      reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.nameField = [UITextField new];
        self.nameField.translatesAutoresizingMaskIntoConstraints = NO;
        self.nameField.clearButtonMode =
            UITextFieldViewModeWhileEditing;
        self.nameField.returnKeyType = UIReturnKeyDone;
        self.nameField.autocapitalizationType =
            UITextAutocapitalizationTypeWords;
        self.nameField.autocorrectionType =
            UITextAutocorrectionTypeDefault;
        self.nameField.font =
            [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        self.nameField.adjustsFontForContentSizeCategory = YES;
        [self.contentView addSubview:self.nameField];

        [NSLayoutConstraint activateConstraints:@[
            [self.nameField.leadingAnchor
                constraintEqualToAnchor:
                    self.contentView.layoutMarginsGuide.leadingAnchor],
            [self.nameField.trailingAnchor
                constraintEqualToAnchor:
                    self.contentView.layoutMarginsGuide.trailingAnchor],
            [self.nameField.topAnchor
                constraintEqualToAnchor:self.contentView.topAnchor
                               constant:12],
            [self.nameField.bottomAnchor
                constraintEqualToAnchor:self.contentView.bottomAnchor
                               constant:-12],
            [self.nameField.heightAnchor
                constraintGreaterThanOrEqualToConstant:28]
        ]];
        [self applyCurrentTheme];
    }
    return self;
}

- (void)applyCurrentTheme {
    self.backgroundColor = [Palette currentSurfaceColor];
    self.nameField.textColor = [Palette currentTextColor];
}

- (void)traitCollectionDidChange:
    (UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyCurrentTheme];
}

@end

@interface BHTThemeBuilderColorCell : UITableViewCell
@property(nonatomic, strong) UILabel* roleLabel;
@property(nonatomic, strong) BHTThemeBuilderHexField* hexField;
@property(nonatomic, strong) BHTThemeBuilderColorWell* colorWell;
- (void)configureWithRole:(NSString*)role
                   mapKey:(NSString*)mapKey
                   rawHex:(NSString*)rawHex
               previewHex:(NSString*)previewHex
                 delegate:(id<UITextFieldDelegate>)delegate
                   target:(id)target
         fieldChangedAction:(SEL)fieldChangedAction
       fieldDidEndAction:(SEL)fieldDidEndAction
        colorChangedAction:(SEL)colorChangedAction;
@end

@implementation BHTThemeBuilderColorCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    if ((self = [super initWithStyle:style
                      reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        self.roleLabel = [UILabel new];
        self.roleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.roleLabel.font =
            [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        self.roleLabel.adjustsFontForContentSizeCategory = YES;
        self.roleLabel.numberOfLines = 0;
        [self.contentView addSubview:self.roleLabel];

        self.hexField = [BHTThemeBuilderHexField new];
        self.hexField.translatesAutoresizingMaskIntoConstraints = NO;
        self.hexField.textAlignment = NSTextAlignmentLeft;
        self.hexField.autocapitalizationType =
            UITextAutocapitalizationTypeAllCharacters;
        self.hexField.autocorrectionType =
            UITextAutocorrectionTypeNo;
        self.hexField.spellCheckingType =
            UITextSpellCheckingTypeNo;
        self.hexField.keyboardType =
            UIKeyboardTypeASCIICapable;
        self.hexField.returnKeyType = UIReturnKeyDone;
        self.hexField.clearButtonMode =
            UITextFieldViewModeNever;
        self.hexField.adjustsFontForContentSizeCategory = YES;
        [self updateHexFieldFont];
        [self.contentView addSubview:self.hexField];

        self.colorWell = [BHTThemeBuilderColorWell new];
        self.colorWell.translatesAutoresizingMaskIntoConstraints = NO;
        self.colorWell.supportsAlpha = NO;
        [self.contentView addSubview:self.colorWell];

        [NSLayoutConstraint activateConstraints:@[
            [self.roleLabel.leadingAnchor
                constraintEqualToAnchor:
                    self.contentView.layoutMarginsGuide.leadingAnchor],
            [self.roleLabel.topAnchor
                constraintEqualToAnchor:self.contentView.topAnchor
                               constant:12],
            [self.roleLabel.trailingAnchor
                constraintEqualToAnchor:
                    self.contentView.layoutMarginsGuide.trailingAnchor],

            [self.hexField.leadingAnchor
                constraintEqualToAnchor:self.roleLabel.leadingAnchor],
            [self.hexField.topAnchor
                constraintEqualToAnchor:self.roleLabel.bottomAnchor
                               constant:8],
            [self.hexField.trailingAnchor
                constraintEqualToAnchor:self.colorWell.leadingAnchor
                               constant:-10],
            [self.hexField.bottomAnchor
                constraintEqualToAnchor:self.contentView.bottomAnchor
                               constant:-10],
            [self.hexField.heightAnchor
                constraintGreaterThanOrEqualToConstant:44],

            [self.colorWell.trailingAnchor
                constraintEqualToAnchor:
                    self.contentView.layoutMarginsGuide.trailingAnchor],
            [self.colorWell.centerYAnchor
                constraintEqualToAnchor:self.hexField.centerYAnchor],
            [self.colorWell.widthAnchor
                constraintEqualToConstant:44],
            [self.colorWell.heightAnchor
                constraintEqualToConstant:44]
        ]];
        [self applyCurrentTheme];
    }
    return self;
}

- (void)updateHexFieldFont {
    UIFont* monospaced =
        [UIFont monospacedSystemFontOfSize:17.0
                                   weight:UIFontWeightRegular];
    self.hexField.font =
        [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:monospaced];
}

- (void)configureWithRole:(NSString*)role
                   mapKey:(NSString*)mapKey
                   rawHex:(NSString*)rawHex
               previewHex:(NSString*)previewHex
                 delegate:(id<UITextFieldDelegate>)delegate
                   target:(id)target
       fieldChangedAction:(SEL)fieldChangedAction
        fieldDidEndAction:(SEL)fieldDidEndAction
       colorChangedAction:(SEL)colorChangedAction {
    NSString* roleName = BHTThemeBuilderRoleName(role);
    NSString* modeIdentifier =
        [mapKey isEqualToString:@"darkColors"] ? @"dark" : @"light";
    NSString* roleIdentifier =
        [[role ?: @"color"
            stringByReplacingOccurrencesOfString:@" "
                                      withString:@"-"] lowercaseString];

    self.roleLabel.text = roleName;
    self.roleLabel.accessibilityElementsHidden = YES;

    [self.hexField removeTarget:nil
                         action:NULL
               forControlEvents:UIControlEventAllEvents];
    self.hexField.delegate = delegate;
    self.hexField.themeRole = role;
    self.hexField.themeMapKey = mapKey;
    self.hexField.text = rawHex ?: @"";
    self.hexField.textColor =
        BHTThemeBuilderNormalizedOpaqueHex(rawHex)
            ? [Palette currentTextColor]
            : UIColor.systemRedColor;
    self.hexField.accessibilityLabel =
        [NSString stringWithFormat:@"%@, hex color", roleName];
    self.hexField.accessibilityHint =
        @"Enter six hexadecimal digits, for example #1DA1F2.";
    self.hexField.accessibilityIdentifier =
        [NSString stringWithFormat:@"theme-builder-%@-%@-hex",
                                   modeIdentifier, roleIdentifier];
    [self.hexField addTarget:target
                      action:fieldChangedAction
            forControlEvents:UIControlEventEditingChanged];
    [self.hexField addTarget:target
                      action:fieldDidEndAction
            forControlEvents:UIControlEventEditingDidEnd];

    [self.colorWell removeTarget:nil
                          action:NULL
                forControlEvents:UIControlEventAllEvents];
    self.colorWell.themeRole = role;
    self.colorWell.themeMapKey = mapKey;
    self.colorWell.title = roleName;
    self.colorWell.supportsAlpha = NO;
    UIColor* selectedColor =
        [Palette colorFromHexString:previewHex];
    if (selectedColor) {
        self.colorWell.selectedColor = selectedColor;
    }
    self.colorWell.accessibilityLabel =
        [NSString stringWithFormat:@"%@ color picker", roleName];
    self.colorWell.accessibilityHint =
        @"Opens the system color picker.";
    self.colorWell.accessibilityIdentifier =
        [NSString stringWithFormat:@"theme-builder-%@-%@-well",
                                   modeIdentifier, roleIdentifier];
    [self.colorWell addTarget:target
                       action:colorChangedAction
             forControlEvents:UIControlEventValueChanged];
    [self applyCurrentTheme];
}

- (void)applyCurrentTheme {
    self.backgroundColor = [Palette currentSurfaceColor];
    self.roleLabel.textColor = [Palette currentTextColor];
    if (BHTThemeBuilderNormalizedOpaqueHex(self.hexField.text)) {
        self.hexField.textColor = [Palette currentTextColor];
    }
}

- (void)traitCollectionDidChange:
    (UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (previousTraitCollection.preferredContentSizeCategory !=
        self.traitCollection.preferredContentSizeCategory) {
        self.roleLabel.font =
            [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        [self updateHexFieldFont];
    }
    [self applyCurrentTheme];
}

@end

@interface BHTThemeBuilderPreviewView : UIView
@property(nonatomic, strong) UIView* headerView;
@property(nonatomic, strong) UIView* cardView;
@property(nonatomic, strong) UIView* bottomBarView;
@property(nonatomic, strong) UIView* elevatedBadge;
@property(nonatomic, strong) UIView* divider;
@property(nonatomic, strong) UIView* accentDot;
@property(nonatomic, strong) UILabel* selectedTabLabel;
@property(nonatomic, strong) UILabel* unselectedTabLabel;
@property(nonatomic, strong) UILabel* nameLabel;
@property(nonatomic, strong) UILabel* handleLabel;
@property(nonatomic, strong) UILabel* bodyLabel;
@property(nonatomic, strong) UILabel* elevatedLabel;
@property(nonatomic, strong) NSArray<UIImageView*>* bottomIcons;
- (void)configureWithColors:(NSDictionary<NSString*, NSString*>*)colors
             darkAppearance:(BOOL)darkAppearance;
@end

@implementation BHTThemeBuilderPreviewView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.layer.cornerRadius = 16;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        self.isAccessibilityElement = YES;
        self.accessibilityIdentifier = @"theme-builder-preview";

        self.headerView = [UIView new];
        self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.headerView];

        self.accentDot = [UIView new];
        self.accentDot.translatesAutoresizingMaskIntoConstraints = NO;
        self.accentDot.layer.cornerRadius = 7;
        [self.headerView addSubview:self.accentDot];

        self.selectedTabLabel =
            [self previewLabelForTextStyle:UIFontTextStyleSubheadline
                                     weight:UIFontWeightSemibold];
        self.selectedTabLabel.text = @"For you";
        [self.headerView addSubview:self.selectedTabLabel];

        self.unselectedTabLabel =
            [self previewLabelForTextStyle:UIFontTextStyleSubheadline
                                     weight:UIFontWeightRegular];
        self.unselectedTabLabel.text = @"Following";
        [self.headerView addSubview:self.unselectedTabLabel];

        self.cardView = [UIView new];
        self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
        self.cardView.layer.cornerRadius = 13;
        self.cardView.layer.masksToBounds = YES;
        [self addSubview:self.cardView];

        self.nameLabel =
            [self previewLabelForTextStyle:UIFontTextStyleHeadline
                                     weight:UIFontWeightSemibold];
        self.nameLabel.text = BHTThemeBuilderLocalized(
            @"THEME_BUILDER_PREVIEW_NAME", @"NeoFreeBird");
        [self.cardView addSubview:self.nameLabel];

        self.handleLabel =
            [self previewLabelForTextStyle:UIFontTextStyleSubheadline
                                     weight:UIFontWeightRegular];
        self.handleLabel.text = BHTThemeBuilderLocalized(
            @"THEME_BUILDER_PREVIEW_HANDLE",
            @"@theme_preview · now");
        [self.cardView addSubview:self.handleLabel];

        self.bodyLabel =
            [self previewLabelForTextStyle:UIFontTextStyleBody
                                     weight:UIFontWeightRegular];
        self.bodyLabel.numberOfLines = 0;
        self.bodyLabel.text = BHTThemeBuilderLocalized(
            @"THEME_BUILDER_PREVIEW_BODY",
            @"Your custom theme updates here as you edit.");
        [self.cardView addSubview:self.bodyLabel];

        self.elevatedBadge = [UIView new];
        self.elevatedBadge.translatesAutoresizingMaskIntoConstraints = NO;
        self.elevatedBadge.layer.cornerRadius = 10;
        [self.cardView addSubview:self.elevatedBadge];

        self.elevatedLabel =
            [self previewLabelForTextStyle:UIFontTextStyleCaption1
                                     weight:UIFontWeightSemibold];
        self.elevatedLabel.text = BHTThemeBuilderLocalized(
            @"THEME_BUILDER_PREVIEW_ELEVATED", @"Elevated");
        [self.elevatedBadge addSubview:self.elevatedLabel];

        self.divider = [UIView new];
        self.divider.translatesAutoresizingMaskIntoConstraints = NO;
        [self.cardView addSubview:self.divider];

        UIStackView* actionRow = [UIStackView new];
        actionRow.translatesAutoresizingMaskIntoConstraints = NO;
        actionRow.axis = UILayoutConstraintAxisHorizontal;
        actionRow.alignment = UIStackViewAlignmentCenter;
        actionRow.distribution = UIStackViewDistributionEqualSpacing;
        [self.cardView addSubview:actionRow];
        for (NSString* symbolName in
             @[@"bubble.left", @"arrow.2.squarepath", @"heart"]) {
            UIImageView* imageView = [[UIImageView alloc]
                initWithImage:[UIImage systemImageNamed:symbolName]];
            imageView.translatesAutoresizingMaskIntoConstraints = NO;
            imageView.contentMode = UIViewContentModeScaleAspectFit;
            [imageView.widthAnchor constraintEqualToConstant:20].active =
                YES;
            [imageView.heightAnchor constraintEqualToConstant:20].active =
                YES;
            [actionRow addArrangedSubview:imageView];
        }

        self.bottomBarView = [UIView new];
        self.bottomBarView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:self.bottomBarView];

        UIStackView* bottomRow = [UIStackView new];
        bottomRow.translatesAutoresizingMaskIntoConstraints = NO;
        bottomRow.axis = UILayoutConstraintAxisHorizontal;
        bottomRow.alignment = UIStackViewAlignmentCenter;
        bottomRow.distribution = UIStackViewDistributionEqualSpacing;
        [self.bottomBarView addSubview:bottomRow];
        NSMutableArray<UIImageView*>* bottomIcons =
            [NSMutableArray array];
        for (NSString* symbolName in
             @[@"house.fill", @"magnifyingglass", @"heart"]) {
            UIImageView* imageView = [[UIImageView alloc]
                initWithImage:[UIImage systemImageNamed:symbolName]];
            imageView.translatesAutoresizingMaskIntoConstraints = NO;
            imageView.contentMode = UIViewContentModeScaleAspectFit;
            [imageView.widthAnchor constraintEqualToConstant:21].active =
                YES;
            [imageView.heightAnchor constraintEqualToConstant:21].active =
                YES;
            [bottomRow addArrangedSubview:imageView];
            [bottomIcons addObject:imageView];
        }
        self.bottomIcons = [bottomIcons copy];

        CGFloat hairline = 1.0 / UIScreen.mainScreen.scale;
        [NSLayoutConstraint activateConstraints:@[
            [self.headerView.topAnchor
                constraintEqualToAnchor:self.topAnchor],
            [self.headerView.leadingAnchor
                constraintEqualToAnchor:self.leadingAnchor],
            [self.headerView.trailingAnchor
                constraintEqualToAnchor:self.trailingAnchor],
            [self.headerView.heightAnchor
                constraintGreaterThanOrEqualToConstant:44],

            [self.accentDot.leadingAnchor
                constraintEqualToAnchor:self.headerView.leadingAnchor
                               constant:14],
            [self.accentDot.centerYAnchor
                constraintEqualToAnchor:self.headerView.centerYAnchor],
            [self.accentDot.widthAnchor constraintEqualToConstant:14],
            [self.accentDot.heightAnchor constraintEqualToConstant:14],
            [self.selectedTabLabel.leadingAnchor
                constraintEqualToAnchor:self.accentDot.trailingAnchor
                               constant:10],
            [self.selectedTabLabel.centerYAnchor
                constraintEqualToAnchor:self.headerView.centerYAnchor],
            [self.selectedTabLabel.topAnchor
                constraintGreaterThanOrEqualToAnchor:
                    self.headerView.topAnchor
                                             constant:8],
            [self.selectedTabLabel.bottomAnchor
                constraintLessThanOrEqualToAnchor:
                    self.headerView.bottomAnchor
                                          constant:-8],
            [self.unselectedTabLabel.trailingAnchor
                constraintEqualToAnchor:self.headerView.trailingAnchor
                               constant:-14],
            [self.unselectedTabLabel.centerYAnchor
                constraintEqualToAnchor:self.headerView.centerYAnchor],
            [self.unselectedTabLabel.topAnchor
                constraintGreaterThanOrEqualToAnchor:
                    self.headerView.topAnchor
                                             constant:8],
            [self.unselectedTabLabel.bottomAnchor
                constraintLessThanOrEqualToAnchor:
                    self.headerView.bottomAnchor
                                          constant:-8],
            [self.unselectedTabLabel.leadingAnchor
                constraintGreaterThanOrEqualToAnchor:
                    self.selectedTabLabel.trailingAnchor
                                             constant:12],

            [self.cardView.topAnchor
                constraintEqualToAnchor:self.headerView.bottomAnchor
                               constant:10],
            [self.cardView.leadingAnchor
                constraintEqualToAnchor:self.leadingAnchor
                               constant:12],
            [self.cardView.trailingAnchor
                constraintEqualToAnchor:self.trailingAnchor
                               constant:-12],

            [self.nameLabel.topAnchor
                constraintEqualToAnchor:self.cardView.topAnchor
                               constant:12],
            [self.nameLabel.leadingAnchor
                constraintEqualToAnchor:self.cardView.leadingAnchor
                               constant:12],
            [self.nameLabel.trailingAnchor
                constraintLessThanOrEqualToAnchor:
                    self.cardView.trailingAnchor
                                          constant:-12],
            [self.handleLabel.topAnchor
                constraintEqualToAnchor:self.nameLabel.bottomAnchor
                               constant:2],
            [self.handleLabel.leadingAnchor
                constraintEqualToAnchor:self.nameLabel.leadingAnchor],
            [self.handleLabel.trailingAnchor
                constraintLessThanOrEqualToAnchor:
                    self.cardView.trailingAnchor
                                          constant:-12],
            [self.bodyLabel.topAnchor
                constraintEqualToAnchor:self.handleLabel.bottomAnchor
                               constant:10],
            [self.bodyLabel.leadingAnchor
                constraintEqualToAnchor:self.nameLabel.leadingAnchor],
            [self.bodyLabel.trailingAnchor
                constraintEqualToAnchor:self.cardView.trailingAnchor
                               constant:-12],

            [self.elevatedBadge.topAnchor
                constraintEqualToAnchor:self.bodyLabel.bottomAnchor
                               constant:10],
            [self.elevatedBadge.leadingAnchor
                constraintEqualToAnchor:self.nameLabel.leadingAnchor],
            [self.elevatedLabel.topAnchor
                constraintEqualToAnchor:self.elevatedBadge.topAnchor
                               constant:4],
            [self.elevatedLabel.bottomAnchor
                constraintEqualToAnchor:self.elevatedBadge.bottomAnchor
                               constant:-4],
            [self.elevatedLabel.leadingAnchor
                constraintEqualToAnchor:self.elevatedBadge.leadingAnchor
                               constant:9],
            [self.elevatedLabel.trailingAnchor
                constraintEqualToAnchor:self.elevatedBadge.trailingAnchor
                               constant:-9],

            [self.divider.topAnchor
                constraintEqualToAnchor:self.elevatedBadge.bottomAnchor
                               constant:12],
            [self.divider.leadingAnchor
                constraintEqualToAnchor:self.cardView.leadingAnchor
                               constant:12],
            [self.divider.trailingAnchor
                constraintEqualToAnchor:self.cardView.trailingAnchor
                               constant:-12],
            [self.divider.heightAnchor constraintEqualToConstant:hairline],

            [actionRow.topAnchor
                constraintEqualToAnchor:self.divider.bottomAnchor
                               constant:10],
            [actionRow.leadingAnchor
                constraintEqualToAnchor:self.cardView.leadingAnchor
                               constant:24],
            [actionRow.trailingAnchor
                constraintEqualToAnchor:self.cardView.trailingAnchor
                               constant:-24],
            [actionRow.bottomAnchor
                constraintEqualToAnchor:self.cardView.bottomAnchor
                               constant:-11],
            [actionRow.heightAnchor
                constraintGreaterThanOrEqualToConstant:22],

            [self.bottomBarView.topAnchor
                constraintEqualToAnchor:self.cardView.bottomAnchor
                               constant:10],
            [self.bottomBarView.leadingAnchor
                constraintEqualToAnchor:self.leadingAnchor],
            [self.bottomBarView.trailingAnchor
                constraintEqualToAnchor:self.trailingAnchor],
            [self.bottomBarView.bottomAnchor
                constraintEqualToAnchor:self.bottomAnchor],
            [self.bottomBarView.heightAnchor
                constraintGreaterThanOrEqualToConstant:44],
            [bottomRow.leadingAnchor
                constraintEqualToAnchor:self.bottomBarView.leadingAnchor
                               constant:38],
            [bottomRow.trailingAnchor
                constraintEqualToAnchor:self.bottomBarView.trailingAnchor
                               constant:-38],
            [bottomRow.topAnchor
                constraintEqualToAnchor:self.bottomBarView.topAnchor
                               constant:10],
            [bottomRow.bottomAnchor
                constraintEqualToAnchor:self.bottomBarView.bottomAnchor
                               constant:-10],

            [self.heightAnchor
                constraintGreaterThanOrEqualToConstant:245]
        ]];
    }
    return self;
}

- (UILabel*)previewLabelForTextStyle:(UIFontTextStyle)textStyle
                               weight:(UIFontWeight)weight {
    UILabel* label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UIFont* preferred = [UIFont preferredFontForTextStyle:textStyle];
    UIFontDescriptor* descriptor = preferred.fontDescriptor;
    if (weight >= UIFontWeightSemibold) {
        UIFontDescriptor* boldDescriptor =
            [descriptor
                fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
        descriptor = boldDescriptor ?: descriptor;
    }
    label.font = [UIFont fontWithDescriptor:descriptor size:0];
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

- (void)configureWithColors:(NSDictionary<NSString*, NSString*>*)colors
             darkAppearance:(BOOL)darkAppearance {
    UIColor* accent =
        [Palette colorFromHexString:colors[BHTThemeColorAccentKey]];
    UIColor* background =
        [Palette colorFromHexString:colors[BHTThemeColorBackgroundKey]];
    UIColor* surface =
        [Palette colorFromHexString:colors[BHTThemeColorSurfaceKey]];
    UIColor* elevated =
        [Palette
            colorFromHexString:
                colors[BHTThemeColorElevatedSurfaceKey]];
    UIColor* text =
        [Palette colorFromHexString:colors[BHTThemeColorTextKey]];
    UIColor* secondary =
        [Palette
            colorFromHexString:
                colors[BHTThemeColorSecondaryTextKey]];
    UIColor* separator =
        [Palette colorFromHexString:colors[BHTThemeColorSeparatorKey]];
    if (!accent || !background || !surface || !elevated || !text ||
        !secondary || !separator) {
        return;
    }

    self.backgroundColor = background;
    self.headerView.backgroundColor = surface;
    self.cardView.backgroundColor = surface;
    self.bottomBarView.backgroundColor = surface;
    self.elevatedBadge.backgroundColor = elevated;
    self.accentDot.backgroundColor = accent;
    self.selectedTabLabel.textColor = accent;
    self.unselectedTabLabel.textColor = secondary;
    self.nameLabel.textColor = text;
    self.handleLabel.textColor = secondary;
    self.bodyLabel.textColor = text;
    self.elevatedLabel.textColor = text;
    self.divider.backgroundColor = separator;
    self.layer.borderColor = separator.CGColor;

    NSArray<UIImageView*>* cardIcons = @[];
    for (UIView* subview in self.cardView.subviews) {
        if ([subview isKindOfClass:UIStackView.class]) {
            NSMutableArray* icons = [NSMutableArray array];
            for (UIView* arranged
                 in ((UIStackView*)subview).arrangedSubviews) {
                if ([arranged isKindOfClass:UIImageView.class]) {
                    [icons addObject:arranged];
                }
            }
            cardIcons = [icons copy];
            break;
        }
    }
    [cardIcons enumerateObjectsUsingBlock:^(
                   UIImageView* icon, NSUInteger index,
                   __unused BOOL* stop) {
        icon.tintColor = index == 2 ? accent : secondary;
    }];
    [self.bottomIcons enumerateObjectsUsingBlock:^(
                          UIImageView* icon, NSUInteger index,
                          __unused BOOL* stop) {
        icon.tintColor = index == 0 ? accent : secondary;
    }];

    NSString* modeName =
        darkAppearance
            ? BHTThemeBuilderLocalized(@"THEME_BUILDER_DARK", @"Dark")
            : BHTThemeBuilderLocalized(@"THEME_BUILDER_LIGHT", @"Light");
    self.accessibilityLabel =
        [NSString stringWithFormat:@"Theme preview, %@ appearance",
                                   modeName];
}

@end

@interface BHTThemeBuilderPreviewCell : UITableViewCell
@property(nonatomic, strong) UISegmentedControl* appearanceControl;
@property(nonatomic, strong) BHTThemeBuilderPreviewView* previewView;
- (void)configureWithColors:(NSDictionary<NSString*, NSString*>*)colors
             darkAppearance:(BOOL)darkAppearance
                     target:(id)target
                     action:(SEL)action;
@end

@implementation BHTThemeBuilderPreviewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString*)reuseIdentifier {
    if ((self = [super initWithStyle:style
                      reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        self.appearanceControl = [[UISegmentedControl alloc]
            initWithItems:@[
                BHTThemeBuilderLocalized(
                    @"THEME_BUILDER_LIGHT", @"Light"),
                BHTThemeBuilderLocalized(
                    @"THEME_BUILDER_DARK", @"Dark")
            ]];
        self.appearanceControl.translatesAutoresizingMaskIntoConstraints =
            NO;
        self.appearanceControl.accessibilityIdentifier =
            @"theme-builder-appearance-mode";
        [self.contentView addSubview:self.appearanceControl];

        self.previewView = [BHTThemeBuilderPreviewView new];
        [self.contentView addSubview:self.previewView];

        [NSLayoutConstraint activateConstraints:@[
            [self.appearanceControl.topAnchor
                constraintEqualToAnchor:self.contentView.topAnchor
                               constant:12],
            [self.appearanceControl.centerXAnchor
                constraintEqualToAnchor:self.contentView.centerXAnchor],
            [self.appearanceControl.widthAnchor
                constraintLessThanOrEqualToAnchor:
                    self.contentView.layoutMarginsGuide.widthAnchor],
            [self.appearanceControl.widthAnchor
                constraintGreaterThanOrEqualToConstant:220],

            [self.previewView.topAnchor
                constraintEqualToAnchor:self.appearanceControl.bottomAnchor
                               constant:12],
            [self.previewView.leadingAnchor
                constraintEqualToAnchor:
                    self.contentView.layoutMarginsGuide.leadingAnchor],
            [self.previewView.trailingAnchor
                constraintEqualToAnchor:
                    self.contentView.layoutMarginsGuide.trailingAnchor],
            [self.previewView.bottomAnchor
                constraintEqualToAnchor:self.contentView.bottomAnchor
                               constant:-12]
        ]];
        [self applyCurrentTheme];
    }
    return self;
}

- (void)configureWithColors:(NSDictionary<NSString*, NSString*>*)colors
             darkAppearance:(BOOL)darkAppearance
                     target:(id)target
                     action:(SEL)action {
    [self.appearanceControl removeTarget:nil
                                  action:NULL
                        forControlEvents:UIControlEventAllEvents];
    self.appearanceControl.selectedSegmentIndex =
        darkAppearance ? 1 : 0;
    [self.appearanceControl addTarget:target
                               action:action
                     forControlEvents:UIControlEventValueChanged];
    [self.previewView configureWithColors:colors
                           darkAppearance:darkAppearance];
    [self applyCurrentTheme];
}

- (void)applyCurrentTheme {
    self.backgroundColor = [Palette currentSurfaceColor];
}

- (void)traitCollectionDidChange:
    (UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyCurrentTheme];
}

@end

@interface BHTThemeBuilderViewController ()
    <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property(nonatomic, strong) UITableView* tableView;
@property(nonatomic, strong) NSMutableDictionary* draft;
@property(nonatomic, strong) NSMutableDictionary* lastValidLightColors;
@property(nonatomic, strong) NSMutableDictionary* lastValidDarkColors;
@property(nonatomic, weak) UITextField* nameField;
@property(nonatomic, assign) BOOL editingExistingTheme;
@property(nonatomic, assign) BOOL darkAppearance;
@end

@implementation BHTThemeBuilderViewController

- (instancetype)initWithTheme:(NSDictionary*)theme {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        NSDictionary* source = theme;
        if (![source isKindOfClass:NSDictionary.class]) {
            NSString* activeIdentifier =
                [BHTThemePresets activePresetIdentifier];
            source = [BHTThemePresets
                newUserThemeDraftBasedOnPreset:
                    [BHTThemePresets
                        presetForIdentifier:activeIdentifier]];
        }

        NSString* identifier =
            [source[@"identifier"] isKindOfClass:NSString.class]
                ? source[@"identifier"]
                : nil;
        NSDictionary* stored =
            [BHTThemePresets presetForIdentifier:identifier];
        _editingExistingTheme =
            [BHTThemePresets isUserPresetIdentifier:identifier] &&
            [stored[@"identifier"] isEqualToString:identifier];

        _draft = [source mutableCopy];
        NSMutableDictionary* lightColors =
            [([source[@"lightColors"] isKindOfClass:NSDictionary.class]
                  ? source[@"lightColors"]
                  : @{}) mutableCopy];
        NSMutableDictionary* darkColors =
            [([source[@"darkColors"] isKindOfClass:NSDictionary.class]
                  ? source[@"darkColors"]
                  : @{}) mutableCopy];
        _draft[@"lightColors"] = lightColors;
        _draft[@"darkColors"] = darkColors;
        _lastValidLightColors = [lightColors mutableCopy];
        _lastValidDarkColors = [darkColors mutableCopy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.darkAppearance = [Palette currentPaletteUsesDarkAppearance];
    self.title = BHTThemeBuilderLocalized(
        self.editingExistingTheme ? @"THEME_BUILDER_EDIT_TITLE"
                                  : @"THEME_BUILDER_NEW_TITLE",
        self.editingExistingTheme ? @"Edit Theme" : @"New Theme");
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc]
            initWithTitle:BHTThemeBuilderLocalized(
                              @"THEME_BUILDER_SAVE_APPLY",
                              @"Save & Apply")
                    style:UIBarButtonItemStyleDone
                   target:self
                   action:@selector(saveTapped)];
    self.navigationItem.rightBarButtonItem.accessibilityIdentifier =
        @"theme-builder-save-apply";
    [self setupTableView];
    [self applyCurrentTheme];
    [self updateSaveButton];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyCurrentTheme];
}

- (void)traitCollectionDidChange:
    (UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (previousTraitCollection.userInterfaceStyle !=
            self.traitCollection.userInterfaceStyle ||
        previousTraitCollection.preferredContentSizeCategory !=
            self.traitCollection.preferredContentSizeCategory) {
        [self applyCurrentTheme];
    }
}

- (void)setupTableView {
    self.tableView =
        [[UITableView alloc] initWithFrame:CGRectZero
                                    style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 62;
    self.tableView.keyboardDismissMode =
        UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.cellLayoutMarginsFollowReadableWidth = YES;
    self.tableView.accessibilityIdentifier = @"theme-builder-table";
    [self.tableView registerClass:BHTThemeBuilderPreviewCell.class
           forCellReuseIdentifier:@"ThemeBuilderPreviewCell"];
    [self.tableView registerClass:BHTThemeBuilderNameCell.class
           forCellReuseIdentifier:@"ThemeBuilderNameCell"];
    [self.tableView registerClass:BHTThemeBuilderColorCell.class
           forCellReuseIdentifier:@"ThemeBuilderColorCell"];
    [self.view addSubview:self.tableView];

    UILayoutGuide* safeArea = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint* fillWidth =
        [self.tableView.widthAnchor
            constraintEqualToAnchor:safeArea.widthAnchor];
    fillWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor
            constraintEqualToAnchor:safeArea.topAnchor],
        [self.tableView.bottomAnchor
            constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.centerXAnchor
            constraintEqualToAnchor:safeArea.centerXAnchor],
        [self.tableView.leadingAnchor
            constraintGreaterThanOrEqualToAnchor:safeArea.leadingAnchor],
        [self.tableView.trailingAnchor
            constraintLessThanOrEqualToAnchor:safeArea.trailingAnchor],
        [self.tableView.widthAnchor
            constraintLessThanOrEqualToConstant:
                BHTThemeBuilderMaximumReadableWidth],
        fillWidth
    ]];
}

- (void)applyCurrentTheme {
    UIColor* background = [Palette currentBackgroundColor];
    self.view.backgroundColor = background;
    self.tableView.backgroundColor = background;
    self.tableView.separatorColor = [Palette currentSeparatorColor];
    self.view.tintColor =
        [Palette
            customThemeColorForRole:BHTThemeColorAccentKey] ?:
        [Palette customAccentColor] ?: UIColor.systemBlueColor;

    for (UITableViewCell* cell in self.tableView.visibleCells) {
        if ([cell respondsToSelector:@selector(applyCurrentTheme)]) {
            [(id)cell applyCurrentTheme];
        } else {
            cell.backgroundColor = [Palette currentSurfaceColor];
        }
    }
}

- (NSString*)currentMapKey {
    return self.darkAppearance ? @"darkColors" : @"lightColors";
}

- (NSMutableDictionary*)draftColorsForMapKey:(NSString*)mapKey {
    id colors = self.draft[mapKey];
    if (![colors isKindOfClass:NSMutableDictionary.class]) {
        colors =
            [([colors isKindOfClass:NSDictionary.class] ? colors : @{})
                mutableCopy];
        self.draft[mapKey] = colors;
    }
    return colors;
}

- (NSMutableDictionary*)lastValidColorsForMapKey:(NSString*)mapKey {
    return [mapKey isEqualToString:@"darkColors"]
               ? self.lastValidDarkColors
               : self.lastValidLightColors;
}

- (NSDictionary*)previewColorsForCurrentAppearance {
    return [[self lastValidColorsForMapKey:[self currentMapKey]] copy];
}

- (BHTThemeBuilderColorCell*)colorCellContainingView:(UIView*)view {
    UIView* candidate = view;
    while (candidate &&
           ![candidate isKindOfClass:BHTThemeBuilderColorCell.class]) {
        candidate = candidate.superview;
    }
    return (BHTThemeBuilderColorCell*)candidate;
}

- (void)refreshPreview {
    NSIndexPath* previewPath =
        [NSIndexPath indexPathForRow:0
                           inSection:BHTThemeBuilderSectionPreview];
    BHTThemeBuilderPreviewCell* cell =
        (BHTThemeBuilderPreviewCell*)
            [self.tableView cellForRowAtIndexPath:previewPath];
    [cell configureWithColors:[self previewColorsForCurrentAppearance]
               darkAppearance:self.darkAppearance
                       target:self
                       action:@selector(appearanceControlChanged:)];
}

- (void)updateSaveButton {
    NSString* name =
        [self.draft[@"name"] isKindOfClass:NSString.class]
            ? [self.draft[@"name"]
                  stringByTrimmingCharactersInSet:
                      NSCharacterSet.whitespaceAndNewlineCharacterSet]
            : nil;
    BOOL valid = name.length > 0 &&
                 name.length <= BHTThemeBuilderMaximumNameLength;
    for (NSString* mapKey in @[@"lightColors", @"darkColors"]) {
        NSDictionary* colors = self.draft[mapKey];
        for (NSString* role in BHTThemeBuilderRoles()) {
            if (!BHTThemeBuilderNormalizedOpaqueHex(colors[role])) {
                valid = NO;
                break;
            }
        }
        if (!valid) break;
    }
    self.navigationItem.rightBarButtonItem.enabled = valid;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return BHTThemeBuilderSectionCount;
}

- (NSInteger)tableView:(UITableView*)tableView
 numberOfRowsInSection:(NSInteger)section {
    switch ((BHTThemeBuilderSection)section) {
        case BHTThemeBuilderSectionPreview:
        case BHTThemeBuilderSectionName:
            return 1;
        case BHTThemeBuilderSectionColors:
            return BHTThemeBuilderRoles().count;
        case BHTThemeBuilderSectionActions:
            return 2;
        case BHTThemeBuilderSectionCount:
            return 0;
    }
    return 0;
}

- (NSString*)tableView:(UITableView*)tableView
    titleForHeaderInSection:(NSInteger)section {
    switch ((BHTThemeBuilderSection)section) {
        case BHTThemeBuilderSectionPreview:
            return BHTThemeBuilderLocalized(
                @"THEME_BUILDER_PREVIEW", @"Preview");
        case BHTThemeBuilderSectionName:
            return BHTThemeBuilderLocalized(
                @"THEME_BUILDER_NAME", @"Theme name");
        case BHTThemeBuilderSectionColors:
            return BHTThemeBuilderLocalized(
                @"THEME_BUILDER_COLORS", @"Colors");
        case BHTThemeBuilderSectionActions:
            return BHTThemeBuilderLocalized(
                @"THEME_BUILDER_ACTIONS_SECTION_TITLE",
                @"Copy colors");
        case BHTThemeBuilderSectionCount:
            return nil;
    }
    return nil;
}

- (NSString*)tableView:(UITableView*)tableView
    titleForFooterInSection:(NSInteger)section {
    if (section != BHTThemeBuilderSectionColors) return nil;
    return self.darkAppearance
               ? BHTThemeBuilderLocalized(
                     @"THEME_BUILDER_DARK_COLORS_FOOTER",
                     @"Editing the colors used in Dark appearance.")
               : BHTThemeBuilderLocalized(
                     @"THEME_BUILDER_LIGHT_COLORS_FOOTER",
                     @"Editing the colors used in Light appearance.");
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    if (indexPath.section == BHTThemeBuilderSectionPreview) {
        BHTThemeBuilderPreviewCell* cell =
            [tableView
                dequeueReusableCellWithIdentifier:
                    @"ThemeBuilderPreviewCell"
                                      forIndexPath:indexPath];
        [cell configureWithColors:[self previewColorsForCurrentAppearance]
                   darkAppearance:self.darkAppearance
                           target:self
                           action:@selector(appearanceControlChanged:)];
        return cell;
    }

    if (indexPath.section == BHTThemeBuilderSectionName) {
        BHTThemeBuilderNameCell* cell =
            [tableView
                dequeueReusableCellWithIdentifier:@"ThemeBuilderNameCell"
                                      forIndexPath:indexPath];
        [cell.nameField removeTarget:nil
                              action:NULL
                    forControlEvents:UIControlEventAllEvents];
        cell.nameField.delegate = self;
        cell.nameField.placeholder = BHTThemeBuilderLocalized(
            @"THEME_BUILDER_DEFAULT_NAME", @"My Theme");
        cell.nameField.text =
            [self.draft[@"name"] isKindOfClass:NSString.class]
                ? self.draft[@"name"]
                : @"";
        cell.nameField.accessibilityLabel =
            BHTThemeBuilderLocalized(
                @"THEME_BUILDER_NAME", @"Theme name");
        cell.nameField.accessibilityIdentifier =
            @"theme-builder-name";
        [cell.nameField addTarget:self
                           action:@selector(nameFieldChanged:)
                 forControlEvents:UIControlEventEditingChanged];
        self.nameField = cell.nameField;
        return cell;
    }

    if (indexPath.section == BHTThemeBuilderSectionColors) {
        BHTThemeBuilderColorCell* cell =
            [tableView
                dequeueReusableCellWithIdentifier:@"ThemeBuilderColorCell"
                                      forIndexPath:indexPath];
        NSString* role = BHTThemeBuilderRoles()[indexPath.row];
        NSString* mapKey = [self currentMapKey];
        NSString* rawHex =
            [[self draftColorsForMapKey:mapKey][role]
                    isKindOfClass:NSString.class]
                ? [self draftColorsForMapKey:mapKey][role]
                : @"";
        NSString* previewHex =
            [self lastValidColorsForMapKey:mapKey][role];
        [cell configureWithRole:role
                        mapKey:mapKey
                        rawHex:rawHex
                    previewHex:previewHex
                      delegate:self
                        target:self
            fieldChangedAction:@selector(hexFieldChanged:)
             fieldDidEndAction:@selector(hexFieldDidEndEditing:)
            colorChangedAction:@selector(colorWellChanged:)];
        return cell;
    }

    static NSString* const actionCellIdentifier =
        @"ThemeBuilderActionCell";
    UITableViewCell* cell =
        [tableView
            dequeueReusableCellWithIdentifier:actionCellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc]
              initWithStyle:UITableViewCellStyleDefault
            reuseIdentifier:actionCellIdentifier];
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
    }
    BOOL lightToDark = indexPath.row == 0;
    cell.textLabel.text =
        lightToDark
            ? BHTThemeBuilderLocalized(
                  @"THEME_BUILDER_COPY_LIGHT_TO_DARK",
                  @"Copy Light to Dark")
            : BHTThemeBuilderLocalized(
                  @"THEME_BUILDER_COPY_DARK_TO_LIGHT",
                  @"Copy Dark to Light");
    cell.textLabel.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.textColor = self.view.tintColor;
    cell.imageView.image =
        [UIImage systemImageNamed:
                     lightToDark ? @"arrow.down.square"
                                 : @"arrow.up.square"];
    cell.imageView.tintColor = self.view.tintColor;
    cell.backgroundColor = [Palette currentSurfaceColor];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessibilityTraits = UIAccessibilityTraitButton;
    cell.accessibilityIdentifier =
        lightToDark ? @"theme-builder-copy-light-to-dark"
                    : @"theme-builder-copy-dark-to-light";
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView
    didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != BHTThemeBuilderSectionActions) return;
    [self.view endEditing:YES];
    if (indexPath.row == 0) {
        [self copyColorsFromMapKey:@"lightColors"
                         toMapKey:@"darkColors"
                showDarkAppearance:YES];
    } else {
        [self copyColorsFromMapKey:@"darkColors"
                         toMapKey:@"lightColors"
                showDarkAppearance:NO];
    }
}

#pragma mark - Editing

- (void)appearanceControlChanged:(UISegmentedControl*)sender {
    [self.view endEditing:YES];
    self.darkAppearance = sender.selectedSegmentIndex == 1;
    NSIndexSet* sections =
        [NSIndexSet indexSetWithIndexesInRange:
                        NSMakeRange(BHTThemeBuilderSectionColors, 2)];
    [self.tableView reloadSections:sections
                  withRowAnimation:UITableViewRowAnimationFade];
    [self refreshPreview];
}

- (void)nameFieldChanged:(UITextField*)sender {
    self.draft[@"name"] = sender.text ?: @"";
    [self updateSaveButton];
}

- (void)hexFieldChanged:(BHTThemeBuilderHexField*)sender {
    NSString* mapKey = sender.themeMapKey ?: [self currentMapKey];
    NSString* role = sender.themeRole;
    if (!role) return;
    NSMutableDictionary* colors =
        [self draftColorsForMapKey:mapKey];
    colors[role] = sender.text ?: @"";
    NSString* normalized =
        BHTThemeBuilderNormalizedOpaqueHex(sender.text);
    sender.textColor =
        normalized ? [Palette currentTextColor]
                   : UIColor.systemRedColor;
    if (normalized) {
        [self lastValidColorsForMapKey:mapKey][role] = normalized;
        UIColor* selectedColor =
            [Palette colorFromHexString:normalized];
        BHTThemeBuilderColorCell* cell =
            [self colorCellContainingView:sender];
        if (selectedColor) {
            cell.colorWell.selectedColor = selectedColor;
        }
        if ([mapKey isEqualToString:[self currentMapKey]]) {
            [self refreshPreview];
        }
    }
    [self updateSaveButton];
}

- (void)hexFieldDidEndEditing:(BHTThemeBuilderHexField*)sender {
    NSString* normalized =
        BHTThemeBuilderNormalizedOpaqueHex(sender.text);
    if (!normalized) return;
    sender.text = normalized;
    NSString* mapKey = sender.themeMapKey ?: [self currentMapKey];
    NSString* role = sender.themeRole;
    if (!role) return;
    [self draftColorsForMapKey:mapKey][role] = normalized;
    [self lastValidColorsForMapKey:mapKey][role] = normalized;
    sender.textColor = [Palette currentTextColor];
    UIColor* selectedColor =
        [Palette colorFromHexString:normalized];
    BHTThemeBuilderColorCell* cell =
        [self colorCellContainingView:sender];
    if (selectedColor) {
        cell.colorWell.selectedColor = selectedColor;
    }
    [self updateSaveButton];
}

- (void)colorWellChanged:(BHTThemeBuilderColorWell*)sender {
    NSString* role = sender.themeRole;
    NSString* mapKey = sender.themeMapKey ?: [self currentMapKey];
    NSString* hex =
        BHTThemeBuilderHexFromColor(sender.selectedColor,
                                    self.traitCollection);
    if (!role || !hex) return;

    [self draftColorsForMapKey:mapKey][role] = hex;
    [self lastValidColorsForMapKey:mapKey][role] = hex;

    if ([mapKey isEqualToString:[self currentMapKey]]) {
        NSUInteger row = [BHTThemeBuilderRoles() indexOfObject:role];
        if (row != NSNotFound) {
            NSIndexPath* path =
                [NSIndexPath
                    indexPathForRow:(NSInteger)row
                         inSection:BHTThemeBuilderSectionColors];
            BHTThemeBuilderColorCell* cell =
                (BHTThemeBuilderColorCell*)
                    [self.tableView cellForRowAtIndexPath:path];
            cell.hexField.text = hex;
            cell.hexField.textColor = [Palette currentTextColor];
        }
        [self refreshPreview];
    }
    [self updateSaveButton];
}

- (void)copyColorsFromMapKey:(NSString*)sourceMapKey
                    toMapKey:(NSString*)destinationMapKey
           showDarkAppearance:(BOOL)showDarkAppearance {
    NSDictionary* source =
        [[self draftColorsForMapKey:sourceMapKey] copy];
    NSDictionary* validSource =
        [[self lastValidColorsForMapKey:sourceMapKey] copy];
    self.draft[destinationMapKey] = [source mutableCopy];
    if ([destinationMapKey isEqualToString:@"darkColors"]) {
        self.lastValidDarkColors = [validSource mutableCopy];
    } else {
        self.lastValidLightColors = [validSource mutableCopy];
    }
    self.darkAppearance = showDarkAppearance;
    NSIndexSet* sections =
        [NSIndexSet indexSetWithIndexesInRange:
                        NSMakeRange(BHTThemeBuilderSectionPreview, 4)];
    [self.tableView reloadSections:sections
                  withRowAnimation:UITableViewRowAnimationFade];
    [self updateSaveButton];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField*)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString*)string {
    NSString* current = textField.text ?: @"";
    NSString* candidate =
        [current stringByReplacingCharactersInRange:range
                                         withString:string ?: @""];
    if (textField == self.nameField) {
        return candidate.length <= BHTThemeBuilderMaximumNameLength &&
               [candidate
                   rangeOfCharacterFromSet:
                       NSCharacterSet.newlineCharacterSet].location ==
                   NSNotFound;
    }

    if (![textField isKindOfClass:BHTThemeBuilderHexField.class]) {
        return YES;
    }
    if (candidate.length > 7) return NO;
    NSCharacterSet* allowed =
        [NSCharacterSet
            characterSetWithCharactersInString:@"#0123456789ABCDEFabcdef"];
    if ([candidate
            rangeOfCharacterFromSet:allowed.invertedSet].location !=
        NSNotFound) {
        return NO;
    }
    NSRange firstHash = [candidate rangeOfString:@"#"];
    if (firstHash.location != NSNotFound && firstHash.location != 0) {
        return NO;
    }
    if (firstHash.location != NSNotFound &&
        [[candidate substringFromIndex:1] containsString:@"#"]) {
        return NO;
    }
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Save and validation

- (NSArray<NSString*>*)appearancesWithLowContrast {
    NSMutableArray<NSString*>* modes = [NSMutableArray array];
    for (NSString* mapKey in @[@"lightColors", @"darkColors"]) {
        NSDictionary* raw = self.draft[mapKey];
        NSMutableDictionary<NSString*, UIColor*>* colors =
            [NSMutableDictionary dictionary];
        BOOL complete = YES;
        for (NSString* role in BHTThemeBuilderRoles()) {
            UIColor* color =
                [Palette colorFromHexString:
                             BHTThemeBuilderNormalizedOpaqueHex(
                                 raw[role])];
            if (!color) {
                complete = NO;
                break;
            }
            colors[role] = color;
        }
        if (!complete) continue;

        UIColor* primary = colors[BHTThemeColorTextKey];
        UIColor* secondary =
            colors[BHTThemeColorSecondaryTextKey];
        UIColor* accent = colors[BHTThemeColorAccentKey];
        NSArray<UIColor*>* surfaces = @[
            colors[BHTThemeColorBackgroundKey],
            colors[BHTThemeColorSurfaceKey],
            colors[BHTThemeColorElevatedSurfaceKey]
        ];
        BOOL lowContrast = NO;
        for (UIColor* surface in surfaces) {
            if (BHTThemeBuilderContrastRatio(primary, surface) < 4.5 ||
                BHTThemeBuilderContrastRatio(secondary, surface) < 3.0 ||
                BHTThemeBuilderContrastRatio(accent, surface) < 3.0) {
                lowContrast = YES;
                break;
            }
        }
        if (lowContrast) {
            [modes addObject:
                [mapKey isEqualToString:@"darkColors"]
                    ? BHTThemeBuilderLocalized(
                          @"THEME_BUILDER_DARK", @"Dark")
                    : BHTThemeBuilderLocalized(
                          @"THEME_BUILDER_LIGHT", @"Light")];
        }
    }
    return [modes copy];
}

- (void)saveTapped {
    [self.view endEditing:YES];
    NSArray<NSString*>* lowContrastModes =
        [self appearancesWithLowContrast];
    if (lowContrastModes.count == 0) {
        [self saveAndApplyDraft];
        return;
    }

    NSString* detailFormat = BHTThemeBuilderLocalized(
        @"THEME_BUILDER_LOW_CONTRAST_WARNING",
        @"Some text or accent colors may be hard to read in %@ mode. "
         "You can save anyway or return to adjust the colors.");
    NSString* modes =
        [lowContrastModes componentsJoinedByString:@" / "];
    NSString* detail =
        [detailFormat containsString:@"%@"] ||
                [detailFormat containsString:@"%1$@"]
            ? [NSString stringWithFormat:detailFormat, modes]
            : detailFormat;
    UIAlertController* alert =
        [UIAlertController
            alertControllerWithTitle:BHTThemeBuilderLocalized(
                                         @"THEME_BUILDER_LOW_CONTRAST_TITLE",
                                         @"Low contrast")
                             message:detail
                      preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:BHTThemeBuilderLocalized(
                                       @"THEME_BUILDER_CANCEL",
                                       @"Keep Editing")
                             style:UIAlertActionStyleCancel
                           handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:BHTThemeBuilderLocalized(
                                       @"THEME_BUILDER_SAVE_ANYWAY",
                                       @"Save Anyway")
                             style:UIAlertActionStyleDefault
                           handler:^(__unused UIAlertAction* action) {
        [weakSelf saveAndApplyDraft];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveAndApplyDraft {
    NSError* error = nil;
    NSDictionary* saved =
        [BHTThemePresets saveUserTheme:self.draft error:&error];
    if (!saved) {
        [self showSaveError:error];
        return;
    }
    NSString* identifier =
        [saved[@"identifier"] isKindOfClass:NSString.class]
            ? saved[@"identifier"]
            : nil;
    if (![BHTThemePresets applyPresetIdentifier:identifier]) {
        NSError* applyError =
            [NSError
                errorWithDomain:@"com.neofreebird.theme-builder"
                           code:1
                       userInfo:@{
                           NSLocalizedDescriptionKey:
                               @"The theme was saved, but it could not be "
                                "applied."
                       }];
        [self showSaveError:applyError];
        return;
    }

    if (self.navigationController.topViewController == self &&
        self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)showSaveError:(NSError*)error {
    UIAlertController* alert =
        [UIAlertController
            alertControllerWithTitle:BHTThemeBuilderLocalized(
                                         @"THEME_BUILDER_ERROR_TITLE",
                                         @"Couldn’t Save Theme")
                             message:error.localizedDescription ?:
                                 @"Check the theme name and colors, then try "
                                  "again."
                      preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:BHTThemeBuilderLocalized(
                                       @"PREFERENCE_PROFILE_OK", @"OK")
                             style:UIAlertActionStyleDefault
                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
