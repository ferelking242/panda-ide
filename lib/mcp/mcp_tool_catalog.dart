import 'dart:io';

class MCPToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parametersSchema;

  MCPToolDefinition({
    required this.name,
    required this.description,
    required this.parametersSchema,
  });
}

class MCPToolCatalog {
  static List<MCPToolDefinition> getStandardTools() {
    return [
      MCPToolDefinition(
        name: 'readFile',
        description: 'Read contents of a file in the workspace',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Absolute path to file'}
          },
          'required': ['path']
        },
      ),
      MCPToolDefinition(
        name: 'writeFile',
        description: 'Write content to a file in the workspace',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Absolute path to file'},
            'content': {'type': 'string', 'description': 'Full file content'}
          },
          'required': ['path', 'content']
        },
      ),
      MCPToolDefinition(
        name: 'runTerminalCommand',
        description: 'Execute a shell command in the workspace terminal',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'command': {'type': 'string', 'description': 'Shell command to execute'}
          },
          'required': ['command']
        },
      ),
      MCPToolDefinition(
        name: 'listDirectory',
        description: 'List contents of a directory',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Directory path'}
          },
          'required': ['path']
        },
      ),
    ];
  }

  static Future<String> executeTool(String toolName, Map<String, dynamic> args) async {
    switch (toolName) {
      case 'readFile':
        final path = args['path'] as String?;
        if (path == null) return 'Error: path is required';
        try {
          return await File(path).readAsString();
        } catch (e) {
          return 'Error reading file: $e';
        }
      case 'writeFile':
        final path = args['path'] as String?;
        final content = args['content'] as String?;
        if (path == null || content == null) return 'Error: path and content required';
        try {
          final file = File(path);
          await file.parent.create(recursive: true);
          await file.writeAsString(content);
          return 'Successfully wrote to $path';
        } catch (e) {
          return 'Error writing file: $e';
        }
      case 'listDirectory':
        final path = args['path'] as String?;
        if (path == null) return 'Error: path required';
        try {
          final dir = Directory(path);
          final entities = await dir.list().toList();
          return entities.map((e) => e.path).join('\n');
        } catch (e) {
          return 'Error listing directory: $e';
        }
      default:
        return 'Unknown tool: $toolName';
    }
  }
}
