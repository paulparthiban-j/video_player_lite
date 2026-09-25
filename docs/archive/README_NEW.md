# Video Player Lite

A high-performance, optimized video player for Flutter applications, specifically designed for low-end Android and iOS devices while maintaining modern features and excellent user experience.

## Features

### 🚀 Performance Optimizations
- **Hardware Acceleration**: Leverages device GPU for smooth playback
- **Memory Management**: Intelligent caching and memory optimization
- **Adaptive Quality**: Automatically adjusts video quality based on device capabilities
- **Low-End Device Detection**: Identifies and optimizes for older devices

### 🎬 Video Playback
- **Multiple Formats**: Support for MP4, AVI, MOV, and other popular formats
- **Network Streaming**: Play videos from URLs with buffering optimization
- **Local Files**: Access and play videos from device storage
- **Auto-Detect Orientation**: Seamless landscape/portrait switching

### 🎮 Modern Controls
- **Gesture Controls**: 
  - Tap to play/pause
  - Double tap for quick actions
  - Horizontal swipe for seeking
  - Vertical swipe for volume/brightness
- **Touch-Friendly UI**: Large, accessible controls
- **Customizable Themes**: Dark/light mode support

### 📱 Device Compatibility
- **Android**: API 21+ (Android 5.0+) with special optimizations for API < 26
- **iOS**: iOS 11+ with enhanced performance for older models
- **Low-End Devices**: Optimized for devices with < 2GB RAM
- **Tablets**: Responsive design for all screen sizes

## Quick Start

### Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  flutter:
    sdk: flutter
  video_player: ^2.8.6
  chewie: ^1.7.4
  file_picker: ^8.0.3
  device_info_plus: ^10.1.0
  permission_handler: ^11.3.1
```

### Basic Usage

```dart
import 'package:flutter/material.dart';
import 'package:video_player_lite/widgets/optimized_video_player.dart';

class MyVideoPlayer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OptimizedVideoPlayer(
        videoUrl: 'https://example.com/video.mp4',
        autoPlay: false,
        looping: false,
        showControls: true,
      ),
    );
  }
}
```

## Advanced Features

### Performance Settings

The app automatically detects device capabilities and adjusts settings:

```dart
// Check if device is low-end
bool isLowEnd = PerformanceService.isLowEndDevice;

// Get optimal settings
var settings = PerformanceService.getOptimalVideoSettings();
```

### Memory Management

```dart
// Initialize memory manager
await MemoryManager.initialize();

// Check memory status
bool isLowMemory = MemoryManager.isLowMemory();

// Get cache size
int maxCache = MemoryManager.getMaxCacheSize();
```

### Gesture Controls

Built-in gesture support for enhanced user experience:

- **Single Tap**: Toggle play/pause
- **Double Tap**: Quick play/pause
- **Horizontal Drag**: Seek forward/backward
- **Left Vertical Drag**: Adjust brightness
- **Right Vertical Drag**: Adjust volume

## Permissions

### Android

Add these permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

### iOS

Add these to `ios/Runner/Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>This app needs access to photo library to select video files.</string>
<key>NSDocumentsFolderUsageDescription</key>
<string>This app needs access to documents folder to load video files.</string>
```

## Architecture

### Core Components

- **PerformanceService**: Device capability detection and optimization
- **MemoryManager**: Memory monitoring and cache management
- **OptimizedVideoPlayer**: Main video player widget with hardware acceleration
- **GestureControls**: Touch gesture handling system
- **VideoPlayerScreen**: Main UI screen with file/network support

### Performance Optimizations

1. **Hardware Acceleration**: Uses device GPU for video decoding
2. **Adaptive Buffering**: Smaller buffers for low-end devices
3. **Memory Management**: Intelligent cache size based on available memory
4. **UI Optimization**: Reduced animations on low-end devices
5. **Background Processing**: Efficient video loading and processing

## Supported Formats

- **Video**: MP4, AVI, MOV, MKV, WebM
- **Codecs**: H.264, H.265, VP8, VP9
- **Streaming**: HTTP, HTTPS, HLS (limited)
- **Subtitles**: SRT, ASS (planned feature)

## Device Support

### Android
- ✅ Android 5.0+ (API 21+)
- ✅ Special optimization for Android < 8.0
- ✅ Hardware acceleration on supported devices
- ✅ Landscape orientation support

### iOS
- ✅ iOS 11+ 
- ✅ Enhanced performance for iPhone 6s and older
- ✅ iPad support with responsive design
- ✅ Background playback support

## Troubleshooting

### Common Issues

1. **Video not playing**: Check file format and network connectivity
2. **Poor performance**: App automatically detects and optimizes for low-end devices
3. **Storage permission**: Ensure proper permissions are granted
4. **Network issues**: Check internet connection for streaming

### Performance Tips

- Use Wi-Fi for streaming large videos
- Close other apps on low-end devices
- Ensure sufficient storage space for caching
- Update to latest app version for optimizations

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Roadmap

- [ ] Subtitle support (SRT, ASS)
- [ ] Picture-in-Picture mode
- [ ] Audio track selection
- [ ] Video quality selector
- [ ] Playlist support
- [ ] Casting to TV devices
- [ ] Video recording capabilities

---

**Video Player Lite** - Optimized for performance, designed for everyone.
