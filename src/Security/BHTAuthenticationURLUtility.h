#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Returns YES for authentication and callback URLs that must remain inside
// X's own browser/authentication session. The helper deliberately records only
// aggregate routing reasons; it never stores the URL or any query values.
BOOL BHTShouldKeepAuthenticationURLInApp(NSURL* _Nullable url);

// Privacy-safe counters used by the compatibility report. No host, path,
// account identifier, callback value, or token is included.
NSDictionary<NSString*, NSNumber*>*
BHTAuthenticationRoutingDiagnosticSnapshot(void);

NS_ASSUME_NONNULL_END
