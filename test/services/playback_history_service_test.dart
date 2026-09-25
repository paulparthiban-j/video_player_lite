import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/services/playback_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const vaultFile =
      '/data/user/0/com.parthi.play/app_flutter/main_vault/1_ab.mp4';
  const decoyFile =
      '/data/user/0/com.parthi.play/app_flutter/fake_vault/2_cd.mp4';
  const normalFile = '/storage/emulated/0/Movies/holiday.mp4';

  test('vault files are never recorded', () async {
    for (final path in [vaultFile, decoyFile]) {
      await PlaybackHistoryService.saveLastPlayedVideo(path);
      await PlaybackHistoryService.savePosition(
        path,
        const Duration(minutes: 3),
      );
      expect(await PlaybackHistoryService.getPosition(path), Duration.zero);
    }
    expect(await PlaybackHistoryService.getLastPlayedVideo(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('regular files keep resume positions', () async {
    await PlaybackHistoryService.saveLastPlayedVideo(normalFile);
    await PlaybackHistoryService.savePosition(
      normalFile,
      const Duration(minutes: 3),
    );
    expect(
      await PlaybackHistoryService.getPosition(normalFile),
      const Duration(minutes: 3),
    );
    expect(await PlaybackHistoryService.getLastPlayedVideo(), normalFile);
  });

  test('private path detection', () {
    expect(PlaybackHistoryService.isPrivatePath(vaultFile), isTrue);
    expect(PlaybackHistoryService.isPrivatePath(decoyFile), isTrue);
    expect(PlaybackHistoryService.isPrivatePath(normalFile), isFalse);
    expect(
      PlaybackHistoryService.isPrivatePath(r'C:\app\main_vault\x.mp4'),
      isTrue,
    );
  });
}
