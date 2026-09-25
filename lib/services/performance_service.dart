import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PerformanceService {
  static bool _isLowEndDevice = false;
  static bool _isInitialized = false;
  static bool _isOptimizedForVideo = false;
  static bool _isMediaTek = false;
  static bool? _forcedHwDec;
  static bool? _forcedFrameDrop;
  static bool? _forcedSkipLoopFilter;
  static bool? _autoPerformanceMode;
  static bool? _dynamicFrameDrop;
  static bool? _dynamicSkipLoopFilter;
  static bool? _hdrToneMap;

  static final StreamController<void> _changes =
      StreamController<void>.broadcast();

  static Stream<void> get changes => _changes.stream;

  // Keys for persistence
  static const String _hwDecKey = 'perf_hw_dec';
  static const String _frameDropKey = 'perf_frame_drop';
  static const String _skipLoopKey = 'perf_skip_loop';
  static const String _autoPerfKey = 'perf_auto_mode';
  static const String _hdrToneMapKey = 'perf_hdr_tonemap';

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        final hardware = androidInfo.hardware.toLowerCase();
        final brand = androidInfo.brand.toLowerCase();
        final manufacturer = androidInfo.manufacturer.toLowerCase();

        // Detect MediaTek devices
        _isMediaTek =
            hardware.contains('mt') ||
            hardware.contains('helio') ||
            brand.contains('vivo') || // Many Vivo phones are MTK
            manufacturer.contains('vivo');

        debugPrint(
          'Device Hardware: $hardware, Brand: $brand, IsMediaTek: $_isMediaTek',
        );

        // Consider devices with Android < 8 or MediaTek P35/G35 class as low-end
        _isLowEndDevice = sdkInt < 26 || _isMediaTek;
      } else if (Platform.isIOS) {
        final iosInfo = await DeviceInfoPlugin().iosInfo;
        final model = iosInfo.model;
        final systemVersion = iosInfo.systemVersion;

        // Consider iPhone 6s/SE and older as low-end
        _isLowEndDevice =
            _isOldIOSDevice(model) || _isOldIOSVersion(systemVersion);
      }
    } catch (e) {
      debugPrint('Error detecting device performance: $e');
      _isLowEndDevice = true; // Assume low-end on error
    }

    await _loadSettings();
    _isInitialized = true;
  }

  static Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _forcedHwDec = prefs.getBool(_hwDecKey);
      _forcedFrameDrop = prefs.getBool(_frameDropKey);
      _forcedSkipLoopFilter = prefs.getBool(_skipLoopKey);
      _autoPerformanceMode = prefs.getBool(_autoPerfKey);
      _hdrToneMap = prefs.getBool(_hdrToneMapKey);
    } catch (e) {
      debugPrint('Error loading performance settings: $e');
    }
  }

  static Future<void> setHardwareDecoding(bool enable) async {
    _forcedHwDec = enable;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hwDecKey, enable);
    _changes.add(null);
  }

  static Future<void> setFrameDrop(bool enable) async {
    _forcedFrameDrop = enable;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_frameDropKey, enable);
    _changes.add(null);
  }

  static Future<void> setSkipLoopFilter(bool enable) async {
    _forcedSkipLoopFilter = enable;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_skipLoopKey, enable);
    _changes.add(null);
  }

  static Future<void> setAutoPerformanceMode(bool enable) async {
    _autoPerformanceMode = enable;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPerfKey, enable);
    _changes.add(null);
  }

  static Future<void> setHdrToneMapping(bool enable) async {
    _hdrToneMap = enable;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hdrToneMapKey, enable);
    _changes.add(null);
  }

  static bool get isHdrToneMappingEnabled => _hdrToneMap ?? false;

  static bool get isAutoPerformanceEnabled => _autoPerformanceMode ?? false;

  static void setDynamicPerformance({bool? frameDrop, bool? skipLoopFilter}) {
    if (frameDrop != null) _dynamicFrameDrop = frameDrop;
    if (skipLoopFilter != null) _dynamicSkipLoopFilter = skipLoopFilter;
  }

  static void resetDynamicPerformance() {
    _dynamicFrameDrop = null;
    _dynamicSkipLoopFilter = null;
  }

  static bool get isHardwareDecodingEnabled =>
      _forcedHwDec ?? true; // Default true
  static bool get isFrameDropEnabled {
    if (_forcedFrameDrop != null) return _forcedFrameDrop!;
    if (isAutoPerformanceEnabled && _dynamicFrameDrop != null) {
      return _dynamicFrameDrop!;
    }
    return _isLowEndDevice;
  }

  static bool get isSkipLoopFilterEnabled {
    if (_forcedSkipLoopFilter != null) return _forcedSkipLoopFilter!;
    if (isAutoPerformanceEnabled && _dynamicSkipLoopFilter != null) {
      return _dynamicSkipLoopFilter!;
    }
    return _isLowEndDevice;
  }

  static Future<void> optimizeForVideoPlayback() async {
    if (_isOptimizedForVideo) return;

    try {
      // Set preferred orientations for video playback
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      // Hide system UI for immersive experience
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      _isOptimizedForVideo = true;
      debugPrint('Performance optimization enabled for video playback');
    } catch (e) {
      debugPrint('Error optimizing performance: $e');
    }
  }

  static Future<void> resetPerformanceSettings() async {
    try {
      // Reset to default orientations
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      // Show system UI again
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      _isOptimizedForVideo = false;
    } catch (e) {
      debugPrint('Error resetting performance settings: $e');
    }
  }

  static bool get isLowEndDevice => _isLowEndDevice;
  static bool get isOptimizedForVideo => _isOptimizedForVideo;

  static bool _isOldIOSDevice(String model) {
    final oldModels = [
      'iPhone6,1', 'iPhone6,2', // iPhone 5s
      'iPhone7,1', 'iPhone7,2', // iPhone 6/6 Plus
      'iPhone8,1', 'iPhone8,2', 'iPhone8,4', // iPhone 6s/6s Plus/SE
    ];
    return oldModels.any((oldModel) => model.contains(oldModel));
  }

  static bool _isOldIOSVersion(String version) {
    try {
      final parts = version.split('.');
      final majorVersion = int.parse(parts[0]);
      return majorVersion < 13;
    } catch (e) {
      return true;
    }
  }

  // Get optimal video resolution based on device capabilities
  static String getOptimalResolution() {
    if (_isLowEndDevice) {
      return '720p'; // Lower resolution for low-end devices
    }
    return '1080p'; // Full HD for capable devices
  }

  // Get optimal buffer duration
  static Duration getOptimalBufferDuration() {
    if (_isLowEndDevice) {
      return const Duration(seconds: 3); // Smaller buffer for low-end devices
    }
    return const Duration(seconds: 10); // Larger buffer for better devices
  }

  // Get optimal video quality settings
  static Map<String, dynamic> getOptimalVideoSettings() {
    return {
      'autoPlay': !_isLowEndDevice, // Disable autoplay on low-end devices
      'looping': false,
      'showControls': true,
      'autoDetectFullscreenDevice': !_isLowEndDevice,
      'autoDetectFullscreenAspectRatio': !_isLowEndDevice,
      'handleLifecycle': true, // Always handle lifecycle for performance
      'expandToFill': true,
      'fit': BoxFit.contain,
      'placeholder': _isLowEndDevice, // Show placeholder on low-end devices
    };
  }

  // Get animation duration based on device performance
  static Duration getAnimationDuration() {
    if (_isLowEndDevice) {
      return const Duration(
        milliseconds: 150,
      ); // Faster animations on low-end devices
    }
    return const Duration(milliseconds: 300); // Normal animations
  }

  // Get slider update frequency
  static Duration getSliderUpdateInterval() {
    if (_isLowEndDevice) {
      return const Duration(
        milliseconds: 500,
      ); // Less frequent updates on low-end devices
    }
    return const Duration(
      milliseconds: 200,
    ); // More frequent updates on better devices
  }

  // OPTIMIZED PLAYER CONFIGURATION

  static String getOptimalVideoSync() {
    // 'display-resample' is very CPU intensive. 'audio' is efficient.
    return 'audio';
  }

  static bool shouldEnableInterpolation() {
    // Interpolation is GPU/CPU intensive. Disable for mobile.
    return false;
  }

  static String getOptimalDemuxerCache() {
    if (_isLowEndDevice) {
      return '64M'; // Increased to standard to prevent starvation on 4K
    }
    return '128M';
  }

  static String getOptimalHardwareDecoder() {
    if (_forcedHwDec == false) return 'no';
    return Platform.isAndroid ? 'mediacodec' : 'auto';
  }

  static String getSkipLoopFilter() {
    if (_forcedSkipLoopFilter == true) return 'all';
    if (_forcedSkipLoopFilter == false) return 'no';

    if (_isLowEndDevice) {
      return 'all'; // Skip ALL deblocking (fastest, slight visual blocking)
    }
    return 'no';
  }

  static int getOptimalThreads() {
    // MediaTek P35 is Octa-core.
    // Using too many threads can cause context switching overhead.
    // 4 is a safe sweet spot for mobile SW decoding.
    if (_isLowEndDevice) {
      return 4;
    }
    return 0; // Auto
  }

  // EXPLICIT OPTIMIZATION PROFILES

  /// Flags specifically for Software Decoding (CPU)
  static Map<String, String> getSoftwareDecoderFlags() {
    return {
      'hwdec': 'no',
      'vd-lavc-threads': getOptimalThreads().toString(),
      'sws-scaler': 'fast-bilinear', // Fastest scaling algorithm
      'vd-lavc-skiploopfilter': 'all', // Crucial for SW decoding speed
      'framedrop': 'decoder', // Aggressively drop frames at decoder level
      'video-sync': 'audio',
    };
  }

  /// Flags specifically for Hardware Decoding (GPU)
  static Map<String, String> getHardwareDecoderFlags() {
    return {
      'hwdec': platformHardwareDecoder,
      'vd-lavc-threads': '0', // HW decoders usually manage their own threads
      'vd-lavc-skiploopfilter': getSkipLoopFilter(),
      'framedrop': isFrameDropEnabled
          ? 'vo'
          : 'no', // Drop at video output if enabled
      'video-sync': 'audio',
      'opengl-glfinish': 'no',
    };
  }

  static String get platformHardwareDecoder {
    if (_forcedHwDec == false) return 'no';
    // Use 'mediacodec' (Zero-Copy) for best performance on Android
    return Platform.isAndroid ? 'mediacodec' : 'auto';
  }
}
