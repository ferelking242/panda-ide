import 'dart:convert';
import 'panda_log_level.dart';

/// A single structured log event.
class PandaLogEvent {
  final String id;
  final DateTime timestamp;
  final PandaLogLevel level;
  final PandaLogCategory category;
  final String message;

  /// Session-level correlation.
  final String? sessionId;
  final String? agentRunId;
  final String? toolCallId;

  /// Source location.
  final String? source;

  /// Duration for timed operations.
  final int? durationMs;

  /// File context.
  final String? projectPath;
  final String? filePath;
  final int? line;
  final int? column;

  /// Command context (terminal / git / build).
  final String? command;
  final String? cwd;
  final int? exitCode;

  /// Arbitrary key-value metadata.
  final Map<String, dynamic>? metadata;

  /// Error info.
  final String? error;
  final String? stackTrace;

  PandaLogEvent({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.sessionId,
    this.agentRunId,
    this.toolCallId,
    this.source,
    this.durationMs,
    this.projectPath,
    this.filePath,
    this.line,
    this.column,
    this.command,
    this.cwd,
    this.exitCode,
    this.metadata,
    this.error,
    this.stackTrace,
  });

  /// Serialize to JSON Lines format.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'ts': timestamp.toIso8601String(),
      'level': level.label,
      'cat': category.label,
      'msg': message,
    };
    if (sessionId != null)    map['sid'] = sessionId;
    if (agentRunId != null)   map['run'] = agentRunId;
    if (toolCallId != null)   map['tool'] = toolCallId;
    if (source != null)       map['src'] = source;
    if (durationMs != null)   map['dur'] = durationMs;
    if (projectPath != null)  map['proj'] = projectPath;
    if (filePath != null)     map['file'] = filePath;
    if (line != null)         map['line'] = line;
    if (column != null)       map['col'] = column;
    if (command != null)      map['cmd'] = command;
    if (cwd != null)          map['cwd'] = cwd;
    if (exitCode != null)     map['exit'] = exitCode;
    if (metadata != null && metadata!.isNotEmpty) map['meta'] = metadata;
    if (error != null)        map['err'] = error;
    if (stackTrace != null)   map['stack'] = stackTrace;
    return map;
  }

  String toJsonLine() => jsonEncode(toJson());

  /// Deserialize from a JSON map.
  factory PandaLogEvent.fromJson(Map<String, dynamic> m) {
    return PandaLogEvent(
      id: m['id'] as String? ?? '',
      timestamp: DateTime.tryParse(m['ts'] as String? ?? '') ?? DateTime.now(),
      level: PandaLogLevel.values.firstWhere(
        (l) => l.label == m['level'],
        orElse: () => PandaLogLevel.info,
      ),
      category: PandaLogCategory.fromString(m['cat'] as String? ?? 'app'),
      message: m['msg'] as String? ?? '',
      sessionId: m['sid'] as String?,
      agentRunId: m['run'] as String?,
      toolCallId: m['tool'] as String?,
      source: m['src'] as String?,
      durationMs: m['dur'] as int?,
      projectPath: m['proj'] as String?,
      filePath: m['file'] as String?,
      line: m['line'] as int?,
      column: m['col'] as int?,
      command: m['cmd'] as String?,
      cwd: m['cwd'] as String?,
      exitCode: m['exit'] as int?,
      metadata: m['meta'] != null
          ? Map<String, dynamic>.from(m['meta'] as Map)
          : null,
      error: m['err'] as String?,
      stackTrace: m['stack'] as String?,
    );
  }

  /// Parse a single JSON line.
  static PandaLogEvent? fromJsonLine(String line) {
    try {
      return PandaLogEvent.fromJson(jsonDecode(line) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      '[${level.prefix}][${category.label}] $message';
}
