/// Index of extension contribution points exposed by Panda's UI.
library;

import 'extension_host.dart';
import 'extension_host_manager.dart';
import 'extension_registry.dart';
import 'command_registry.dart';

class ExtensionViewEntry {
  final String extensionId;
  final String title;
  final String viewId;
  final bool isContainer;

  const ExtensionViewEntry({
    required this.extensionId,
    required this.title,
    required this.viewId,
    this.isContainer = false,
  });
}

class ExtensionMenuEntry {
  final String extensionId;
  final String menuId;
  final String command;
  final String? when;

  const ExtensionMenuEntry({
    required this.extensionId,
    required this.menuId,
    required this.command,
    this.when,
  });
}

class ExtensionContributionSnapshot {
  final List<RegisteredCommand> commands;
  final List<ExtensionViewEntry> views;
  final List<ExtensionMenuEntry> menus;

  const ExtensionContributionSnapshot({
    this.commands = const [],
    this.views = const [],
    this.menus = const [],
  });
}

/// Reads manifests only. It never starts extension code.
class ExtensionContributionIndex {
  static Future<ExtensionContributionSnapshot> load() async {
    await ExtensionRegistry.instance.load();
    await ExtensionHost.instance.scanInstalled();

    final commands = <RegisteredCommand>[];
    final views = <ExtensionViewEntry>[];
    final menus = <ExtensionMenuEntry>[];
    final commandIds = <String>{};
    final viewIds = <String>{};

    for (final ext in ExtensionRegistry.instance.all) {
      final contributes = ext.manifest.contributes;
      for (final item in contributes.commands) {
        final id = item['command']?.toString();
        if (id == null || id.isEmpty || !commandIds.add(id)) continue;
        commands.add(RegisteredCommand(
          command: id,
          extensionId: ext.manifest.id,
          title: item['title']?.toString() ?? id,
          category: item['category']?.toString() ?? ext.manifest.displayName,
          description: item['description']?.toString() ?? ext.manifest.description,
        ));
      }
      for (final item in contributes.views) {
        final id = item['id']?.toString();
        if (id == null || id.isEmpty || !viewIds.add('${ext.manifest.id}:$id')) {
          continue;
        }
        views.add(ExtensionViewEntry(
          extensionId: ext.manifest.id,
          viewId: id,
          title: item['name']?.toString() ?? id,
        ));
      }
      for (final item in contributes.viewsContainers) {
        final id = item['id']?.toString();
        if (id == null || id.isEmpty || !viewIds.add('${ext.manifest.id}:$id')) {
          continue;
        }
        views.add(ExtensionViewEntry(
          extensionId: ext.manifest.id,
          viewId: id,
          title: item['title']?.toString() ?? id,
          isContainer: true,
        ));
      }
      for (final item in contributes.menus) {
        final command = item['command']?.toString();
        if (command == null || command.isEmpty) continue;
        menus.add(ExtensionMenuEntry(
          extensionId: ext.manifest.id,
          menuId: item['_container']?.toString() ?? 'menus',
          command: command,
          when: item['when']?.toString(),
        ));
      }
    }

    for (final manifest in ExtensionHost.instance.knownManifests) {
      for (final item in manifest.contributes.commands) {
        if (item.id.isEmpty || !commandIds.add(item.id)) continue;
        commands.add(RegisteredCommand(
          command: item.id,
          extensionId: manifest.id,
          title: item.title.isEmpty ? item.id : item.title,
          category: item.category ?? manifest.name,
          description: manifest.description,
        ));
      }
      for (final item in manifest.contributes.sidebarViews) {
        if (item.id.isEmpty || !viewIds.add('${manifest.id}:${item.id}')) {
          continue;
        }
        views.add(ExtensionViewEntry(
          extensionId: manifest.id,
          viewId: item.id,
          title: item.name.isEmpty ? item.id : item.name,
        ));
      }
      for (final item in manifest.contributes.menus) {
        menus.add(ExtensionMenuEntry(
          extensionId: manifest.id,
          menuId: item.position,
          command: item.command,
          when: item.when,
        ));
      }
    }

    return ExtensionContributionSnapshot(
      commands: commands,
      views: views,
      menus: menus,
    );
  }

  static Future<void> launchCommand(RegisteredCommand command) async {
    final native = ExtensionHost.instance.manifestOf(command.extensionId);
    if (native != null) {
      await ExtensionHost.instance.executeCommand(command.command);
      return;
    }

    await ExtensionRegistry.instance.load();
    final ext = ExtensionRegistry.instance.get(command.extensionId);
    if (ext == null) {
      throw StateError('Extension ${command.extensionId} is not installed');
    }
    if (!ExtensionHostManager.instance.isActive(ext.manifest.id)) {
      await ExtensionHostManager.instance.activate(ext);
    }
    await CommandRegistry.instance.execute(command.command, const []);
  }

  static Future<void> showView(ExtensionViewEntry view) async {
    final native = ExtensionHost.instance.manifestOf(view.extensionId);
    if (native != null) {
      await ExtensionHost.instance.onViewShown(view.viewId);
      return;
    }

    await ExtensionRegistry.instance.load();
    final ext = ExtensionRegistry.instance.get(view.extensionId);
    if (ext == null) {
      throw StateError('Extension ${view.extensionId} is not installed');
    }
    // Activation is the VS Code contract for contributed views. The extension
    // registers its webview/tree provider while activating; the panel manager
    // then exposes the resulting view in the Extensions sidebar.
    await ExtensionHostManager.instance.activateForView(view.viewId);
  }
}