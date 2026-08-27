import 'package:flutter/material.dart';

import '../../utils/agentic_tools.dart';
import 'tool_definition.dart';
import 'tool_registry.dart';

/// Bridges the existing AgenticTools implementation with the new ToolRegistry.
///
/// This allows us to keep the existing 30+ tool implementations while
/// exposing them through the new registry system.
class NativeToolBridge {
  /// Register all existing AgenticTools into the new ToolRegistry.
  ///
  /// This wraps each existing tool call into a ToolDefinition.
  static void registerAll({
    required ToolRegistry registry,
    required BuildContext context,
    required String workspacePath,
    AgentConfirmCallback? onConfirmRequired,
    String approvalMode = 'default',
  }) {
    final tools = AgenticTools(
      context: context,
      workspacePath: workspacePath,
      onConfirmRequired: onConfirmRequired,
      approvalMode: approvalMode,
    );

    // Register each tool spec as a ToolDefinition
    for (final spec in AgenticTools.toolSpecs) {
      registry.register(ToolDefinition(
        name: spec.name,
        description: spec.description,
        parameters: _parametersFor(spec.name),
        isMutating: spec.requiresWriteAccess,
        category: _categoryFor(spec.name),
        execute: (args) async {
          try {
            final result = await _callTool(tools, spec.name, args);
            return ToolResult.fromExisting(result);
          } catch (e) {
            return ToolResult.fail(e.toString());
          }
        },
      ));
    }
  }

  static ToolCategory _categoryFor(String name) {
    if (['readFile', 'writeFile', 'editFile', 'deleteFile', 'rename',
         'renamePath', 'insertAtLine', 'replaceAllInFile', 'readFilesBatch',
         'listFiles', 'getPendingEditsForFile', 'getFileInfo']
        .contains(name)) {
      return ToolCategory.file;
    }
    if (['activeEditorFile', 'currentlySelectedText'].contains(name)) {
      return ToolCategory.editor;
    }
    if (['runShellCommand', 'getTerminalOutput'].contains(name)) {
      return ToolCategory.terminal;
    }
    if (['searchInFiles', 'grepInFiles', 'globSearchFiles'].contains(name)) {
      return ToolCategory.search;
    }
    if (['gitStatus', 'gitDiff', 'gitLog'].contains(name)) {
      return ToolCategory.git;
    }
    if (['searchInWeb', 'openLinks'].contains(name)) {
      return ToolCategory.web;
    }
    if (['getSecret', 'listSecrets', 'getAgentSkills', 'useAgentSkill',
         'updateProjectMemory', 'getLspDiagnostics'].contains(name)) {
      return ToolCategory.agent;
    }
    return ToolCategory.other;
  }

  /// Dispatch a tool call to the existing AgenticTools instance.
  static Future<dynamic> _callTool(
    AgenticTools tools,
    String name,
    Map<String, dynamic> args,
  ) async {
    switch (name) {
      case 'readFile':
        return tools.readFile(
          args['filePath']?.toString() ?? '',
          args['startLine'] as int?,
          args['endLine'] as int?,
        );
      case 'writeFile':
        return tools.writeFile(
          args['filePath']?.toString() ?? '',
          args['content']?.toString() ?? '',
        );
      case 'editFile':
        return tools.editFile(
          args['filePath']?.toString() ?? '',
          args['oldString']?.toString() ?? '',
          args['newString']?.toString() ?? '',
        );
      case 'runShellCommand':
        return tools.runShellCommand(
          args['command']?.toString() ?? '',
        );
      case 'searchInFiles':
        return tools.searchInFiles(
          args['query']?.toString() ?? '',
          filePattern: args['filePattern']?.toString(),
        );
      case 'grepInFiles':
        return tools.grepInFiles(
          args['query']?.toString() ?? '',
          filePattern: args['filePattern']?.toString(),
        );
      case 'listFiles':
        return tools.listFiles(
          args['directoryPath']?.toString() ?? '',
          pattern: args['pattern']?.toString(),
          recursive: args['recursive'] as bool? ?? false,
        );
      case 'globSearchFiles':
        return tools.globSearchFiles(
          args['pattern']?.toString() ?? '',
          directoryPath: args['directoryPath']?.toString(),
        );
      case 'readFilesBatch':
        return tools.readFilesBatch(
          (args['files'] as List?)?.cast<String>() ?? [],
        );
      case 'deleteFile':
        return tools.deleteFile(args['filePath']?.toString() ?? '');
      case 'rename':
      case 'renamePath':
        return tools.rename(
          args['oldPath']?.toString() ?? '',
          args['newPath']?.toString() ?? '',
        );
      case 'insertAtLine':
        return tools.insertAtLine(
          args['filePath']?.toString() ?? '',
          args['line'] as int? ?? 0,
          args['text']?.toString() ?? '',
        );
      case 'replaceAllInFile':
        return tools.replaceAllInFile(
          args['filePath']?.toString() ?? '',
          args['oldText']?.toString() ?? '',
          args['newText']?.toString() ?? '',
        );
      case 'activeEditorFile':
        return tools.activeEditorFile();
      case 'currentlySelectedText':
        return tools.currentlySelectedText();
      case 'getTerminalOutput':
        return tools.getTerminalOutput(
          args['lines'] as int? ?? 100,
        );
      case 'getLspDiagnostics':
        return tools.getLspDiagnostics(
          args['filePath']?.toString() ?? '',
        );
      case 'getPendingEditsForFile':
        return tools.getPendingEditsForFile(
          args['filePath']?.toString() ?? '',
        );
      case 'getFileInfo':
        return tools.getFileInfo(
          args['filePath']?.toString() ?? '',
        );
      case 'searchInWeb':
        return tools.searchInWeb(
          args['query']?.toString() ?? '',
        );
      case 'openLinks':
        return tools.openLinks(
          args['urls'] as List? ?? [],
        );
      case 'getSecret':
        return tools.getSecret(
          args['key']?.toString() ?? '',
        );
      case 'listSecrets':
        return tools.listSecrets();
      case 'getAgentSkills':
        return tools.getAgentSkills();
      case 'useAgentSkill':
        return tools.useAgentSkill(
          args['skill']?.toString() ?? '',
        );
      case 'updateProjectMemory':
        return tools.updateProjectMemory(
          args['content']?.toString() ?? '',
        );
      case 'gitStatus':
        return tools.gitStatus();
      case 'gitDiff':
        return tools.gitDiff(
          args['filePath']?.toString(),
        );
      case 'gitLog':
        return tools.gitLog(
          args['count'] as int? ?? 10,
        );
      default:
        return 'Unknown tool: $name';
    }
  }

  static Map<String, dynamic> _parametersFor(String name) {
    // Basic parameter schemas for existing tools
    switch (name) {
      case 'readFile':
        return {
          'type': 'object',
          'properties': {
            'filePath': {'type': 'string', 'description': 'Path to the file'},
            'startLine': {'type': 'integer', 'description': 'Start line (optional)'},
            'endLine': {'type': 'integer', 'description': 'End line (optional)'},
          },
          'required': ['filePath'],
        };
      case 'writeFile':
        return {
          'type': 'object',
          'properties': {
            'filePath': {'type': 'string'},
            'content': {'type': 'string'},
          },
          'required': ['filePath', 'content'],
        };
      case 'editFile':
        return {
          'type': 'object',
          'properties': {
            'filePath': {'type': 'string'},
            'oldString': {'type': 'string'},
            'newString': {'type': 'string'},
          },
          'required': ['filePath', 'oldString', 'newString'],
        };
      case 'runShellCommand':
        return {
          'type': 'object',
          'properties': {
            'command': {'type': 'string', 'description': 'Shell command to execute'},
          },
          'required': ['command'],
        };
      case 'searchInFiles':
        return {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
            'filePattern': {'type': 'string'},
          },
          'required': ['query'],
        };
      default:
        return {
          'type': 'object',
          'properties': {},
        };
    }
  }
}
