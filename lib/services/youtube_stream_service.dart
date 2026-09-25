import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeStreamException implements Exception {
  final String message;

  const YoutubeStreamException(this.message);

  @override
  String toString() => message;
}

class YoutubeStreamQuality {
  final String label;
  final String url;
  final String? audioUrl;
  final int height;
  final int bitrateKbps;
  final int fps;

  const YoutubeStreamQuality({
    required this.label,
    required this.url,
    this.audioUrl,
    required this.height,
    required this.bitrateKbps,
    required this.fps,
  });
}

class YoutubeStreamResult {
  final String url;
  final List<YoutubeStreamQuality> qualities;
  final YoutubeStreamQuality? selected;
  final bool isLive;
  final String? videoId;

  const YoutubeStreamResult({
    required this.url,
    required this.qualities,
    required this.selected,
    required this.isLive,
    this.videoId,
  });
}

class YoutubeStreamService {
  static final RegExp _youtubePattern = RegExp(
    r'(https?://)?(www\.)?(m\.)?(youtube\.com|youtu\.be)/',
    caseSensitive: false,
  );
  static const String _qualityPrefPrefix = 'yt_quality_';

  static bool isYoutubeUrl(String url) => _youtubePattern.hasMatch(url);

  static Future<YoutubeStreamResult> resolvePlayableUrlWithQualities(
    String url, {
    int? preferredHeight,
  }) async {
    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(url);

      if (video.isLive) {
        final liveUrl = await yt.videos.streamsClient.getHttpLiveStreamUrl(
          video.id,
        );
        if (liveUrl.isEmpty) {
          throw const YoutubeStreamException('Live stream is unavailable');
        }
        return YoutubeStreamResult(
          url: liveUrl,
          qualities: const [],
          selected: null,
          isLive: true,
          videoId: video.id.value,
        );
      }

      final storedHeight =
          preferredHeight ?? await getPreferredHeight(video.id.value);

      final manifest = await yt.videos.streamsClient.getManifest(video.id);
      final muxed = manifest.muxed;
      final videoOnly = manifest.videoOnly;
      final audioOnly = manifest.audioOnly;

      if (muxed.isNotEmpty || videoOnly.isNotEmpty) {
        final qualities = <YoutubeStreamQuality>[];

        final bestAudio = audioOnly.isNotEmpty
            ? audioOnly.reduce(
                (a, b) =>
                    a.bitrate.kiloBitsPerSecond > b.bitrate.kiloBitsPerSecond
                    ? a
                    : b,
              )
            : null;

        final videoOnlyMap = <int, VideoOnlyStreamInfo>{};
        for (final stream in videoOnly) {
          final height = _qualityHeight(stream.videoQuality);
          final current = videoOnlyMap[height];
          if (current == null) {
            videoOnlyMap[height] = stream;
            continue;
          }
          final curFps = current.framerate.framesPerSecond;
          final nextFps = stream.framerate.framesPerSecond;
          if (nextFps > curFps ||
              (nextFps == curFps &&
                  stream.bitrate.kiloBitsPerSecond >
                      current.bitrate.kiloBitsPerSecond)) {
            videoOnlyMap[height] = stream;
          }
        }

        final muxedMap = <int, MuxedStreamInfo>{};
        for (final stream in muxed) {
          final height = _qualityHeight(stream.videoQuality);
          final current = muxedMap[height];
          if (current == null ||
              stream.bitrate.kiloBitsPerSecond >
                  current.bitrate.kiloBitsPerSecond) {
            muxedMap[height] = stream;
          }
        }

        if (bestAudio != null) {
          for (final entry in videoOnlyMap.entries) {
            final stream = entry.value;
            final height = entry.key;
            final fps = stream.framerate.framesPerSecond.toDouble();
            final label = fps >= 50
                ? '${height}p ${fps.round()}fps'
                : '${height}p';
            qualities.add(
              YoutubeStreamQuality(
                label: label,
                url: stream.url.toString(),
                audioUrl: bestAudio.url.toString(),
                height: height,
                bitrateKbps: stream.bitrate.kiloBitsPerSecond.toInt(),
                fps: fps.round(),
              ),
            );
          }
        }

        for (final entry in muxedMap.entries) {
          if (videoOnlyMap.containsKey(entry.key)) continue;
          final stream = entry.value;
          final height = entry.key;
          final fps = stream.framerate.framesPerSecond.toDouble();
          final label = fps >= 50
              ? '${height}p ${fps.round()}fps'
              : '${height}p';
          qualities.add(
            YoutubeStreamQuality(
              label: label,
              url: stream.url.toString(),
              height: height,
              bitrateKbps: stream.bitrate.kiloBitsPerSecond.toInt(),
              fps: fps.round(),
            ),
          );
        }

        qualities.sort((a, b) {
          final heightCompare = a.height.compareTo(b.height);
          if (heightCompare != 0) return heightCompare;
          return a.bitrateKbps.compareTo(b.bitrateKbps);
        });

        YoutubeStreamQuality selected;
        if (storedHeight != null) {
          final candidates = qualities
              .where((q) => q.height <= storedHeight)
              .toList();
          selected = candidates.isNotEmpty ? candidates.last : qualities.last;
        } else {
          selected = qualities.last;
        }

        return YoutubeStreamResult(
          url: selected.url,
          qualities: qualities,
          selected: selected,
          isLive: false,
          videoId: video.id.value,
        );
      }

      throw const YoutubeStreamException('No compatible YouTube stream found');
    } catch (e) {
      if (e is YoutubeStreamException) rethrow;
      throw const YoutubeStreamException(
        'This YouTube video cannot be streamed in-app. It may be restricted or blocked for third-party playback.',
      );
    } finally {
      yt.close();
    }
  }

  static Future<String> resolvePlayableUrl(String url) async {
    final result = await resolvePlayableUrlWithQualities(url);
    return result.url;
  }

  static Future<YoutubeStreamResult?> resolveIfNeededWithQualities(
    String url, {
    int? preferredHeight,
  }) async {
    if (!isYoutubeUrl(url)) return null;
    return resolvePlayableUrlWithQualities(
      url,
      preferredHeight: preferredHeight,
    );
  }

  static Future<String> resolveIfNeeded(String url) async {
    if (!isYoutubeUrl(url)) return url;
    return resolvePlayableUrl(url);
  }

  static Future<int?> getPreferredHeight(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_qualityPrefPrefix$videoId');
  }

  static Future<void> setPreferredHeight(String videoId, int height) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_qualityPrefPrefix$videoId', height);
  }

  static int _qualityHeight(VideoQuality quality) {
    final digits = quality.qualityString.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }
}
