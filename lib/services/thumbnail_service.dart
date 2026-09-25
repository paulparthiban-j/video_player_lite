import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:video_thumbnail/video_thumbnail.dart';

class ThumbnailService {
  static final Map<String, String> _thumbnailCache = {};
  static Directory? _thumbnailDir;
  static const int _maxCacheSizeBytes = 200 * 1024 * 1024; // 200MB
  static final List<String> _queue = [];
  static bool _isProcessingQueue = false;
  static Future<void>? _queueRunner;
  static DateTime? _lastCleanupAt;
  static Timer? _pauseTimer;
  static const int _batchLimit = 30;
  static const Duration _cleanupInterval = Duration(hours: 12);
  static const int _thumbnailQuality = 60;
  static const int _thumbnailMaxWidth = 320;
  static const int _thumbnailMaxHeight = 180;
  static const Duration _queueSpacing = Duration(milliseconds: 120);
  static bool _isPaused = false;

  static Future<void> initialize() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _thumbnailDir = Directory(path.join(appDir.path, 'thumbnails'));
      if (!await _thumbnailDir!.exists()) {
        await _thumbnailDir!.create(recursive: true);
      }
      await _enforceCacheLimit();
    } catch (e) {
      debugPrint('Error initializing thumbnail service: $e');
    }
  }

  static String _getThumbnailFileName(String videoPath) {
    final bytes = utf8.encode(videoPath);
    final digest = sha256.convert(bytes);
    return '${digest.toString()}.jpg';
  }

  static Future<String?> getThumbnailPath(String videoPath) async {
    if (_thumbnailDir == null) {
      await initialize();
    }

    final fileName = _getThumbnailFileName(videoPath);
    final thumbnailPath = path.join(_thumbnailDir!.path, fileName);

    if (await File(thumbnailPath).exists()) {
      return thumbnailPath;
    }

    return null;
  }

  static Future<String?> generateThumbnail(String videoPath) async {
    try {
      if (_thumbnailDir == null) {
        await initialize();
      }

      final cachedPath = await getThumbnailPath(videoPath);
      if (cachedPath != null) {
        return cachedPath;
      }

      if (!await File(videoPath).exists()) {
        return null;
      }

      final fileName = _getThumbnailFileName(videoPath);
      final thumbnailPath = path.join(_thumbnailDir!.path, fileName);

      final generatedPath = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: _thumbnailDir!.path,
        imageFormat: ImageFormat.JPEG,
        quality: _thumbnailQuality,
        maxWidth: _thumbnailMaxWidth,
        maxHeight: _thumbnailMaxHeight,
      );

      if (generatedPath != null && await File(generatedPath).exists()) {
        if (generatedPath != thumbnailPath) {
          await File(generatedPath).rename(thumbnailPath);
        }
        _thumbnailCache[videoPath] = thumbnailPath;
        await _enforceCacheLimit();
        return thumbnailPath;
      }

      return null;
    } catch (e) {
      debugPrint('Error generating thumbnail for $videoPath: $e');
      return null;
    }
  }

  static Future<void> generateThumbnailsBatch(List<String> videoPaths) async {
    final limited = videoPaths.take(_batchLimit).toList();
    for (final videoPath in limited) {
      if (_queue.contains(videoPath)) continue;
      _queue.add(videoPath);
    }
    unawaited(_runQueue());
  }

  static void setPaused(bool paused) {
    _pauseTimer?.cancel();
    _isPaused = paused;
  }

  static void setPausedDebounced(
    bool paused, {
    Duration delay = const Duration(milliseconds: 140),
  }) {
    if (paused) {
      setPaused(true);
      return;
    }
    _pauseTimer?.cancel();
    _pauseTimer = Timer(delay, () {
      setPaused(false);
    });
  }

  static Future<void> clearCache() async {
    try {
      if (_thumbnailDir != null && await _thumbnailDir!.exists()) {
        await _thumbnailDir!.delete(recursive: true);
        await _thumbnailDir!.create(recursive: true);
      }
      _thumbnailCache.clear();
    } catch (e) {
      debugPrint('Error clearing thumbnail cache: $e');
    }
  }

  static Future<void> deleteThumbnail(String videoPath) async {
    try {
      final thumbnailPath = await getThumbnailPath(videoPath);
      if (thumbnailPath != null) {
        final file = File(thumbnailPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      _thumbnailCache.remove(videoPath);
    } catch (e) {
      debugPrint('Error deleting thumbnail: $e');
    }
  }

  static Future<void> _enforceCacheLimit() async {
    if (_thumbnailDir == null) {
      await initialize();
    }
    final dir = _thumbnailDir;
    if (dir == null) return;
    final now = DateTime.now();
    if (_lastCleanupAt != null &&
        now.difference(_lastCleanupAt!) < _cleanupInterval) {
      return;
    }
    _lastCleanupAt = now;

    final files = await dir
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    if (files.isEmpty) return;

    final entries = <_ThumbnailEntry>[];
    int totalSize = 0;
    for (final file in files) {
      try {
        final stat = await file.stat();
        totalSize += stat.size;
        entries.add(
          _ThumbnailEntry(file: file, size: stat.size, modified: stat.modified),
        );
      } catch (_) {}
    }

    if (totalSize <= _maxCacheSizeBytes) return;

    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (totalSize <= _maxCacheSizeBytes) break;
      try {
        await entry.file.delete();
        totalSize -= entry.size;
      } catch (_) {}
    }
  }

  static Future<void> _runQueue() {
    if (_isProcessingQueue && _queueRunner != null) return _queueRunner!;
    _queueRunner = _processQueue();
    return _queueRunner!;
  }

  static Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    try {
      while (_queue.isNotEmpty) {
        if (_isPaused) {
          await Future.delayed(_queueSpacing);
          continue;
        }
        final next = _queue.removeAt(0);
        try {
          await generateThumbnail(next);
        } catch (e) {
          debugPrint('Error generating thumbnail for $next: $e');
        }
        await Future.delayed(_queueSpacing);
      }
    } finally {
      _isProcessingQueue = false;
      _queueRunner = null;
      await _enforceCacheLimit();
    }
  }
}

class _ThumbnailEntry {
  final File file;
  final int size;
  final DateTime modified;

  const _ThumbnailEntry({
    required this.file,
    required this.size,
    required this.modified,
  });
}
