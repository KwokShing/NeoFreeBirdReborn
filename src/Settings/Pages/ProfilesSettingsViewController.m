//
//  ProfilesSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/ProfilesSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Headers/TWHeaders.h"

extern void applySquareAvatarsSetting(void);

@implementation ProfilesSettingsViewController

- (NSString*)pageKey {
    return @"profiles";
}

- (void)switchChanged:(UISwitch*)sender {
    [super switchChanged:sender];
    NSString* key = BHTSettingsKeyForSwitch(sender);
    if ([key isEqualToString:@"square_avatars"]) {
        applySquareAvatarsSetting();
    }
}

@end
