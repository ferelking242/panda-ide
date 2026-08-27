import '../../mcp/mcp_client.dart';
import '../../mcp/mcp_registry.dart';
import '../tools/tool_definition.dart';
import '../tools/tool_registry.dart';

/// Bridges MCP server tools into the ToolRegistry.
///
/// When MCP servers are connected, their tools are registered
/// as ToolDefinitions with the 'mcp:' prefix.
class McpToolBridge {
  final ToolRegistry _registry;
  final McpClient _client = McpClient();

  McpToolBridge({required ToolRegistry registry}) : _registry = registry;

  /// Discover and register tools from all configured MCP servers.
  Future<void> syncAll() async {
    final servers = await McpRegistry.loadServers();

    for (final server in servers) {
      if (!server.isEnabled) continue;
      await _syncServer(server);
    }
  }

  /// Sync tools from a single MCP server.
  Future<void> _syncServer(McpServerConfig server) async {
    try {
      // Remove old tools from this server
      _registry.unregisterServer(server.id);

      // Discover new tools
      final mcpTools = await _client.discoverTools(server);

      for (final mcpTool in mcpTools) {
        final toolName = 'mcp:${server.id}:${mcpTool.name}';

        _registry.register(ToolDefinition(
          name: toolName,
          description: '[${server.name}] ${mcpTool.description}',
          parameters: mcpTool.inputSchema,
          isMutating: false, // MCP tools default to read-only
          category: ToolCategory.mcp,
          isMcp: true,
          mcpServerId: server.id,
          execute: (args) async {
            try {
              final result = await _client.callTool(server, mcpTool.name, args);
              return ToolResult.ok(result?.toString() ?? '');
            } catch (e) {
              return ToolResult.fail('MCP error: $e');
            }
          },
        ));
      }
    } catch (_) {
      // Server connection failed — skip
    }
  }

  /// Remove all MCP tools.
  void clearAll() {
    final mcpTools = _registry.mcpTools.map((t) => t.name).toList();
    for (final name in mcpTools) {
      _registry.unregister(name);
    }
  }
}
