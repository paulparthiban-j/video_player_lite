import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:media_kit_video/media_kit_video.dart';
import '../core/video_player_controller.dart';
import '../services/performance_service.dart';
import '../services/system_controls_service.dart';
import '../services/playback_history_service.dart';
import '../services/settings_service.dart';
import 'parthi_play_controls.dart';
import 'parthi_play_gesture_detector.dart';
import 'subtitle_display_widget.dart';
import 'video_error_handler.dart';

class ParthiPlayVideoPlayer extends ConsumerStatefulWidget {
  final String? videoUrl;
  final String? videoPath;
  final bool autoPlay;
  final bool looping;
  final VoidCallback? onVideoEnded;
  final VoidCallback? onBackPressed;

  const ParthiPlayVideoPlayer({
    super.key,
    this.videoUrl,
    this.videoPath,
    this.autoPlay = true,
    this.looping = false,
    this.onVideoEnded,
    this.onBackPressed,
  });

  @override
  ConsumerState<ParthiPlayVideoPlayer> createState() =>
      _ParthiPlayVideoPlayerState();
}

class _ParthiPlayVideoPlayerState extends ConsumerState<ParthiPlayVideoPlayer>
    with WidgetsBindingObserver {
  VideoPlayerControllerNotifier? _videoController;
  StateController<VoidCallback?>? _backCallbackController;
  static const MethodChannel _orientationChannel = MethodChannel(
    'parthi_play/orientation',
  );
  StreamSubscription<void>? _performanceSettingsSubscription;
  bool _autoPerfMonitoring = false;
  bool _autoPerfApplied = false;
  final List<int> _jankSamples = [];
  DateTime? _autoPerfLastAppliedAt;
  DateTime? _autoPerfLastRecoveredAt;
  static const Duration _autoPerfCooldown = Duration(seconds: 12);
  PlayerOrientation? _lastAutoOrientation;
  Timer? _orientationRetryTimer;
  bool _backgroundPlayEnabled = false;
  StreamSubscription<void>? _settingsSubscription;
  String? _resumePromptForPath;

  @override
  void initState() {
    super.initState();
    PerformanceService.initialize();
    PerformanceService.optimizeForVideoPlayback();
    WidgetsBinding.instance.addObserver(this);
    _backCallbackController = ref.read(
      videoPlayerBackCallbackProvider.notifier,
    );
    // Ensure auto-rotate is enabled on the player screen by default.
    _applyOrientationWithRetry(PlayerOrientation.auto);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _videoController = ref.read(videoPlayerControllerProvider.notifier);
        if (widget.onBackPressed != null) {
          _backCallbackController?.state = widget.onBackPressed;
        }
        _initializeVideo();

        final videoState = ref.read(videoPlayerControllerProvider);
        _applyOrientation(videoState.orientation);
      }
    });

    _performanceSettingsSubscription = PerformanceService.changes.listen((_) {
      _updateAutoPerformanceMonitoring();
      _applyRuntimePerformanceSettings();
    });

    _loadBackgroundPlayPreference();
    _settingsSubscription = SettingsService.changes.listen((_) {
      _loadBackgroundPlayPreference();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orientationRetryTimer?.cancel();
    _orientationRetryTimer = null;
    _stopAutoPerformanceMonitoring();
    _performanceSettingsSubscription?.cancel();
    _performanceSettingsSubscription = null;
    _settingsSubscription?.cancel();
    _settingsSubscription = null;
    try {
      _videoController?.reset();
    } catch (e) {
      debugPrint('Error in dispose: $e');
    }
    _resetOrientation();
    PerformanceService.resetPerformanceSettings();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      final videoState = ref.read(videoPlayerControllerProvider);
      if (!videoState.isInPip && !_backgroundPlayEnabled) {
        _videoController?.pause();
      }
      if (videoState.videoPath != null) {
        PlaybackHistoryService.savePosition(
          videoState.videoPath!,
          videoState.position,
        );
      }
    } else if (state == AppLifecycleState.resumed) {
      final controller = ref.read(videoPlayerControllerProvider.notifier);
      controller.setInPip(false);
      controller.setControlsVisible(true);
      _updateAutoPerformanceMonitoring();
    }
  }

  Future<void> _handleBack() async {
    _backCallbackController?.state = null;
    if (_videoController != null) {
      await _videoController!.pause();
      await _videoController!.reset();
    }
    // Removed delay for instant navigation
    if (mounted) {
      if (widget.onBackPressed != null) {
        widget.onBackPressed!();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _initializeVideo() async {
    if (_videoController == null) {
      debugPrint('Video controller not initialized yet');
      return;
    }

    try {
      final videoState = ref.read(videoPlayerControllerProvider);

      if (!videoState.isInitialized &&
          (widget.videoUrl != null || widget.videoPath != null) &&
          videoState.player == null) {
        Duration? startPosition;
        if (widget.videoPath != null) {
          startPosition = await _resolveStartPosition(widget.videoPath!);
        }
        await _videoController!.initializeVideo(
          widget.videoUrl,
          widget.videoPath,
          autoPlay: widget.autoPlay,
          startPosition: startPosition,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error in _initializeVideo: $e');
      debugPrint('Stack trace: $stackTrace');
    }

    _updateAutoPerformanceMonitoring();
    _applyRuntimePerformanceSettings();
  }

  Future<void> _loadBackgroundPlayPreference() async {
    final enabled = await SettingsService.getBackgroundPlaybackEnabled(
      isIOS: Platform.isIOS,
    );
    if (!mounted) return;
    setState(() {
      _backgroundPlayEnabled = enabled;
    });
  }

  Future<Duration?> _resolveStartPosition(String videoPath) async {
    if (_resumePromptForPath == videoPath) return null;
    final savedPosition = await PlaybackHistoryService.getPosition(videoPath);
    if (savedPosition.inSeconds <= 5) return null;

    _resumePromptForPath = videoPath;
    if (!mounted) return null;
    final resume = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resume playback?'),
        content: Text('Continue from ${_formatDuration(savedPosition)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Start Over'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Resume'),
          ),
        ],
      ),
    );

    if (resume == true) return savedPosition;
    if (resume == false) {
      await PlaybackHistoryService.clearPosition(videoPath);
    }
    return null;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  void _applyRuntimePerformanceSettings() {
    final controller = _videoController;
    if (controller == null) return;
    controller.applyHdrToneMapping(PerformanceService.isHdrToneMappingEnabled);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final orientation = ref.read(
      videoPlayerControllerProvider.select((s) => s.orientation),
    );
    if (orientation == PlayerOrientation.auto) {
      _applyOrientation(PlayerOrientation.auto);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _updateAutoPerformanceMonitoring() {
    if (PerformanceService.isAutoPerformanceEnabled) {
      _startAutoPerformanceMonitoring();
    } else {
      _stopAutoPerformanceMonitoring();
      _autoPerfApplied = false;
      PerformanceService.resetDynamicPerformance();
    }
  }

  void _startAutoPerformanceMonitoring() {
    if (_autoPerfMonitoring) return;
    _autoPerfMonitoring = true;
    _autoPerfApplied = false;
    _jankSamples.clear();
    _autoPerfLastAppliedAt = null;
    _autoPerfLastRecoveredAt = null;
    SchedulerBinding.instance.addTimingsCallback(_handleFrameTimings);
  }

  void _stopAutoPerformanceMonitoring() {
    if (!_autoPerfMonitoring) return;
    _autoPerfMonitoring = false;
    _jankSamples.clear();
    _autoPerfLastAppliedAt = null;
    _autoPerfLastRecoveredAt = null;
    SchedulerBinding.instance.removeTimingsCallback(_handleFrameTimings);
  }

  void _handleFrameTimings(List<FrameTiming> timings) {
    if (!_autoPerfMonitoring) return;
    for (final timing in timings) {
      final total = timing.totalSpan.inMilliseconds;
      final isJank = total > 32 ? 1 : 0;
      _jankSamples.add(isJank);
    }
    const int windowSize = 30;
    const int minSamples = 20;
    if (_jankSamples.length > windowSize) {
      _jankSamples.removeRange(0, _jankSamples.length - windowSize);
    }
    if (_jankSamples.length < minSamples) return;

    final now = DateTime.now();
    final jankCount = _jankSamples.fold<int>(0, (sum, v) => sum + v);
    final jankRatio = jankCount / _jankSamples.length;

    if (!_autoPerfApplied) {
      final canApply =
          _autoPerfLastAppliedAt == null ||
          now.difference(_autoPerfLastAppliedAt!) >= _autoPerfCooldown;
      if (canApply && jankRatio >= 0.4) {
        debugPrint(
          '[auto-perf] jank=${(jankRatio * 100).toStringAsFixed(0)}% -> enable frame drop',
        );
        final controller = ref.read(videoPlayerControllerProvider.notifier);
        controller.applyDynamicPerformance(
          frameDrop: true,
          skipLoopFilter: true,
        );
        _autoPerfApplied = true;
        _autoPerfLastAppliedAt = now;
        _jankSamples.clear();
      }
      return;
    }

    final canRecover =
        _autoPerfLastRecoveredAt == null ||
        now.difference(_autoPerfLastRecoveredAt!) >= _autoPerfCooldown;
    if (canRecover && jankRatio <= 0.15) {
      debugPrint(
        '[auto-perf] jank=${(jankRatio * 100).toStringAsFixed(0)}% -> disable frame drop',
      );
      final controller = ref.read(videoPlayerControllerProvider.notifier);
      controller.applyDynamicPerformance(
        frameDrop: false,
        skipLoopFilter: false,
      );
      _autoPerfApplied = false;
      _autoPerfLastRecoveredAt = now;
      _jankSamples.clear();
    }
  }

  void _resetOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _setNativeOrientation('setSensorPortrait');
  }

  void _applyOrientation(PlayerOrientation orientation) {
    switch (orientation) {
      case PlayerOrientation.auto:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        _setNativeOrientation('setFullSensor');
        break;
      case PlayerOrientation.landscape:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        _setNativeOrientation('setSensorLandscape');
        break;
      case PlayerOrientation.portrait:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        _setNativeOrientation('setSensorPortrait');
        break;
    }
  }

  Future<void> _setNativeOrientation(String method) async {
    try {
      await _orientationChannel.invokeMethod(method);
    } catch (_) {
      // Ignore if not available (e.g., iOS)
    }
  }

  void _applyOrientationWithRetry(PlayerOrientation orientation) {
    _applyOrientation(orientation);
    _orientationRetryTimer?.cancel();
    int attempts = 0;
    _orientationRetryTimer = Timer.periodic(const Duration(milliseconds: 400), (
      timer,
    ) {
      attempts++;
      _applyOrientation(orientation);
      if (attempts >= 3) {
        timer.cancel();
      }
    });
  }

  void _applyAutoOrientationForAspectRatio(double aspectRatio) {
    if (aspectRatio <= 0) return;
    final next = aspectRatio >= 1.15
        ? PlayerOrientation.landscape
        : PlayerOrientation.portrait;
    if (_lastAutoOrientation == next) return;
    _lastAutoOrientation = next;
    _applyOrientationWithRetry(next);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(videoPlayerControllerProvider.select((s) => s.orientation), (
      _,
      next,
    ) {
      _applyOrientationWithRetry(next);
    });

    ref.listen(videoPlayerControllerProvider.select((s) => s.aspectRatio), (
      _,
      ratio,
    ) {
      final orientation = ref.read(
        videoPlayerControllerProvider.select((s) => s.orientation),
      );
      if (orientation == PlayerOrientation.auto) {
        _applyAutoOrientationForAspectRatio(ratio);
      }
    });

    // Use select to only watch specific properties to avoid unnecessary rebuilds
    final bool isInitialized = ref.watch(
      videoPlayerControllerProvider.select((s) => s.isInitialized),
    );
    final bool isLoaded = ref.watch(
      videoPlayerControllerProvider.select((s) => s.isLoaded),
    );
    final bool isSwitching = ref.watch(
      videoPlayerControllerProvider.select((s) => s.isSwitchingDecoder),
    );
    final bool isLoading = (!isInitialized || !isLoaded) && !isSwitching;
    final bool isInPip = ref.watch(
      videoPlayerControllerProvider.select((s) => s.isInPip),
    );
    final bool isPlaying = ref.watch(
      videoPlayerControllerProvider.select((s) => s.isPlaying),
    );

    // Use a separate ProviderScope or select for orientation to avoid full rebuilds
    // Note: Orientation is handled by strict listener above, so we don't need to watch it here
    // for building the widget tree structure unless it changes the valid layout.

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _handleBack();
        }
      },
      child: VideoPlayerErrorHandler(
        videoPath: widget.videoPath,
        videoUrl: widget.videoUrl,
        onRetry: () => _initializeVideo(),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              if (isInitialized)
                Stack(
                  children: [
                    ParthiPlayGestureDetector(
                      onSeek: (position) {
                        ref
                            .read(videoPlayerControllerProvider.notifier)
                            .seekTo(position);
                      },
                      onVolumeChanged: (volume) {
                        ref
                            .read(videoPlayerControllerProvider.notifier)
                            .setVolume(volume);
                      },
                      onBrightnessChanged: (brightness) async {
                        try {
                          await SystemControlsService.setBrightness(brightness);
                        } catch (e) {
                          debugPrint('Error setting brightness: $e');
                        }
                      },
                      child: Container(
                        color: Colors.black,
                        width: double.infinity,
                        height: double.infinity,
                        child: Center(
                          child: Consumer(
                            builder: (context, ref, child) {
                              final currentRatio = ref.watch(
                                videoPlayerControllerProvider.select(
                                  (s) => s.aspectRatio,
                                ),
                              );
                              final videoController = ref.watch(
                                videoPlayerControllerProvider.select(
                                  (s) => s.videoController,
                                ),
                              );

                              if (videoController == null) {
                                return const SizedBox.shrink();
                              }

                              final Widget videoWidget = Video(
                                controller: videoController,
                                fit: BoxFit.contain,
                                controls: NoVideoControls,
                                width: double.infinity,
                                height: double.infinity,
                                fill: Colors.black,
                                filterQuality: FilterQuality.high,
                              );

                              if (currentRatio > 0) {
                                return AspectRatio(
                                  aspectRatio: currentRatio,
                                  child: videoWidget,
                                );
                              }
                              return videoWidget;
                            },
                          ),
                        ),
                      ),
                    ),
                    if (!isInPip)
                      Positioned.fill(
                        child: Consumer(
                          builder: (context, ref, child) {
                            final isLoaded = ref.watch(
                              videoPlayerControllerProvider.select(
                                (s) => s.isLoaded,
                              ),
                            );
                            if (!isLoaded) return const SizedBox.shrink();
                            return const ParthiPlayControls();
                          },
                        ),
                      ),
                    if (!isInPip)
                      Positioned.fill(
                        child: Consumer(
                          builder: (context, ref, child) {
                            final position = ref.watch(
                              videoPlayerControllerProvider.select(
                                (s) => s.position,
                              ),
                            );
                            final subtitles = ref.watch(
                              videoPlayerControllerProvider.select(
                                (s) => s.subtitles,
                              ),
                            );
                            final subtitlePath = ref.watch(
                              videoPlayerControllerProvider.select(
                                (s) => s.subtitlePath,
                              ),
                            );

                            if (subtitles.isEmpty || subtitlePath == null) {
                              return const SizedBox.shrink();
                            }

                            return SubtitleDisplayWidget(
                              currentPosition: position,
                              subtitles: subtitles,
                            );
                          },
                        ),
                      ),
                    if (isInPip)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Material(
                          color: Colors.black45,
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              ref
                                  .read(videoPlayerControllerProvider.notifier)
                                  .togglePlayPause();
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              if (isLoading) _buildLoadingIndicator(),
              _buildDecoderSwitchOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDecoderSwitchOverlay() {
    final isSwitching = ref.watch(
      videoPlayerControllerProvider.select((s) => s.isSwitchingDecoder),
    );
    if (!isSwitching) return const SizedBox.shrink();
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
            ),
            SizedBox(height: 12),
            Text('Switching decoder...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    final isResolving = ref.watch(
      videoPlayerControllerProvider.select((s) => s.isResolvingStream),
    );
    final message = ref.watch(
      videoPlayerControllerProvider.select((s) => s.resolvingMessage),
    );
    final progress = ref.watch(
      videoPlayerControllerProvider.select((s) => s.resolvingProgress),
    );

    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
            ),
            if (isResolving) ...[
              const SizedBox(height: 12),
              Text(
                message ?? 'Loading stream...',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 220,
                child: LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(progress.clamp(0.0, 1.0) * 100).round()}%',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
