static NSUInteger countOccurrences(NSString* value, NSString* needle) {
    NSUInteger count = 0;
    NSRange remaining = NSMakeRange(0, value.length);
    while (remaining.length > 0) {
        NSRange match = [value rangeOfString:needle
                                    options:0 range:remaining];
        if (match.location == NSNotFound) break;
        count++;
        NSUInteger next = NSMaxRange(match);
        remaining = NSMakeRange(next, value.length - next);
    }
    return count;
}

static void testWebSessionSecurity(void) {
    for (NSString* allowed in @[
             @"https://x.com/home",
             @"https://api.x.com/2/timeline",
             @"https://twitter.com/i/api/graphql/test",
             @"https://upload.twitter.com/1.1/media/upload.json",
             @"https://api.x.com:443/test",
         ]) {
        NSCAssert(BHTWebSessionURLIsAllowed(
            [NSURL URLWithString:allowed]),
            @"Expected an HTTPS first-party X URL");
    }
    for (NSString* blocked in @[
             @"http://x.com/home",
             @"https://x.com.evil.example/home",
             @"https://notx.com/home",
             @"https://twitter.com.evil.example/home",
             @"https://user@x.com/home",
             @"https://x.com:444/home",
             @"file:///tmp/x.com",
         ]) {
        NSCAssert(!BHTWebSessionURLIsAllowed(
            [NSURL URLWithString:blocked]),
            @"Credentials must fail closed outside first-party HTTPS");
    }

    NSCAssert([[BHTWebSessionNormalizedHandle(@" @DylanOlson6 ")
        lowercaseString] isEqualToString:@"dylanolson6"],
        @"Normalize a user-confirmed handle without changing its content");
    for (id invalid in @[
             @"", @"name-with-dash", @"sixteen_char_name", @"a/b",
             @"name.example", @123, NSNull.null
         ]) {
        NSCAssert(BHTWebSessionNormalizedHandle(invalid) == nil,
            @"Reject malformed account labels");
    }

    NSCAssert(BHTWebSessionUserIDFromTWID(@"u%3D123456789") ==
                  123456789,
              @"Decode X's percent-encoded twid cookie");
    NSCAssert(BHTWebSessionUserIDFromTWID(@"u=42") == 42,
              @"Accept X's decoded twid form");
    for (id invalid in @[
             @"", @"u%3D0", @"u%3D12x", @"-3",
             @"18446744073709551616", @123, NSNull.null
         ]) {
        NSCAssert(BHTWebSessionUserIDFromTWID(invalid) == 0,
            @"Reject malformed or overflowing user IDs");
    }

    NSCAssert(BHTWebSessionCredentialValueIsValid(
                  @"abcDEF1234567890._~-+%2B"),
              @"Accept bounded cookie-safe values");
    for (id invalid in @[
             @"short", @"abc;defgh", @"abc defgh", @"abc\r\ndefgh",
             @123, NSNull.null
         ]) {
        NSCAssert(!BHTWebSessionCredentialValueIsValid(invalid),
            @"Reject header delimiters and non-string credentials");
    }

    NSString* merged = BHTWebSessionCookieHeader(
        @"lang=en; auth_token=old; theme=dark; ct0=old; twid=u%3D4",
        @"newAuthValue123", @"newCsrfValue123", 99);
    NSCAssert([merged containsString:@"lang=en"] &&
              [merged containsString:@"theme=dark"],
              @"Preserve unrelated first-party cookies");
    NSCAssert(![merged containsString:@"=old"],
              @"Remove stale authentication cookie values");
    NSCAssert(countOccurrences(merged, @"auth_token=") == 1 &&
              countOccurrences(merged, @"ct0=") == 1 &&
              countOccurrences(merged, @"twid=") == 1,
              @"Emit exactly one value for each authentication cookie");
    NSCAssert([merged containsString:@"twid=u%3D99"],
              @"Encode the validated user ID in X's cookie form");
    puts("PASS: secure web-session host, identifier, credential, and cookie validation");
}
