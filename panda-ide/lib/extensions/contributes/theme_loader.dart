/// Chargeur de thèmes couleur VSCode — Phase 13.
///
/// Charge les fichiers .json de thèmes couleur (color themes) depuis une
/// extension installée et les applique à l'IDE.
///
/// Format supporté :
///   contributes.themes[].path → chemin vers le fichier JSON
///   Le fichier JSON est au format VSCode color theme (tokenColors, colors, etc.)
///
/// Référence : https://code.visualstudio.com/api/extension-guides/color-theme
library;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../extension_registry.dart';





// ── Modèles ────────────────────────────────────────────────────────────────

class VsColorTheme {
  final String name;
  final String type;  // 'dark' | 'light' | 'hc'
  final Map<String, String> colors;           // workbench colors
  final List<TokenColor> tokenColors;         // syntax highlighting
  final String extensionId;
  final String sourcePath;

  const VsColorTheme({
    required this.name,
    required this.type,
    required this.colors,
    required this.tokenColors,
    required this.extensionId,
    required this.sourcePath,
  });

  bool get isDark => type == 'dark' || type == 'hc';

  /// Retourne la couleur de fond de l'éditeur.
  Color get editorBackground {
    final hex = colors['editor.background'] ??
        colors['terminal.background'] ??
        (isDark ? '#1E1E1E' : '#FFFFFF');
    return _hexColor(hex);
  }

  /// Retourne la couleur de premier plan de l'éditeur.
  Color get editorForeground {
    final hex = colors['editor.foreground'] ?? (isDark ? '#D4D4D4' : '#000000');
    return _hexColor(hex);
  }

  /// Crée un ThemeData Flutter approximant le thème VSCode.
  ThemeData toFlutterTheme() {
    final bg = editorBackground;
    final fg = editorForeground;
    final brightness = isDark ? Brightness.dark : Brightness.light;

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: _hexColor(colors['focusBorder'] ??
            (isDark ? '#007FD4' : '#0066B8')),
        onPrimary: Colors.white,
        secondary: _hexColor(colors['button.background'] ??
            (isDark ? '#0E639C' : '#007ACC')),
        onSecondary: Colors.white,
        surface: _hexColor(colors['sideBar.background'] ??
            (isDark ? '#252526' : '#F3F3F3')),
        onSurface: fg,
        error: Colors.red,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: _hexColor(colors['titleBar.activeBackground'] ??
            (isDark ? '#3C3C3C' : '#DDDDDD')),
        foregroundColor: _hexColor(colors['titleBar.activeForeground'] ??
            (isDark ? '#CCCCCC' : '#333333')),
        elevation: 0,
      ),
    );
  }

  static Color _hexColor(String hex) {
    try {
      final h = hex.trim().replaceFirst('#', '');
      if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
      if (h.length == 8) return Color(int.parse(h, radix: 16));
    } catch (_) {}
    return Colors.transparent;
  }
}

class TokenColor {
  final String? name;
  final List<String> scope;
  final Map<String, String> settings;

  const TokenColor({
    this.name,
    required this.scope,
    required this.settings,
  });
}

// ── Loader ─────────────────────────────────────────────────────────────────────

class ThemeLoader {
  static final ThemeLoader instance = ThemeLoader._();
  ThemeLoader._();

  final Map<String, VsColorTheme> _loadedThemes = {};
  VsColorTheme? _activeTheme;

  Map<String, VsColorTheme> get availableThemes => Map.unmodifiable(_loadedThemes);
  VsColorTheme? get activeTheme => _activeTheme;

  // ── Loading ─────────────────────────────────────────────────────────────────

  /// Charge tous les thèmes de toutes les extensions installées.
  Future<void> loadAll() async {
    await ExtensionRegistry.instance.load();
    for (final ext in ExtensionRegistry.instance.all) {
      await loadFromExtension(ext);
    }
  }

  /// Charge les thèmes d'une extension donnée.
  Future<void> loadFromExtension(InstalledExtension ext) async {
    final themes = ext.manifest.raw['contributes']?['themes'];
    if (themes is! List) return;

    for (final themeEntry in themes) {
      if (themeEntry is! Map<String, dynamic>) continue;
      final path = themeEntry['path'] as String?;
      if (path == null) continue;

      final themePath = p.join(ext.installPath, path.replaceFirst('./', ''));
      final theme = await _loadThemeFile(
        themePath,
        label: themeEntry['label'] as String? ?? p.basenameWithoutExtension(themePath),
        uiTheme: themeEntry['uiTheme'] as String? ?? 'vs-dark',
        extensionId: ext.manifest.id,
      );
      if (theme != null) {
        _loadedThemes['${ext.manifest.id}/${theme.name}'] = theme;
      }
    }
  }

  Future<VsColorTheme?> _loadThemeFile(
    String filePath, {
    required String label,
    required String uiTheme,
    required String extensionId,
  }) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;

      final raw = await file.readAsString();
      // Strip JSON comments (VSCode themes often have // comments)
      final cleaned = raw.replaceAll(RegExp(r'//[^\n]*'), '');
      final json = jsonDecode(cleaned) as Map<String, dynamic>;

      final type = uiTheme == 'vs' ? 'light' : uiTheme == 'hc-black' ? 'hc' : 'dark';

      final colors = (json['colors'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString()));

      final rawTokenColors = json['tokenColors'] as List? ?? [];
      final tokenColors = <TokenColor>[];
      for (final tc in rawTokenColors) {
        if (tc is! Map<String, dynamic>) continue;
        final scope = tc['scope'];
        final scopes = scope is String
            ? [scope]
            : (scope as List? ?? []).map((s) => s.toString()).toList();
        final settings = (tc['settings'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString()));
        tokenColors.add(TokenColor(name: tc['name'] as String?, scope: scopes, settings: settings));
      }

      return VsColorTheme(
        name: label,
        type: type,
        colors: colors,
        tokenColors: tokenColors,
        extensionId: extensionId,
        sourcePath: filePath,
      );
    } catch (e) {
      debugPrint('[ThemeLoader] Failed to load $filePath: $e');
      return null;
    }
  }

  // ── Activation ──────────────────────────────────────────────────────────────

  void setActiveTheme(String themeKey) {
    _activeTheme = _loadedThemes[themeKey];
  }

  void clearActiveTheme() => _activeTheme = null;
}
