import 'dart:async';

import 'package:flutter/foundation.dart';

import 'panda_logger.dart';
import 'panda_log_level.dart';

/// Global crash handler that captures uncaught Flutter/Dart errors.
class PandaCrashHandler {
  static bool _installed = false;

  /// Install the global error handlers. Call once at app startup.
  static void install() {
    if (_installed) return;
    _installed = true;

    // Flutter framework errors
    FlutterError.onError = (details) {
      PandaLogger.crash(
        details.exception,
        details.stack ?? StackTrace.empty,
        context: 'FlutterError: ${details.context}',
      );
    };

    // Async errors not caught by zone
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      PandaLogger.crash(error, stackTrace, context: 'PlatformDispatcher');
      return true;
    };

    // Zone errors (catch-all)
    runZonedGuarded(() {}, (error, stackTrace) {
      PandaLogger.crash(error, stackTrace, context: 'ZoneGuarded');
    });
  }
}
