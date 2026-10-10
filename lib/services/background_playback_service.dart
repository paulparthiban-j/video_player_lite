import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BackgroundPlaybackService {
  static const MethodChannel _channel = MethodChannel('next_player/background');
  static bool _isBackgroundEnabled = false;
  static StreamController<bool>? _backgroundStatusController;

  static Stream<bool> get backgroundStatusStream =>
      _backgroundStatusController?.stream ?? Stream.empty();

  static Future<bool> isBackgroundSupported() async {
    // Only iOS has a native handler for this channel.
    if (!Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod('isBackgroundSupported') ?? false;
    } catch (e) {
      debugPrint('Error checking background support: $e');
      return false;
    }
  }

  static Future<bool> isBackgroundActive() async {
    try {
      return await _channel.invokeMethod('isBackgroundActive') ?? false;
    } catch (e) {
      debugPrint('Error checking background status: $e');
      return false;
    }
  }

  static Future<bool> enableBackgroundPlayback({
    required String title,
    required String artist,
    required String url,
    String? albumArt,
    Duration? duration,
  }) async {
    try {
      if (!await isBackgroundSupported()) {
        debugPrint('Background playback not supported on this device');
        return false;
      }

      final params = <String, dynamic>{
        'title': title,
        'artist': artist,
        'url': url,
        'albumArt': albumArt,
        'duration': duration?.inMilliseconds,
      };

      final result = await _channel.invokeMethod(
        'enableBackgroundPlayback',
        params,
      );
      _isBackgroundEnabled = result ?? false;

      if (_isBackgroundEnabled) {
        _initializeBackgroundStatusStream();
      }

      return _isBackgroundEnabled;
    } catch (e) {
      debugPrint('Error enabling background playback: $e');
      return false;
    }
  }

  static Future<bool> disableBackgroundPlayback() async {
    try {
      final result = await _channel.invokeMethod('disableBackgroundPlayback');
      _isBackgroundEnabled = !(result ?? true);

      if (!_isBackgroundEnabled) {
        _disposeBackgroundStatusStream();
      }

      return !_isBackgroundEnabled;
    } catch (e) {
      debugPrint('Error disabling background playback: $e');
      return false;
    }
  }

  static Future<void> updateBackgroundMedia({
    String? title,
    String? artist,
    String? albumArt,
    Duration? duration,
  }) async {
    try {
      if (!_isBackgroundEnabled) return;

      final params = <String, dynamic>{
        'title': title,
        'artist': artist,
        'albumArt': albumArt,
        'duration': duration?.inMilliseconds,
      };

      await _channel.invokeMethod('updateBackgroundMedia', params);
    } catch (e) {
      debugPrint('Error updating background media: $e');
    }
  }

  static Future<void> setBackgroundPosition(Duration position) async {
    try {
      if (!_isBackgroundEnabled) return;

      await _channel.invokeMethod('setBackgroundPosition', {
        'position': position.inMilliseconds,
      });
    } catch (e) {
      debugPrint('Error setting background position: $e');
    }
  }

  static Future<void> setBackgroundPlayPause(bool isPlaying) async {
    try {
      if (!_isBackgroundEnabled) return;

      await _channel.invokeMethod('setBackgroundPlayPause', {
        'isPlaying': isPlaying,
      });
    } catch (e) {
      debugPrint('Error setting background play/pause: $e');
    }
  }

  static void _initializeBackgroundStatusStream() {
    _backgroundStatusController?.close();
    _backgroundStatusController = StreamController<bool>.broadcast();

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onBackgroundStarted':
          _isBackgroundEnabled = true;
          _backgroundStatusController?.add(true);
          break;
        case 'onBackgroundStopped':
          _isBackgroundEnabled = false;
          _backgroundStatusController?.add(false);
          break;
        case 'onBackgroundPlayPause':
          final isPlaying = call.arguments['isPlaying'] ?? false;
          _backgroundStatusController?.add(isPlaying);
          break;
      }
    });
  }

  static void _disposeBackgroundStatusStream() {
    _backgroundStatusController?.close();
    _backgroundStatusController = null;
    _channel.setMethodCallHandler(null);
  }

  static bool get isCurrentlyInBackground => _isBackgroundEnabled;

  static Future<void> dispose() async {
    if (_isBackgroundEnabled) {
      await disableBackgroundPlayback();
    }
    _disposeBackgroundStatusStream();
  }
}
