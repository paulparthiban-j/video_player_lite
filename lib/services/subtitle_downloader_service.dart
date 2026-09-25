import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class SubtitleSearchResult {
  final String id;
  final String language;
  final String languageCode;
  final String name;
  final String fileName;
  final int downloads;
  final double rating;
  final String format;
  final int cdCount;
  final bool isHearingImpaired;

  SubtitleSearchResult({
    required this.id,
    required this.language,
    required this.languageCode,
    required this.name,
    required this.fileName,
    required this.downloads,
    required this.rating,
    required this.format,
    required this.cdCount,
    required this.isHearingImpaired,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'language': language,
      'languageCode': languageCode,
      'name': name,
      'fileName': fileName,
      'downloads': downloads,
      'rating': rating,
      'format': format,
      'cdCount': cdCount,
      'isHearingImpaired': isHearingImpaired,
    };
  }

  factory SubtitleSearchResult.fromJson(Map<String, dynamic> json) {
    return SubtitleSearchResult(
      id: json['id'],
      language: json['language'],
      languageCode: json['languageCode'],
      name: json['name'],
      fileName: json['fileName'],
      downloads: json['downloads'],
      rating: json['rating'].toDouble(),
      format: json['format'],
      cdCount: json['cdCount'],
      isHearingImpaired: json['isHearingImpaired'],
    );
  }
}

class SubtitleDownloadProgress {
  final double progress;
  final String? currentOperation;
  final int? downloadedBytes;
  final int? totalBytes;

  SubtitleDownloadProgress({
    required this.progress,
    this.currentOperation,
    this.downloadedBytes,
    this.totalBytes,
  });
}

class SubtitleDownloaderService {
  static const String _opensubtitlesBaseUrl = 'https://rest.opensubtitles.org';
  static const String _userAgent = 'ParthiPlay v1.0';
  static StreamController<SubtitleDownloadProgress>? _progressController;

  static Stream<SubtitleDownloadProgress> get downloadProgressStream =>
      _progressController?.stream ?? Stream.empty();

  static Future<List<SubtitleSearchResult>> searchSubtitles({
    required String query,
    String? language,
    String? imdbId,
    int? season,
    int? episode,
    int year = 0,
    int limit = 50,
  }) async {
    try {
      final searchParams = <String, String>{
        'query': query,
        'limit': limit.toString(),
      };

      if (language != null) {
        searchParams['sublanguageid'] = language;
      }

      if (imdbId != null) {
        searchParams['imdbid'] = imdbId;
      }

      if (season != null && episode != null) {
        searchParams['season'] = season.toString();
        searchParams['episode'] = episode.toString();
      }

      if (year > 0) {
        searchParams['year'] = year.toString();
      }

      final uri = Uri.parse(
        '$_opensubtitlesBaseUrl/search',
      ).replace(queryParameters: searchParams);

      final response = await http.get(
        uri,
        headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => _parseSubtitleResult(item)).toList();
      } else {
        debugPrint('OpenSubtitles API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Error searching subtitles: $e');
      return [];
    }
  }

  static Future<List<SubtitleSearchResult>> searchSubtitlesByHash({
    required String movieHash,
    required int fileSizeBytes,
    String? language,
  }) async {
    try {
      final searchParams = <String, String>{
        'moviehash': movieHash,
        'moviebytesize': fileSizeBytes.toString(),
      };

      if (language != null) {
        searchParams['sublanguageid'] = language;
      }

      final uri = Uri.parse(
        '$_opensubtitlesBaseUrl/search',
      ).replace(queryParameters: searchParams);

      final response = await http.get(
        uri,
        headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => _parseSubtitleResult(item)).toList();
      } else {
        debugPrint('OpenSubtitles API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Error searching subtitles by hash: $e');
      return [];
    }
  }

  static Future<String?> downloadSubtitle({
    required String subtitleId,
    required String fileName,
    String? outputDirectory,
    Function(double)? onProgress,
  }) async {
    try {
      _initializeProgressStream();

      // Get download link
      final downloadUri = Uri.parse(
        '$_opensubtitlesBaseUrl/download/$subtitleId',
      );

      final response = await http.get(
        downloadUri,
        headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        debugPrint('Failed to get download link: ${response.statusCode}');
        return null;
      }

      final downloadData = json.decode(response.body);
      final downloadLink = downloadData['link'] as String?;

      if (downloadLink == null) {
        debugPrint('No download link found');
        return null;
      }

      // Download the subtitle file
      final fileResponse = await http.get(
        Uri.parse(downloadLink),
        headers: {'User-Agent': _userAgent},
      );

      if (fileResponse.statusCode != 200) {
        debugPrint(
          'Failed to download subtitle file: ${fileResponse.statusCode}',
        );
        return null;
      }

      // Save to file
      final directory = outputDirectory ?? await _getSubtitleDirectory();
      final outputPath = path.join(directory, fileName);
      final file = File(outputPath);

      final contentLength = fileResponse.bodyBytes.length;
      final sink = file.openWrite();
      sink.add(fileResponse.bodyBytes);
      await sink.close();

      _notifyProgress(
        SubtitleDownloadProgress(
          progress: 1.0,
          currentOperation: 'Complete',
          downloadedBytes: contentLength,
          totalBytes: contentLength,
        ),
      );

      return outputPath;
    } catch (e) {
      debugPrint('Error downloading subtitle: $e');
      _notifyProgress(
        SubtitleDownloadProgress(progress: -1.0, currentOperation: 'Error: $e'),
      );
      return null;
    }
  }

  static Future<String?> downloadAndSaveSubtitle({
    required SubtitleSearchResult subtitle,
    String? outputDirectory,
    Function(double)? onProgress,
  }) async {
    return downloadSubtitle(
      subtitleId: subtitle.id,
      fileName: subtitle.fileName,
      outputDirectory: outputDirectory,
      onProgress: onProgress,
    );
  }

  static Future<String?> downloadBestMatch({
    required String query,
    required String language,
    String? outputDirectory,
    Function(double)? onProgress,
  }) async {
    try {
      final results = await searchSubtitles(
        query: query,
        language: language,
        limit: 10,
      );

      if (results.isEmpty) return null;

      // Sort by rating and downloads
      results.sort((a, b) {
        final scoreA = a.rating * a.downloads;
        final scoreB = b.rating * b.downloads;
        return scoreB.compareTo(scoreA);
      });

      final bestMatch = results.first;
      return await downloadAndSaveSubtitle(
        subtitle: bestMatch,
        outputDirectory: outputDirectory,
        onProgress: onProgress,
      );
    } catch (e) {
      debugPrint('Error downloading best match: $e');
      return null;
    }
  }

  static Future<String?> downloadForVideo({
    required String videoPath,
    String? language,
    String? outputDirectory,
    Function(double)? onProgress,
  }) async {
    try {
      // Try hash-based search first
      final hash = await _calculateMovieHash(videoPath);
      final file = File(videoPath);
      final fileSize = await file.length();

      if (hash != null) {
        final hashResults = await searchSubtitlesByHash(
          movieHash: hash,
          fileSizeBytes: fileSize,
          language: language,
        );

        if (hashResults.isNotEmpty) {
          final bestMatch = hashResults.first;
          return await downloadAndSaveSubtitle(
            subtitle: bestMatch,
            outputDirectory: outputDirectory,
            onProgress: onProgress,
          );
        }
      }

      // Fallback to filename-based search
      final fileName = path.basenameWithoutExtension(videoPath);
      return await downloadBestMatch(
        query: fileName,
        language: language ?? 'en',
        outputDirectory: outputDirectory,
        onProgress: onProgress,
      );
    } catch (e) {
      debugPrint('Error downloading subtitle for video: $e');
      return null;
    }
  }

  static Future<String?> _calculateMovieHash(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final bytes = await file.openRead(0, 64 * 1024).toList(); // First 64KB
      final data = bytes.expand((e) => e).toList();

      if (data.length < 64 * 1024) return null;

      // OpenSubtitles hash algorithm
      final hash = _calculateOpenSubtitlesHash(data, await file.length());
      return hash.toString();
    } catch (e) {
      debugPrint('Error calculating movie hash: $e');
      return null;
    }
  }

  static int _calculateOpenSubtitlesHash(List<int> data, int fileSize) {
    try {
      // Read first and last 64KB
      final first64KB = data.take(64 * 1024).toList();
      final last64KB = data
          .skip(data.length - 64 * 1024)
          .take(64 * 1024)
          .toList();

      // Combine the data
      final hashData = [...first64KB, ...last64KB];

      // Calculate hash
      int hash = fileSize;
      for (int i = 0; i < hashData.length; i += 8) {
        int chunk = 0;
        for (int j = 0; j < 8 && i + j < hashData.length; j++) {
          chunk |= hashData[i + j] << (8 * j);
        }
        hash += chunk;
      }

      return hash & 0xFFFFFFFF;
    } catch (e) {
      debugPrint('Error in hash calculation: $e');
      return 0;
    }
  }

  static Future<String> _getSubtitleDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final subtitleDir = Directory(path.join(directory.path, 'subtitles'));

    if (!await subtitleDir.exists()) {
      await subtitleDir.create(recursive: true);
    }

    return subtitleDir.path;
  }

  static SubtitleSearchResult _parseSubtitleResult(dynamic item) {
    return SubtitleSearchResult(
      id: item['IDSubtitleFile']?.toString() ?? '',
      language: item['LanguageName']?.toString() ?? 'Unknown',
      languageCode: item['SubLanguageID']?.toString() ?? 'unknown',
      name: item['MovieName']?.toString() ?? 'Unknown',
      fileName: item['SubFileName']?.toString() ?? 'subtitle.srt',
      downloads: int.tryParse(item['SubDownloadsCnt']?.toString() ?? '0') ?? 0,
      rating: double.tryParse(item['SubRating']?.toString() ?? '0.0') ?? 0.0,
      format: item['SubFormat']?.toString() ?? 'srt',
      cdCount: int.tryParse(item['SubSumCD']?.toString() ?? '1') ?? 1,
      isHearingImpaired: item['SubHearingImpaired'] == '1',
    );
  }

  static void _initializeProgressStream() {
    _progressController?.close();
    _progressController =
        StreamController<SubtitleDownloadProgress>.broadcast();
  }

  static void _notifyProgress(SubtitleDownloadProgress progress) {
    _progressController?.add(progress);
  }

  static Map<String, String> getSupportedLanguages() {
    return {
      'en': 'English',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'it': 'Italian',
      'pt': 'Portuguese',
      'ru': 'Russian',
      'ja': 'Japanese',
      'ko': 'Korean',
      'zh': 'Chinese',
      'ar': 'Arabic',
      'hi': 'Hindi',
      'th': 'Thai',
      'vi': 'Vietnamese',
      'nl': 'Dutch',
      'sv': 'Swedish',
      'no': 'Norwegian',
      'da': 'Danish',
      'fi': 'Finnish',
      'pl': 'Polish',
      'tr': 'Turkish',
      'el': 'Greek',
      'he': 'Hebrew',
      'cs': 'Czech',
      'hu': 'Hungarian',
      'ro': 'Romanian',
      'bg': 'Bulgarian',
      'hr': 'Croatian',
      'sr': 'Serbian',
      'sk': 'Slovak',
      'sl': 'Slovenian',
      'et': 'Estonian',
      'lv': 'Latvian',
      'lt': 'Lithuanian',
      'uk': 'Ukrainian',
      'mk': 'Macedonian',
      'sq': 'Albanian',
      'mt': 'Maltese',
      'cy': 'Welsh',
      'ga': 'Irish',
      'gd': 'Scottish Gaelic',
      'eu': 'Basque',
      'ca': 'Catalan',
      'gl': 'Galician',
      'is': 'Icelandic',
      'ms': 'Malay',
      'id': 'Indonesian',
      'tl': 'Filipino',
      'sw': 'Swahili',
      'af': 'Afrikaans',
      'zu': 'Zulu',
      'xh': 'Xhosa',
      'st': 'Sesotho',
      'tn': 'Setswana',
    };
  }

  static Future<List<String>> getDownloadedSubtitles() async {
    try {
      final directory = await _getSubtitleDirectory();
      final dir = Directory(directory);

      if (!await dir.exists()) return [];

      final files = await dir
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();

      return files.map((file) => file.path).toList();
    } catch (e) {
      debugPrint('Error getting downloaded subtitles: $e');
      return [];
    }
  }

  static Future<bool> deleteDownloadedSubtitle(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error deleting downloaded subtitle: $e');
      return false;
    }
  }

  static Future<void> dispose() async {
    unawaited(_progressController?.close());
    _progressController = null;
  }
}
