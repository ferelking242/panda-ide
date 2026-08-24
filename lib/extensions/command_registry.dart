/// CommandRegistry — vscode.commands.* — Phase 5.
///
/// Registre central des commandes VSCode enregistrées par les extensions.
/// Les commandes sont ensuite exécutables depuis :
///   - La CommandPalette Flutter (Phase 5)
///   - D'autres extensions via vscode.commands.executeCommand()
///   - Des boutons de la status bar (command:xxx)
///   - Des menu items de context (Phase 13)
library;
import 'dart:async';
import 'extension_host_manager.dart';




// ── Command model ─────────────────────────────────────────────────────────

class RegisteredCommand {
  final String command;
  final String extensionId;
  final String? title;       // fourni par contributes.commands dans package.json
  final String? category;    // ex: "Git", "Prettier"
  final String? description;

  const RegisteredCommand({
    required this.command,
    required this.extensionId,
    this.title,
    this.category,
    this.description,
  });

  /// Libellé affiché dans la CommandPalette : "Category: Title" ou juste title.
  String get displayLabel {
    if (category != null && title != null) return '$category: $title';
    return title ?? command;
  }
}

// ── CommandRegistry ───────────────────────────────────────────────────────

class CommandRegistry {
  static final CommandRegistry instance = CommandRegistry._();
  CommandRegistry._();

  /// Toutes les commandes enregistrées : commandId → RegisteredCommand.
  final Map<String, RegisteredCommand> _commands = {};

  /// Listeners notifiés quand la liste change (pour la CommandPalette).
  final List<void Function()> _listeners = [];

  // ── Registration ──────────────────────────────────────────────────────────

  void register({
    required String command,
    required String extensionId,
    String? title,
    String? category,
    String? description,
  }) {
    _commands[command] = RegisteredCommand(
      command:     command,
      extensionId: extensionId,
      title:       title ?? command,
      category:    category,
      description: description,
    );
    _notifyListeners();
  }

  void unregister(String command) {
    if (_commands.remove(command) != null) _notifyListeners();
  }

  /// Enregistre les commandes déclarées dans contributes.commands du manifest.
  void registerContributed(String extensionId, List<dynamic> contributes) {
    for (final item in contributes.whereType<Map<String, dynamic>>()) {
      final cmd = item['command'] as String?;
      if (cmd == null) continue;
      register(
        command:     cmd,
        extensionId: extensionId,
        title:       item['title'] as String?,
        category:    item['category'] as String?,
        description: item['description'] as String?,
      );
    }
    _notifyListeners();
  }

  void unregisterAll(String extensionId) {
    _commands.removeWhere((_, v) => v.extensionId == extensionId);
    _notifyListeners();
  }

  // ── Execution ─────────────────────────────────────────────────────────────

  /// Exécute une commande.
  /// Envoie un event 'command.invoke' à l'extension propriétaire.
  Future<dynamic> execute(String command, List<dynamic> args) async {
    final registered = _commands[command];
    if (registered == null) {
      // Commande builtin ou inconnue — on ignore silencieusement
      return null;
    }

    final bridge = ExtensionHostManager.instance.getBridge(registered.extensionId);
    if (bridge == null) return null;

    // L'extension a enregistré un handler via vscode.commands.registerCommand()
    // qui crée un ipc.onCall handler. On peut aussi utiliser fireEvent.
    // On préfère call() pour avoir un retour.
    try {
      return await bridge.call('command.${command}', args);
    } catch (_) {
      // Si pas de handler call, fire l'event classique
      bridge.fireEvent('command.invoke', {'command': command, 'args': args});
      return null;
    }
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  List<RegisteredCommand> get all => _commands.values.toList();

  List<RegisteredCommand> search(String query) {
    if (query.isEmpty) return all;
    final q = query.toLowerCase();
    return _commands.values
        .where((c) =>
            c.displayLabel.toLowerCase().contains(q) ||
            c.command.toLowerCase().contains(q))
        .toList();
  }

  RegisteredCommand? get(String command) => _commands[command];

  List<String> get commandIds => _commands.keys.toList();

  // ── Listeners ─────────────────────────────────────────────────────────────

  void addListener(void Function() fn) => _listeners.add(fn);
  void removeListener(void Function() fn) => _listeners.remove(fn);

  void _notifyListeners() {
    for (final fn in List.of(_listeners)) {
      fn();
    }
  }
}
