# NeoFreeBird

[![Build NeoFreeBird](https://github.com/Vicitiniman/NeoFreeBirdReborn/actions/workflows/build.yml/badge.svg)](https://github.com/Vicitiniman/NeoFreeBirdReborn/actions/workflows/build.yml)

NeoFreeBird is a modular enhancement tweak for X 12.9. It restores familiar
Twitter branding and adds themes, navigation controls, media tools, timeline
filters, and guarded compatibility options for modified installations.

> **Beta software:** NeoFreeBird is developed and tested for X 12.9. Other X
> versions may not be compatible.

NeoFreeBird does not include or distribute the X app. Sideloaded and TrollStore
builds require a decrypted X 12.9 IPA that you are legally authorized to use.

## Compatibility

| Component | Supported target |
| --- | --- |
| Host app | X 12.9 |
| Audited build | X 12.9 build 10 |
| Minimum iOS | iOS 15.0 |
| Architecture | arm64 |
| Packages | Sideloaded IPA, TrollStore TIPA, rootless DEB, rootful DEB |

NeoFreeBird checks version-specific app interfaces before using them. Missing
capabilities are recorded in the compatibility report, and native behavior is
preserved where possible.

## Features

### Appearance and navigation

- Nine coordinated presets, including Apollo-inspired blue, Classic Twitter,
  Midnight OLED, and Native X Blue.
- A visual theme builder with separate light and dark palettes, live previews,
  contrast checks, exact color entry, and a personal theme library.
- Theming across supported timelines, tweet details, settings, navigation
  chrome, and the custom Likes experience.
- Reorderable bottom navigation and sidebar items, including an independent
  **Likes** destination with normal navigation and swipe-back.
- Twitter bird branding for the Home title, compatible iPad rail, classic
  launch animation, display name, and alternate app icon.

### Timeline, Likes, and media

- Layered promoted-content filtering across timelines, profiles, search,
  Explore, cards, articles, and supported video paths.
- Separate **For You** filters for usernames/display names and post text,
  including `@mentions`. Following is never filtered by these lists.
- A Posts/Media selector in Likes with an adaptive, pinch-adjustable waterfall
  that respects each item's aspect ratio.
- Full-window photo and video viewing on iPhone and iPad, original-quality
  photos, highest-available MP4 playback, zoom, paging, and swipe-down dismiss.
- Native-style photo, video, and GIF menus with configurable download and share
  actions.
- Coalesced and downsampled image loading to reduce duplicate work and memory
  pressure, especially on iPad.

### Settings and portability

- Organized settings with global search that opens or highlights the matching
  setting and supported nested editors.
- Exportable preference profiles for validated NeoFreeBird settings, layouts,
  keyword filters, and personal themes.
- Runtime compatibility reports for device-specific troubleshooting.

Profiles never include X accounts, credentials, cookies, cached media, or
compatibility-reply session data.

## Account compatibility

Native X sign-in and native replies remain the defaults.

**Compatibility Sign-in** is an explicit X 12.9 fallback for installations
where the normal account flow does not finish. It opens a separate NeoFreeBird
screen and submits one guarded password request through X's legacy account
service. The password field is cleared before that request starts and is never
saved or included in reports. Verification, account registration, credential
storage, and account switching continue through X's own services. The same
option is available when adding another account. Beta 43 returns the password
request to X 12.9's native client metadata and preserves the minimum preflight
window observed in the successful beta 29 and beta 36 device reports. Captured
WebKit instrumentation remains diagnostic-only and is never supplied to the
password command. Timeline, posting, media, and all other API traffic remain
untouched.

The default-off **Compatibility reply composer** is available when sideloaded
builds reject native replies. It opens X's official reply page in a visible,
in-app web surface and never posts automatically. Compatibility replies for
every native app account use the same persistent x.com session, which does not
switch with the account selected inside X. NeoFreeBird asks you to review that
session before the first compatibility reply after each launch and when it
detects a native-account context change. NeoFreeBird does not read or export
web credentials, cookies, page account data, or reply text, and it cannot match
the web account to the account selected in X. After visually checking X, you
can optionally save a local **Last confirmed: @handle** label. That
user-provided label is not verified and is excluded from preference profiles
and compatibility reports.

## Where to find things

| Feature | Location |
| --- | --- |
| Themes and theme builder | **Settings > NeoFreeBird > Appearance > Themes** |
| Preference profiles | **Settings > NeoFreeBird > Backup & restore** |
| Compatibility report | **Settings > NeoFreeBird > Debug** |
| Signed-out report | **X login screen > Share Report** |

## Build and install

Choose the package for your installation method:

| Method | Output |
| --- | --- |
| Sideloading | `.ipa` |
| TrollStore | `.tipa` |
| Rootless jailbreak | `.deb` |
| Rootful jailbreak | `.deb` |

Avoid injecting multiple X/Twitter tweaks into the same app. Overlapping hooks
can cause startup crashes and inconsistent behavior.

### GitHub Actions

Open **Actions > Build NeoFreeBird > Run workflow**, select the deployment
format, and optionally choose a commit. Sideloaded and TrollStore builds also
need a direct URL to a decrypted X 12.9 IPA.
Download the package from the completed run's **Artifacts** section.

### Local build

Requirements:

- [Theos](https://github.com/theos/theos) with an iOS 16.5 SDK
- GNU Make, `dpkg`, `ldid`, and Python 3
- [cyan](https://github.com/asdfzxcvbn/pyzule-rw) for IPA/TrollStore output
- A legally obtained decrypted X 12.9 IPA for IPA/TrollStore builds

```bash
git clone --recursive https://github.com/Vicitiniman/NeoFreeBirdReborn.git
cd NeoFreeBirdReborn
chmod +x build.sh rebrand.sh deps/ffmpeg-kit-next/build-ffmpeg.sh
```

For a sideloaded or TrollStore build, place the IPA at:

```text
packages/com.atebits.Tweetie2.ipa
```

Then run one build command:

```bash
./build.sh --sideloaded
./build.sh --trollstore
./build.sh --rootless
./build.sh --rootfull
```

The first build takes longer because the FFmpeg stack is compiled and cached.
macOS uses `sips` for alternate-icon sizing; Linux IPA builds require
ImageMagick's `magick` or `convert` command.

## Troubleshooting

First confirm that the host app is X 12.9 and remove any other injected
X/Twitter tweak.

To export a report while signed out:

1. On X's login screen, tap **Share Report** beneath
   **Compatibility Sign-in**.
2. Save the generated JSON.

If X's guarded compatibility service is unavailable, its error alert includes a
**Share Report** action.

After signing in, use **Settings > NeoFreeBird > Debug > Export compatibility
report**. A copy is also stored inside the app container at:

```text
Library/Caches/BHTwitter-X12.9-Compatibility.json
```

For startup crashes, also attach the newest `.ips` report and include the
NeoFreeBird version, X version/build, iOS version, device model, installation
method, and reproduction steps.

## Privacy and safety

- NeoFreeBird does not bypass app attestation or spoof subscriptions.
- It does not save or log passwords, cookies, session tokens, or account data.
- Reports exclude credentials, account identifiers, post/reply text, raw URLs,
  response bodies, and web-session contents.
- Optional web-reply account labels are user-provided, local only, and never
  included in reports or shared preference profiles.
- Compatibility sign-in clears its password field before contacting X and
  delegates successful account storage entirely to X's account service.
- Missing private methods fall back to native behavior or a visible unavailable
  state.

## Contributing

Pull requests and device reports are welcome. Guard private classes and
selectors, preserve native behavior when a capability is unavailable, keep
sensitive data out of diagnostics, and never commit decrypted IPAs or generated
FFmpeg libraries.

Check formatting before opening a pull request:

```bash
./format.sh --check
```

Detailed implementation notes and release history are in
[`docs/X12_9_FEATURE_AUDIT.md`](docs/X12_9_FEATURE_AUDIT.md).

## Credits

NeoFreeBird builds on
[BHTwitter](https://github.com/BandarHL/BHTwitter), NeoFreeBird contributors,
Theacrat's and Orion's NeoFreeBird work,
[FLEX](https://github.com/FLEXTool/FLEX),
[zxPluginsInject](https://github.com/asdfzxcvbn/zxPluginsInject), and
[ffmpeg-kit-next](https://github.com/arthenica/ffmpeg-kit-next).

NeoFreeBird is an independent community project and is not affiliated with,
endorsed by, or sponsored by X Corp., Twitter, or Apple.
