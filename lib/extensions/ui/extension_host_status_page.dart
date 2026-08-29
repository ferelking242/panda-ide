import 'package:flutter/material.dart';
import '../extension_host_health.dart';
import '../extension_host_manager.dart';
import '../node_runtime.dart';

/// Extension host status and diagnostics page.
class ExtensionHostStatusPage extends StatefulWidget {
  const ExtensionHostStatusPage({super.key});

  @override
  State<ExtensionHostStatusPage> createState() => _ExtensionHostStatusPageState();
}

class _ExtensionHostStatusPageState extends State<ExtensionHostStatusPage> {
  ExtensionHostReport? _report;
  NodeRuntimeStatus? _nodeStatus;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final report = await ExtensionHostHealth.check();
    final nodeStatus = await NodeRuntimeManager.instance.getStatus();
    if (mounted) {
      setState(() {
        _report = report;
        _nodeStatus = nodeStatus;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Extension Host', style: TextStyle(fontSize: 14)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Health status header
                  _buildHealthHeader(cs),
                  const SizedBox(height: 24),

                  // Node.js runtime
                  _buildNodeSection(cs),
                  const SizedBox(height: 24),

                  // Health checks
                  _buildChecksSection(cs),
                  const SizedBox(height: 24),

                  // Active extensions
                  _buildActiveExtensions(cs),
                ],
              ),
            ),
    );
  }

  Widget _buildHealthHeader(ColorScheme cs) {
    final healthy = _report?.healthy ?? false;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: healthy
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: healthy
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            healthy ? Icons.check_circle : Icons.error,
            size: 24,
            color: healthy ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  healthy ? 'Extension Host Ready' : 'Extension Host Issues',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: healthy ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _report?.summary ?? 'Unknown',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeSection(ColorScheme cs) {
    final installed = _nodeStatus?.installed ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.javascript, size: 18, color: installed ? Colors.green : Colors.grey),
                const SizedBox(width: 8),
                const Text('Node.js Runtime', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: installed ? Colors.green.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    installed ? 'Installed' : 'Not Installed',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: installed ? Colors.green : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (installed) ...[
              _infoRow('Version', _nodeStatus?.version ?? 'Unknown'),
              _infoRow('Path', _nodeStatus?.path ?? 'Unknown'),
              _infoRow('Size', _nodeStatus?.sizeText ?? 'Unknown'),
            ] else ...[
              Text(
                'Node.js is required for running VS Code extensions (Live Server, ESLint, Prettier, etc.).',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _installNode,
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Install Node.js'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChecksSection(ColorScheme cs) {
    final checks = _report?.checks ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Health Checks', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...checks.map((check) => _buildCheckTile(check, cs)),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckTile(ExtensionHostCheck check, ColorScheme cs) {
    final icon = check.severity == CheckSeverity.ok
        ? Icons.check_circle
        : check.severity == CheckSeverity.warning
            ? Icons.warning
            : Icons.error;
    final color = check.severity == CheckSeverity.ok
        ? Colors.green
        : check.severity == CheckSeverity.warning
            ? Colors.orange
            : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                Text(check.message, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveExtensions(ColorScheme cs) {
    final activeHosts = ExtensionHostManager.instance.activeHosts;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Active Extensions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${activeHosts.length}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            if (activeHosts.isEmpty)
              Text(
                'No extensions are currently active.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              )
            else
              ...activeHosts.map((host) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.extension, size: 16, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            host.manifest.displayName ?? host.id,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Active', style: TextStyle(fontSize: 10, color: Colors.green)),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  void _installNode() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Install Node.js'),
        content: const Text(
          'Node.js is required for running VS Code extensions like Live Server, ESLint, and Prettier.\n\n'
          'The binary (~80MB) will be downloaded to your device.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Download Node.js from Settings → Runtimes')),
              );
            },
            child: const Text('Install'),
          ),
        ],
      ),
    );
  }
}
