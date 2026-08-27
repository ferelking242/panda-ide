import 'dart:async';

/// Represents a single tool available to the agent.
///
/// Each tool has a name, description, JSON schema for parameters,
/// and an execute function. Tools can be native (Dart) or MCP.
class ToolDefinition {
  /// Unique tool name (e.g. 'readFile', 'runShellCommand').
  final String name;

  /// Human-readable description.
  final String description;

  /// JSON Schema for the tool's input parameters.
  final Map<String, dynamic> parameters;

  /// Whether this tool modifies files/shell (requires write permission).
  final bool isMutating;

  /// Category for UI grouping.
  final ToolCategory category;

  /// Whether this tool comes from MCP (vs native Dart).
  final bool isMcp;

  /// MCP server ID if isMcp is true.
  final String? mcpServerId;

  /// The actual execution function.
  final Future<ToolResult> Function(Map<String, dynamic> args) execute;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    required this.isMutating,
    required this.category,
    this.isMcp = false,
    this.mcpServerId,
    required this.execute,
  });

  /// Convert to OpenAI-compatible tool schema for LLM API calls.
  Map<String, dynamic> toSchema() => {
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        }
      };
}

/// Tool categories for UI grouping.
enum ToolCategory {
  file,
  editor,
  terminal,
  search,
  git,
  web,
  agent,
  mcp,
  other,
}

/// Result of a tool execution.
class ToolResult {
  final bool success;
  final String? data;
  final String? error;
  final Map<String, dynamic>? metadata;

  const ToolResult({
    required this.success,
    this.data,
    this.error,
    this.metadata,
  });

  factory ToolResult.ok(String data, {Map<String, dynamic>? metadata}) =>
      ToolResult(success: true, data: data, metadata: metadata);

  factory ToolResult.fail(String error) =>
      ToolResult(success: false, error: error);

  /// Compatibility with existing code that returns strings.
  factory ToolResult.fromExisting(dynamic result) {
    if (result is String) {
      return ToolResult(success: true, data: result);
    }
    if (result is Map && result.containsKey('error')) {
      return ToolResult(success: false, error: result['error'].toString());
    }
    return ToolResult(success: true, data: result?.toString() ?? '');
  }
}
