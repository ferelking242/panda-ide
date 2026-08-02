/// ExtensionsPanel — liste des extensions installées — Phase 8.
///
/// Affiche toutes les extensions installées avec possibilité de :
///   - activer / désactiver
///   - désinstaller
///   - voir le README
///   - voir l'état d'activation
///
/// Usage :
///   Navigator.push(context, MaterialPageRoute(builder: (_) => const ExtensionsPanel()));
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../extension_host_manager.dart';
import '../extension_registry.dart';
import '../open_vsx_client.dart';
import '../vsix_installer.dart';
import 'marketplace_page.dart';

class ExtensionsPanel extends StatefulWidget {
  const ExtensionsPanel({super.key});

  @override
  State<ExtensionsPanel> createState() => _ExtensionsPanelState();
}

class _ExtensionsPanelState extends State<ExtensionsPanel> {
  List<InstalledExtension> _extensions = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadExtensions();
  }

  Future<void> _loadExtensions() async {
    await ExtensionRegistry.instance.load();
    if (!mounted) return;
    setState(() {
      _extensions = ExtensionRegistry.instance.all;
      _loaded = true;
    });
  }

  Future<void> _setEnabled(InstalledExtension ext, bool enabled) async {
    await ExtensionRegistry.instance.setEnabled(ext.manifest.id, enabled: enabled);
    if (enabled) {
      if (ExtensionHostManager.instance.isConfigured) {
        try {
          await ExtensionHostManager.instance.activate(
            ExtensionRegistry.instance.get(ext.manifest.id)!,
          );
        } catch (_) {}
      }
    } else {
      await ExtensionHostManager.instance.deactivate(ext.manifest.id);
    }
    _loadExtensions();
  }

  Future<void> _uninstall(InstalledExtension ext) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Désinstaller'),
        content: Text(
            'Voulez-vous vraiment désinstaller "${ext.manifest.displayName}" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Désinstaller'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ExtensionHostManager.instance.deactivate(ext.manifest.id);
    await VsixInstaller().uninstall(ext.manifest.id);
    _loadExtensions();
  }

  void _viewReadme(InstalledExtension ext) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ReadmePage(extension: ext),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF2D2D2D) : null,
        elevation: 0,
        title: const Text('Extensions installées', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Marketplace',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MarketplacePage()),
            ).then((_) => _loadExtensions()),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Rafraîchir',
            onPressed: _loadExtensions,
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _extensions.isEmpty
              ? _EmptyState(
                  onOpenMarketplace: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MarketplacePage()),
                  ).then((_) => _loadExtensions()),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _extensions.length,
                  itemBuilder: (_, i) => _ExtensionListItem(
                    ext: _extensions[i],
                    isActive: ExtensionHostManager.instance.isActive(_extensions[i].manifest.id),
                    onToggle: (v) => _setEnabled(_extensions[i], v),
                    onUninstall: () => _uninstall(_extensions[i]),
                    onViewReadme: () => _viewReadme(_extensions[i]),
                  ),
                ),
    );
  }
}

// ── Extension list item ───────────────────────────────────────────────────────

class _ExtensionListItem extends StatelessWidget {
  final InstalledExtension ext;
  final bool isActive;
  final ValueChanged<bool> onToggle;
  final VoidCallback onUninstall;
  final VoidCallback onViewReadme;

  const _ExtensionListItem({
    required this.ext,
    required this.isActive,
    required this.onToggle,
    required this.onUninstall,
    required this.onViewReadme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final subColor = isDark ? Colors.white54 : Colors.black54;
    final cardColor = isDark ? const Color(0xFF252526) : Colors.white;
    final borderColor = isDark ? const Color(0xFF3C3C3C) : const Color(0xFFE0E0E0);

    // State indicator color
    Color stateColor;
    IconData stateIcon;
    if (ext.state == ExtensionState.error) {
      stateColor = Colors.red;
      stateIcon = Icons.error_outline;
    } else if (!ext.isEnabled) {
      stateColor = Colors.grey;
      stateIcon = Icons.pause_circle_outline;
    } else if (isActive) {
      stateColor = Colors.green;
      stateIcon = Icons.check_circle_outline;
    } else {
      stateColor = Colors.orange;
      stateIcon = Icons.circle_outlined;
    }

    return Card(
      color: cardColor,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Icon
                _ExtIcon(installPath: ext.installPath, size: 36),
                const SizedBox(width: 10),

                // Name + publisher
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ext.manifest.displayName,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${ext.manifest.publisher} · v${ext.manifest.version}',
                        style: TextStyle(fontSize: 11, color: subColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // State indicator
                Tooltip(
                  message: ext.state == ExtensionState.error
                      ? ext.errorMessage ?? 'Erreur'
                      : isActive
                          ? 'Actif'
                          : ext.isEnabled
                              ? 'Activé (non démarré)'
                              : 'Désactivé',
                  child: Icon(stateIcon, size: 16, color: stateColor),
                ),
                const SizedBox(width: 8),

                // Enable/disable toggle
                Switch(
                  value: ext.isEnabled,
                  onChanged: onToggle,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: const Color(0xFF0066B8),
                ),
              ],
            ),

            if (ext.manifest.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                ext.manifest.description,
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            if (ext.state == ExtensionState.error && ext.errorMessage != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  ext.errorMessage!,
                  style: const TextStyle(fontSize: 11, color: Colors.red),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Action buttons
            Row(
              children: [
                // Tags
                if (ext.manifest.categories.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0066B8).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      ext.manifest.categories.first,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF0066B8)),
                    ),
                  ),
                const Spacer(),
                // README button
                TextButton.icon(
                  onPressed: onViewReadme,
                  icon: const Icon(Icons.description_outlined, size: 14),
                  label: const Text('README', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: subColor,
                  ),
                ),
                const SizedBox(width: 4),
                // Uninstall
                TextButton.icon(
                  onPressed: onUninstall,
                  icon: const Icon(Icons.delete_outline, size: 14),
                  label: const Text('Désinstaller', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: Colors.red[400],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Extension icon helper ─────────────────────────────────────────────────────

class _ExtIcon extends StatelessWidget {
  final String installPath;
  final double size;
  const _ExtIcon({required this.installPath, required this.size});

  @override
  Widget build(BuildContext context) {
    // Try to find icon from the extension's package.json icon field
    // This would need the manifest icon field — for now use default
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0066B8).withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(Icons.extension, size: size * 0.55, color: const Color(0xFF0066B8)),
    );
  }
}

// ── README page ───────────────────────────────────────────────────────────────

class _ReadmePage extends StatefulWidget {
  final InstalledExtension extension;
  const _ReadmePage({required this.extension});

  @override
  State<_ReadmePage> createState() => _ReadmePageState();
}

class _ReadmePageState extends State<_ReadmePage> {
  String? _readme;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReadme();
  }

  Future<void> _loadReadme() async {
    // Try local README first
    final localReadme = File('${widget.extension.installPath}/README.md');
    if (localReadme.existsSync()) {
      final content = await localReadme.readAsString();
      if (mounted) {
        setState(() {
          _readme = content;
          _loading = false;
        });
      }
      return;
    }

    // Fallback: fetch from Open VSX
    final manifest = widget.extension.manifest;
    final parts = manifest.id.split('.');
    if (parts.length >= 2) {
      try {
        final client = OpenVsxClient();
        final readme = await client.getReadme(parts[0], parts.sublist(1).join('.'), manifest.version);
        client.dispose();
        if (mounted) {
          setState(() {
            _readme = readme ?? '*Aucun README disponible.*';
            _loading = false;
          });
        }
        return;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _readme = '*Aucun README disponible.*';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.extension.manifest.displayName,
          style: const TextStyle(fontSize: 16),
        ),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _readme != null
              ? MarkdownWidget(
                  data: _readme!,
                  config: MarkdownConfig(configs: [
                    if (isDark)
                      const PreConfig(theme: {'root': TextStyle(color: Colors.white70)}),
                  ]),
                )
              : Center(child: Text(_error ?? 'README non disponible')),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onOpenMarketplace;
  const _EmptyState({required this.onOpenMarketplace});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.extension_off, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Aucune extension installée',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Installez des extensions depuis le marketplace\nOpen VSX pour enrichir votre IDE.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onOpenMarketplace,
              icon: const Icon(Icons.store, size: 18),
              label: const Text('Ouvrir le Marketplace'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0066B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
