// Every unlock spawns several isolates for key derivation, which is slow on
// busy CI and Windows machines.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/core/security/password_hasher.dart';
import 'package:next_gen_video_player/core/security/vault_crypto.dart';
import 'package:next_gen_video_player/services/vault_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUpAll(() {
    VaultCrypto.algorithm = DartAesGcm.with256bits();
    // The production work factor is far too slow for the pure-Dart cipher
    // and hasher used under test.
    PasswordHasher.defaultIterations = 1000;
  });

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('vault_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempRoot.path,
        );
    SharedPreferences.setMockInitialValues({});
    VaultService.elapsedRealtimeMs = () async => null;
    await VaultService.logout();
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  /// Unlocks the main vault and configures recovery, which videos need
  /// before they can be encrypted.
  Future<void> unlockMain() async {
    await VaultService.authenticate('main-pass');
    await VaultService.setSecurityQuestions(['Q?'], ['A']);
  }

  group('setup and unlock', () {
    test('rejects weak or identical passwords', () async {
      expect(await VaultService.setupVault('abc', 'decoy1'), isFalse);
      expect(await VaultService.setupVault('same1', 'same1'), isFalse);
      expect(await VaultService.isVaultSetup(), isFalse);
    });

    test('main and decoy passwords open their own vaults', () async {
      expect(await VaultService.setupVault('main-pass', 'decoy-pass'), isTrue);

      final main = await VaultService.unlock('main-pass');
      expect(main.status, VaultAuthStatus.success);
      expect(VaultService.isInFakeMode, isFalse);

      await VaultService.logout();
      final decoy = await VaultService.unlock('decoy-pass');
      expect(decoy.status, VaultAuthStatus.success);
      expect(VaultService.isInFakeMode, isTrue);

      await VaultService.logout();
      final wrong = await VaultService.unlock('nope');
      expect(wrong.status, VaultAuthStatus.invalidPassword);
      expect(VaultService.isAuthenticated, isFalse);
    });

    test('cannot overwrite an existing vault', () async {
      expect(await VaultService.setupVault('main-pass', 'decoy-pass'), isTrue);
      expect(await VaultService.setupVault('evil-main', 'evil-fake'), isFalse);
      expect(await VaultService.authenticate('main-pass'), isTrue);
    });

    test('passwords are stored salted, never as plain SHA-256', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('main_vault_password')!;
      expect(stored, startsWith(r'pbkdf2$'));
      expect(
        stored,
        isNot(sha256.convert(utf8.encode('main-pass')).toString()),
      );
    });

    test('legacy SHA-256 hashes still unlock and are upgraded', () async {
      String legacy(String s) => sha256.convert(utf8.encode(s)).toString();
      SharedPreferences.setMockInitialValues({
        'vault_is_setup': true,
        'main_vault_password': legacy('old-main'),
        'fake_vault_password': legacy('old-fake'),
      });

      expect(await VaultService.authenticate('old-main'), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('main_vault_password'), startsWith(r'pbkdf2$'));
      // The untouched decoy hash keeps working until it is used.
      expect(prefs.getString('fake_vault_password'), legacy('old-fake'));
    });

    test('locks out after repeated failures', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      VaultAuthResult? last;
      for (var i = 0; i < 5; i++) {
        last = await VaultService.unlock('wrong-$i');
      }
      expect(last!.status, VaultAuthStatus.lockedOut);
      expect(last.retryAfter, greaterThan(Duration.zero));

      // Even the right password is refused while locked out.
      final locked = await VaultService.unlock('main-pass');
      expect(locked.status, VaultAuthStatus.lockedOut);
    });

    test('lockout grows exponentially and is capped', () {
      expect(VaultService.lockoutFor(4), Duration.zero);
      expect(VaultService.lockoutFor(5), const Duration(seconds: 30));
      expect(VaultService.lockoutFor(6), const Duration(seconds: 60));
      expect(VaultService.lockoutFor(50), const Duration(hours: 1));
    });
  });

  group('password recovery', () {
    Future<void> setUpWithQuestions() async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await VaultService.authenticate('main-pass');
      expect(
        await VaultService.setSecurityQuestions(
          ['Pet?', 'City?'],
          ['Rex', 'New York'],
        ),
        isTrue,
      );
      await VaultService.logout();
    }

    test('only the unlocked main vault may set questions', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      expect(await VaultService.setSecurityQuestions(['Q'], ['A']), isFalse);

      await VaultService.authenticate('decoy-pass');
      expect(await VaultService.setSecurityQuestions(['Q'], ['A']), isFalse);
      expect(await VaultService.isSecuritySetup(), isFalse);
    });

    test('answers are matched case- and whitespace-insensitively', () async {
      await setUpWithQuestions();
      expect(
        await VaultService.verifySecurityAnswers(['  rex ', 'new   YORK']),
        isTrue,
      );
      expect(
        await VaultService.verifySecurityAnswers(['Rex', 'Boston']),
        isFalse,
      );
    });

    test('reset sets the chosen main password and keeps the decoy', () async {
      await setUpWithQuestions();
      expect(
        await VaultService.resetPasswordWithSecurity('brand-new', [
          'rex',
          'new york',
        ]),
        isTrue,
      );
      expect(await VaultService.authenticate('main-pass'), isFalse);
      expect(await VaultService.authenticate('brand-new'), isTrue);
      expect(VaultService.isInFakeMode, isFalse);
      await VaultService.logout();
      expect(await VaultService.authenticate('decoy-pass'), isTrue);
      expect(VaultService.isInFakeMode, isTrue);
    });

    test('reset refuses a password equal to the decoy', () async {
      await setUpWithQuestions();
      expect(
        await VaultService.resetPasswordWithSecurity('decoy-pass', [
          'rex',
          'new york',
        ]),
        isFalse,
      );
    });
  });

  group('changePassword', () {
    test('the decoy password cannot replace the main password', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await VaultService.authenticate('decoy-pass');
      expect(
        await VaultService.changePassword('decoy-pass', 'hijack', 'hijack2'),
        isFalse,
      );
      await VaultService.logout();
      expect(await VaultService.authenticate('main-pass'), isTrue);
    });

    test('main vault owner can rotate both passwords', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await VaultService.authenticate('main-pass');
      expect(
        await VaultService.changePassword('main-pass', 'main-2', 'decoy-2'),
        isTrue,
      );
      await VaultService.logout();
      expect(await VaultService.authenticate('main-2'), isTrue);
    });
  });

  group('file handling', () {
    test('availablePath never returns an existing file', () async {
      final target = p.join(tempRoot.path, 'movie.mp4');
      expect(await VaultService.availablePath(target), target);

      await File(target).writeAsString('x');
      expect(
        await VaultService.availablePath(target),
        p.join(tempRoot.path, 'movie (1).mp4'),
      );
    });

    test('hide then unhide restores the file without clobbering', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await unlockMain();

      final original = File(p.join(tempRoot.path, 'clip.mp4'));
      await original.writeAsString('video-bytes');

      expect(await VaultService.hideVideo(original.path), isTrue);
      expect(await original.exists(), isFalse);

      final videos = await VaultService.getVaultVideos();
      expect(videos, hasLength(1));
      expect(await File(videos.single.hiddenPath).exists(), isTrue);

      // Another file now occupies the original location.
      await original.writeAsString('newer');
      expect(await VaultService.unhideVideo(videos.single.id), isTrue);

      expect(await original.readAsString(), 'newer');
      final restored = File(p.join(tempRoot.path, 'clip (1).mp4'));
      expect(await restored.readAsString(), 'video-bytes');
      expect(await VaultService.getVaultVideos(), isEmpty);
    });

    test('vault contents are unavailable when locked', () async {
      expect(await VaultService.getVaultVideos(), isEmpty);
      expect(await VaultService.hideVideo('/does/not/matter'), isFalse);
    });
  });

  group('encryption', () {
    Future<File> makeVideo(String name, String content) async =>
        File(p.join(tempRoot.path, name))..writeAsStringSync(content);

    test('hidden files and metadata are encrypted at rest', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await unlockMain();
      final video = await makeVideo('holiday.mp4', 'secret-video-bytes' * 50);

      expect(await VaultService.hideVideo(video.path), isTrue);
      final stored = (await VaultService.getVaultVideos()).single;
      expect(stored.isEncrypted, isTrue);

      final hiddenBytes = await File(
        stored.hiddenPath,
      ).readAsString(encoding: const Latin1Codec());
      expect(hiddenBytes, isNot(contains('secret-video-bytes')));
      expect(
        await VaultCrypto.isEncryptedFile(File(stored.hiddenPath)),
        isTrue,
      );

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('main_vault_videos')!;
      expect(raw, startsWith('enc1:'));
      expect(raw, isNot(contains('holiday')));
      expect(raw, isNot(contains(tempRoot.path)));
    });

    test('decoy and main vaults are isolated', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await unlockMain();
      await VaultService.hideVideo((await makeVideo('a.mp4', 'main')).path);
      await VaultService.logout();

      await VaultService.authenticate('decoy-pass');
      expect(await VaultService.getVaultVideos(), isEmpty);
      await VaultService.hideVideo((await makeVideo('b.mp4', 'decoy')).path);
      expect(await VaultService.getVaultVideos(), hasLength(1));
      await VaultService.logout();

      await unlockMain();
      final main = await VaultService.getVaultVideos();
      expect(main.single.fileName, 'a.mp4');
    });

    test('password recovery keeps encrypted videos readable', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await unlockMain();
      await VaultService.setSecurityQuestions(['Pet?'], ['Rex']);
      final video = await makeVideo('keep.mp4', 'precious');
      await VaultService.hideVideo(video.path);
      await VaultService.logout();

      expect(
        await VaultService.resetPasswordWithSecurity('new-pass', [' REX ']),
        isTrue,
      );
      expect(await VaultService.authenticate('new-pass'), isTrue);
      final stored = (await VaultService.getVaultVideos()).single;
      expect(await VaultService.unhideVideo(stored.id), isTrue);
      expect(await video.readAsString(), 'precious');
    });

    test('changing passwords keeps both vaults readable', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await VaultService.authenticate('decoy-pass');
      await VaultService.hideVideo((await makeVideo('d.mp4', 'decoy')).path);
      await VaultService.logout();

      await unlockMain();
      expect(
        await VaultService.changePassword('main-pass', 'main-2', 'decoy-2'),
        isTrue,
      );
      await VaultService.logout();

      await VaultService.authenticate('decoy-2');
      expect(VaultService.isInFakeMode, isTrue);
      final decoyVideo = (await VaultService.getVaultVideos()).single;
      expect(await VaultService.verifyVaultIntegrity(), isTrue);
      expect(decoyVideo.fileName, 'd.mp4');
    });

    test('streams encrypted videos for playback', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await unlockMain();
      await VaultService.hideVideo(
        (await makeVideo('s.mp4', 'streamed-content')).path,
      );
      final playback = await VaultService.openForPlayback(
        (await VaultService.getVaultVideos()).single,
      );
      expect(playback.url, isNotNull);

      // The test binding stubs HttpClient; talk to the real loopback server.
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final client = HttpClient();
      final res = await (await client.getUrl(playback.url!)).close();
      expect(
        await res.transform(const Utf8Decoder()).join(),
        'streamed-content',
      );
      client.close(force: true);

      await playback.release();
      await VaultService.logout();
    });

    test('vaults from older versions are migrated', () async {
      // Pre-encryption state: legacy hash, plain JSON list, plain file.
      String legacy(String s) => sha256.convert(utf8.encode(s)).toString();
      final vaultDir = Directory(p.join(tempRoot.path, 'main_vault'))
        ..createSync(recursive: true);
      final plainFile = File(p.join(vaultDir.path, 'old.vault'))
        ..writeAsStringSync('legacy-video');
      SharedPreferences.setMockInitialValues({
        'vault_is_setup': true,
        'main_vault_password': legacy('old-main'),
        'fake_vault_password': legacy('old-fake'),
        'security_setup_done': true,
      });
      await VaultService.writeLegacyVideoList([
        VaultVideo(
          id: 'old',
          originalPath: p.join(tempRoot.path, 'old.mp4'),
          hiddenPath: plainFile.path,
          fileName: 'old.mp4',
          originalExtension: 'mp4',
          fileSize: 12,
          hiddenDate: DateTime(2024),
          format: VaultFileFormat.plain,
        ),
      ]);

      expect(await VaultService.authenticate('old-main'), isTrue);
      // No recovery key yet: the owner is asked to re-save their questions.
      expect(await VaultService.needsRecoverySetup(), isTrue);

      final before = await VaultService.getVaultVideos();
      expect(before.single.isEncrypted, isFalse);
      expect(await VaultService.countUnencryptedVideos(), 1);

      // Nothing is encrypted until the vault can be recovered.
      expect(await VaultService.encryptPendingVideos(), 0);
      expect(await plainFile.exists(), isTrue);

      expect(await VaultService.setSecurityQuestions(['Q?'], ['A']), isTrue);
      expect(await VaultService.encryptPendingVideos(), 1);
      final after = (await VaultService.getVaultVideos()).single;
      expect(after.isEncrypted, isTrue);
      expect(await plainFile.exists(), isFalse);

      expect(await VaultService.unhideVideo(after.id), isTrue);
      expect(
        await File(p.join(tempRoot.path, 'old.mp4')).readAsString(),
        'legacy-video',
      );
    });
  });
  group('data safety', () {
    Future<File> video(String name, [String content = 'bytes']) async =>
        File(p.join(tempRoot.path, name))..writeAsStringSync(content);

    test('refuses to encrypt before recovery is configured', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await VaultService.authenticate('main-pass');
      expect(await VaultService.needsRecoverySetup(), isTrue);

      final v = await video('early.mp4');
      expect(await VaultService.hideVideo(v.path), isFalse);
      expect(await v.exists(), isTrue, reason: 'original must be untouched');
      expect(await VaultService.getVaultVideos(), isEmpty);
    });

    test('the decoy vault may encrypt without recovery', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await VaultService.authenticate('decoy-pass');
      expect(await VaultService.hideVideo((await video('d.mp4')).path), isTrue);
    });

    test('concurrent hides all land in the index', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await unlockMain();
      final files = [for (var i = 0; i < 6; i++) await video('c$i.mp4', '$i')];
      final results = await Future.wait(
        files.map((f) => VaultService.hideVideo(f.path)),
      );
      expect(results, everyElement(isTrue));
      expect(await VaultService.getVaultVideos(), hasLength(6));
    });

    test('concurrent hide and delete do not lose updates', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await unlockMain();
      await VaultService.hideVideo((await video('keep.mp4')).path);
      await VaultService.hideVideo((await video('drop.mp4')).path);
      final drop = (await VaultService.getVaultVideos()).firstWhere(
        (v) => v.fileName == 'drop.mp4',
      );
      final added = await video('new.mp4');
      await Future.wait([
        VaultService.deleteFromVault(drop.id),
        VaultService.hideVideo(added.path),
      ]);
      final names = (await VaultService.getVaultVideos())
          .map((v) => v.fileName)
          .toSet();
      expect(names, {'keep.mp4', 'new.mp4'});
    });

    test(
      'a reset cannot orphan encrypted videos from a legacy vault',
      () async {
        await VaultService.setupVault('main-pass', 'decoy-pass');
        await unlockMain();
        // Emulate a vault upgraded from an old version: answers exist but the
        // recovery wrap was never created.
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('vault_main_dek_recovery');
        await VaultService.logout();

        final dir = Directory(p.join(tempRoot.path, 'main_vault'))
          ..createSync(recursive: true);
        File(p.join(dir.path, 'x.pvault')).writeAsStringSync('encrypted');

        expect(
          await VaultService.resetPasswordWithSecurity('new-pass', ['A']),
          isFalse,
        );
        expect(await VaultService.authenticate('main-pass'), isTrue);
      },
    );

    test('a legacy vault with no encrypted files can still reset', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await unlockMain();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('vault_main_dek_recovery');
      await VaultService.logout();
      expect(
        await VaultService.resetPasswordWithSecurity('new-pass', ['A']),
        isTrue,
      );
    });
  });

  group('lockout clock', () {
    test('changing the wall clock does not end a lockout', () async {
      var elapsed = 1000000;
      VaultService.elapsedRealtimeMs = () async => elapsed;
      await VaultService.setupVault('main-pass', 'decoy-pass');
      for (var i = 0; i < 5; i++) {
        await VaultService.unlock('wrong-$i');
      }
      expect(
        await VaultService.getLockoutRemaining(),
        greaterThan(Duration.zero),
      );

      // User sets the clock forward: the stored wall-clock deadline is past.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('vault_locked_until_ms', 1);
      elapsed += 5000;
      final remaining = await VaultService.getLockoutRemaining();
      expect(remaining, greaterThan(const Duration(seconds: 20)));
      expect(
        (await VaultService.unlock('main-pass')).status,
        VaultAuthStatus.lockedOut,
      );

      elapsed += 26000;
      expect(await VaultService.getLockoutRemaining(), Duration.zero);
      expect((await VaultService.unlock('main-pass')).isSuccess, isTrue);
    });

    test('falls back to the wall clock without a monotonic source', () async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      for (var i = 0; i < 5; i++) {
        await VaultService.unlock('wrong-$i');
      }
      expect(
        await VaultService.getLockoutRemaining(),
        greaterThan(Duration.zero),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('vault_locked_until_ms', 1);
      expect(await VaultService.getLockoutRemaining(), Duration.zero);
    });
  });

  group('key derivation upgrade', () {
    test('unlock re-wraps keys made with fewer iterations', () async {
      PasswordHasher.defaultIterations = 10;
      await VaultService.setupVault('main-pass', 'decoy-pass');
      PasswordHasher.defaultIterations = 1000;
      addTearDown(() => PasswordHasher.defaultIterations = 1000);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('vault_main_dek'), contains(r'$10$'));

      expect((await VaultService.unlock('main-pass')).isSuccess, isTrue);
      expect(
        VaultCrypto.wrapNeedsUpgrade(prefs.getString('vault_main_dek')!),
        isFalse,
      );
      await VaultService.logout();
      expect((await VaultService.unlock('main-pass')).isSuccess, isTrue);
    });

    test('rejects passwords shorter than the minimum', () async {
      expect(VaultService.minPasswordLength, greaterThanOrEqualTo(6));
      expect(await VaultService.setupVault('12345', 'abcdef'), isFalse);
    });
  });
}
