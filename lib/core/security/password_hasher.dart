import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Salted, iterated password hashing (PBKDF2-HMAC-SHA256).
///
/// Encoded hashes have the form `pbkdf2$<iterations>$<salt>$<hash>` where salt
/// and hash are base64. Hashes written by older app versions (bare, unsalted
/// SHA-256 hex) are still accepted by [verify]; callers should re-hash on a
/// successful match when [needsRehash] returns true.
class PasswordHasher {
  PasswordHasher._();

  static const String _scheme = 'pbkdf2';
  static const int defaultIterations = 120000;
  static const int _saltLength = 16;
  static const int _keyLength = 32;

  static final Random _random = Random.secure();

  /// Hashes [secret] with a fresh random salt.
  static String hash(String secret, {int iterations = defaultIterations}) {
    final salt = Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => _random.nextInt(256)),
    );
    final derived = pbkdf2(utf8.encode(secret), salt, iterations, _keyLength);
    return '$_scheme\$$iterations\$${base64.encode(salt)}\$${base64.encode(derived)}';
  }

  /// Returns true when [secret] matches [encoded]. Never throws.
  static bool verify(String secret, String encoded) {
    if (encoded.isEmpty) return false;
    try {
      if (_isLegacy(encoded)) {
        final legacy = sha256.convert(utf8.encode(secret)).toString();
        return constantTimeEquals(utf8.encode(legacy), utf8.encode(encoded));
      }
      final parts = encoded.split(r'$');
      if (parts.length != 4 || parts[0] != _scheme) return false;
      final iterations = int.parse(parts[1]);
      final salt = base64.decode(parts[2]);
      final expected = base64.decode(parts[3]);
      final actual = pbkdf2(
        utf8.encode(secret),
        salt,
        iterations,
        expected.length,
      );
      return constantTimeEquals(actual, expected);
    } catch (_) {
      return false;
    }
  }

  /// True when [encoded] uses a weaker scheme or fewer iterations than today.
  static bool needsRehash(String encoded) {
    if (_isLegacy(encoded)) return true;
    final parts = encoded.split(r'$');
    if (parts.length != 4) return true;
    return (int.tryParse(parts[1]) ?? 0) < defaultIterations;
  }

  static bool _isLegacy(String encoded) =>
      encoded.length == 64 && RegExp(r'^[0-9a-f]{64}$').hasMatch(encoded);

  /// Compares two byte sequences in time independent of where they differ.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// PBKDF2 with HMAC-SHA256 as the PRF (RFC 8018).
  static Uint8List pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int keyLength,
  ) {
    if (iterations < 1) throw ArgumentError.value(iterations, 'iterations');
    final hmac = Hmac(sha256, password);
    const hLen = 32;
    final blocks = (keyLength + hLen - 1) ~/ hLen;
    final out = Uint8List(blocks * hLen);

    for (var block = 1; block <= blocks; block++) {
      final blockIndex = Uint8List(4)
        ..buffer.asByteData().setUint32(0, block, Endian.big);
      var u = hmac.convert([...salt, ...blockIndex]).bytes;
      final t = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < hLen; j++) {
          t[j] ^= u[j];
        }
      }
      out.setRange((block - 1) * hLen, block * hLen, t);
    }
    return Uint8List.sublistView(out, 0, keyLength);
  }
}
