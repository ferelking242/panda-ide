/// Chargeur de thèmes d'icônes VSCode — Phase 13.
///
/// Charge les fichiers icon theme (.json) depuis les extensions.
/// Fournit les icônes de fichiers / dossiers à l'arbre de fichiers de l'IDE.
///
/// Format : contributes.iconThemes[].path → fichier JSON
/// Référence : https://code.visualstudio.com/api/extension-guides/file-icon-theme
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../extension_registry.dart';

library;




// ── Modèles ────────────────────────────────────────────────────────────────

class IconDefinition {
  final String iconPath;     // absolute path to the SVG/PNG
  final String? fontCharacter;
  final String? fontColor;
  final String? fontSize;
  final String? fontId;

  const IconDefinition({
    required this.iconPath,
    this.fontCharacter,
    this.fontColor,
    this.fontSize,
    this.fontId,
  });
}

class IconTheme {
  final String name;
  final String extensionId;
  final String sourcePath;    // base dir of the theme JSON

  /// iconDefinitions key → IconDefinition
  final Map<String, IconDefinition> definitions;

  /// file/folder name/extension → definition key
  final Map<String, String> fileNames;
  final Map<String, String> fileExtensions;
  final Map<String, String> folderNames;
  final Map<String, String> folderNamesExpanded;
  final String? file;          // default file icon key
  final String? folder;        // default folder icon key
  final String? folderExpanded;
  final String? rootFolder;
  final String? rootFolderExpanded;

  const IconTheme({
    required this.name,
    required this.extensionId,
    required this.sourcePath,
    required this.definitions,
    this.fileNames = const {},
    this.fileExtensions = const {},
    this.folderNames = const {},
    this.folderNamesExpanded = const {},
    this.file,
    this.folder,
    this.folderExpanded,
    this.rootFolder,
    this.rootFolderExpanded,
  });

  /// Returns the icon path for a given filename, or null for default.
  String? iconPathForFile(String fileName) {
    final lower = fileName.toLowerCase();

    // Exact filename match
    if (fileNames.containsKey(lower)) {
      return definitions[fileNames[lower]]?.iconPath;
    }

    // Extension match
    final ext = _extensionOf(lower);
    if (ext != null && fileExtensions.containsKey(ext)) {
      return definitions[fileExtensions[ext]]?.iconPath;
    }

    // Default file icon
    if (file != null) return definitions[file]?.iconPath;
    return null;
  }

  String? iconPathForFolder(String folderName, {bool expanded = false}) {
    final lower = folderName.toLowerCase();
    final map = expanded ? folderNamesExpanded : folderNames;

    if (map.containsKey(lower)) {
      return definitions[map[lower]]?.iconPath;
    }

    final key = expanded ? folderExpanded : folder;
    if (key != null) return definitions[key]?.iconPath;
    return null;
  }

  static String? _extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return null;
    return filename.substring(dot + 1);
  }
}

// ── Loader ─────────────────────────────────────────────────────────────────────

class IconThemeLoader {
  static final IconThemeLoader instance = IconThemeLoader._();
  IconThemeLoader._();

  final Map<String, IconTheme> _themes = {};
  IconTheme? _activeTheme;

  Map<String, IconTheme> get availableThemes => Map.unmodifiable(_themes);
  IconTheme? get activeTheme => _activeTheme;

  // ── Loading ─────────────────────────────────────────────────────────────────

  Future<void> loadAll() async {
    await ExtensionRegistry.instance.load();
    for (final ext in ExtensionRegistry.instance.all) {
      await loadFromExtension(ext);
    }
  }

  Future<void> loadFromExtension(InstalledExtension ext) async {
    final iconThemes = ext.manifest.raw['contributes']?['iconThemes'];
    if (iconThemes is! List) return;

    for (final entry in iconThemes) {
      if (entry is! Map<String, dynamic>) continue;
      final path = entry['path'] as String?;
      final label = entry['label'] as String? ?? 'Unknown';
      final id = entry['id'] as String? ?? label;
      if (path == null) continue;

      final filePath = p.join(ext.installPath, path.replaceFirst('./', ''));
      final theme = await _loadThemeFile(
        filePath,
        name: label,
        extensionId: ext.manifest.id,
      );
      if (theme != null) {
        _themes['${ext.manifest.id}/$id'] = theme;
      }
    }
  }

  Future<IconTheme?> _loadThemeFile(
    String filePath, {
    required String name,
    required String extensionId,
  }) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;

      final raw = await file.readAsString();
      final cleaned = raw.replaceAll(RegExp(r'//[^\n]*'), '');
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      final baseDir = p.dirname(filePath);

      // Parse icon definitions
      final rawDefs = json['iconDefinitions'] as Map<String, dynamic>? ?? {};
      final definitions = <String, IconDefinition>{};

      rawDefs.forEach((key, value) {
        if (value is! Map<String, dynamic>) return;
        final iconPath = value['iconPath'] as String?;
        if (iconPath == null) return;
        final absPath = p.isAbsolute(iconPath)
            ? iconPath
            : p.join(baseDir, iconPath.replaceFirst('./', ''));
        definitions[key] = IconDefinition(
          iconPath: absPath,
          fontCharacter: value['fontCharacter'] as String?,
          fontColor: value['fontColor'] as String?,
          fontSize: value['fontSize'] as String?,
          fontId: value['fontId'] as String?,
        );
      });

      Map<String, String> _strMap(String key) {
        final m = json[key] as Map<String, dynamic>? ?? {};
        return m.map((k, v) => MapEntry(k.toLowerCase(), v.toString()));
      }

      return IconTheme(
        name: name,
        extensionId: extensionId,
        sourcePath: baseDir,
        definitions: definitions,
        fileNames: _strMap('fileNames'),
        fileExtensions: _strMap('fileExtensions'),
        folderNames: _strMap('folderNames'),
        folderNamesExpanded: _strMap('folderNamesExpanded'),
        file: json['file'] as String?,
        folder: json['folder'] as String?,
        folderExpanded: json['folderExpanded'] as String?,
        rootFolder: json['rootFolder'] as String?,
        rootFolderExpanded: json['rootFolderExpanded'] as String?,
      );
    } catch (e) {
      debugPrint('[IconThemeLoader] Failed to load $filePath: $e');
      return null;
    }
  }

  // ── Activation ──────────────────────────────────────────────────────────────

  void setActiveTheme(String themeKey) {
    _activeTheme = _themes[themeKey];
  }

  void clearActiveTheme() => _activeTheme = null;

  /// Helper to build a Flutter Image widget from an icon path.
  Widget buildFileIcon(String fileName, {double size = 16}) {
    final theme = _activeTheme;
    if (theme == null) return Icon(Icons.insert_drive_file, size: size);

    final iconPath = theme.iconPathForFile(fileName);
    if (iconPath == null) return Icon(Icons.insert_drive_file, size: size);

    return _buildIconWidget(iconPath, size);
  }

  Widget buildFolderIcon(String folderName, {bool expanded = false, double size = 16}) {
    final theme = _activeTheme;
    if (theme == null) {
      return Icon(expanded ? Icons.folder_open : Icons.folder, size: size);
    }

    final iconPath = theme.iconPathForFolder(folderName, expanded: expanded);
    if (iconPath == null) {
      return Icon(expanded ? Icons.folder_open : Icons.folder, size: size);
    }

    return _buildIconWidget(iconPath, size);
  }

  static Widget _buildIconWidget(String iconPath, double size) {
    final file = File(iconPath);
    if (!file.existsSync()) {
      return Icon(Icons.insert_drive_file, size: size);
    }

    if (iconPath.endsWith('.svg')) {
      // flutter_svg would handle this but we don't assume it's imported here.
      // Return a placeholder — the consuming widget can use flutter_svg directly.
      return SizedBox(width: size, height: size);
    }

    return Image.file(file, width: size, height: size, fit: BoxFit.contain);
  }
}
