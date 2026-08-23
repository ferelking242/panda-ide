/// PandaRegistryPage — navigateur du registre ferelking242/panda-extensions.
///
/// Lit index.json (1 requête), affiche le catalogue avec icônes,
/// et installe/désinstalle au RUNTIME sans rebuild APK :
///
///   Install    : télécharge les fichiers → $appDir/extensions/<id>/ → charge
///   Désinstall : unload + suppression du dossier
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../native_extension_loader.dart';
import '../remote_registry.dart';
import '../../ui/flutter_device_panel.dart';

class PandaRegistryPage extends StatefulWidget {
  const PandaRegistryPage({super.key});

  @override
  State<PandaRegistryPage> createState() => _PandaRegistryPageState();
}

class _PandaRegistryPageState extends State<PandaRegistryPage> {
  RegistryIndex? _index;
  String? _error;
  final Set<String> _installed = {};
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // Racine réelle : $appDir/extensions
      final support = await getApplicationSupportDirectory();
      RemoteExtensionRegistry.instance.installRoot =
          Directory('${support.parent.path}/extensions').path;
      await Directory(RemoteExtensionRegistry.instance.installRoot)
          .create(recursive: true);

      final index = await RemoteExtensionRegistry.instance.fetchIndex();
      if (!mounted) return;
      setState(() => _index = index);

      for (final e in index.extensions) {
        if (await RemoteExtensionRegistry.instance.isInstalled(e.id)) {
          setState(() => _installed.add(e.id));
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _install(RegistryEntry entry) async {
    setState(() => _busy.add(entry.id));
    try {
      final path = await RemoteExtensionRegistry.instance.install(entry,
          onProgress: (done, total, file) {});
      await NativeExtensionLoader.instance.load(path);
      if (!mounted) return;
      setState(() {
        _installed.add(entry.id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${entry.name} installé 🐼'),
            backgroundColor: Colors.green.shade700));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Échec installation : $e'),
          backgroundColor: Colors.red.shade700));
    } finally {
      if (mounted) setState(() => _busy.remove(entry.id));
    }
  }

  Future<void> _uninstall(RegistryEntry entry) async {
    setState(() => _busy.add(entry.id));
    try {
      await NativeExtensionLoader.instance.unload(entry.id);
      await RemoteExtensionRegistry.instance.uninstall(entry.id);
      if (!mounted) return;
      setState(() => _installed.remove(entry.id));
    } finally {
      if (mounted) setState(() => _busy.remove(entry.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.storefront_rounded, size: 20),
          SizedBox(width: 8),
          Text('Extensions Panda',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Rafraîchir le registre',
            onPressed: () async {
              setState(() { _error = null; _index = null; });
              await RemoteExtensionRegistry.instance.fetchIndex(force: true);
              _bootstrap();
            },
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_rounded, size: 40),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13)),
              ])))
          : _index == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _index!.extensions.length,
                  itemBuilder: (_, i) =>
                      _buildCard(_index!.extensions[i], cs)),
    );
  }

  Widget _buildCard(RegistryEntry e, ColorScheme cs) {
    final isInstalled = _installed.contains(e.id);
    final isBusy = _busy.contains(e.id);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: .4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Icône (URL du registre)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: e.iconUrl != null
                  ? Image.network(e.iconUrl!,
                      width: 46, height: 46, errorBuilder: (_, __, ___) =>
                          Container(width: 46, height: 46, color:
                              cs.primaryContainer, child: Icon(Icons.extension,
                              color: cs.onPrimaryContainer)))
                  : Container(width: 46, height: 46, color: cs.primaryContainer,
                      child: Icon(Icons.extension, color: cs.onPrimaryContainer)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(child: Text(e.name,
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                    if (e.featured) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                    ],
                  ]),
                  Text('$e.version · ${e.author ?? 'anonyme'}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ])),
          ]),
          const SizedBox(height: 10),
          Text(e.description, style: const TextStyle(fontSize: 13, height: 1.35)),
          const SizedBox(height: 10),
          // Permissions
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final p in e.permissions.take(5))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(20)),
                child: Text(p, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (isInstalled && e.id == 'dev.panda.device')
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 17),
                  label: const Text('Ouvrir'),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const FlutterDevicePanel())),
                ),
              ),            if (isBusy)
              const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              FilledButton.icon(
                icon: Icon(isInstalled ? Icons.delete_outline : Icons.download_rounded, size: 17),
                label: Text(isInstalled ? 'Désinstaller' : 'Installer'),
                style: FilledButton.styleFrom(
                  backgroundColor: isInstalled ? null : cs.primary,
                  foregroundColor: isInstalled ? cs.error : cs.onPrimary,
                ),
                onPressed: () => isInstalled ? _uninstall(e) : _install(e),
              ),
          ]),
        ]),
      ),
    );
  }
}
