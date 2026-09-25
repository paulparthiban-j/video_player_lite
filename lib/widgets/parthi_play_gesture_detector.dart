import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/video_player_controller.dart';
import '../services/settings_service.dart';
import '../services/system_controls_service.dart';

class ParthiPlayGestureDetector extends ConsumerStatefulWidget {
  final Widget child;
  final Function(Duration) onSeek;
  final Function(double) onVolumeChanged;
  final Function(double) onBrightnessChanged;

  const ParthiPlayGestureDetector({
    super.key,
    required this.child,
    required this.onSeek,
    required this.onVolumeChanged,
    required this.onBrightnessChanged,
  });

  @override
  ConsumerState<ParthiPlayGestureDetector> createState() =>
      _ParthiPlayGestureDetectorState();
}

class _ParthiPlayGestureDetectorState
    extends ConsumerState<ParthiPlayGestureDetector> {
  double _dragStartX = 0;
  double _dragStartY = 0;
  Duration _dragStartPosition = Duration.zero;
  bool _isSeeking = false;
  bool _isAdjustingVolume = false;
  bool _isAdjustingBrightness = false;
  bool _wasPlayingBeforeHold = false;
  double _prevPlaybackSpeed = 1.0;
  Timer? _rewindTimer;
  static const Duration _rewindInterval = Duration(milliseconds: 250);
  Duration _rewindStep = const Duration(milliseconds: 500);
  StreamSubscription<void>? _settingsSubscription;
  double _forwardHoldSpeed = 2.0;
  double _rewindHoldSpeed = 2.0;
  TapDownDetails? _doubleTapDetails;

  // Initial values for gestures
  double _startVolume = 0.5;
  double _startBrightness = 0.5;

  // Gesture indicators
  bool _showVolumeIndicator = false;
  bool _showBrightnessIndicator = false;
  bool _showSeekIndicator = false;
  bool _showSpeedIndicator = false;
  bool _isForwardSpeed = true;
  double _currentVolume = 0.5;
  double _currentBrightness = 0.5;
  Duration _seekPosition = Duration.zero;
  bool _showSkipForward = false;
  bool _showSkipBack = false;
  Timer? _skipTimer;
  int _skipSeconds = 10;

  @override
  void initState() {
    super.initState();
    _loadGestureSettings();
    _settingsSubscription = SettingsService.changes.listen((_) {
      _loadGestureSettings();
    });
  }

  Future<void> _loadGestureSettings() async {
    final skipSeconds = await SettingsService.getDoubleTapSeekSeconds();
    final forwardHoldSpeed = await SettingsService.getHoldForwardSpeed();
    final rewindHoldSpeed = await SettingsService.getHoldRewindSpeed();
    if (!mounted) return;
    setState(() {
      _skipSeconds = skipSeconds;
      _forwardHoldSpeed = forwardHoldSpeed;
      _rewindHoldSpeed = rewindHoldSpeed;
      _rewindStep = Duration(
        milliseconds:
            (_rewindInterval.inMilliseconds * _rewindHoldSpeed).round().clamp(
                  100,
                  2000,
                ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Removed full state watch to prevent rebuilds
    // final videoState = ref.watch(videoPlayerControllerProvider);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final videoState = ref.read(videoPlayerControllerProvider);
        if (videoState.isLocked) return;
        final videoController = ref.read(
          videoPlayerControllerProvider.notifier,
        );
        debugPrint('[gesture] tap -> toggle controls');
        videoController.toggleControls();
      },
      onDoubleTapDown: (details) {
        final videoState = ref.read(videoPlayerControllerProvider);
        if (videoState.isLocked) return;
        debugPrint(
          '[gesture] doubleTapDown x=${details.localPosition.dx.toStringAsFixed(1)} y=${details.localPosition.dy.toStringAsFixed(1)}',
        );
        _doubleTapDetails = details;
      },
      onDoubleTap: () {
        final videoState = ref.read(videoPlayerControllerProvider);
        if (videoState.isLocked) return;
        final details = _doubleTapDetails;
        if (details == null) return;

        final box = context.findRenderObject() as RenderBox?;
        final width = box?.size.width ?? MediaQuery.of(context).size.width;
        final tapX = details.localPosition.dx;

        final videoController = ref.read(
          videoPlayerControllerProvider.notifier,
        );
        final videoStateCurrent = ref.read(videoPlayerControllerProvider);

        if (tapX < width / 3) {
          debugPrint('[gesture] doubleTap -> left seek -${_skipSeconds}s');
          final newPosition =
              videoStateCurrent.position - Duration(seconds: _skipSeconds);
          videoController.seekTo(newPosition);
          _showSkipIndicator(false);
        } else if (tapX > width * 2 / 3) {
          debugPrint('[gesture] doubleTap -> right seek +${_skipSeconds}s');
          final duration = videoStateCurrent.duration;
          Duration newPosition =
              videoStateCurrent.position + Duration(seconds: _skipSeconds);
          if (duration.inMilliseconds > 0 && newPosition > duration) {
            newPosition = duration;
          }
          videoController.seekTo(newPosition);
          _showSkipIndicator(true);
        } else {
          debugPrint('[gesture] doubleTap -> center play/pause');
          videoController.togglePlayPause();
        }
      },
      onLongPressStart: (details) {
        final videoState = ref.read(videoPlayerControllerProvider);
        if (videoState.isLocked) return;
        final screenWidth = MediaQuery.of(context).size.width;
        final videoController = ref.read(
          videoPlayerControllerProvider.notifier,
        );

        _wasPlayingBeforeHold = videoState.isPlaying;
        _prevPlaybackSpeed = videoState.playbackSpeed;

        if (details.globalPosition.dx > screenWidth / 2) {
          // Right side long press -> Speed Forward
          debugPrint(
            '[gesture] longPressStart -> forward ${_forwardHoldSpeed.toStringAsFixed(1)}x',
          );
          videoController.setPlaybackSpeed(_forwardHoldSpeed);
          if (!_wasPlayingBeforeHold) {
            videoController.play();
          }
          setState(() {
            _showSpeedIndicator = true;
            _isForwardSpeed = true;
          });
        } else {
          // Left side long press -> Rewind (safe seek loop)
          debugPrint(
            '[gesture] longPressStart -> rewind ${_rewindHoldSpeed.toStringAsFixed(1)}x',
          );
          videoController.pause();
          _rewindTimer?.cancel();
          _rewindTimer = Timer.periodic(_rewindInterval, (_) {
            final currentState = ref.read(videoPlayerControllerProvider);
            final newPosition = currentState.position - _rewindStep;
            videoController.seekTo(newPosition);
          });
          setState(() {
            _showSpeedIndicator = true;
            _isForwardSpeed = false;
          });
        }
      },
      onLongPressEnd: (details) {
        debugPrint('[gesture] longPressEnd');
        _endSpeedup();
      },
      onLongPressUp: () {
        debugPrint('[gesture] longPressUp');
        _endSpeedup();
      },
      onHorizontalDragStart: (details) {
        final videoState = ref.read(videoPlayerControllerProvider);
        if (videoState.isLocked) return;
        _dragStartX = details.globalPosition.dx;
        _dragStartPosition = videoState.position;
        _isSeeking = true;
        _showSeekIndicator = true;
        _seekPosition = _dragStartPosition;
      },
      onHorizontalDragUpdate: (details) {
        if (!_isSeeking) return;

        final videoState = ref.read(videoPlayerControllerProvider);
        final screenWidth = MediaQuery.of(context).size.width;
        final deltaX = details.globalPosition.dx - _dragStartX;
        final percentage = deltaX / screenWidth;

        final seekAmount = Duration(
          milliseconds: (videoState.duration.inMilliseconds * percentage)
              .round(),
        );

        _seekPosition = Duration(
          milliseconds: (_dragStartPosition + seekAmount).inMilliseconds.clamp(
            0,
            videoState.duration.inMilliseconds,
          ),
        );

        setState(() {});
      },
      onHorizontalDragEnd: (details) {
        if (_isSeeking) {
          widget.onSeek(_seekPosition);
          _isSeeking = false;
          _showSeekIndicator = false;
          setState(() {});
        }
      },
      onVerticalDragStart: (details) async {
        final videoState = ref.read(videoPlayerControllerProvider);
        if (videoState.isLocked) return;
        _dragStartY = details.globalPosition.dy;
        final screenWidth = MediaQuery.of(context).size.width;

        // Determine if we're adjusting volume (right side) or brightness (left side)
        if (details.globalPosition.dx > screenWidth / 2) {
          _isAdjustingVolume = true;
          _showVolumeIndicator = true;
          // Use player volume as baseline if system volume fails
          _startVolume = videoState.volume / 100.0;
          _currentVolume = _startVolume;
        } else {
          _isAdjustingBrightness = true;
          _showBrightnessIndicator = true;
          _startBrightness = await SystemControlsService.getCurrentBrightness();
          _currentBrightness = _startBrightness;
        }
      },
      onVerticalDragUpdate: (details) {
        if (!_isAdjustingVolume && !_isAdjustingBrightness) return;

        final screenHeight = MediaQuery.of(context).size.height;
        // Dragging UP (negative dy) should INCREASE value, so we subtract delta
        final deltaY = (_dragStartY - details.globalPosition.dy) / screenHeight;

        // Scale factor to make controls more responsive (1.5x sensitivity)
        final scaledDelta = deltaY * 1.5;

        if (_isAdjustingVolume) {
          _currentVolume = (_startVolume + scaledDelta).clamp(0.0, 2.0);
          widget.onVolumeChanged(_currentVolume);
          // Set actual system volume (system only supports 0-1)
          SystemControlsService.setVolume(_currentVolume.clamp(0.0, 1.0));
        } else if (_isAdjustingBrightness) {
          _currentBrightness = (_startBrightness + scaledDelta).clamp(0.0, 1.0);
          widget.onBrightnessChanged(_currentBrightness);
          // Set actual system brightness
          SystemControlsService.setBrightness(_currentBrightness);
        }

        setState(() {});
      },
      onVerticalDragEnd: (details) {
        _isAdjustingVolume = false;
        _isAdjustingBrightness = false;
        _showVolumeIndicator = false;
        _showBrightnessIndicator = false;
        setState(() {});
      },
      child: Stack(
        children: [
          // Main content
          widget.child,

          // Speed Indicator
          if (_showSpeedIndicator)
            Positioned(
              top: 80,
              left: _isForwardSpeed ? null : 40,
              right: _isForwardSpeed ? 40 : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isForwardSpeed ? Icons.fast_forward : Icons.fast_rewind,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isForwardSpeed
                          ? '${_forwardHoldSpeed.toStringAsFixed(1)}x Playing'
                          : '${_rewindHoldSpeed.toStringAsFixed(1)}x Rewinding',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Volume indicator (Centered)
          if (_showVolumeIndicator)
            Center(
              child: _buildCenterIndicator(
                _currentVolume > 0 
                  ? (_currentVolume >= 0.5 ? Icons.volume_up : Icons.volume_down)
                  : Icons.volume_off,
                _currentVolume,
                _currentVolume > 1.0 ? Colors.red : Colors.blue,
                isVolume: true,
              ),
            ),

          // Brightness indicator (Centered)
          if (_showBrightnessIndicator)
            Center(
              child: _buildCenterIndicator(
                _currentBrightness > 0.5 ? Icons.brightness_7 : Icons.brightness_6,
                _currentBrightness,
                Colors.orange,
              ),
            ),

          // Skip Indicators (Double tap)
          if (_showSkipBack)
            Positioned(
              left: 50,
              top: 0,
              bottom: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fast_rewind, color: Colors.white, size: 48),
                    Text(
                      "-${_skipSeconds}s",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_showSkipForward)
            Positioned(
              right: 50,
              top: 0,
              bottom: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fast_forward, color: Colors.white, size: 48),
                    Text(
                      "+${_skipSeconds}s",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Seek indicator
          if (_showSeekIndicator)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Consumer(
                builder: (context, ref, child) {
                  final duration = ref.watch(
                    videoPlayerControllerProvider.select((s) => s.duration),
                  );
                  return _buildSeekIndicator(duration);
                },
              ),
            ),
        ],
      ),
    );
  }

  void _showSkipIndicator(bool forward) {
    _skipTimer?.cancel();
    setState(() {
      if (forward) {
        _showSkipForward = true;
        _showSkipBack = false;
      } else {
        _showSkipBack = true;
        _showSkipForward = false;
      }
    });
    _skipTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _showSkipForward = false;
          _showSkipBack = false;
        });
      }
    });
  }

  Widget _buildCenterIndicator(IconData icon, double value, Color color, {bool isVolume = false}) {
    // For volume boost, we show a special label
    final isBoost = isVolume && value > 1.0;
    // Normalize value for display (0-100% or more for boost)
    final displayValue = (value * 100).round();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isBoost ? Colors.red : color,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            isBoost ? 'Boost: $displayValue%' : '$displayValue%',
            style: TextStyle(
              color: isBoost ? Colors.red : Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 150,
            height: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: isVolume ? (value / 2.0).clamp(0.0, 1.0) : value.clamp(0.0, 1.0),
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isBoost ? Colors.red : color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeekIndicator(Duration duration) {
    final percentage = duration.inMilliseconds > 0
        ? (_seekPosition.inMilliseconds /
              duration.inMilliseconds *
              100)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _seekPosition < _dragStartPosition
                    ? Icons.fast_rewind
                    : Icons.fast_forward,
                color: Colors.red,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(_seekPosition),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: Colors.grey[600],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
          ),
          const SizedBox(height: 4),
          Text(
            '${percentage.round()}%',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _endSpeedup() {
    if (_showSpeedIndicator) {
      final videoController = ref.read(videoPlayerControllerProvider.notifier);
      _rewindTimer?.cancel();
      _rewindTimer = null;
      videoController.setPlaybackSpeed(_prevPlaybackSpeed);
      if (!_wasPlayingBeforeHold) {
        videoController.pause();
      }
      setState(() {
        _showSpeedIndicator = false;
      });
    }
  }

  @override
  void dispose() {
    _rewindTimer?.cancel();
    _rewindTimer = null;
    _settingsSubscription?.cancel();
    _settingsSubscription = null;
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    final String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}
