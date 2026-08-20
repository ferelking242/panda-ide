import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/constants.dart';
import 'panda_log_event.dart';
import 'panda_log_level.dart';
import 'secret_redactor.dart';

/// Configuration for log storage.
class PandaLogConfig {
  /// Maximum size per log file in bytes (default ~10 MB).
  final int maxFileSizeBytes;

  /// Number of days to retain logs.
  final int retentionDays;

  /// Number of days to retain crash logs.
  final int crashRetentionDays;

  /// Minimum level to write to file.
  final PandaLogLevel fileMinLevel;

  /// Flush interval for batched writes.
  final Duration flushInterval;

  /// Maximum events in memory before force flush.
  final int maxBufferSize;

  const PandaLogConfig({
    this.maxFileSizeBytes = 10 * 1024 * 1024,
    this.retentionDays = 30,
    this.crashRetentionDays = 90,
    this.fileMinLevel = PandaLogLevel.debug,
    this.flushInterval = const Duration(seconds: 3),
    this.maxBufferSize = 200,
  });

  static const defaultConfig = PandaLogConfig();

  /// Diagnostic mode config with more verbose logging.
  static const diagnosticConfig = PandaLogConfig(
    fileMinLevel: PandaLogLevel.debug,
    flushInterval: Duration(seconds: 1),
    maxBufferSize: 500,
  );
}



/// Background log writer that batches events and writes to disk.
class PandaLogStore {
  static PandaLogStore? _instance;
  static PandaLogStore get instance => _instance ??= PandaLogStore._();

  PandaLogStore._();

  PandaLogConfig _config = PandaLogConfig.defaultConfig;
  final Queue<PandaLogEvent> _buffer = Queue<PandaLogEvent>();
  final List<PandaLogEvent> _recentRingBuffer = [];
  Timer? _flushTimer;
  bool _initialized = false;
  IOSink? _currentSink;
  String? _currentLogPath;
  DateTime? _currentLogDate;

  /// In-memory store for the Logs Explorer (last N events).
  final List<PandaLogEvent> _memoryEvents = [];
  static const int _maxMemoryEvents = 2000;

  /// Stream for live mode in Logs Explorer.
  final StreamController<PandaLogEvent> _liveController =
      StreamController<PandaLogEvent>.broadcast();
  Stream<PandaLogEvent> get liveStream => _liveController.stream;

  /// Get recent events from memory.
  List<PandaLogEvent> get recentEvents =>
      List.unmodifiable(_memoryEvents);

  /// Get the crash ring buffer.
  List<PandaLogEvent> get ringBuffer =>
      List.unmodifiable(_recentRingBuffer);

  /// Initialize the store.
  Future<void> init({PandaLogConfig? config}) async {
    if (_initialized) return;
    _config = config ?? PandaLogConfig.defaultConfig;

    try {
      final dir = Directory(pandaLogsDir);
      if (!dir.existsSync()) await dir.create(recursive: true);

      // Create subdirectories
      for (final sub in ['agent', 'terminal', 'crash', 'diagnostics']) {
        final subDir = Directory('${dir.path}/$sub');
        if (!subDir.existsSync()) await subDir.create(recursive: true);
      }

      _rotateOldLogs();
      _initialized = true;
      _startFlushTimer();
    } catch (e) {
      debugPrint('[PandaLogStore] init failed: $e');
    }
  }

  /// Update config at runtime (e.g., toggle diagnostic mode).
  void updateConfig(PandaLogConfig config) {
    _config = config;
    _startFlushTimer();
  }

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_config.flushInterval, (_) => flush());
  }

  /// Enqueue a log event.
  void write(PandaLogEvent event) {
    // Always keep in ring buffer for crash recovery (last 100 events)
    _recentRingBuffer.add(event);
    if (_recentRingBuffer.length > 100) {
      _recentRingBuffer.removeAt(0);
    }

    // Keep in memory for Logs Explorer
    _memoryEvents.add(event);
    if (_memoryEvents.length > _maxMemoryEvents) {
      _memoryEvents.removeAt(0);
    }

    // Broadcast to live listeners
    if (!_liveController.isClosed) {
      _liveController.add(event);
    }

    // Check level filter
    if (event.level.index < _config.fileMinLevel.index) return;

    // Apply secret redaction
    final redacted = _redactEvent(event);

    _buffer.add(redacted);

    // Force flush on critical events
    if (event.level == PandaLogLevel.error ||
        event.level == PandaLogLevel.fatal ||
        _buffer.length >= _config.maxBufferSize) {
      flush();
    }
  }

  PandaLogEvent _redactEvent(PandaLogEvent event) {
    if (!SecretRedactor.containsSensitive(event.message)) return event;

    return PandaLogEvent(
      id: event.id,
      timestamp: event.timestamp,
      level: event.level,
      category: event.category,
      message: SecretRedactor.redact(event.message),
      sessionId: event.sessionId,
      agentRunId: event.agentRunId,
      toolCallId: event.toolCallId,
      source: event.source,
      durationMs: event.durationMs,
      projectPath: event.projectPath,
      filePath: event.filePath,
      line: event.line,
      column: event.column,
      command: SecretRedactor.redact(event.command ?? ''),
      cwd: event.cwd,
      exitCode: event.exitCode,
      metadata: event.metadata,
      error: event.error != null ? SecretRedactor.redact(event.error!) : null,
      stackTrace: event.stackTrace,
    );
  }

  /// Flush buffered events to disk.
  Future<void> flush() async {
    if (_buffer.isEmpty) return;

    try {
      final sink = await _getSink();
      if (sink == null) return;

      while (_buffer.isNotEmpty) {
        final event = _buffer.removeFirst();
        sink.writeln(event.toJsonLine());
      }

      await sink.flush();
    } catch (e) {
      debugPrint('[PandaLogStore] flush error: $e');
      // Don't let logging failures crash the app
    }
  }

  /// Write a crash report directly (bypasses buffer).
  Future<void> writeCrashReport(PandaLogEvent event) async {
    try {
      final crashDir = Directory('${pandaLogsDir}/crash');
      if (!crashDir.existsSync()) await crashDir.create(recursive: true);

      final ts = event.timestamp
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('-', '')
          .substring(0, 15);
      final file = File('${crashDir.path}/crash-$ts.log');
      final sink = file.openWrite(mode: FileMode.append);
      sink.writeln(event.toJsonLine());
      await sink.flush();
      await sink.close();
    } catch (e) {
      debugPrint('[PandaLogStore] crash write error: $e');
    }
  }

  Future<IOSink?> _getSink() async {
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    if (_currentLogDate != null &&
        _currentLogDate!.year == today.year &&
        _currentLogDate!.month == today.month &&
        _currentLogDate!.day == today.day &&
        _currentSink != null) {
      return _currentSink;
    }

    // Close previous sink
    try {
      await _currentSink?.flush();
      await _currentSink?.close();
    } catch (_) {}

    try {
      final file = File('$pandaLogsDir/$dateStr.log');
      _currentSink = file.openWrite(mode: FileMode.append);
      _currentLogPath = file.path;
      _currentLogDate = today;

      // Check file size for rotation
      if (file.existsSync() && file.lengthSync() > _config.maxFileSizeBytes) {
        final rotated = File('${file.path}.${DateTime.now().millisecondsSinceEpoch}');
        await file.rename(rotated.path);
        _currentSink = file.openWrite(mode: FileMode.append);
        _currentLogPath = file.path;
      }

      return _currentSink;
    } catch (e) {
      debugPrint('[PandaLogStore] sink creation error: $e');
      return null;
    }
  }

  /// Rotate old log files based on retention policy.
  void _rotateOldLogs() {
    try {
      final dir = Directory(pandaLogsDir);
      if (!dir.existsSync()) return;

      final cutoff = DateTime.now().subtract(Duration(days: _config.retentionDays));
      final crashCutoff =
          DateTime.now().subtract(Duration(days: _config.crashRetentionDays));

      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        final name = entity.path.split('/').last;

        // Regular logs: YYYY-MM-DD.log
        if (RegExp(r'^\d{4}-\d{2}-\d{2}\.log$').hasMatch(name)) {
          try {
            final datePart = name.substring(0, 10);
            final fileDate = DateTime.parse(datePart);
            if (fileDate.isBefore(cutoff)) {
              entity.deleteSync();
            }
          } catch (_) {}
        }

        // Crash logs
        if (entity.path.contains('/crash/') && name.startsWith('crash-')) {
          try {
            if (entity.lastModifiedSync().isBefore(crashCutoff)) {
              entity.deleteSync();
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[PandaLogStore] rotation error: $e');
    }
  }

  /// Get total log storage size in bytes.
  Future<int> getStorageSize() async {
    try {
      final dir = Directory(pandaLogsDir);
      if (!dir.existsSync()) return 0;
      int total = 0;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) {
          total += entity.lengthSync();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Clear all logs.
  Future<void> clearAll() async {
    try {
      final dir = Directory(pandaLogsDir);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
      _memoryEvents.clear();
      _recentRingBuffer.clear();
      _buffer.clear();
    } catch (e) {
      debugPrint('[PandaLogStore] clear error: $e');
    }
  }

  /// Clear only crash reports.
  Future<void> clearCrashReports() async {
    try {
      final dir = Directory('${pandaLogsDir}/crash');
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (_) {}
  }

  /// Read logs from a file with pagination.
  Future<List<PandaLogEvent>> readLogFile(
    String path, {
    int offset = 0,
    int limit = 100,
    String? searchQuery,
    PandaLogLevel? levelFilter,
    PandaLogCategory? categoryFilter,
    DateTime? since,
    DateTime? until,
  }) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return [];

      final lines = await file.readAsLines();
      final results = <PandaLogEvent>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final event = PandaLogEvent.fromJsonLine(line);
        if (event == null) continue;

        if (levelFilter != null && event.level != levelFilter) continue;
        if (categoryFilter != null && event.category != categoryFilter) continue;
        if (since != null && event.timestamp.isBefore(since)) continue;
        if (until != null && event.timestamp.isAfter(until)) continue;
        if (searchQuery != null &&
            searchQuery.isNotEmpty &&
            !event.message
                .toLowerCase()
                .contains(searchQuery.toLowerCase())) {
          continue;
        }

        results.add(event);
      }

      // Sort newest first
      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (offset >= results.length) return [];
      final end = (offset + limit).clamp(0, results.length);
      return results.sublist(offset, end);
    } catch (e) {
      debugPrint('[PandaLogStore] read error: $e');
      return [];
    }
  }

  /// Get all log files sorted by date.
  List<File> getLogFiles() {
    try {
      final dir = Directory(pandaLogsDir);
      if (!dir.existsSync()) return [];
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => RegExp(r'^\d{4}-\d{2}-\d{2}\.log$')
              .hasMatch(f.path.split('/').last))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      return files;
    } catch (_) {
      return [];
    }
  }

  /// Clean up resources.
  Future<void> dispose() async {
    _flushTimer?.cancel();
    await flush();
    try {
      await _currentSink?.flush();
      await _currentSink?.close();
    } catch (_) {}
    await _liveController.close();
    _initialized = false;
  }
}
