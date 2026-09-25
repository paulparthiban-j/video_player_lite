import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class SystemControlsService {
  static const MethodChannel _channel = MethodChannel(
    'next_player/system_controls',
  );
  static double _currentBrightness = 0.5;
  static double _currentVolume = 0.5;
  static bool _isInitialized = false;

  static Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Get current system values
      await _getCurrentBrightness();
      await _getCurrentVolume();
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Error initializing system controls: $e');
      return false;
    }
  }

  static Future<double> getCurrentBrightness() async {
    if (!_isInitialized) await initialize();
    return _currentBrightness;
  }

  static Future<double> getCurrentVolume() async {
    if (!_isInitialized) await initialize();
    return _currentVolume;
  }

  static Future<bool> setBrightness(double brightness) async {
    try {
      if (brightness < 0.0) brightness = 0.0;
      if (brightness > 1.0) brightness = 1.0;

      final result = await _channel.invokeMethod('setBrightness', {
        'brightness': brightness,
      });

      if (result == true) {
        _currentBrightness = brightness;
      }

      return result ?? false;
    } catch (e) {
      debugPrint('Error setting brightness: $e');
      return false;
    }
  }

  static Future<bool> setVolume(double volume) async {
    try {
      if (volume < 0.0) volume = 0.0;
      if (volume > 1.0) volume = 1.0;

      final result = await _channel.invokeMethod('setVolume', {
        'volume': volume,
      });

      if (result == true) {
        _currentVolume = volume;
      }

      return result ?? false;
    } catch (e) {
      debugPrint('Error setting volume: $e');
      return false;
    }
  }

  static Future<void> _getCurrentBrightness() async {
    try {
      final brightness = await _channel.invokeMethod('getBrightness');
      if (brightness != null) {
        _currentBrightness = (brightness as num).toDouble().clamp(0.0, 1.0);
      }
    } catch (e) {
      debugPrint('Error getting current brightness: $e');
      // Use default value
      _currentBrightness = 0.5;
    }
  }

  static Future<void> _getCurrentVolume() async {
    try {
      final volume = await _channel.invokeMethod('getVolume');
      if (volume != null) {
        _currentVolume = (volume as num).toDouble().clamp(0.0, 1.0);
      }
    } catch (e) {
      debugPrint('Error getting current volume: $e');
      // Use default value
      _currentVolume = 0.5;
    }
  }

  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod('isSupported') ?? false;
    } catch (e) {
      debugPrint('Error checking system controls support: $e');
      return false;
    }
  }

  static Future<bool> requestAudioFocus() async {
    try {
      return await _channel.invokeMethod('requestAudioFocus') ?? false;
    } catch (e) {
      debugPrint('Error requesting audio focus: $e');
      return false;
    }
  }

  static Future<bool> abandonAudioFocus() async {
    try {
      return await _channel.invokeMethod('abandonAudioFocus') ?? false;
    } catch (e) {
      debugPrint('Error abandoning audio focus: $e');
      return false;
    }
  }

  static bool get isInitialized => _isInitialized;
}
