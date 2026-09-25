import 'package:shared_preferences/shared_preferences.dart';

class PlaybackHistoryService {
  static const String _prefix = 'video_pos_';
  static const String _lastPlayedKey = 'last_played_video';

  /// Vault files must never appear in history: recording them would reveal
  /// the vault's contents and file names outside the encrypted store.
  static bool isPrivatePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.contains('/main_vault/') ||
        normalized.contains('/fake_vault/');
  }

  /// Save the playback position for a specific video
  static Future<void> savePosition(String videoPath, Duration position) async {
    if (position.inSeconds < 5) return; // Don't save if just started
    if (isPrivatePath(videoPath)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefix$videoPath', position.inMilliseconds);
  }

  /// Get the saved position for a video
  static Future<Duration> getPosition(String videoPath) async {
    if (isPrivatePath(videoPath)) return Duration.zero;
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('$_prefix$videoPath');
    return ms != null ? Duration(milliseconds: ms) : Duration.zero;
  }

  /// Save the video path as the last played video
  static Future<void> saveLastPlayedVideo(String videoPath) async {
    if (isPrivatePath(videoPath)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastPlayedKey, videoPath);
  }

  /// Get the path of the last played video
  static Future<String?> getLastPlayedVideo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastPlayedKey);
  }

  /// Clear position (e.g. when video changes or finishes)
  static Future<void> clearPosition(String videoPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$videoPath');
  }
}
