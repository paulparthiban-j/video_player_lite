import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/core/security/vault_crypto.dart';
import 'package:path/path.dart' as p;

Uint8List _bytes(int n, [int seed = 1]) {
  final r = Random(seed);
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

void main() {
  late Directory dir;

  setUpAll(() => VaultCrypto.algorithm = DartAesGcm.with256bits());
  setUp(() async => dir = await Directory.systemTemp.createTemp('crypto_'));
  tearDown(() => dir.delete(recursive: true));

  Future<File> write(String name, List<int> data) async =>
      File(p.join(dir.path, name))..writeAsBytesSync(data);

  group('file encryption', () {
    const chunk = 64;

    for (final size in [0, 1, chunk - 1, chunk, chunk + 1, chunk * 5 + 7]) {
      test('round trips $size bytes', () async {
        final data = _bytes(size, size);
        final plain = await write('plain', data);
        final enc = File(p.join(dir.path, 'enc'));
        final out = File(p.join(dir.path, 'out'));
        final key = VaultCrypto.newKey();

        await VaultCrypto.encryptFile(plain, enc, key, chunkSize: chunk);
        expect(
          await enc.length(),
          VaultCrypto.encryptedLength(size, chunkSize: chunk),
        );
        expect(await VaultCrypto.isEncryptedFile(enc), isTrue);

        await VaultCrypto.decryptFile(enc, out, key);
        expect(await out.readAsBytes(), data);
      });
    }

    test('ciphertext does not contain the plaintext', () async {
      final data = Uint8List.fromList(List.filled(4096, 0x41));
      final enc = File(p.join(dir.path, 'enc'));
      await VaultCrypto.encryptFile(
        await write('plain', data),
        enc,
        VaultCrypto.newKey(),
        chunkSize: 1024,
      );
      final bytes = await enc.readAsBytes();
      final run = List.filled(32, 0x41);
      var longest = 0, current = 0;
      for (final b in bytes) {
        current = b == 0x41 ? current + 1 : 0;
        longest = max(longest, current);
      }
      expect(longest, lessThan(run.length));
    });

    test('wrong key, tampering and truncation are detected', () async {
      final key = VaultCrypto.newKey();
      final enc = File(p.join(dir.path, 'enc'));
      await VaultCrypto.encryptFile(
        await write('plain', _bytes(300)),
        enc,
        key,
        chunkSize: 100,
      );
      final out = File(p.join(dir.path, 'out'));

      await expectLater(
        VaultCrypto.decryptFile(enc, out, VaultCrypto.newKey()),
        throwsA(isA<VaultCryptoException>()),
      );
      expect(await out.exists(), isFalse, reason: 'partial output removed');

      final tampered = await enc.readAsBytes();
      tampered[VaultCrypto.headerLength + 20] ^= 1;
      final bad = await write('tampered', tampered);
      await expectLater(
        VaultCrypto.decryptFile(bad, out, key),
        throwsA(isA<VaultCryptoException>()),
      );

      final original = await enc.readAsBytes();
      final truncated = await write(
        'truncated',
        original.sublist(0, original.length - 50),
      );
      await expectLater(
        EncryptedFileReader.open(truncated, key),
        throwsA(isA<VaultCryptoException>()),
      );
    });

    test('chunks cannot be swapped', () async {
      final key = VaultCrypto.newKey();
      final enc = File(p.join(dir.path, 'enc'));
      await VaultCrypto.encryptFile(
        await write('plain', _bytes(200)),
        enc,
        key,
        chunkSize: 100,
      );
      final b = await enc.readAsBytes();
      const record = 100 + 28;
      const h = VaultCrypto.headerLength;
      final swapped = Uint8List.fromList([
        ...b.sublist(0, h),
        ...b.sublist(h + record, h + 2 * record),
        ...b.sublist(h, h + record),
      ]);
      final reader = await EncryptedFileReader.open(
        await write('swapped', swapped),
        key,
      );
      await expectLater(
        reader.readChunk(0),
        throwsA(isA<VaultCryptoException>()),
      );
      await reader.close();
    });

    test('readRange returns exact byte ranges across chunks', () async {
      final data = _bytes(1000, 9);
      final key = VaultCrypto.newKey();
      final enc = File(p.join(dir.path, 'enc'));
      await VaultCrypto.encryptFile(
        await write('plain', data),
        enc,
        key,
        chunkSize: 128,
      );
      final reader = await EncryptedFileReader.open(enc, key);
      final r = Random(3);
      for (var i = 0; i < 50; i++) {
        final start = r.nextInt(1000);
        final end = start + r.nextInt(1000 - start);
        final got = <int>[];
        await for (final part in reader.readRange(start, end)) {
          got.addAll(part);
        }
        expect(got, data.sublist(start, end + 1), reason: '$start-$end');
      }
      await reader.close();
    });
  });

  group('key wrapping', () {
    test('wraps with a secret and rejects the wrong one', () async {
      final key = VaultCrypto.newKey();
      final wrapped = await VaultCrypto.wrapKeyWithSecret(
        key,
        'pw',
        iterations: 1000,
      );
      expect(await VaultCrypto.unwrapKeyWithSecret(wrapped, 'pw'), key);
      expect(await VaultCrypto.unwrapKeyWithSecret(wrapped, 'nope'), isNull);
      expect(await VaultCrypto.unwrapKeyWithSecret('garbage', 'pw'), isNull);
    });

    test('wraps with a raw key', () async {
      final inner = VaultCrypto.newKey();
      final outer = VaultCrypto.newKey();
      final wrapped = await VaultCrypto.wrapKey(inner, outer);
      expect(await VaultCrypto.unwrapKey(wrapped, outer), inner);
      expect(
        await VaultCrypto.unwrapKey(wrapped, VaultCrypto.newKey()),
        isNull,
      );
    });

    test('seals strings', () async {
      final key = VaultCrypto.newKey();
      final sealed = await VaultCrypto.sealString('secret list', key);
      expect(sealed, isNot(contains('secret')));
      expect(await VaultCrypto.openString(sealed, key), 'secret list');
    });
  });
}
