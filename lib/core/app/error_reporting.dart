import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Central hooks for uncaught errors.
///
/// Framework errors, errors escaping the platform dispatcher and errors
/// thrown in the root zone all end up in [report], which is the single place
/// to forward them to a crash-reporting backend.
abstract final class ErrorReporting {
  static void install() {
    // debugPrint is not stripped from release builds. Silence it there so
    // file names, stream URLs and other user data never reach device logs.
    if (kReleaseMode) {
      debugPrint = (String? message, {int? wrapWidth}) {};
    }

    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (kDebugMode) {
        (previousFlutterHandler ?? FlutterError.presentError)(details);
      }
      report(details.exception, details.stack, context: 'flutter');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, context: 'platform');
      return true;
    };

    // Replace the red error screen with a neutral message in release builds.
    if (kReleaseMode) {
      ErrorWidget.builder = (details) => const _ReleaseErrorWidget();
    }
  }

  /// Records an error that was caught but not otherwise handled.
  static void report(Object error, StackTrace? stack, {String? context}) {
    if (kDebugMode) {
      debugPrint('Uncaught ${context ?? ''} error: $error');
      if (stack != null) debugPrintStack(stackTrace: stack);
    }
    // Hook point for a crash reporter (e.g. Crashlytics / Sentry).
  }

  /// Runs [body] in a guarded zone that forwards async errors to [report].
  static void runGuarded(FutureOr<void> Function() body) {
    runZonedGuarded<void>(
      () => body(),
      (error, stack) => report(error, stack, context: 'zone'),
    );
  }
}

class _ReleaseErrorWidget extends StatelessWidget {
  const _ReleaseErrorWidget();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF0A0A0A),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Something went wrong displaying this content.',
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 14),
          ),
        ),
      ),
    );
  }
}
