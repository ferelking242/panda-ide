import 'package:flutter/material.dart';
import '../launch_config.dart';

/// VS Code-style launch.json configuration page.
class LaunchConfigPage extends StatefulWidget {
  final String workspacePath;
  const LaunchConfigPage({super.key, required this.workspacePath});

  @override
  State<LaunchConfigPage> createState() => _LaunchConfigPageState();
}

class _LaunchConfigPageState extends State<LaunchConfigPage> {
  late LaunchConfigManager _manager;
  List<LaunchConfig> _configs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _manager = LaunchConfigManager(widget.workspacePath);
    _load();
  }

  Future<void> _load() async {
    final configs = await _manager.load();
    if (configs.isEmpty) {
      // Add default configs
      configs.add(LaunchConfigManager.defaultFlutter());
      configs.add(LaunchConfigManager.defaultDart());
      await _manager.save(configs);
    }
    if (mounted) setState(() { _configs = configs; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Launch Configurations', style: TextStyle(fontSize: 14)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            tooltip: 'Add Configuration',
            onPressed: _addConfig,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _configs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bug_report, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text('No launch configurations', style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _addConfig,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Configuration'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _configs.length,
                  itemBuilder: (ctx, i) => _buildConfigTile(_configs[i], i, cs),
                ),
    );
  }

  Widget _buildConfigTile(LaunchConfig config, int index, ColorScheme cs) {
    final typeIcon = _typeIcon(config.type);
    final typeColor = _typeColor(config.type);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: typeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(typeIcon, size: 18, color: typeColor),
        ),
        title: Text(config.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text('${config.type} • ${config.request}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 18),
              tooltip: 'Start Debugging',
              onPressed: () => _startDebug(config),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Remove',
              onPressed: () => _removeConfig(index),
            ),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'flutter': return Icons.phone_android;
      case 'dart': return Icons.code;
      case 'node': return Icons.javascript;
      case 'python': return Icons.code;
      default: return Icons.bug_report;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'flutter': return Colors.blue;
      case 'dart': return Colors.cyan;
      case 'node': return Colors.green;
      case 'python': return Colors.amber;
      default: return Colors.grey;
    }
  }

  void _addConfig() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddConfigSheet(
        onAdd: (config) async {
          await _manager.addConfig(config);
          _load();
        },
      ),
    );
  }

  void _removeConfig(int index) async {
    await _manager.removeConfig(index);
    _load();
  }

  void _startDebug(LaunchConfig config) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Starting: ${config.name}...')),
    );
  }
}

class _AddConfigSheet extends StatefulWidget {
  final void Function(LaunchConfig config) onAdd;
  const _AddConfigSheet({required this.onAdd});

  @override
  State<_AddConfigSheet> createState() => _AddConfigSheetState();
}

class _AddConfigSheetState extends State<_AddConfigSheet> {
  final _nameCtrl = TextEditingController(text: 'Flutter (main.dart)');
  String _type = 'flutter';
  String _request = 'launch';
  final _programCtrl = TextEditingController(text: 'lib/main.dart');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New Launch Configuration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Name', isDense: true),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type', isDense: true),
            items: const [
              DropdownMenuItem(value: 'flutter', child: Text('Flutter')),
              DropdownMenuItem(value: 'dart', child: Text('Dart')),
              DropdownMenuItem(value: 'node', child: Text('Node.js')),
              DropdownMenuItem(value: 'python', child: Text('Python')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'flutter'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _request,
            decoration: const InputDecoration(labelText: 'Request', isDense: true),
            items: const [
              DropdownMenuItem(value: 'launch', child: Text('Launch')),
              DropdownMenuItem(value: 'attach', child: Text('Attach')),
            ],
            onChanged: (v) => setState(() => _request = v ?? 'launch'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _programCtrl,
            decoration: const InputDecoration(labelText: 'Program path', isDense: true),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  widget.onAdd(LaunchConfig(
                    name: _nameCtrl.text,
                    type: _type,
                    request: _request,
                    args: {'program': _programCtrl.text},
                  ));
                  Navigator.pop(context);
                },
                child: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
