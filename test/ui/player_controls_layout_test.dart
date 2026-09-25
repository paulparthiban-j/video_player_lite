import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/core/theme/app_theme.dart';
import 'package:next_gen_video_player/core/video_player_controller.dart';
import 'package:next_gen_video_player/widgets/parthi_play_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LoadedPlayer extends VideoPlayerControllerNotifier {
  _LoadedPlayer() {
    state = const VideoPlayerState(
      videoPath:
          '/storage/emulated/0/Movies/A very long movie title that should '
          'truncate instead of overflowing (Director\'s Cut) 2160p.mkv',
      isInitialized: true,
      isLoaded: true,
      isPlaying: true,
      position: Duration(minutes: 42, seconds: 7),
      duration: Duration(hours: 2, minutes: 13, seconds: 55),
      bufferDuration: Duration(minutes: 50),
    );
  }
}

const devices = <String, Size>{
  'small phone 320x568': Size(320, 568),
  'small phone landscape 568x320': Size(568, 320),
  'pixel 412x915': Size(412, 915),
  'pixel landscape 915x412': Size(915, 412),
  'foldable 673x841': Size(673, 841),
  'tablet landscape 1280x800': Size(1280, 800),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'next_player/system_controls',
      'parthi_play/orientation',
      'plugins.flutter.io/path_provider',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
  });

  for (final device in devices.entries) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('player controls fit ${device.key} @${scale}x', (
        tester,
      ) async {
        final errors = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = errors.add;
        addTearDown(() => FlutterError.onError = previousOnError);

        final landscape = device.value.width > device.value.height;
        final insets = landscape
            ? const EdgeInsets.fromLTRB(40, 0, 0, 16)
            : const EdgeInsets.fromLTRB(0, 40, 0, 24);

        tester.view.physicalSize = device.value * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              videoPlayerControllerProvider.overrideWith(
                (ref) => _LoadedPlayer(),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.dark,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  // Status bar / notch and gesture bar insets; in landscape
                  // the punch-hole camera sits on the left edge.
                  padding: insets,
                  viewPadding: insets,
                ),
                child: child!,
              ),
              home: const Scaffold(
                backgroundColor: Colors.black,
                body: SizedBox.expand(child: ParthiPlayControls()),
              ),
            ),
          ),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
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
                      .where((l) => l.contains('/lib/'))
                      .map((l) => '  ${l.trim()}'),
                ].join('\n'),
              )
              .join('\n'),
        );
      });
    }
  }
}
