import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_archive/flutter_archive.dart';

/// GatewayInstaller — télécharge et installe Panda AI Gateway.
///
/// Stratégie :
///   1. Si le répertoire d'installation existe et est valide → skip
///   2. Sinon : télécharger depuis GitHub Releases (panda-ai)
///   3. Fallback : extraire depuis les assets bundled (si disponibles)
///   4. Lancer pip install -r requirements.txt
class GatewayInstaller {
  static const _githubRepo = 'ferelking242/panda-ai';
  static const _versionFile = '.gateway_version';

  /// Retourne le répertoire d'installation (crée si nécessaire).
  static Future<String> getInstallDir() async {
    final base = await getApplicationSupportDirectory();
    return '${base.path}/gateway';
  }

  /// Vérifie si le gateway est déjà installé et valide.
  static Future<bool> isInstalled() async {
    final dir = await getInstallDir();
    final marker = File('$dir/requirements.txt');
    return marker.exists();
  }

  /// Retourne la version installée (tag GitHub ou 'bundled').
  static Future<String> getInstalledVersion() async {
    final dir = await getInstallDir();
    final vFile = File('$dir/$_versionFile');
    if (await vFile.exists()) {
      return (await vFile.readAsString()).trim();
    }
    return 'unknown';
  }

  /// Vérifie si une mise à jour est disponible.
  static Future<String?> checkForUpdate() async {
    try {
      final apiUrl =
          'https://api.github.com/repos/$_githubRepo/releases/latest';
      final resp = await http.get(
        Uri.parse(apiUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;

      final release = json.decode(resp.body) as Map<String, dynamic>;
      final latestTag = release['tag_name'] as String? ?? 'latest';
      final currentVersion = await getInstalledVersion();

      if (latestTag != currentVersion) {
        return latestTag;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Installe le gateway (download + pip install).
  static Future<void> install({
    void Function(String msg)? onProgress,
    bool forceReinstall = false,
  }) async {
    final dir = await getInstallDir();

    void log(String msg) => onProgress?.call(msg);

    if (!forceReinstall && await isInstalled()) {
      log('✓ Gateway déjà installé dans $dir');
      return;
    }

    log('📦 Installation de Panda AI Gateway…');
    await Directory(dir).create(recursive: true);

    // 1. Tenter le téléchargement GitHub
    bool downloaded = false;
    String? tag;
    try {
      final result = await _downloadFromGitHub(dir, log: log);
      downloaded = result.$1;
      tag = result.$2;
    } catch (e) {
      log('⚠ Téléchargement GitHub échoué: $e');
    }

    // 2. Fallback : assets bundlés
    if (!downloaded) {
      log('📦 Extraction depuis les assets embarqués…');
      await _extractFromAssets(dir, log: log);
      tag = 'bundled';
    }

    // 3. pip install
    await _pipInstall(dir, log: log);

    // 4. Sauvegarder la version
    if (tag != null) {
      await File('$dir/$_versionFile').writeAsString(tag);
    }

    log('✓ Installation terminée — version $tag');
  }

  /// Met à jour le gateway vers la dernière version.
  static Future<void> update({
    void Function(String msg)? onProgress,
  }) async {
    await install(onProgress: onProgress, forceReinstall: true);
  }

  // ── GitHub download ────────────────────────────────────────────────

  static Future<(bool, String?)> _downloadFromGitHub(
    String destDir, {
    void Function(String)? log,
  }) async {
    log?.call('🌐 Récupération de la dernière release GitHub…');

    final apiUrl =
        'https://api.github.com/repos/$_githubRepo/releases/latest';
    final resp = await http.get(
      Uri.parse(apiUrl),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('GitHub API ${resp.statusCode}');
    }

    final release = json.decode(resp.body) as Map<String, dynamic>;
    final assets = (release['assets'] as List?) ?? [];
    final tagName = release['tag_name'] as String? ?? 'latest';

    // Chercher l'asset ZIP
    String? downloadUrl;
    for (final asset in assets) {
      final name = asset['name'] as String;
      if (name.contains('panda-ai') && name.endsWith('.zip')) {
        downloadUrl = asset['browser_download_url'] as String;
        break;
      }
    }

    // Fallback : zipball de la release
    downloadUrl ??=
        'https://github.com/$_githubRepo/archive/refs/tags/$tagName.zip';

    log?.call('⬇ Téléchargement $tagName…');

    final zipResp =
        await http.get(Uri.parse(downloadUrl)).timeout(const Duration(seconds: 120));

    if (zipResp.statusCode != 200) {
      throw Exception('Download ${zipResp.statusCode}');
    }

    final zipFile = File('$destDir/gateway.zip');
    await zipFile.writeAsBytes(zipResp.bodyBytes);
    log?.call('✓ Téléchargé (${zipResp.bodyBytes.length ~/ 1024} KB)');

    await _extractZip(zipFile, destDir, log: log);
    await zipFile.delete();
    return (true, tagName);
  }

  // ── Assets bundlés ────────────────────────────────────────────────

  static Future<void> _extractFromAssets(
    String destDir, {
    void Function(String)? log,
  }) async {
    log?.call('⚠ Assets embarqués non disponibles');
    log?.call('Clonez panda-ai manuellement :');
    log?.call('git clone https://github.com/$_githubRepo');
  }

  // ── ZIP extraction ────────────────────────────────────────────────

  static Future<void> _extractZip(
    File zipFile,
    String destDir, {
    void Function(String)? log,
  }) async {
    log?.call('📂 Extraction ZIP…');
    final destDirectory = Directory(destDir);

    try {
      await ZipFile.extractToDirectory(
        zipFile: zipFile,
        destinationDir: destDirectory,
      );
    } catch (e) {
      log?.call('⚠ ZipFile extraction échouée: $e');
      final result = await Process.run(
        'unzip', ['-o', zipFile.path, '-d', destDir],
      );
      if (result.exitCode != 0) {
        throw Exception('unzip failed: ${result.stderr}');
      }
    }

    // Si l'extraction a créé un sous-dossier (cas du zipball GitHub),
    // déplacer le contenu vers destDir
    final entries = await destDirectory.list().toList();
    if (entries.length == 1 && entries.first is Directory) {
      final subDir = entries.first as Directory;
      log?.call('  Réorganisation depuis ${subDir.path}…');
      await _moveContents(subDir, destDirectory);
      await subDir.delete(recursive: true);
    }

    log?.call('✓ Extraction terminée');
  }

  static Future<void> _moveContents(Directory from, Directory to) async {
    await for (final entity in from.list()) {
      final name = entity.path.split('/').last;
      if (entity is File) {
        await entity.copy('${to.path}/$name');
      } else if (entity is Directory) {
        await _copyDir(entity, Directory('${to.path}/$name'));
      }
    }
  }

  static Future<void> _copyDir(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list()) {
      final name = entity.path.split('/').last;
      if (entity is File) {
        await entity.copy('${to.path}/$name');
      } else if (entity is Directory) {
        await _copyDir(entity, Directory('${to.path}/$name'));
      }
    }
  }

  // ── pip install ───────────────────────────────────────────────────

  static Future<void> _pipInstall(
    String installDir, {
    void Function(String)? log,
  }) async {
    final reqFile = File('$installDir/requirements.txt');
    if (!await reqFile.exists()) {
      log?.call('⚠ requirements.txt introuvable — pip install ignoré');
      return;
    }

    log?.call('📦 Installation des dépendances Python…');

    final pip = await _findPip();
    if (pip == null) {
      log?.call('⚠ pip introuvable. Installez Python + pip via le terminal.');
      return;
    }

    final proc = await Process.start(
      pip,
      ['install', '-r', 'requirements.txt', '--quiet'],
      workingDirectory: installDir,
    );

    proc.stdout
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .listen((l) => log?.call('  $l'));
    proc.stderr
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .listen((l) => log?.call('  $l'));

    final code = await proc.exitCode;
    if (code == 0) {
      log?.call('✓ Dépendances installées');
    } else {
      log?.call('⚠ pip install a terminé avec le code $code');
    }
  }

  static Future<String?> _findPip() async {
    final candidates = [
      '/data/data/com.termux.app/files/usr/bin/pip3',
      '/data/data/com.termux.app/files/usr/bin/pip',
      '/usr/bin/pip3',
      '/usr/local/bin/pip3',
    ];
    for (final p in candidates) {
      if (await File(p).exists()) return p;
    }
    try {
      final r = await Process.run('which', ['pip3']);
      if (r.exitCode == 0) {
        final p = (r.stdout as String).trim();
        if (p.isNotEmpty) return p;
      }
    } catch (_) {}
    return null;
  }
}
