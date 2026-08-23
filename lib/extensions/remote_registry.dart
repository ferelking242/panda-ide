/// Registre distant des extensions — ferelking242/panda-extensions.
///
/// Le marketplace ne lit QU'UN SEUL fichier (`index.json`) pour tout
/// afficher. L'installation copie les fichiers de l'extension dans le
/// dossier `extensions/` de l'app au RUNTIME :
///
///   GET /repos/…/contents/extensions/<id>?ref=main  → liste récursive
///   GET raw.githubusercontent.com/…                 → chaque fichier
///   → $appDir/extensions/<id>/                      → PluginManager.loadAll()
///
/// Désinstaller = supprimer le dossier + unload. Aucun rebuild d'APK.
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
  final String path; // ex: extensions/dev.panda.device
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

/// Le registre complet parsé.
class RegistryIndex {
  final List<RegistryEntry> extensions;
  final DateTime updatedAt;
  RegistryIndex({required this.extensions, required this.updatedAt});
}

/// Service de registre + installation runtime.
class RemoteExtensionRegistry {
  RemoteExtensionRegistry._();
  static final RemoteExtensionRegistry instance =
      RemoteExtensionRegistry._();

  static const repoRawBase =
      'https://raw.githubusercontent.com/ferelking242/panda-extensions/main';
  static const repoApiBase =
      'https://api.github.com/repos/ferelking242/panda-extensions/contents';
  static const indexUrl = '$repoRawBase/index.json';

  /// Racine où sont installées les extensions (à injecter par l'app :
  /// `$appDir/extensions`).
  String installRoot = 'extensions';

  RegistryIndex? _cache;
  DateTime _cacheTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const cacheTtl = Duration(minutes: 30);

  // ── Lecture du catalogue ──────────────────────────────────────────

  /// Récupère l'index (cache mémoire 30 min). [force] ignore le cache.
  Future<RegistryIndex> fetchIndex({bool force = false}) async {
    if (!force &&
        _cache != null &&
        DateTime.now().difference(_cacheTime) < cacheTtl) {
      return _cache!;
    }

    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(indexUrl));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('index.json HTTP ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      final doc = jsonDecode(body) as Map<String, dynamic>;
      final list = (doc['extensions'] as List? ?? [])
          .map((e) => RegistryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _cache = RegistryIndex(
        extensions: list,
        updatedAt: DateTime.tryParse(doc['updatedAt'] ?? '') ?? DateTime.now(),
      );
      _cacheTime = DateTime.now();
      return _cache!;
    } finally {
      client.close();
    }
  }

  // ── Installation runtime ─────────────────────────────────────────

  /// Installe une extension depuis le registre.
  ///
  /// 1. Liste tous les fichiers du dossier via l'API contents (récursif)
  /// 2. Télécharge chaque fichier en raw
  /// 3. Écrit dans `$installRoot/<id>/`
  ///
  /// Retourne le chemin installé (prêt pour PluginManager.loadAll).
  Future<String> install(RegistryEntry entry,
      {void Function(int received, int total, String file)? onProgress}) async {
    final targetDir = p.join(installRoot, entry.id);
    await Directory(targetDir).create(recursive: true);

    // 1. Liste récursive via API GitHub
    final files = <_RemoteFile>[];
    await _listRecursive(entry.path, files);
    if (files.isEmpty) {
      throw StateError('Aucun fichier trouvé pour ${entry.id}');
    }

    // 2+3. Téléchargement + copie
    var done = 0;
    for (final f in files) {
      onProgress?.call(done, files.length, f.relPath);
      final relUnderExt =
          f.relPath.substring(entry.path.length + 1); // strip "extensions/<id>/"
      final localPath = p.join(targetDir, relUnderExt);
      await File(localPath).parent.create(recursive: true);
      final bytes = await _download(f.rawUrl);
      await File(localPath).writeAsBytes(bytes);
      done++;
    }
    onProgress?.call(files.length, files.length, '');

    return targetDir;
  }

  /// Désinstalle : unload + suppression du dossier. Sans rebuild.
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

  /// IDs des extensions installées localement.
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

  Future<void> _listRecursive(String apiPath, List<_RemoteFile> out,
      {int depth = 0}) async {
    if (depth > 6) return; // garde-fou
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('$repoApiBase/$apiPath?ref=main'));
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close();
      if (res.statusCode != 200) return;
      final body = await res.transform(utf8.decoder).join();
      final items = jsonDecode(body) as List;
      for (final item in items) {
        final m = item as Map<String, dynamic>;
        final type = m['type'];
        final path = m['path'] as String;
        if (type == 'file') {
          out.add(_RemoteFile(
            relPath: path,
            rawUrl: '$repoRawBase/$path',
            size: (m['size'] as num?)?.toInt() ?? 0,
          ));
        } else if (type == 'dir') {
          await _listRecursive(path, out, depth: depth + 1);
        }
      }
    } finally {
      client.close();
    }
  }

  Future<List<int>> _download(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('download $url → ${res.statusCode}');
      }
      final builder = BytesBuilder();
      await for (final chunk in res) {
        builder.add(chunk);
      }
      return builder.takeBytes();
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
