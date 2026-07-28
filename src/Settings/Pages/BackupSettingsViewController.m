#import "Settings/Pages/BackupSettingsViewController.h"

#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "ThemeColor/BHTThemePresets.h"

static const NSUInteger kBHTMaximumPreferenceProfileBytes = 512 * 1024;

@implementation BackupSettingsViewController

- (NSString*)pageKey {
    return @"backup";
}

- (void)exportPreferenceProfile:(__unused NSDictionary*)sender {
    NSError* error = nil;
    NSData* data =
        [BHTSettings preferenceProfileJSONDataWithError:&error];
    if (!data) {
        [self showProfileError:error];
        return;
    }

    NSURL* destination =
        [[BHTManager temporaryDirectoryURL]
            URLByAppendingPathComponent:
                @"NeoFreeBird-Preferences.json"];
    if (![data writeToURL:destination
                  options:NSDataWritingAtomic
                    error:&error]) {
        [self showProfileError:error];
        return;
    }
    [BHTManager showSaveVC:destination];
}

- (void)importPreferenceProfile:(__unused NSDictionary*)sender {
    UIDocumentPickerViewController* picker =
        [[UIDocumentPickerViewController alloc]
            initWithDocumentTypes:@[@"public.json", @"public.text"]
                           inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller
    didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
    NSURL* url = urls.firstObject;
    if (!url) return;

    BOOL securityScoped = [url startAccessingSecurityScopedResource];
    NSError* error = nil;
    NSData* data = [NSData dataWithContentsOfURL:url
                                        options:NSDataReadingMappedIfSafe
                                          error:&error];
    if (securityScoped) [url stopAccessingSecurityScopedResource];
    if (!data || data.length == 0 ||
        data.length > kBHTMaximumPreferenceProfileBytes) {
        if (!error) {
            error = [NSError
                errorWithDomain:@"com.neofreebird.preference-profile"
                           code:10
                       userInfo:@{
                           NSLocalizedDescriptionKey:
                               [[BHTBundle sharedBundle]
                                   localizedStringForKey:
                                       @"IMPORT_PREFERENCE_PROFILE_SIZE_ERROR"]
                       }];
        }
        [self showProfileError:error];
        return;
    }

    id profile = [NSJSONSerialization JSONObjectWithData:data
                                                 options:0
                                                   error:&error];
    if (![profile isKindOfClass:NSDictionary.class] ||
        ![BHTSettings applyPreferenceProfile:profile error:&error]) {
        [self showProfileError:error];
        return;
    }

    [BHTThemePresets reapplyCurrentAccent];
    [self.tableView reloadData];
    [self showProfileAlertWithTitleKey:
              @"IMPORT_PREFERENCE_PROFILE_SUCCESS_TITLE"
                              messageKey:
                                  @"IMPORT_PREFERENCE_PROFILE_SUCCESS_DETAIL"];
}

- (void)showProfileError:(NSError*)error {
    NSString* fallback = [[BHTBundle sharedBundle]
        localizedStringForKey:@"PREFERENCE_PROFILE_GENERIC_ERROR"];
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[[BHTBundle sharedBundle]
                                     localizedStringForKey:
                                         @"PREFERENCE_PROFILE_ERROR_TITLE"]
                         message:error.localizedDescription ?: fallback
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:[[BHTBundle sharedBundle]
                                       localizedStringForKey:
                                           @"PREFERENCE_PROFILE_OK"]
                             style:UIAlertActionStyleDefault
                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showProfileAlertWithTitleKey:(NSString*)titleKey
                          messageKey:(NSString*)messageKey {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[[BHTBundle sharedBundle]
                                     localizedStringForKey:titleKey]
                         message:[[BHTBundle sharedBundle]
                                     localizedStringForKey:messageKey]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:
               [UIAlertAction
                   actionWithTitle:[[BHTBundle sharedBundle]
                                       localizedStringForKey:
                                           @"PREFERENCE_PROFILE_OK"]
                             style:UIAlertActionStyleDefault
                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
