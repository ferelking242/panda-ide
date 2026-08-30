import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'agent_models.dart';
import 'beui/approval/beui_approval_card.dart';
import 'beui/approval/beui_tool_approval.dart';
import 'beui/beui_theme.dart';
import 'beui/conversation/beui_message.dart';
import 'beui/conversation/beui_message_bubble.dart';
import 'beui/conversation/beui_message_scroller.dart';
import 'beui/progress/beui_agent_activity.dart';
import 'beui/progress/beui_agent_loading_states.dart';
import 'beui/progress/beui_todo_list.dart';
import 'beui/response/beui_citations.dart';
import 'beui/response/beui_image_generation.dart';
import 'beui/response/beui_streaming_response.dart';
import 'beui/tools/beui_code_block.dart';
import 'beui/tools/beui_file_diff.dart';
import 'beui/tools/beui_tool_result.dart';

/// The single rendering boundary for Panda Agent.
///
/// Home owns the agent state and callbacks; this widget owns the conversation
/// presentation. Event payloads stay map-shaped because they are also used by
/// the persistence and streaming layers.
class PandaAgentBeUI extends StatefulWidget {
  final List<Map<String, dynamic>> messages;
  final ScrollController scrollController;
  final bool isGenerating;
  final String phase;
  final AgentActivityController activityController;
  final ValueChanged<int>? onRetry;
  final ValueChanged<bool>? onToolApproval;
  final VoidCallback? onAlwaysAllowTools;
  final ValueChanged<String>? onApprovalText;
  final VoidCallback? onApprovalDeny;
  final void Function(String name, Map<String, dynamic> args, String? result)?
      onOpenTool;
  final bool isDark;

  const PandaAgentBeUI({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.isGenerating,
    required this.phase,
    required this.activityController,
    this.onRetry,
    this.onToolApproval,
    this.onAlwaysAllowTools,
    this.onApprovalText,
    this.onApprovalDeny,
    this.onOpenTool,
    required this.isDark,
  });

  @override
  State<PandaAgentBeUI> createState() => _PandaAgentBeUIState();
}

class _PandaAgentBeUIState extends State<PandaAgentBeUI> {
  final BeUIAgentActivityController _beUiActivity =
      BeUIAgentActivityController();
  bool _activityExpanded = true;

  @override
  Widget build(BuildContext context) {
    _syncActivity();

    return widget.messages.isEmpty
        ? const SizedBox.shrink()
        : BeUIMessageScroller(
            scrollController: widget.scrollController,
            isStreaming: widget.isGenerating,
            backgroundColor: widget.isDark
                ? const Color(0xff181818)
                : const Color(0xfffafafa),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            itemCount: widget.messages.length,
            itemBuilder: (_, index) => _buildMessage(index),
          );
  }

  void _syncActivity() {
    final source = widget.activityController;
    _beUiActivity.history
      ..clear()
      ..addAll(source.history.map(_mapStep));
    _beUiActivity.activeActivity =
        source.activeActivity == null ? null : _mapStep(source.activeActivity!);
    _beUiActivity.isToolRunning = source.isToolRunning;
    _beUiActivity.activeToolId = source.activeToolId;
  }

  BeUIAgentStep _mapStep(AgentActivityEvent source) {
    final type = switch (source.type) {
      AgentActivityType.thinking => BeUIStepType.reasoning,
      AgentActivityType.tool => BeUIStepType.tool,
      _ => BeUIStepType.status,
    };
    final status = switch (source.status) {
      AgentActivityStatus.pending => BeUIStepStatus.pending,
      AgentActivityStatus.running => BeUIStepStatus.running,
      AgentActivityStatus.error => BeUIStepStatus.error,
      AgentActivityStatus.completed => BeUIStepStatus.success,
    };
    return BeUIAgentStep(
      id: source.id,
      timestamp: source.timestamp,
      type: type,
      status: status,
      title: source.label,
      toolName: source.toolName,
      toolArgs: source.toolArgs,
      toolResult: source.toolResult,
      outputText: source.outputText,
      duration: source.duration,
      isExpanded: source.isExpanded,
    );
  }

  Widget _buildMessage(int index) {
    final msg = widget.messages[index];
    final isUser = msg['role'] == 'user';
    final text = (msg['text'] as String? ?? '').trim();
    final phase = msg['phase'] as String? ?? 'done';
    final isStreaming =
        phase == 'streaming' && index == widget.messages.length - 1;
    final isError = phase == 'error';

    if (isUser) {
      return BeUIMessage(
        key: ValueKey('user-$index'),
        role: BeUIMessageRole.user,
        child: BeUIMessageBubble(
          tone: BeUIBubbleTone.user,
          text: text,
          expandable: false,
          animateIn: false,
          enableSwipeActions: false,
          onCopy: () => _copy(text),
        ),
      );
    }

    final blocks = ((msg['blocks'] as List?) ?? const [])
        .whereType<Map>()
        .map((block) => Map<String, dynamic>.from(block))
        .toList();
    final calls = ((msg['toolCalls'] as List?) ?? const [])
        .whereType<Map>()
        .map((call) => Map<String, dynamic>.from(call))
        .toList();
    final timeline = <Map<String, dynamic>>[
      ...blocks,
      if (blocks.isEmpty && (msg['thinking'] as String? ?? '').trim().isNotEmpty)
        {'type': 'thinking', 'thinking': msg['thinking']},
      if (blocks.isEmpty)
        ...calls.map((call) => {'type': 'toolCall', ...call}),
    ];
    if (timeline.isEmpty && text.isNotEmpty) {
      timeline.add({'type': 'text', 'text': text});
    }

    final children = <Widget>[];
    final isActiveMessage =
        index == widget.messages.length - 1 && widget.isGenerating;
    if (isActiveMessage &&
        (_beUiActivity.history.isNotEmpty ||
            _beUiActivity.activeActivity != null)) {
      children.add(
        BeUIAgentActivity(
          controller: _beUiActivity,
          isExpanded: _activityExpanded,
          onToggleExpanded: () =>
              setState(() => _activityExpanded = !_activityExpanded),
          isDark: widget.isDark,
          fg: widget.isDark ? Colors.grey[300]! : Colors.grey[800]!,
          muted: widget.isDark ? Colors.grey[500]! : Colors.grey[500]!,
        ),
      );
    }

    for (var eventIndex = 0; eventIndex < timeline.length; eventIndex++) {
      children.add(_buildEvent(
        timeline[eventIndex],
        messageIndex: index,
        isActiveMessage: isActiveMessage,
        isStreaming: isStreaming,
        isError: isError,
      ));
    }

    if (children.isEmpty && text.isEmpty && isActiveMessage) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: BeUILoadingState(
            label: _phaseLabel(),
            variant: BeUILoadingVariant.progress,
            color: BeUIColors.accentOf(widget.isDark),
          ),
        ),
      );
    }

    return Padding(
      key: ValueKey('assistant-$index'),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: BeUIMessage(
        role: BeUIMessageRole.assistant,
        isStreaming: isStreaming,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  String _phaseLabel() {
    switch (widget.phase) {
      case 'thinking':
        return 'Réflexion…';
      case 'toolRunning':
        return 'Exécution…';
      case 'error':
        return 'Erreur';
      default:
        return 'Génération…';
    }
  }

  Widget _buildEvent(
    Map<String, dynamic> event, {
    required int messageIndex,
    required bool isActiveMessage,
    required bool isStreaming,
    required bool isError,
  }) {
    final type = event['type'] as String? ?? '';
    switch (type) {
      case 'thinking':
      case 'reasoning':
        final reasoning = (event['thinking'] ?? event['text'] ?? '')
            .toString()
            .trim();
        if (reasoning.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: BeUIMessageBubble(
            tone: BeUIBubbleTone.system,
            text: reasoning,
            expandable: true,
            maxLines: 8,
            animateIn: false,
            enableSwipeActions: false,
          ),
        );

      case 'toolCall':
      case 'tool':
        return _buildToolEvent(event);

      case 'code':
        return BeUICodeBlock(
          code: (event['code'] ?? event['text'] ?? '').toString(),
          language: event['language']?.toString(),
          isDark: widget.isDark,
        );

      case 'diff':
      case 'fileDiff':
        return _buildDiff(event);

      case 'citations':
      case 'sources':
        return _buildCitations(event);

      case 'image':
      case 'imageGeneration':
        return _buildImage(event);

      case 'todo':
      case 'todos':
        return _buildTodos(event);

      case 'approval':
        return _buildApproval(event);

      case 'loading':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: BeUILoadingState(
            label: event['label']?.toString() ?? _phaseLabel(),
            variant: BeUILoadingVariant.cycling,
            cyclingPhrases: (event['phrases'] as List?)
                ?.map((phrase) => phrase.toString())
                .toList(),
            color: BeUIColors.accentOf(widget.isDark),
          ),
        );

      case 'text':
      default:
        final response = _extractText(event['text']?.toString() ?? '');
        if (response.trim().isEmpty) return const SizedBox.shrink();
        return _buildResponse(
          response,
          messageIndex: messageIndex,
          isStreaming: isStreaming && isActiveMessage,
          isError: isError,
        );
    }
  }

  Widget _buildResponse(
    String text, {
    required int messageIndex,
    required bool isStreaming,
    required bool isError,
  }) {
    final previousUser = messageIndex > 0 &&
        widget.messages[messageIndex - 1]['role'] == 'user';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._splitCodeFences(text).map(
          (segment) => segment.isCode
              ? BeUICodeBlock(
                  code: segment.value,
                  language: segment.language,
                  isDark: widget.isDark,
                )
              : BeUIStreamingResponse(
                  text: segment.value,
                  isStreaming: isStreaming,
                  isDark: widget.isDark,
                  onCopy: () => _copy(text),
                  onRetry: !isStreaming && previousUser && widget.onRetry != null
                      ? () => widget.onRetry!(messageIndex)
                      : null,
                ),
        ),
      ],
    );
  }

  Widget _buildToolEvent(Map<String, dynamic> event) {
    final name = (event['name'] ?? event['toolName'] ?? '').toString();
    final args = (event['args'] as Map?)
            ?.map((key, value) => MapEntry(key.toString(), value)) ??
        <String, dynamic>{};
    final result = event['result']?.toString();
    final status = event['status']?.toString() ?? 'done';
    if (status == 'pending_approval' || status == 'pending') {
      return BeUIToolApproval(
        toolName: name,
        args: args,
        onAllow: () => widget.onToolApproval?.call(true),
        onAlways: () {
          widget.onAlwaysAllowTools?.call();
          widget.onToolApproval?.call(true);
        },
        onDeny: () => widget.onToolApproval?.call(false),
        isDark: widget.isDark,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BeUIToolResult(
          title: name.isEmpty ? 'Outil' : name,
          output: result ?? '',
          isRunning: status == 'running',
          exitCode: (event['exitCode'] as num?)?.toInt(),
          duration: event['duration']?.toString(),
          isDark: widget.isDark,
        ),
        if (widget.onOpenTool != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => widget.onOpenTool!(name, args, result),
              icon: const Icon(Icons.open_in_new, size: 13),
              label: const Text('Ouvrir dans l’éditeur'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: BeUIColors.accentOf(widget.isDark),
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDiff(Map<String, dynamic> event) {
    final lines = ((event['lines'] as List?) ?? const []).whereType<Map>().map(
      (line) {
        final type = switch (line['type']?.toString()) {
          'added' || '+' => BeUIDiffLineType.added,
          'removed' || '-' => BeUIDiffLineType.removed,
          _ => BeUIDiffLineType.context,
        };
        return BeUIDiffLine(
          type: type,
          oldLine: (line['oldLine'] as num?)?.toInt(),
          newLine: (line['newLine'] as num?)?.toInt(),
          text: (line['text'] ?? '').toString(),
        );
      },
    ).toList();
    return BeUIFileDiff(
      fileName: event['fileName']?.toString() ?? event['path']?.toString(),
      lines: lines,
      isStreaming: widget.isGenerating,
      isDone: !widget.isGenerating,
      isDark: widget.isDark,
    );
  }

  Widget _buildCitations(Map<String, dynamic> event) {
    final sourceList = (event['citations'] ?? event['sources']) as List?;
    final citations = (sourceList ?? const []).asMap().entries.map((entry) {
      final value = entry.value;
      if (value is Map) {
        return BeUICitation(
          index: (value['index'] as num?)?.toInt() ?? entry.key + 1,
          title: (value['title'] ?? value['name'] ?? 'Source').toString(),
          domain: value['domain']?.toString(),
          snippet: value['snippet']?.toString(),
        );
      }
      return BeUICitation(index: entry.key + 1, title: value.toString());
    }).toList();
    return BeUICitations(citations: citations, isDark: widget.isDark);
  }

  Widget _buildImage(Map<String, dynamic> event) {
    final status = switch (event['status']?.toString()) {
      'queued' => BeUIImageStatus.queued,
      'generating' => BeUIImageStatus.generating,
      _ => BeUIImageStatus.done,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: BeUIImageGeneration(
        status: status,
        imageUrl: event['url']?.toString() ?? event['imageUrl']?.toString(),
        label: event['label']?.toString(),
        isDark: widget.isDark,
      ),
    );
  }

  Widget _buildTodos(Map<String, dynamic> event) {
    final items = ((event['items'] as List?) ?? const []).whereType<Map>().map(
      (item) {
        final status = switch (item['status']?.toString()) {
          'running' || 'in_progress' => BeUITodoStatus.running,
          'done' || 'completed' || 'complete' => BeUITodoStatus.done,
          _ => BeUITodoStatus.pending,
        };
        return BeUITodoItem(
          title: (item['title'] ?? item['text'] ?? '').toString(),
          status: status,
          details: item['details']?.toString(),
        );
      },
    ).where((item) => item.title.isNotEmpty).toList();
    return BeUITodoList(
      items: items,
      isDark: widget.isDark,
      fg: widget.isDark ? Colors.grey[300]! : Colors.grey[800]!,
      muted: widget.isDark ? Colors.grey[500]! : Colors.grey[500]!,
    );
  }

  Widget _buildApproval(Map<String, dynamic> event) {
    final options = ((event['options'] as List?) ?? const []).map((option) {
      if (option is Map) {
        return BeUIApprovalOption(
          label: (option['label'] ?? option['title'] ?? '').toString(),
          description: option['description']?.toString(),
        );
      }
      return BeUIApprovalOption(label: option.toString());
    }).where((option) => option.label.isNotEmpty).toList();
    return BeUIApprovalCard(
      question: event['question']?.toString() ?? 'Confirmer cette action ?',
      description: event['description']?.toString(),
      options: options,
      multiSelect: event['multiSelect'] == true,
      allowTextInput: event['allowTextInput'] == true,
      textInputPlaceholder: event['textInputPlaceholder']?.toString(),
      onOptionsSelected: (_) {},
      onTextSubmitted: widget.onApprovalText,
      onDeny: widget.onApprovalDeny,
      isDark: widget.isDark,
    );
  }

  String _extractText(String text) {
    final match = RegExp(
      r'<(think|thought)>[\s\S]*?(?:</\1>|$)',
      caseSensitive: false,
    );
    return text.replaceAll(match, '').trim();
  }

  void _copy(String text) {
    if (text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copié !', style: TextStyle(fontSize: 12)),
        duration: Duration(seconds: 1),
      ),
    );
  }
}

class _TextSegment {
  final String value;
  final String? language;
  final bool isCode;

  const _TextSegment(this.value, {this.language, required this.isCode});
}

List<_TextSegment> _splitCodeFences(String text) {
  final segments = <_TextSegment>[];
  final pattern = RegExp(r'```([^\n]*)\n([\s\S]*?)```');
  var cursor = 0;
  for (final match in pattern.allMatches(text)) {
    final before = text.substring(cursor, match.start).trim();
    if (before.isNotEmpty) {
      segments.add(_TextSegment(before, isCode: false));
    }
    final language = match.group(1)?.trim();
    final code = match.group(2) ?? '';
    segments.add(_TextSegment(
      code.endsWith('\n') ? code.substring(0, code.length - 1) : code,
      language: language?.isEmpty == true ? null : language,
      isCode: true,
    ));
    cursor = match.end;
  }
  final after = text.substring(cursor).trim();
  if (after.isNotEmpty) segments.add(_TextSegment(after, isCode: false));
  return segments.isEmpty
      ? <_TextSegment>[_TextSegment(text, isCode: false)]
      : segments;
}