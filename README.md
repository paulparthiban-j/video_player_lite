# Parthi Play

[![CI](https://github.com/paulparthiban-j/video_player_lite/actions/workflows/ci.yml/badge.svg)](https://github.com/paulparthiban-j/video_player_lite/actions/workflows/ci.yml)

A Flutter video player for Android and iOS built on
[media_kit](https://pub.dev/packages/media_kit) (libmpv), with hardware
decoding, gesture controls, network streaming and an encrypted private
vault.

## Features

| Area | Highlights |
| --- | --- |
| Playback | libmpv with hardware decoding and automatic software fallback, playback speed, aspect-ratio modes, resume position, HDR tone mapping |
| Controls | Swipe for seek, volume and brightness; double-tap seek; hold-to-fast-forward; lock screen; rotation toggle |
| Audio | Multiple audio tracks, 10-band equalizer, volume boost, audio delay |
| Subtitles | External subtitle files, online subtitle search, styling (size, colour, background, position) |
| Library | MediaStore-backed scanning on Android, folder view, configurable scan directories, thumbnails |
| Streaming | HLS / HTTP streams, saved stream list, YouTube links with quality selection, links shared from other apps |
| Tools | Picture-in-picture, background playback, video cutter (FFmpeg) |
| Private vault | AES-256-GCM encrypted videos and metadata, streamed to the player without decrypted copies on disk; auto-lock, screenshot blocking, decoy vault, recovery questions and brute-force lockout (see [SECURITY.md](SECURITY.md)) |

## Getting started

Requirements: Flutter **3.47** (stable) or newer, Android SDK / Xcode for
device builds.

```bash
flutter pub get
flutter run
```

### Quality gates

CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs the same
checks you can run locally; all of them must pass:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
```

Lint rules live in [analysis_options.yaml](analysis_options.yaml). Beyond the
Flutter recommended set they flag leaked subscriptions and sinks, and
un-awaited futures; wrap intentional fire-and-forget calls in `unawaited(...)`.

### Downloading builds

- **Releases:** every published version is on the
  [Releases page](https://github.com/paulparthiban-j/video_player_lite/releases)
  with APKs for direct install:
  - `arm64-v8a` for almost every phone from 2017 onwards (smallest download)
  - `armeabi-v7a` for older 32-bit phones
  - `universal` if unsure
  - an `.aab` for Google Play, plus `SHA256SUMS.txt`
- **Latest commit:** each CI run attaches an installable APK under
  *Actions → CI → run → Artifacts*.

### Publishing a release

```bash
# bump `version:` in pubspec.yaml if you like; the tag decides the name
git tag v1.2.0
git push origin v1.2.0
```

Or open *Actions → Release → Run workflow* and enter a version.
[release.yml](.github/workflows/release.yml) runs the analyzer and tests,
builds the APKs and bundle, and publishes the GitHub Release. The build
number comes from the workflow run number, so every upload is higher than
the last.

**Signing.** Add these repository secrets (*Settings → Secrets and
variables → Actions*) so releases are signed with your upload key:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias, e.g. `upload` |
| `ANDROID_KEY_PASSWORD` | key password |

Create a keystore once with:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias upload
```

Without the secrets, releases are signed with a debug key and the release
notes say so. Such builds install fine, but they can't be uploaded to Play,
and users must uninstall them before installing a properly signed build.

For local release builds, put the same four values in
`android/key.properties` (git-ignored) as `storeFile`, `storePassword`,
`keyAlias`, `keyPassword`.

## Device support

| | |
| --- | --- |
| Android | 7.0 (API 24) and newer, 32- and 64-bit ARM plus x86_64; 16 KB memory-page devices (Android 15+) |
| Screens | Phones from 320 dp wide, foldables, tablets and resizable windows (split screen, DeX, ChromeOS); lists switch to 2–3 columns on wide windows, forms stay readable width |
| Orientation | Phones browse in portrait; tablets and foldables rotate freely; the player supports auto/landscape/portrait |
| Display cutouts | Video can use notch and punch-hole areas; controls stay inside the safe area |
| System bars | Edge-to-edge (enforced on Android 15+), content clears the gesture bar |
| Text size | Layouts are tested at 1.0×, 1.3× (common OEM "large" setting) and 2.0× |

`test/ui/` renders every screen and the player controls on devices from a
320×568 phone to a 1280×800 tablet, in both orientations, at each text
scale, and fails on any overflow.

## Project layout

```
lib/
  main.dart                  App entry: error handling, routes, theme mode
  core/
    app/error_reporting.dart Global error hooks (single place to add crash reporting)
    security/                Password hashing (PBKDF2) and vault encryption (AES-256-GCM)
    theme/app_theme.dart     Light and dark Material themes
    ui/responsive.dart       Window size classes, adaptive lists, orientation policy
    video_player_controller.dart  Riverpod StateNotifier owning the media_kit Player
  screens/                   Full-screen routes (library, settings, vault, cutter, ...)
  services/                  Platform, storage and domain services (mostly static)
  widgets/                   Player surface, controls, gestures, list items
test/                        Unit tests (mirrors lib/) and ui/ layout tests
docs/archive/                Historical development reports
```

### Player state

`VideoPlayerControllerNotifier` is the single owner of the native player.
Widgets subscribe to the slices they render with
`ref.watch(videoPlayerControllerProvider.select(...))`, which keeps
position ticks (every ~150 ms) from rebuilding unrelated UI. A new
`initializeVideo` call supersedes one that is still loading; the superseded
player is disposed rather than leaked.

`VideoPlayerState.copyWith` distinguishes "not passed" from an explicit
`null`, so nullable fields such as `errorMessage` can be cleared.

### Error handling and logging

`ErrorReporting.install()` routes framework, platform-dispatcher and zone
errors to `ErrorReporting.report`. In release builds `debugPrint` is a no-op
so file names and stream URLs never reach device logs, and the red error
screen is replaced by a neutral message.
