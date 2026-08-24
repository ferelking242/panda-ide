/// Central file utilities for Panda IDE.
/// Git operations, models, and other utilities have been extracted
/// to their own files for better architecture.
///
/// This file re-exports everything for backward compatibility.

// ── File utilities (core) ──
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:code_forge/code_forge.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:path_provider/path_provider.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:panda/utils/themes.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../terminal/terminal.dart';
import '../utils/constants.dart';
import '../utils/languages.dart';

const Set<String> supportedImageExtensions = {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
  '.wbmp',
  '.ico',
  '.tif',
  '.tiff',
  '.heic',
  '.heif',
  '.avif',
};

const Set<String> supportedSvgExtensions = {
  '.svg',
  '.svgz',
};

bool isImageFilePath(String filePath) {
  return supportedImageExtensions.contains(
    path.extension(filePath).toLowerCase(),
  );
}

bool isPdfFilePath(String filePath) {
  return path.extension(filePath).toLowerCase() == '.pdf';
}

bool isSvgFilePath(String filePath) {
  return supportedSvgExtensions.contains(
    path.extension(filePath).toLowerCase(),
  );
}

bool isPreviewFilePath(String filePath) {
  return
    isImageFilePath(filePath) ||
    isSvgFilePath(filePath) ||
    isPdfFilePath(filePath);
}

const String _legacyProjectDir = '/data/data/com.panda.ide/Roxum/Projects';
const String _legacyTemplateDir = '/data/data/com.panda.ide/Roxum/Templates';
const String _legacyFilesDir = '/data/data/com.panda.ide/Roxum/Files';
const String sharedStorageMigrationNoticeKey = 'panda_shared_storage_migration_notice';
const String sharedStorageMigrationDoneKey = 'panda_shared_storage_import_done_v1';

Future<void> _copyEntityRecursive(FileSystemEntity source, Directory targetRoot) async {
  if (source is Directory) {
    final target = Directory(path.join(targetRoot.path, path.basename(source.path)));
    if (!target.existsSync()) {
      await target.create(recursive: true);
    }
    await for (final child in source.list(recursive: false, followLinks: false)) {
      await _copyEntityRecursive(child, target);
    }
    return;
  }

  if (source is File) {
    final target = File(path.join(targetRoot.path, path.basename(source.path)));
    await target.parent.create(recursive: true);
    await source.copy(target.path);
  }
}

Future<bool> _copyDirectoryRoot(String sourcePath, String targetPath) async {
  final source = Directory(sourcePath);
  if (!await source.exists()) {
    return false;
  }

  final target = Directory(targetPath);
  if (!await target.exists()) {
    await target.create(recursive: true);
  }

  final entities = await source.list(followLinks: false).toList();
  for (final entity in entities) {
    final destination = path.join(target.path, path.basename(entity.path));
    if (entity is Directory) {
      await Directory(destination).create(recursive: true);
      await for (final child in entity.list(followLinks: false)) {
        await _copyEntityRecursive(child, Directory(destination));
      }
    } else if (entity is File) {
      await File(destination).parent.create(recursive: true);
      await entity.copy(destination);
    }
  }

  return true;
}

Map<String, dynamic>? _normalizeRecentMap(dynamic rawEntry) {
  if (rawEntry is Map && rawEntry['type'] is String && rawEntry['path'] is String) {
    return {
      'type': rawEntry['type'],
      'path': rawEntry['path'],
      'rootDir': rawEntry['rootDir'] ?? rawEntry['path'],
    };
  }

  if (rawEntry is Map && rawEntry.length == 1) {
    final dynamic key = rawEntry.keys.first;
    if (key is String) {
      return {'type': 'file', 'path': key, 'rootDir': rawEntry[key]};
    }
  }

  return null;
}

String _remapLegacyPath(String value) {
  if (value.startsWith(_legacyProjectDir)) {
    return value.replaceFirst(_legacyProjectDir, projectDir);
  }
  if (value.startsWith(_legacyTemplateDir)) {
    return value.replaceFirst(_legacyTemplateDir, templateDir);
  }
  if (value.startsWith(_legacyFilesDir)) {
    return value.replaceFirst(_legacyFilesDir, filesDir);
  }
  return value;
}

Future<void> _remapRecentEntriesToPrivateStorage() async {
  final prefs = await SharedPreferences.getInstance();
  final rawRecent = prefs.getString('recent');
  if (rawRecent == null || rawRecent.trim().isEmpty) {
    return;
  }

  try {
    final decoded = jsonDecode(rawRecent);
    if (decoded is! List) return;

    var changed = false;
    final remapped = <dynamic>[];

    for (final rawEntry in decoded) {
      final normalized = _normalizeRecentMap(rawEntry);
      if (normalized == null) {
        continue;
      }

      final nextPath = _remapLegacyPath(normalized['path'] as String);
      final nextRootDir = _remapLegacyPath(normalized['rootDir'] as String);
      if (nextPath != normalized['path'] || nextRootDir != normalized['rootDir']) {
        changed = true;
      }

      remapped.add({
        'type': normalized['type'],
        'path': nextPath,
        'rootDir': nextRootDir,
      });
    }

    if (changed) {
      await prefs.setString('recent', jsonEncode(remapped));
    }
  } catch (_) {}
}

Future<bool> importPublicProjectsToPrivate() async {
  var migrated = false;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(sharedStorageMigrationDoneKey) ?? false) return false;
  for (final pair in [
    (publicProjectDir, projectDir),
    (publicTemplateDir, templateDir),
    (publicFilesDir, filesDir),
  ]) {
    try {
      migrated = await _copyDirectoryRoot(pair.$1, pair.$2) || migrated;
    } on FileSystemException {
      continue;
    }
  }

  await _remapRecentEntriesToPrivateStorage();
  final publicHasContent = [
    Directory(publicProjectDir),
    Directory(publicTemplateDir),
    Directory(publicFilesDir),
  ].any((directory) => directory.existsSync());
  // Do not consume the one-time import marker while shared storage is still
  // inaccessible on a first launch; the permission screen can retry later.
  if (migrated || publicHasContent) {
    await prefs.setBool(sharedStorageMigrationDoneKey, true);
    if (migrated) await prefs.setBool(sharedStorageMigrationNoticeKey, true);
  }

  return migrated;
}


// ── Re-exports for backward compatibility ──
export 'git/git_operations.dart';
export 'git/git_diff.dart';
export 'string_utils.dart';
export 'extractors.dart';
export 'models/editor_models.dart';
export 'editors/edit_hunks.dart';
export 'ssh/ssh_utils.dart';
export 'search/search_index.dart';
export 'editors/editor_theme.dart';
