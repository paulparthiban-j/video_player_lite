import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/services/performance_service.dart';
import 'package:next_gen_video_player/services/subtitle_downloader_service.dart';

void main() {
  group('subtitle file names from the server', () {
    test('cannot escape the target directory', () {
      expect(SubtitleDownloaderService.safeFileName('../../x.srt'), 'x.srt');
      expect(SubtitleDownloaderService.safeFileName(r'..\..\x.srt'), 'x.srt');
      expect(SubtitleDownloaderService.safeFileName('/etc/passwd'), 'passwd');
      expect(SubtitleDownloaderService.safeFileName('..'), 'subtitle.srt');
      expect(SubtitleDownloaderService.safeFileName(''), 'subtitle.srt');
      expect(
        SubtitleDownloaderService.safeFileName('a\u0000b?.srt'),
        'a_b_.srt',
      );
    });

    test('keeps ordinary names', () {
      expect(
        SubtitleDownloaderService.safeFileName('Movie (2020).en.srt'),
        'Movie (2020).en.srt',
      );
    });
  });

  group('low-end MediaTek detection', () {
    test('flags entry-level MediaTek chips', () {
      expect(PerformanceService.isLowEndMediaTek('mt6765'), isTrue);
      expect(PerformanceService.isLowEndMediaTek('MT6762'), isTrue);
      expect(PerformanceService.isLowEndMediaTek('mt6580'), isTrue);
      expect(PerformanceService.isLowEndMediaTek('helio_g85'), isTrue);
    });

    test('leaves Snapdragon, Exynos and Dimensity at full quality', () {
      expect(PerformanceService.isLowEndMediaTek('qcom'), isFalse);
      expect(PerformanceService.isLowEndMediaTek('exynos2100'), isFalse);
      expect(PerformanceService.isLowEndMediaTek('mt6983'), isFalse);
      expect(PerformanceService.isLowEndMediaTek('mt6895'), isFalse);
      expect(PerformanceService.isLowEndMediaTek('smt1000'), isFalse);
    });
  });
}
