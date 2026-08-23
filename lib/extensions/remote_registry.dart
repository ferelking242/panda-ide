/// Registre distant des extensions — ferelking242/panda-extensions.
///
/// Résilience réseau (mobile proot, connexions instables) :
///   - timeout court sur chaque requête (jamais de spinner infini)
///   - fallback CDN jsdelivr si raw.githubusercontent est lent/bloqué
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Une entrée du catalogue (index.json).
class RegistryEntry {
  final String id;
  final String name;
  final String version;
  final String? author;
  final String description;
  final String? iconUrl;
  final List<String> permissions;
  final List<String> tags;
  final String category;
  final String path;
  final bool featured;

  const RegistryEntry({
    required this.id,
    required this.name,
    required this.version,
    this.author,
    this.description = '',
    this.iconUrl,
    this.permissions = const [],
    this.tags = const [],
    this.category = 'tools',
    required this.path,
    this.featured = false,
  });

  factory RegistryEntry.fromJson(Map<String, dynamic> j) => RegistryEntry(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        version: j['version'] ?? '0.0.0',
        author: j['author'],
        description: j['description'] ?? '',
        iconUrl: j['icon'] is Map ? j['icon']['src'] as String? : null,
        permissions:
            (j['permissions'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        category: j['category'] ?? 'tools',
        path: j['path'] ?? '',
        featured: j['featured'] == true,
      );
}

class RegistryIndex {
  final List<RegistryEntry> extensions;
  final DateTime updatedAt;
  RegistryIndex({required this.extensions, required this.updatedAt});
}

class RemoteExtensionRegistry {
  RemoteExtensionRegistry._();
  static final RemoteExtensionRegistry instance =
      RemoteExtensionRegistry._();

  static const repoRawBase =
      'https://raw.githubusercontent.com/ferelking242/panda-extensions/main';
  static const repoApiBase =
      'https://api.github.com/repos/ferelking242/panda-extensions/contents';
  /// Fallback CDN : sert les fichiers du repo même si GitHub raw est lent.
  static const cdnBase =
      'https://cdn.jsdelivr.net/gh/ferelking242/panda-extensions@main';
  static const indexUrl = '$repoRawBase/index.json';
  static const cdnIndexUrl = '$cdnBase/index.json';

  static const _timeout = Duration(seconds: 12);

  String installRoot = 'extensions';

  RegistryIndex? _cache;
  DateTime _cacheTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const cacheTtl = Duration(minutes: 30);

  // ── Lecture du catalogue ──────────────────────────────────────────

  Future<RegistryIndex> fetchIndex({bool force = false}) async {
    if (!force &&
        _cache != null &&
        DateTime.now().difference(_cacheTime) < cacheTtl) {
      return _cache!;
    }

    // raw d'abord, CDN en secours — avec timeout, JAMAIS de blocage infini
    Object? lastErr;
    for (final url in [indexUrl, cdnIndexUrl]) {
      try {
        final body = await _getString(url);
        final doc = jsonDecode(body) as Map<String, dynamic>;
        var list = <RegistryEntry>[
          for (final e in (doc['extensions'] as List? ?? []))
            RegistryEntry.fromJson(e as Map<String, dynamic>),
        ];
        // Shards (registres volumineux) : paginer le reste
        final shards = doc['shards'];
        if (shards is Map && (shards['pages'] as List? ?? []).isNotEmpty) {
          for (final page in (shards['pages'] as List)) {
            final shardUrl = (page as Map)['url'] as String;
            final cdnShard =
                shardUrl.replaceFirst(repoRawBase, cdnBase);
            try {
              final sBody = await _getString(shardUrl)
                  .timeout(_timeout, onTimeout: () => throw TimeoutException('t'))
                  .catchError((_) async => await _getString(cdnShard));
              final sDoc = jsonDecode(sBody) as Map<String, dynamic>;
              list.addAll([
                for (final e in (sDoc['extensions'] as List? ?? []))
                  RegistryEntry.fromJson(e as Map<String, dynamic>)
              ]);
            } catch (_) {}
          }
        }
        // Petit registre tout-inline
        if (doc['inline'] is List) {
          list.addAll([
            for (final e in (doc['inline'] as List))
              RegistryEntry.fromJson(e as Map<String, dynamic>)
          ]);
        }

        _cache = RegistryIndex(
          extensions: list,
          updatedAt:
              DateTime.tryParse(doc['updatedAt'] ?? '') ?? DateTime.now(),
        );
        _cacheTime = DateTime.now();
        return _cache!;
      } catch (e) {
        lastErr = e;
      }
    }
    throw StateError(
        'Registre inaccessible (raw + CDN). Vérifie la connexion.\n$lastErr');
  }

  // ── Installation runtime ─────────────────────────────────────────

  Future<String> install(RegistryEntry entry,
      {void Function(int received, int total, String file)? onProgress}) async {
    final targetDir = p.join(installRoot, entry.id);
    await Directory(targetDir).create(recursive: true);

    final files = <_RemoteFile>[];
    await _listRecursive(entry.path, files);
    if (files.isEmpty) {
      throw StateError('Aucun fichier trouvé pour ${entry.id}');
    }

    var done = 0;
    for (final f in files) {
      onProgress?.call(done, files.length, f.relPath);
      final relUnderExt = f.relPath.substring(entry.path.length + 1);
      final localPath = p.join(targetDir, relUnderExt);
      await File(localPath).parent.create(recursive: true);
      final bytes = await _download(f.rawUrl);
      await File(localPath).writeAsBytes(bytes);
      done++;
    }
    onProgress?.call(files.length, files.length, '');
    return targetDir;
  }

  Future<bool> uninstall(String extensionId) async {
    final dir = Directory(p.join(installRoot, extensionId));
    if (!await dir.exists()) return false;
    try {
      await dir.delete(recursive: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<List<String>> listInstalled() async {
    final root = Directory(installRoot);
    if (!await root.exists()) return [];
    final ids = <String>[];
    await for (final e in root.list()) {
      if (e is Directory &&
          await File(p.join(e.path, 'panda.yaml')).exists()) {
        ids.add(p.basename(e.path));
      }
    }
    return ids;
  }

  Future<bool> isInstalled(String id) =>
      File(p.join(installRoot, id, 'panda.yaml')).exists();

  // ── HTTP helpers ─────────────────────────────────────────────────

  Future<String> _getString(String url) async {
    final client = HttpClient()
      ..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        throw HttpException('$url → ${res.statusCode}');
      }
      return await res.transform(utf8.decoder).join().timeout(_timeout);
    } finally {
      client.close();
    }
  }

  Future<void> _listRecursive(String apiPath, List<_RemoteFile> out,
      {int depth = 0}) async {
    if (depth > 6) return;
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client
          .getUrl(Uri.parse('$repoApiBase/$apiPath?ref=main'))
          .timeout(_timeout);
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) return;
      final body =
          await res.transform(utf8.decoder).join().timeout(_timeout);
      final items = jsonDecode(body) as List;
      for (final item in items) {
        final m = item as Map<String, dynamic>;
        if (m['type'] == 'file') {
          out.add(_RemoteFile(
            relPath: m['path'] as String,
            rawUrl: m['download_url'] as String? ??
                '$repoRawBase/${m['path']}',
            size: (m['size'] as num?)?.toInt() ?? 0,
          ));
        } else if (m['type'] == 'dir') {
          await _listRecursive(m['path'] as String, out, depth: depth + 1);
        }
      }
    } finally {
      client.close();
    }
  }

  /// Téléchargement fichier avec fallback CDN automatique.
  Future<List<int>> _download(String url) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      for (final u in [url, url.replaceFirst(repoRawBase, cdnBase)]) {
        try {
          final req = await client.getUrl(Uri.parse(u)).timeout(_timeout);
          final res = await req.close().timeout(_timeout);
          if (res.statusCode != 200) continue;
          final builder = BytesBuilder();
          await for (final chunk in res) {
            builder.add(chunk);
          }
          return builder.takeBytes();
        } catch (_) {
          continue; // essai suivant (CDN)
        }
      }
      throw HttpException('download $url échoué (raw + CDN)');
    } finally {
      client.close();
    }
  }
}

class _RemoteFile {
  final String relPath;
  final String rawUrl;
  final int size;
  const _RemoteFile({
    required this.relPath,
    required this.rawUrl,
    required this.size,
  });
}
