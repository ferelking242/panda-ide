/// Panda YAML manifest parser for .panda extensions.
///
/// Parses `panda.yaml` — the manifest format for native Dart extensions.
library;

import 'dart:convert';
import 'dart:io';

/// Parsed panda.yaml manifest.
class PandaManifest {
  final String id;
  final String name;
  final String version;
  final String? author;
  final String? description;
  final String? license;
  final String? repository;
  final PandaCompatibility compatibility;
  final ActivationConfig activation;
  final ContributedFeatures contributes;
  final List<String> permissions;

  const PandaManifest({
    required this.id,
    required this.name,
    required this.version,
    this.author,
    this.description,
    this.license,
    this.repository,
    this.compatibility = const PandaCompatibility(),
    this.activation = const ActivationConfig(),
    this.contributes = const ContributedFeatures(),
    this.permissions = const [],
  });

  /// Parse from a panda.yaml file.
  static Future<PandaManifest> fromFile(String path) async {
    final content = await File(path).readAsString();
    return parse(content);
  }

  /// Parse from YAML string (simplified parser — no dependency needed).
  static PandaManifest parse(String yaml) {
    final doc = _parseYaml(yaml);
    return PandaManifest(
      id: doc['id'] ?? '',
      name: doc['name'] ?? '',
      version: doc['version'] ?? '0.0.0',
      author: doc['author'],
      description: doc['description'],
      license: doc['license'],
      repository: doc['repository'],
      compatibility: PandaCompatibility.fromMap(doc['panda'] ?? {}),
      activation: ActivationConfig.fromMap(doc['activation'] ?? {}),
      contributes: ContributedFeatures.fromMap(doc['contributes'] ?? {}),
      permissions: _toStringList(doc['permissions']),
    );
  }

  /// Convert to JSON (for the extension host).
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'author': author,
        'description': description,
        'license': license,
        'repository': repository,
        'panda': compatibility.toMap(),
        'activation': activation.toMap(),
        'contributes': contributes.toMap(),
        'permissions': permissions,
      };

  @override
  String toString() => 'PandaManifest($id@$version)';
}

/// Compatibility constraints.
class PandaCompatibility {
  final String? minVersion;
  final String? maxVersion;
  final List<String> platforms;
  final String? dartSdk;

  const PandaCompatibility({
    this.minVersion,
    this.maxVersion,
    this.platforms = const ['android', 'linux', 'macos', 'windows', 'ios'],
    this.dartSdk,
  });

  factory PandaCompatibility.fromMap(Map<String, dynamic> m) =>
      PandaCompatibility(
        minVersion: m['min_version'],
        maxVersion: m['max_version'],
        platforms: _toStringList(m['platforms']),
        dartSdk: m['dart_sdk'],
      );

  Map<String, dynamic> toMap() => {
        if (minVersion != null) 'min_version': minVersion,
        if (maxVersion != null) 'max_version': maxVersion,
        'platforms': platforms,
        if (dartSdk != null) 'dart_sdk': dartSdk,
      };
}

/// Activation configuration.
class ActivationConfig {
  final List<String> events;
  final bool eager;

  const ActivationConfig({
    this.events = const [],
    this.eager = false,
  });

  factory ActivationConfig.fromMap(Map<String, dynamic> m) =>
      ActivationConfig(
        events: _toStringList(m['events']),
        eager: m['eager'] ?? false,
      );

  Map<String, dynamic> toMap() => {
        'events': events,
        'eager': eager,
      };

  bool get onStartup => events.contains('on_startup');
  bool get isLazy => !eager && !onStartup;

  /// Check if this extension should activate for a given event.
  bool shouldActivate(String event) {
    if (eager || onStartup) return true;
    return events.any((e) => e == event || event.startsWith('$e:'));
  }
}

/// All contribution points.
class ContributedFeatures {
  final List<CommandContribution> commands;
  final List<ViewContribution> sidebarViews;
  final List<ViewContribution> panelViews;
  final List<ThemeContribution> themes;
  final List<LanguageContribution> languages;
  final List<SnippetContribution> snippets;
  final List<KeybindingContribution> keybindings;
  final List<MenuContribution> menus;
  final List<ConfigContribution> configuration;
  final List<IconContribution> icons;
  final List<ListenerContribution> listeners;
  final List<ServiceContribution> services;
  final List<WebviewContribution> webviews;

  const ContributedFeatures({
    this.commands = const [],
    this.sidebarViews = const [],
    this.panelViews = const [],
    this.themes = const [],
    this.languages = const [],
    this.snippets = const [],
    this.keybindings = const [],
    this.menus = const [],
    this.configuration = const [],
    this.icons = const [],
    this.listeners = const [],
    this.services = const [],
    this.webviews = const [],
  });

  factory ContributedFeatures.fromMap(Map<String, dynamic> m) =>
      ContributedFeatures(
        commands: (m['commands'] as List? ?? [])
            .map((c) => CommandContribution.fromMap(c))
            .toList(),
        sidebarViews: (m['views'] is Map
                ? (m['views']['sidebar'] as List? ?? [])
                : [])
            .map((v) => ViewContribution.fromMap(v))
            .toList(),
        panelViews: (m['views'] is Map
                ? (m['views']['panel'] as List? ?? [])
                : [])
            .map((v) => ViewContribution.fromMap(v))
            .toList(),
        themes: (m['themes'] as List? ?? [])
            .map((t) => ThemeContribution.fromMap(t))
            .toList(),
        languages: (m['languages'] as List? ?? [])
            .map((l) => LanguageContribution.fromMap(l))
            .toList(),
        snippets: (m['snippets'] as List? ?? [])
            .map((s) => SnippetContribution.fromMap(s))
            .toList(),
        keybindings: (m['keybindings'] as List? ?? [])
            .map((k) => KeybindingContribution.fromMap(k))
            .toList(),
        menus: (m['menus'] is Map
                ? (m['menus'] as Map).entries
                    .map((e) => MenuContribution.fromMap(
                        {'position': e.key, 'items': e.value}))
                    .toList()
                : []),
        configuration: m['configuration'] is Map
            ? _parseConfigProperties(m['configuration'])
            : [],
        icons: (m['icons'] is Map
                ? (m['icons']['activity_bar'] as List? ?? [])
                : [])
            .map((i) => IconContribution.fromMap(i))
            .toList(),
        listeners: (m['listeners'] as List? ?? [])
            .map((l) => ListenerContribution.fromMap(l))
            .toList(),
        services: (m['services'] as List? ?? [])
            .map((s) => ServiceContribution.fromMap(s))
            .toList(),
        webviews: (m['webviews'] as List? ?? [])
            .map((w) => WebviewContribution.fromMap(w))
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        if (commands.isNotEmpty)
          'commands': commands.map((c) => c.toMap()).toList(),
        if (sidebarViews.isNotEmpty || panelViews.isNotEmpty)
          'views': {
            if (sidebarViews.isNotEmpty)
              'sidebar': sidebarViews.map((v) => v.toMap()).toList(),
            if (panelViews.isNotEmpty)
              'panel': panelViews.map((v) => v.toMap()).toList(),
          },
        if (themes.isNotEmpty)
          'themes': themes.map((t) => t.toMap()).toList(),
        if (languages.isNotEmpty)
          'languages': languages.map((l) => l.toMap()).toList(),
        if (keybindings.isNotEmpty)
          'keybindings': keybindings.map((k) => k.toMap()).toList(),
      };
}

/// A contributed command.
class CommandContribution {
  final String id;
  final String title;
  final String? category;
  final String? icon;
  final String? keybinding;

  const CommandContribution({
    required this.id,
    required this.title,
    this.category,
    this.icon,
    this.keybinding,
  });

  factory CommandContribution.fromMap(Map<String, dynamic> m) =>
      CommandContribution(
        id: m['id'] ?? '',
        title: m['title'] ?? '',
        category: m['category'],
        icon: m['icon'],
        keybinding: m['keybinding'],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        if (category != null) 'category': category,
        if (icon != null) 'icon': icon,
        if (keybinding != null) 'keybinding': keybinding,
      };
}

/// A contributed view.
class ViewContribution {
  final String id;
  final String name;
  final String? icon;
  final String? widget;
  final bool defaultVisible;

  const ViewContribution({
    required this.id,
    required this.name,
    this.icon,
    this.widget,
    this.defaultVisible = false,
  });

  factory ViewContribution.fromMap(Map<String, dynamic> m) =>
      ViewContribution(
        id: m['id'] ?? '',
        name: m['name'] ?? '',
        icon: m['icon'],
        widget: m['widget'],
        defaultVisible: m['default_visible'] ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (icon != null) 'icon': icon,
        if (widget != null) 'widget': widget,
        'default_visible': defaultVisible,
      };
}

/// A contributed theme.
class ThemeContribution {
  final String id;
  final String name;
  final String type;
  final String? file;

  const ThemeContribution({
    required this.id,
    required this.name,
    this.type = 'dark',
    this.file,
  });

  factory ThemeContribution.fromMap(Map<String, dynamic> m) =>
      ThemeContribution(
        id: m['id'] ?? '',
        name: m['name'] ?? '',
        type: m['type'] ?? 'dark',
        file: m['file'],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        if (file != null) 'file': file,
      };
}

/// A contributed language.
class LanguageContribution {
  final String id;
  final String name;
  final List<String> extensions;
  final String? grammar;
  final bool autocomplete;
  final bool linting;

  const LanguageContribution({
    required this.id,
    required this.name,
    this.extensions = const [],
    this.grammar,
    this.autocomplete = false,
    this.linting = false,
  });

  factory LanguageContribution.fromMap(Map<String, dynamic> m) =>
      LanguageContribution(
        id: m['id'] ?? '',
        name: m['name'] ?? '',
        extensions: _toStringList(m['extensions']),
        grammar: m['grammar'],
        autocomplete: m['autocomplete'] ?? false,
        linting: m['linting'] ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'extensions': extensions,
        if (grammar != null) 'grammar': grammar,
        'autocomplete': autocomplete,
        'linting': linting,
      };
}

/// A contributed snippet.
class SnippetContribution {
  final String language;
  final String file;

  const SnippetContribution({required this.language, required this.file});

  factory SnippetContribution.fromMap(Map<String, dynamic> m) =>
      SnippetContribution(
        language: m['language'] ?? '',
        file: m['file'] ?? '',
      );

  Map<String, dynamic> toMap() => {'language': language, 'file': file};
}

/// A contributed keybinding.
class KeybindingContribution {
  final String key;
  final String command;
  final String? when;

  const KeybindingContribution({
    required this.key,
    required this.command,
    this.when,
  });

  factory KeybindingContribution.fromMap(Map<String, dynamic> m) =>
      KeybindingContribution(
        key: m['key'] ?? '',
        command: m['command'] ?? '',
        when: m['when'],
      );

  Map<String, dynamic> toMap() => {
        'key': key,
        'command': command,
        if (when != null) 'when': when,
      };
}

/// A contributed menu item.
class MenuContribution {
  final String position;
  final String command;
  final String? when;

  const MenuContribution({
    required this.position,
    required this.command,
    this.when,
  });

  factory MenuContribution.fromMap(Map<String, dynamic> m) =>
      MenuContribution(
        position: m['position'] ?? '',
        command: m['command'] ?? '',
        when: m['when'],
      );

  Map<String, dynamic> toMap() => {
        'position': position,
        'command': command,
        if (when != null) 'when': when,
      };
}

/// A contributed configuration property.
class ConfigContribution {
  final String key;
  final String type;
  final dynamic defaultValue;
  final String? description;
  final bool secret;
  final int? min;
  final int? max;
  final List<String>? values;

  const ConfigContribution({
    required this.key,
    required this.type,
    this.defaultValue,
    this.description,
    this.secret = false,
    this.min,
    this.max,
    this.values,
  });

  factory ConfigContribution.fromMap(String key, Map<String, dynamic> m) =>
      ConfigContribution(
        key: key,
        type: m['type'] ?? 'string',
        defaultValue: m['default'],
        description: m['description'],
        secret: m['secret'] ?? false,
        min: m['min'],
        max: m['max'],
        values: _toStringList(m['values']),
      );

  Map<String, dynamic> toMap() => {
        key: {
          'type': type,
          if (defaultValue != null) 'default': defaultValue,
          if (description != null) 'description': description,
          if (secret) 'secret': true,
          if (min != null) 'min': min,
          if (max != null) 'max': max,
          if (values != null) 'values': values,
        },
      };
}

/// A contributed icon.
class IconContribution {
  final String id;
  final String name;
  final String icon;
  final String? position;

  const IconContribution({
    required this.id,
    required this.name,
    required this.icon,
    this.position,
  });

  factory IconContribution.fromMap(Map<String, dynamic> m) =>
      IconContribution(
        id: m['id'] ?? '',
        name: m['name'] ?? '',
        icon: m['icon'] ?? '',
        position: m['position'],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'icon': icon,
        if (position != null) 'position': position,
      };
}

/// A contributed event listener.
class ListenerContribution {
  final String event;
  final String handler;

  const ListenerContribution({required this.event, required this.handler});

  factory ListenerContribution.fromMap(Map<String, dynamic> m) =>
      ListenerContribution(
        event: m['event'] ?? '',
        handler: m['handler'] ?? '',
      );

  Map<String, dynamic> toMap() => {'event': event, 'handler': handler};
}

/// A contributed background service.
class ServiceContribution {
  final String id;
  final String type;
  final List<String> command;

  const ServiceContribution({
    required this.id,
    required this.type,
    this.command = const [],
  });

  factory ServiceContribution.fromMap(Map<String, dynamic> m) =>
      ServiceContribution(
        id: m['id'] ?? '',
        type: m['type'] ?? 'background',
        command: _toStringList(m['command']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'command': command,
      };
}

/// A contributed webview.
class WebviewContribution {
  final String id;
  final String title;
  final String? icon;
  final String contentType;

  const WebviewContribution({
    required this.id,
    required this.title,
    this.icon,
    this.contentType = 'flutter',
  });

  factory WebviewContribution.fromMap(Map<String, dynamic> m) =>
      WebviewContribution(
        id: m['id'] ?? '',
        title: m['title'] ?? '',
        icon: m['icon'],
        contentType: m['content_type'] ?? 'flutter',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        if (icon != null) 'icon': icon,
        'content_type': contentType,
      };
}

// ═══════════════════════════════════════════════════════════════
// Helpers — Minimal YAML parser (no external deps)
// ═══════════════════════════════════════════════════════════════

Map<String, dynamic> _parseYaml(String yaml) {
  // Simple line-by-line YAML parser for manifests.
  // Handles: key: value, key: "quoted", key: [list], key:\n  sub: value
  final result = <String, dynamic>{};
  final lines = yaml.split('\n');
  String? currentKey;
  Map<String, dynamic>? currentMap;
  List<String>? currentList;
  String? currentListKey;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimRight();

    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    final indent = line.length - line.trimLeft().length;
    final colonIdx = trimmed.indexOf(':');

    if (colonIdx < 0) {
      // Continuation of list
      if (currentList != null && currentListKey != null) {
        final value = trimmed.replaceFirst(RegExp(r'^-\s*'), '').trim();
        currentList.add(value);
      }
      continue;
    }

    final key = trimmed.substring(0, colonIdx).trim();
    final valuePart = trimmed.substring(colonIdx + 1).trim();

    if (indent == 0) {
      currentKey = key;
      currentMap = null;
      currentList = null;
      currentListKey = null;

      if (valuePart.isEmpty) {
        // Will be populated by subsequent indented lines
        result[key] = <String, dynamic>{};
        currentMap = result[key] as Map<String, dynamic>;
      } else if (valuePart.startsWith('[')) {
        // Inline list
        result[key] = _parseInlineList(valuePart);
      } else {
        result[key] = _parseValue(valuePart);
      }
    } else if (currentMap != null || currentKey != null) {
      if (indent <= 2) {
        // Sub-key under current key
        final target = currentMap ?? (result[currentKey!] = <String, dynamic>{}) as Map<String, dynamic>;
        if (currentMap == null) {
          result[currentKey!] = target;
          currentMap = target;
        }

        if (valuePart.isEmpty) {
          // Nested map
          if (key == 'sidebar' || key == 'panel' || key == 'activity_bar') {
            target[key] = <Map<String, dynamic>>[];
          } else {
            target[key] = <String, dynamic>{};
          }
        } else if (valuePart.startsWith('[')) {
          target[key] = _parseInlineList(valuePart);
        } else {
          target[key] = _parseValue(valuePart);
        }
      } else if (indent > 2) {
        // Deeper nesting
        if (currentMap != null) {
          // Check if parent value was a list
          final parentKey = currentMap!.keys.last;
          final parentValue = currentMap![parentKey];

          if (parentValue is List) {
            // Item in a list of maps
            if (parentValue.isEmpty || parentValue.last is! Map) {
              parentValue.add(<String, dynamic>{});
            }
            final lastItem = parentValue.last as Map<String, dynamic>;
            if (valuePart.isEmpty) {
              lastItem[key] = <String, dynamic>{};
            } else {
              lastItem[key] = _parseValue(valuePart);
            }
          } else if (parentValue is Map<String, dynamic>) {
            if (valuePart.isEmpty) {
              parentValue[key] = <String, dynamic>{};
            } else {
              parentValue[key] = _parseValue(valuePart);
            }
          }
        }
      }
    }
  }

  return result;
}

List<String> _parseInlineList(String s) {
  final content =
      s.substring(1, s.length - 1).trim(); // Remove [ and ]
  if (content.isEmpty) return [];
  return content.split(',').map((e) => _parseValue(e).toString()).toList();
}

dynamic _parseValue(String s) {
  if (s.isEmpty) return '';
  // Remove surrounding quotes
  if ((s.startsWith('"') && s.endsWith('"')) ||
      (s.startsWith("'") && s.endsWith("'"))) {
    return s.substring(1, s.length - 1);
  }
  if (s == 'true') return true;
  if (s == 'false') return false;
  // Try number
  final n = int.tryParse(s);
  if (n != null) return n;
  final d = double.tryParse(s);
  if (d != null) return d;
  // Strip trailing comments
  final commentIdx = s.indexOf(' #');
  if (commentIdx > 0) return s.substring(0, commentIdx).trim();
  return s;
}

List<String> _toStringList(dynamic v) {
  if (v == null) return [];
  if (v is List) return v.map((e) => e.toString()).toList();
  if (v is String) return v.isEmpty ? [] : [v];
  return [];
}

List<ConfigContribution> _parseConfigProperties(Map<String, dynamic> m) {
  final props = m['properties'];
  if (props is Map<String, dynamic>) {
    return props.entries
        .map((e) => ConfigContribution.fromMap(e.key, e.value as Map<String, dynamic>))
        .toList();
  }
  return [];
}
