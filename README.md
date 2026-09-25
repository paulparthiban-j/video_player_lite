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
| Private vault | AES-256-GCM encrypted videos and metadata, streamed to the player without decrypted copies on disk; decoy vault, recovery questions and brute-force lockout (see [SECURITY.md](SECURITY.md)) |

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

### Release builds (Android)

Release signing is read from `android/key.properties`, which is git-ignored:

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Without that file a release build is signed with the debug key and prints a
warning; such builds are fine for local testing but cannot be published.

```bash
flutter build appbundle --release
```

## Project layout

```
lib/
  main.dart                  App entry: error handling, routes, theme mode
  core/
    app/error_reporting.dart Global error hooks (single place to add crash reporting)
    security/                Password hashing (PBKDF2) and vault encryption (AES-256-GCM)
    theme/app_theme.dart     Light and dark Material themes
    video_player_controller.dart  Riverpod StateNotifier owning the media_kit Player
  screens/                   Full-screen routes (library, settings, vault, cutter, ...)
  services/                  Platform, storage and domain services (mostly static)
  widgets/                   Player surface, controls, gestures, list items
test/                        Unit tests (mirrors lib/)
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
