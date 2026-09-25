import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:floating/floating.dart';

import '../widgets/subtitle_display_widget.dart';
import '../services/system_controls_service.dart';
import '../services/file_browser_service.dart';
import '../services/video_format_service.dart';
import '../services/performance_service.dart';
import '../services/playback_history_service.dart';
import '../services/youtube_stream_service.dart';

enum MediaType { video, audio, streaming, image }

class AudioTrackInfo {
  final int id;
  final String title;
  final String language;
  final String? codec;
  final int? channels;
  final int? bitrate;

  const AudioTrackInfo({
    required this.id,
    required this.title,
    required this.language,
    this.codec,
    this.channels,
    this.bitrate,
  });

  String get displayName {
    if (title.isNotEmpty) return title;

    // Build descriptive name with codec and language
    final parts = <String>[];
    if (codec != null && codec!.isNotEmpty) {
      parts.add(codec!.toUpperCase());
    }
    if (language.isNotEmpty && language != 'Unknown') {
      parts.add(language.toUpperCase());
    }
    if (parts.isNotEmpty) {
      return parts.join(' • ');
    }

    // Fallback to track number with language if available
    if (language.isNotEmpty && language != 'Unknown') {
      return 'Track $id ($language)';
    }
    return 'Track $id';
  }
}

enum PlayerOrientation { auto, landscape, portrait }

enum AspectRatioMode {
  auto('Auto'),
  fit('Fit'),
  fill('Fill'),
  sixteenNine('16:9'),
  fourThree('4:3'),
  twentyOneNine('21:9'),
  oneOne('1:1'),
  stretch('Stretch');

  final String label;
  const AspectRatioMode(this.label);
}

/// Marker for "argument not passed" so [VideoPlayerState.copyWith] can tell
/// an omitted nullable field apart from an explicit `null` that clears it.
const Object _unset = Object();

// Video player state model
class VideoPlayerState {
  final Player? player;
  final VideoController? videoController;
  final bool isInitialized;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final Duration bufferDuration;
  final double volume;
  final bool isLocked;
  final String? subtitlePath;
  final List<SubtitleEntry> subtitles;
  final bool showControls;
  final bool isFullscreen;
  final int audioTrackIndex;
  final bool hasError;
  final String? errorMessage;
  final double playbackSpeed;
  final AspectRatioMode aspectRatioMode;
  final double aspectRatio;
  final String? videoPath;
  final String? videoUrl;
  final bool isLoaded;
  final PlayerOrientation orientation;
  final bool isInPip;
  final bool useHwDec;
  final double audioDelay; // In milliseconds
  final double volumeBoost; // 1.0 is normal, 2.0 is double
  final MediaType type;
  final List<VideoFile> currentFolderVideos;
  final String? currentFolderName;
  final List<double> equalizerBands;
  final bool isEqualizerEnabled;
  final List<AudioTrackInfo> audioTracks;
  final bool isSwitchingDecoder;
  final bool isResolvingStream;
  final String? resolvingMessage;
  final double resolvingProgress;
  final List<YoutubeStreamQuality> youtubeQualities;
  final YoutubeStreamQuality? selectedYoutubeQuality;
  final String? youtubeVideoId;

  const VideoPlayerState({
    this.player,
    this.videoController,
    this.isInitialized = false,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferDuration = Duration.zero,
    this.volume = 100.0,
    this.isLocked = false,
    this.subtitlePath,
    this.subtitles = const [],
    this.showControls = true,
    this.isFullscreen = false,
    this.audioTrackIndex = -1,
    this.hasError = false,
    this.errorMessage,
    this.playbackSpeed = 1.0,
    this.aspectRatioMode = AspectRatioMode.fit,
    this.aspectRatio = 1.777,
    this.videoPath,
    this.videoUrl,
    this.isLoaded = false,
    this.orientation = PlayerOrientation.auto,
    this.isInPip = false,
    this.useHwDec = true,
    this.audioDelay = 0.0,
    this.volumeBoost = 1.0,
    this.type = MediaType.video,
    this.currentFolderVideos = const [],
    this.currentFolderName,
    this.equalizerBands = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    this.isEqualizerEnabled = false,
    this.audioTracks = const [],
    this.isSwitchingDecoder = false,
    this.isResolvingStream = false,
    this.resolvingMessage,
    this.resolvingProgress = 0.0,
    this.youtubeQualities = const [],
    this.selectedYoutubeQuality,
    this.youtubeVideoId,
  });

  VideoPlayerState copyWith({
    Object? player = _unset,
    Object? videoController = _unset,
    bool? isInitialized,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    Duration? bufferDuration,
    double? volume,
    bool? isLocked,
    Object? subtitlePath = _unset,
    List<SubtitleEntry>? subtitles,
    bool? showControls,
    bool? isFullscreen,
    int? audioTrackIndex,
    bool? hasError,
    Object? errorMessage = _unset,
    double? playbackSpeed,
    double? aspectRatio,
    AspectRatioMode? aspectRatioMode,
    Object? videoPath = _unset,
    Object? videoUrl = _unset,
    bool? isLoaded,
    PlayerOrientation? orientation,
    bool? isInPip,
    bool? useHwDec,
    double? audioDelay,
    double? volumeBoost,
    MediaType? type,
    List<VideoFile>? currentFolderVideos,
    Object? currentFolderName = _unset,
    List<double>? equalizerBands,
    bool? isEqualizerEnabled,
    List<AudioTrackInfo>? audioTracks,
    bool? isSwitchingDecoder,
    bool? isResolvingStream,
    Object? resolvingMessage = _unset,
    double? resolvingProgress,
    List<YoutubeStreamQuality>? youtubeQualities,
    Object? selectedYoutubeQuality = _unset,
    Object? youtubeVideoId = _unset,
  }) {
    return VideoPlayerState(
      player: identical(player, _unset) ? this.player : player as Player?,
      videoController: identical(videoController, _unset)
          ? this.videoController
          : videoController as VideoController?,
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferDuration: bufferDuration ?? this.bufferDuration,
      volume: volume ?? this.volume,
      isLocked: isLocked ?? this.isLocked,
      subtitlePath: identical(subtitlePath, _unset)
          ? this.subtitlePath
          : subtitlePath as String?,
      subtitles: subtitles ?? this.subtitles,
      showControls: showControls ?? this.showControls,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      audioTrackIndex: audioTrackIndex ?? this.audioTrackIndex,
      hasError: hasError ?? this.hasError,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      aspectRatioMode: aspectRatioMode ?? this.aspectRatioMode,
      videoPath: identical(videoPath, _unset)
          ? this.videoPath
          : videoPath as String?,
      videoUrl: identical(videoUrl, _unset)
          ? this.videoUrl
          : videoUrl as String?,
      isLoaded: isLoaded ?? this.isLoaded,
      orientation: orientation ?? this.orientation,
      isInPip: isInPip ?? this.isInPip,
      useHwDec: useHwDec ?? this.useHwDec,
      audioDelay: audioDelay ?? this.audioDelay,
      volumeBoost: volumeBoost ?? this.volumeBoost,
      type: type ?? this.type,
      currentFolderVideos: currentFolderVideos ?? this.currentFolderVideos,
      currentFolderName: identical(currentFolderName, _unset)
          ? this.currentFolderName
          : currentFolderName as String?,
      equalizerBands: equalizerBands ?? this.equalizerBands,
      isEqualizerEnabled: isEqualizerEnabled ?? this.isEqualizerEnabled,
      audioTracks: audioTracks ?? this.audioTracks,
      isSwitchingDecoder: isSwitchingDecoder ?? this.isSwitchingDecoder,
      isResolvingStream: isResolvingStream ?? this.isResolvingStream,
      resolvingMessage: identical(resolvingMessage, _unset)
          ? this.resolvingMessage
          : resolvingMessage as String?,
      resolvingProgress: resolvingProgress ?? this.resolvingProgress,
      youtubeQualities: youtubeQualities ?? this.youtubeQualities,
      selectedYoutubeQuality: identical(selectedYoutubeQuality, _unset)
          ? this.selectedYoutubeQuality
          : selectedYoutubeQuality as YoutubeStreamQuality?,
      youtubeVideoId: identical(youtubeVideoId, _unset)
          ? this.youtubeVideoId
          : youtubeVideoId as String?,
    );
  }
}

class VideoPlayerControllerNotifier extends StateNotifier<VideoPlayerState> {
  final Floating _floating = Floating();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _positionThrottleTimer;
  Timer? _audioTrackPoller;
  Timer? _statePoller;
  Timer? _resolveProgressTimer;
  Duration? _pendingPosition;
  DateTime? _lastPositionUpdateTime;
  static const int _uiUpdateIntervalMs = 150;
  bool _isInitializing = false;
  String? _inFlightSourceKey;
  int _loadGeneration = 0;
  Player? _loadingPlayer;
  String? _lastSourceKey;
  int _initRetryCount = 0;

  VideoPlayerControllerNotifier() : super(const VideoPlayerState());

  Player? get _currentPlayerOrNull => mounted ? state.player : null;

  /// Tears down the active (and any half-loaded) player.
  ///
  /// Everything that touches [state] happens synchronously before the first
  /// `await`, so this is safe to call from [dispose].
  Future<void> _disposePlayer({bool updateState = true}) async {
    final subscriptions = List.of(_subscriptions);
    _subscriptions.clear();
    _positionThrottleTimer?.cancel();
    _positionThrottleTimer = null;
    _pendingPosition = null;
    _lastPositionUpdateTime = null;
    _audioTrackPoller?.cancel();
    _audioTrackPoller = null;
    _statePoller?.cancel();
    _statePoller = null;
    _resolveProgressTimer?.cancel();
    _resolveProgressTimer = null;

    final player = _currentPlayerOrNull;
    final loading = _loadingPlayer;
    _loadingPlayer = null;
    if (updateState && mounted && player != null) {
      state = state.copyWith(player: null, videoController: null);
    }

    for (final s in subscriptions) {
      await s.cancel();
    }
    if (player != null) await player.dispose();
    if (loading != null && !identical(loading, player)) {
      await loading.dispose();
    }

    unawaited(SystemControlsService.abandonAudioFocus());

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> reset() async {
    await _disposePlayer();
    state = const VideoPlayerState();
  }

  void applyDynamicPerformance({
    required bool frameDrop,
    required bool skipLoopFilter,
  }) {
    PerformanceService.setDynamicPerformance(
      frameDrop: frameDrop,
      skipLoopFilter: skipLoopFilter,
    );

    if (state.player?.platform is NativePlayer) {
      final nativePlayer = state.player!.platform as NativePlayer;
      nativePlayer.setProperty('framedrop', frameDrop ? 'vo' : 'no');
      unawaited(
        nativePlayer.setProperty(
          'vd-lavc-skiploopfilter',
          skipLoopFilter ? 'all' : 'no',
        ),
      );
    }
  }

  void applyHdrToneMapping(bool enable) {
    if (state.player?.platform is! NativePlayer) return;
    final nativePlayer = state.player!.platform as NativePlayer;
    if (enable) {
      nativePlayer.setProperty('tone-mapping', 'mobius');
      nativePlayer.setProperty('hdr-compute-peak', 'yes');
      nativePlayer.setProperty('target-trc', 'bt.1886');
      nativePlayer.setProperty('target-prim', 'bt.709');
    } else {
      nativePlayer.setProperty('tone-mapping', 'no');
      nativePlayer.setProperty('hdr-compute-peak', 'no');
      nativePlayer.setProperty('target-trc', 'auto');
      nativePlayer.setProperty('target-prim', 'auto');
    }
  }

  void _startResolveProgress() {
    _resolveProgressTimer?.cancel();
    state = state.copyWith(resolvingProgress: 0.01);
    _resolveProgressTimer = Timer.periodic(const Duration(milliseconds: 180), (
      _,
    ) {
      final next = (state.resolvingProgress + 0.03).clamp(0.01, 0.95);
      if (next == state.resolvingProgress) return;
      state = state.copyWith(resolvingProgress: next);
    });
  }

  void _stopResolveProgress({bool complete = false}) {
    _resolveProgressTimer?.cancel();
    _resolveProgressTimer = null;
    if (complete) {
      state = state.copyWith(resolvingProgress: 1.0);
    }
  }

  Future<void> initializeVideo(
    String? videoUrl,
    String? videoPath, {
    bool autoPlay = false,
    Duration? startPosition,
  }) async {
    final sourceKey = (videoUrl != null && videoUrl.isNotEmpty)
        ? 'url:$videoUrl'
        : 'path:$videoPath';
    // A duplicate request for the source already loading is a no-op; any
    // other request supersedes the in-flight load.
    if (_isInitializing && _inFlightSourceKey == sourceKey) return;
    final generation = ++_loadGeneration;
    bool isStale() => generation != _loadGeneration || !mounted;

    _isInitializing = true;
    _inFlightSourceKey = sourceKey;
    if (_lastSourceKey != sourceKey) {
      _lastSourceKey = sourceKey;
      _initRetryCount = 0;
    }
    // Remember the quality chosen for the previous stream before the state
    // for the new source is reset below.
    final previousYoutubeHeight = state.selectedYoutubeQuality?.height;
    Player? player;
    try {
      await _disposePlayer();
      if (isStale()) return;

      state = state.copyWith(
        isInitialized: false,
        errorMessage: null,
        videoPath: videoPath,
        videoUrl: videoUrl,
        isLoaded: false,
        hasError: false,
        type: videoPath != null
            ? (VideoFormatService.getFormatByPath(videoPath)?.type ??
                  MediaType.video)
            : MediaType.video,
      );

      if (videoUrl == null ||
          videoUrl.isEmpty ||
          !YoutubeStreamService.isYoutubeUrl(videoUrl)) {
        state = state.copyWith(
          youtubeQualities: const [],
          selectedYoutubeQuality: null,
          isResolvingStream: false,
          resolvingMessage: null,
          resolvingProgress: 0.0,
          youtubeVideoId: null,
        );
        _stopResolveProgress();
      }

      if (videoPath != null) {
        unawaited(PlaybackHistoryService.saveLastPlayedVideo(videoPath));
      }

      player = Player();
      _loadingPlayer = player;

      try {
        if (player.platform is NativePlayer) {
          final nativePlayer = player.platform as NativePlayer;

          Map<String, String> flags;

          // Select Optimization Profile
          if (state.useHwDec) {
            flags = PerformanceService.getHardwareDecoderFlags();
          } else {
            // FORCE SOFTWARE OPTIMIZATIONS
            flags = PerformanceService.getSoftwareDecoderFlags();
          }

          // Apply all flags
          flags.forEach((key, value) {
            nativePlayer.setProperty(key, value);
          });

          // Common Optimizations

          if (PerformanceService.shouldEnableInterpolation()) {
            unawaited(nativePlayer.setProperty('interpolation', 'yes'));
            unawaited(nativePlayer.setProperty('tscale', 'oversample'));
          } else {
            unawaited(nativePlayer.setProperty('interpolation', 'no'));
            // Use bilinear scaling which is faster
            unawaited(nativePlayer.setProperty('tscale', 'bilinear'));
          }

          unawaited(nativePlayer.setProperty('cache', 'yes'));
          unawaited(
            nativePlayer.setProperty(
              'demuxer-max-bytes',
              PerformanceService.getOptimalDemuxerCache(),
            ),
          );
          unawaited(nativePlayer.setProperty('demuxer-max-back-bytes', '16M'));

          applyHdrToneMapping(PerformanceService.isHdrToneMappingEnabled);
        }
      } catch (e) {
        debugPrint('Hardware decoding setup error: $e');
      }

      final videoController = VideoController(player);

      _subscriptions.add(
        player.stream.position.listen((p) {
          final now = DateTime.now();
          final lastUpdate = _lastPositionUpdateTime;
          final elapsedMs = lastUpdate == null
              ? 9999
              : now.difference(lastUpdate).inMilliseconds;

          _pendingPosition = p;

          if (elapsedMs >= _uiUpdateIntervalMs) {
            _lastPositionUpdateTime = now;
            if (_pendingPosition != null &&
                _pendingPosition != state.position) {
              state = state.copyWith(position: _pendingPosition!);
            }
            _pendingPosition = null;
          } else {
            _positionThrottleTimer?.cancel();
            _positionThrottleTimer = Timer(
              Duration(milliseconds: _uiUpdateIntervalMs - elapsedMs),
              () {
                if (_pendingPosition == null) return;
                _lastPositionUpdateTime = DateTime.now();
                if (_pendingPosition != state.position) {
                  state = state.copyWith(position: _pendingPosition!);
                }
                _pendingPosition = null;
              },
            );
          }

          // Save position on pause/stop only (avoid playback stutter)
        }),
      );

      Duration? lastDuration;
      DateTime? lastDurationUpdateTime;
      _subscriptions.add(
        player.stream.duration.listen((d) {
          if (d != lastDuration) {
            lastDuration = d;
            final now = DateTime.now();
            if (lastDurationUpdateTime == null ||
                now.difference(lastDurationUpdateTime!).inMilliseconds > 500) {
              lastDurationUpdateTime = now;
              state = state.copyWith(duration: d);
            }
          }
        }),
      );

      DateTime? lastBufferUpdateTime;
      _subscriptions.add(
        player.stream.buffer.listen((b) {
          final now = DateTime.now();
          if (lastBufferUpdateTime == null ||
              now.difference(lastBufferUpdateTime!).inMilliseconds > 500) {
            lastBufferUpdateTime = now;
            state = state.copyWith(bufferDuration: b);
          }
        }),
      );

      _subscriptions.add(
        player.stream.completed.listen((completed) {
          if (completed && state.videoPath != null) {
            PlaybackHistoryService.clearPosition(state.videoPath!);
          }
        }),
      );

      _subscriptions.add(
        player.stream.playing.listen((isPlaying) {
          state = state.copyWith(isPlaying: isPlaying);
          if (!isPlaying && state.videoPath != null) {
            PlaybackHistoryService.savePosition(
              state.videoPath!,
              state.position,
            );
          }
        }),
      );

      double? lastVolume;
      _subscriptions.add(
        player.stream.volume.listen((v) {
          if ((lastVolume == null || (v - lastVolume!).abs() > 1.0)) {
            lastVolume = v;
            state = state.copyWith(volume: v);
          }
        }),
      );

      _subscriptions.add(
        player.stream.error.listen((e) {
          debugPrint('Player Error: $e');
          // Auto-fallback to Software Decoding if HW decoding fails
          if (state.useHwDec && !state.hasError) {
            debugPrint(
              'Hardware decoding failed, switching to Software decoding...',
            );
            final resumeAt = state.position;
            final resume = state.isPlaying;
            // Disable HW decoding and reload the same source.
            state = state.copyWith(useHwDec: false);
            _isInitializing = false;
            _inFlightSourceKey = null;
            unawaited(
              initializeVideo(
                state.videoUrl,
                state.videoPath,
                autoPlay: resume,
                startPosition: resumeAt > Duration.zero ? resumeAt : null,
              ),
            );
            return;
          }

          state = state.copyWith(
            hasError: true,
            errorMessage: 'Playback error: $e. Try switching to SW decoder.',
            isPlaying: false,
          );
        }),
      );

      Media? media;
      if (videoUrl != null && videoUrl.isNotEmpty) {
        if (YoutubeStreamService.isYoutubeUrl(videoUrl)) {
          state = state.copyWith(
            isResolvingStream: true,
            resolvingMessage: 'Loading YouTube stream...',
            resolvingProgress: 0.01,
            youtubeQualities: const [],
            selectedYoutubeQuality: null,
          );
          _startResolveProgress();

          final preferredHeight = previousYoutubeHeight;
          final result =
              await YoutubeStreamService.resolvePlayableUrlWithQualities(
                videoUrl,
                preferredHeight: preferredHeight,
              ).timeout(
                const Duration(seconds: 20),
                onTimeout: () {
                  throw const YoutubeStreamException(
                    'YouTube loading timed out. Please try again.',
                  );
                },
              );
          if (isStale()) return;

          state = state.copyWith(
            isResolvingStream: false,
            resolvingMessage: null,
            resolvingProgress: 1.0,
            youtubeQualities: result.qualities,
            selectedYoutubeQuality: result.selected,
            youtubeVideoId: result.videoId,
          );
          _stopResolveProgress(complete: true);

          media = Media(result.url);
        } else {
          final resolvedUrl = await YoutubeStreamService.resolveIfNeeded(
            videoUrl,
          );
          if (isStale()) return;
          media = Media(resolvedUrl);
        }
      } else if (videoPath != null && videoPath.isNotEmpty) {
        media = Media(videoPath);
      }

      if (media == null) throw Exception('No valid media source');

      await player
          .open(media, play: false)
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () {
              throw Exception('Connection timed out. Please try again.');
            },
          );
      if (isStale()) return;

      if (state.selectedYoutubeQuality?.audioUrl != null) {
        await player.setAudioTrack(
          AudioTrack.uri(state.selectedYoutubeQuality!.audioUrl!),
        );
      } else {
        await player.setAudioTrack(AudioTrack.auto());
      }

      if (isStale()) return;

      _loadingPlayer = null;
      state = state.copyWith(
        player: player,
        videoController: videoController,
        isInitialized: true,
        isLoaded: true,
        isSwitchingDecoder: false,
      );

      _startStatePolling(player);
      _startAudioTrackPolling(player);

      if (startPosition != null) {
        await player.seek(startPosition);
      }

      if (autoPlay) {
        await player.play();
      }
    } on YoutubeStreamException catch (e) {
      if (isStale()) return;
      debugPrint('YouTube stream error: $e');
      await _disposePlayer();
      state = state.copyWith(
        isInitialized: false,
        hasError: true,
        errorMessage: e.message,
        isSwitchingDecoder: false,
        isResolvingStream: false,
        resolvingMessage: null,
        resolvingProgress: 0.0,
      );
      _stopResolveProgress();
    } catch (e, stackTrace) {
      if (isStale()) return;
      if (e.toString().contains('Connection timed out') &&
          _initRetryCount < 1) {
        _initRetryCount += 1;
        _isInitializing = false;
        await initializeVideo(
          videoUrl,
          videoPath,
          autoPlay: autoPlay,
          startPosition: startPosition,
        );
        return;
      }
      debugPrint('Error initializing video: $e');
      debugPrint('Stack trace: $stackTrace');
      await _disposePlayer();
      state = state.copyWith(
        isInitialized: false,
        hasError: true,
        errorMessage: 'Failed to load video: ${e.toString()}',
        isSwitchingDecoder: false,
        isResolvingStream: false,
        resolvingMessage: null,
        resolvingProgress: 0.0,
      );
      _stopResolveProgress();
    } finally {
      // A player that never made it into state (superseded or failed) would
      // otherwise keep its native decoder and surfaces alive.
      if (player != null &&
          identical(_loadingPlayer, player) &&
          !identical(player, _currentPlayerOrNull)) {
        _loadingPlayer = null;
        unawaited(player.dispose());
      }
      if (generation == _loadGeneration) {
        _isInitializing = false;
        _inFlightSourceKey = null;
      }
    }
  }

  void _startStatePolling(Player player) {
    _statePoller?.cancel();
    _statePoller = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final current = player.state;
      final wasPlaying = state.isPlaying;
      if (current.position != state.position) {
        state = state.copyWith(position: current.position);
      }
      if (current.duration != state.duration) {
        state = state.copyWith(duration: current.duration);
      }
      if (current.playing != wasPlaying) {
        if (current.playing) {
          SystemControlsService.requestAudioFocus();
        } else {
          SystemControlsService.abandonAudioFocus();
        }
        state = state.copyWith(isPlaying: current.playing);
      }
    });
  }

  Future<void> play() async => await state.player?.play();
  Future<void> pause() async => await state.player?.pause();
  Future<void> togglePlayPause() async => await state.player?.playOrPause();

  Future<void> setYoutubeQuality(YoutubeStreamQuality quality) async {
    final player = state.player;
    if (player == null) return;
    if (state.videoUrl == null ||
        !YoutubeStreamService.isYoutubeUrl(state.videoUrl!)) {
      return;
    }

    final wasPlaying = state.isPlaying;
    final position = state.position;
    state = state.copyWith(
      isResolvingStream: true,
      resolvingMessage: 'Switching quality...',
      resolvingProgress: 0.01,
      selectedYoutubeQuality: quality,
    );
    _startResolveProgress();

    try {
      if (state.youtubeVideoId != null) {
        await YoutubeStreamService.setPreferredHeight(
          state.youtubeVideoId!,
          quality.height,
        );
      }
      await player
          .open(Media(quality.url), play: false)
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () {
              throw Exception('Connection timed out. Please try again.');
            },
          );

      if (quality.audioUrl != null) {
        await player.setAudioTrack(AudioTrack.uri(quality.audioUrl!));
      } else {
        await player.setAudioTrack(AudioTrack.auto());
      }

      if (state.duration.inMilliseconds > 0) {
        await player.seek(position);
      }
      if (wasPlaying) {
        await player.play();
      }
    } catch (e) {
      debugPrint('Error switching quality: $e');
      state = state.copyWith(
        hasError: true,
        errorMessage: 'Failed to switch quality: ${e.toString()}',
      );
    } finally {
      state = state.copyWith(
        isResolvingStream: false,
        resolvingMessage: null,
        resolvingProgress: 0.0,
      );
      _stopResolveProgress();
    }
  }

  Future<void> seekTo(Duration position) async {
    Duration safePosition = position;
    if (safePosition.isNegative) {
      safePosition = Duration.zero;
    }
    final duration = state.duration;
    if (duration.inMilliseconds > 0 && safePosition > duration) {
      safePosition = duration;
    }
    await state.player?.seek(safePosition);
  }

  void _startAudioTrackPolling(Player player) {
    _audioTrackPoller?.cancel();
    int attempts = 0;
    const maxAttempts = 20;

    void updateTracks() {
      final tracks = player.state.tracks.audio;
      if (tracks.isEmpty) return;

      final audioTracks = _buildAudioTrackInfo(tracks);
      final currentTrack = player.state.track.audio;
      int initialTrackIndex = -1;
      if (tracks.isNotEmpty) {
        try {
          final trackIndex = tracks.indexOf(currentTrack);
          initialTrackIndex = trackIndex >= 0 ? trackIndex : 0;
        } catch (_) {
          initialTrackIndex = 0;
        }
      }

      state = state.copyWith(
        audioTracks: audioTracks,
        audioTrackIndex: initialTrackIndex,
      );
    }

    _audioTrackPoller = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) {
      attempts++;
      updateTracks();
      if (state.audioTracks.isNotEmpty || attempts >= maxAttempts) {
        timer.cancel();
      }
    });

    // Initial immediate attempt.
    updateTracks();
  }

  List<AudioTrackInfo> _buildAudioTrackInfo(List<dynamic> tracks) {
    final audioTracks = <AudioTrackInfo>[];
    for (int i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      String? codecInfo = track.codec;
      final String? titleInfo = track.title;

      if (codecInfo == null || codecInfo.isEmpty) {
        if (track.channels != null) {
          final channels = track.channels.toString();
          if (channels.contains('2')) {
            codecInfo = 'STEREO';
          } else if (channels.contains('6')) {
            codecInfo = '5.1';
          } else if (channels.contains('8')) {
            codecInfo = '7.1';
          }
        }
      }

      audioTracks.add(
        AudioTrackInfo(
          id: i,
          title: titleInfo?.isNotEmpty == true
              ? titleInfo!
              : (codecInfo?.isNotEmpty == true
                    ? 'Audio $codecInfo'
                    : 'Track ${i + 1}'),
          language: track.language ?? 'Unknown',
          codec: codecInfo,
          channels: track.channels != null
              ? int.tryParse(track.channels.toString())
              : null,
        ),
      );
    }

    if (audioTracks.isEmpty) {
      audioTracks.add(
        const AudioTrackInfo(
          id: 0,
          title: 'Default Audio',
          language: 'Unknown',
          codec: null,
          channels: null,
        ),
      );
    }

    return audioTracks;
  }

  Future<void> setVolume(double volume) async {
    final v = (volume * 100).clamp(0.0, 200.0);
    await state.player?.setVolume(v);
    try {
      await SystemControlsService.setVolume(volume.clamp(0.0, 1.0));
    } catch (e) {
      // Ignore system volume sync errors
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await state.player?.setRate(speed);
    state = state.copyWith(playbackSpeed: speed);
  }

  void toggleControls() =>
      state = state.copyWith(showControls: !state.showControls);
  void setControlsVisible(bool visible) {
    if (state.showControls != visible) {
      state = state.copyWith(showControls: visible);
    }
  }

  void setInPip(bool value) {
    if (state.isInPip != value) {
      state = state.copyWith(isInPip: value);
    }
  }

  void toggleLock() => state = state.copyWith(isLocked: !state.isLocked);
  void toggleFullscreen() =>
      state = state.copyWith(isFullscreen: !state.isFullscreen);

  void setAspectRatio(AspectRatioMode mode) {
    double ratio = 16.0 / 9.0;
    switch (mode) {
      case AspectRatioMode.sixteenNine:
        ratio = 16.0 / 9.0;
        break;
      case AspectRatioMode.fourThree:
        ratio = 4.0 / 3.0;
        break;
      case AspectRatioMode.oneOne:
        ratio = 1.0;
        break;
      case AspectRatioMode.twentyOneNine:
        ratio = 21.0 / 9.0;
        break;
      case AspectRatioMode.fit:
        ratio = -1.0;
        break;
      case AspectRatioMode.fill:
        ratio = -2.0;
        break;
      case AspectRatioMode.stretch:
        ratio = -3.0;
        break;
      case AspectRatioMode.auto:
        ratio = 0.0;
        break;
    }
    state = state.copyWith(aspectRatio: ratio, aspectRatioMode: mode);
  }

  void cycleAspectRatio() {
    final modes = AspectRatioMode.values;
    setAspectRatio(
      modes[(modes.indexOf(state.aspectRatioMode) + 1) % modes.length],
    );
  }

  void setAudioDelay(double delay) {
    state = state.copyWith(audioDelay: delay);
    if (state.player?.platform is NativePlayer) {
      (state.player!.platform as NativePlayer).setProperty(
        'audio-delay',
        (delay / 1000.0).toString(),
      );
    }
  }

  void setVolumeBoost(double boost) {
    state = state.copyWith(volumeBoost: boost);
    if (state.player != null) state.player!.setVolume(state.volume * boost);
  }

  Future<void> setAudioTrack(int? index) async {
    if (state.player == null) return;

    final tracks = state.player!.state.tracks.audio;
    if (index == null) {
      state = state.copyWith(audioTrackIndex: -1);
      if (tracks.isNotEmpty) {
        await state.player!.setAudioTrack(tracks[0]);
      }
      return;
    }

    if (index >= 0 && index < tracks.length) {
      await state.player!.setAudioTrack(tracks[index]);
      state = state.copyWith(audioTrackIndex: index);
    }
  }

  void setSubtitle(String? path) => state = state.copyWith(subtitlePath: path);

  Future<void> toggleRotation() async {
    late PlayerOrientation newO;
    switch (state.orientation) {
      case PlayerOrientation.auto:
        newO = PlayerOrientation.landscape;
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
      case PlayerOrientation.landscape:
        newO = PlayerOrientation.portrait;
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        break;
      case PlayerOrientation.portrait:
        newO = PlayerOrientation.auto;
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
    }
    state = state.copyWith(orientation: newO);
  }

  Future<void> enterPIP() async {
    try {
      final pipAvailable = await _floating.isPipAvailable;
      if (pipAvailable == true) {
        if (await _floating.enable(
              ImmediatePiP(aspectRatio: const Rational.landscape()),
            ) ==
            PiPStatus.enabled) {
          state = state.copyWith(isInPip: true);
        }
      }
    } catch (e) {
      // Ignore PiP errors
    }
  }

  Future<void> takeScreenshot() async {
    if (state.player == null) return;
    try {
      await state.player!.screenshot();
    } catch (e) {
      // Ignore screenshot errors
    }
  }

  Future<void> toggleDecoder() async {
    if (state.videoPath == null && state.videoUrl == null) return;
    final currentPosition = state.position;
    final wasPlaying = state.isPlaying;
    state = state.copyWith(
      useHwDec: !state.useHwDec,
      isLoaded: false,
      isInitialized: false,
      isSwitchingDecoder: true,
    );
    try {
      await initializeVideo(state.videoUrl, state.videoPath, autoPlay: false);
    } finally {
      state = state.copyWith(isSwitchingDecoder: false);
    }
    if (currentPosition.inMilliseconds > 0) {
      await seekTo(currentPosition);
    }
    if (wasPlaying) {
      await play();
    }
  }

  void setCurrentFolder(List<VideoFile> folderVideos, String folderName) {
    state = state.copyWith(
      currentFolderVideos: folderVideos,
      currentFolderName: folderName,
    );
  }

  Future<void> playNextInFolder() async {
    if (state.currentFolderVideos.isEmpty || state.videoPath == null) return;
    final idx = state.currentFolderVideos.indexWhere(
      (v) => v.path == state.videoPath,
    );
    if (idx != -1 && idx < state.currentFolderVideos.length - 1) {
      await initializeVideo(null, state.currentFolderVideos[idx + 1].path);
    }
  }

  Future<void> playPreviousInFolder() async {
    if (state.currentFolderVideos.isEmpty || state.videoPath == null) return;
    final idx = state.currentFolderVideos.indexWhere(
      (v) => v.path == state.videoPath,
    );
    if (idx > 0) {
      await initializeVideo(null, state.currentFolderVideos[idx - 1].path);
    }
  }

  void toggleEqualizer() {
    state = state.copyWith(isEqualizerEnabled: !state.isEqualizerEnabled);
    _applyEqualizer();
  }

  void setEqualizerBand(int index, double value) {
    final bands = List<double>.from(state.equalizerBands);
    bands[index] = value;
    state = state.copyWith(equalizerBands: bands);
    if (state.isEqualizerEnabled) _applyEqualizer();
  }

  void _applyEqualizer() {
    if (state.player?.platform is NativePlayer) {
      if (!state.isEqualizerEnabled) {
        (state.player!.platform as NativePlayer).setProperty('af', '');
        return;
      }
      String filter = 'superequalizer=';
      for (int i = 0; i < state.equalizerBands.length; i++) {
        filter += '${i + 1}b=${state.equalizerBands[i].toStringAsFixed(1)}';
        if (i < state.equalizerBands.length - 1) filter += ':';
      }
      (state.player!.platform as NativePlayer).setProperty('af', filter);
    }
  }

  @override
  void dispose() {
    // Abort any in-flight load, then release native resources.
    _loadGeneration++;
    unawaited(_disposePlayer(updateState: false));
    super.dispose();
  }
}

final videoPlayerControllerProvider =
    StateNotifierProvider<VideoPlayerControllerNotifier, VideoPlayerState>(
      (ref) => VideoPlayerControllerNotifier(),
    );

final gestureStateProvider = StateProvider<GestureState>(
  (ref) => const GestureState(),
);

final videoPlayerBackCallbackProvider = StateProvider<VoidCallback?>(
  (ref) => null,
);

class GestureState {
  final bool isSeeking;
  final double seekPosition;
  final bool showVolumeIndicator;
  final double volume;
  final bool showBrightnessIndicator;
  final double brightness;

  const GestureState({
    this.isSeeking = false,
    this.seekPosition = 0.0,
    this.showVolumeIndicator = false,
    this.volume = 1.0,
    this.showBrightnessIndicator = false,
    this.brightness = 1.0,
  });

  GestureState copyWith({
    bool? isSeeking,
    double? seekPosition,
    bool? showVolumeIndicator,
    double? volume,
    bool? showBrightnessIndicator,
    double? brightness,
  }) {
    return GestureState(
      isSeeking: isSeeking ?? this.isSeeking,
      seekPosition: seekPosition ?? this.seekPosition,
      showVolumeIndicator: showVolumeIndicator ?? this.showVolumeIndicator,
      volume: volume ?? this.volume,
      showBrightnessIndicator:
          showBrightnessIndicator ?? this.showBrightnessIndicator,
      brightness: brightness ?? this.brightness,
    );
  }
}
