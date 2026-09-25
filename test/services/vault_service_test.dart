import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/services/vault_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('vault_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempRoot.path,
        );
    SharedPreferences.setMockInitialValues({});
    await VaultService.logout();
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

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
      await VaultService.authenticate('main-pass');

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
}
