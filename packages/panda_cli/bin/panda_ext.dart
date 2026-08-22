#!/usr/bin/env dart
/// panda ext — CLI tool for managing Panda IDE extensions.
///
/// Usage:
///   panda_ext create <name>       Create a new extension
///   panda_ext dev <path>          Run extension in dev mode
///   panda_ext test <path>         Run extension tests
///   panda_ext package <path>      Package extension as .panda
///   panda_ext list                List installed extensions
///   panda_ext info <id>           Show extension info
///
/// Examples:
///   panda_ext create my-extension
///   panda_ext package ./my-extension
import 'dart:io';

import 'package:path/path.dart' as p;

void main(List<String> args) {
  if (args.isEmpty) {
    _printUsage();
    exit(0);
  }

  final command = args[0];
  final rest = args.sublist(1);

  switch (command) {
    case 'create':
      _createExtension(rest);
      break;
    case 'dev':
      _devExtension(rest);
      break;
    case 'test':
      _testExtension(rest);
      break;
    case 'package':
      _packageExtension(rest);
      break;
    case 'list':
      _listExtensions();
      break;
    case 'info':
      _infoExtension(rest);
      break;
    default:
      print('Unknown command: $command');
      _printUsage();
      exit(1);
  }
}

void _printUsage() {
  print('''
🐼 Panda IDE Extension CLI

Usage: panda_ext <command> [options]

Commands:
  create <name>           Create a new extension scaffold
  dev <path>              Run extension in development mode
  test <path>             Run extension tests
  package <path>          Package extension as .panda file
  list                    List installed extensions
  info <id>               Show extension info

Examples:
  panda_ext create my-extension
  panda_ext dev ./my-extension
  panda_ext package ./my-extension
''');
}

void _createExtension(List<String> args) {
  if (args.isEmpty) {
    print('Usage: panda_ext create <name>');
    exit(1);
  }

  final name = args[0];
  final dir = Directory(name);

  if (dir.existsSync()) {
    print('Directory $name already exists');
    exit(1);
  }

  final id = 'com.example.${name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-')}';

  // Create directory structure
  dir.createSync(recursive: true);
  Directory(p.join(name, 'lib')).createSync();
  Directory(p.join(name, 'assets', 'icons')).createSync();
  Directory(p.join(name, 'assets', 'themes')).createSync();
  Directory(p.join(name, 'assets', 'snippets')).createSync();
  Directory(p.join(name, 'tests')).createSync();

  // Create panda.yaml
  File(p.join(name, 'panda.yaml')).writeAsStringSync('''
# panda.yaml — Extension manifest for Panda IDE
# Format: panda-v1

id: $id
name: $name
version: "0.1.0"
author: "Your Name"
description: |
  A new Panda IDE extension.
license: MIT

# Compatibility
panda:
  min_version: "1.0.0"
  platforms:
    - android
    - linux
    - macos
    - windows

# Activation
activation:
  events:
    - on_startup

# Contributions
contributes:
  commands:
    - id: ${id}.hello
      title: "${name}: Say Hello"
      keybinding: "ctrl+shift+h"

  # views:
  #   sidebar:
  #     - id: ${name}.panel
  #       name: "My Panel"
  #       widget: "views/my_panel.dart"

  # themes:
  #   - id: ${name}-dark
  #     name: "${name} Dark"
  #     type: dark
  #     file: "assets/themes/dark.yaml"

  configuration:
    ${name}.enabled:
      type: boolean
      default: true
      description: "Enable ${name}"
''');

  // Create extension.dart
  File(p.join(name, 'lib', 'extension.dart')).writeAsStringSync('''
import 'package:panda_sdk/panda_sdk.dart';

/// $name — Panda IDE Extension
class ${_toClassName(name)}Extension extends PandaExtension {
  @override
  String get id => '$id';

  @override
  String get name => '$name';

  @override
  Future<void> onActivate(ExtensionContext context) async {
    // Register commands
    context.commands.register('${id}.hello', (args) async {
      await context.window.showInformation('Hello from $name! 🐼');
    });

    context.logger.info('$name activated');
  }

  @override
  Future<void> onDeactivate() async {
    // Cleanup
  }
}

String _toClassName(String name) {
  return name
      .split(RegExp(r'[-_]'))
      .map((s) => s[0].toUpperCase() + s.substring(1))
      .join();
}
''');

  // Create pubspec.yaml
  File(p.join(name, 'pubspec.yaml')).writeAsStringSync('''
name: ${name.replaceAll('-', '_')}
description: $name — Panda IDE Extension
version: 0.1.0

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  panda_sdk:
    path: ../panda_sdk

dev_dependencies:
  test: ^1.24.0
''');

  // Create README.md
  File(p.join(name, 'README.md')).writeAsStringSync('''
# $name

A Panda IDE extension.

## Development

```bash
# Run in dev mode
panda_ext dev .

# Run tests
panda_ext test .

# Package
panda_ext package .
```

## Install

```bash
panda_ext install $name
```
''');

  print('✅ Created extension: $name');
  print('   Directory: ${p.absolute(name)}');
  print('   Manifest: ${p.join(name, "panda.yaml")}');
  print('   Entry:    ${p.join(name, "lib", "extension.dart")}');
  print('');
  print('Next steps:');
  print('  cd $name');
  print('  panda_ext dev .');
}

void _devExtension(List<String> args) {
  final dir = args.isNotEmpty ? args[0] : '.';
  final yamlPath = p.join(dir, 'panda.yaml');

  if (!File(yamlPath).existsSync()) {
    print('No panda.yaml found in $dir');
    exit(1);
  }

  print('🔨 Development mode for $dir');
  print('   Watching for changes...');
  print('   Press Ctrl+C to stop');

  // Watch for file changes and reload
  final watcher = Directory(dir).watch(recursive: true);
  watcher.listen((event) {
    if (event.path.endsWith('.dart') || event.path.endsWith('.yaml')) {
      print('   🔄 Change detected: ${p.basename(event.path)}');
    }
  });
}

void _testExtension(List<String> args) {
  final dir = args.isNotEmpty ? args[0] : '.';
  print('🧪 Running tests for $dir...');

  // Run dart test in the extension directory
  final result = Process.runSync('dart', ['test'], workingDirectory: dir);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exit(result.exitCode);
}

void _packageExtension(List<String> args) {
  final dir = args.isNotEmpty ? args[0] : '.';
  final yamlPath = p.join(dir, 'panda.yaml');

  if (!File(yamlPath).existsSync()) {
    print('No panda.yaml found in $dir');
    exit(1);
  }

  // Read manifest for name and version
  final content = File(yamlPath).readAsStringSync();
  final nameMatch = RegExp(r'^name:\s*(.+)', multiLine: true).firstMatch(content);
  final versionMatch =
      RegExp(r'^version:\s*["\']?(.+?)["\']?\s*$', multiLine: true)
          .firstMatch(content);

  final name = nameMatch?.group(1)?.trim() ?? 'extension';
  final version = versionMatch?.group(1)?.trim() ?? '0.0.0';
  final outputName = '$name-$version.panda';

  print('📦 Packaging $name@$version...');

  // Create .panda archive
  final result = Process.runSync(
    'zip',
    ['-r', '-x', '*.git*', '-x', '*.dart_tool*', '-x', 'build/*'],
    [outputName, '.'],
    workingDirectory: dir,
  );

  if (result.exitCode == 0) {
    print('✅ Created: $outputName');
    final file = File(p.join(dir, outputName));
    print('   Size: ${(file.lengthSync() / 1024).toStringAsFixed(1)} KB');
  } else {
    print('❌ Package failed');
    stderr.write(result.stderr);
    exit(1);
  }
}

void _listExtensions() {
  final home = Platform.environment['HOME'] ?? '~';
  final extDir = Directory(p.join(home, '.panda', 'extensions'));

  if (!extDir.existsSync()) {
    print('No extensions directory found');
    return;
  }

  print('📦 Installed Extensions:\n');

  var count = 0;
  for (final entity in extDir.listSync()) {
    if (entity is! Directory) continue;
    count++;

    final name = p.basename(entity.path);
    final pandaYaml = File(p.join(entity.path, 'panda.yaml'));
    final packageJson = File(p.join(entity.path, 'package.json'));

    if (pandaYaml.existsSync()) {
      print('  🐼 $name (.panda)');
    } else if (packageJson.existsSync()) {
      print('  🔧 $name (.vsix)');
    } else {
      print('  ❓ $name (unknown)');
    }
  }

  if (count == 0) {
    print('  No extensions installed');
  }
}

void _infoExtension(List<String> args) {
  if (args.isEmpty) {
    print('Usage: panda_ext info <extension-id>');
    exit(1);
  }

  final id = args[0];
  final home = Platform.environment['HOME'] ?? '~';
  final extDir = Directory(p.join(home, '.panda', 'extensions'));

  if (!extDir.existsSync()) {
    print('No extensions directory found');
    exit(1);
  }

  // Search for the extension
  for (final entity in extDir.listSync()) {
    if (entity is! Directory) continue;

    final pandaYaml = File(p.join(entity.path, 'panda.yaml'));
    if (pandaYaml.existsSync()) {
      final content = pandaYaml.readAsStringSync();
      if (content.contains('id: $id')) {
        print('Extension: $id');
        print('Path: ${entity.path}');
        print('');
        print(content);
        return;
      }
    }
  }

  print('Extension not found: $id');
  exit(1);
}
