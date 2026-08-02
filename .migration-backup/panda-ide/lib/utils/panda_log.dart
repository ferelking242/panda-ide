/// PandaLog — système de logging léger pour Panda IDE.
///
/// Stratégie de performance :
///  - En mode release (`kDebugMode == false`) : toutes les méthodes sont
///    des no-ops inline, entièrement éliminées par le tree-shaker de Dart.
///  - En mode debug : les logs sont contrôlés par [PandaLog.enabled].
///    Mettre à `false` pour désactiver même en debug (ex: tests perf).
///  - Les lambdas passées à [d] / [i] / [w] / [e] ne sont jamais évaluées
///    en release grâce aux assertions conditionnelles.
library;

import 'package:flutter/foundation.dart';

/// Niveaux de log.
enum PandaLevel { verbose, debug, info, warning, error }

/// Logger principal de Panda IDE.
///
/// ```dart
/// PandaLog.i('Agent', 'Sending request to ${model.chatUrl}');
/// PandaLog.e('Agent', 'HTTP ${resp.statusCode}', body: resp.body);
/// ```
abstract final class PandaLog {
  /// Active ou désactive tous les logs en debug. Sans effet en release.
  static bool enabled = true;

  /// Niveau minimum affiché (en debug). Sans effet en release.
  static PandaLevel minLevel = PandaLevel.verbose;

  // ── API publique ──────────────────────────────────────────────────────────

  /// Log verbose (détails internes, payloads).
  static void v(String tag, String message, {String? body}) =>
      _log(PandaLevel.verbose, tag, message, body: body);

  /// Log debug (flow, valeurs intermédiaires).
  static void d(String tag, String message, {String? body}) =>
      _log(PandaLevel.debug, tag, message, body: body);

  /// Log info (étapes clés).
  static void i(String tag, String message, {String? body}) =>
      _log(PandaLevel.info, tag, message, body: body);

  /// Log warning (dégradation non fatale).
  static void w(String tag, String message, {String? body}) =>
      _log(PandaLevel.warning, tag, message, body: body);

  /// Log erreur (échec, exception).
  static void e(String tag, String message, {String? body, Object? error}) {
    if (!kDebugMode || !enabled) return;
    final extra = error != null ? '\n  error: $error' : '';
    _log(PandaLevel.error, tag, '$message$extra', body: body);
  }

  // ── Helpers spécialisés ──────────────────────────────────────────────────

  /// Log une requête HTTP sortante.
  static void httpRequest(String tag, String method, String url,
      {String? body}) {
    if (!kDebugMode || !enabled) return;
    final preview = _truncate(body, 500);
    _log(PandaLevel.debug, tag, '→ $method $url', body: preview);
  }

  /// Log une réponse HTTP.
  static void httpResponse(String tag, int status, String url,
      {String? body}) {
    if (!kDebugMode || !enabled) return;
    final level = status >= 400 ? PandaLevel.error : PandaLevel.debug;
    final preview = _truncate(body, 800);
    _log(level, tag, '← $status $url', body: preview);
  }

  /// Log un appel de tool.
  static void toolCall(String tag, String name,
      Map<String, dynamic> args) {
    if (!kDebugMode || !enabled) return;
    _log(PandaLevel.info, tag, '🔧 tool=$name args=${_truncate(args.toString(), 300)}');
  }

  /// Log le résultat d'un tool.
  static void toolResult(String tag, String name, String result) {
    if (!kDebugMode || !enabled) return;
    _log(PandaLevel.debug, tag, '✅ tool=$name result=${_truncate(result, 300)}');
  }

  // ── Internals ────────────────────────────────────────────────────────────

  static void _log(PandaLevel level, String tag, String message,
      {String? body}) {
    if (!kDebugMode || !enabled) return;
    if (level.index < minLevel.index) return;

    final prefix = _levelPrefix(level);
    final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:mm:ss.mmm
    final line = '$prefix [$ts][$tag] $message';
    debugPrint(line);
    if (body != null && body.isNotEmpty) {
      // Indentation pour lisibilité dans la console
      debugPrint('         $body');
    }
  }

  static String _levelPrefix(PandaLevel level) {
    switch (level) {
      case PandaLevel.verbose:
        return '[V]';
      case PandaLevel.debug:
        return '[D]';
      case PandaLevel.info:
        return '[I]';
      case PandaLevel.warning:
        return '[W]';
      case PandaLevel.error:
        return '[E]';
    }
  }

  static String? _truncate(String? s, int maxLen) {
    if (s == null) return null;
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen)}… [+${s.length - maxLen} chars]';
  }
}
