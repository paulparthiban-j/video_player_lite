import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/core/video_player_controller.dart';
import 'package:next_gen_video_player/screens/file_browser_screen.dart';
import 'package:next_gen_video_player/screens/launch_screen.dart';
import 'package:next_gen_video_player/screens/next_file_browser_screen.dart';
import 'package:next_gen_video_player/screens/parthi_play_main_screen.dart';
import 'package:next_gen_video_player/screens/vault_auth_screen.dart';
import 'package:next_gen_video_player/screens/vault_screen.dart';
import 'package:next_gen_video_player/screens/video_cutter_screen.dart';
import 'package:next_gen_video_player/services/file_browser_service.dart';
import 'package:next_gen_video_player/services/vault_auto_lock.dart';
import 'package:next_gen_video_player/services/vault_service.dart';
import 'package:next_gen_video_player/widgets/equalizer_widget.dart';
import 'package:next_gen_video_player/widgets/subtitle_selection_widget.dart';
import 'package:next_gen_video_player/widgets/video_file_item.dart';
import 'package:path/path.dart' as p;

import 'layout_harness.dart';

/// Hosts a bottom-sheet body the way showModalBottomSheet does: at the
/// bottom, at most ~70% of the screen tall.
Widget _sheetHost(Widget child) => Scaffold(
  backgroundColor: Colors.black,
  body: Builder(
    builder: (context) => Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Material(color: const Color(0xFF1E1E1E), child: child),
      ),
    ),
  ),
);

/// Mirrors VideoCutterScreen's layout with a placeholder instead of the
/// native video surface.
Widget _cutterLayout() {
  final panel = CutterControlsPanel(
    position: const Duration(minutes: 42, seconds: 7),
    duration: const Duration(hours: 2, minutes: 13, seconds: 55),
    start: 60000,
    end: 5400000,
    isProcessing: false,
    onSeek: (_) {},
    onRangeChanged: (_) {},
    onRangeChangeStart: () {},
    onRangeChangeEnd: (_) {},
    onCut: () {},
  );
  return Builder(
    builder: (context) {
      final landscape =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      final video = Expanded(flex: 3, child: Container(color: Colors.black));
      final controls = Expanded(flex: 2, child: panel);
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Video Cutter')),
        body: SafeArea(
          child: landscape
              ? Row(children: [video, controls])
              : Column(children: [video, controls]),
        ),
      );
    },
  );
}

Future<void> _unlockVaultWithVideos(WidgetTester tester) async {
  await tester.runAsync(() async {
    await VaultService.logout();
    await VaultService.hardResetVault();
    await VaultService.setupVault('main-pass', 'decoy-pass');
    await VaultService.authenticate('main-pass');
    const longName =
        'A very long private video name that should wrap or ellipsize '
        'cleanly on every device (2024).mp4';
    for (final name in [longName, 'Short.mkv', 'Clip 3.mp4']) {
      final file = File(p.join(layoutTempDir.path, name))
        ..writeAsStringSync('x' * 2048);
      await VaultService.hideVideo(file.path);
    }
  });
  VaultAutoLock.resetForTest();
}

const _longListName =
    'An extremely long video file name that keeps going and going '
    '(2024) [2160p] x265 HDR10+ Atmos.mkv';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installLayoutMocks();

  // --- Remaining screens -------------------------------------------------
  layoutMatrix('Launch', () => const LaunchScreen());
  layoutMatrix('File browser', () => const FileBrowserScreen());
  layoutMatrix('Next file browser', () => const NextFileBrowserScreen());
  layoutMatrix('Video cutter', _cutterLayout);

  // --- Library tabs and dialogs ------------------------------------------
  layoutMatrix(
    'Library folders tab',
    () => const ParthiPlayMainScreen(),
    interact: (tester) => tapVisible(tester, find.text('Folders')),
  );
  layoutMatrix(
    'Library streaming tab',
    () => const ParthiPlayMainScreen(),
    interact: (tester) => tapVisible(tester, find.text('Streaming')),
  );
  layoutMatrix(
    'Library play-URL dialog',
    () => const ParthiPlayMainScreen(),
    interact: (tester) async {
      await tapVisible(tester, find.byIcon(Icons.more_vert));
      await tapVisible(tester, find.text('Play URL'));
    },
  );
  layoutMatrix(
    'Library sort sheet',
    () => const ParthiPlayMainScreen(),
    interact: (tester) async {
      await tapVisible(tester, find.byIcon(Icons.more_vert));
      await tapVisible(tester, find.text('Sort'));
    },
  );

  // --- Vault --------------------------------------------------------------
  layoutMatrix(
    'Vault with videos',
    () => const VaultScreen(),
    prepare: _unlockVaultWithVideos,
  );
  layoutMatrix(
    'Vault auto-lock dialog',
    () => const VaultScreen(),
    prepare: _unlockVaultWithVideos,
    interact: (tester) async {
      await tapVisible(tester, find.byIcon(Icons.more_vert));
      await tapVisible(tester, find.text('Auto-lock'));
    },
  );
  layoutMatrix(
    'Vault format dialog',
    () => const VaultAuthScreen(),
    interact: (tester) =>
        tapVisible(tester, find.text('Format Vault & Clear All Data')),
  );

  // --- Sheets and list items ----------------------------------------------
  layoutMatrix('Equalizer sheet', () => _sheetHost(const EqualizerWidget()));
  layoutMatrix(
    'Subtitle sheet',
    () => _sheetHost(
      const SubtitleSelectionWidget(
        videoPath: '/storage/emulated/0/Movies/A long movie title.mkv',
      ),
    ),
  );
  layoutMatrix(
    'Video list item',
    () => Scaffold(
      body: ListView(
        children: [
          for (final name in [_longListName, 'Short.mp4'])
            VideoFileItem(
              videoFile: VideoFile(
                path: '/storage/emulated/0/Movies/$name',
                name: name,
                size: 7340032000,
                lastModified: DateTime(2024, 3, 1),
                type: MediaType.video,
              ),
              onTap: () {},
              onMoreTap: () {},
            ),
        ],
      ),
    ),
  );
}
