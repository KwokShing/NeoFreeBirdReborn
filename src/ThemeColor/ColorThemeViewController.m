//
//  ColorThemeViewController.m
//  NeoFreeBird
//
//  The lightweight "Accent only" picker. Coordinated full-app themes live in
//  PresetSettingsViewController so there is one canonical theme library.
//

#import "ThemeColor/ColorThemeViewController.h"

#import "Core/BHTBundle.h"
#import "Core/TwitterChirpFont.h"
#import "Headers/TWHeaders.h"
#import "ThemeColor/BHTThemePresets.h"
#import "ThemeColor/ColorSwatchControl.h"
#import "ThemeColor/Palette.h"

static NSInteger BHTCurrentAccentOnlyOption(void) {
    if ([BHTThemePresets activePresetIdentifier]) return NSNotFound;
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:@"bh_color_theme_selectedColor"]) {
        return [defaults integerForKey:@"bh_color_theme_selectedColor"];
    }
    NSInteger option =
        [defaults integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
    return option >= 1 ? option : 1;
}

enum { kBHTAccentOptionCount = 6 };
static NSString* const kBHTAccentColorNames[kBHTAccentOptionCount] = {
    @"BLUE", @"YELLOW", @"RED", @"PURPLE", @"ORANGE", @"GREEN"
};

static UIColor* BHTNativeAccentColor(NSUInteger option) {
    Class settingsClass = objc_getClass("TAEColorSettings");
    if (![settingsClass respondsToSelector:@selector(sharedSettings)]) {
        return UIColor.systemBlueColor;
    }
    id settings = [settingsClass sharedSettings];
    if (![settings respondsToSelector:@selector(currentColorPalette)]) {
        return UIColor.systemBlueColor;
    }
    id current = [settings currentColorPalette];
    if (![current respondsToSelector:@selector(colorPalette)]) {
        return UIColor.systemBlueColor;
    }
    id palette = [current colorPalette];
    if (![palette respondsToSelector:@selector(primaryColorForOption:)]) {
        return UIColor.systemBlueColor;
    }
    UIColor* color = [palette primaryColorForOption:option];
    return [color isKindOfClass:UIColor.class] ? color
                                               : UIColor.systemBlueColor;
}

@interface ColorThemeViewController ()
@property (nonatomic, copy) NSArray<ColorSwatchControl*>* swatches;
@property (nonatomic, strong) UILabel* detailLabel;
@end

@implementation ColorThemeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.title = [[BHTBundle sharedBundle]
        localizedStringForKey:@"THEME_SETTINGS_NAVIGATION_TITLE"];
    self.view.backgroundColor = [Palette currentBackgroundColor];

    UIScrollView* scrollView = [UIScrollView new];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:scrollView];

    UIView* contentView = [UIView new];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:contentView];

    UILabel* detail = [UILabel new];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.text = [[BHTBundle sharedBundle]
        localizedStringForKey:@"THEME_SETTINGS_NAVIGATION_DETAIL"];
    detail.font =
        [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15];
    detail.textColor = [Palette currentSecondaryTextColor];
    detail.numberOfLines = 0;
    [contentView addSubview:detail];
    self.detailLabel = detail;

    UIStackView* row = [UIStackView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.alignment = UIStackViewAlignmentFill;
    row.accessibilityIdentifier = @"theme-accent-only-swatches";
    [contentView addSubview:row];

    NSMutableArray<ColorSwatchControl*>* swatches =
        [NSMutableArray arrayWithCapacity:kBHTAccentOptionCount];
    for (NSUInteger option = 1; option <= kBHTAccentOptionCount;
         option++) {
        ColorSwatchControl* swatch = [ColorSwatchControl new];
        swatch.translatesAutoresizingMaskIntoConstraints = NO;
        swatch.colorID = option;
        swatch.isAccessibilityElement = YES;
        swatch.accessibilityIdentifier =
            [NSString stringWithFormat:@"theme-accent-only-%lu",
                                       (unsigned long)option];
        swatch.accessibilityLabel = [[BHTBundle sharedBundle]
            localizedTwitterStringForKey:
                [NSString
                    stringWithFormat:
                        @"FLEETS_COLOR_%@_ACCESSIBILITY_LABEL",
                        kBHTAccentColorNames[option - 1]]];
        [swatch setSwatchColor:BHTNativeAccentColor(option)];
        [swatch addTarget:self
                   action:@selector(swatchTapped:)
         forControlEvents:UIControlEventTouchUpInside];
        [row addArrangedSubview:swatch];
        [swatches addObject:swatch];
    }
    self.swatches = [swatches copy];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide
                                        .topAnchor],
        [scrollView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor
            constraintEqualToAnchor:self.view.bottomAnchor],
        [contentView.topAnchor
            constraintEqualToAnchor:scrollView.contentLayoutGuide
                                        .topAnchor],
        [contentView.leadingAnchor
            constraintEqualToAnchor:scrollView.contentLayoutGuide
                                        .leadingAnchor],
        [contentView.trailingAnchor
            constraintEqualToAnchor:scrollView.contentLayoutGuide
                                        .trailingAnchor],
        [contentView.bottomAnchor
            constraintEqualToAnchor:scrollView.contentLayoutGuide
                                        .bottomAnchor],
        [contentView.widthAnchor
            constraintEqualToAnchor:scrollView.frameLayoutGuide
                                        .widthAnchor],
        [detail.topAnchor
            constraintEqualToAnchor:contentView.topAnchor
                           constant:24],
        [detail.leadingAnchor
            constraintEqualToAnchor:contentView.leadingAnchor
                           constant:20],
        [detail.trailingAnchor
            constraintEqualToAnchor:contentView.trailingAnchor
                           constant:-20],
        [row.topAnchor constraintEqualToAnchor:detail.bottomAnchor
                                      constant:24],
        [row.leadingAnchor
            constraintEqualToAnchor:contentView.leadingAnchor
                           constant:16],
        [row.trailingAnchor
            constraintEqualToAnchor:contentView.trailingAnchor
                           constant:-16],
        [row.heightAnchor constraintEqualToConstant:56],
        [row.bottomAnchor
            constraintLessThanOrEqualToAnchor:contentView.bottomAnchor
                                    constant:-24]
    ]];
    [self applyCurrentAppearance];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyCurrentAppearance];
}

- (void)traitCollectionDidChange:
    (UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (previousTraitCollection.userInterfaceStyle !=
        self.traitCollection.userInterfaceStyle) {
        [self applyCurrentAppearance];
    }
}

- (void)applyCurrentAppearance {
    self.view.backgroundColor = [Palette currentBackgroundColor];
    self.detailLabel.textColor = [Palette currentSecondaryTextColor];
    self.view.tintColor =
        [Palette customAccentColor] ?: BHTNativeAccentColor(1);
    NSInteger selected = BHTCurrentAccentOnlyOption();
    for (ColorSwatchControl* swatch in self.swatches) {
        [swatch setSwatchColor:
                    BHTNativeAccentColor(swatch.colorID)];
        [swatch setSwatchSelected:swatch.colorID == selected];
    }
}

- (void)swatchTapped:(ColorSwatchControl*)swatch {
    // Write the final native accent before clearing the coordinated theme so
    // every observer sees one complete, stable Accent Only state.
    [NSUserDefaults.standardUserDefaults
        setInteger:swatch.colorID
            forKey:@"bh_color_theme_selectedColor"];
    [BHTThemePresets clearPresetSelection];
    [BHTThemePresets reapplyCurrentAccent];
    [self applyCurrentAppearance];
    [self reapplyTabBarAccent];
}

- (void)reapplyTabBarAccent {
    Class tabBarClass = NSClassFromString(@"T1TabBarViewController");
    if (!tabBarClass) return;

    for (UIWindowScene* scene
         in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState !=
                UISceneActivationStateForegroundActive) {
            continue;
        }
        for (UIWindow* window in scene.windows) {
            if (!window.rootViewController) continue;
            NSMutableArray<UIViewController*>* queue =
                [NSMutableArray arrayWithObject:
                                    window.rootViewController];
            while (queue.count > 0) {
                UIViewController* controller = queue.firstObject;
                [queue removeObjectAtIndex:0];
                if ([controller isKindOfClass:tabBarClass] &&
                    [controller respondsToSelector:
                                    @selector(tabViews)]) {
                    for (id tab in
                         [controller valueForKey:@"tabViews"]) {
                        if ([tab respondsToSelector:
                                     @selector(
                                         applyCurrentThemeToIcon)]) {
                            [tab performSelector:
                                     @selector(
                                         applyCurrentThemeToIcon)];
                        }
                    }
                }
                if (controller.presentedViewController) {
                    [queue addObject:
                               controller.presentedViewController];
                }
                [queue addObjectsFromArray:
                           controller.childViewControllers];
            }
        }
    }
}

@end
