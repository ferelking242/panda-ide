/// Bridge Flutter pour vscode.workspace.fs — FileSystem API — Phase 3.
///
/// Implémente l'interface vscode.FileSystemProvider côté Flutter pour que
/// les extensions puissent lire/écrire/déplacer/supprimer des fichiers via
/// des apiCall IPC sans accès direct au FS Android.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

// ── FileStat model ────────────────────────────────────────────────────────

enum FileType { unknown, file, directory, symbolicLink }

class FileStat {
  final int mtime;
  final int ctime;
  final int size;
  final FileType type;

  const FileStat({
    required this.mtime,
    required this.ctime,
    required this.size,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'mtime': mtime,
    'ctime': ctime,
    'size': size,
    'type': type.index,
  };
}

// ── FsBridge ─────────────────────────────────────────────────────────────

class FsBridge {
  static final FsBridge instance = FsBridge._();
  FsBridge._();

  // ── stat ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> stat(String fsPath) async {
    final entity = FileSystemEntity.typeSync(fsPath);
    switch (entity) {
      case FileSystemEntityType.file:
        final f    = File(fsPath);
        final stat = await f.stat();
        return FileStat(
          mtime: stat.modified.millisecondsSinceEpoch,
          ctime: stat.changed.millisecondsSinceEpoch,
          size:  stat.size,
          type:  FileType.file,
        ).toJson();

      case FileSystemEntityType.directory:
        final d    = Directory(fsPath);
        final stat = await d.stat();
        return FileStat(
          mtime: stat.modified.millisecondsSinceEpoch,
          ctime: stat.changed.millisecondsSinceEpoch,
          size:  0,
          type:  FileType.directory,
        ).toJson();

      case FileSystemEntityType.link:
        return FileStat(
          mtime: 0, ctime: 0, size: 0, type: FileType.symbolicLink,
        ).toJson();

      default:
        throw FileSystemException('File not found', fsPath);
    }
  }

  // ── readDirectory ─────────────────────────────────────────────────────────

  Future<List<List<dynamic>>> readDirectory(String fsPath) async {
    final dir = Directory(fsPath);
    if (!dir.existsSync()) {
      throw FileSystemException('Directory not found', fsPath);
    }

    final entries = <List<dynamic>>[];
    await for (final entity in dir.list(recursive: false)) {
      final type = entity is Directory
          ? FileType.directory
          : entity is Link
              ? FileType.symbolicLink
              : FileType.file;
      entries.add([p.basename(entity.path), type.index]);
    }
    return entries;
  }

  // ── createDirectory ───────────────────────────────────────────────────────

  Future<void> createDirectory(String fsPath) async {
    await Directory(fsPath).create(recursive: true);
  }

  // ── readFile ──────────────────────────────────────────────────────────────

  Future<List<int>> readFile(String fsPath) async {
    final file = File(fsPath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', fsPath);
    }
    return file.readAsBytes();
  }

  // ── writeFile ─────────────────────────────────────────────────────────────

  Future<void> writeFile(
    String fsPath,
    List<int> content, {
    bool create = true,
    bool overwrite = true,
  }) async {
    final file = File(fsPath);
    final exists = file.existsSync();

    if (!exists && !create) {
      throw FileSystemException('File does not exist', fsPath);
    }
    if (exists && !overwrite) {
      throw FileSystemException('File already exists', fsPath);
    }

    await file.parent.create(recursive: true);
    await file.writeAsBytes(Uint8List.fromList(content));
  }

  // ── writeFileText (helper) ────────────────────────────────────────────────

  Future<void> writeFileText(
    String fsPath,
    String content, {
    bool create = true,
    bool overwrite = true,
  }) async {
    await writeFile(fsPath, content.codeUnits, create: create, overwrite: overwrite);
  }

  // ── delete ────────────────────────────────────────────────────────────────

  Future<void> delete(String fsPath, {bool recursive = false}) async {
    final type = FileSystemEntity.typeSync(fsPath);
    switch (type) {
      case FileSystemEntityType.file:
        await File(fsPath).delete();
      case FileSystemEntityType.directory:
        await Directory(fsPath).delete(recursive: recursive);
      case FileSystemEntityType.link:
        await Link(fsPath).delete();
      default:
        throw FileSystemException('Not found', fsPath);
    }
  }

  // ── rename ────────────────────────────────────────────────────────────────

  Future<void> rename(String oldPath, String newPath, {bool overwrite = true}) async {
    if (!overwrite && File(newPath).existsSync()) {
      throw FileSystemException('Target already exists', newPath);
    }
    final type = FileSystemEntity.typeSync(oldPath);
    switch (type) {
      case FileSystemEntityType.file:
        await File(oldPath).rename(newPath);
      case FileSystemEntityType.directory:
        await Directory(oldPath).rename(newPath);
      default:
        throw FileSystemException('Not found', oldPath);
    }
  }

  // ── copy ──────────────────────────────────────────────────────────────────

  Future<void> copy(String source, String dest, {bool overwrite = true}) async {
    if (!overwrite && File(dest).existsSync()) {
      throw FileSystemException('Target already exists', dest);
    }
    final type = FileSystemEntity.typeSync(source);
    if (type == FileSystemEntityType.file) {
      await Directory(p.dirname(dest)).create(recursive: true);
      await File(source).copy(dest);
    } else if (type == FileSystemEntityType.directory) {
      await _copyDirectory(Directory(source), Directory(dest));
    } else {
      throw FileSystemException('Not found', source);
    }
  }

  Future<void> _copyDirectory(Directory src, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      final destPath = p.join(dest.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(destPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      }
    }
  }

  // ── IPC dispatcher ────────────────────────────────────────────────────────

  Future<dynamic> dispatch(String method, List<dynamic> args) async {
    String resolvePath(dynamic uriArg) {
      if (uriArg is Map<String, dynamic>) {
        return uriArg['fsPath'] as String? ?? uriArg['path'] as String? ?? '';
      }
      return uriArg.toString();
    }

    switch (method) {
      case 'fs.stat':
        return stat(resolvePath(args[0]));

      case 'fs.readDirectory':
        return readDirectory(resolvePath(args[0]));

      case 'fs.createDirectory':
        return createDirectory(resolvePath(args[0]));

      case 'fs.readFile':
        final bytes = await readFile(resolvePath(args[0]));
        // Retourne en base64 pour le transport JSON
        return bytes;

      case 'fs.writeFile':
        final path    = resolvePath(args[0]);
        final content = args[1];
        List<int> bytes;
        if (content is List) {
          bytes = content.cast<int>();
        } else if (content is String) {
          bytes = content.codeUnits;
        } else {
          bytes = [];
        }
        final opts = args.length > 2 ? args[2] as Map<String, dynamic>? : null;
        await writeFile(
          path, bytes,
          create:    opts?['create']    as bool? ?? true,
          overwrite: opts?['overwrite'] as bool? ?? true,
        );
        return null;

      case 'fs.delete':
        final opts = args.length > 1 ? args[1] as Map<String, dynamic>? : null;
        await delete(resolvePath(args[0]),
            recursive: opts?['recursive'] as bool? ?? false);
        return null;

      case 'fs.rename':
        final opts = args.length > 2 ? args[2] as Map<String, dynamic>? : null;
        await rename(resolvePath(args[0]), resolvePath(args[1]),
            overwrite: opts?['overwrite'] as bool? ?? true);
        return null;

      case 'fs.copy':
        final opts = args.length > 2 ? args[2] as Map<String, dynamic>? : null;
        await copy(resolvePath(args[0]), resolvePath(args[1]),
            overwrite: opts?['overwrite'] as bool? ?? true);
        return null;

      default:
        throw UnsupportedError('FsBridge: unknown method $method');
    }
  }
}
