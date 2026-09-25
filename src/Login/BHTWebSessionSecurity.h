#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Pure validation helpers shared by the web sign-in screen and the request
// bridge. They never persist or log their inputs.
BOOL BHTWebSessionURLIsAllowed(NSURL* _Nullable URL);
NSString* _Nullable BHTWebSessionNormalizedHandle(id _Nullable value);
uint64_t BHTWebSessionUserIDFromTWID(NSString* _Nullable value);
BOOL BHTWebSessionCredentialValueIsValid(NSString* _Nullable value);
NSString* BHTWebSessionCookieHeader(
    NSString* _Nullable existingHeader,
    NSString* authToken,
    NSString* csrfToken,
    uint64_t userID);

NS_ASSUME_NONNULL_END
