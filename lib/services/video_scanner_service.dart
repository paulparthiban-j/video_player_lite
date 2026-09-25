import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'file_browser_service.dart';
import 'scan_directory_service.dart';
import '../core/video_player_controller.dart';

class VideoScannerService {
  static const List<String> videoExtensions = [
    'mp4',
    'avi',
    'mov',
    'mkv',
    'wmv',
    'flv',
    'webm',
    'm4v',
    '3gp',
    'mpg',
    'mpeg',
    'ts',
    'mts',
    'vob',
    'f4v',
    'asf',
    'rm',
    'rmvb',
  ];

  static const List<String> audioExtensions = [
    'mp3',
    'wav',
    'm4a',
    'ogg',
    'flac',
    'aac',
    'wma',
    'aiff',
    'au',
    'ra',
    'amr',
    'ac3',
    'dts',
    'm4p',
    'm4b',
    'm4r',
    'opus',
    'webm',
    'mp4a',
  ];

  static const String _cacheKey = 'scanned_videos_cache';

  /// Scans for videos in a separate isolate to prevent UI jank
  static Future<List<VideoFile>> scanAllVideos({bool useCache = true}) async {
    if (useCache) {
      final cached = await getCachedVideos();
      if (cached.isNotEmpty) return cached;
    }

    // Check permissions on the main thread
    if (!await _checkPermissions()) {
      debugPrint('Storage permission denied');
      return [];
    }

    List<VideoFile> videos = [];
    if (Platform.isAndroid) {
      // Use MediaStore via photo_manager for Android 10+ scoped storage
      videos = await _scanAndroidMediaStoreVideos();
    } else {
      // Get directories on the main thread
      final directories = await _getAvailableDirectories();

      // Run scanning in isolate
      videos = await compute(_scanInIsolate, directories);
    }

    // Save to cache
    await saveVideosToCache(videos);

    return videos;
  }

  static Future<List<VideoFile>> getCachedVideos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString(_cacheKey);
      if (jsonStr == null) return [];

      final List<dynamic> list = jsonDecode(jsonStr);
      return list.map((item) => VideoFile.fromJson(item)).toList();
    } catch (e) {
      debugPrint('Error loading cached videos: $e');
      return [];
    }
  }

  static Future<void> saveVideosToCache(List<VideoFile> videos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String jsonStr = jsonEncode(videos.map((v) => v.toJson()).toList());
      await prefs.setString(_cacheKey, jsonStr);
    } catch (e) {
      debugPrint('Error saving videos to cache: $e');
    }
  }

  static Future<void> removeFromCache(String filePath) async {
    try {
      final cached = await getCachedVideos();
      if (cached.isEmpty) return;

      final updated = cached.where((v) => v.path != filePath).toList();
      if (updated.length == cached.length) return;

      await saveVideosToCache(updated);
    } catch (e) {
      debugPrint('Error removing cached video: $e');
    }
  }

  static Future<bool> _checkPermissions() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final permission = await PhotoManager.requestPermissionExtend();
      return permission.isAuth || permission.hasAccess;
    }
    if (Platform.isAndroid) {
      if (await Permission.storage.request().isGranted) {
        return true;
      }
    }
    return true;
  }

  static Future<List<String>> _getAvailableDirectories() async {
    try {
      // Use the new scan directory service to get all directories
      return await ScanDirectoryService.getAllScanDirectories();
    } catch (e) {
      debugPrint('Error getting directories: $e');
      // Fallback to basic directories
      final Set<String> directories = {};
      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final path = extDir.path;
          final androidIndex = path.indexOf('/Android');
          if (androidIndex != -1) {
            directories.add(path.substring(0, androidIndex));
          } else {
            directories.add(path);
          }
        }
      }
      return directories.toList();
    }
  }

  /// Top-level function for isolate
  static Future<List<VideoFile>> _scanInIsolate(
    List<String> directories,
  ) async {
    final List<VideoFile> allVideos = [];
    final Set<String> processedPaths = {};
    final List<String> excludedPathFragments = [
      '${Platform.pathSeparator}Android${Platform.pathSeparator}',
      '${Platform.pathSeparator}android${Platform.pathSeparator}',
      '${Platform.pathSeparator}cache${Platform.pathSeparator}',
      '${Platform.pathSeparator}Cache${Platform.pathSeparator}',
      '${Platform.pathSeparator}tmp${Platform.pathSeparator}',
      '${Platform.pathSeparator}Temp${Platform.pathSeparator}',
      '${Platform.pathSeparator}.thumbnails${Platform.pathSeparator}',
      '${Platform.pathSeparator}thumbnails${Platform.pathSeparator}',
    ];

    for (final dirPath in directories) {
      try {
        final directory = Directory(dirPath);
        if (!directory.existsSync()) continue;

        // Recursive scan
        // Note: listSync with recursive: true can be slow on huge trees,
        // but since we stand in an isolate, we won't freeze UI.
        // However, we should be careful about memory if there are million files.
        // Using sync iterator is fine in isolate.

        final entities = directory.listSync(
          recursive: true,
          followLinks: false,
        );

        for (final entity in entities) {
          if (entity is File) {
            final path = entity.path;
            bool skip = false;
            for (final fragment in excludedPathFragments) {
              if (path.contains(fragment)) {
                skip = true;
                break;
              }
            }
            if (skip) continue;
            final name = path.split(Platform.pathSeparator).last;
            final extension = name.contains('.')
                ? name.split('.').last.toLowerCase()
                : '';

            final allExtensions = videoExtensions; // Only scan for video files
            if (allExtensions.contains(extension)) {
              // Filter small files (thumbnails/ads)
              try {
                final stat = entity.statSync();
                final minSize = 1024 * 1024; // 1MB minimum for video files

                if (stat.size > minSize) {
                  if (!processedPaths.contains(path)) {
                    processedPaths.add(path);
                    allVideos.add(
                      VideoFile(
                        path: path,
                        name: name,
                        size: stat.size,
                        lastModified: stat.modified,
                      ),
                    );
                  }
                }
              } catch (e) {
                // ignore access errors
              }
            }
          }
        }
      } catch (e) {
        // Start next dir
      }
    }

    // Sort by name
    allVideos.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    return allVideos;
  }

  static Future<List<VideoFile>> _scanAndroidMediaStoreVideos() async {
    final List<VideoFile> allVideos = [];
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      hasAll: true,
      onlyAll: true,
    );

    if (paths.isEmpty) return allVideos;

    final path = paths.first;
    final total = await path.assetCountAsync;

    const pageSize = 200;
    final totalPages = (total / pageSize).ceil();

    for (int page = 0; page < totalPages; page++) {
      final assets = await path.getAssetListPaged(page: page, size: pageSize);
      for (final asset in assets) {
        final file = await asset.file;
        if (file == null) continue;
        allVideos.add(
          VideoFile(
            path: file.path,
            name: asset.title ?? file.uri.pathSegments.last,
            size: await file.length(),
            lastModified: asset.modifiedDateTime,
            type: MediaType.video,
          ),
        );
      }
      // Yield to UI thread between pages to avoid long startup stalls.
      await Future.delayed(const Duration(milliseconds: 4));
    }

    // Sort by name
    allVideos.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    return allVideos;
  }
}
