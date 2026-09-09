import 'dart:io';

import 'context_budget.dart';
import 'context_pruner.dart';
import 'project_tree.dart';
import 'relevant_files.dart';

/// Builds intelligent context for the LLM from multiple sources.
///
/// Sources are prioritized and budgeted to fit within token limits.
class ContextManager {
  final ContextBudgetConfig _config;

  ContextManager({ContextBudgetConfig? config})
      : _config = config ?? ContextBudgetConfig.midRange();

  /// Build the full context for an agent turn.
  Future<AgentContext> build({
    required String workspacePath,
    required String userRequest,
    required List<Map<String, dynamic>> conversationHistory,
    List<String>? openFiles,
    String? gitDiff,
    String? projectMemory,
    String? knowledgeRules,
    String? lspDiagnostics,
    List<Map<String, dynamic>>? recentToolOutputs,
  }) async {
    final budget = ContextBudget(maxTokens: _config.maxTokens);
    final sections = <ContextSection>[];

    // 1. Project tree (always include)
    if (_config.projectTreeBudget > 0) {
      final tree = await ProjectTree.scan(workspacePath);
      final tokens = budget.allocate('project_tree', _config.projectTreeBudget);
      sections.add(ContextSection(
        name: 'project_tree',
        content: tree,
        tokenBudget: tokens,
      ));
    }

    // 2. Active/open files (high priority)
    if (openFiles != null && openFiles.isNotEmpty) {
      final content = await _readFiles(openFiles, workspacePath);
      final tokens = budget.allocate('active_files', _config.activeFileBudget);
      sections.add(ContextSection(
        name: 'active_files',
        content: content,
        tokenBudget: tokens,
      ));
    }

    // 3. Relevant files (based on user request)
    final relevant = await RelevantFiles.find(workspacePath, userRequest);
    if (relevant.isNotEmpty) {
      final paths = relevant.map((r) => r.path).toList();
      final content = await _readFiles(paths, workspacePath);
      final tokens = budget.allocate('relevant_files', _config.relevantFilesBudget);
      sections.add(ContextSection(
        name: 'relevant_files',
        content: content,
        tokenBudget: tokens,
      ));
    }

    // 4. Git diff
    if (gitDiff != null && gitDiff.isNotEmpty) {
      final tokens = budget.allocate('git_diff', _config.gitDiffBudget);
      sections.add(ContextSection(
        name: 'git_diff',
        content: gitDiff,
        tokenBudget: tokens,
      ));
    }

    // 5. Project memory
    if (projectMemory != null && projectMemory.isNotEmpty) {
      final tokens = budget.allocate('memory', _config.memoryBudget);
      sections.add(ContextSection(
        name: 'memory',
        content: projectMemory,
        tokenBudget: tokens,
      ));
    }

    // 6. Knowledge rules
    if (knowledgeRules != null && knowledgeRules.isNotEmpty) {
      final tokens = budget.allocate('knowledge', _config.knowledgeBudget);
      sections.add(ContextSection(
        name: 'knowledge',
        content: knowledgeRules,
        tokenBudget: tokens,
      ));
    }

    // 7. LSP diagnostics
    if (lspDiagnostics != null && lspDiagnostics.isNotEmpty) {
      final tokens = budget.allocate('lsp', _config.lspDiagnosticsBudget);
      sections.add(ContextSection(
        name: 'lsp_diagnostics',
        content: lspDiagnostics,
        tokenBudget: tokens,
      ));
    }

    // 8. Recent tool outputs (pruned)
    if (recentToolOutputs != null && recentToolOutputs.isNotEmpty) {
      final pruned = recentToolOutputs.takeLast(5).map((o) {
        final output = o['result']?.toString() ?? '';
        return ContextPruner.truncateToolOutput(output, maxTokens: 1000);
      }).join('\n---\n');
      final tokens = budget.allocate('tool_outputs', _config.toolOutputBudget);
      sections.add(ContextSection(
        name: 'tool_outputs',
        content: pruned,
        tokenBudget: tokens,
      ));
    }

    // 9. Conversation history (pruned)
    final prunedHistory = ContextPruner.prune(
      conversationHistory,
      maxTokens: budget.available,
    );
    sections.add(ContextSection(
      name: 'conversation',
      content: _formatHistory(prunedHistory),
      tokenBudget: budget.available,
    ));

    return AgentContext(
      sections: sections,
      totalTokens: _config.maxTokens - budget.available,
      maxTokens: _config.maxTokens,
    );
  }

  Future<String> _readFiles(List<String> paths, String rootPath) async {
    final buffer = StringBuffer();
    for (final relPath in paths.take(10)) {
      try {
        final file = File('$rootPath/$relPath');
        if (await file.exists()) {
          final content = await file.readAsString();
          final truncated = ContextPruner.truncateToolOutput(content, maxTokens: 3000);
          buffer.writeln('### $relPath\n```dart\n$truncated\n```\n');
        }
      } catch (_) {}
    }
    return buffer.toString();
  }

  String _formatHistory(List<Map<String, dynamic>> messages) {
    final buffer = StringBuffer();
    buffer.writeln('## Historique de conversation');
    for (final msg in messages) {
      final role = msg['role'] == 'user' ? 'Utilisateur' : 'Agent';
      final content = msg['content']?.toString() ?? '';
      buffer.writeln('**$role:** $content\n');
    }
    return buffer.toString();
  }
}

class AgentContext {
  final List<ContextSection> sections;
  final int totalTokens;
  final int maxTokens;

  const AgentContext({
    required this.sections,
    required this.totalTokens,
    required this.maxTokens,
  });

  double get usagePercent => totalTokens / maxTokens;

  /// Build the full context string for the LLM.
  String buildString() {
    final buffer = StringBuffer();
    for (final section in sections) {
      if (section.content.isNotEmpty) {
        buffer.writeln(section.content);
        buffer.writeln();
      }
    }
    return buffer.toString();
  }
}

class ContextSection {
  final String name;
  final String content;
  final int tokenBudget;

  const ContextSection({
    required this.name,
    required this.content,
    required this.tokenBudget,
  });
}

extension _ListTakeLast<T> on List<T> {
  List<T> takeLast(int n) {
    if (length <= n) return this;
    return sublist(length - n);
  }
}
