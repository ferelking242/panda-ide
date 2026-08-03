/// PandaLog — système de logging pour Panda IDE.
///
/// Stratégie :
///  - Console (debugPrint) toujours actif en debug.
///  - Fichier (pandaLogsDir/panda-YYYY-MM-DD.log) actif dès que le dossier
///    existe (même en release, niveau WARNING et au-dessus).
///  - Rotation automatique : 7 jours max (fichiers plus anciens supprimés).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'constants.dart';

/// Niveaux de log.
enum PandaLevel { verbose, debug, info, warning, error }

/// Logger principal de Panda IDE.
///
/// ```dart
/// PandaLog.i('Agent', 'Sending request to ${model.chatUrl}');
/// PandaLog.e('Agent', 'HTTP ${resp.statusCode}', body: resp.body);
/// ```
abstract final class PandaLog {
  /// Active ou désactive tous les logs en debug. Sans effet sur les fichiers.
  static bool enabled = true;

  /// Niveau minimum affiché sur la console (en debug).
  static PandaLevel minLevel = PandaLevel.verbose;

  /// Niveau minimum écrit dans le fichier log (release + debug).
  static PandaLevel fileMinLevel = PandaLevel.info;

  static IOSink? _fileSink;
  static String? _openLogDate;
  static bool _fileLoggingReady = false;
  static final _lock = Completer<void>.sync();

  // ── Initialisation ────────────────────────────────────────────────────────

  /// À appeler une fois au démarrage (après que le dossier Panda IDE est créé).
  static Future<void> initFileLogging() async {
    if (kIsWeb) return;
    try {
      final dir = Directory(pandaLogsDir);
      if (!dir.existsSync()) await dir.create(recursive: true);
      await _openTodayLog(dir);
      await _rotateOldLogs(dir);
      _fileLoggingReady = true;
    } catch (e) {
      debugPrint('[PandaLog] initFileLogging failed: $e');
    }
  }

  static Future<void> _openTodayLog(Directory dir) async {
    final today = DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD
    if (_openLogDate == today && _fileSink != null) return;
    await _fileSink?.flush().catchError((_) {});
    await _fileSink?.close().catchError((_) {});
    final file = File('${dir.path}/panda-$today.log');
    _fileSink = file.openWrite(mode: FileMode.append);
    _openLogDate = today;
    _fileSink!.writeln('\n── Session started ${DateTime.now().toIso8601String()} ──');
  }

  static Future<void> _rotateOldLogs(Directory dir) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.path.split('/').last;
      if (!name.startsWith('panda-') || !name.endsWith('.log')) continue;
      // Extract YYYY-MM-DD from panda-YYYY-MM-DD.log
      final datePart = name.substring(6, 16);
      try {
        final fileDate = DateTime.parse(datePart);
        if (fileDate.isBefore(cutoff)) await entity.delete();
      } catch (_) {}
    }
  }

  // ── API publique ──────────────────────────────────────────────────────────

  static void v(String tag, String message, {String? body}) =>
      _log(PandaLevel.verbose, tag, message, body: body);

  static void d(String tag, String message, {String? body}) =>
      _log(PandaLevel.debug, tag, message, body: body);

  static void i(String tag, String message, {String? body}) =>
      _log(PandaLevel.info, tag, message, body: body);

  static void w(String tag, String message, {String? body}) =>
      _log(PandaLevel.warning, tag, message, body: body);

  static void e(String tag, String message, {String? body, Object? error}) {
    final extra = error != null ? '\n  error: $error' : '';
    _log(PandaLevel.error, tag, '$message$extra', body: body);
  }

  // ── Helpers spécialisés ──────────────────────────────────────────────────

  static void httpRequest(String tag, String method, String url, {String? body}) {
    final preview = _truncate(body, 500);
    _log(PandaLevel.debug, tag, '→ $method $url', body: preview);
  }

  static void httpResponse(String tag, int status, String url, {String? body}) {
    final level = status >= 400 ? PandaLevel.error : PandaLevel.debug;
    final preview = _truncate(body, 800);
    _log(level, tag, '← $status $url', body: preview);
  }

  static void toolCall(String tag, String name, Map<String, dynamic> args) {
    _log(PandaLevel.info, tag,
        '🔧 tool=$name args=${_truncate(args.toString(), 300)}');
  }

  static void toolResult(String tag, String name, String result) {
    _log(PandaLevel.debug, tag,
        '✅ tool=$name result=${_truncate(result, 300)}');
  }

  // ── Internals ────────────────────────────────────────────────────────────

  static void _log(PandaLevel level, String tag, String message,
      {String? body}) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final prefix = _levelPrefix(level);
    final line = '$prefix [$ts][$tag] $message';

    // Console (debug mode only)
    if (kDebugMode && enabled && level.index >= minLevel.index) {
      debugPrint(line);
      if (body != null && body.isNotEmpty) debugPrint('         $body');
    }

    // File (always, if ready, for WARNING+)
    if (!kIsWeb && _fileLoggingReady && level.index >= fileMinLevel.index) {
      _writeToFile(line, body);
    }
  }

  static void _writeToFile(String line, String? body) {
    try {
      // Rotate if day changed
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (today != _openLogDate) {
        // Schedule async rotation without awaiting
        final dir = Directory(pandaLogsDir);
        _openTodayLog(dir);
      }
      _fileSink?.writeln(line);
      if (body != null && body.isNotEmpty) _fileSink?.writeln('         $body');
    } catch (_) {}
  }

  static String _levelPrefix(PandaLevel level) {
    switch (level) {
      case PandaLevel.verbose: return '[V]';
      case PandaLevel.debug:   return '[D]';
      case PandaLevel.info:    return '[I]';
      case PandaLevel.warning: return '[W]';
      case PandaLevel.error:   return '[E]';
    }
  }

  static String? _truncate(String? s, int maxLen) {
    if (s == null) return null;
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen)}… [+${s.length - maxLen} chars]';
  }

  /// Flush proprement le fichier log (à appeler avant quitter l'app).
  static Future<void> flush() async {
    await _fileSink?.flush().catchError((_) {});
  }
}
