import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/video_player_controller.dart';
import '../services/youtube_stream_service.dart';

class CodecErrorHandler {
  static bool _isHEVCUnsupported = false;
  static String? _lastFailedVideo;

  static bool isHEVCUnsupported(String? videoPath) {
    if (videoPath == null) return false;

    // Check if we already know this device has HEVC issues
    if (_isHEVCUnsupported) return true;

    // Check if this specific video failed before
    if (_lastFailedVideo == videoPath) return true;

    return false;
  }

  static void markHEVCUnsupported(String videoPath) {
    _isHEVCUnsupported = true;
    _lastFailedVideo = videoPath;
    debugPrint('HEVC codec marked as unsupported for this device');
  }

  static void reset() {
    _isHEVCUnsupported = false;
    _lastFailedVideo = null;
  }

  static String getUnsupportedMessage() {
    return 'HEVC (H.265) codec is not supported on this device. Try converting the video to H.264 format or use a different video.';
  }
}

class VideoPlayerErrorHandler extends ConsumerStatefulWidget {
  final Widget child;
  final String? videoPath;
  final String? videoUrl;
  final VoidCallback? onRetry;

  const VideoPlayerErrorHandler({
    super.key,
    required this.child,
    this.videoPath,
    this.videoUrl,
    this.onRetry,
  });

  @override
  ConsumerState<VideoPlayerErrorHandler> createState() =>
      _VideoPlayerErrorHandlerState();
}

class _VideoPlayerErrorHandlerState
    extends ConsumerState<VideoPlayerErrorHandler> {
  bool _hasError = false;
  String _errorMessage = '';

  bool get _isNetworkError {
    final msg = _errorMessage.toLowerCase();
    return msg.contains('timed out') || msg.contains('network');
  }

  @override
  void initState() {
    super.initState();
  }

  void _retryPlayback() {
    setState(() {
      _hasError = false;
    });

    CodecErrorHandler.reset();
    widget.onRetry?.call();
  }

  @override
  Widget build(BuildContext context) {
    // Listen for error states - this is the correct place for ref.listen
    ref.listen<VideoPlayerState>(videoPlayerControllerProvider, (
      previous,
      next,
    ) {
      if (next.hasError && !_hasError) {
        setState(() {
          _hasError = true;
          _errorMessage = next.errorMessage ?? 'Unknown error occurred';
        });
      } else if (!next.hasError && _hasError) {
        setState(() {
          _hasError = false;
          _errorMessage = '';
        });
      }
    });

    if (_hasError) {
      return _buildErrorScreen();
    }

    return widget.child;
  }

  Widget _buildErrorScreen() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, Colors.grey[900]!],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 64,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Playback Error',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage.isNotEmpty
                    ? _errorMessage
                    : CodecErrorHandler.getUnsupportedMessage(),
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Go Back',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (widget.videoUrl != null &&
                      YoutubeStreamService.isYoutubeUrl(widget.videoUrl!))
                    ElevatedButton(
                      onPressed: _openInYoutube,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Open in YouTube',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.red.shade600, Colors.orange.shade600],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _retryPlayback,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _isNetworkError ? 'Reconnect' : 'Retry',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openInYoutube() async {
    final url = widget.videoUrl;
    if (url == null || url.isEmpty) return;

    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
