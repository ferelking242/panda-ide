/// PandaLog — backward-compatible logging API.
///
/// Delegates to the new PandaLogger system. Existing code continues to work.
import 'panda_log_bridge.dart';

library;


/// Niveaux de log (kept for backward compatibility).
enum PandaLevel { verbose, debug, info, warning, error }

/// Legacy logging API. Routes to PandaLogger.
abstract final class PandaLog {
  static bool enabled = true;
  static PandaLevel minLevel = PandaLevel.verbose;
  static PandaLevel fileMinLevel = PandaLevel.verbose;

  static Future<void> initFileLogging() async {
    // No-op: PandaLogger handles file logging
  }

  static void v(String tag, String msg, {String? body}) =>
      PandaLogBridge.i(tag, msg, body: body);

  static void d(String tag, String msg, {String? body}) =>
      PandaLogBridge.d(tag, msg, body: body);

  static void i(String tag, String msg, {String? body}) =>
      PandaLogBridge.i(tag, msg, body: body);

  static void w(String tag, String msg, {String? body}) =>
      PandaLogBridge.w(tag, msg, body: body);

  static void e(String tag, String msg, {String? body, Object? error}) =>
      PandaLogBridge.e(tag, msg, body: body, error: error);

  static void httpRequest(String tag, String method, String url, {String? body}) =>
      PandaLogBridge.i(tag, '→ $method $url', body: body);

  static void httpResponse(String tag, int status, String url, {String? body}) =>
      PandaLogBridge.i(tag, '← $status $url', body: body);

  static void toolCall(String tag, String name, dynamic args) =>
      PandaLogBridge.i(tag, '🔧 tool=$name args=$args');

  static void toolResult(String tag, String name, String result) =>
      PandaLogBridge.d(tag, '✅ tool=$name result=$result');

  static Future<void> flush() async {}
}
