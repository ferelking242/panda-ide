import 'agent_definition.dart';

/// Registry of all available agents in the system.
class AgentRegistry {
  final Map<String, AgentDefinition> _agents = {};

  AgentRegistry() {
    // Register built-in agents
    register(PredefinedAgents.mainAgent);
    register(PredefinedAgents.thinker);
    register(PredefinedAgents.reviewer);
  }

  void register(AgentDefinition agent) => _agents[agent.id] = agent;

  AgentDefinition? get(String id) => _agents[id];

  List<AgentDefinition> get all => _agents.values.toList();

  List<AgentDefinition> spawnable(String fromAgentId) {
    final agent = _agents[fromAgentId];
    if (agent == null) return [];
    return agent.spawnableAgents
        .map((id) => _agents[id])
        .whereType<AgentDefinition>()
        .toList();
  }

  bool has(String id) => _agents.containsKey(id);
}

/// Predefined built-in agents.
class PredefinedAgents {
  static const mainAgent = AgentDefinition(
    id: 'main',
    displayName: 'Panda Agent',
    model: 'auto',
    systemPrompt: '', // Built dynamically by AgentRunner
    toolNames: [
      'readFile', 'writeFile', 'editFile', 'deleteFile',
      'runShellCommand', 'searchInFiles', 'grepInFiles',
      'listFiles', 'globSearchFiles', 'readFilesBatch',
      'insertAtLine', 'replaceAllInFile', 'rename',
      'activeEditorFile', 'currentlySelectedText',
      'getTerminalOutput', 'getLspDiagnostics',
      'gitStatus', 'gitDiff', 'gitLog',
      'searchInWeb', 'openLinks',
      'getSecret', 'listSecrets',
      'getAgentSkills', 'useAgentSkill',
      'updateProjectMemory', 'spawn_subagent',
    ],
    spawnableAgents: ['thinker', 'reviewer'],
  );

  static const thinker = AgentDefinition(
    id: 'thinker',
    displayName: 'Thinker',
    model: 'auto',
    systemPrompt: '''You are a thinker agent. You analyze problems deeply.
Use <think> tags to reason about the user's request.
You have no tools — only your reasoning ability.
Provide a concise, actionable analysis.''',
    toolNames: [],
    spawnableAgents: [],
    inheritParentSystemPrompt: true,
    includeMessageHistory: true,
    outputMode: AgentOutputMode.structuredOutput,
  );

  static const reviewer = AgentDefinition(
    id: 'reviewer',
    displayName: 'Reviewer',
    model: 'auto',
    systemPrompt: '''You are a code reviewer. You review file changes and provide critical feedback.
You have no tools — you can only suggest changes.
Be brief and focus on issues that matter.
If the code looks good, say so in one sentence.''',
    toolNames: [],
    spawnableAgents: [],
    inheritParentSystemPrompt: true,
    includeMessageHistory: true,
    outputMode: AgentOutputMode.lastMessage,
  );
}
