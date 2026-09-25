import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import '../core/video_player_controller.dart';
import 'video_format_service.dart';

class VideoFile {
  final String path;
  final String name;
  final int size;
  final DateTime lastModified;
  final String? thumbnail;
  final String format;
  final bool isSupported;
  final String quality;
  final MediaType type;

  VideoFile({
    required this.path,
    required this.name,
    required this.size,
    required this.lastModified,
    this.thumbnail,
    String? format,
    bool? isSupported,
    String? quality,
    MediaType? type,
  }) : format = format ?? VideoFormatService.getFormatName(path),
       isSupported = isSupported ?? VideoFormatService.isFileSupported(path),
       quality = quality ?? VideoFormatService.getQualityIndicator(path),
       type =
           type ??
           (VideoFormatService.getFormatByPath(path)?.type ?? MediaType.video);

  bool get isAudio => type == MediaType.audio;
  bool get isStreaming => type == MediaType.streaming;

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get displayName {
    final nameWithoutExt = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    return nameWithoutExt.length > 30
        ? '${nameWithoutExt.substring(0, 30)}...'
        : nameWithoutExt;
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'name': name,
      'size': size,
      'lastModified': lastModified.toIso8601String(),
      'thumbnail': thumbnail,
      'format': format,
      'isSupported': isSupported,
      'quality': quality,
      'type': type.index,
    };
  }

  factory VideoFile.fromJson(Map<String, dynamic> json) {
    return VideoFile(
      path: json['path'],
      name: json['name'],
      size: json['size'],
      lastModified: DateTime.parse(json['lastModified']),
      thumbnail: json['thumbnail'],
      format: json['format'],
      isSupported: json['isSupported'],
      quality: json['quality'],
      type: json['type'] != null
          ? MediaType.values[json['type']]
          : MediaType.video,
    );
  }
}

class FileBrowserService {
  static const List<String> supportedVideoExtensions = [
    'mp4',
    'avi',
    'mkv',
    'mov',
    'wmv',
    'flv',
    'webm',
    'm4v',
    '3gp',
    'ogv',
    'mpg',
    'mpeg',
    'ts',
    'mts',
    'm2ts',
    'vob',
    'f4v',
    'asf',
    'rm',
    'rmvb',
    'mp3',
    'wav',
    'm4a',
    'ogg',
    'flac',
    'aac',
    'm3u8',
    'm3u',
  ];

  static List<String> getAllSupportedExtensions() {
    return VideoFormatService.getSupportedExtensions();
  }

  static Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      // Android 13+ should use media-specific permissions.
      final videoStatus = await Permission.videos.request();
      final audioStatus = await Permission.audio.request();
      if (videoStatus.isGranted || audioStatus.isGranted) {
        return true;
      }
      // Fallback for Android 12 and below.
      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    } else if (Platform.isIOS) {
      final photosPermission = await Permission.photos.request();
      return photosPermission.isGranted;
    }
    return true;
  }

  static Future<List<String>> getStorageDirectories() async {
    final List<String> directories = [];

    if (Platform.isAndroid) {
      try {
        // Common Android storage paths
        final commonPaths = [
          '/storage/emulated/0',
          '/storage/sdcard0',
          '/storage/sdcard1',
          '/sdcard',
          '/mnt/sdcard',
        ];

        for (String path in commonPaths) {
          if (Directory(path).existsSync()) {
            if (!directories.contains(path)) {
              directories.add(path);
            }
          }
        }

        // Try to get external storage directories as fallback
        try {
          final externalStorage = await getExternalStorageDirectories();
          if (externalStorage != null) {
            for (var dir in externalStorage) {
              final path = dir.path;
              // Extract root directories (remove /Android/data/... part)
              final segments = path.split('/');
              if (segments.length > 1) {
                final rootPath = '/${segments[1]}';
                if (!directories.contains(rootPath) &&
                    Directory(rootPath).existsSync()) {
                  directories.add(rootPath);
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Error getting external storage directories: $e');
        }
      } catch (e) {
        debugPrint('Error getting Android storage directories: $e');
      }
    } else if (Platform.isIOS) {
      try {
        final documentsDir = await getApplicationDocumentsDirectory();
        directories.add(documentsDir.path);
      } catch (e) {
        debugPrint('Error getting iOS storage directory: $e');
      }
    }

    return directories;
  }

  static Future<List<VideoFile>> getVideoFilesInDirectory(
    String directoryPath,
  ) async {
    final List<VideoFile> videoFiles = [];

    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        return videoFiles;
      }

      await for (final entity in directory.list()) {
        try {
          if (entity is File) {
            final file = entity;
            final extension = file.path.split('.').last.toLowerCase();

            if (supportedVideoExtensions.contains(extension) ||
                VideoFormatService.isFormatSupported(extension)) {
              final stat = await file.stat();
              videoFiles.add(
                VideoFile(
                  path: file.path,
                  name: file.uri.pathSegments.last,
                  size: stat.size,
                  lastModified: stat.modified,
                ),
              );
            }
          }
        } catch (e) {
          debugPrint('Error processing file ${entity.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('Error scanning directory $directoryPath: $e');
    }

    // Sort by name
    videoFiles.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    return videoFiles;
  }

  static Future<List<VideoFile>> searchVideoFiles(String searchTerm) async {
    List<VideoFile> allVideos = [];

    try {
      final storageDirectories = await getStorageDirectories();

      for (String directory in storageDirectories) {
        final videos = await getVideoFilesInDirectory(directory);
        allVideos.addAll(videos);
      }

      // Filter by search term
      if (searchTerm.isNotEmpty) {
        allVideos = allVideos
            .where(
              (video) =>
                  video.name.toLowerCase().contains(searchTerm.toLowerCase()),
            )
            .toList();
      }
    } catch (e) {
      debugPrint('Error searching video files: $e');
    }

    return allVideos;
  }

  static Future<List<VideoFile>> getRecentVideos({int limit = 20}) async {
    List<VideoFile> allVideos = [];

    try {
      final storageDirectories = await getStorageDirectories();

      for (String directory in storageDirectories) {
        final videos = await getVideoFilesInDirectory(directory);
        allVideos.addAll(videos);
      }

      // Sort by last modified date (most recent first)
      allVideos.sort((a, b) => b.lastModified.compareTo(a.lastModified));

      // Limit results
      if (allVideos.length > limit) {
        allVideos = allVideos.take(limit).toList();
      }
    } catch (e) {
      debugPrint('Error getting recent videos: $e');
    }

    return allVideos;
  }

  static bool isVideoFile(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    return supportedVideoExtensions.contains(extension) ||
        VideoFormatService.isFormatSupported(extension);
  }

  static String getFileIcon(
    String extension, [
    MediaType type = MediaType.video,
  ]) {
    if (type == MediaType.audio) {
      return '🎵';
    }
    if (type == MediaType.streaming) {
      return '📡';
    }
    switch (extension.toLowerCase()) {
      case 'mp4':
        return '🎬';
      case 'avi':
        return '📹';
      case 'mkv':
        return '🎥';
      case 'mov':
        return '📱';
      case 'wmv':
        return '🖥️';
      case 'flv':
        return '🌐';
      case 'webm':
        return '🌍';
      case 'm3u8':
        return '📡';
      default:
        return '📺';
    }
  }
}
