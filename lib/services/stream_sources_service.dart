import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StreamSource {
  final String title;
  final String url;
  final bool isLive;

  const StreamSource({
    required this.title,
    required this.url,
    required this.isLive,
  });

  factory StreamSource.fromJson(Map<String, dynamic> json) {
    return StreamSource(
      title: json['title']?.toString().trim().isNotEmpty == true
          ? json['title'].toString()
          : 'Untitled Stream',
      url: json['url']?.toString() ?? '',
      isLive: json['isLive'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'isLive': isLive,
  };
}

class StreamSourcesService {
  static const String _customStreamsKey = 'custom_streams';

  static Future<List<StreamSource>> loadDefaultStreams() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/streams.json');
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((item) => StreamSource.fromJson(item as Map<String, dynamic>))
          .where((stream) => stream.url.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<StreamSource>> loadCustomStreams() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_customStreamsKey);
      if (jsonStr == null || jsonStr.trim().isEmpty) {
        return [];
      }

      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((item) => StreamSource.fromJson(item as Map<String, dynamic>))
          .where((stream) => stream.url.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<StreamSource>> loadAllStreams() async {
    final defaults = await loadDefaultStreams();
    final custom = await loadCustomStreams();

    final existing = <String>{};
    final merged = <StreamSource>[];
    for (final stream in [...defaults, ...custom]) {
      final key = stream.url.trim();
      if (key.isEmpty || existing.contains(key)) continue;
      existing.add(key);
      merged.add(stream);
    }

    return merged;
  }

  static Future<void> addCustomStream(StreamSource stream) async {
    final url = stream.url.trim();
    if (url.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final current = await loadCustomStreams();

    final exists = current.any((s) => s.url.trim() == url);
    if (!exists) {
      current.add(stream);
      await prefs.setString(
        _customStreamsKey,
        jsonEncode(current.map((s) => s.toJson()).toList()),
      );
    }
  }

  static Future<void> removeCustomStream(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadCustomStreams();
    final updated = current.where((s) => s.url.trim() != url.trim()).toList();
    await prefs.setString(
      _customStreamsKey,
      jsonEncode(updated.map((s) => s.toJson()).toList()),
    );
  }
}
