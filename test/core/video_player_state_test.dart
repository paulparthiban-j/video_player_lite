import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/core/video_player_controller.dart';

void main() {
  group('VideoPlayerState.copyWith', () {
    const loaded = VideoPlayerState(
      hasError: true,
      errorMessage: 'Playback error',
      videoPath: '/videos/a.mp4',
      resolvingMessage: 'Loading YouTube stream...',
      subtitlePath: '/videos/a.srt',
      youtubeVideoId: 'abc123',
    );

    test('keeps nullable fields that are not passed', () {
      final next = loaded.copyWith(isPlaying: true);
      expect(next.isPlaying, isTrue);
      expect(next.errorMessage, 'Playback error');
      expect(next.videoPath, '/videos/a.mp4');
      expect(next.subtitlePath, '/videos/a.srt');
    });

    test('clears nullable fields when null is passed explicitly', () {
      final next = loaded.copyWith(
        hasError: false,
        errorMessage: null,
        resolvingMessage: null,
        subtitlePath: null,
        youtubeVideoId: null,
      );
      expect(next.hasError, isFalse);
      expect(next.errorMessage, isNull);
      expect(next.resolvingMessage, isNull);
      expect(next.subtitlePath, isNull);
      expect(next.youtubeVideoId, isNull);
    });

    test('switching from a file to a URL drops the stale file path', () {
      final next = loaded.copyWith(
        videoPath: null,
        videoUrl: 'https://example.com/stream.m3u8',
      );
      expect(next.videoPath, isNull);
      expect(next.videoUrl, 'https://example.com/stream.m3u8');
    });
  });

  group('AudioTrackInfo.displayName', () {
    test('prefers the explicit title', () {
      const info = AudioTrackInfo(id: 1, title: 'Director', language: 'en');
      expect(info.displayName, 'Director');
    });

    test('falls back to codec and language', () {
      const info = AudioTrackInfo(
        id: 1,
        title: '',
        language: 'en',
        codec: 'aac',
      );
      expect(info.displayName, 'AAC • EN');
    });

    test('falls back to the track number', () {
      const info = AudioTrackInfo(id: 3, title: '', language: 'Unknown');
      expect(info.displayName, 'Track 3');
    });
  });
}
