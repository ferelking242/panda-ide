/// Unified Plugin Manager — handles both .vsix (Node.js) and .panda (Dart) extensions.
///
/// This is the single entry point for loading, activating, and managing
/// all types of extensions in Panda IDE.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'extension_host_manager.dart';
import 'extension_registry.dart';
import 'models/extension_manifest.dart';
import 'models/panda_manifest.dart';
import 'native_extension_loader.dart';

/// The unified type that wraps either a Node.js or Dart extension.
enum ExtensionType { vscode, native }

/// A loaded extension (either .vsix or .panda).
class LoadedExtension {
  final ExtensionType type;
  final String id;
  final String name;
  final String version;

  /// For .vsix: InstalledExtension. For .panda: NativeExtension.
  final dynamic _impl;

  LoadedExtension.vscode(this._impl)
      : type = ExtensionType.vscode,
        id = (_impl as InstalledExtension).manifest.id,
        name = (_impl as InstalledExtension).manifest.displayName ??
            (_impl as InstalledExtension).manifest.name,
        version = (_impl as InstalledExtension).manifest.version;

  LoadedExtension.native(this._impl)
      : type = ExtensionType.native,
        id = (_impl as NativeExtension).id,
        name = (_impl as NativeExtension).manifest.name,
        version = (_impl as NativeExtension).manifest.version;

  InstalledExtension? get asVscode =>
      type == ExtensionType.vscode ? _impl as InstalledExtension : null;
  NativeExtension? get asNative =>
      type == ExtensionType.native ? _impl as NativeExtension : null;
}

/// Unified plugin manager.
class PluginManager {
  static final PluginManager instance = PluginManager._();
  PluginManager._();

  final Map<String, LoadedExtension> _loaded = {};
  final Map<String, bool> _enabled = {};

  List<LoadedExtension> get loaded => _loaded.values.toList();

  // ── Initialization ──────────────────────────────────────────────────────

  /// Load all extensions from the extensions directory.
  Future<void> loadAll(String extensionsDir) async {
    if (!await Directory(extensionsDir).exists()) return;

    await for (final entity in Directory(extensionsDir).list()) {
      if (entity is! Directory) continue;
      final dirPath = entity.path;

      try {
        // Check for .panda manifest
        if (await File(p.join(dirPath, 'panda.yaml')).exists()) {
          await _loadNative(dirPath);
        }
        // Check for VS Code manifest
        else if (await File(p.join(dirPath, 'package.json')).exists()) {
          await _loadVscode(dirPath);
        }
      } catch (e) {
        // ignore: avoid_print
        print('[PluginManager] Failed to load extension in $dirPath: $e');
      }
    }
  }

  /// Load a single .panda extension.
  Future<void> _loadNative(String dir) async {
    final ext = await NativeExtensionLoader.instance.load(dir);
    final loaded = LoadedExtension.native(ext);
    _loaded[ext.id] = loaded;
    _enabled[ext.id] = true;
  }

  /// Load a single .vsix extension.
  Future<void> _loadVscode(String dir) async {
    final manifestPath = p.join(dir, 'package.json');
    final manifest = await ExtensionManifest.fromFile(manifestPath);
    final installed = InstalledExtension(
      manifest: manifest,
      installPath: dir,
      isEnabled: true,
    );

    // Register in the existing extension registry
    await ExtensionRegistry.instance.register(installed);

    final loaded = LoadedExtension.vscode(installed);
    _loaded[manifest.id] = loaded;
    _enabled[manifest.id] = true;
  }

  // ── Activation ──────────────────────────────────────────────────────────

  /// Activate all enabled extensions.
  Future<void> activateAll() async {
    for (final ext in _loaded.values) {
      if (!(_enabled[ext.id] ?? true)) continue;
      try {
        await activate(ext.id);
      } catch (e) {
        print('[PluginManager] Failed to activate ${ext.id}: $e');
      }
    }
  }

  /// Activate a specific extension.
  Future<void> activate(String extensionId) async {
    final ext = _loaded[extensionId];
    if (ext == null) return;

    switch (ext.type) {
      case ExtensionType.vscode:
        final installed = ext.asVscode!;
        if (!installed.isRunnable) return;
        await ExtensionHostManager.instance.activate(installed);
        break;
      case ExtensionType.native:
        final native = ext.asNative!;
        await NativeExtensionLoader.instance.activate(native);
        break;
    }
  }

  /// Deactivate a specific extension.
  Future<void> deactivate(String extensionId) async {
    final ext = _loaded[extensionId];
    if (ext == null) return;

    switch (ext.type) {
      case ExtensionType.vscode:
        await ExtensionHostManager.instance.deactivate(extensionId);
        break;
      case ExtensionType.native:
        await NativeExtensionLoader.instance.unload(extensionId);
        break;
    }
  }

  // ── Enable/Disable ──────────────────────────────────────────────────────

  Future<void> enable(String extensionId) async {
    _enabled[extensionId] = true;
    await activate(extensionId);
  }

  Future<void> disable(String extensionId) async {
    _enabled[extensionId] = false;
    await deactivate(extensionId);
  }

  bool isEnabled(String extensionId) => _enabled[extensionId] ?? false;

  // ── Events ──────────────────────────────────────────────────────────────

  /// Broadcast an event to all active extensions.
  void broadcastEvent(String event, [dynamic data]) {
    // VS Code extensions
    ExtensionHostManager.instance.broadcastEvent(event, data);
    // Native Dart extensions
    NativeExtensionLoader.instance.broadcastEvent(event, data);
  }

  // ── Introspection ───────────────────────────────────────────────────────

  LoadedExtension? getExtension(String id) => _loaded[id];

  List<LoadedExtension> get active {
    return _loaded.values.where((ext) {
      if (ext.type == ExtensionType.vscode) {
        return ExtensionHostManager.instance.isActive(ext.id);
      } else {
        return ext.asNative?.isActivated ?? false;
      }
    }).toList();
  }

  /// Install a .vsix file.
  Future<void> installVsix(String vsixPath) async {
    // Delegate to existing VSIX installer
    // This will extract the .vsix, install npm deps, and register
    await _loadVscode(vsixPath);
  }

  /// Install a .panda extension from a directory.
  Future<void> installPanda(String dirPath) async {
    await _loadNative(dirPath);
  }

  /// Uninstall an extension.
  Future<void> uninstall(String extensionId) async {
    await deactivate(extensionId);
    final ext = _loaded.remove(extensionId);
    if (ext == null) return;

    if (ext.type == ExtensionType.native && ext.asNative != null) {
      await NativeExtensionLoader.instance.unload(extensionId);
    }

    _enabled.remove(extensionId);
  }

  // ── Dispose ─────────────────────────────────────────────────────────────

  Future<void> disposeAll() async {
    await ExtensionHostManager.instance.disposeAll();
    await NativeExtensionLoader.instance.unloadAll();
    _loaded.clear();
    _enabled.clear();
  }
}
