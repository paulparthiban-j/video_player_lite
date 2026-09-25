import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'system_controls_service.dart';
import 'vault_service.dart';

/// Locks the vault when the app leaves the foreground for too long, and when
/// the vault screen is closed.
///
/// Locking wipes the data key from memory, stops the loopback stream server
/// and, if vault screens are open, returns the user to the vault login.
///
/// Only `hidden`/`paused` count as leaving: Android reports picture-in-
/// picture as `inactive`, so a vault video in PiP keeps playing.
class VaultAutoLock {
  VaultAutoLock._();

  static const String _timeoutKey = 'vault_auto_lock_seconds';

  /// Choices offered in the UI. [Duration.zero] locks as soon as the app is
  /// backgrounded.
  static const List<Duration> options = [
    Duration.zero,
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  static const Duration defaultTimeout = Duration(minutes: 1);

  /// Navigator used to return to the login screen; set by the app root.
  static GlobalKey<NavigatorState>? navigatorKey;

  /// While a system picker or share sheet opened from the vault is showing,
  /// the vault stays unlocked for at least this long.
  static const Duration suspendedFloor = Duration(minutes: 5);

  static int _suspendDepth = 0;
  static DateTime? _backgroundedAt;
  static Timer? _timer;
  static int _openVaultScreens = 0;
  static Duration? _cachedTimeout;

  static Future<Duration> getTimeout() async {
    final cached = _cachedTimeout;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final seconds = prefs.getInt(_timeoutKey);
    return _cachedTimeout = seconds == null
        ? defaultTimeout
        : Duration(seconds: seconds);
  }

  static Future<void> setTimeout(Duration timeout) async {
    _cachedTimeout = timeout;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timeoutKey, timeout.inSeconds);
  }

  static String describe(Duration timeout) {
    if (timeout == Duration.zero) return 'Immediately';
    if (timeout.inMinutes >= 1) {
      final m = timeout.inMinutes;
      return 'After $m minute${m == 1 ? '' : 's'}';
    }
    return 'After ${timeout.inSeconds} seconds';
  }

  /// Called by the vault screen while it is mounted.
  static void vaultScreenOpened() {
    _openVaultScreens++;
    unawaited(SystemControlsService.setSecure(true));
  }

  /// Called when the vault screen is disposed; leaving the vault locks it.
  static void vaultScreenClosed() {
    _openVaultScreens = _openVaultScreens > 0 ? _openVaultScreens - 1 : 0;
    if (_openVaultScreens == 0) {
      unawaited(SystemControlsService.setSecure(false));
      if (VaultService.isAuthenticated) unawaited(VaultService.logout());
    }
  }

  static bool get isVaultOnScreen => _openVaultScreens > 0;

  /// Runs [action] (a file picker, share sheet, ...) that briefly sends the
  /// app to the background, without an "Immediately" setting locking the
  /// vault underneath it. A longer absence still locks.
  static Future<T> runWhileSuspended<T>(Future<T> Function() action) async {
    _suspendDepth++;
    try {
      return await action();
    } finally {
      _suspendDepth--;
    }
  }

  static Future<Duration> _effectiveTimeout() async {
    final timeout = await getTimeout();
    if (_suspendDepth > 0 && timeout < suspendedFloor) return suspendedFloor;
    return timeout;
  }

  /// Feed every app lifecycle change here.
  static Future<void> handleLifecycle(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (!VaultService.isAuthenticated || _backgroundedAt != null) return;
        _backgroundedAt = DateTime.now();
        final timeout = await _effectiveTimeout();
        if (timeout == Duration.zero) {
          await lockNow();
        } else {
          // May not fire if the OS freezes the process; resume re-checks.
          _timer?.cancel();
          _timer = Timer(timeout, () => unawaited(lockNow()));
        }
      case AppLifecycleState.resumed:
        _timer?.cancel();
        _timer = null;
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since == null || !VaultService.isAuthenticated) return;
        if (DateTime.now().difference(since) >= await _effectiveTimeout()) {
          await lockNow();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Locks immediately and, if vault screens are open, shows the login.
  static Future<void> lockNow() async {
    _timer?.cancel();
    _timer = null;
    if (!VaultService.isAuthenticated) return;
    await VaultService.logout();

    final navigator = navigatorKey?.currentState;
    if (navigator == null || !isVaultOnScreen) return;
    // Drop the vault screen and anything opened from it (e.g. the player).
    navigator.popUntil(
      (route) => route.settings.name == '/main' || route.isFirst,
    );
    unawaited(navigator.pushNamed('/vault-auth'));
  }

  @visibleForTesting
  static void resetForTest() {
    _timer?.cancel();
    _timer = null;
    _backgroundedAt = null;
    _openVaultScreens = 0;
    _suspendDepth = 0;
    _cachedTimeout = null;
    navigatorKey = null;
  }
}
