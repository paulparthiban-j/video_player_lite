import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';

import 'password_hasher.dart';

/// Thrown when encrypted data is malformed, truncated or fails authentication
/// (wrong key or tampering).
class VaultCryptoException implements Exception {
  final String message;
  const VaultCryptoException(this.message);

  @override
  String toString() => 'VaultCryptoException: $message';
}

/// Authenticated encryption for vault files, metadata and keys.
///
/// ## File format (version 1)
///
/// ```text
/// header (36 bytes)
///   magic       "PPVE"            4
///   version     0x01              1
///   reserved    0x00 0x00 0x00    3
///   chunkSize   uint32 BE         4
///   plainLength uint64 BE         8
///   fileId      random            16
/// chunk i (i = 0 .. n-1)
///   nonce       random            12
///   ciphertext  <= chunkSize
///   tag         GCM               16
/// ```
///
/// Each chunk is sealed with AES-256-GCM using
/// `fileId || i || plainLength` as associated data, so chunks cannot be
/// reordered, moved between files, or truncated without detection. All chunks
/// except the last hold exactly `chunkSize` bytes, which makes any byte range
/// addressable without reading the chunks before it; that is what allows
/// streaming playback with seeking.
class VaultCrypto {
  VaultCrypto._();

  static const int keyLength = 32;
  static const int defaultChunkSize = 1024 * 1024;
  static const int headerLength = 36;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;
  static const List<int> _magic = [0x50, 0x50, 0x56, 0x45]; // "PPVE"
  static const int _formatVersion = 1;

  static final Random _random = Random.secure();

  static AesGcm? _algorithm;

  /// AES-256-GCM. Uses the platform implementation (hardware-accelerated
  /// javax.crypto / CryptoKit) on Android and iOS, and a pure-Dart
  /// implementation elsewhere (for example in unit tests).
  static AesGcm get algorithm => _algorithm ??= FlutterAesGcm.with256bits();

  /// Overrides the cipher implementation (tests).
  static set algorithm(AesGcm value) => _algorithm = value;

  static Uint8List randomBytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256)),
  );

  /// Creates a new random data-encryption key.
  static Uint8List newKey() => randomBytes(keyLength);

  // ---------------------------------------------------------------------------
  // Small payloads (metadata, wrapped keys)
  // ---------------------------------------------------------------------------

  /// Encrypts [plain] as `nonce || ciphertext || tag`.
  static Future<Uint8List> seal(
    List<int> plain,
    List<int> key, {
    List<int> aad = const [],
  }) async {
    final box = await algorithm.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: randomBytes(_nonceLength),
      aad: aad,
    );
    return box.concatenation();
  }

  /// Reverses [seal]. Throws [VaultCryptoException] if authentication fails.
  static Future<Uint8List> open(
    List<int> sealed,
    List<int> key, {
    List<int> aad = const [],
  }) async {
    if (sealed.length < _nonceLength + _tagLength) {
      throw const VaultCryptoException('Sealed payload too short');
    }
    try {
      final box = SecretBox.fromConcatenation(
        sealed,
        nonceLength: _nonceLength,
        macLength: _tagLength,
      );
      final plain = await algorithm.decrypt(
        box,
        secretKey: SecretKey(key),
        aad: aad,
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const VaultCryptoException('Authentication failed');
    }
  }

  static Future<String> sealString(String plain, List<int> key) async =>
      base64.encode(await seal(utf8.encode(plain), key));

  static Future<String> openString(String sealed, List<int> key) async =>
      utf8.decode(await open(base64.decode(sealed), key));

  // ---------------------------------------------------------------------------
  // Key wrapping with a password-derived key
  // ---------------------------------------------------------------------------

  static const String _wrapScheme = 'kw1';

  /// Encrypts [dataKey] under a key derived from [secret] with PBKDF2.
  /// Encoded as `kw1$<iterations>$<salt>$<sealed>`.
  static Future<String> wrapKeyWithSecret(
    List<int> dataKey,
    String secret, {
    int iterations = PasswordHasher.defaultIterations,
  }) async {
    final salt = randomBytes(16);
    final kek = await _deriveKey(secret, salt, iterations);
    final sealed = await seal(dataKey, kek, aad: utf8.encode(_wrapScheme));
    return '$_wrapScheme\$$iterations\$${base64.encode(salt)}'
        '\$${base64.encode(sealed)}';
  }

  /// Returns the data key, or null when [secret] is wrong or [wrapped] is
  /// malformed.
  static Future<Uint8List?> unwrapKeyWithSecret(
    String wrapped,
    String secret,
  ) async {
    final parts = wrapped.split(r'$');
    if (parts.length != 4 || parts[0] != _wrapScheme) return null;
    try {
      final iterations = int.parse(parts[1]);
      final salt = base64.decode(parts[2]);
      final kek = await _deriveKey(secret, salt, iterations);
      return await open(
        base64.decode(parts[3]),
        kek,
        aad: utf8.encode(_wrapScheme),
      );
    } on VaultCryptoException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Encrypts [dataKey] under another raw key (e.g. decoy key under main key).
  static Future<String> wrapKey(List<int> dataKey, List<int> kek) async =>
      base64.encode(await seal(dataKey, kek, aad: utf8.encode('kw-raw')));

  static Future<Uint8List?> unwrapKey(String wrapped, List<int> kek) async {
    try {
      return await open(
        base64.decode(wrapped),
        kek,
        aad: utf8.encode('kw-raw'),
      );
    } on VaultCryptoException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Future<Uint8List> _deriveKey(
    String secret,
    List<int> salt,
    int iterations,
  ) {
    final secretBytes = utf8.encode(secret);
    final saltBytes = List<int>.of(salt);
    return Isolate.run(
      () =>
          PasswordHasher.pbkdf2(secretBytes, saltBytes, iterations, keyLength),
    );
  }

  // ---------------------------------------------------------------------------
  // Files
  // ---------------------------------------------------------------------------

  /// Size of the encrypted file for a plaintext of [plainLength] bytes.
  static int encryptedLength(
    int plainLength, {
    int chunkSize = defaultChunkSize,
  }) {
    final chunks = plainLength == 0
        ? 1
        : (plainLength + chunkSize - 1) ~/ chunkSize;
    return headerLength + plainLength + chunks * (_nonceLength + _tagLength);
  }

  /// Encrypts [source] into [destination]. On failure the partial
  /// destination is deleted and the error rethrown.
  static Future<void> encryptFile(
    File source,
    File destination,
    List<int> key, {
    int chunkSize = defaultChunkSize,
    void Function(double progress)? onProgress,
  }) async {
    final plainLength = await source.length();
    final fileId = randomBytes(16);
    final header = _buildHeader(chunkSize, plainLength, fileId);
    final chunkCount = plainLength == 0
        ? 1
        : (plainLength + chunkSize - 1) ~/ chunkSize;
    final secretKey = SecretKey(key);

    await destination.parent.create(recursive: true);
    final input = await source.open();
    final output = await destination.open(mode: FileMode.write);
    try {
      await output.writeFrom(header);
      for (var i = 0; i < chunkCount; i++) {
        final plain = await input.read(chunkSize);
        final expected = i == chunkCount - 1
            ? plainLength - i * chunkSize
            : chunkSize;
        if (plain.length != expected) {
          throw const VaultCryptoException('Source changed while encrypting');
        }
        final box = await algorithm.encrypt(
          plain,
          secretKey: secretKey,
          nonce: randomBytes(_nonceLength),
          aad: _chunkAad(fileId, i, plainLength),
        );
        await output.writeFrom(box.nonce);
        await output.writeFrom(box.cipherText);
        await output.writeFrom(box.mac.bytes);
        onProgress?.call((i + 1) / chunkCount);
      }
      await output.flush();
      await output.close();
      await input.close();
    } catch (_) {
      await input.close();
      await output.close();
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  /// Decrypts [source] into [destination]. On failure the partial
  /// destination is deleted and the error rethrown.
  static Future<void> decryptFile(
    File source,
    File destination,
    List<int> key, {
    void Function(double progress)? onProgress,
  }) async {
    final reader = await EncryptedFileReader.open(source, key);
    await destination.parent.create(recursive: true);
    final output = await destination.open(mode: FileMode.write);
    try {
      for (var i = 0; i < reader.chunkCount; i++) {
        await output.writeFrom(await reader.readChunk(i));
        onProgress?.call((i + 1) / reader.chunkCount);
      }
      await output.flush();
      await output.close();
      await reader.close();
    } catch (_) {
      await output.close();
      await reader.close();
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  /// True when [file] starts with the vault encryption header.
  static Future<bool> isEncryptedFile(File file) async {
    if (!await file.exists() || await file.length() < headerLength) {
      return false;
    }
    final raf = await file.open();
    try {
      final magic = await raf.read(_magic.length);
      return PasswordHasher.constantTimeEquals(magic, _magic);
    } finally {
      await raf.close();
    }
  }

  static Uint8List _buildHeader(int chunkSize, int plainLength, List<int> id) {
    final header = Uint8List(headerLength);
    header.setRange(0, 4, _magic);
    header[4] = _formatVersion;
    final data = ByteData.sublistView(header);
    data.setUint32(8, chunkSize, Endian.big);
    data.setUint64(12, plainLength, Endian.big);
    header.setRange(20, 36, id);
    return header;
  }

  static List<int> _chunkAad(List<int> fileId, int index, int plainLength) {
    final aad = Uint8List(32);
    aad.setRange(0, 16, fileId);
    final data = ByteData.sublistView(aad);
    data.setUint64(16, index, Endian.big);
    data.setUint64(24, plainLength, Endian.big);
    return aad;
  }
}

/// Random-access reader for files written by [VaultCrypto.encryptFile].
///
/// Not safe for concurrent use; open one reader per consumer.
class EncryptedFileReader {
  final RandomAccessFile _raf;
  final SecretKey _key;
  final List<int> _fileId;

  /// Plaintext length in bytes.
  final int length;
  final int chunkSize;
  final int chunkCount;

  int _cachedIndex = -1;
  Uint8List? _cached;

  EncryptedFileReader._(
    this._raf,
    this._key,
    this._fileId,
    this.length,
    this.chunkSize,
    this.chunkCount,
  );

  static Future<EncryptedFileReader> open(File file, List<int> key) async {
    final raf = await file.open();
    try {
      final fileLength = await raf.length();
      if (fileLength < VaultCrypto.headerLength) {
        throw const VaultCryptoException('Not a vault file');
      }
      final header = await raf.read(VaultCrypto.headerLength);
      if (!PasswordHasher.constantTimeEquals(
        header.sublist(0, 4),
        VaultCrypto._magic,
      )) {
        throw const VaultCryptoException('Not a vault file');
      }
      if (header[4] != VaultCrypto._formatVersion) {
        throw VaultCryptoException('Unsupported format version ${header[4]}');
      }
      final data = ByteData.sublistView(header);
      final chunkSize = data.getUint32(8, Endian.big);
      final plainLength = data.getUint64(12, Endian.big);
      if (chunkSize == 0) throw const VaultCryptoException('Bad chunk size');
      final chunkCount = plainLength == 0
          ? 1
          : (plainLength + chunkSize - 1) ~/ chunkSize;
      if (fileLength !=
          VaultCrypto.encryptedLength(plainLength, chunkSize: chunkSize)) {
        throw const VaultCryptoException('File is truncated or corrupted');
      }
      return EncryptedFileReader._(
        raf,
        SecretKey(key),
        header.sublist(20, 36),
        plainLength,
        chunkSize,
        chunkCount,
      );
    } catch (_) {
      await raf.close();
      rethrow;
    }
  }

  int _plainLengthOf(int index) =>
      index == chunkCount - 1 ? length - index * chunkSize : chunkSize;

  /// Decrypts and returns chunk [index].
  Future<Uint8List> readChunk(int index) async {
    if (index < 0 || index >= chunkCount) {
      throw RangeError.range(index, 0, chunkCount - 1, 'index');
    }
    if (index == _cachedIndex) return _cached!;

    const overhead = VaultCrypto._nonceLength + VaultCrypto._tagLength;
    final offset = VaultCrypto.headerLength + index * (chunkSize + overhead);
    await _raf.setPosition(offset);
    final record = await _raf.read(_plainLengthOf(index) + overhead);
    try {
      final box = SecretBox.fromConcatenation(
        record,
        nonceLength: VaultCrypto._nonceLength,
        macLength: VaultCrypto._tagLength,
      );
      final plain = await VaultCrypto.algorithm.decrypt(
        box,
        secretKey: _key,
        aad: VaultCrypto._chunkAad(_fileId, index, length),
      );
      _cachedIndex = index;
      return _cached = Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const VaultCryptoException('Chunk failed authentication');
    }
  }

  /// Streams plaintext bytes in `[start, endInclusive]`.
  Stream<List<int>> readRange(int start, int endInclusive) async* {
    if (length == 0) return;
    RangeError.checkValueInInterval(start, 0, length - 1, 'start');
    RangeError.checkValueInInterval(
      endInclusive,
      start,
      length - 1,
      'endInclusive',
    );
    var position = start;
    while (position <= endInclusive) {
      final index = position ~/ chunkSize;
      final chunk = await readChunk(index);
      final from = position - index * chunkSize;
      final to = min(chunk.length, endInclusive - index * chunkSize + 1);
      yield Uint8List.sublistView(chunk, from, to);
      position = index * chunkSize + to;
    }
  }

  Future<void> close() => _raf.close();
}
