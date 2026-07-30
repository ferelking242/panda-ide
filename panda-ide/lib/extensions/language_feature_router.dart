/// LanguageFeatureRouter — vscode.languages.* → code_forge — Phase 4.
///
/// Reçoit les résultats des providers d'extension (completion, hover,
/// diagnostics, definition, references, signature, codeAction, format)
/// et les injecte dans le CodeForgeController actif.
///
/// Architecture :
///   Extension (Node.js)
///     → apiCall 'languages.registerXxxProvider'  → ExtensionApiRouter
///     → stash du provider dans cette classe
///   L'éditeur flutter_forge demande des complétions / hover / etc.
///     → LanguageFeatureRouter.requestXxx()
///     → envoie une 'apiCall' au host.js de l'extension
///     → reçoit la réponse
///     → convertit + injecte dans CodeForgeController
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'ipc_bridge.dart';

// ── Provider registration models ─────────────────────────────────────────

class _ProviderEntry {
  final String extensionId;
  final String providerId;
  final List<String> documentSelector; // language IDs ou glob patterns

  const _ProviderEntry({
    required this.extensionId,
    required this.providerId,
    required this.documentSelector,
  });

  bool matches(String languageId) =>
      documentSelector.isEmpty ||
      documentSelector.any((s) =>
          s == '*' || s == languageId || s.startsWith('*'));
}

// ── Diagnostic model (Flutter-side) ──────────────────────────────────────

class ExtensionDiagnostic {
  final String filePath;
  final String message;
  final int severity; // 0=Error 1=Warning 2=Info 3=Hint
  final int startLine;
  final int startChar;
  final int endLine;
  final int endChar;
  final String? source;
  final String? code;

  const ExtensionDiagnostic({
    required this.filePath,
    required this.message,
    required this.severity,
    required this.startLine,
    required this.startChar,
    required this.endLine,
    required this.endChar,
    this.source,
    this.code,
  });

  static ExtensionDiagnostic fromJson(String filePath, Map<String, dynamic> j) {
    final range    = j['range'] as Map<String, dynamic>? ?? {};
    final start    = range['start'] as Map<String, dynamic>? ?? {};
    final end      = range['end']   as Map<String, dynamic>? ?? {};
    return ExtensionDiagnostic(
      filePath:  filePath,
      message:   j['message'] as String? ?? '',
      severity:  (j['severity'] as num?)?.toInt() ?? 0,
      startLine: (start['line'] as num?)?.toInt() ?? 0,
      startChar: (start['character'] as num?)?.toInt() ?? 0,
      endLine:   (end['line'] as num?)?.toInt() ?? 0,
      endChar:   (end['character'] as num?)?.toInt() ?? 0,
      source:    j['source'] as String?,
      code:      j['code']?.toString(),
    );
  }
}

// ── Completion item model (Flutter-side) ──────────────────────────────────

class ExtensionCompletionItem {
  final String label;
  final String? detail;
  final String? documentation;
  final int kind; // VSCode CompletionItemKind
  final String insertText;
  final bool isSnippet;

  const ExtensionCompletionItem({
    required this.label,
    this.detail,
    this.documentation,
    required this.kind,
    required this.insertText,
    this.isSnippet = false,
  });

  static ExtensionCompletionItem fromJson(Map<String, dynamic> j) {
    final insertTextOrSnippet = j['insertText'];
    String insertText;
    bool isSnippet = false;

    if (insertTextOrSnippet is Map<String, dynamic>) {
      insertText = insertTextOrSnippet['value'] as String? ?? j['label'] as String? ?? '';
      isSnippet  = true;
    } else {
      insertText = insertTextOrSnippet as String? ?? j['label'] as String? ?? '';
    }

    return ExtensionCompletionItem(
      label:         j['label'] as String? ?? '',
      detail:        j['detail'] as String?,
      documentation: j['documentation'] is Map
          ? (j['documentation'] as Map)['value'] as String?
          : j['documentation'] as String?,
      kind:          (j['kind'] as num?)?.toInt() ?? 1,
      insertText:    insertText,
      isSnippet:     isSnippet,
    );
  }
}

// ── LanguageFeatureRouter ─────────────────────────────────────────────────

class LanguageFeatureRouter {
  static final LanguageFeatureRouter instance = LanguageFeatureRouter._();
  LanguageFeatureRouter._();

  // Provider registries keyed by type
  final Map<String, List<_ProviderEntry>> _providers = {
    'completion':  [],
    'hover':       [],
    'definition':  [],
    'references':  [],
    'signature':   [],
    'codeAction':  [],
    'format':      [],
    'diagnostics': [],
    'rename':      [],
    'symbol':      [],
  };

  // Diagnostics: filePath → list<diagnostic>
  final Map<String, List<ExtensionDiagnostic>> _diagnostics = {};

  // Notifier pour que l'UI réagisse aux nouveaux diagnostics
  final ValueNotifier<int> diagnosticsVersion = ValueNotifier(0);

  // IPC bridge lookup : extensionId → IpcBridge
  IpcBridge? Function(String extensionId)? bridgeLookup;

  // ── Provider registration (called by ExtensionApiRouter) ─────────────────

  /// Appelé par ExtensionApiRouter quand une extension enregistre un provider.
  /// [providerId] est généré côté JS et correspond à la méthode IPC
  /// 'provider.<providerId>.invoke' exposée par Node.js.
  String registerProvider({
    required String type,
    required String extensionId,
    required String providerId,
    required List<dynamic> selector,
  }) {
    // Déduplique si déjà enregistré (ex: rechargement)
    _providers[type]?.removeWhere((e) => e.providerId == providerId);
    final entry = _ProviderEntry(
      extensionId:      extensionId,
      providerId:       providerId,
      documentSelector: _resolveSelector(selector),
    );
    _providers[type]?.add(entry);
    return providerId;
  }

  void unregisterProvider(String providerId) {
    for (final list in _providers.values) {
      list.removeWhere((e) => e.providerId == providerId);
    }
  }

  List<String> _resolveSelector(List<dynamic> raw) {
    final result = <String>[];
    for (final item in raw) {
      if (item is String) {
        result.add(item);
      } else if (item is Map<String, dynamic>) {
        final lang = item['language'] as String?;
        if (lang != null) result.add(lang);
      }
    }
    return result;
  }

  // ── Diagnostics (push model — extension pushes, Flutter reacts) ───────────

  void setDiagnostics(String fsPath, List<dynamic> rawDiagnostics) {
    if (rawDiagnostics.isEmpty) {
      _diagnostics.remove(fsPath);
    } else {
      _diagnostics[fsPath] = rawDiagnostics
          .whereType<Map<String, dynamic>>()
          .map((d) => ExtensionDiagnostic.fromJson(fsPath, d))
          .toList();
    }
    diagnosticsVersion.value++;
  }

  void clearDiagnostics(String extensionId) {
    _diagnostics.clear();
    diagnosticsVersion.value++;
  }

  List<ExtensionDiagnostic> getDiagnosticsForFile(String fsPath) =>
      _diagnostics[fsPath] ?? [];

  Map<String, List<ExtensionDiagnostic>> get allDiagnostics =>
      Map.unmodifiable(_diagnostics);

  // ── Completion request (pull model) ───────────────────────────────────────

  Future<List<ExtensionCompletionItem>> requestCompletions({
    required String filePath,
    required String languageId,
    required String content,
    required int line,
    required int character,
    required String triggerCharacter,
  }) async {
    final providers = _matchProviders('completion', languageId);
    if (providers.isEmpty) return [];

    final results = <ExtensionCompletionItem>[];
    for (final entry in providers) {
      final bridge = bridgeLookup?.call(entry.extensionId);
      if (bridge == null) continue;
      try {
        final response = await bridge.call(
          'provider.${entry.providerId}.invoke',
          [
            {
              'uri':        {'fsPath': filePath, 'scheme': 'file', 'path': filePath},
              'languageId': languageId,
              'content':    content,
            },
            {
              'line':      line,
              'character': character,
            },
            {
              'triggerKind':      triggerCharacter.isEmpty ? 1 : 2,
              'triggerCharacter': triggerCharacter.isEmpty ? null : triggerCharacter,
            },
          ],
        );

        final items = _unwrapCompletionResponse(response);
        results.addAll(items.map(ExtensionCompletionItem.fromJson));
      } catch (_) {}
    }
    return results;
  }

  // ── Hover request ─────────────────────────────────────────────────────────

  Future<String?> requestHover({
    required String filePath,
    required String languageId,
    required String content,
    required int line,
    required int character,
  }) async {
    final providers = _matchProviders('hover', languageId);
    for (final entry in providers) {
      final bridge = bridgeLookup?.call(entry.extensionId);
      if (bridge == null) continue;
      try {
        final response = await bridge.call(
          'provider.${entry.providerId}.invoke',
          [
            {
              'uri':        {'fsPath': filePath, 'scheme': 'file', 'path': filePath},
              'languageId': languageId,
              'content':    content,
            },
            {'line': line, 'character': character},
          ],
        );
        if (response == null) continue;
        final hover = response as Map<String, dynamic>?;
        if (hover == null) continue;
        final contents = hover['contents'] as List<dynamic>? ?? [];
        if (contents.isEmpty) continue;

        final sb = StringBuffer();
        for (final c in contents) {
          if (c is String) {
            sb.writeln(c);
          } else if (c is Map<String, dynamic>) {
            sb.writeln(c['value'] as String? ?? '');
          }
        }
        return sb.toString().trim();
      } catch (_) {}
    }
    return null;
  }

  // ── Definition request ────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> requestDefinition({
    required String filePath,
    required String languageId,
    required int line,
    required int character,
  }) async {
    final providers = _matchProviders('definition', languageId);
    final results   = <Map<String, dynamic>>[];
    for (final entry in providers) {
      final bridge = bridgeLookup?.call(entry.extensionId);
      if (bridge == null) continue;
      try {
        final response = await bridge.call(
          'provider.${entry.providerId}.invoke',
          [
            {'uri': {'fsPath': filePath, 'scheme': 'file', 'path': filePath}, 'languageId': languageId},
            {'line': line, 'character': character},
          ],
        );
        if (response is List) {
          results.addAll(response.whereType<Map<String, dynamic>>());
        } else if (response is Map<String, dynamic>) {
          results.add(response);
        }
      } catch (_) {}
    }
    return results;
  }

  // ── Format request ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> requestFormat({
    required String filePath,
    required String languageId,
    required String content,
    required Map<String, dynamic> options,
  }) async {
    final providers = _matchProviders('format', languageId);
    for (final entry in providers) {
      final bridge = bridgeLookup?.call(entry.extensionId);
      if (bridge == null) continue;
      try {
        final response = await bridge.call(
          'provider.${entry.providerId}.invoke',
          [
            {
              'uri':        {'fsPath': filePath, 'scheme': 'file', 'path': filePath},
              'languageId': languageId,
              'content':    content,
            },
            options,
          ],
        );
        if (response is List && response.isNotEmpty) {
          return response.whereType<Map<String, dynamic>>().toList();
        }
      } catch (_) {}
    }
    return [];
  }

  // ── Code Action request ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> requestCodeActions({
    required String filePath,
    required String languageId,
    required Map<String, dynamic> range,
    required List<ExtensionDiagnostic> contextDiagnostics,
  }) async {
    final providers = _matchProviders('codeAction', languageId);
    final results   = <Map<String, dynamic>>[];
    for (final entry in providers) {
      final bridge = bridgeLookup?.call(entry.extensionId);
      if (bridge == null) continue;
      try {
        final response = await bridge.call(
          'provider.${entry.providerId}.invoke',
          [
            {'uri': {'fsPath': filePath, 'scheme': 'file', 'path': filePath}, 'languageId': languageId},
            range,
            {
              'diagnostics': contextDiagnostics.map((d) => {
                'message':  d.message,
                'severity': d.severity,
                'range': {
                  'start': {'line': d.startLine, 'character': d.startChar},
                  'end':   {'line': d.endLine,   'character': d.endChar},
                },
              }).toList(),
            },
          ],
        );
        if (response is List) {
          results.addAll(response.whereType<Map<String, dynamic>>());
        }
      } catch (_) {}
    }
    return results;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<_ProviderEntry> _matchProviders(String type, String languageId) =>
      (_providers[type] ?? [])
          .where((e) => e.matches(languageId))
          .toList();

  List<Map<String, dynamic>> _unwrapCompletionResponse(dynamic response) {
    if (response == null) return [];
    if (response is List) {
      return response.whereType<Map<String, dynamic>>().toList();
    }
    if (response is Map<String, dynamic>) {
      // CompletionList: { isIncomplete, items }
      final items = response['items'] as List<dynamic>? ?? [];
      return items.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }
}
