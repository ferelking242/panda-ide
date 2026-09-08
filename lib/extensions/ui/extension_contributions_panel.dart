import 'package:flutter/material.dart';
import '../command_registry.dart';
import '../extension_contributions.dart';

/// Sidebar entry point for VS Code contribution points.
///
/// This keeps contributed commands and views discoverable even when an
/// extension is lazy and has not started its Node host yet.
class ExtensionContributionsPanel extends StatefulWidget {
  const ExtensionContributionsPanel({super.key});

  @override
  State<ExtensionContributionsPanel> createState() =>
      _ExtensionContributionsPanelState();
}

class _ExtensionContributionsPanelState
    extends State<ExtensionContributionsPanel> {
  ExtensionContributionSnapshot? _snapshot;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await ExtensionContributionIndex.load();
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (_) {
      if (mounted) setState(() => _snapshot = const ExtensionContributionSnapshot());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runCommand(RegisteredCommand command) async {
    try {
      await ExtensionContributionIndex.launchCommand(command);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${command.displayLabel} exécutée')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Impossible de lancer ${command.displayLabel}: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openView(ExtensionViewEntry view) async {
    try {
      await ExtensionContributionIndex.showView(view);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${view.title} activée')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Impossible d’ouvrir ${view.title}: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());

    final snapshot = _snapshot ?? const ExtensionContributionSnapshot();
    if (snapshot.commands.isEmpty &&
        snapshot.views.isEmpty &&
        snapshot.menus.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            Icon(Icons.extension_off, size: 42, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Aucune contribution d’extension installée.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (snapshot.views.isNotEmpty) ...[
            _sectionTitle('VUES ET PANNEAUX', cs),
            ...snapshot.views.map(
              (view) => ListTile(
                dense: true,
                leading: Icon(
                  view.isContainer
                      ? Icons.dashboard_customize_outlined
                      : Icons.view_sidebar_outlined,
                  size: 18,
                  color: cs.primary,
                ),
                title: Text(view.title, style: const TextStyle(fontSize: 12)),
                subtitle: Text(
                  '${view.extensionId} · ${view.viewId}',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _openView(view),
              ),
            ),
          ],
          if (snapshot.commands.isNotEmpty) ...[
            _sectionTitle('COMMANDES', cs),
            ...snapshot.commands.map(
              (command) => ListTile(
                dense: true,
                leading: Icon(Icons.play_arrow_outlined, size: 18, color: cs.primary),
                title: Text(command.displayLabel,
                    style: const TextStyle(fontSize: 12)),
                subtitle: Text(
                  '${command.extensionId} · ${command.command}',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _runCommand(command),
              ),
            ),
          ],
          if (snapshot.menus.isNotEmpty) ...[
            _sectionTitle('MENUS', cs),
            ...snapshot.menus.map(
              (menu) => ListTile(
                dense: true,
                leading: Icon(Icons.menu_open, size: 18, color: cs.primary),
                title: Text(menu.command, style: const TextStyle(fontSize: 12)),
                subtitle: Text(
                  '${menu.extensionId} · ${menu.menuId}'
                      '${menu.when == null ? '' : ' · when ${menu.when}'}',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _runMenu(menu),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _runMenu(ExtensionMenuEntry menu) async {
    final command = (_snapshot?.commands ?? const <RegisteredCommand>[])
        .where((item) =>
            item.command == menu.command &&
            item.extensionId == menu.extensionId)
        .firstOrNull;
    if (command == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Commande ${menu.command} non déclarée')),
      );
      return;
    }
    await _runCommand(command);
  }

  Widget _sectionTitle(String label, ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: cs.onSurfaceVariant,
          ),
        ),
      );
}