//
//  AuthViewController.m
//  BHTwitter
//
//  Created by BandarHelal on 25/09/2021.
//

#import "AuthViewController.h"
#import <LocalAuthentication/LocalAuthentication.h>

@interface AuthViewController ()
@property (nonatomic, strong) UILabel* statusLabel;
@property (nonatomic, strong) UIButton* retryButton;
@property (nonatomic, assign) BOOL evaluationInProgress;
@end

@implementation AuthViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UIImageView* lock = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
    lock.translatesAutoresizingMaskIntoConstraints = NO;
    lock.tintColor = UIColor.labelColor;

    self.statusLabel = [UILabel new];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.text = @"Authentication is required to open Twitter.";
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;

    self.retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.retryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.retryButton setTitle:@"Try Again"
                      forState:UIControlStateNormal];
    self.retryButton.titleLabel.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [self.retryButton addTarget:self
                         action:@selector(retryAuthentication)
               forControlEvents:UIControlEventTouchUpInside];
    self.retryButton.hidden = YES;

    [self.view addSubview:lock];
    [self.view addSubview:self.statusLabel];
    [self.view addSubview:self.retryButton];
    [NSLayoutConstraint activateConstraints:@[
        [lock.centerXAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [lock.centerYAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor
                           constant:-44],
        [lock.widthAnchor constraintEqualToConstant:36],
        [lock.heightAnchor constraintEqualToConstant:36],
        [self.statusLabel.leadingAnchor
            constraintGreaterThanOrEqualToAnchor:
                self.view.safeAreaLayoutGuide.leadingAnchor
                                      constant:32],
        [self.statusLabel.trailingAnchor
            constraintLessThanOrEqualToAnchor:
                self.view.safeAreaLayoutGuide.trailingAnchor
                                   constant:-32],
        [self.statusLabel.centerXAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [self.statusLabel.topAnchor constraintEqualToAnchor:lock.bottomAnchor
                                                   constant:16],
        [self.retryButton.centerXAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [self.retryButton.topAnchor
            constraintEqualToAnchor:self.statusLabel.bottomAnchor
                           constant:16]
    ]];

    [self retryAuthentication];
}

- (void)retryAuthentication {
    if (self.evaluationInProgress) return;
    self.evaluationInProgress = YES;
    self.retryButton.hidden = YES;
    self.statusLabel.text = @"Authenticate to open Twitter.";

    LAContext* context = [[LAContext alloc] init];
    NSError* availabilityError = nil;
    if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication
                             error:&availabilityError]) {
        [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
                localizedReason:
                    @"Face ID, Touch ID, or your passcode is required to use Twitter"
                          reply:^(BOOL success, NSError* _Nullable error) {
                              [self finishWithResult:success error:error];
                          }];
    } else {
        [self finishWithResult:NO error:availabilityError];
    }
}

- (void)finishWithResult:(BOOL)success error:(NSError*)error {
    if (error) {
        NSLog(@"%@", error);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (success) {
            [self dismissViewControllerAnimated:true
                                     completion:^{
                                         if (self.completion) self.completion(YES);
                                     }];
        } else {
            self.evaluationInProgress = NO;
            self.statusLabel.text =
                error.localizedDescription.length > 0
                    ? error.localizedDescription
                    : @"Authentication was not completed.";
            self.retryButton.hidden = NO;
            if (self.completion) self.completion(NO);
        }
    });
}

@end
