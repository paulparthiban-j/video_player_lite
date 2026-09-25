import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/security/password_hasher.dart';
import '../core/security/vault_crypto.dart';
import 'thumbnail_service.dart';
import 'vault_stream_server.dart';
import 'video_scanner_service.dart';

/// How a vault file is stored on disk.
enum VaultFileFormat {
  /// Moved into the vault without encryption (vaults from older versions).
  /// Upgraded by [VaultService.encryptPendingVideos].
  plain,

  /// Chunked AES-256-GCM, see [VaultCrypto].
  encrypted,
}

class VaultVideo {
  final String id;
  final String originalPath;
  final String hiddenPath;
  final String fileName;
  final String originalExtension;
  final int fileSize;
  final DateTime hiddenDate;
  final VaultFileFormat format;

  const VaultVideo({
    required this.id,
    required this.originalPath,
    required this.hiddenPath,
    required this.fileName,
    required this.originalExtension,
    required this.fileSize,
    required this.hiddenDate,
    required this.format,
  });

  bool get isEncrypted => format == VaultFileFormat.encrypted;

  VaultVideo copyWith({String? hiddenPath, VaultFileFormat? format}) {
    return VaultVideo(
      id: id,
      originalPath: originalPath,
      hiddenPath: hiddenPath ?? this.hiddenPath,
      fileName: fileName,
      originalExtension: originalExtension,
      fileSize: fileSize,
      hiddenDate: hiddenDate,
      format: format ?? this.format,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'originalPath': originalPath,
    'hiddenPath': hiddenPath,
    'fileName': fileName,
    'originalExtension': originalExtension,
    'fileSize': fileSize,
    'hiddenDate': hiddenDate.toIso8601String(),
    'format': format.name,
  };

  factory VaultVideo.fromJson(Map<String, dynamic> json) {
    final fileName = (json['fileName'] ?? '').toString();
    final storedExt = (json['originalExtension'] ?? '').toString().trim();
    return VaultVideo(
      id: json['id'] as String,
      originalPath: json['originalPath'] as String,
      hiddenPath: json['hiddenPath'] as String,
      fileName: fileName,
      originalExtension: storedExt.isNotEmpty
          ? storedExt
          : path.extension(fileName).replaceFirst('.', ''),
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      hiddenDate:
          DateTime.tryParse(json['hiddenDate']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      // Entries written before encryption existed carry no format field and
      // were always stored as plain files.
      format: json['format'] == VaultFileFormat.encrypted.name
          ? VaultFileFormat.encrypted
          : VaultFileFormat.plain,
    );
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

/// What the player should open for a vault video.
class VaultPlayback {
  /// Loopback URL for encrypted videos, otherwise null.
  final Uri? url;

  /// Local file handle for plain (legacy) videos, otherwise null.
  final VaultPlaybackHandle? fileHandle;

  const VaultPlayback._({this.url, this.fileHandle});

  /// Releases the URL or restores the renamed file. Call when playback ends.
  Future<void> release() async {
    final url = this.url;
    if (url != null) VaultStreamServer.unregister(url);
    final handle = fileHandle;
    if (handle != null) await VaultService.restoreDirectPlayback(handle);
  }
}

/// Password-protected hidden folder with a decoy vault.
///
/// ## Key hierarchy
///
/// Each vault (main and decoy) has a random 256-bit data key that encrypts
/// its files and its metadata list. The data key is stored only in wrapped
/// form:
///
/// * main key, wrapped by a key derived from the main password;
/// * main key, wrapped by a key derived from the recovery answers, so a
///   password reset keeps existing files readable;
/// * decoy key, wrapped by a key derived from the decoy password;
/// * decoy key, wrapped by the main key, so the owner can rotate the decoy
///   password.
///
/// The unwrapped key lives in memory only while the vault is unlocked.
class VaultService {
  static const String _mainVaultKey = 'main_vault_password';
  static const String _fakeVaultKey = 'fake_vault_password';
  static const String _mainVideosKey = 'main_vault_videos';
  static const String _fakeVideosKey = 'fake_vault_videos';
  static const String _isSetupKey = 'vault_is_setup';
  static const String _fakeModeKey = 'is_fake_mode';

  // Wrapped data keys
  static const String _mainDataKeyKey = 'vault_main_dek';
  static const String _fakeDataKeyKey = 'vault_fake_dek';
  static const String _mainRecoveryDataKeyKey = 'vault_main_dek_recovery';
  static const String _fakeDataKeyByMainKey = 'vault_fake_dek_by_main';

  // Security Questions Keys
  static const String _securityQuestionsKey = 'security_questions';
  // Legacy: one hash per answer (each crackable on its own).
  static const String _securityAnswersKey = 'security_answers';
  // Current: one hash over all answers together.
  static const String _securityAnswersCombinedKey = 'security_answers_all';
  static const String _questionCountKey = 'security_question_count';
  static const String _securitySetupKey = 'security_setup_done';

  // Brute-force protection
  static const String _failedAttemptsKey = 'vault_failed_attempts';
  static const String _lockedUntilKey = 'vault_locked_until_ms';
  static const int _freeAttempts = 5;
  static const Duration _baseLockout = Duration(seconds: 30);
  static const Duration _maxLockout = Duration(hours: 1);

  /// Minimum accepted length for vault passwords.
  static const int minPasswordLength = 4;

  static const String _encryptedMetadataPrefix = 'enc1:';
  static const String _plainHiddenExtension = 'vault';
  static const String _encryptedHiddenExtension = 'pvault';
  static const int _copyChunkSize = 8 * 1024 * 1024;

  static final Random _random = Random.secure();

  static bool _isInFakeMode = false;
  static bool _isAuthenticated = false;
  static Uint8List? _dataKey;

  static bool get isInFakeMode => _isInFakeMode;
  static bool get isAuthenticated => _isAuthenticated;

  // ---------------------------------------------------------------------------
  // Recovery questions
  // ---------------------------------------------------------------------------

  static Future<bool> isSecuritySetup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_securitySetupKey) ?? false;
  }

  /// Whether the main vault key is recoverable through the recovery answers.
  /// Vaults created by older versions lack this until questions are re-saved.
  static Future<bool> hasRecoveryKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_mainRecoveryDataKeyKey) != null;
  }

  /// True when the unlocked vault should ask the owner to (re)configure
  /// recovery questions before continuing.
  static Future<bool> needsRecoverySetup() async {
    if (!_isAuthenticated || _isInFakeMode) return false;
    return !await isSecuritySetup() || !await hasRecoveryKey();
  }

  /// Stores recovery questions. Only the owner of the main vault may do this;
  /// otherwise anyone holding the decoy password (or nobody at all) could set
  /// answers and then use them to reset the main password.
  static Future<bool> setSecurityQuestions(
    List<String> questions,
    List<String> answers,
  ) async {
    final dataKey = _dataKey;
    if (!_isAuthenticated || _isInFakeMode || dataKey == null) return false;
    if (questions.length != answers.length || questions.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();

      final secret = _recoverySecret(answers.map(normalizeAnswer).toList());
      // A single hash over all answers: guessing one answer at a time
      // against separate hashes is no longer possible.
      final results = await Future.wait([
        _hashSecret(secret),
        VaultCrypto.wrapKeyWithSecret(dataKey, secret),
      ]);

      await prefs.setStringList(_securityQuestionsKey, questions);
      await prefs.setString(_securityAnswersCombinedKey, results[0]);
      await prefs.setInt(_questionCountKey, questions.length);
      await prefs.remove(_securityAnswersKey);
      await prefs.setString(_mainRecoveryDataKeyKey, results[1]);
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

  static String _recoverySecret(List<String> normalizedAnswers) =>
      normalizedAnswers.join('\u0000');

  static Future<bool> verifySecurityAnswers(List<String> answers) async {
    if (await getLockoutRemaining() > Duration.zero) return false;
    try {
      final prefs = await SharedPreferences.getInstance();

      final combined = prefs.getString(_securityAnswersCombinedKey);
      if (combined != null) {
        final expectedCount = prefs.getInt(_questionCountKey);
        final matches =
            answers.length == expectedCount &&
            await _verifySecret(
              _recoverySecret(answers.map(normalizeAnswer).toList()),
              combined,
            );
        if (matches) {
          await _clearFailedAttempts();
        } else {
          await _registerFailedAttempt();
        }
        return matches;
      }

      // Vaults whose questions were set before the combined hash existed.
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
  /// The main data key is recovered with the answers and re-wrapped, so
  /// encrypted videos stay readable. The decoy password is left untouched,
  /// and the new main password must differ from it.
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

      Uint8List? dataKey;
      final recoveryWrap = prefs.getString(_mainRecoveryDataKeyKey);
      if (recoveryWrap != null) {
        dataKey = await VaultCrypto.unwrapKeyWithSecret(
          recoveryWrap,
          _recoverySecret(answers.map(normalizeAnswer).toList()),
        );
        if (dataKey == null) return false;
      } else if (prefs.getString(_mainDataKeyKey) != null) {
        // Only possible for vaults that never re-saved their questions after
        // upgrading; they have no encrypted content yet (encryption starts
        // after recovery setup), so a fresh key loses nothing.
        dataKey = VaultCrypto.newKey();
        await prefs.remove(_fakeDataKeyByMainKey);
      }

      await prefs.setString(_mainVaultKey, await _hashSecret(newPassword));
      if (dataKey != null) {
        await prefs.setString(
          _mainDataKeyKey,
          await VaultCrypto.wrapKeyWithSecret(dataKey, newPassword),
        );
      }
      await prefs.setBool(_isSetupKey, true);

      debugPrint('Main password reset using security questions');
      return true;
    } catch (e) {
      debugPrint('Error resetting password: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Setup and authentication
  // ---------------------------------------------------------------------------

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
      final mainKey = VaultCrypto.newKey();
      final fakeKey = VaultCrypto.newKey();

      final results = await Future.wait([
        _hashSecret(mainPassword),
        _hashSecret(fakePassword),
        VaultCrypto.wrapKeyWithSecret(mainKey, mainPassword),
        VaultCrypto.wrapKeyWithSecret(fakeKey, fakePassword),
        VaultCrypto.wrapKey(fakeKey, mainKey),
      ]);

      await prefs.setString(_mainVaultKey, results[0]);
      await prefs.setString(_fakeVaultKey, results[1]);
      await prefs.setString(_mainDataKeyKey, results[2]);
      await prefs.setString(_fakeDataKeyKey, results[3]);
      await prefs.setString(_fakeDataKeyByMainKey, results[4]);
      await prefs.setBool(_isSetupKey, true);
      await _clearFailedAttempts();

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

      final dataKey = await _loadOrCreateDataKey(
        prefs,
        password,
        isMain: isMain,
      );
      if (dataKey == null) {
        return const VaultAuthResult(VaultAuthStatus.error);
      }

      await _clearFailedAttempts();
      _dataKey = dataKey;
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
        isMain
            ? 'Authenticated with main vault'
            : 'Authenticated with fake vault',
      );
      await _createVaultDirectories();
      return const VaultAuthResult(VaultAuthStatus.success);
    } catch (e) {
      debugPrint('Authentication error: $e');
      return const VaultAuthResult(VaultAuthStatus.error);
    }
  }

  /// Unwraps the vault's data key, creating one for vaults set up before
  /// encryption existed.
  static Future<Uint8List?> _loadOrCreateDataKey(
    SharedPreferences prefs,
    String password, {
    required bool isMain,
  }) async {
    final storageKey = isMain ? _mainDataKeyKey : _fakeDataKeyKey;
    final wrapped = prefs.getString(storageKey);
    if (wrapped != null) {
      final key = await VaultCrypto.unwrapKeyWithSecret(wrapped, password);
      if (key == null) debugPrint('Vault key could not be unwrapped');
      return key;
    }

    final key = VaultCrypto.newKey();
    await prefs.setString(
      storageKey,
      await VaultCrypto.wrapKeyWithSecret(key, password),
    );
    return key;
  }

  static Future<void> logout() async {
    _isAuthenticated = false;
    _isInFakeMode = false;
    _dataKey?.fillRange(0, _dataKey!.length, 0);
    _dataKey = null;
    await VaultStreamServer.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fakeModeKey, false);
    debugPrint('Logged out from vault');
  }

  /// Replaces both passwords. Requires an unlocked *main* vault and the
  /// current main password; the decoy password cannot change the real one.
  ///
  /// Returns false if the decoy vault holds a key the main vault cannot
  /// recover (a decoy vault first opened after upgrading from a version
  /// without encryption); changing its password would orphan its files.
  static Future<bool> changePassword(
    String oldPassword,
    String newMainPassword,
    String newFakePassword,
  ) async {
    final mainKey = _dataKey;
    if (!_isAuthenticated || _isInFakeMode || mainKey == null) return false;
    if (newMainPassword.length < minPasswordLength ||
        newFakePassword.length < minPasswordLength ||
        newMainPassword == newFakePassword) {
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final mainHash = prefs.getString(_mainVaultKey) ?? '';
      if (!await _verifySecret(oldPassword, mainHash)) return false;

      Uint8List? fakeKey;
      final fakeByMain = prefs.getString(_fakeDataKeyByMainKey);
      if (fakeByMain != null) {
        fakeKey = await VaultCrypto.unwrapKey(fakeByMain, mainKey);
        if (fakeKey == null) return false;
      } else if (prefs.getString(_fakeDataKeyKey) != null) {
        return false;
      }

      await prefs.setString(_mainVaultKey, await _hashSecret(newMainPassword));
      await prefs.setString(_fakeVaultKey, await _hashSecret(newFakePassword));
      await prefs.setString(
        _mainDataKeyKey,
        await VaultCrypto.wrapKeyWithSecret(mainKey, newMainPassword),
      );
      if (fakeKey != null) {
        await prefs.setString(
          _fakeDataKeyKey,
          await VaultCrypto.wrapKeyWithSecret(fakeKey, newFakePassword),
        );
      }

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

      final appDir = await getApplicationDocumentsDirectory();
      for (final name in ['main_vault', 'fake_vault']) {
        final dir = Directory(path.join(appDir.path, name));
        if (await dir.exists()) await dir.delete(recursive: true);
      }

      for (final key in [
        _mainVaultKey,
        _fakeVaultKey,
        _mainVideosKey,
        _fakeVideosKey,
        _isSetupKey,
        _fakeModeKey,
        _securityQuestionsKey,
        _securityAnswersKey,
        _securityAnswersCombinedKey,
        _questionCountKey,
        _securitySetupKey,
        _failedAttemptsKey,
        _lockedUntilKey,
        _mainDataKeyKey,
        _fakeDataKeyKey,
        _mainRecoveryDataKeyKey,
        _fakeDataKeyByMainKey,
      ]) {
        await prefs.remove(key);
      }

      await logout();
      debugPrint('Vault hard reset completed');
    } catch (e) {
      debugPrint('Error during hard reset: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Videos
  // ---------------------------------------------------------------------------

  /// Encrypts [videoPath] into the vault and deletes the original.
  static Future<bool> hideVideo(
    String videoPath, {
    ValueChanged<double>? onProgress,
  }) async {
    final dataKey = _dataKey;
    if (!_isAuthenticated || dataKey == null) return false;

    final source = File(videoPath);
    File? hidden;
    try {
      if (!await source.exists()) return false;

      final videoId = _generateVideoId();
      final vaultDir = await _getVaultDirectory();
      hidden = File(
        path.join(vaultDir.path, '$videoId.$_encryptedHiddenExtension'),
      );
      final sourceSize = await source.length();

      await VaultCrypto.encryptFile(
        source,
        hidden,
        dataKey,
        onProgress: onProgress,
      );

      final vaultVideo = VaultVideo(
        id: videoId,
        originalPath: videoPath,
        hiddenPath: hidden.path,
        fileName: path.basename(videoPath),
        originalExtension: path.extension(videoPath).replaceFirst('.', ''),
        fileSize: sourceSize,
        hiddenDate: DateTime.now(),
        format: VaultFileFormat.encrypted,
      );

      // Remove the original last: if that fails, undo so the video is not
      // left in two places.
      try {
        await source.delete();
      } catch (e) {
        debugPrint('Could not delete original after encrypting: $e');
        await hidden.delete();
        return false;
      }

      await _updateVideos((videos) => [...videos, vaultVideo]);
      await VideoScannerService.removeFromCache(videoPath);
      await ThumbnailService.deleteThumbnail(videoPath);

      onProgress?.call(1.0);
      debugPrint('Video hidden and encrypted');
      return true;
    } catch (e) {
      debugPrint('Error hiding video: $e');
      if (hidden != null && await source.exists() && await hidden.exists()) {
        await hidden.delete();
      }
      return false;
    }
  }

  /// Restores a video to its original folder (or a free name next to it).
  static Future<bool> unhideVideo(
    String videoId, {
    ValueChanged<double>? onProgress,
  }) async {
    if (!_isAuthenticated) return false;

    try {
      final video = (await _getVaultVideos()).firstWhere(
        (v) => v.id == videoId,
      );
      // Never clobber a file that has since appeared at the original path.
      final destination = await availablePath(video.originalPath);

      final success = video.isEncrypted
          ? await _decryptVideoToPath(
              video,
              destination,
              onProgress: onProgress,
            )
          : await _moveFileToPath(
              sourceFile: File(video.hiddenPath),
              destinationPath: destination,
              onProgress: onProgress,
            );
      if (!success) return false;

      if (video.isEncrypted) {
        final hidden = File(video.hiddenPath);
        if (await hidden.exists()) await hidden.delete();
      }
      await _updateVideos(
        (videos) => videos.where((v) => v.id != videoId).toList(),
      );

      debugPrint('Video restored from vault');
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

  /// Number of videos in the open vault still stored without encryption.
  static Future<int> countUnencryptedVideos() async {
    if (!_isAuthenticated) return 0;
    return (await _getVaultVideos()).where((v) => !v.isEncrypted).length;
  }

  /// Encrypts videos hidden by versions that stored them as plain files.
  ///
  /// Each file is encrypted to a new path, the metadata is switched over,
  /// and only then is the plain file deleted, so an interruption never loses
  /// a video. Returns the number of videos encrypted.
  static Future<int> encryptPendingVideos({
    void Function(int done, int total, double fileProgress)? onProgress,
  }) async {
    final dataKey = _dataKey;
    if (!_isAuthenticated || dataKey == null) return 0;

    final pending = (await _getVaultVideos())
        .where((v) => !v.isEncrypted)
        .toList();
    var done = 0;
    for (final video in pending) {
      final plain = File(video.hiddenPath);
      if (!await plain.exists()) {
        done++;
        continue;
      }
      final encrypted = File(
        path.join(plain.parent.path, '${video.id}.$_encryptedHiddenExtension'),
      );
      try {
        await VaultCrypto.encryptFile(
          plain,
          encrypted,
          dataKey,
          onProgress: (p) => onProgress?.call(done, pending.length, p),
        );
        await _updateVideos(
          (videos) => [
            for (final v in videos)
              v.id == video.id
                  ? v.copyWith(
                      hiddenPath: encrypted.path,
                      format: VaultFileFormat.encrypted,
                    )
                  : v,
          ],
        );
        await plain.delete();
      } catch (e) {
        debugPrint('Error encrypting existing vault video: $e');
        if (await encrypted.exists() && await plain.exists()) {
          await encrypted.delete();
        }
        continue;
      }
      done++;
      onProgress?.call(done, pending.length, 1.0);
    }
    return done;
  }

  /// Prepares [video] for the player. Encrypted videos are streamed through
  /// [VaultStreamServer]; call [VaultPlayback.release] when done.
  static Future<VaultPlayback> openForPlayback(VaultVideo video) async {
    final dataKey = _dataKey;
    if (video.isEncrypted) {
      if (!_isAuthenticated || dataKey == null) {
        throw StateError('Vault is locked');
      }
      final url = await VaultStreamServer.register(
        file: File(video.hiddenPath),
        key: dataKey,
        extension: video.originalExtension,
      );
      return VaultPlayback._(url: url);
    }
    return VaultPlayback._(fileHandle: await prepareDirectPlayback(video));
  }

  static Future<bool> deleteFromVault(String videoId) async {
    if (!_isAuthenticated) return false;

    try {
      final video = (await _getVaultVideos()).firstWhere(
        (v) => v.id == videoId,
      );
      final hiddenFile = File(video.hiddenPath);
      if (await hiddenFile.exists()) await hiddenFile.delete();

      await _updateVideos(
        (videos) => videos.where((v) => v.id != videoId).toList(),
      );
      debugPrint('Video deleted from vault');
      return true;
    } catch (e) {
      debugPrint('Error deleting from vault: $e');
      return false;
    }
  }

  static Future<void> clearVault() async {
    if (!_isAuthenticated) return;

    try {
      for (final video in await _getVaultVideos()) {
        final hiddenFile = File(video.hiddenPath);
        if (await hiddenFile.exists()) await hiddenFile.delete();
      }
      await _updateVideos((_) => []);
      debugPrint('Vault cleared');
    } catch (e) {
      debugPrint('Error clearing vault: $e');
    }
  }

  static Future<int> getVaultSize() async {
    if (!_isAuthenticated) return 0;

    try {
      int totalSize = 0;
      for (final video in await _getVaultVideos()) {
        final hiddenFile = File(video.hiddenPath);
        if (await hiddenFile.exists()) totalSize += await hiddenFile.length();
      }
      return totalSize;
    } catch (e) {
      debugPrint('Error calculating vault size: $e');
      return 0;
    }
  }

  /// Checks that every vault file exists and that encrypted files have a
  /// valid, authenticated first chunk.
  static Future<bool> verifyVaultIntegrity() async {
    final dataKey = _dataKey;
    if (!_isAuthenticated || dataKey == null) return false;

    try {
      for (final video in await _getVaultVideos()) {
        final hiddenFile = File(video.hiddenPath);
        if (!await hiddenFile.exists()) {
          debugPrint('Missing vault file detected');
          return false;
        }
        if (video.isEncrypted) {
          final reader = await EncryptedFileReader.open(hiddenFile, dataKey);
          try {
            await reader.readChunk(0);
          } finally {
            await reader.close();
          }
        }
      }
      debugPrint('Vault integrity verification passed');
      return true;
    } catch (e) {
      debugPrint('Error during vault integrity check: $e');
      return false;
    }
  }

  /// Writes a decrypted copy to the temp directory for the share sheet.
  static Future<String?> exportVideoForSharing(VaultVideo video) =>
      _exportToTemp(video, 'share');

  /// Writes a decrypted copy to the temp directory.
  static Future<String?> exportVideoForPlayback(
    VaultVideo video, {
    ValueChanged<double>? onProgress,
  }) => _exportToTemp(video, 'play', onProgress: onProgress);

  static Future<String?> _exportToTemp(
    VaultVideo video,
    String purpose, {
    ValueChanged<double>? onProgress,
  }) async {
    if (!_isAuthenticated) return null;

    try {
      final exportDir = Directory(
        path.join((await _exportRoot()).path, purpose, video.id),
      );
      await exportDir.create(recursive: true);
      final exportPath = path.join(
        exportDir.path,
        path.basename(video.fileName),
      );
      final exportFile = File(exportPath);
      if (await exportFile.exists()) await exportFile.delete();

      final success = video.isEncrypted
          ? await _decryptVideoToPath(video, exportPath, onProgress: onProgress)
          : await _copyVideoToPath(
              sourcePath: video.hiddenPath,
              destinationPath: exportPath,
              onProgress: onProgress,
            );
      return success ? exportPath : null;
    } catch (e) {
      debugPrint('Error exporting vault video: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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
    final vaultDir = Directory(
      path.join(appDir.path, _isInFakeMode ? 'fake_vault' : 'main_vault'),
    );
    if (!await vaultDir.exists()) await vaultDir.create(recursive: true);
    await _ensureNoMediaFile(vaultDir);
    return vaultDir;
  }

  static Future<void> _createVaultDirectories() async {
    final appDir = await getApplicationDocumentsDirectory();
    for (final name in ['main_vault', 'fake_vault']) {
      final dir = Directory(path.join(appDir.path, name));
      if (!await dir.exists()) await dir.create(recursive: true);
      await _ensureNoMediaFile(dir);
    }
  }

  static Future<void> _ensureNoMediaFile(Directory dir) async {
    try {
      final noMedia = File(path.join(dir.path, '.nomedia'));
      if (!await noMedia.exists()) await noMedia.writeAsString('');
    } catch (e) {
      debugPrint('Error creating .nomedia file: $e');
    }
  }

  /// Decrypted exports (share sheet, legacy playback) live here and are
  /// wiped by [cleanupPlaybackTempFiles].
  static Future<Directory> _exportRoot() async => Directory(
    path.join((await getTemporaryDirectory()).path, 'vault_export'),
  );

  static String get _videosPrefsKey =>
      _isInFakeMode ? _fakeVideosKey : _mainVideosKey;

  /// Reads the vault's video list, decrypting it when needed. Lists written
  /// by older versions are plain JSON and are encrypted on the next write.
  static Future<List<VaultVideo>> _getVaultVideos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_videosPrefsKey);
    if (raw == null || raw.isEmpty) return [];

    String json;
    if (raw.startsWith(_encryptedMetadataPrefix)) {
      final dataKey = _dataKey;
      if (dataKey == null) return [];
      json = await VaultCrypto.openString(
        raw.substring(_encryptedMetadataPrefix.length),
        dataKey,
      );
    } else {
      json = raw;
    }
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((e) => VaultVideo.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> _saveVaultVideos(List<VaultVideo> videos) async {
    final dataKey = _dataKey;
    if (dataKey == null) throw StateError('Vault is locked');
    final prefs = await SharedPreferences.getInstance();
    final sealed = await VaultCrypto.sealString(
      jsonEncode(videos.map((v) => v.toJson()).toList()),
      dataKey,
    );
    await prefs.setString(_videosPrefsKey, '$_encryptedMetadataPrefix$sealed');
  }

  static Future<void> _updateVideos(
    List<VaultVideo> Function(List<VaultVideo> videos) update,
  ) async {
    await _saveVaultVideos(update(await _getVaultVideos()));
  }

  static Future<bool> _decryptVideoToPath(
    VaultVideo video,
    String destinationPath, {
    ValueChanged<double>? onProgress,
  }) async {
    final dataKey = _dataKey;
    if (dataKey == null) return false;
    try {
      await VaultCrypto.decryptFile(
        File(video.hiddenPath),
        File(destinationPath),
        dataKey,
        onProgress: onProgress,
      );
      onProgress?.call(1.0);
      return true;
    } catch (e) {
      debugPrint('Error decrypting vault video: $e');
      return false;
    }
  }

  static Future<bool> _copyVideoToPath({
    required String sourcePath,
    required String destinationPath,
    ValueChanged<double>? onProgress,
  }) async {
    final destFile = File(destinationPath);
    RandomAccessFile? input;
    RandomAccessFile? output;
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) return false;
      final size = await sourceFile.length();
      await destFile.parent.create(recursive: true);
      input = await sourceFile.open();
      output = await destFile.open(mode: FileMode.write);

      var copied = 0;
      while (copied < size) {
        final chunk = await input.read(_copyChunkSize);
        if (chunk.isEmpty) break;
        await output.writeFrom(chunk);
        copied += chunk.length;
        if (size > 0) onProgress?.call(copied / size);
      }
      await output.close();
      await input.close();
      onProgress?.call(1.0);
      return true;
    } catch (e) {
      debugPrint('Error copying video: $e');
      await output?.close();
      await input?.close();
      if (await destFile.exists()) await destFile.delete();
      return false;
    }
  }

  static Future<bool> _moveFileToPath({
    required File sourceFile,
    required String destinationPath,
    ValueChanged<double>? onProgress,
  }) async {
    try {
      await File(destinationPath).parent.create(recursive: true);
      try {
        await sourceFile.rename(destinationPath);
        onProgress?.call(1.0);
        return true;
      } on FileSystemException {
        // Different volume: fall back to copy + delete.
        final copied = await _copyVideoToPath(
          sourcePath: sourceFile.path,
          destinationPath: destinationPath,
          onProgress: onProgress,
        );
        if (!copied) return false;
        try {
          await sourceFile.delete();
        } catch (_) {
          // Can't delete: treat as failure to avoid leaving duplicates.
          await File(destinationPath).delete();
          return false;
        }
        return true;
      }
    } catch (e) {
      debugPrint('Error moving video: $e');
      return false;
    }
  }

  /// Plain (legacy) vault files are stored with a `.vault` extension the
  /// player can't sniff; rename (or copy) them to the original extension for
  /// the duration of playback.
  static Future<VaultPlaybackHandle> prepareDirectPlayback(
    VaultVideo video,
  ) async {
    final hiddenFile = File(video.hiddenPath);
    final extension = video.originalExtension.trim();
    final currentExt = path.extension(video.hiddenPath).replaceFirst('.', '');
    if (!await hiddenFile.exists() ||
        extension.isEmpty ||
        currentExt.toLowerCase() == extension.toLowerCase()) {
      return VaultPlaybackHandle(video.hiddenPath, video.hiddenPath);
    }

    final renamedPath = path.join(
      hiddenFile.parent.path,
      '${video.id}.$extension',
    );
    try {
      final renamed = await hiddenFile.rename(renamedPath);
      return VaultPlaybackHandle(renamed.path, video.hiddenPath);
    } catch (e) {
      debugPrint('Error renaming vault file for playback: $e');
      try {
        final tempDir = Directory(
          path.join(hiddenFile.parent.path, 'playback_temp'),
        );
        await tempDir.create(recursive: true);
        await _ensureNoMediaFile(tempDir);
        final copied = await hiddenFile.copy(
          path.join(tempDir.path, '${video.id}.$extension'),
        );
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

  /// Removes decrypted/copied files left behind by an interrupted session.
  static Future<void> cleanupPlaybackTempFiles() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      for (final name in ['main_vault', 'fake_vault']) {
        final dir = Directory(path.join(appDir.path, name, 'playback_temp'));
        if (await dir.exists()) await dir.delete(recursive: true);
      }
      final exportRoot = await _exportRoot();
      if (await exportRoot.exists()) await exportRoot.delete(recursive: true);
    } catch (e) {
      debugPrint('Error cleaning playback temp files: $e');
    }
  }

  @visibleForTesting
  static String get plainHiddenExtension => _plainHiddenExtension;

  /// Test hook: stores [videos] exactly as a pre-encryption version did.
  @visibleForTesting
  static Future<void> writeLegacyVideoList(
    List<VaultVideo> videos, {
    bool fake = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      fake ? _fakeVideosKey : _mainVideosKey,
      jsonEncode(videos.map((v) => v.toJson()..remove('format')).toList()),
    );
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
