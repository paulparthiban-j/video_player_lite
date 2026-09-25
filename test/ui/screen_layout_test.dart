import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/core/theme/app_theme.dart';
import 'package:next_gen_video_player/screens/about_screen.dart';
import 'package:next_gen_video_player/screens/parthi_play_main_screen.dart';
import 'package:next_gen_video_player/screens/vault_screen.dart';
import 'package:next_gen_video_player/screens/scan_directories_settings_screen.dart';
import 'package:next_gen_video_player/screens/settings_screen.dart';
import 'package:next_gen_video_player/screens/vault_auth_screen.dart';
import 'package:next_gen_video_player/screens/vault_forgot_screen.dart';
import 'package:next_gen_video_player/screens/vault_security_setup_screen.dart';
import 'package:next_gen_video_player/screens/vault_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Representative devices: small/budget phones, flagship phones, phone
/// landscape, foldable inner screens and tablets in both orientations.
const devices = <String, Size>{
  'small phone 320x568': Size(320, 568),
  'budget phone 360x640': Size(360, 640),
  'pixel 412x915': Size(412, 915),
  'phone landscape 915x412': Size(915, 412),
  'foldable 673x841': Size(673, 841),
  'tablet portrait 800x1280': Size(800, 1280),
  'tablet landscape 1280x800': Size(1280, 800),
};

/// Default, Samsung/Xiaomi "large" font, and accessibility maximum.
const textScales = [1.0, 1.3, 2.0];

final screens = <String, Widget Function()>{
  'Library': () => const ParthiPlayMainScreen(),
  'Vault': () => const VaultScreen(),
  'Settings': () => const SettingsScreen(),
  'About': () => const AboutScreen(),
  'Scan directories': () => const ScanDirectoriesSettingsScreen(),
  'Vault login': () => const VaultAuthScreen(),
  'Vault setup': () => const VaultSetupScreen(),
  'Vault recovery': () => const VaultForgotScreen(),
  'Vault security setup': () => const VaultSecuritySetupScreen(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'scanned_videos_cache': jsonEncode([
        for (var i = 0; i < 12; i++)
          {
            'path': '/storage/emulated/0/Movies/Folder $i/video_$i.mp4',
            'name': i == 0
                ? 'An extremely long video file name that keeps going and '
                      'going to test wrapping (2024) [1080p] x265 HDR.mkv'
                : 'Holiday clip $i.mp4',
            'size': 734003200 * (i + 1),
            'lastModified': DateTime(2024, 1, i + 1).toIso8601String(),
            'thumbnail': null,
            'format': 'mp4',
            'isSupported': true,
            'quality': '1080p',
            'type': 0,
          },
      ]),
      'vault_is_setup': true,
      'security_questions': ['What was your first pet\'s name?', 'City?'],
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'plugins.flutter.io/path_provider',
      'dev.fluttercommunity.plus/package_info',
      'dev.fluttercommunity.plus/device_info',
      'next_player/system_controls',
      'flutter.baseflow.com/permissions/methods',
      'plugins.flutter.io/url_launcher_android',
      'receive_sharing_intent/messages',
      'com.fluttercandies/photo_manager',
      'plugins.justsoftware.de/video_thumbnail',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
  });

  for (final screen in screens.entries) {
    for (final device in devices.entries) {
      for (final scale in textScales) {
        testWidgets('${screen.key} fits ${device.key} @${scale}x', (
          tester,
        ) async {
          final errors = <FlutterErrorDetails>[];
          final previousOnError = FlutterError.onError;
          FlutterError.onError = errors.add;
          addTearDown(() => FlutterError.onError = previousOnError);

          tester.view.physicalSize = device.value * 2;
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: ThemeMode.dark,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    // Status bar and gesture navigation bar (edge-to-edge).
                    padding: const EdgeInsets.only(top: 24, bottom: 24),
                    viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
                  ),
                  child: child!,
                ),
                routes: {
                  '/': (_) => screen.value(),
                  '/vault': (_) => const Scaffold(),
                  '/vault-auth': (_) => const Scaffold(),
                  '/vault-setup': (_) => const Scaffold(),
                  '/vault-forgot': (_) => const Scaffold(),
                  '/vault-security-setup': (_) => const Scaffold(),
                  '/main': (_) => const Scaffold(),
                },
              ),
            ),
          );
          // Let async loads (prefs) complete and entrance animations settle.
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 200));
          }
          // Unmount so screens cancel their timers and subscriptions.
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 3));
          FlutterError.onError = previousOnError;
          expect(
            errors,
            isEmpty,
            reason: errors
                .map(
                  (e) => [
                    e.exceptionAsString().split('\n').first,
                    ...e
                        .toString()
                        .split('\n')
                        .where(
                          (l) => l.contains('file:///') && l.contains('/lib/'),
                        )
                        .map((l) => '  ${l.trim()}'),
                  ].join('\n'),
                )
                .join('\n'),
          );
        });
      }
    }
  }
}
