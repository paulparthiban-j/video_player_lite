import 'package:flutter_test/flutter_test.dart';
import 'package:next_gen_video_player/screens/about_screen.dart';
import 'package:next_gen_video_player/screens/parthi_play_main_screen.dart';
import 'package:next_gen_video_player/screens/scan_directories_settings_screen.dart';
import 'package:next_gen_video_player/screens/settings_screen.dart';
import 'package:next_gen_video_player/screens/vault_auth_screen.dart';
import 'package:next_gen_video_player/screens/vault_forgot_screen.dart';
import 'package:next_gen_video_player/screens/vault_screen.dart';
import 'package:next_gen_video_player/screens/vault_security_setup_screen.dart';
import 'package:next_gen_video_player/screens/vault_setup_screen.dart';

import 'layout_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installLayoutMocks();

  layoutMatrix('Library', () => const ParthiPlayMainScreen());
  layoutMatrix('Vault (empty)', () => const VaultScreen());
  layoutMatrix('Settings', () => const SettingsScreen());
  layoutMatrix('About', () => const AboutScreen());
  layoutMatrix('Scan directories', () => const ScanDirectoriesSettingsScreen());
  layoutMatrix('Vault login', () => const VaultAuthScreen());
  layoutMatrix('Vault setup', () => const VaultSetupScreen());
  layoutMatrix('Vault recovery', () => const VaultForgotScreen());
  layoutMatrix('Vault security setup', () => const VaultSecuritySetupScreen());
}
