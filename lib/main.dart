import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'core/app/error_reporting.dart';
import 'core/theme/app_theme.dart';
import 'core/ui/responsive.dart';
import 'services/theme_service.dart';
import 'services/vault_service.dart';
import 'screens/parthi_play_main_screen.dart';
import 'screens/launch_screen.dart';
import 'screens/vault_auth_screen.dart';
import 'screens/vault_setup_screen.dart';
import 'screens/vault_screen.dart';
import 'screens/vault_forgot_screen.dart';
import 'screens/vault_security_setup_screen.dart';
import 'screens/file_browser_screen.dart';
import 'screens/next_file_browser_screen.dart';

void main() {
  ErrorReporting.runGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    ErrorReporting.install();

    await AppOrientation.applyBrowsing();

    try {
      MediaKit.ensureInitialized();
    } catch (e, stack) {
      ErrorReporting.report(e, stack, context: 'media_kit init');
    }

    // Remove any vault playback copies left behind by a previous session.
    unawaited(VaultService.cleanupPlaybackTempFiles());

    runApp(const ProviderScope(child: ParthiPlayApp()));
  });
}

class ParthiPlayApp extends ConsumerStatefulWidget {
  const ParthiPlayApp({super.key});

  @override
  ConsumerState<ParthiPlayApp> createState() => _ParthiPlayAppState();
}

class _ParthiPlayAppState extends ConsumerState<ParthiPlayApp>
    with WidgetsBindingObserver {
  DateTime? _lastVaultCleanupAt;
  static const Duration _vaultCleanupCooldown = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_lastVaultCleanupAt == null ||
          now.difference(_lastVaultCleanupAt!) > _vaultCleanupCooldown) {
        unawaited(VaultService.cleanupPlaybackTempFiles());
        _lastVaultCleanupAt = now;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Parthi Play',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      initialRoute: '/',
      routes: {
        '/': (context) => const LaunchScreen(),
        '/main': (context) => const ParthiPlayMainScreen(),
        '/vault-auth': (context) => const VaultAuthScreen(),
        '/vault-setup': (context) => const VaultSetupScreen(),
        '/vault': (context) => const VaultScreen(),
        '/vault-forgot': (context) => const VaultForgotScreen(),
        '/vault-security-setup': (context) => const VaultSecuritySetupScreen(),
        '/file-browser': (context) => const FileBrowserScreen(),
        '/next-browser': (context) => const NextFileBrowserScreen(),
      },
    );
  }
}
