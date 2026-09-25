import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/core/security/vault_crypto.dart';
import 'package:next_gen_video_player/core/theme/app_theme.dart';
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

/// Library contents shared by the layout tests, including a pathological
/// file name.
List<Map<String, Object?>> sampleLibrary() => [
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
];

late Directory layoutTempDir;

/// Mocks the platform channels screens touch and seeds preferences.
void installLayoutMocks() {
  setUpAll(() => VaultCrypto.algorithm = DartAesGcm.with256bits());

  setUp(() async {
    layoutTempDir = await Directory.systemTemp.createTemp('layout_');
    SharedPreferences.setMockInitialValues({
      'scanned_videos_cache': jsonEncode(sampleLibrary()),
      'vault_is_setup': true,
      'security_questions': ['What was your first pet\'s name?', 'City?'],
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => layoutTempDir.path,
    );
    for (final name in [
      'dev.fluttercommunity.plus/package_info',
      'dev.fluttercommunity.plus/device_info',
      'next_player/system_controls',
      'parthi_play/orientation',
      'flutter.baseflow.com/permissions/methods',
      'plugins.flutter.io/url_launcher_android',
      'receive_sharing_intent/messages',
      'com.fluttercandies/photo_manager',
      'plugins.justsoftware.de/video_thumbnail',
      'miguelruivo.flutter.plugins.filepicker',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
  });

  tearDown(() async {
    if (await layoutTempDir.exists()) {
      await layoutTempDir.delete(recursive: true);
    }
  });
}

typedef TesterStep = Future<void> Function(WidgetTester tester);

/// Registers one test per device and text scale that renders [build],
/// optionally runs [interact] (open a tab, sheet or dialog), and fails on
/// any overflow or exception.
void layoutMatrix(
  String name,
  Widget Function() build, {
  TesterStep? prepare,
  TesterStep? interact,
  Map<String, Size> deviceSet = devices,
}) {
  for (final device in deviceSet.entries) {
    for (final scale in textScales) {
      testWidgets('$name fits ${device.key} @${scale}x', (tester) async {
        if (prepare != null) await prepare(tester);

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
                '/': (_) => build(),
                for (final route in [
                  '/vault',
                  '/vault-auth',
                  '/vault-setup',
                  '/vault-forgot',
                  '/vault-security-setup',
                  '/main',
                ])
                  route: (_) => const Scaffold(),
              },
            ),
          ),
        );
        // Let async loads (prefs) complete and entrance animations settle.
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        if (interact != null) {
          await interact(tester);
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 200));
          }
        }
        // Unmount so screens cancel their timers and subscriptions.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
        FlutterError.onError = previousOnError;
        expect(errors, isEmpty, reason: describeErrors(errors));
      });
    }
  }
}

String describeErrors(List<FlutterErrorDetails> errors) => errors
    .map(
      (e) => [
        e.exceptionAsString().split('\n').first,
        ...e
            .toString()
            .split('\n')
            .where((l) => l.contains('/lib/'))
            .take(4)
            .map((l) => '  ${l.trim()}'),
      ].join('\n'),
    )
    .join('\n');

/// Taps the widget found by [finder], scrolling it into view first.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 300));
}
