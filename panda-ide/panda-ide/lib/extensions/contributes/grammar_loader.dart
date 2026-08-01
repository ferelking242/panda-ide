/// Chargeur de grammaires TextMate — Phase 13.
///
/// Charge les fichiers .tmLanguage.json / .tmGrammar.json depuis les extensions.
/// Ces grammaires définissent la coloration syntaxique des langages.
///
/// Référence : https://code.visualstudio.com/api/language-extensions/syntax-highlight-guide
/// Format : contributes.grammars[].path → fichier JSON TextMate grammar
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../extension_registry.dart';

// ── Modèles ────────────────────────────────────────────────────────────────

class TmGrammar {
  final String scopeName;       // ex: 'source.python'
  final String languageId;      // ex: 'python'
  final String filePath;
  final String extensionId;
  final Map<String, dynamic> raw;

  const TmGrammar({
    required this.scopeName,
    required this.languageId,
    required this.filePath,
    required this.extensionId,
    required this.raw,
  });

  /// Retourne les patterns de tokenisation (simplifié).
  List<Map<String, dynamic>> get patterns =>
      (raw['patterns'] as List?)?.cast<Map<String, dynamic>>() ?? [];

  /// Retourne les repository entries.
  Map<String, dynamic> get repository =>
      (raw['repository'] as Map<String, dynamic>?) ?? {};
}

class LanguageContribution {
  final String id;
  final List<String> extensions;  // file extensions (ex: ['.py'])
  final List<String> aliases;     // display names
  final String? firstLine;        // first-line pattern
  final String extensionId;

  const LanguageContribution({
    required this.id,
    required this.extensions,
    required this.aliases,
    this.firstLine,
    required this.extensionId,
  });
}

// ── Loader ─────────────────────────────────────────────────────────────────────

class GrammarLoader {
  static final GrammarLoader instance = GrammarLoader._();
  GrammarLoader._();

  /// scopeName → grammar
  final Map<String, TmGrammar> _grammars = {};

  /// languageId → grammar
  final Map<String, TmGrammar> _byLanguage = {};

  /// file extension → languageId
  final Map<String, String> _extToLanguage = {};

  final List<LanguageContribution> _languages = [];

  Map<String, TmGrammar> get allGrammars => Map.unmodifiable(_grammars);

  TmGrammar? grammarForLanguage(String languageId) => _byLanguage[languageId];
  TmGrammar? grammarForScope(String scopeName) => _grammars[scopeName];

  String? languageIdForExtension(String fileExt) {
    final ext = fileExt.startsWith('.') ? fileExt : '.$fileExt';
    return _extToLanguage[ext.toLowerCase()];
  }

  List<LanguageContribution> get registeredLanguages =>
      List.unmodifiable(_languages);

  // ── Loading ─────────────────────────────────────────────────────────────────

  Future<void> loadAll() async {
    await ExtensionRegistry.instance.load();
    for (final ext in ExtensionRegistry.instance.all) {
      await loadFromExtension(ext);
    }
  }

  Future<void> loadFromExtension(InstalledExtension ext) async {
    final contributes = ext.manifest.raw['contributes'] as Map<String, dynamic>?;
    if (contributes == null) return;

    // Load language contributions
    final langs = contributes['languages'] as List?;
    if (langs != null) {
      for (final lang in langs) {
        if (lang is! Map<String, dynamic>) continue;
        final id = lang['id'] as String? ?? '';
        if (id.isEmpty) continue;

        final exts = (lang['extensions'] as List? ?? [])
            .map((e) => e.toString().toLowerCase())
            .toList();
        final aliases = (lang['aliases'] as List? ?? [])
            .map((e) => e.toString())
            .toList();

        _languages.add(LanguageContribution(
          id: id,
          extensions: exts,
          aliases: aliases,
          firstLine: lang['firstLine'] as String?,
          extensionId: ext.manifest.id,
        ));

        for (final fileExt in exts) {
          _extToLanguage[fileExt] = id;
        }
      }
    }

    // Load grammar contributions
    final grammars = contributes['grammars'] as List?;
    if (grammars == null) return;

    for (final entry in grammars) {
      if (entry is! Map<String, dynamic>) continue;
      final path = entry['path'] as String?;
      final scopeName = entry['scopeName'] as String?;
      final language = entry['language'] as String?;
      if (path == null || scopeName == null) continue;

      final filePath = p.join(ext.installPath, path.replaceFirst('./', ''));
      final grammar = await _loadGrammarFile(
        filePath,
        scopeName: scopeName,
        languageId: language ?? '',
        extensionId: ext.manifest.id,
      );
      if (grammar != null) {
        _grammars[scopeName] = grammar;
        if (language != null) {
          _byLanguage[language] = grammar;
        }
      }
    }
  }

  Future<TmGrammar?> _loadGrammarFile(
    String filePath, {
    required String scopeName,
    required String languageId,
    required String extensionId,
  }) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;

      final raw = await file.readAsString();
      Map<String, dynamic> json;

      if (filePath.endsWith('.json') || filePath.endsWith('.tmLanguage.json')) {
        // Strip comments
        final cleaned = raw.replaceAll(RegExp(r'//[^\n]*'), '');
        json = jsonDecode(cleaned) as Map<String, dynamic>;
      } else {
        // Other formats (plist XML) — skip for now
        debugPrint('[GrammarLoader] Non-JSON grammar skipped: $filePath');
        return null;
      }

      return TmGrammar(
        scopeName: scopeName,
        languageId: languageId,
        filePath: filePath,
        extensionId: extensionId,
        raw: json,
      );
    } catch (e) {
      debugPrint('[GrammarLoader] Failed to load $filePath: $e');
      return null;
    }
  }

  void unloadExtension(String extensionId) {
    _grammars.removeWhere((_, g) => g.extensionId == extensionId);
    _byLanguage.removeWhere((_, g) => g.extensionId == extensionId);
    _languages.removeWhere((l) => l.extensionId == extensionId);
    // Rebuild ext-to-language map
    _extToLanguage.clear();
    for (final lang in _languages) {
      for (final ext in lang.extensions) {
        _extToLanguage[ext] = lang.id;
      }
    }
  }
}
