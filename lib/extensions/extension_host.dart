/// ExtensionHost — orchestrateur d'activation paresseuse façon VS Code.
///
/// VS Code ne charge JAMAIS le code d'une extension au démarrage : il scanne
/// uniquement les manifests (package.json) puis attend un événement
/// d'activation. Ce fichier porte la même sémantique pour les extensions
/// .panda :
///
///   scanInstalled()        → indexe les manifests SANS exécuter de code
///   activateEager()        → `*` / onStartup / onStartupFinished
///   executeCommand(id)     → `onCommand:<id>`   (palette, keybinding, menus)
///   onFileOpened(lang)     → `onLanguage:<id>`  (ouverture d'un fichier)
///   onViewShown(viewId)    → `onView:<id>`      (vue sidebar/panel visible)
///   onWorkspaceOpened(dir) → `workspaceContains:<pattern>`
///   handleUri(uri)         → `panda://<extId>/<command>` (lien externe)
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'models/panda_manifest.dart';
import 'native_extension_loader.dart';
import 'remote_registry.dart';

class ExtensionHost {
  ExtensionHost._();
  static final ExtensionHost instance = ExtensionHost._();

  /// id → chemin du dossier installé.
  final Map<String, String> _installPaths = {};

  /// id → manifest parsé (léger : aucun code d'extension exécuté).
  final Map<String, PandaManifest> _manifests = {};

  bool _scanned = false;

  List<PandaManifest> get knownManifests =>
      _manifests.values.toList(growable: false);

  PandaManifest? manifestOf(String id) => _manifests[id];

  /// L'extension est-elle chargée ET activée ?
  bool isActive(String id) {
    for (final ext in NativeExtensionLoader.instance.loaded) {
      if (ext.id == id) return ext.isActivated;
    }
    return false;
  }

  // ── Scan des manifests (équivalent scan package.json de VS Code) ─────

  /// Indexe tous les manifests installés. Rapide (lecture fichiers YAML),
  /// aucun isolate lancé, aucune activation.
  Future<void> scanInstalled() async {
    final root = Directory(RemoteExtensionRegistry.instance.installRoot);
    if (!await root.exists()) {
      _scanned = true;
      return;
    }
    await for (final e in root.list()) {
      if (e is! Directory) continue;
      final mf = File(p.join(e.path, 'panda.yaml'));
      if (!await mf.exists()) continue;
      try {
        final m = await PandaManifest.fromFile(mf.path);
        _installPaths[m.id] = e.path;
        _manifests[m.id] = m;
      } catch (_) {
        // manifest cassé : ignoré, jamais bloquant pour les autres
      }
    }
    _scanned = true;
  }

  Future<void> _ensureScanned() async {
    if (!_scanned) await scanInstalled();
  }

  /// À appeler après désinstallation pour purger l'index.
  void forgetInstalled(String id) {
    _installPaths.remove(id);
    _manifests.remove(id);
  }

  /// Charge + active une extension si ce n'est pas déjà fait.
  Future<void> ensureActivated(String id) async {
    await _ensureScanned();
    if (isActive(id)) return;
    var dir = _installPaths[id];
    dir ??= p.join(RemoteExtensionRegistry.instance.installRoot, id);
    final ext = await NativeExtensionLoader.instance.load(dir);
    if (!ext.isActivated) {
      await NativeExtensionLoader.instance.activate(ext);
    }
  }

  // ── Événements d'activation ───────────────────────────────────────────

  /// Active toutes les extensions déclarées sur `*` / onStartup /
  /// onStartupFinished. À appeler une fois l'IDE démarré.
  Future<void> activateEagerExtensions() async {
    await _ensureScanned();
    for (final m in _manifests.values) {
      if (m.activation.wantsStartup && !isActive(m.id)) {
        try {
          await ensureActivated(m.id);
        } catch (_) {
          // une extension cassée n'empêche jamais les autres de démarrer
        }
      }
    }
  }

  /// `onCommand:<id>` — appelé par la palette de commandes, les keybindings,
  /// les menus contextuels, les status bar items… C'est LE point d'entrée
  /// universel des extensions VS Code.
  ///
  /// Retourne le résultat envoyé par l'extension (null si elle ne renvoie
  /// rien), ou throw si la commande est inconnue / non activable.
  Future<dynamic> executeCommand(String commandId) async {
    await _ensureScanned();

    // 1. Trouver l'extension qui déclare cette commande (sans la charger).
    PandaManifest? owner;
    for (final m in _manifests.values) {
      if (m.contributes.commands.any((c) => c.id == commandId)) {
        owner = m;
        break;
      }
    }
    if (owner == null) {
      throw StateError('Commande inconnue : $commandId');
    }

    // 2. Activation paresseuse : seulement si onCommand:<id> correspond,
    //    ou si l'extension est eager/startup. Jamais sinon.
    final evts = owner.activation.events;
    final lazilyActivatable =
        evts.contains('onCommand:$commandId') || owner.activation.wantsStartup;
    if (!isActive(owner.id)) {
      if (!lazilyActivatable && evts.isNotEmpty && !owner.activation.eager) {
        throw StateError(
            '${owner.id} ne s\'active pas via onCommand:$commandId '
            '(events: $evts)');
      }
      await ensureActivated(owner.id);
      await _notify(owner.id, {'reason': 'onCommand:$commandId'});
    }

    // 3. Déléguer à l'extension activée.
    for (final ext in NativeExtensionLoader.instance.loaded) {
      if (ext.id == owner.id) {
        return ext.request<dynamic>('command', {'command': commandId});
      }
    }
    throw StateError('${owner.id} introuvable après activation');
  }

  /// `onLanguage:<id>` — à appeler à chaque ouverture/création de fichier.
  /// [languageId] : identifiant du langage ('dart', 'python', 'markdown'…).
  Future<void> onFileOpened(String languageId) async {
    await _ensureScanned();
    for (final m in _manifests.values) {
      if (!isActive(m.id) &&
          m.activation.events.contains('onLanguage:$languageId')) {
        try {
          await ensureActivated(m.id);
          await _notify(m.id, {'reason': 'onLanguage:$languageId'});
        } catch (_) {}
      }
    }
  }

  /// `onView:<id>` — à appeler quand une vue sidebar/panel devient visible.
  Future<void> onViewShown(String viewId) async {
    await _ensureScanned();
    for (final m in _manifests.values) {
      if (!isActive(m.id) &&
          (m.activation.events.contains('onView:$viewId') ||
              m.activation.matchesView(viewId))) {
        try {
          await ensureActivated(m.id);
          await _notify(m.id, {'reason': 'onView:$viewId'});
        } catch (_) {}
      }
    }
  }

  /// `workspaceContains:<pattern>` — à appeler à l'ouverture d'un dossier.
  /// Pattern simple : suffixe de nom de fichier ('**/*.x' → '.x',
  /// nom exact sinon).
  Future<void> onWorkspaceOpened(String rootPath) async {
    await _ensureScanned();
    for (final m in _manifests.values) {
      for (final evt in m.activation.events) {
        if (!evt.startsWith('workspaceContains:')) continue;
        final pattern =
            evt.substring('workspaceContains:'.length).trim();
        if (await _workspaceMatches(rootPath, pattern)) {
          try {
            await ensureActivated(m.id);
            await _notify(m.id, {'reason': evt});
          } catch (_) {}
          break;
        }
      }
    }
  }

  Future<bool> _workspaceMatches(String rootPath, String pattern) async {
    try {
      var suffix = pattern;
      if (suffix.startsWith('**/')) suffix = suffix.substring(3);
      if (suffix.startsWith('*.')) suffix = suffix.substring(1);
      final dir = Directory(rootPath);
      if (!await dir.exists()) return false;
      await for (final e in dir.list(recursive: true).take(200)) {
        if (e.path.endsWith(suffix)) return true;
      }
    } catch (_) {}
    return false;
  }

  // ── URI handler ────────────────────────────────────────────────────────

  /// `panda://<commandId>` ou `panda://<extId>/<command>?a=b` — permet de
  /// lancer une commande d'extension depuis l'extérieur (navigateur,
  /// notification, autre app), comme le vscode:// handler de VS Code.
  ///
  /// Retourne true si l'URI a été consommée.
  Future<bool> handleUri(Uri uri) async {
    if (uri.scheme != 'panda') return false;
    await _ensureScanned();
    var commandId = uri.host;
    final sub = uri.path.replaceFirst('/', '').trim();
    if (sub.isNotEmpty && !commandId.contains('.')) {
      commandId = '$commandId.$sub';
    } else if (sub.isNotEmpty) {
      commandId = sub;
    }
    try {
      await executeCommand(commandId);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Interne ────────────────────────────────────────────────────────────

  Future<void> _notify(String id, Map<String, dynamic> ctx) async {
    for (final ext in NativeExtensionLoader.instance.loaded) {
      if (ext.id == id && ext.isActivated) {
        ext.send('event', {'event': 'activate', 'data': ctx});
      }
    }
  }
}
