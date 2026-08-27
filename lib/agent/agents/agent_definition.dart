/// Typed definition of an agent in the Panda Agent system.
///
/// Each agent has a unique ID, display name, model, system prompt,
/// allowed tools, and spawnable sub-agents.
class AgentDefinition {
  final String id;
  final String displayName;
  final String model;
  final String systemPrompt;
  final List<String> toolNames;
  final List<String> spawnableAgents;
  final bool inheritParentSystemPrompt;
  final bool includeMessageHistory;
  final Map<String, dynamic>? inputSchema;
  final AgentOutputMode outputMode;

  const AgentDefinition({
    required this.id,
    required this.displayName,
    required this.model,
    required this.systemPrompt,
    this.toolNames = const [],
    this.spawnableAgents = const [],
    this.inheritParentSystemPrompt = false,
    this.includeMessageHistory = false,
    this.inputSchema,
    this.outputMode = AgentOutputMode.lastMessage,
  });
}

enum AgentOutputMode {
  lastMessage,
  structuredOutput,
}
