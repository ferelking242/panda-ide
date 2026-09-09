import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// VS Code-style launch configuration (launch.json).
class LaunchConfig {
  final String name;
  final String type; // 'dart', 'flutter', 'node', 'python'
  final String request; // 'launch' or 'attach'
  final Map<String, dynamic> args;
  final List<LaunchConfig> compounds;

  const LaunchConfig({
    required this.name,
    required this.type,
    this.request = 'launch',
    this.args = const {},
    this.compounds = const [],
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'request': request,
        ...args,
        if (compounds.isNotEmpty)
          'compounds': compounds.map((c) => c.toJson()).toList(),
      };

  factory LaunchConfig.fromJson(Map<String, dynamic> json) {
    return LaunchConfig(
      name: json['name'] ?? 'Unnamed',
      type: json['type'] ?? 'dart',
      request: json['request'] ?? 'launch',
      args: Map.from(json)
        ..remove('name')
        ..remove('type')
        ..remove('request')
        ..remove('compounds'),
      compounds: (json['compounds'] as List<dynamic>?)
              ?.map((c) => LaunchConfig.fromJson(c))
              .toList() ??
          [],
    );
  }
}

/// Manages launch.json for a workspace.
class LaunchConfigManager {
  final String workspacePath;

  LaunchConfigManager(this.workspacePath);

  File get _launchFile => File(p.join(workspacePath, '.vscode', 'launch.json'));

  Future<List<LaunchConfig>> load() async {
    if (!await _launchFile.exists()) return [];
    try {
      final content = await _launchFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final configs = json['configurations'] as List<dynamic>? ?? [];
      return configs.map((c) => LaunchConfig.fromJson(c)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<LaunchConfig> configs) async {
    final dir = _launchFile.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final json = {
      'version': '0.2.0',
      'configurations': configs.map((c) => c.toJson()).toList(),
    };
    await _launchFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
    );
  }

  Future<void> addConfig(LaunchConfig config) async {
    final configs = await load();
    configs.add(config);
    await save(configs);
  }

  Future<void> removeConfig(int index) async {
    final configs = await load();
    if (index >= 0 && index < configs.length) {
      configs.removeAt(index);
      await save(configs);
    }
  }

  /// Default Flutter launch config.
  static LaunchConfig defaultFlutter({String? program}) {
    return LaunchConfig(
      name: 'Flutter (main.dart)',
      type: 'flutter',
      request: 'launch',
      args: {
        'program': program ?? 'lib/main.dart',
        'flutterMode': 'debug',
      },
    );
  }

  /// Default Dart launch config.
  static LaunchConfig defaultDart({String? program}) {
    return LaunchConfig(
      name: 'Dart (main.dart)',
      type: 'dart',
      request: 'launch',
      args: {
        'program': program ?? 'lib/main.dart',
      },
    );
  }
}
