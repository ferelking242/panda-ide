import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

enum PandaScheme { file, memory, github, saf }

class PandaUri {
  final PandaScheme scheme;
  final String path;
  final String authority;

  PandaUri({
    required this.scheme,
    required this.path,
    this.authority = '',
  });

  factory PandaUri.parse(String uriString) {
    final uri = Uri.parse(uriString);
    PandaScheme scheme = PandaScheme.file;
    if (uri.scheme == 'memory') {
      scheme = PandaScheme.memory;
    } else if (uri.scheme == 'github') {
      scheme = PandaScheme.github;
    } else if (uri.scheme == 'saf') {
      scheme = PandaScheme.saf;
    }
    return PandaUri(
      scheme: scheme,
      path: uri.path,
      authority: uri.authority,
    );
  }

  String toUriString() {
    final schemeStr = scheme.name;
    if (authority.isNotEmpty) {
      return '$schemeStr://$authority$path';
    }
    return '$schemeStr://$path';
  }

  @override
  String toString() => toUriString();
}

class PandaFileStat {
  final bool isDirectory;
  final int size;
  final DateTime modifiedTime;

  PandaFileStat({
    required this.isDirectory,
    required this.size,
    required this.modifiedTime,
  });
}

class PandaFileSystemProvider {
  static final PandaFileSystemProvider _instance = PandaFileSystemProvider._internal();
  factory PandaFileSystemProvider() => _instance;
  PandaFileSystemProvider._internal();

  final Map<String, String> _virtualMemoryFS = {};
  final Map<String, PandaFileStat> _virtualMemoryStats = {};

  Future<String> readAsString(PandaUri uri) async {
    if (uri.scheme == PandaScheme.memory || kIsWeb) {
      return _virtualMemoryFS[uri.path] ?? '';
    }
    try {
      final file = File(uri.path);
      return await file.readAsString();
    } catch (e) {
      return _virtualMemoryFS[uri.path] ?? '';
    }
  }

  Future<void> writeAsString(PandaUri uri, String content) async {
    _virtualMemoryFS[uri.path] = content;
    _virtualMemoryStats[uri.path] = PandaFileStat(
      isDirectory: false,
      size: utf8.encode(content).length,
      modifiedTime: DateTime.now(),
    );

    if (uri.scheme == PandaScheme.file && !kIsWeb) {
      try {
        final file = File(uri.path);
        await file.parent.create(recursive: true);
        await file.writeAsString(content);
      } catch (_) {}
    }
  }

  Future<bool> exists(PandaUri uri) async {
    if (_virtualMemoryFS.containsKey(uri.path)) return true;
    if (uri.scheme == PandaScheme.file && !kIsWeb) {
      try {
        return await File(uri.path).exists() || await Directory(uri.path).exists();
      } catch (_) {}
    }
    return false;
  }

  Future<List<PandaUri>> listDirectory(PandaUri uri) async {
    final List<PandaUri> result = [];
    if (uri.scheme == PandaScheme.file && !kIsWeb) {
      try {
        final dir = Directory(uri.path);
        if (await dir.exists()) {
          final entities = await dir.list().toList();
          for (var entity in entities) {
            result.add(PandaUri(
              scheme: PandaScheme.file,
              path: entity.path,
            ));
          }
        }
      } catch (_) {}
    }

    // Include virtual memory entries under this path
    final prefix = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    for (var key in _virtualMemoryFS.keys) {
      if (key.startsWith(prefix)) {
        final relative = key.substring(prefix.length);
        final firstPart = relative.split('/').first;
        final childPath = '$prefix$firstPart';
        final childUri = PandaUri(scheme: PandaScheme.memory, path: childPath);
        if (!result.any((u) => u.path == childPath)) {
          result.add(childUri);
        }
      }
    }
    return result;
  }

  Future<void> delete(PandaUri uri) async {
    _virtualMemoryFS.remove(uri.path);
    _virtualMemoryStats.remove(uri.path);
    if (uri.scheme == PandaScheme.file && !kIsWeb) {
      try {
        final file = File(uri.path);
        if (await file.exists()) {
          await file.delete(recursive: true);
        }
      } catch (_) {}
    }
  }
}
