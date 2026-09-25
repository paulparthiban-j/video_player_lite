import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/core/security/password_hasher.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('pbkdf2 (RFC 7914 / RFC 6070-style vectors for HMAC-SHA256)', () {
    test('1 iteration', () {
      final out = PasswordHasher.pbkdf2(
        utf8.encode('password'),
        utf8.encode('salt'),
        1,
        32,
      );
      expect(
        _hex(out),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('4096 iterations', () {
      final out = PasswordHasher.pbkdf2(
        utf8.encode('password'),
        utf8.encode('salt'),
        4096,
        32,
      );
      expect(
        _hex(out),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });

    test('multi-block output', () {
      final out = PasswordHasher.pbkdf2(
        utf8.encode('passwordPASSWORDpassword'),
        utf8.encode('saltSALTsaltSALTsaltSALTsaltSALTsalt'),
        4096,
        40,
      );
      expect(
        _hex(out),
        '348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1'
        'c635518c7dac47e9',
      );
    });
  });

  group('hash / verify', () {
    test('round trips and rejects wrong secrets', () {
      final encoded = PasswordHasher.hash('hunter2', iterations: 1000);
      expect(PasswordHasher.verify('hunter2', encoded), isTrue);
      expect(PasswordHasher.verify('hunter3', encoded), isFalse);
      expect(PasswordHasher.verify('', encoded), isFalse);
    });

    test('uses a unique salt per hash', () {
      final a = PasswordHasher.hash('same', iterations: 1000);
      final b = PasswordHasher.hash('same', iterations: 1000);
      expect(a, isNot(b));
      expect(PasswordHasher.verify('same', a), isTrue);
      expect(PasswordHasher.verify('same', b), isTrue);
    });

    test('accepts legacy unsalted SHA-256 hashes and flags them', () {
      final legacy = sha256.convert(utf8.encode('old-pass')).toString();
      expect(PasswordHasher.verify('old-pass', legacy), isTrue);
      expect(PasswordHasher.verify('other', legacy), isFalse);
      expect(PasswordHasher.needsRehash(legacy), isTrue);
    });

    test('flags hashes below the current work factor', () {
      expect(
        PasswordHasher.needsRehash(PasswordHasher.hash('x', iterations: 10)),
        isTrue,
      );
    });

    test('never throws on malformed input', () {
      for (final bad in ['', 'pbkdf2', r'pbkdf2$x$y$z', r'bcrypt$1$2$3']) {
        expect(PasswordHasher.verify('pw', bad), isFalse, reason: bad);
      }
    });
  });

  test('constantTimeEquals', () {
    expect(PasswordHasher.constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    expect(PasswordHasher.constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    expect(PasswordHasher.constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
  });

  test('default work factor stays within an acceptable time budget', () {
    final sw = Stopwatch()..start();
    PasswordHasher.hash('benchmark');
    sw.stop();
    // printOnFailure keeps CI logs quiet unless something regresses.
    printOnFailure('PBKDF2 default hash took ${sw.elapsedMilliseconds}ms');
    expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
  });
}
