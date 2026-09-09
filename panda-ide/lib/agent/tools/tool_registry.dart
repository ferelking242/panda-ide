import 'tool_definition.dart';

/// Central registry for all tools available to the agent.
///
/// Tools are registered at startup. The agent runner queries this registry
/// to know which tools are available and to dispatch tool calls.
///
/// Native tools (file, terminal, search) are registered directly.
/// MCP tools are registered when MCP servers are discovered.
class ToolRegistry {
  final Map<String, ToolDefinition> _tools = {};

  /// Register a native tool.
  void register(ToolDefinition tool) {
    _tools[tool.name] = tool;
  }

  /// Register multiple tools at once.
  void registerAll(List<ToolDefinition> tools) {
    for (final tool in tools) {
      _tools[tool.name] = tool;
    }
  }

  /// Get a tool by name.
  ToolDefinition? get(String name) => _tools[name];

  /// Check if a tool exists.
  bool has(String name) => _tools.containsKey(name);

  /// Get all registered tools.
  List<ToolDefinition> get all => _tools.values.toList();

  /// Get tools filtered by category.
  List<ToolDefinition> byCategory(ToolCategory category) =>
      _tools.values.where((t) => t.category == category).toList();

  /// Get all native (non-MCP) tools.
  List<ToolDefinition> get nativeTools =>
      _tools.values.where((t) => !t.isMcp).toList();

  /// Get all MCP tools.
  List<ToolDefinition> get mcpTools =>
      _tools.values.where((t) => t.isMcp).toList();

  /// Get tools allowed for a specific mode.
  List<ToolDefinition> forMode(String mode) {
    return _tools.values.where((t) {
      // All modes can read
      if (!t.isMutating) return true;
      // Only agent mode can write
      return mode == 'agent';
    }).toList();
  }

  /// Get OpenAI-compatible schemas for all tools (or a subset).
  List<Map<String, dynamic>> getSchemas({String? mode}) {
    final tools = mode != null ? forMode(mode) : _tools.values.toList();
    return tools.map((t) => t.toSchema()).toList();
  }

  /// Get count of registered tools.
  int get count => _tools.length;

  /// Remove a tool (e.g. when an MCP server disconnects).
  void unregister(String name) {
    _tools.remove(name);
  }

  /// Remove all MCP tools from a specific server.
  void unregisterServer(String serverId) {
    _tools.removeWhere(
        (key, tool) => tool.isMcp && tool.mcpServerId == serverId);
  }

  /// Clear all tools.
  void clear() {
    _tools.clear();
  }
}
