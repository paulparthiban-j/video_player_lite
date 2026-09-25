import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/core/security/vault_crypto.dart';
import 'package:next_gen_video_player/services/vault_auto_lock.dart';
import 'package:next_gen_video_player/services/vault_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stand-in for the vault screen: registers itself like the real one.
class _FakeVaultScreen extends StatefulWidget {
  const _FakeVaultScreen();

  @override
  State<_FakeVaultScreen> createState() => _FakeVaultScreenState();
}

class _FakeVaultScreenState extends State<_FakeVaultScreen> {
  @override
  void initState() {
    super.initState();
    VaultAutoLock.vaultScreenOpened();
  }

  @override
  void dispose() {
    VaultAutoLock.vaultScreenClosed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('vault');
}

void main() {
  late Directory tempRoot;
  final secureCalls = <bool>[];

  setUpAll(() => VaultCrypto.algorithm = DartAesGcm.with256bits());

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('autolock_');
    secureCalls.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempRoot.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('next_player/system_controls'),
      (call) async {
        if (call.method == 'setSecure') {
          secureCalls.add((call.arguments as Map)['secure'] as bool);
        }
        return true;
      },
    );
    SharedPreferences.setMockInitialValues({});
    VaultAutoLock.resetForTest();
  });

  tearDown(() async {
    await VaultService.logout();
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  /// Main screen with the vault opened on top, vault unlocked.
  Future<GlobalKey<NavigatorState>> openVault(
    WidgetTester tester, {
    Duration timeout = VaultAutoLock.defaultTimeout,
  }) async {
    await tester.runAsync(() async {
      await VaultService.setupVault('main-pass', 'decoy-pass');
      await VaultService.authenticate('main-pass');
      await VaultAutoLock.setTimeout(timeout);
    });
    final key = GlobalKey<NavigatorState>();
    VaultAutoLock.navigatorKey = key;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        initialRoute: '/main',
        routes: {
          '/main': (_) => const Text('library'),
          '/vault': (_) => const _FakeVaultScreen(),
          '/vault-auth': (_) => const Text('login'),
        },
      ),
    );
    key.currentState!.pushNamed('/vault');
    await tester.pumpAndSettle();
    expect(find.text('vault'), findsOneWidget);
    return key;
  }

  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) =>
      tester.runAsync(() => VaultAutoLock.handleLifecycle(state));

  testWidgets('"Immediately" locks as soon as the app is backgrounded', (
    tester,
  ) async {
    await openVault(tester, timeout: Duration.zero);
    await lifecycle(tester, AppLifecycleState.hidden);
    await tester.pumpAndSettle();

    expect(VaultService.isAuthenticated, isFalse);
    expect(find.text('login'), findsOneWidget);
    expect(find.text('vault'), findsNothing);
  });

  testWidgets('a short trip away does not lock', (tester) async {
    await openVault(tester);
    await lifecycle(tester, AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(const Duration(minutes: 2));

    expect(VaultService.isAuthenticated, isTrue);
    expect(find.text('vault'), findsOneWidget);
  });

  testWidgets('locks once the timeout elapses in the background', (
    tester,
  ) async {
    // Short real-time timeout: the lock timer runs on the real clock.
    await openVault(tester, timeout: const Duration(milliseconds: 300));
    await lifecycle(tester, AppLifecycleState.paused);
    expect(VaultService.isAuthenticated, isTrue);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 900)),
    );
    await tester.pumpAndSettle();

    expect(VaultService.isAuthenticated, isFalse);
    expect(find.text('login'), findsOneWidget);
  });

  testWidgets('picture-in-picture (inactive) keeps the vault open', (
    tester,
  ) async {
    await openVault(tester, timeout: Duration.zero);
    await lifecycle(tester, AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(VaultService.isAuthenticated, isTrue);
  });

  testWidgets('system pickers do not trigger "Immediately"', (tester) async {
    await openVault(tester, timeout: Duration.zero);
    await tester.runAsync(
      () => VaultAutoLock.runWhileSuspended(() async {
        await VaultAutoLock.handleLifecycle(AppLifecycleState.paused);
        await VaultAutoLock.handleLifecycle(AppLifecycleState.resumed);
      }),
    );
    await tester.pumpAndSettle();
    expect(VaultService.isAuthenticated, isTrue);
  });

  testWidgets('leaving the vault screen locks it and lifts FLAG_SECURE', (
    tester,
  ) async {
    final nav = await openVault(tester);
    expect(secureCalls, [true]);

    nav.currentState!.pop();
    await tester.runAsync(() async {
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    expect(VaultService.isAuthenticated, isFalse);
    expect(secureCalls, [true, false]);
    expect(find.text('library'), findsOneWidget);
  });

  test('describes timeouts', () {
    expect(VaultAutoLock.describe(Duration.zero), 'Immediately');
    expect(
      VaultAutoLock.describe(const Duration(seconds: 30)),
      'After 30 seconds',
    );
    expect(
      VaultAutoLock.describe(const Duration(minutes: 1)),
      'After 1 minute',
    );
    expect(
      VaultAutoLock.describe(const Duration(minutes: 5)),
      'After 5 minutes',
    );
  });
}
