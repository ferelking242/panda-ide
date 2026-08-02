/// Téléchargement et extraction des fichiers .vsix.
///
/// Un .vsix est un ZIP contenant :
///   extension/package.json   ← manifest
///   extension/package.nls.json (optionnel)
///   extension/<main>         ← entry point JS
///   extension/...            ← reste de l'extension
///   [Content_Types].xml      ← metadata ZIP (ignoré)
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_archive/flutter_archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'extension_registry.dart';
import 'models/extension_manifest.dart';

/// Résultat d'une installation.
sealed class InstallResult {
  const InstallResult();
}

class InstallSuccess extends InstallResult {
  final InstalledExtension extension;
  const InstallSuccess(this.extension);
}

class InstallFailure extends InstallResult {
  final String reason;
  const InstallFailure(this.reason);
}

/// Raison de rejet d'une extension.
enum InstallRejectionReason {
  nativeBinaries,
  noEntryPoint,
  alreadyInstalled,
  downloadFailed,
  extractionFailed,
  manifestMissing,
  manifestInvalid,
}

class VsixInstaller {
  final void Function(double progress, String message)? onProgress;

  const VsixInstaller({this.onProgress});

  // ── Point d'entrée principal ─────────────────────────────────────────────

  /// Télécharge et installe une extension depuis une URL .vsix.
  Future<InstallResult> installFromUrl(String vsixUrl, {bool force = false}) async {
    _progress(0.0, 'Téléchargement…');

    // 1. Téléchargement
    final File vsixFile;
    try {
      vsixFile = await _download(vsixUrl);
    } catch (e) {
      return InstallFailure('Échec du téléchargement : $e');
    }

    try {
      return await installFromFile(vsixFile, force: force);
    } finally {
      // Nettoyage du fichier temporaire
      try {
        await vsixFile.delete();
      } catch (_) {}
    }
  }

  /// Installe depuis un fichier .vsix local (ex: sélectionné via file_picker).
  Future<InstallResult> installFromFile(File vsixFile, {bool force = false}) async {
    _progress(0.3, 'Extraction…');

    // 2. Extraction vers dossier temporaire
    final tempDir = Directory(
        p.join(Directory.systemTemp.path, 'panda_vsix_${DateTime.now().millisecondsSinceEpoch}'));
    await tempDir.create(recursive: true);

    try {
      await ZipFile.extractToDirectory(
        zipFile: vsixFile,
        destinationDir: tempDir,
      );
    } catch (e) {
      await _cleanup(tempDir);
      return InstallFailure('Échec de l\'extraction : $e');
    }

    _progress(0.5, 'Lecture du manifest…');

    // 3. Lecture du manifest
    final manifestFile = File(p.join(tempDir.path, 'extension', 'package.json'));
    if (!manifestFile.existsSync()) {
      await _cleanup(tempDir);
      return InstallFailure('package.json introuvable dans le .vsix');
    }

    ExtensionManifest manifest;
    try {
      final raw = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      manifest = ExtensionManifest.fromJson(raw);
    } catch (e) {
      await _cleanup(tempDir);
      return InstallFailure('Manifest invalide : $e');
    }

    _progress(0.6, 'Vérification de la compatibilité…');

    // 4. Vérifications de compatibilité
    if (manifest.requiresNativeBinaries) {
      await _cleanup(tempDir);
      return InstallFailure(
          'Cette extension utilise des binaires natifs (.node) compilés pour x64 PC — '
          'incompatibles avec Android ARM64. '
          'Cherchez une alternative sur open-vsx.org.');
    }

    if (!manifest.hasRunnableEntryPoint) {
      await _cleanup(tempDir);
      return InstallFailure(
          'Cette extension n\'a pas d\'entry point (champ "main" ou "browser" manquant).');
    }

    // 5. Vérifier si déjà installée
    await ExtensionRegistry.instance.load();
    if (!force && ExtensionRegistry.instance.isInstalled(manifest.id)) {
      await _cleanup(tempDir);
      return InstallFailure(
          '${manifest.id} est déjà installé. Utilisez force: true pour réinstaller.');
    }

    _progress(0.7, 'Installation…');

    // 6. Déplacer vers le dossier d'installation final
    final installPath = ExtensionRegistry.installPathFor(manifest.id, manifest.version);
    final installDir = Directory(installPath);

    if (installDir.existsSync()) {
      await installDir.delete(recursive: true);
    }

    await Directory(p.dirname(installPath)).create(recursive: true);

    // On déplace le sous-dossier "extension/" vers installPath
    final extensionDir = Directory(p.join(tempDir.path, 'extension'));
    await extensionDir.rename(installPath);

    _progress(0.9, 'Enregistrement…');

    // 7. Enregistrer dans le registre
    final installed = InstalledExtension(
      manifest: manifest,
      installPath: installPath,
      state: ExtensionState.enabled,
    );
    await ExtensionRegistry.instance.register(installed);

    await _cleanup(tempDir);
    _progress(1.0, 'Installation terminée');

    return InstallSuccess(installed);
  }

  // ── Désinstallation ──────────────────────────────────────────────────────

  Future<bool> uninstall(String extensionId) async {
    await ExtensionRegistry.instance.load();
    final ext = ExtensionRegistry.instance.get(extensionId);
    if (ext == null) return false;

    // Supprimer les fichiers
    final dir = Directory(ext.installPath);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }

    // Supprimer du registre
    await ExtensionRegistry.instance.unregister(extensionId);
    return true;
  }

  // ── Mise à jour ──────────────────────────────────────────────────────────

  Future<InstallResult> update(String vsixUrl) async {
    return installFromUrl(vsixUrl, force: true);
  }

  // ── Helpers privés ───────────────────────────────────────────────────────

  Future<File> _download(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final tempFile = File(
        p.join(Directory.systemTemp.path, 'panda_${DateTime.now().millisecondsSinceEpoch}.vsix'));
    await tempFile.writeAsBytes(response.bodyBytes);
    return tempFile;
  }

  Future<void> _cleanup(Directory dir) async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  void _progress(double value, String message) {
    onProgress?.call(value, message);
  }
}
