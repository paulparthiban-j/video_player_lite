import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/security/vault_crypto.dart';

/// Serves encrypted vault videos to the player over loopback HTTP, decrypting
/// on the fly so plaintext never touches the disk.
///
/// * Binds to 127.0.0.1 only, on an ephemeral port.
/// * Every registered file gets an unguessable 256-bit token in its URL;
///   requests without a live token get 404, so other apps on the device
///   cannot enumerate or fetch vault content.
/// * Honors `Range` requests, which the player uses for seeking.
class VaultStreamServer {
  VaultStreamServer._();

  static HttpServer? _server;
  static final Map<String, _Entry> _entries = {};

  /// Registers [file] for playback and returns its loopback URL.
  static Future<Uri> register({
    required File file,
    required List<int> key,
    required String extension,
  }) async {
    final server = await _ensureStarted();
    final token = base64Url
        .encode(VaultCrypto.randomBytes(32))
        .replaceAll('=', '');
    final ext = extension.isEmpty ? 'bin' : extension.toLowerCase();
    _entries[token] = _Entry(file, List<int>.of(key), _mimeFor(ext));
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/$token/video.$ext',
    );
  }

  /// Revokes the URL returned by [register].
  static void unregister(Uri url) {
    if (url.pathSegments.isNotEmpty) _entries.remove(url.pathSegments.first);
    if (_entries.isEmpty) unawaited(stop());
  }

  /// Revokes every URL and shuts the server down (e.g. on vault logout).
  static Future<void> stop() async {
    _entries.clear();
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  @visibleForTesting
  static int? get port => _server?.port;

  static Future<HttpServer> _ensureStarted() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    server.listen((request) => unawaited(_handle(request)));
    return _server = server;
  }

  static Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    EncryptedFileReader? reader;
    try {
      final segments = request.uri.pathSegments;
      final entry = segments.isEmpty ? null : _entries[segments.first];
      if (entry == null ||
          (request.method != 'GET' && request.method != 'HEAD')) {
        response.statusCode = entry == null
            ? HttpStatus.notFound
            : HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }

      reader = await EncryptedFileReader.open(entry.file, entry.key);
      final length = reader.length;
      final range = _parseRange(
        request.headers.value(HttpHeaders.rangeHeader),
        length,
      );

      response.headers
        ..contentType = ContentType.parse(entry.mimeType)
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.cacheControlHeader, 'no-store');

      if (range == null &&
          request.headers.value(HttpHeaders.rangeHeader) != null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        await response.close();
        return;
      }

      final start = range?.$1 ?? 0;
      final end = range?.$2 ?? length - 1;
      if (range != null) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$length',
        );
      }
      response.contentLength = length == 0 ? 0 : end - start + 1;

      if (request.method == 'HEAD' || length == 0) {
        await response.close();
        return;
      }
      await response.addStream(reader.readRange(start, end));
      await response.close();
    } on SocketException {
      // The player closed the connection (seek or stop); nothing to do.
    } on HttpException {
      // Same as above: client went away mid-response.
    } catch (e) {
      debugPrint('Vault stream error: $e');
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {
        // Headers already sent; the connection is simply dropped.
      }
    } finally {
      await reader?.close();
    }
  }

  /// Parses a single `bytes=a-b`, `bytes=a-` or `bytes=-n` range.
  /// Returns null when absent or unsatisfiable.
  @visibleForTesting
  static (int, int)? parseRangeForTest(String? header, int length) =>
      _parseRange(header, length);

  static (int, int)? _parseRange(String? header, int length) {
    if (header == null || length == 0) return null;
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null) return null;
    final a = match.group(1)!;
    final b = match.group(2)!;
    int start;
    int end;
    if (a.isEmpty) {
      if (b.isEmpty) return null;
      final suffix = int.parse(b);
      if (suffix == 0) return null;
      start = suffix >= length ? 0 : length - suffix;
      end = length - 1;
    } else {
      start = int.parse(a);
      end = b.isEmpty ? length - 1 : int.parse(b);
      if (end >= length) end = length - 1;
    }
    if (start >= length || start > end) return null;
    return (start, end);
  }

  static String _mimeFor(String ext) {
    switch (ext) {
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case '3gp':
        return 'video/3gpp';
      case 'ts':
      case 'mts':
        return 'video/mp2t';
      default:
        return 'application/octet-stream';
    }
  }
}

class _Entry {
  final File file;
  final List<int> key;
  final String mimeType;

  _Entry(this.file, this.key, this.mimeType);
}
