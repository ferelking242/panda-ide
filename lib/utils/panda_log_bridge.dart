/// Bridge from the legacy PandaLog API to the new PandaLogger system.
///
/// This allows existing code that uses PandaLog to work seamlessly
/// while the new logging system is active.
library;
import '../logging/panda_logger.dart';
import '../logging/panda_log_level.dart';



/// Legacy-compatible static methods that delegate to PandaLogger.
/// Existing code calling PandaLog.i() / PandaLog.e() etc. will
/// continue to work and now also write structured events.
class PandaLogBridge {
  static void i(String tag, String message, {String? body}) {
    PandaLogger.i(_categoryFromTag(tag), '[$tag] $message',
        metadata: body != null ? {'body': body} : null);
  }

  static void d(String tag, String message, {String? body}) {
    PandaLogger.d(_categoryFromTag(tag), '[$tag] $message',
        metadata: body != null ? {'body': body} : null);
  }

  static void w(String tag, String message, {String? body}) {
    PandaLogger.w(_categoryFromTag(tag), '[$tag] $message',
        metadata: body != null ? {'body': body} : null);
  }

  static void e(String tag, String message, {String? body, Object? error}) {
    PandaLogger.e(_categoryFromTag(tag), '[$tag] $message',
        error: error?.toString());
  }

  static PandaLogCategory _categoryFromTag(String tag) {
    final lower = tag.toLowerCase();
    if (lower.contains('terminal')) return PandaLogCategory.terminal;
    if (lower.contains('agent') || lower.contains('copilot')) return PandaLogCategory.agent;
    if (lower.contains('tool')) return PandaLogCategory.tool;
    if (lower.contains('git')) return PandaLogCategory.git;
    if (lower.contains('build')) return PandaLogCategory.build;
    if (lower.contains('network') || lower.contains('http')) return PandaLogCategory.network;
    if (lower.contains('extension')) return PandaLogCategory.extension;
    if (lower.contains('file') || lower.contains('editor')) return PandaLogCategory.file;
    if (lower.contains('ui')) return PandaLogCategory.ui;
    if (lower.contains('performance') || lower.contains('perf')) return PandaLogCategory.performance;
    if (lower.contains('alpine')) return PandaLogCategory.system;
    return PandaLogCategory.app;
  }
}
