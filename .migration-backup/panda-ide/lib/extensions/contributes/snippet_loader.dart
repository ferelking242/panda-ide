/// Chargeur de snippets VSCode — Phase 13.
///
/// Charge les fichiers .json de snippets depuis les extensions installées
/// et les expose au moteur de complétion (code_forge).
///
/// Format : contributes.snippets[].path → fichier JSON VSCode snippets
/// Référence : https://code.visualstudio.com/docs/editor/userdefinedsnippets
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../extension_registry.dart';

// ── Modèles ────────────────────────────────────────────────────────────────

class VsSnippet {
  final String name;
  final String prefix;
  final List<String> prefixes;  // some snippets have multiple prefixes
  final List<String> body;      // lines of the snippet body
  final String? description;
  final String languageId;
  final String extensionId;

  const VsSnippet({
    required this.name,
    required this.prefix,
    required this.prefixes,
    required this.body,
    this.description,
    required this.languageId,
    required this.extensionId,
  });

  /// Body as a single string with newlines.
  String get bodyText => body.join('\n');

  /// Converts $1, $2, ${1:placeholder} tabstops to their placeholder text.
  String get bodyWithPlaceholders {
    return bodyText
        .replaceAllMapped(RegExp(r'\$\{(\d+):([^}]*)\}'), (m) => m.group(2) ?? '')
        .replaceAllMapped(RegExp(r'\$(\d+)'), (_) => '');
  }

  Map<String, dynamic> toCompletionItem() => {
    'label': prefix,
    'detail': '${name} (snippet)',
    'documentation': description,
    'insertText': bodyText,
    'kind': 15, // Snippet
  };
}

// ── Loader ─────────────────────────────────────────────────────────────────────

class SnippetLoader {
  static final SnippetLoader instance = SnippetLoader._();
  SnippetLoader._();

  /// language → list of snippets
  final Map<String, List<VsSnippet>> _snippets = {};

  Map<String, List<VsSnippet>> get allSnippets => Map.unmodifiable(_snippets);

  List<VsSnippet> snippetsForLanguage(String languageId) =>
      _snippets[languageId] ?? const [];

  // ── Loading ─────────────────────────────────────────────────────────────────

  Future<void> loadAll() async {
    await ExtensionRegistry.instance.load();
    for (final ext in ExtensionRegistry.instance.all) {
      await loadFromExtension(ext);
    }
  }

  Future<void> loadFromExtension(InstalledExtension ext) async {
    final snippets = ext.manifest.raw['contributes']?['snippets'];
    if (snippets is! List) return;

    for (final entry in snippets) {
      if (entry is! Map<String, dynamic>) continue;
      final path = entry['path'] as String?;
      final language = entry['language'] as String? ?? 'plaintext';
      if (path == null) continue;

      final filePath = p.join(ext.installPath, path.replaceFirst('./', ''));
      await _loadSnippetFile(filePath, languageId: language, extensionId: ext.manifest.id);
    }
  }

  Future<void> _loadSnippetFile(
    String filePath, {
    required String languageId,
    required String extensionId,
  }) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return;

      final raw = await file.readAsString();
      final cleaned = raw.replaceAll(RegExp(r'//[^\n]*'), '');
      final json = jsonDecode(cleaned) as Map<String, dynamic>;

      final snippetList = _snippets.putIfAbsent(languageId, () => []);

      json.forEach((name, value) {
        if (value is! Map<String, dynamic>) return;

        // prefix can be string or array
        final rawPrefix = value['prefix'];
        final prefixes = rawPrefix is List
            ? rawPrefix.map((e) => e.toString()).toList()
            : rawPrefix is String
                ? [rawPrefix]
                : <String>[];

        if (prefixes.isEmpty) return;

        // body can be string or array of strings
        final rawBody = value['body'];
        final body = rawBody is List
            ? rawBody.map((e) => e.toString()).toList()
            : rawBody is String
                ? rawBody.split('\n')
                : <String>[];

        snippetList.add(VsSnippet(
          name: name,
          prefix: prefixes.first,
          prefixes: prefixes,
          body: body,
          description: value['description'] as String?,
          languageId: languageId,
          extensionId: extensionId,
        ));
      });
    } catch (e) {
      debugPrint('[SnippetLoader] Failed to load $filePath: $e');
    }
  }

  // ── Query ──────────────────────────────────────────────────────────────────

  /// Retourne les snippets correspondant au préfixe pour un langage.
  List<VsSnippet> searchByPrefix(String languageId, String prefix) {
    final lp = prefix.toLowerCase();
    return snippetsForLanguage(languageId)
        .where((s) => s.prefixes.any((p) => p.toLowerCase().startsWith(lp)))
        .toList();
  }

  void unloadExtension(String extensionId) {
    for (final list in _snippets.values) {
      list.removeWhere((s) => s.extensionId == extensionId);
    }
  }
}
