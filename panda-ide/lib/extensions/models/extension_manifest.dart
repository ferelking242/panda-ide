/// Représente le package.json d'une extension VSCode.
/// Parsé depuis le .vsix extrait.
library;

class ExtensionContributes {
  final List<Map<String, dynamic>> commands;
  final List<Map<String, dynamic>> languages;
  final List<Map<String, dynamic>> grammars;
  final List<Map<String, dynamic>> snippets;
  final List<Map<String, dynamic>> themes;
  final List<Map<String, dynamic>> iconThemes;
  final List<Map<String, dynamic>> keybindings;
  final List<Map<String, dynamic>> configuration;
  final List<Map<String, dynamic>> menus;
  final List<Map<String, dynamic>> views;
  final List<Map<String, dynamic>> viewsContainers;
  final List<Map<String, dynamic>> taskDefinitions;
  final List<Map<String, dynamic>> debuggers;
  final List<Map<String, dynamic>> breakpoints;
  final List<Map<String, dynamic>> problemMatchers;

  const ExtensionContributes({
    this.commands = const [],
    this.languages = const [],
    this.grammars = const [],
    this.snippets = const [],
    this.themes = const [],
    this.iconThemes = const [],
    this.keybindings = const [],
    this.configuration = const [],
    this.menus = const [],
    this.views = const [],
    this.viewsContainers = const [],
    this.taskDefinitions = const [],
    this.debuggers = const [],
    this.breakpoints = const [],
    this.problemMatchers = const [],
  });

  factory ExtensionContributes.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> list(String key) {
      final v = json[key];
      if (v is List) return v.whereType<Map<String, dynamic>>().toList();
      if (v is Map<String, dynamic>) {
        // e.g. contributes.views is a map of viewContainer → list
        final result = <Map<String, dynamic>>[];
        v.forEach((k, items) {
          if (items is List) {
            for (final item in items) {
              if (item is Map<String, dynamic>) {
                result.add({...item, '_container': k});
              }
            }
          }
        });
        return result;
      }
      return const [];
    }

    return ExtensionContributes(
      commands: list('commands'),
      languages: list('languages'),
      grammars: list('grammars'),
      snippets: list('snippets'),
      themes: list('themes'),
      iconThemes: list('iconThemes'),
      keybindings: list('keybindings'),
      configuration: list('configuration'),
      menus: list('menus'),
      views: list('views'),
      viewsContainers: list('viewsContainers'),
      taskDefinitions: list('taskDefinitions'),
      debuggers: list('debuggers'),
      breakpoints: list('breakpoints'),
      problemMatchers: list('problemMatchers'),
    );
  }

  Map<String, dynamic> toJson() => {
    'commands': commands,
    'languages': languages,
    'grammars': grammars,
    'snippets': snippets,
    'themes': themes,
    'iconThemes': iconThemes,
    'keybindings': keybindings,
    'configuration': configuration,
    'menus': menus,
    'views': views,
    'viewsContainers': viewsContainers,
    'taskDefinitions': taskDefinitions,
    'debuggers': debuggers,
    'breakpoints': breakpoints,
    'problemMatchers': problemMatchers,
  };
}

class ExtensionActivationEvents {
  /// Liste brute des événements d'activation (ex: "onLanguage:python").
  final List<String> events;

  const ExtensionActivationEvents(this.events);

  /// L'extension s'active au démarrage.
  bool get activatesOnStartup =>
      events.contains('*') || events.contains('onStartupFinished');

  /// L'extension s'active pour ce langage.
  bool activatesForLanguage(String languageId) =>
      events.contains('*') ||
      events.contains('onLanguage:$languageId') ||
      events.contains('onStartupFinished');

  /// L'extension s'active pour cette commande.
  bool activatesForCommand(String commandId) =>
      events.contains('*') ||
      events.contains('onCommand:$commandId');
}

/// Modèle complet du package.json d'une extension VSCode.
class ExtensionManifest {
  final String id; // "{publisher}.{name}"
  final String name;
  final String publisher;
  final String displayName;
  final String description;
  final String version;
  final String? main;   // Entry point Node.js
  final String? browser; // Entry point Web Worker
  final String? icon;
  final List<String> categories;
  final List<String> keywords;
  final String? repository;
  final String? homepage;
  final Map<String, String> engines; // { "vscode": "^1.80.0" }
  final ExtensionActivationEvents activationEvents;
  final ExtensionContributes contributes;
  final List<String> extensionDependencies;
  final Map<String, dynamic> raw; // package.json complet

  const ExtensionManifest({
    required this.id,
    required this.name,
    required this.publisher,
    required this.displayName,
    required this.description,
    required this.version,
    this.main,
    this.browser,
    this.icon,
    this.categories = const [],
    this.keywords = const [],
    this.repository,
    this.homepage,
    this.engines = const {},
    required this.activationEvents,
    required this.contributes,
    this.extensionDependencies = const [],
    required this.raw,
  });

  factory ExtensionManifest.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? 'unknown';
    final publisher = json['publisher'] as String? ?? 'unknown';

    List<String> strings(String key) {
      final v = json[key];
      if (v is List) return v.whereType<String>().toList();
      return const [];
    }

    Map<String, String> strMap(String key) {
      final v = json[key];
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), val.toString()));
      }
      return const {};
    }

    return ExtensionManifest(
      id: '$publisher.$name',
      name: name,
      publisher: publisher,
      displayName: json['displayName'] as String? ?? name,
      description: json['description'] as String? ?? '',
      version: json['version'] as String? ?? '0.0.0',
      main: json['main'] as String?,
      browser: json['browser'] as String?,
      icon: json['icon'] as String?,
      categories: strings('categories'),
      keywords: strings('keywords'),
      repository: (json['repository'] is Map)
          ? (json['repository'] as Map)['url'] as String?
          : json['repository'] as String?,
      homepage: json['homepage'] as String?,
      engines: strMap('engines'),
      activationEvents: ExtensionActivationEvents(
        strings('activationEvents'),
      ),
      contributes: json['contributes'] is Map<String, dynamic>
          ? ExtensionContributes.fromJson(
              json['contributes'] as Map<String, dynamic>)
          : const ExtensionContributes(),
      extensionDependencies: strings('extensionDependencies'),
      raw: json,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'publisher': publisher,
    'displayName': displayName,
    'description': description,
    'version': version,
    if (main != null) 'main': main,
    if (browser != null) 'browser': browser,
    if (icon != null) 'icon': icon,
    'categories': categories,
    'keywords': keywords,
    if (repository != null) 'repository': repository,
    if (homepage != null) 'homepage': homepage,
    'engines': engines,
    'activationEvents': activationEvents.events,
    'contributes': contributes.toJson(),
    'extensionDependencies': extensionDependencies,
  };

  /// Vérifie si cette extension nécessite des binaires natifs (.node files).
  /// Ces extensions ne peuvent pas tourner sur Android ARM64.
  bool get requiresNativeBinaries =>
      raw['nativeDependencies'] != null ||
      (raw['dependencies'] as Map?)?.keys
          .any((k) => k.toString().contains('-native')) ==
          true;

  /// L'extension a un entry point utilisable dans notre contexte.
  bool get hasRunnableEntryPoint => main != null || browser != null;

  @override
  String toString() => 'ExtensionManifest($id@$version)';
}
