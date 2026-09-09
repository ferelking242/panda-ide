import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/constants.dart';
import 'panda_log_event.dart';
import 'panda_log_level.dart';
import 'panda_log_store.dart';
import 'secret_redactor.dart';

/// Central logging API for Panda IDE.
///
/// All subsystems (Agent, Terminal, File, Git, Build, Network, etc.)
/// should use this class instead of raw print() or debugPrint().
///
/// ```dart
/// PandaLogger.i(PandaLogCategory.agent, 'Agent started', agentRunId: 'abc');
/// PandaLogger.e(PandaLogCategory.terminal, 'Command failed', error: 'exit 1');
/// ```
abstract final class PandaLogger {
  // ── Configuration ────────────────────────────────────────────────────────

  static bool _initialized = false;
  static bool _diagnosticMode = false;
  static String? _sessionId;
  static String? _currentProjectPath;

  /// Current session ID (generated on app start).
  static String get sessionId => _sessionId ??= _generateId();

  /// Enable/disable diagnostic mode (more verbose logging).
  static bool get diagnosticMode => _diagnosticMode;
  static set diagnosticMode(bool value) {
    _diagnosticMode = value;
    PandaLogStore.instance.updateConfig(
      value ? PandaLogConfig.diagnosticConfig : PandaLogConfig.defaultConfig,
    );
  }

  /// Initialize the logger. Call once at app startup.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      await PandaLogStore.instance.init();
      _initialized = true;
      i(PandaLogCategory.app, 'PandaLogger initialized');
    } catch (e) {
      debugPrint('[PandaLogger] init failed: $e');
    }
  }

  /// Set the current project path for log context.
  static void setProject(String? path) => _currentProjectPath = path;

  // ── Core logging methods ────────────────────────────────────────────────

  static void _log(
    PandaLogLevel level,
    PandaLogCategory category,
    String message, {
    String? sessionId,
    String? agentRunId,
    String? toolCallId,
    String? source,
    int? durationMs,
    String? projectPath,
    String? filePath,
    int? line,
    int? column,
    String? command,
    String? cwd,
    int? exitCode,
    Map<String, dynamic>? metadata,
    String? error,
    StackTrace? stackTrace,
  }) {
    if (!_initialized) {
      // Queue will be empty; just print in debug
      if (kDebugMode) {
        debugPrint('[${level.prefix}][${category.label}] $message');
      }
      return;
    }

    final event = PandaLogEvent(
      id: _generateId(),
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: SecretRedactor.redact(message),
      sessionId: sessionId ?? _sessionId,
      agentRunId: agentRunId,
      toolCallId: toolCallId,
      source: source,
      durationMs: durationMs,
      projectPath: projectPath ?? _currentProjectPath,
      filePath: filePath,
      line: line,
      column: column,
      command: command != null ? SecretRedactor.redact(command) : null,
      cwd: cwd,
      exitCode: exitCode,
      metadata: metadata,
      error: error != null ? SecretRedactor.redact(error) : null,
      stackTrace: stackTrace?.toString(),
    );

    PandaLogStore.instance.write(event);

    // Debug console output
    if (kDebugMode) {
      final prefix = '[${level.prefix}][${category.label}]';
      debugPrint('$prefix $message');
      if (error != null) debugPrint('  err: ${SecretRedactor.redact(error)}');
    }
  }

  // ── Convenience methods ─────────────────────────────────────────────────

  static void v(PandaLogCategory cat, String msg, {String? source, String? agentRunId, Map<String, dynamic>? metadata}) =>
      _log(PandaLogLevel.debug, cat, msg, source: source, agentRunId: agentRunId, metadata: metadata);

  static void d(PandaLogCategory cat, String msg, {String? source, String? agentRunId, Map<String, dynamic>? metadata}) =>
      _log(PandaLogLevel.debug, cat, msg, source: source, agentRunId: agentRunId, metadata: metadata);

  static void i(PandaLogCategory cat, String msg, {String? source, String? agentRunId, Map<String, dynamic>? metadata, int? durationMs, String? filePath, String? command, int? exitCode}) =>
      _log(PandaLogLevel.info, cat, msg, source: source, agentRunId: agentRunId, metadata: metadata, durationMs: durationMs, filePath: filePath, command: command, exitCode: exitCode);

  static void s(PandaLogCategory cat, String msg, {String? source, String? agentRunId, Map<String, dynamic>? metadata, int? durationMs}) =>
      _log(PandaLogLevel.success, cat, msg, source: source, agentRunId: agentRunId, metadata: metadata, durationMs: durationMs);

  static void w(PandaLogCategory cat, String msg, {String? source, String? agentRunId, Map<String, dynamic>? metadata}) =>
      _log(PandaLogLevel.warning, cat, msg, source: source, agentRunId: agentRunId, metadata: metadata);

  static void e(
    PandaLogCategory cat,
    String msg, {
    String? error,
    StackTrace? stackTrace,
    String? agentRunId,
    int? durationMs,
  }) =>
      _log(PandaLogLevel.error, cat, msg, error: error, stackTrace: stackTrace, agentRunId: agentRunId, durationMs: durationMs);

  static void f(
    PandaLogCategory cat,
    String msg, {
    String? error,
    StackTrace? stackTrace,
  }) =>
      _log(PandaLogLevel.fatal, cat, msg, error: error, stackTrace: stackTrace);

  // ── Agent-specific logging ──────────────────────────────────────────────

  static void agentStarted(String runId, {String? model}) {
    i(PandaLogCategory.agent, 'Agent run started',
        agentRunId: runId, metadata: {'model': model});
  }

  static void agentThinking(String runId) {
    d(PandaLogCategory.agent, 'Agent thinking', agentRunId: runId);
  }

  static void agentCompleted(String runId, {int? durationMs}) {
    s(PandaLogCategory.agent, 'Agent run completed',
        agentRunId: runId, durationMs: durationMs);
  }

  static void agentCancelled(String runId) {
    w(PandaLogCategory.agent, 'Agent run cancelled', agentRunId: runId);
  }

  static void agentError(String runId, String error) {
    e(PandaLogCategory.agent, 'Agent error: $error', agentRunId: runId);
  }

  static void toolStarted(
    String runId,
    String toolName,
    Map<String, dynamic> args,
  ) {
    i(PandaLogCategory.tool, 'Tool call: $toolName',
        agentRunId: runId, metadata: {'args': args});
  }

  static void toolCompleted(
    String runId,
    String toolName, {
    int? durationMs,
    String? error,
  }) {
    if (error != null) {
      e(PandaLogCategory.tool, 'Tool failed: $toolName: $error',
          agentRunId: runId, durationMs: durationMs);
    } else {
      s(PandaLogCategory.tool, 'Tool completed: $toolName',
          agentRunId: runId, durationMs: durationMs);
    }
  }

  // ── Terminal-specific logging ───────────────────────────────────────────

  static void terminalCommand({
    required String command,
    required String cwd,
    int? exitCode,
    int? durationMs,
    String? error,
  }) {
    final level = (exitCode != null && exitCode != 0) || error != null
        ? PandaLogLevel.error
        : PandaLogLevel.info;
    _log(level, PandaLogCategory.terminal, 'Command: $command',
        command: command, cwd: cwd, exitCode: exitCode,
        durationMs: durationMs, error: error,
        metadata: exitCode != null ? {'exitCode': exitCode} : null);
  }

  // ── File-specific logging ──────────────────────────────────────────────

  static void fileOperation(
    String operation,
    String filePath, {
    int? line,
    int? column,
  }) {
    _log(PandaLogLevel.info, PandaLogCategory.file, '$operation: $filePath',
        filePath: filePath, line: line, column: column);
  }

  // ── Git-specific logging ───────────────────────────────────────────────

  static void gitOperation({
    required String command,
    int? exitCode,
    int? durationMs,
    String? error,
  }) {
    final level = (exitCode != null && exitCode != 0) || error != null
        ? PandaLogLevel.error
        : PandaLogLevel.info;
    _log(level, PandaLogCategory.git, 'Git: $command',
        command: 'git $command', exitCode: exitCode,
        durationMs: durationMs, error: error);
  }

  // ── Build-specific logging ─────────────────────────────────────────────

  static void buildOperation({
    required String command,
    int? exitCode,
    int? durationMs,
    String? error,
  }) {
    final level = (exitCode != null && exitCode != 0) || error != null
        ? PandaLogLevel.error
        : PandaLogLevel.info;
    _log(level, PandaLogCategory.build, 'Build: $command',
        command: command, exitCode: exitCode,
        durationMs: durationMs, error: error);
  }

  // ── Performance logging ────────────────────────────────────────────────

  static void perf(String operation, int durationMs, {String? details}) {
    final level = durationMs > 5000
        ? PandaLogLevel.warning
        : PandaLogLevel.info;
    _log(level, PandaLogCategory.performance, '⏱ $operation: ${durationMs}ms',
        durationMs: durationMs,
        metadata: details != null ? {'details': details} : null);
  }

  // ── Crash reporting ────────────────────────────────────────────────────

  static Future<void> crash(
    Object error,
    StackTrace stackTrace, {
    String? context,
  }) async {
    final event = PandaLogEvent(
      id: _generateId(),
      timestamp: DateTime.now(),
      level: PandaLogLevel.fatal,
      category: PandaLogCategory.crash,
      message: 'Uncaught: $error',
      sessionId: _sessionId,
      projectPath: _currentProjectPath,
      source: context,
      error: error.toString(),
      stackTrace: stackTrace.toString(),
      metadata: await _collectCrashMetadata(),
    );

    await PandaLogStore.instance.writeCrashReport(event);
    PandaLogStore.instance.write(event);

    if (kDebugMode) {
      debugPrint('[FATAL][CRASH] $error');
      debugPrint(stackTrace.toString());
    }
  }

  static Future<Map<String, dynamic>> _collectCrashMetadata() async {
    try {
      final info = await Process.run('uname', ['-a']);
      return {
        'platform': Platform.operatingSystem,
        'platformVersion': Platform.operatingSystemVersion,
        'dartVersion': Platform.version,
        'kernel': info.stdout.toString().trim(),
      };
    } catch (_) {
      return {
        'platform': Platform.operatingSystem,
        'platformVersion': Platform.operatingSystemVersion,
        'dartVersion': Platform.version,
      };
    }
  }

  // ── Query API (for Panda Agent and Logs Explorer) ──────────────────────

  /// Get recent events from memory.
  static List<PandaLogEvent> get recentEvents =>
      PandaLogStore.instance.recentEvents;

  /// Get the crash ring buffer.
  static List<PandaLogEvent> get ringBuffer =>
      PandaLogStore.instance.ringBuffer;

  /// Live stream of new events.
  static Stream<PandaLogEvent> get liveStream =>
      PandaLogStore.instance.liveStream;

  /// Get recent errors.
  static List<PandaLogEvent> getErrors({int limit = 50}) {
    return recentEvents
        .where((e) =>
            e.level == PandaLogLevel.error || e.level == PandaLogLevel.fatal)
        .take(limit)
        .toList();
  }

  /// Get events for a specific agent run.
  static List<PandaLogEvent> getLogsForAgentRun(String runId) {
    return recentEvents.where((e) => e.agentRunId == runId).toList();
  }

  /// Get events for a specific terminal command.
  static List<PandaLogEvent> getLogsForTerminalCommand(String command) {
    return recentEvents
        .where((e) =>
            e.category == PandaLogCategory.terminal && e.command == command)
        .toList();
  }

  /// Get events for a specific file.
  static List<PandaLogEvent> getLogsForFile(String path) {
    return recentEvents.where((e) => e.filePath == path).toList();
  }

  /// Get recent build logs.
  static List<PandaLogEvent> getRecentBuildLogs({int limit = 20}) {
    return recentEvents
        .where((e) => e.category == PandaLogCategory.build)
        .take(limit)
        .toList();
  }

  /// Search logs by query.
  static List<PandaLogEvent> searchLogs(
    String query, {
    PandaLogLevel? level,
    PandaLogCategory? category,
    DateTime? since,
  }) {
    return recentEvents.where((e) {
      if (level != null && e.level != level) return false;
      if (category != null && e.category != category) return false;
      if (since != null && e.timestamp.isBefore(since)) return false;
      if (query.isNotEmpty &&
          !e.message.toLowerCase().contains(query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  // ── Storage ────────────────────────────────────────────────────────────

  static Future<void> clearAll() async => PandaLogStore.instance.clearAll();
  static Future<void> clearCrashReports() async =>
      PandaLogStore.instance.clearCrashReports();
  static Future<int> getStorageSize() async =>
      PandaLogStore.instance.getStorageSize();
  static List<File> getLogFiles() => PandaLogStore.instance.getLogFiles();

  static Future<List<PandaLogEvent>> readLogFile(
    String path, {
    int offset = 0,
    int limit = 100,
    String? searchQuery,
    PandaLogLevel? levelFilter,
    PandaLogCategory? categoryFilter,
  }) =>
      PandaLogStore.instance.readLogFile(
        path,
        offset: offset,
        limit: limit,
        searchQuery: searchQuery,
        levelFilter: levelFilter,
        categoryFilter: categoryFilter,
      );

  // ── Export ─────────────────────────────────────────────────────────────

  static Future<File> exportDiagnostics() async {
    final dir = await getTemporaryDirectory();
    final exportDir = Directory('${dir.path}/panda-diagnostic');
    if (exportDir.existsSync()) await exportDir.delete(recursive: true);
    await exportDir.create(recursive: true);

    // Copy logs
    final logDir = Directory(pandaLogsDir);
    if (logDir.existsSync()) {
      for (final entity in logDir.listSync()) {
        if (entity is File) {
          await entity.copy('${exportDir.path}/${entity.path.split('/').last}');
        }
        if (entity is Directory) {
          final subName = entity.path.split('/').last;
          final subDir = Directory('${exportDir.path}/$subName');
          await subDir.create(recursive: true);
          for (final f in entity.listSync()) {
            if (f is File) {
              await f.copy(
                  '${subDir.path}/${f.path.split('/').last}');
            }
          }
        }
      }
    }

    // System info
    final appInfo = File('${exportDir.path}/app.json');
    await appInfo.writeAsString(SecretRedactor.redact('''{
  "platform": "${Platform.operatingSystem}",
  "platformVersion": "${Platform.operatingSystemVersion}",
  "dartVersion": "${Platform.version}",
  "diagnosticMode": $_diagnosticMode,
  "sessionId": "$sessionId",
  "projectPath": "${_currentProjectPath ?? ''}"
}'''), flush: true);

    // Create zip
    final zipFile = File('${dir.path}/panda-diagnostic.zip');
    // For simplicity on Android, return the directory path
    return zipFile;
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  static String _generateId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rand = (DateTime.now().microsecondsSinceEpoch % 99999).toString();
    return '$ts$rand';
  }
}
