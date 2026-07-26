//
//  ColorThemeViewController.m
//  BHTwitter
//
//  Created by Bandar Alruwaili on 10/12/2023.
//  Modified by actuallyaridan on 25/05/2025.
//
//  Clones the native accent picker (ColorThemePickerItem).
//

#import "ColorThemeViewController.h"
#import <UIKit/UIKit.h>
#import "ColorSwatchControl.h"
#import "Core/BHTBundle.h"
#import "Core/TwitterChirpFont.h"
#import "Headers/TWHeaders.h"
#import "ThemeColor/BHTThemePresets.h"
#import "ThemeColor/Palette.h"

// Mirrors CurrentAccentColor's precedence (our override, then Twitter's own
// option) so the default swatch shows selected before any change.
static NSInteger CurrentSelectedColorOption(void) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([Palette customAccentColor] ||
        [BHTThemePresets activePresetIdentifier]) {
        return NSNotFound;
    }
    if ([defaults objectForKey:@"bh_color_theme_selectedColor"]) {
        return [defaults integerForKey:@"bh_color_theme_selectedColor"];
    }
    // Twitter stores its default accent (blue) as option 0, and resets to 0 on
    // launch; our swatches are options 1-6, so map 0 (or unset) to blue.
    NSInteger option = [defaults integerForKey:@"T1ColorSettingsPrimaryColorOptionKey"];
    return option >= 1 ? option : 1;
}

// The accent picker ships no localized colour names, so the swatches borrow the
// Fleets accessibility labels for the same six colours.
static const NSUInteger kAccentOptionCount = 6;
static NSString* const kAccentColorNames[kAccentOptionCount] = {@"BLUE", @"YELLOW", @"RED",
                                                                @"PURPLE", @"ORANGE", @"GREEN"};

static UIColor* NativeAccentColor(NSUInteger option) {
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
    return [color isKindOfClass:[UIColor class]]
               ? color
               : UIColor.systemBlueColor;
}

@interface ColorThemeViewController ()
@property (nonatomic, strong) NSMutableArray<ColorSwatchControl*>* swatches;
@property (nonatomic, strong)
    NSMutableDictionary<NSString*, UIButton*>* presetButtons;
@end

@implementation ColorThemeViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.view.backgroundColor = [Palette currentBackgroundColor];

    UIScrollView* scrollView = [UIScrollView new];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    scrollView.keyboardDismissMode =
        UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scrollView];

    UIView* contentView = [UIView new];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:contentView];

    UILabel* detail = [UILabel new];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.text =
        [[BHTBundle sharedBundle] localizedStringForKey:@"THEME_SETTINGS_NAVIGATION_DETAIL"];
    detail.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
    detail.textColor = [UIColor secondaryLabelColor];
    detail.numberOfLines = 0;
    [contentView addSubview:detail];

    // Evenly-spread row of swatches, matching the native picker's flex layout.
    UIStackView* row = [[UIStackView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    // Fill so each swatch spans the row height as a real tap target.
    row.alignment = UIStackViewAlignmentFill;
    [contentView addSubview:row];

    self.swatches = [NSMutableArray new];
    for (NSUInteger option = 1; option <= kAccentOptionCount; option++) {
        ColorSwatchControl* swatch = [[ColorSwatchControl alloc] init];
        swatch.translatesAutoresizingMaskIntoConstraints = NO;
        swatch.colorID = option;
        swatch.isAccessibilityElement = YES;
        swatch.accessibilityLabel = [[BHTBundle sharedBundle]
            localizedTwitterStringForKey:[NSString
                                             stringWithFormat:@"FLEETS_COLOR_%@_ACCESSIBILITY_LABEL",
                                                              kAccentColorNames[option - 1]]];
        [swatch setSwatchColor:NativeAccentColor(option)];
        [swatch addTarget:self
                      action:@selector(swatchTapped:)
            forControlEvents:UIControlEventTouchUpInside];
        [row addArrangedSubview:swatch];
        [self.swatches addObject:swatch];
    }

    UILabel* presetTitle = [UILabel new];
    presetTitle.translatesAutoresizingMaskIntoConstraints = NO;
    presetTitle.text = [[BHTBundle sharedBundle]
        localizedStringForKey:@"THEME_PRESETS_SECTION_TITLE"];
    presetTitle.font =
        [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:17];
    presetTitle.textColor = UIColor.labelColor;
    [contentView addSubview:presetTitle];

    UIStackView* presetStack = [UIStackView new];
    presetStack.translatesAutoresizingMaskIntoConstraints = NO;
    presetStack.axis = UILayoutConstraintAxisVertical;
    presetStack.spacing = 10;
    [contentView addSubview:presetStack];

    self.presetButtons = [NSMutableDictionary dictionary];
    for (NSDictionary* preset in [BHTThemePresets availablePresets]) {
        UIButton* button = [self buttonForPreset:preset];
        [presetStack addArrangedSubview:button];
        self.presetButtons[preset[@"identifier"]] = button;
    }

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [contentView.topAnchor
            constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [contentView.leadingAnchor
            constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [contentView.trailingAnchor
            constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [contentView.bottomAnchor
            constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [contentView.widthAnchor
            constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor],

        [detail.topAnchor constraintEqualToAnchor:contentView.topAnchor
                                         constant:16],
        [detail.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                             constant:16],
        [detail.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                              constant:-16],

        [row.topAnchor constraintEqualToAnchor:detail.bottomAnchor
                                      constant:16],
        [row.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor
                                          constant:16],
        [row.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor
                                           constant:-16],
        [row.heightAnchor constraintEqualToConstant:52],

        [presetTitle.topAnchor constraintEqualToAnchor:row.bottomAnchor
                                              constant:24],
        [presetTitle.leadingAnchor
            constraintEqualToAnchor:contentView.leadingAnchor
                           constant:16],
        [presetTitle.trailingAnchor
            constraintEqualToAnchor:contentView.trailingAnchor
                           constant:-16],

        [presetStack.topAnchor constraintEqualToAnchor:presetTitle.bottomAnchor
                                              constant:12],
        [presetStack.leadingAnchor
            constraintEqualToAnchor:contentView.leadingAnchor
                           constant:16],
        [presetStack.trailingAnchor
            constraintEqualToAnchor:contentView.trailingAnchor
                           constant:-16],
        [presetStack.bottomAnchor
            constraintEqualToAnchor:contentView.bottomAnchor
                           constant:-24]
    ]];

    [self refreshSelection];
}

#pragma mark - Preset Buttons

- (UIButton*)buttonForPreset:(NSDictionary*)preset {
    UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.contentHorizontalAlignment =
        UIControlContentHorizontalAlignmentLeading;
    button.titleLabel.numberOfLines = 0;
    button.layer.cornerRadius = 14;
    button.layer.borderWidth = 1;
    button.layer.borderColor = UIColor.separatorColor.CGColor;
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 14, 12, 14);
    button.accessibilityIdentifier =
        [@"theme-preset-" stringByAppendingString:preset[@"identifier"]];
    objc_setAssociatedObject(button, @selector(presetTapped:),
                             preset[@"identifier"],
                             OBJC_ASSOCIATION_COPY_NONATOMIC);

    NSString* title = [[BHTBundle sharedBundle]
        localizedStringForKey:preset[@"titleKey"]];
    NSString* detail = [[BHTBundle sharedBundle]
        localizedStringForKey:preset[@"detailKey"]];
    NSMutableAttributedString* label =
        [[NSMutableAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"%@\n%@", title, detail]];
    [label addAttributes:@{
        NSFontAttributeName:
            [TwitterChirpFont(TwitterFontStyleBold) fontWithSize:16],
        NSForegroundColorAttributeName: UIColor.labelColor
    }
                   range:NSMakeRange(0, title.length)];
    [label addAttributes:@{
        NSFontAttributeName:
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13],
        NSForegroundColorAttributeName: UIColor.secondaryLabelColor
    }
                   range:NSMakeRange(title.length + 1, detail.length)];
    [button setAttributedTitle:label forState:UIControlStateNormal];

    id hex = preset[@"accentHex"];
    UIColor* color =
        hex == NSNull.null ? NativeAccentColor(1)
                           : [Palette colorFromHexString:hex];
    UIImageSymbolConfiguration* configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:14
                                                        weight:
                                                            UIImageSymbolWeightBold];
    [button setImage:[[UIImage systemImageNamed:@"circle.fill"
                               withConfiguration:configuration]
                         imageWithRenderingMode:
                             UIImageRenderingModeAlwaysTemplate]
            forState:UIControlStateNormal];
    button.tintColor = color ?: UIColor.systemBlueColor;
    button.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 12);
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:64].active =
        YES;
    [button addTarget:self
                   action:@selector(presetTapped:)
         forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)presetTapped:(UIButton*)button {
    NSString* identifier =
        objc_getAssociatedObject(button, @selector(presetTapped:));
    if (![BHTThemePresets applyPresetIdentifier:identifier]) return;
    [self refreshSelection];
    [self reapplyTabBarAccent];
}

#pragma mark - Selection

- (void)refreshSelection {
    NSInteger selected = CurrentSelectedColorOption();
    for (ColorSwatchControl* swatch in self.swatches) {
        [swatch setSwatchSelected:(swatch.colorID == selected)];
    }
    NSString* activePreset = [BHTThemePresets activePresetIdentifier];
    [self.presetButtons enumerateKeysAndObjectsUsingBlock:^(
                            NSString* identifier, UIButton* button,
                            BOOL* stop) {
        BOOL selectedPreset = [identifier isEqualToString:activePreset];
        button.layer.borderWidth = selectedPreset ? 2 : 1;
        button.layer.borderColor =
            (selectedPreset ? button.tintColor : UIColor.separatorColor).CGColor;
        button.accessibilityTraits =
            selectedPreset ? UIAccessibilityTraitButton |
                                 UIAccessibilityTraitSelected
                           : UIAccessibilityTraitButton;
    }];
}

- (void)swatchTapped:(ColorSwatchControl*)swatch {
    [BHTThemePresets clearPresetSelection];
    [[NSUserDefaults standardUserDefaults] setInteger:swatch.colorID
                                               forKey:@"bh_color_theme_selectedColor"];
    [BHTThemePresets reapplyCurrentAccent];

    [self refreshSelection];
    [self reapplyTabBarAccent];
}

- (void)traitCollectionDidChange:
    (UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (previousTraitCollection.userInterfaceStyle !=
        self.traitCollection.userInterfaceStyle) {
        [self refreshSelection];
    }
}

// Re-tint the live tab bar icons to the new accent.
- (void)reapplyTabBarAccent {
    Class t1TabBarVCClass = NSClassFromString(@"T1TabBarViewController");
    if (!t1TabBarVCClass) return;

    UIWindow* window = nil;
    for (UIWindowScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:[UIWindowScene class]]) {
            if ([scene.delegate respondsToSelector:@selector(window)]) {
                window = [(id)scene.delegate window];
            } else {
                for (UIWindow* w in [(id)scene windows]) {
                    if (w.isKeyWindow) {
                        window = w;
                        break;
                    }
                }
            }
            if (window) break;
        }
    }
    if (!window) return;

    NSMutableArray* stack = [NSMutableArray arrayWithObject:window.rootViewController];
    while (stack.count) {
        UIViewController* vc = stack.firstObject;
        [stack removeObjectAtIndex:0];
        if ([vc isKindOfClass:t1TabBarVCClass] && [vc respondsToSelector:@selector(tabViews)]) {
            for (id tab in [vc valueForKey:@"tabViews"]) {
                if ([tab respondsToSelector:@selector(applyCurrentThemeToIcon)]) {
                    [tab performSelector:@selector(applyCurrentThemeToIcon)];
                }
            }
        }
        if (vc.presentedViewController) [stack addObject:vc.presentedViewController];
        if ([vc isKindOfClass:[UINavigationController class]])
            [stack addObjectsFromArray:((UINavigationController*)vc).viewControllers];
        if ([vc isKindOfClass:[UITabBarController class]])
            [stack addObjectsFromArray:((UITabBarController*)vc).viewControllers];
        [stack addObjectsFromArray:vc.childViewControllers];
    }
}

@end
