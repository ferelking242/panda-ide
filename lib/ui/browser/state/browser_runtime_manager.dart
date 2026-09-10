import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/browser_runtime.dart';

/// Gère le runtime du navigateur sans mélanger installation, état et UI.
///
/// Le runtime CEF est volontairement externe à l'application. Tant qu'un
/// paquet CEF validé n'est pas fourni par le canal de distribution, ce service
/// ne télécharge rien et ne marque jamais une installation comme prête sur la
/// seule présence d'un dossier.
class BrowserRuntimeManager extends ChangeNotifier {
  BrowserRuntimeManager._();

  static final BrowserRuntimeManager instance = BrowserRuntimeManager._();

  BrowserRuntimeSnapshot _snapshot = const BrowserRuntimeSnapshot(
    engine: BrowserEngineKind.unavailable,
    status: BrowserRuntimeStatus.checking,
  );

  BrowserRuntimeSnapshot get snapshot => _snapshot;

  Future<void> refresh() async {
    if (kIsWeb) {
      _set(
        const BrowserRuntimeSnapshot(
          engine: BrowserEngineKind.unavailable,
          status: BrowserRuntimeStatus.unsupported,
          message: 'Le navigateur intégré n’est pas disponible sur le Web.',
        ),
      );
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.linux) {
      // Le support existant Android/iOS passe par le WebView natif de la
      // plateforme. CEF est réservé au chemin desktop Linux.
      _set(
        const BrowserRuntimeSnapshot(
          engine: BrowserEngineKind.nativeWebView,
          status: BrowserRuntimeStatus.ready,
          message: 'Le moteur natif de la plateforme est utilisé.',
        ),
      );
      return;
    }

    _set(
      const BrowserRuntimeSnapshot(
        engine: BrowserEngineKind.cef,
        status: BrowserRuntimeStatus.checking,
      ),
    );

    try {
      final root = await _runtimeRoot();
      final manifestFile = File(p.join(root.path, 'manifest.json'));
      if (!await manifestFile.exists()) {
        _set(
          BrowserRuntimeSnapshot(
            engine: BrowserEngineKind.cef,
            status: BrowserRuntimeStatus.notInstalled,
            installPath: root.path,
            message: 'Le runtime CEF n’est pas encore installé.',
          ),
        );
        return;
      }

      final manifest = jsonDecode(await manifestFile.readAsString());
      if (manifest is! Map<String, dynamic>) {
        throw const FormatException('Manifest CEF invalide.');
      }

      final version = manifest['version'];
      final requiredFiles = (manifest['requiredFiles'] as List?)
          ?.whereType<String>()
          .toList(growable: false);
      if (version is! String ||
          version.trim().isEmpty ||
          requiredFiles == null ||
          requiredFiles.isEmpty) {
        throw const FormatException('Manifest CEF incomplet.');
      }

      for (final relativePath in requiredFiles) {
        final file = File(p.normalize(p.join(root.path, relativePath)));
        if (!p.isWithin(root.path, file.path)) {
          throw const FormatException(
            'Le manifest CEF contient un chemin hors du runtime.',
          );
        }
        if (!await file.exists()) {
          throw FileSystemException('Fichier CEF manquant', file.path);
        }
      }

      _set(
        BrowserRuntimeSnapshot(
          engine: BrowserEngineKind.cef,
          status: BrowserRuntimeStatus.ready,
          version: version,
          installPath: root.path,
        ),
      );
    } on FormatException catch (error) {
      _set(
        BrowserRuntimeSnapshot(
          engine: BrowserEngineKind.cef,
          status: BrowserRuntimeStatus.corrupted,
          message: error.message,
        ),
      );
    } on FileSystemException catch (error) {
      _set(
        BrowserRuntimeSnapshot(
          engine: BrowserEngineKind.cef,
          status: BrowserRuntimeStatus.corrupted,
          message: error.message,
        ),
      );
    } catch (error) {
      _set(
        BrowserRuntimeSnapshot(
          engine: BrowserEngineKind.cef,
          status: BrowserRuntimeStatus.error,
          message: error.toString(),
        ),
      );
    }
  }

  /// Retourne l'emplacement global du runtime, indépendant du projet ouvert.
  Future<Directory> runtimeDirectory() async => _runtimeRoot();

  Future<Directory> _runtimeRoot() async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'browser-runtime', 'cef'));
  }

  void _set(BrowserRuntimeSnapshot value) {
    _snapshot = value;
    notifyListeners();
  }

  @override
  void dispose() {
    // Singleton conservé pendant toute la durée de l'application.
    super.dispose();
  }
}

/// Permet aux tests et aux futures implémentations natives de détecter le
/// canal d'intégration choisi sans dépendre de la présence d'un plugin CEF.
const browserRuntimeChannel = MethodChannel('panda/browser_runtime');
