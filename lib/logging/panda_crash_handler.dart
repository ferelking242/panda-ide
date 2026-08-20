import 'dart:async';

import 'package:flutter/foundation.dart';

import 'panda_logger.dart';
import 'panda_log_level.dart';

/// Global crash handler that captures uncaught Flutter/Dart errors.
/// Chains with existing handlers instead of replacing them.
class PandaCrashHandler {
  static bool _installed = false;

  /// Install the global error handlers. Call once after runApp().
  static void install() {
    if (_installed) return;
    _installed = true;

    // Chain with existing FlutterError.onError handler
    final previousHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      // Call original handler first if it exists
      previousHandler?.call(details);
      PandaLogger.crash(
        details.exception,
        details.stack ?? StackTrace.empty,
        context: 'FlutterError: ${details.context}',
      );
    };

    // Async errors not caught by zone
    final previousDispatcher = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      PandaLogger.crash(error, stackTrace, context: 'PlatformDispatcher');
      // Let previous handler decide if it was handled
      return previousDispatcher?.call(error, stackTrace) ?? false;
    };
  }
}
