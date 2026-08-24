/// Panda YAML manifest parser for .panda extensions.
///
/// Parses `panda.yaml` — the manifest format for native Dart extensions.
import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';

library;



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
    Map<String, dynamic> doc;
    try {
      final loaded = loadYaml(yaml);
      doc = loaded is YamlMap ? _yamlToMap(loaded) : <String, dynamic>{};
    } catch (_) {
      doc = <String, dynamic>{};
    }
    // Fallback : mini-parser maison si le vrai YAML échoue ou rend vide.
    if (doc.isEmpty) {
      try {
        doc = _parseYaml(yaml);
      } catch (_) {
        doc = <String, dynamic>{};
      }
    }
    return PandaManifest(
      id: doc['id'] ?? '',
      name: doc['name'] ?? '',
      version: doc['version'] ?? '0.0.0',
      author: _asStr(doc['author']),
      description: _asStr(doc['description']),
      license: _asStr(doc['license']),
      repository: _asStr(doc['repository']),
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
        minVersion: _asStr(m['min_version']),
        maxVersion: _asStr(m['max_version']),
        platforms: _toStringList(m['platforms']),
        dartSdk: _asStr(m['dart_sdk']),
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
  // ── Événements d'activation façon VS Code ────────────────────────────
  /// `*` / onStartup / onStartupFinished : l'extension démarre avec l'IDE.
  bool get wantsStartup =>
      events.contains('*') ||
      events.contains('onStartup') ||
      events.contains('onStartupFinished');

  /// `onCommand:<id>` — palette, keybinding, menus, status bar…
  bool matchesCommand(String commandId) =>
      wantsStartup || events.contains('onCommand:$commandId');

  /// `onLanguage:<id>` — ouverture d'un fichier de ce langage.
  bool matchesLanguage(String languageId) =>
      wantsStartup || events.contains('onLanguage:$languageId');

  /// `onView:<id>` — la vue sidebar/panel devient visible.
  bool matchesView(String viewId) =>
      wantsStartup || events.contains('onView:$viewId');
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
  // ── VS Code parity: debuggers, authentication, tasks, problems, notebooks, chat, MCP ──
  final List<DebuggerContribution> debuggers;
  final List<AuthContribution> authentication;
  final List<TaskContribution> taskDefinitions;
  final List<ProblemPatternContribution> problemPatterns;
  final List<NotebookContribution> notebooks;
  final List<ChatParticipantContribution> chatParticipants;
  final List<LanguageModelToolContribution> languageModelTools;
  final List<McpServerContribution> mcpServers;

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
    this.debuggers = const [],
    this.authentication = const [],
    this.taskDefinitions = const [],
    this.problemPatterns = const [],
    this.notebooks = const [],
    this.chatParticipants = const [],
    this.languageModelTools = const [],
    this.mcpServers = const [],
  });

  factory ContributedFeatures.fromMap(Map<String, dynamic> m) =>
      ContributedFeatures(
        commands: _asList(m['commands'])
            .map((c) => CommandContribution.fromMap(_asMap(c)))
            .toList(),
        sidebarViews: _asList(_asMap(m['views'])['sidebar'])
            .map((v) => ViewContribution.fromMap(_asMap(v)))
            .toList(),
        panelViews: _asList(_asMap(m['views'])['panel'])
            .map((v) => ViewContribution.fromMap(_asMap(v)))
            .toList(),
        themes: _asList(m['themes'])
            .map((t) => ThemeContribution.fromMap(_asMap(t)))
            .toList(),
        languages: _asList(m['languages'])
            .map((l) => LanguageContribution.fromMap(_asMap(l)))
            .toList(),
        snippets: _asList(m['snippets'])
            .map((s) => SnippetContribution.fromMap(_asMap(s)))
            .toList(),
        keybindings: _asList(m['keybindings'])
            .map((k) => KeybindingContribution.fromMap(_asMap(k)))
            .toList(),
        menus: _asMap(m['menus']).entries
                .map((e) => MenuContribution.fromMap(
                    {'position': e.key.toString(), 'command': ''}))
                .toList(),
        configuration: m['configuration'] == null
            ? []
            : _parseConfigProperties(_asMap(m['configuration'])),
        icons: _asList(_asMap(m['icons'])['activity_bar'])
            .map((i) => IconContribution.fromMap(_asMap(i)))
            .toList(),
        listeners: _asList(m['listeners'])
            .map((l) => ListenerContribution.fromMap(_asMap(l)))
            .toList(),
        services: _asList(m['services'])
            .map((s) => ServiceContribution.fromMap(_asMap(s)))
            .toList(),
        webviews: _asList(m['webviews'])
            .map((w) => WebviewContribution.fromMap(_asMap(w)))
            .toList(),
        debuggers: _asList(m['debuggers'])
            .map((d) => DebuggerContribution.fromMap(_asMap(d)))
            .toList(),
        authentication: _asList(m['authentication'])
            .map((a) => AuthContribution.fromMap(_asMap(a)))
            .toList(),
        taskDefinitions: _asList(m['taskDefinitions'])
            .map((t) => TaskContribution.fromMap(_asMap(t)))
            .toList(),
        problemPatterns: _asList(m['problemPatterns'])
            .map((p) => ProblemPatternContribution.fromMap(_asMap(p)))
            .toList(),
        notebooks: _asList(m['notebooks'])
            .map((n) => NotebookContribution.fromMap(_asMap(n)))
            .toList(),
        chatParticipants: _asList(m['chatParticipants'])
            .map((c) => ChatParticipantContribution.fromMap(_asMap(c)))
            .toList(),
        languageModelTools: _asList(m['languageModelTools'])
            .map((t) => LanguageModelToolContribution.fromMap(_asMap(t)))
            .toList(),
        mcpServers: _asList(_asMap(m['mcp'])['servers'])
            .map((s) => McpServerContribution.fromMap(_asMap(s)))
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
        if (debuggers.isNotEmpty)
          'debuggers': debuggers.map((d) => d.toMap()).toList(),
        if (authentication.isNotEmpty)
          'authentication': authentication.map((a) => a.toMap()).toList(),
        if (taskDefinitions.isNotEmpty)
          'taskDefinitions': taskDefinitions.map((t) => t.toMap()).toList(),
        if (problemPatterns.isNotEmpty)
          'problemPatterns': problemPatterns.map((p) => p.toMap()).toList(),
        if (notebooks.isNotEmpty)
          'notebooks': notebooks.map((n) => n.toMap()).toList(),
        if (chatParticipants.isNotEmpty)
          'chatParticipants': chatParticipants.map((c) => c.toMap()).toList(),
        if (languageModelTools.isNotEmpty)
          'languageModelTools': languageModelTools.map((t) => t.toMap()).toList(),
        if (mcpServers.isNotEmpty)
          'mcp': {'servers': mcpServers.map((s) => s.toMap()).toList()},
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
        id: _asStr(m['id']) ?? '',
        title: _asStr(m['title']) ?? '',
        category: _asStr(m['category']),
        icon: _asStr(m['icon']),
        keybinding: _asStr(m['keybinding']),
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
        id: _asStr(m['id']) ?? '',
        name: _asStr(m['name']) ?? '',
        icon: _asStr(m['icon']),
        widget: _asStr(m['widget']),
        defaultVisible: _asBool(m['default_visible']),
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
        id: _asStr(m['id']) ?? '',
        name: _asStr(m['name']) ?? '',
        type: _asStr(m['type']) ?? 'dark',
        file: _asStr(m['file']),
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
        grammar: _asStr(m['grammar']),
        autocomplete: _asBool(m['autocomplete']),
        linting: _asBool(m['linting']),
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
        language: _asStr(m['language']) ?? '',
        file: _asStr(m['file']) ?? '',
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
        key: _asStr(m['key']) ?? '',
        command: _asStr(m['command']) ?? '',
        when: _asStr(m['when']),
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
        position: _asStr(m['position']) ?? '',
        command: _asStr(m['command']) ?? '',
        when: _asStr(m['when']),
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
        type: _asStr(m['type']) ?? 'string',
        defaultValue: m['default'],
        description: _asStr(m['description']),
        secret: _asBool(m['secret']),
        min: _asInt(m['min']),
        max: _asInt(m['max']),
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
        id: _asStr(m['id']) ?? '',
        name: _asStr(m['name']) ?? '',
        icon: _asStr(m['icon']) ?? '',
        position: _asStr(m['position']),
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
        event: _asStr(m['event']) ?? '',
        handler: _asStr(m['handler']) ?? '',
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
        id: _asStr(m['id']) ?? '',
        type: _asStr(m['type']) ?? 'background',
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
        id: _asStr(m['id']) ?? '',
        title: _asStr(m['title']) ?? '',
        icon: _asStr(m['icon']),
        contentType: _asStr(m['content_type']) ?? 'flutter',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        if (icon != null) 'icon': icon,
        'content_type': contentType,
      };
}

// ── VS Code parity contribution types ──────────────────────────────

class DebuggerContribution {
  final String type;
  final String label;
  final String? program;
  final Map<String, dynamic>? configurationAttributes;
  const DebuggerContribution({required this.type, required this.label, this.program, this.configurationAttributes});
  factory DebuggerContribution.fromMap(Map<String, dynamic> m) => DebuggerContribution(
    type: _asStr(m['type']) ?? '', label: _asStr(m['label']) ?? '',
    program: _asStr(m['program']), configurationAttributes: m['configurationAttributes'] as Map<String, dynamic>?,
  );
  Map<String, dynamic> toMap() => {'type': type, 'label': label, if (program != null) 'program': program};
}

class AuthContribution {
  final String id;
  final String label;
  const AuthContribution({required this.id, required this.label});
  factory AuthContribution.fromMap(Map<String, dynamic> m) => AuthContribution(id: _asStr(m['id']) ?? '', label: _asStr(m['label']) ?? '');
  Map<String, dynamic> toMap() => {'id': id, 'label': label};
}

class TaskContribution {
  final String type;
  final String? required;
  const TaskContribution({required this.type, this.required});
  factory TaskContribution.fromMap(Map<String, dynamic> m) => TaskContribution(type: _asStr(m['type']) ?? '', required: _asStr(m['required']));
  Map<String, dynamic> toMap() => {'type': type};
}

class ProblemPatternContribution {
  final String name;
  final String? regex;
  const ProblemPatternContribution({required this.name, this.regex});
  factory ProblemPatternContribution.fromMap(Map<String, dynamic> m) => ProblemPatternContribution(name: _asStr(m['name']) ?? '', regex: _asStr(m['regex']));
  Map<String, dynamic> toMap() => {'name': name};
}

class NotebookContribution {
  final String type;
  final String displayName;
  const NotebookContribution({required this.type, required this.displayName});
  factory NotebookContribution.fromMap(Map<String, dynamic> m) => NotebookContribution(type: _asStr(m['type']) ?? '', displayName: _asStr(m['displayName']) ?? '');
  Map<String, dynamic> toMap() => {'type': type, 'displayName': displayName};
}

class ChatParticipantContribution {
  final String id;
  final String name;
  final String? description;
  const ChatParticipantContribution({required this.id, required this.name, this.description});
  factory ChatParticipantContribution.fromMap(Map<String, dynamic> m) => ChatParticipantContribution(
    id: _asStr(m['id']) ?? '', name: _asStr(m['name']) ?? '', description: _asStr(m['description']),
  );
  Map<String, dynamic> toMap() => {'id': id, 'name': name};
}

class LanguageModelToolContribution {
  final String id;
  final String name;
  final String? description;
  const LanguageModelToolContribution({required this.id, required this.name, this.description});
  factory LanguageModelToolContribution.fromMap(Map<String, dynamic> m) => LanguageModelToolContribution(
    id: _asStr(m['id']) ?? '', name: _asStr(m['name']) ?? '', description: _asStr(m['description']),
  );
  Map<String, dynamic> toMap() => {'id': id, 'name': name};
}

class McpServerContribution {
  final String id;
  final String type;
  final String? command;
  final List<String> args;
  final Map<String, String>? env;
  const McpServerContribution({required this.id, required this.type, this.command, this.args = const [], this.env});
  factory McpServerContribution.fromMap(Map<String, dynamic> m) => McpServerContribution(
    id: _asStr(m['id']) ?? '', type: _asStr(m['type']) ?? 'stdio',
    command: _asStr(m['command']),
    args: _toStringList(m['args']),
    env: m['env'] != null ? Map<String, String>.from(m['env'] as Map) : null,
  );
  Map<String, dynamic> toMap() => {'id': id, 'type': type, if (command != null) 'command': command, 'args': args};
}

// ═══════════════════════════════════════════════════════════════
// Helpers — Minimal YAML parser (no external deps)
// ═══════════════════════════════════════════════════════════════

// ── Conversions sûres (YamlMap / dynamic → types Dart) ──────────────

Map<String, dynamic> _yamlToMap(YamlMap y) => {
      for (final e in y.entries) e.key.toString(): _convertYaml(e.value),
    };

dynamic _convertYaml(dynamic v) {
  if (v is YamlMap) return _yamlToMap(v);
  if (v is YamlList) return [for (final i in v) _convertYaml(i)];
  return v;
}

String? _asStr(dynamic v) =>
    v == null ? null : (v is String ? v : v.toString());

List<dynamic> _asList(dynamic v) =>
    v is List ? v : const [];

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return {for (final e in v.entries) e.key.toString(): e.value};
  return <String, dynamic>{};
}

bool _asBool(dynamic v, [bool def = false]) => v is bool ? v : def;

int? _asInt(dynamic v) => v is int
    ? v
    : v is num
        ? v.toInt()
        : int.tryParse(v?.toString() ?? '');

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
  final props = _asMap(m['properties']);
  final source = props.isNotEmpty ? props : m;
  return [
    for (final e in source.entries)
      if (e.key.toString() != 'properties')
        ConfigContribution.fromMap(e.key.toString(), _asMap(e.value)),
  ];
}
