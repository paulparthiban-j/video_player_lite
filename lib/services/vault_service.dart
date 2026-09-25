import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/security/password_hasher.dart';
import 'thumbnail_service.dart';
import 'video_scanner_service.dart';

class VaultVideo {
  final String id;
  final String originalPath;
  final String hiddenPath;
  final String fileName;
  final String originalExtension;
  final int fileSize;
  final DateTime hiddenDate;
  final String thumbnail;
  final String encryptionKey;
  final String checksum;
  final bool isEncrypted;

  VaultVideo({
    required this.id,
    required this.originalPath,
    required this.hiddenPath,
    required this.fileName,
    required this.originalExtension,
    required this.fileSize,
    required this.hiddenDate,
    required this.thumbnail,
    required this.encryptionKey,
    required this.checksum,
    this.isEncrypted = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalPath': originalPath,
      'hiddenPath': hiddenPath,
      'fileName': fileName,
      'originalExtension': originalExtension,
      'fileSize': fileSize,
      'hiddenDate': hiddenDate.toIso8601String(),
      'thumbnail': thumbnail,
      'encryptionKey': encryptionKey,
      'checksum': checksum,
      'isEncrypted': isEncrypted,
    };
  }

  factory VaultVideo.fromJson(Map<String, dynamic> json) {
    final fileName = json['fileName'] ?? '';
    final extension =
        (json['originalExtension'] ?? '').toString().trim().isNotEmpty
            ? json['originalExtension'].toString()
            : _getExtensionFromName(fileName);
    return VaultVideo(
      id: json['id'],
      originalPath: json['originalPath'],
      hiddenPath: json['hiddenPath'],
      fileName: fileName,
      originalExtension: extension,
      fileSize: json['fileSize'],
      hiddenDate: DateTime.parse(json['hiddenDate']),
      thumbnail: json['thumbnail'] ?? '',
      encryptionKey: json['encryptionKey'] ?? '',
      checksum: json['checksum'] ?? '',
      isEncrypted: json['isEncrypted'] ?? true,
    );
  }

  static String _getExtensionFromName(String name) {
    final parts = name.split('.');
    if (parts.length <= 1) return '';
    return parts.last;
  }
}

/// Outcome of a vault unlock attempt.
enum VaultAuthStatus { success, invalidPassword, lockedOut, notSetUp, error }

class VaultAuthResult {
  final VaultAuthStatus status;

  /// Time remaining before another attempt is allowed ([VaultAuthStatus.lockedOut]).
  final Duration retryAfter;

  const VaultAuthResult(this.status, {this.retryAfter = Duration.zero});

  bool get isSuccess => status == VaultAuthStatus.success;
}

class VaultService {
  static const String _mainVaultKey = 'main_vault_password';
  static const String _fakeVaultKey = 'fake_vault_password';
  static const String _mainVideosKey = 'main_vault_videos';
  static const String _fakeVideosKey = 'fake_vault_videos';
  static const String _isSetupKey = 'vault_is_setup';
  static const String _fakeModeKey = 'is_fake_mode';

  // Security Questions Keys
  static const String _securityQuestionsKey = 'security_questions';
  static const String _securityAnswersKey = 'security_answers';
  static const String _securitySetupKey = 'security_setup_done';

  // Brute-force protection
  static const String _failedAttemptsKey = 'vault_failed_attempts';
  static const String _lockedUntilKey = 'vault_locked_until_ms';
  static const int _freeAttempts = 5;
  static const Duration _baseLockout = Duration(seconds: 30);
  static const Duration _maxLockout = Duration(hours: 1);

  /// Minimum accepted length for vault passwords.
  static const int minPasswordLength = 4;

  // Chunk size for file processing (8MB) balances speed and memory usage
  static const int _chunkSize = 8 * 1024 * 1024;
  static const int _yieldEveryBytes = 32 * 1024 * 1024;
  static const bool _useEncryption = false;
  static const String _hiddenExtension = 'vault';

  static final Random _random = Random.secure();

  static bool _isInFakeMode = false;
  static bool _isAuthenticated = false;

  static bool get isInFakeMode => _isInFakeMode;
  static bool get isAuthenticated => _isAuthenticated;

  // Security Questions Management
  static Future<bool> isSecuritySetup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_securitySetupKey) ?? false;
  }

  /// Stores recovery questions. Only the owner of the main vault may do this;
  /// otherwise anyone holding the decoy password (or nobody at all) could set
  /// answers and then use them to reset the main password.
  static Future<bool> setSecurityQuestions(
    List<String> questions,
    List<String> answers,
  ) async {
    if (!_isAuthenticated || _isInFakeMode) return false;
    if (questions.length != answers.length || questions.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();

      final hashedAnswers = await Future.wait(
        answers.map((answer) => _hashSecret(normalizeAnswer(answer))),
      );

      await prefs.setStringList(_securityQuestionsKey, questions);
      await prefs.setStringList(_securityAnswersKey, hashedAnswers);
      await prefs.setBool(_securitySetupKey, true);

      debugPrint('Security questions set up successfully');
      return true;
    } catch (e) {
      debugPrint('Error setting security questions: $e');
      return false;
    }
  }

  static Future<List<String>?> getSecurityQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_securityQuestionsKey);
  }

  /// Canonical form of a recovery answer: case, surrounding and repeated
  /// whitespace are ignored so "  New  York" matches "new york".
  @visibleForTesting
  static String normalizeAnswer(String answer) =>
      answer.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static Future<bool> verifySecurityAnswers(List<String> answers) async {
    if (await getLockoutRemaining() > Duration.zero) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedHashedAnswers =
          prefs.getStringList(_securityAnswersKey) ?? [];

      if (storedHashedAnswers.isEmpty ||
          storedHashedAnswers.length != answers.length) {
        await _registerFailedAttempt();
        return false;
      }

      var allMatch = true;
      for (int i = 0; i < answers.length; i++) {
        final stored = storedHashedAnswers[i];
        // Older versions hashed `answer.toLowerCase()` without trimming.
        final matches =
            await _verifySecret(normalizeAnswer(answers[i]), stored) ||
                (PasswordHasher.needsRehash(stored) &&
                    await _verifySecret(answers[i].toLowerCase(), stored));
        allMatch &= matches;
      }

      if (allMatch) {
        await _clearFailedAttempts();
      } else {
        await _registerFailedAttempt();
      }
      return allMatch;
    } catch (e) {
      debugPrint('Error verifying security answers: $e');
      return false;
    }
  }

  /// Sets a new main password after the recovery answers are verified.
  ///
  /// The decoy password is left untouched, and the new main password must
  /// differ from it (otherwise the two vaults could not be told apart).
  static Future<bool> resetPasswordWithSecurity(
    String newPassword,
    List<String> answers,
  ) async {
    if (newPassword.length < minPasswordLength) return false;
    if (!await verifySecurityAnswers(answers)) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final fakeHash = prefs.getString(_fakeVaultKey) ?? '';
      if (fakeHash.isNotEmpty && await _verifySecret(newPassword, fakeHash)) {
        return false;
      }

      await prefs.setString(_mainVaultKey, await _hashSecret(newPassword));
      await prefs.setBool(_isSetupKey, true);

      debugPrint('Main password reset using security questions');
      return true;
    } catch (e) {
      debugPrint('Error resetting password: $e');
      return false;
    }
  }

  // Password Setup
  static Future<bool> setupVault(
    String mainPassword,
    String fakePassword,
  ) async {
    if (mainPassword.length < minPasswordLength ||
        fakePassword.length < minPasswordLength ||
        mainPassword == fakePassword) {
      return false;
    }
    // Re-running setup would silently replace the passwords of an existing
    // vault; that must go through changePassword or hardResetVault instead.
    if (await isVaultSetup()) return false;
    try {
      final prefs = await SharedPreferences.getInstance();

      final hashes = await Future.wait([
        _hashSecret(mainPassword),
        _hashSecret(fakePassword),
      ]);

      await prefs.setString(_mainVaultKey, hashes[0]);
      await prefs.setString(_fakeVaultKey, hashes[1]);
      await prefs.setBool(_isSetupKey, true);
      await _clearFailedAttempts();

      // Create vault directories
      await _createVaultDirectories();

      debugPrint('Vault setup completed');
      return true;
    } catch (e) {
      debugPrint('Error setting up vault: $e');
      return false;
    }
  }

  static Future<bool> isVaultSetup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isSetupKey) ?? false;
  }

  /// How long the user must wait before the next unlock attempt.
  static Future<Duration> getLockoutRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final untilMs = prefs.getInt(_lockedUntilKey) ?? 0;
    final remaining = untilMs - DateTime.now().millisecondsSinceEpoch;
    return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
  }

  @visibleForTesting
  static Duration lockoutFor(int failedAttempts) {
    if (failedAttempts < _freeAttempts) return Duration.zero;
    final exponent = (failedAttempts - _freeAttempts).clamp(0, 16);
    final lockout = _baseLockout * (1 << exponent);
    return lockout > _maxLockout ? _maxLockout : lockout;
  }

  static Future<void> _registerFailedAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = (prefs.getInt(_failedAttemptsKey) ?? 0) + 1;
    await prefs.setInt(_failedAttemptsKey, attempts);
    final lockout = lockoutFor(attempts);
    if (lockout > Duration.zero) {
      await prefs.setInt(
        _lockedUntilKey,
        DateTime.now().add(lockout).millisecondsSinceEpoch,
      );
    }
  }

  static Future<void> _clearFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_failedAttemptsKey);
    await prefs.remove(_lockedUntilKey);
  }

  // Authentication
  static Future<bool> authenticate(String password) async =>
      (await unlock(password)).isSuccess;

  /// Attempts to unlock the vault, applying brute-force throttling.
  static Future<VaultAuthResult> unlock(String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!await isVaultSetup()) {
        return const VaultAuthResult(VaultAuthStatus.notSetUp);
      }

      final lockout = await getLockoutRemaining();
      if (lockout > Duration.zero) {
        return VaultAuthResult(VaultAuthStatus.lockedOut, retryAfter: lockout);
      }

      final mainHash = prefs.getString(_mainVaultKey) ?? '';
      final fakeHash = prefs.getString(_fakeVaultKey) ?? '';

      // Check both so timing does not reveal which vault a password opens.
      final results = await Future.wait([
        _verifySecret(password, mainHash),
        _verifySecret(password, fakeHash),
      ]);
      final isMain = results[0];
      final isFake = results[1];

      if (!isMain && !isFake) {
        await _registerFailedAttempt();
        final lockout = await getLockoutRemaining();
        return lockout > Duration.zero
            ? VaultAuthResult(VaultAuthStatus.lockedOut, retryAfter: lockout)
            : const VaultAuthResult(VaultAuthStatus.invalidPassword);
      }

      await _clearFailedAttempts();
      _isAuthenticated = true;
      _isInFakeMode = !isMain;
      await prefs.setBool(_fakeModeKey, _isInFakeMode);

      // Transparently upgrade hashes written by older app versions.
      final matchedKey = isMain ? _mainVaultKey : _fakeVaultKey;
      final matchedHash = isMain ? mainHash : fakeHash;
      if (PasswordHasher.needsRehash(matchedHash)) {
        await prefs.setString(matchedKey, await _hashSecret(password));
      }

      debugPrint(
        isMain ? 'Authenticated with main vault' : 'Authenticated with fake vault',
      );
      await _createVaultDirectories();
      return const VaultAuthResult(VaultAuthStatus.success);
    } catch (e) {
      debugPrint('Authentication error: $e');
      return const VaultAuthResult(VaultAuthStatus.error);
    }
  }

  static Future<void> logout() async {
    _isAuthenticated = false;
    _isInFakeMode = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fakeModeKey, false);
    debugPrint('Logged out from vault');
  }

  // Enhanced Video Management with Streaming Encryption
  static Future<bool> hideVideo(
    String videoPath, {
    ValueChanged<double>? onProgress,
  }) async {
    if (!_isAuthenticated) return false;

    try {
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) return false;

      final videoId = _generateVideoId();
      final encryptionKey = _useEncryption ? _generateEncryptionKey() : '';
      final hiddenFileName = '$videoId.$_hiddenExtension';
      final vaultDir = await _getVaultDirectory();
      final hiddenPath = '${vaultDir.path}/$hiddenFileName';

      final sourceSize = await videoFile.length();
      String checksum = '';

      if (_useEncryption) {
        RandomAccessFile? sourceRaf;
        IOSink? destSink;
        try {
          sourceRaf = await videoFile.open(mode: FileMode.read);
          final destFile = File(hiddenPath);
          destSink = destFile.openWrite();

          final output = AccumulatorSink<Digest>();
          final checksumSink = sha256.startChunkedConversion(output);

          final key = encrypt.Key.fromBase64(encryptionKey);
          final encrypter = encrypt.Encrypter(encrypt.AES(key));
          int bytesRead = 0;
          int bytesSinceYield = 0;

          while (bytesRead < sourceSize) {
            final remaining = sourceSize - bytesRead;
            final toRead = remaining < _chunkSize ? remaining : _chunkSize;
            final dataBytes = await sourceRaf.read(toRead);

            checksumSink.add(dataBytes);

            final iv = encrypt.IV.fromSecureRandom(16);
            final encrypted = encrypter.encryptBytes(dataBytes, iv: iv);

            final lengthBytes = Uint8List(4);
            final len = encrypted.bytes.length;
            ByteData.view(lengthBytes.buffer).setUint32(0, len, Endian.big);

            destSink.add(iv.bytes);
            destSink.add(lengthBytes);
            destSink.add(encrypted.bytes);

            bytesRead += toRead;
            bytesSinceYield += toRead;

            if (onProgress != null && sourceSize > 0) {
              onProgress(bytesRead / sourceSize);
            }

            if (bytesSinceYield >= _yieldEveryBytes) {
              bytesSinceYield = 0;
              await Future.delayed(Duration.zero);
            }
          }

          checksumSink.close();
          await destSink.flush();
          await destSink.close();
          await sourceRaf.close();

          checksum = output.events.single.toString();
        } catch (e) {
          await sourceRaf?.close();
          await destSink?.close();
          rethrow;
        }
      } else {
        final moved = await _moveFileToPath(
          sourceFile: videoFile,
          destinationPath: hiddenPath,
          onProgress: onProgress,
        );
        if (!moved) return false;
        onProgress?.call(1.0);
      }

      // Create vault video object
      final vaultVideo = VaultVideo(
        id: videoId,
        originalPath: videoPath,
        hiddenPath: hiddenPath,
        fileName: videoFile.uri.pathSegments.last,
        originalExtension: path.extension(videoPath).replaceFirst('.', ''),
        fileSize: sourceSize,
        hiddenDate: DateTime.now(),
        thumbnail: '',
        encryptionKey: encryptionKey,
        checksum: checksum,
        isEncrypted: _useEncryption,
      );

      await _saveVideoToVault(vaultVideo);

      await VideoScannerService.removeFromCache(videoPath);
      await ThumbnailService.deleteThumbnail(videoPath);

      onProgress?.call(1.0);
      debugPrint('Video securely hidden: ${vaultVideo.fileName}');
      return true;
    } catch (e) {
      debugPrint('Error hiding video: $e');
      return false;
    }
  }

  static Future<bool> unhideVideo(
    String videoId, {
    ValueChanged<double>? onProgress,
  }) async {
    if (!_isAuthenticated) return false;

    try {
      final videos = await _getVaultVideos();
      final video = videos.firstWhere((v) => v.id == videoId);
      bool success = false;
      // Never clobber a file that has since appeared at the original path.
      final destination = await availablePath(video.originalPath);

      if (video.isEncrypted) {
        success = await _decryptVideoToPath(
          video,
          destination,
          onProgress: onProgress,
        );
      } else {
        success = await _moveFileToPath(
          sourceFile: File(video.hiddenPath),
          destinationPath: destination,
          onProgress: onProgress,
        );
      }

      if (!success) return false;

      await _removeVideoFromVault(videoId);

      debugPrint('Video securely unhidden: ${video.fileName}');
      return true;
    } catch (e) {
      debugPrint('Error unhiding video: $e');
      return false;
    }
  }

  static Future<List<VaultVideo>> getVaultVideos() async {
    if (!_isAuthenticated) return [];
    return _getVaultVideos();
  }

  // Private Helper Methods
  /// Returns [desiredPath], or `name (1).ext`, `name (2).ext`, ... if taken.
  @visibleForTesting
  static Future<String> availablePath(String desiredPath) async {
    if (!await File(desiredPath).exists()) return desiredPath;
    final dir = path.dirname(desiredPath);
    final base = path.basenameWithoutExtension(desiredPath);
    final ext = path.extension(desiredPath);
    for (var i = 1; i < 10000; i++) {
      final candidate = path.join(dir, '$base ($i)$ext');
      if (!await File(candidate).exists()) return candidate;
    }
    return path.join(dir, '${base}_${_generateVideoId()}$ext');
  }

  // Key derivation is deliberately slow, so run it off the UI isolate.
  static Future<String> _hashSecret(String secret) =>
      Isolate.run(() => PasswordHasher.hash(secret));

  static Future<bool> _verifySecret(String secret, String encoded) {
    if (encoded.isEmpty) return Future.value(false);
    return Isolate.run(() => PasswordHasher.verify(secret, encoded));
  }

  static String _generateVideoId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final suffix = List<String>.generate(
      8,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${timestamp}_$suffix';
  }


  static Future<Directory> _getVaultDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final vaultName = _isInFakeMode ? 'fake_vault' : 'main_vault';
    final vaultDir = Directory('${appDir.path}/$vaultName');

    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    await _ensureNoMediaFile(vaultDir);

    return vaultDir;
  }

  static Future<void> _createVaultDirectories() async {
    final appDir = await getApplicationDocumentsDirectory();

    final mainVaultDir = Directory('${appDir.path}/main_vault');
    final fakeVaultDir = Directory('${appDir.path}/fake_vault');

    if (!await mainVaultDir.exists()) {
      await mainVaultDir.create(recursive: true);
    }

    if (!await fakeVaultDir.exists()) {
      await fakeVaultDir.create(recursive: true);
    }

    await _ensureNoMediaFile(mainVaultDir);
    await _ensureNoMediaFile(fakeVaultDir);
  }

  static Future<void> _ensureNoMediaFile(Directory dir) async {
    try {
      final noMedia = File(path.join(dir.path, '.nomedia'));
      if (!await noMedia.exists()) {
        await noMedia.writeAsString('');
      }
    } catch (e) {
      debugPrint('Error creating .nomedia file: $e');
    }
  }

  static Future<void> _saveVideoToVault(VaultVideo video) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _isInFakeMode ? _fakeVideosKey : _mainVideosKey;

    final videosJson = prefs.getString(key) ?? '[]';
    final videosList = json.decode(videosJson) as List;
    videosList.add(video.toJson());

    await prefs.setString(key, json.encode(videosList));
  }

  static Future<List<VaultVideo>> _getVaultVideos() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _isInFakeMode ? _fakeVideosKey : _mainVideosKey;

    final videosJson = prefs.getString(key) ?? '[]';
    final videosList = json.decode(videosJson) as List;

    return videosList.map((json) => VaultVideo.fromJson(json)).toList();
  }

  static Future<void> _removeVideoFromVault(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _isInFakeMode ? _fakeVideosKey : _mainVideosKey;

    final videosJson = prefs.getString(key) ?? '[]';
    final videosList = json.decode(videosJson) as List;

    videosList.removeWhere((video) => video['id'] == videoId);

    await prefs.setString(key, json.encode(videosList));
  }

  static String _generateEncryptionKey() {
    final key = encrypt.Key.fromSecureRandom(32); // 256-bit key
    return key.base64;
  }



  // Legacy/Helper
  static Future<bool> deleteFromVault(String videoId) async {
    if (!_isAuthenticated) return false;

    try {
      final videos = await _getVaultVideos();
      final video = videos.firstWhere((v) => v.id == videoId);

      final hiddenFile = File(video.hiddenPath);
      if (await hiddenFile.exists()) {
        await hiddenFile.delete(); // Simplified delete
      }

      await _removeVideoFromVault(videoId);

      debugPrint('Video deleted from vault: ${video.fileName}');
      return true;
    } catch (e) {
      debugPrint('Error deleting from vault: $e');
      return false;
    }
  }

  static Future<void> clearVault() async {
    if (!_isAuthenticated) return;

    try {
      final videos = await _getVaultVideos();

      for (final video in videos) {
        final hiddenFile = File(video.hiddenPath);
        if (await hiddenFile.exists()) {
          await hiddenFile.delete();
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final key = _isInFakeMode ? _fakeVideosKey : _mainVideosKey;
      await prefs.setString(key, '[]');

      debugPrint('Vault cleared');
    } catch (e) {
      debugPrint('Error clearing vault: $e');
    }
  }

  static Future<int> getVaultSize() async {
    if (!_isAuthenticated) return 0;

    try {
      final videos = await _getVaultVideos();
      int totalSize = 0;

      for (final video in videos) {
        final hiddenFile = File(video.hiddenPath);
        if (await hiddenFile.exists()) {
          totalSize += await hiddenFile.length();
        }
      }

      return totalSize;
    } catch (e) {
      debugPrint('Error calculating vault size: $e');
      return 0;
    }
  }

  static Future<bool> verifyVaultIntegrity() async {
    if (!_isAuthenticated) return false;

    try {
      final videos = await _getVaultVideos();

      for (final video in videos) {
        final hiddenFile = File(video.hiddenPath);
        if (!await hiddenFile.exists()) {
          debugPrint('Missing file detected: ${video.fileName}');
          return false;
        }
      }

      debugPrint('Vault integrity verification passed');
      return true;
    } catch (e) {
      debugPrint('Error during vault integrity check: $e');
      return false;
    }
  }

  /// Replaces both passwords. Requires an unlocked *main* vault and the
  /// current main password; the decoy password cannot change the real one.
  static Future<bool> changePassword(
    String oldPassword,
    String newMainPassword,
    String newFakePassword,
  ) async {
    if (!_isAuthenticated || _isInFakeMode) return false;
    if (newMainPassword.length < minPasswordLength ||
        newFakePassword.length < minPasswordLength ||
        newMainPassword == newFakePassword) {
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final mainHash = prefs.getString(_mainVaultKey) ?? '';
      if (!await _verifySecret(oldPassword, mainHash)) return false;

      final hashes = await Future.wait([
        _hashSecret(newMainPassword),
        _hashSecret(newFakePassword),
      ]);
      await prefs.setString(_mainVaultKey, hashes[0]);
      await prefs.setString(_fakeVaultKey, hashes[1]);

      debugPrint('Passwords changed successfully');
      return true;
    } catch (e) {
      debugPrint('Error changing passwords: $e');
      return false;
    }
  }

  static Future<void> hardResetVault() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Clear all files
      final appDir = await getApplicationDocumentsDirectory();
      final mainVaultDir = Directory('${appDir.path}/main_vault');
      final fakeVaultDir = Directory('${appDir.path}/fake_vault');

      if (await mainVaultDir.exists()) {
        await mainVaultDir.delete(recursive: true);
      }
      if (await fakeVaultDir.exists()) {
        await fakeVaultDir.delete(recursive: true);
      }

      // Clear all keys
      await prefs.remove(_mainVaultKey);
      await prefs.remove(_fakeVaultKey);
      await prefs.remove(_mainVideosKey);
      await prefs.remove(_fakeVideosKey);
      await prefs.remove(_isSetupKey);
      await prefs.remove(_fakeModeKey);
      await prefs.remove(_securityQuestionsKey);
      await prefs.remove(_securityAnswersKey);
      await prefs.remove(_securitySetupKey);
      await prefs.remove(_failedAttemptsKey);
      await prefs.remove(_lockedUntilKey);

      _isAuthenticated = false;
      _isInFakeMode = false;

      debugPrint('Vault hard reset completed');
    } catch (e) {
      debugPrint('Error during hard reset: $e');
    }
  }

  static Future<String?> exportVideoForSharing(VaultVideo video) async {
    if (!_isAuthenticated) return null;

    try {
      final tempDir = await getTemporaryDirectory();
      final exportPath = path.join(tempDir.path, 'shared_${video.fileName}');
      final exportFile = File(exportPath);

      if (await exportFile.exists()) {
        await exportFile.delete();
      }

      final success = video.isEncrypted
          ? await _decryptVideoToPath(video, exportPath)
          : await _copyVideoToPath(
              sourcePath: video.hiddenPath,
              destinationPath: exportPath,
            );
      if (!success) return null;

      return exportPath;
    } catch (e) {
      debugPrint('Error exporting video for sharing: $e');
      return null;
    }
  }

  static Future<String?> exportVideoForPlayback(
    VaultVideo video, {
    ValueChanged<double>? onProgress,
  }) async {
    if (!_isAuthenticated) return null;

    try {
      final tempDir = await getTemporaryDirectory();
      final exportPath = path.join(tempDir.path, 'vault_play_${video.fileName}');
      final exportFile = File(exportPath);

      if (await exportFile.exists()) {
        await exportFile.delete();
      }

      final success = video.isEncrypted
          ? await _decryptVideoToPath(
              video,
              exportPath,
              onProgress: onProgress,
            )
          : await _copyVideoToPath(
              sourcePath: video.hiddenPath,
              destinationPath: exportPath,
              onProgress: onProgress,
            );
      if (!success) return null;

      return exportPath;
    } catch (e) {
      debugPrint('Error exporting video for playback: $e');
      return null;
    }
  }

  static Future<bool> _decryptVideoToPath(
    VaultVideo video,
    String destinationPath, {
    ValueChanged<double>? onProgress,
  }
  ) async {
    RandomAccessFile? hiddenRaf;
    IOSink? destSink;
    File? destFile;

    try {
      final hiddenFile = File(video.hiddenPath);
      if (!await hiddenFile.exists()) return false;

      final key = encrypt.Key.fromBase64(video.encryptionKey);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));

      hiddenRaf = await hiddenFile.open(mode: FileMode.read);
      final hiddenSize = await hiddenFile.length();

      destFile = File(destinationPath);
      final destDir = destFile.parent;
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      destSink = destFile.openWrite();

      final output = AccumulatorSink<Digest>();
      final checksumSink = sha256.startChunkedConversion(output);

      int bytesProcessed = 0;
      int bytesSinceYield = 0;

      while (bytesProcessed < hiddenSize) {
        if (hiddenSize - bytesProcessed < 20) break;

        final ivBytes = await hiddenRaf.read(16);
        final lenBytes = await hiddenRaf.read(4);

        final encryptedLen = ByteData.view(
          lenBytes.buffer,
        ).getUint32(0, Endian.big);

        final encryptedData = await hiddenRaf.read(encryptedLen);

        final iv = encrypt.IV(ivBytes);
        final decryptedBytes = encrypter.decryptBytes(
          encrypt.Encrypted(encryptedData),
          iv: iv,
        );

        destSink.add(decryptedBytes);
        checksumSink.add(decryptedBytes);

        bytesProcessed += 16 + 4 + encryptedLen;
        bytesSinceYield += 16 + 4 + encryptedLen;

        if (onProgress != null && hiddenSize > 0) {
          onProgress(bytesProcessed / hiddenSize);
        }

        if (bytesSinceYield >= _yieldEveryBytes) {
          bytesSinceYield = 0;
          await Future.delayed(Duration.zero);
        }
      }

      await destSink.flush();
      await destSink.close();
      await hiddenRaf.close();

      checksumSink.close();
      final calculatedChecksum = output.events.single.toString();

      if (calculatedChecksum != video.checksum) {
        debugPrint('Checksum mismatch! Video might be corrupted.');
      }

      onProgress?.call(1.0);
      return true;
    } catch (e) {
      debugPrint('Error decrypting video: $e');
      try {
        await destSink?.close();
        await hiddenRaf?.close();
        if (destFile != null && await destFile.exists()) {
          await destFile.delete();
        }
      } catch (_) {
        // ignore cleanup errors
      }
      return false;
    }
  }

  static Future<bool> _copyVideoToPath({
    required String sourcePath,
    required String destinationPath,
    ValueChanged<double>? onProgress,
  }) async {
    RandomAccessFile? sourceRaf;
    IOSink? destSink;
    File? destFile;

    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) return false;

      final sourceSize = await sourceFile.length();
      sourceRaf = await sourceFile.open(mode: FileMode.read);

      destFile = File(destinationPath);
      final destDir = destFile.parent;
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      destSink = destFile.openWrite();

      int bytesRead = 0;
      int bytesSinceYield = 0;

      while (bytesRead < sourceSize) {
        final remaining = sourceSize - bytesRead;
        final toRead = remaining < _chunkSize ? remaining : _chunkSize;
        final dataBytes = await sourceRaf.read(toRead);

        destSink.add(dataBytes);

        bytesRead += toRead;
        bytesSinceYield += toRead;

        if (onProgress != null && sourceSize > 0) {
          onProgress(bytesRead / sourceSize);
        }

        if (bytesSinceYield >= _yieldEveryBytes) {
          bytesSinceYield = 0;
          await Future.delayed(Duration.zero);
        }
      }

      await destSink.flush();
      await destSink.close();
      await sourceRaf.close();

      onProgress?.call(1.0);
      return true;
    } catch (e) {
      debugPrint('Error copying video: $e');
      try {
        await destSink?.close();
        await sourceRaf?.close();
        if (destFile != null && await destFile.exists()) {
          await destFile.delete();
        }
      } catch (_) {
        // ignore cleanup errors
      }
      return false;
    }
  }

  static Future<bool> _moveFileToPath({
    required File sourceFile,
    required String destinationPath,
    ValueChanged<double>? onProgress,
  }) async {
    try {
      final destFile = File(destinationPath);
      final destDir = destFile.parent;
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      try {
        await sourceFile.rename(destinationPath);
        onProgress?.call(1.0);
        return true;
      } catch (_) {
        final copied = await _copyVideoToPath(
          sourcePath: sourceFile.path,
          destinationPath: destinationPath,
          onProgress: onProgress,
        );
        if (!copied) return false;

        try {
          await sourceFile.delete();
        } catch (_) {
          // If we can't delete, treat as failure to avoid leaving duplicates
          return false;
        }

        return true;
      }
    } catch (e) {
      debugPrint('Error moving video: $e');
      return false;
    }
  }

  static Future<VaultPlaybackHandle> prepareDirectPlayback(
    VaultVideo video,
  ) async {
    final hiddenFile = File(video.hiddenPath);
    if (!await hiddenFile.exists()) {
      return VaultPlaybackHandle(video.hiddenPath, video.hiddenPath);
    }

    final extension = video.originalExtension.trim();
    if (extension.isEmpty) {
      return VaultPlaybackHandle(video.hiddenPath, video.hiddenPath);
    }

    final currentExt = path.extension(video.hiddenPath).replaceFirst('.', '');
    if (currentExt.toLowerCase() == extension.toLowerCase()) {
      return VaultPlaybackHandle(video.hiddenPath, video.hiddenPath);
    }

    final renamedPath = path.join(
      hiddenFile.parent.path,
      '${video.id}.$extension',
    );
    final tempPlaybackDir = Directory(
      path.join(hiddenFile.parent.path, 'playback_temp'),
    );
    try {
      if (!await tempPlaybackDir.exists()) {
        await tempPlaybackDir.create(recursive: true);
      }
      await _ensureNoMediaFile(tempPlaybackDir);
    } catch (e) {
      debugPrint('Error preparing playback temp directory: $e');
    }
    final tempPlaybackPath = path.join(
      tempPlaybackDir.path,
      '${video.id}.$extension',
    );

    try {
      // Try to open for read to detect obvious locks before rename.
      final raf = await hiddenFile.open(mode: FileMode.read);
      await raf.close();
      final renamedFile = await hiddenFile.rename(renamedPath);
      return VaultPlaybackHandle(renamedFile.path, video.hiddenPath);
    } catch (e) {
      debugPrint('Error renaming vault file for playback: $e');
      try {
        final copied = await hiddenFile.copy(tempPlaybackPath);
        return VaultPlaybackHandle(
          copied.path,
          video.hiddenPath,
          renameFailed: true,
          copyCreated: true,
        );
      } catch (copyError) {
        debugPrint('Error copying vault file for playback: $copyError');
        return VaultPlaybackHandle(
          video.hiddenPath,
          video.hiddenPath,
          renameFailed: true,
        );
      }
    }
  }

  static Future<void> restoreDirectPlayback(VaultPlaybackHandle handle) async {
    if (handle.playPath == handle.originalHiddenPath) return;
    try {
      final current = File(handle.playPath);
      if (await current.exists()) {
        if (handle.copyCreated) {
          await current.delete();
        } else {
          await current.rename(handle.originalHiddenPath);
        }
      }
    } catch (e) {
      debugPrint('Error restoring vault file name: $e');
    }
  }

  static Future<void> cleanupPlaybackTempFiles() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final mainTempDir = Directory(
        path.join(appDir.path, 'main_vault', 'playback_temp'),
      );
      final fakeTempDir = Directory(
        path.join(appDir.path, 'fake_vault', 'playback_temp'),
      );

      for (final dir in [mainTempDir, fakeTempDir]) {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('Error cleaning playback temp files: $e');
    }
  }
}

class VaultPlaybackHandle {
  final String playPath;
  final String originalHiddenPath;
  final bool renameFailed;
  final bool copyCreated;

  const VaultPlaybackHandle(
    this.playPath,
    this.originalHiddenPath, {
    this.renameFailed = false,
    this.copyCreated = false,
  });
}
