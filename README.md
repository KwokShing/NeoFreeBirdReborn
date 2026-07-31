# NeoFreeBird

[![Build NeoFreeBird](https://github.com/Vicitiniman/NeoFreeBirdReborn/actions/workflows/build.yml/badge.svg)](https://github.com/Vicitiniman/NeoFreeBirdReborn/actions/workflows/build.yml)

NeoFreeBird is a modular enhancement tweak for X 12.9. It combines the newer
NeoFreeBird architecture with targeted X 12.9 compatibility work, improved
Twitter branding, media tools, themes, navigation, content controls, and
privacy-conscious diagnostics.

> **Beta software:** NeoFreeBird is developed and tested for X 12.9. It uses
> guarded, version-specific app interfaces, so other X versions are not
> considered compatible.

NeoFreeBird does not include or distribute the X app. Sideloaded and TrollStore
builds require a decrypted X 12.9 IPA that you are legally authorized to use.

## Compatibility

| Component | Supported target |
| --- | --- |
| Host app | X 12.9 (build 10 audited) |
| Current package | 6.1.0-beta.35 |
| Minimum iOS | iOS 15.0 |
| Architecture | arm64 |
| Packages | Sideloaded IPA, TrollStore TIPA, rootless DEB, rootful DEB |

Private app interfaces can vary between builds. When a required capability is
missing, NeoFreeBird records it in the compatibility report and preserves
native behavior where possible.

## Highlights

### Appearance and navigation

- Nine coordinated presets: Apollo-inspired blue, Classic Twitter blue,
  Native X blue, Midnight OLED, Evergreen, Rose Quartz, Solarized Coast,
  Amethyst, and Cinder.
- A visual theme builder with separate light and dark palettes, live previews,
  contrast checks, and save/apply/edit/duplicate/delete controls. Personal
  themes travel with preference-profile export and import.
- Coordinated theming across supported timelines, tweet details, settings,
  navigation chrome, and NeoFreeBird's custom Likes experience.
- Reorderable bottom navigation and sidebar items, including an independent
  **Likes** destination with normal navigation and swipe-back.
- Twitter bird branding for the Home title, compatible iPad rail, optional
  classic launch animation, display name, and alternate app icon.

### Likes and media

- A Posts/Media selector for Likes.
- An adaptive, pinch-adjustable waterfall that follows each item's aspect
  ratio instead of forcing every image into the same crop.
- Full-window photo and video viewing on iPhone and iPad.
- Original-quality photo loading and highest-available MP4 playback.
- Native-style photo, video, and GIF menus with configurable action order.
- Download, share, contextual preview, zoom, paging, and interactive
  swipe-down dismissal.
- Coalesced and downsampled image loading to reduce duplicate work and memory
  pressure, especially on iPad.

### Timeline and content controls

- Layered promoted-content filtering across timelines, profiles, search,
  Explore, cards, articles, and supported video paths.
- Separate **For You** filters for usernames/display names and post text,
  including `@mentions`; Following is explicitly excluded.
- Controls for prompts, recommendations, topics, Spaces, trends, custom
  timelines, and other optional surfaces.
- Highest-quality image loading, optional full-frame media, and a
  highest-video-quality preference.

### Settings, themes, and profiles

- Organized settings pages with localized global search.
- Search results that open or highlight the matching setting or nested editor.
- Portable preference profiles containing validated NeoFreeBird settings,
  navigation layouts, keyword filters, and personal themes.
- An allow-listed profile format that excludes X accounts, credentials,
  cookies, cached media, and web-reply session data.
- Runtime compatibility reports for device-specific troubleshooting.

### Account compatibility

Native X sign-in and native replies remain the defaults.

For X 12.9 installations where the normal account flow does not finish,
NeoFreeBird provides an explicit **Compatibility Sign-in** fallback. It calls
X's own password, challenge, account-registration, and credential-storage
services. Every required private method is checked before use, and the same
fallback is available from X's Add Account flow.

If a sideloaded build rejects native replies, the X 12.9-only, default-off
**Compatibility reply composer** can open X's official web reply screen inside
the app. It is a visible web surface, not X's native composer, and it never
auto-posts. Complete **Set Up Web Replies** normally once (until X expires the
web session), then verify the displayed web account before posting because it
can differ from the account selected in the app. NeoFreeBird transiently
validates navigation destinations for safety, but it does not store or export
raw URLs, credentials, cookies, account details, or reply text.

## Installation

Build the package that matches your installation method:

| Method | Output |
| --- | --- |
| Sideloading | `.ipa` |
| TrollStore | `.tipa` |
| Rootless jailbreak | `.deb` |
| Rootful jailbreak | `.deb` |

Install the result with the corresponding sideloading, TrollStore, or package
manager tool. Avoid injecting multiple X/Twitter tweaks into the same app;
overlapping hooks can cause startup crashes and inconsistent behavior.

## Building locally

### Requirements

- [Theos](https://github.com/theos/theos)
- An iOS 16.5 SDK in Theos; the project targets iOS 15.0
- GNU Make, `dpkg`, and `ldid`
- Python 3 for branding and build checks
- [cyan](https://github.com/asdfzxcvbn/pyzule-rw) for IPA/TrollStore output
- A legally obtained decrypted X 12.9 IPA for IPA/TrollStore builds

Clone the project and its submodules:

```bash
git clone --recursive https://github.com/Vicitiniman/NeoFreeBirdReborn.git
cd NeoFreeBirdReborn
chmod +x build.sh rebrand.sh deps/ffmpeg-kit-next/build-ffmpeg.sh
```

For sideloaded or TrollStore builds, place the IPA at:

```text
packages/com.atebits.Tweetie2.ipa
```

Choose one build format:

```bash
./build.sh --sideloaded
./build.sh --trollstore
./build.sh --rootless
./build.sh --rootfull
```

The FFmpeg stack is compiled and cached on first use, so the first build takes
longer. macOS uses `sips` for alternate-icon sizing; Linux IPA builds require
ImageMagick's `magick` or `convert` command.

Sideloaded and TrollStore branding is applied during packaging. Reinstall or
update the generated app before evaluating its display name, launch image, or
alternate-icon list.

## Building with GitHub Actions

Open **Actions > Build NeoFreeBird > Run workflow**, select the deployment
format, and optionally choose a commit.

Sideloaded and TrollStore builds also require a direct URL to a decrypted
X 12.9 IPA that you are authorized to use. The workflow verifies the host-app
version before packaging. Download the generated package from the completed
run's **Artifacts** section.

## Privacy and safety boundaries

- NeoFreeBird does not bypass app attestation or spoof subscriptions.
- It does not harvest passwords, cookies, session tokens, or account data.
- Compatibility reports exclude credentials, account identifiers, reply text,
  raw URLs, response bodies, and web-session contents.
- Reports contain app/build details, capability availability, preference
  states, keyword counts, layout summaries, and aggregate diagnostics.
- Preference profiles contain only validated NeoFreeBird settings and personal
  themes. The Compatibility reply toggle is intentionally excluded.
- Compatibility sign-in stores successful accounts only through X's native
  account service.
- Compatibility web replies use a visible, persistent WebKit session that
  NeoFreeBird only checks for safe navigation destinations; it does not inspect
  account or message content or export the session.
- Missing private methods fall back to native behavior or a visible
  unavailable state.

## Troubleshooting

First confirm that the app is X 12.9 and remove other tweaks injected into the
same app.

### Export a report while signed out

1. Open **Compatibility Sign-in** from X's login screen.
2. Tap **Share Report**.
3. Save the generated JSON.

### Export a report after signing in

1. Open **Settings > NeoFreeBird > Debug**.
2. Tap **Export compatibility report**.
3. Attach the JSON to the issue or pull request.

A copy is also written inside the app container at:

```text
Library/Caches/BHTwitter-X12.9-Compatibility.json
```

For a startup crash, attach the newest `.ips` crash report and include the
NeoFreeBird version, X version/build, iOS version, device model, installation
method, and reproduction steps.

For compatibility replies, complete **Set Up Web Replies** and verify the
displayed X account before testing a reply.

## Contributing

Pull requests and device reports are welcome. Changes should:

- Guard every private class and selector before use.
- Preserve native X behavior when a capability is unavailable.
- Add a setting for new user-visible behavior.
- Keep credentials, account content, post text, and raw URLs out of
  diagnostics.
- Update compatibility reporting when adding a version-specific hook.
- Never commit decrypted IPAs or generated FFmpeg libraries.

Check formatting before opening a pull request:

```bash
./format.sh --check
```

Detailed implementation notes are in
[`docs/X12_9_FEATURE_AUDIT.md`](docs/X12_9_FEATURE_AUDIT.md).

## Credits

NeoFreeBird builds on the work of
[BHTwitter](https://github.com/BandarHL/BHTwitter), NeoFreeBird contributors,
Theacrat's and Orion's NeoFreeBird work,
[FLEX](https://github.com/FLEXTool/FLEX),
[zxPluginsInject](https://github.com/asdfzxcvbn/zxPluginsInject), and
[ffmpeg-kit-next](https://github.com/arthenica/ffmpeg-kit-next).

NeoFreeBird is an independent community project and is not affiliated with,
endorsed by, or sponsored by X Corp., Twitter, Apple, or Apollo.
