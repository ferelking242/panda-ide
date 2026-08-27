import 'package:flutter/material.dart';

import '../../utils/agentic_tools.dart' hide ToolResult;
import 'tool_definition.dart';
import 'tool_registry.dart';

/// Bridges the existing AgenticTools implementation with the new ToolRegistry.
///
/// This keeps all 30+ existing tool implementations while exposing them
/// through the new V3 registry system.
class NativeToolBridge {
  /// Register all existing AgenticTools into the new ToolRegistry.
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
         'getPendingEditsForFile', 'getFileInfo'].contains(name)) {
      return ToolCategory.file;
    }
    if (['searchInFiles', 'grepInFiles', 'globSearchFiles', 'listFiles'].contains(name)) {
      return ToolCategory.search;
    }
    if (['runShellCommand', 'getTerminalOutput'].contains(name)) {
      return ToolCategory.terminal;
    }
    if (['gitStatus', 'gitDiff', 'gitLog'].contains(name)) {
      return ToolCategory.git;
    }
    if (['searchInWeb', 'openLinks'].contains(name)) {
      return ToolCategory.web;
    }
    return ToolCategory.other;
  }

  /// Dispatch a tool call to the native AgenticTools.
  static Future<dynamic> _callTool(
    AgenticTools tools,
    String name,
    Map<String, dynamic> args,
  ) async {
    switch (name) {
      case 'readFile':
        return tools.readFile(
          (args['filePath'] ?? '').toString(),
          args['startLine'] as int?,
          args['endLine'] as int?,
        );
      case 'writeFile':
        return tools.writeFile(
          (args['filePath'] ?? '').toString(),
          (args['content'] ?? '').toString(),
        );
      case 'editFile':
        return tools.editFile(
          (args['filePath'] ?? '').toString(),
          (args['oldText'] ?? args['oldString'] ?? '').toString(),
          (args['newText'] ?? args['newString'] ?? '').toString(),
        );
      case 'deleteFile':
        return tools.deleteFile((args['filePath'] ?? '').toString());
      case 'rename':
      case 'renamePath':
        return tools.renamePath(
          (args['oldPath'] ?? '').toString(),
          (args['newPath'] ?? '').toString(),
        );
      case 'insertAtLine':
        return tools.insertAtLine(
          (args['filePath'] ?? '').toString(),
          args['line'] as int? ?? 0,
          (args['text'] ?? '').toString(),
        );
      case 'replaceAllInFile':
        return tools.replaceAllInFile(
          (args['filePath'] ?? '').toString(),
          (args['oldText'] ?? '').toString(),
          (args['newText'] ?? '').toString(),
        );
      case 'listFiles':
        return tools.listFiles(
          (args['directoryPath'] ?? '.').toString(),
          pattern: args['pattern']?.toString(),
          recursive: args['recursive'] as bool? ?? false,
        );
      case 'readFilesBatch':
        return tools.readFilesBatch(
          (args['files'] as List?)?.map((e) => e.toString()).toList() ?? [],
        );
      case 'globSearchFiles':
        return tools.globSearchFiles(
          (args['pattern'] ?? '').toString(),
          directoryPath: args['directoryPath']?.toString(),
        );
      case 'searchInFiles':
        return tools.searchInFiles(
          (args['query'] ?? '').toString(),
          filePattern: args['filePattern']?.toString(),
        );
      case 'grepInFiles':
        return tools.grepInFiles(
          (args['query'] ?? '').toString(),
          filePattern: args['filePattern']?.toString(),
        );
      case 'activeEditorFile':
        return tools.activeEditorFile();
      case 'currentlySelectedText':
        return tools.currentlySelectedText();
      case 'getTerminalOutput':
        // Handled by TerminalBridge directly, not AgenticTools
        return ToolResult.ok('Use TerminalBridge.getRecentOutput()');
      case 'getLspDiagnostics':
        return tools.getLspDiagnostics(
          args['filePath']?.toString(),
        );
      case 'getPendingEditsForFile':
        return tools.getPendingEditsForFile(
          (args['filePath'] ?? '').toString(),
        );
      case 'getFileInfo':
        return tools.getFileInfo(
          (args['filePath'] ?? '').toString(),
        );
      case 'searchInWeb':
        return tools.searchInWeb(
          (args['searchQuery'] ?? args['query'] ?? '').toString(),
        );
      case 'openLinks':
        return tools.openLinks(
          (args['url'] ?? args['urls'] ?? '').toString(),
        );
      case 'runShellCommand':
        final cmdArgs = (args['args'] as List?)
            ?.map((e) => e.toString())
            .toList() ?? [];
        final envs = (args['envs'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), v.toString()))
            ?? <String, String>{};
        return tools.runShellCommand(
          (args['command'] ?? '').toString(),
          cmdArgs,
          envs,
        );
      case 'getSecret':
        return tools.getSecret(
          (args['name'] ?? args['key'] ?? '').toString(),
        );
      case 'listSecrets':
        return tools.listSecrets();
      case 'getAgentSkills':
        return tools.getAgentSkills();
      case 'useAgentSkill':
        return tools.useAgentSkill(
          (args['skillName'] ?? args['skill'] ?? args['name'] ?? '').toString(),
        );
      case 'updateProjectMemory':
        return tools.updateProjectMemory(
          (args['content'] ?? '').toString(),
        );
      case 'gitStatus':
        return tools.gitStatus();
      case 'gitDiff':
        return tools.gitDiff(
          filePath: args['filePath']?.toString(),
          staged: args['staged'] as bool? ?? false,
          contextLines: args['contextLines'] as int? ?? 3,
        );
      case 'gitLog':
        return tools.gitLog(
          limit: args['limit'] as int? ?? 20,
          filePath: args['filePath']?.toString(),
        );
      default:
        return 'Unknown tool: $name';
    }
  }

  static Map<String, dynamic> _parametersFor(String name) {
    switch (name) {
      case 'readFile':
        return {
          'type': 'object',
          'properties': {
            'filePath': {'type': 'string'},
            'startLine': {'type': 'integer'},
            'endLine': {'type': 'integer'},
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
            'oldText': {'type': 'string'},
            'newText': {'type': 'string'},
          },
          'required': ['filePath', 'oldText', 'newText'],
        };
      case 'runShellCommand':
        return {
          'type': 'object',
          'properties': {
            'command': {'type': 'string'},
            'args': {'type': 'array', 'items': {'type': 'string'}},
            'envs': {'type': 'object'},
          },
          'required': ['command'],
        };
      case 'searchInFiles':
      case 'grepInFiles':
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
          'properties': <String, dynamic>{},
        };
    }
  }
}
