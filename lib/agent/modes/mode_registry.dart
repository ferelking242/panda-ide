/// Agent modes define behavior, permissions, and tool access.
///
/// Each mode has:
/// - A set of allowed tools
/// - Whether mutations (write/shell) are permitted
/// - Whether planning is enabled
/// - Whether verification is required
class AgentMode {
  final String id;
  final String displayName;
  final String description;
  final bool allowMutations;
  final bool allowPlanning;
  final bool requireVerification;
  final List<String> extraTools; // tools specific to this mode
  final List<String> blockedTools; // tools blocked in this mode

  const AgentMode({
    required this.id,
    required this.displayName,
    required this.description,
    this.allowMutations = false,
    this.allowPlanning = false,
    this.requireVerification = false,
    this.extraTools = const [],
    this.blockedTools = const [],
  });

  /// Check if a tool is allowed in this mode.
  bool isToolAllowed(String toolName, {required bool isMutating}) {
    if (blockedTools.contains(toolName)) return false;
    if (isMutating && !allowMutations) return false;
    return true;
  }
}

/// Pre-defined modes matching Panda's existing Agent/Ask/Plan system.
class PandaModes {
  static const agent = AgentMode(
    id: 'agent',
    displayName: 'Agent',
    description: 'Autonomie totale — lecture, écriture, shell, git.',
    allowMutations: true,
    allowPlanning: true,
    requireVerification: true,
  );

  static const ask = AgentMode(
    id: 'ask',
    displayName: 'Ask',
    description: 'Questions et réponses — lecture seule.',
    allowMutations: false,
    allowPlanning: false,
    requireVerification: false,
    blockedTools: [
      'writeFile',
      'editFile',
      'deleteFile',
      'replaceAllInFile',
      'insertAtLine',
      'rename',
      'renamePath',
      'runShellCommand',
      'gitCommit',
      'gitPush',
    ],
  );

  static const plan = AgentMode(
    id: 'plan',
    displayName: 'Plan',
    description: 'Planification — lecture et analyse.',
    allowMutations: false,
    allowPlanning: true,
    requireVerification: false,
    blockedTools: [
      'writeFile',
      'editFile',
      'deleteFile',
      'replaceAllInFile',
      'insertAtLine',
      'rename',
      'renamePath',
      'runShellCommand',
    ],
  );

  static const all = [agent, ask, plan];

  static AgentMode byId(String id) =>
      all.firstWhere((m) => m.id == id, orElse: () => agent);
}

/// Registry of all available modes.
class ModeRegistry {
  final Map<String, AgentMode> _modes = {};

  ModeRegistry() {
    // Register default modes
    for (final mode in PandaModes.all) {
      _modes[mode.id] = mode;
    }
  }

  /// Get a mode by ID.
  AgentMode? get(String id) => _modes[id];

  /// Get all registered modes.
  List<AgentMode> get all => _modes.values.toList();

  /// Register a custom mode.
  void register(AgentMode mode) {
    _modes[mode.id] = mode;
  }

  /// Check if a tool is allowed in a given mode.
  bool isToolAllowed(String modeId, String toolName,
      {required bool isMutating}) {
    final mode = _modes[modeId];
    if (mode == null) return true; // unknown mode = allow all
    return mode.isToolAllowed(toolName, isMutating: isMutating);
  }
}
