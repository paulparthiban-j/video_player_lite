import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/core/security/vault_crypto.dart';
import 'package:next_gen_video_player/services/vault_stream_server.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late Uint8List data;
  late File encrypted;
  late Uint8List key;

  setUpAll(() => VaultCrypto.algorithm = DartAesGcm.with256bits());

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('stream_');
    final r = Random(7);
    data = Uint8List.fromList(List.generate(5000, (_) => r.nextInt(256)));
    final plain = File(p.join(dir.path, 'plain'))..writeAsBytesSync(data);
    encrypted = File(p.join(dir.path, 'enc'));
    key = VaultCrypto.newKey();
    await VaultCrypto.encryptFile(plain, encrypted, key, chunkSize: 1024);
  });

  tearDown(() async {
    await VaultStreamServer.stop();
    await dir.delete(recursive: true);
  });

  Future<(int, Map<String, String>, List<int>)> get(
    Uri url, {
    String? range,
    String method = 'GET',
  }) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, url);
      if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
      final res = await req.close();
      final body = <int>[];
      await for (final part in res) {
        body.addAll(part);
      }
      final headers = <String, String>{};
      res.headers.forEach((k, v) => headers[k] = v.join(','));
      return (res.statusCode, headers, body);
    } finally {
      client.close(force: true);
    }
  }

  test('serves the full decrypted file on loopback', () async {
    final url = await VaultStreamServer.register(
      file: encrypted,
      key: key,
      extension: 'mp4',
    );
    expect(url.host, '127.0.0.1');
    final (status, headers, body) = await get(url);
    expect(status, 200);
    expect(headers['content-type'], 'video/mp4');
    expect(headers['accept-ranges'], 'bytes');
    expect(body, data);
  });

  test('honors byte ranges for seeking', () async {
    final url = await VaultStreamServer.register(
      file: encrypted,
      key: key,
      extension: 'mkv',
    );
    final (status, headers, body) = await get(url, range: 'bytes=1000-3000');
    expect(status, 206);
    expect(headers['content-range'], 'bytes 1000-3000/5000');
    expect(body, data.sublist(1000, 3001));

    final (s2, _, tail) = await get(url, range: 'bytes=-10');
    expect(s2, 206);
    expect(tail, data.sublist(4990));

    final (s3, _, _) = await get(url, range: 'bytes=9000-');
    expect(s3, 416);
  });

  test('unknown or revoked tokens are refused', () async {
    final url = await VaultStreamServer.register(
      file: encrypted,
      key: key,
      extension: 'mp4',
    );
    final guess = url.replace(path: '/not-a-token/video.mp4');
    expect((await get(guess)).$1, 404);

    VaultStreamServer.unregister(url);
    await VaultStreamServer.stop();
    final second = await VaultStreamServer.register(
      file: encrypted,
      key: key,
      extension: 'mp4',
    );
    expect((await get(second.replace(path: url.path))).$1, 404);
  });

  test('range parsing', () {
    expect(VaultStreamServer.parseRangeForTest('bytes=0-99', 1000), (0, 99));
    expect(VaultStreamServer.parseRangeForTest('bytes=900-', 1000), (900, 999));
    expect(VaultStreamServer.parseRangeForTest('bytes=0-5000', 1000), (0, 999));
    expect(VaultStreamServer.parseRangeForTest('bytes=-100', 1000), (900, 999));
    expect(VaultStreamServer.parseRangeForTest('bytes=5-2', 1000), isNull);
    expect(VaultStreamServer.parseRangeForTest('items=0-1', 1000), isNull);
    expect(VaultStreamServer.parseRangeForTest(null, 1000), isNull);
  });
}
