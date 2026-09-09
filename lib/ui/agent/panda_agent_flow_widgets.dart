import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/broken_icons.dart';
import 'flow_ui/models/flow_attachment.dart';
import 'flow_ui/models/flow_message_data.dart';
import 'flow_ui/models/flow_message_part.dart';
import 'flow_ui/widgets/flow_markdown.dart';
import 'flow_ui/widgets/flow_thinking_indicator.dart';
import 'flow_ui/widgets/flow_thread.dart';

/// The Panda host adapter for Flow UI.
///
/// Domain messages stay in the shape used by the agent runner, while this
/// widget owns the only conversion into Flow UI's immutable message model.
/// The runner talks directly to Flow UI through this focused adapter.
class PandaAgentFlowChat extends StatelessWidget {
  const PandaAgentFlowChat({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.isGenerating,
    this.onRetry,
    this.onToolApproval,
    this.onAlwaysAllowTools,
    this.onOpenTool,
  });

  final List<Map<String, dynamic>> messages;
  final ScrollController scrollController;
  final bool isGenerating;
  final void Function(int index)? onRetry;
  final ValueChanged<bool>? onToolApproval;
  final VoidCallback? onAlwaysAllowTools;
  final void Function(String name, Map<String, dynamic> args, String? result)?
      onOpenTool;

  List<FlowMessageData> _flowMessages() {
    return [
      for (var index = 0; index < messages.length; index++)
        _toFlowMessage(messages[index], index),
    ];
  }

  FlowMessageData _toFlowMessage(Map<String, dynamic> source, int index) {
    final isUser = source['role'] == 'user';
    final text = source['text']?.toString() ?? '';
    final sourcePhase = source['phase']?.toString() ?? 'done';
    final status = switch (sourcePhase) {
      'streaming' => FlowMessageStatus.streaming,
      'error' => FlowMessageStatus.error,
      _ => FlowMessageStatus.complete,
    };
    final parts = <FlowMessagePart>[];

    if (isUser) {
      final attachments = (source['attachments'] as List?)
              ?.whereType<Map>()
              .map(
                (attachment) => FlowAttachment(
                  id: attachment['path']?.toString().isNotEmpty == true
                      ? attachment['path'].toString()
                      : attachment['name']?.toString() ?? '',
                  label: attachment['name']?.toString(),
                  kind: _attachmentKind(attachment['name']?.toString()),
                ),
              )
              .where((attachment) => attachment.id.isNotEmpty)
              .toList() ??
          <FlowAttachment>[];
      if (attachments.isNotEmpty) {
        parts.add(FlowAttachmentPart(attachments));
      }
      if (text.isNotEmpty) parts.add(FlowTextPart(text));
      return FlowMessageData(
        id: 'agent-message-$index',
        role: FlowMessageRole.user,
        parts: parts,
        status: status,
      );
    }

    final blocks = (source['blocks'] as List?)
            ?.whereType<Map>()
            .map((block) => Map<String, dynamic>.from(block))
            .toList() ??
        <Map<String, dynamic>>[];
    // Keep one lightweight activity line in the message stream. It replaces
    // both FlowThread's pending indicator and the old sticky footer activity:
    // the line is inserted after the user message and content grows below it.
    final showThinkingLine =
        source['showThinkingLine'] == true ||
        sourcePhase == 'streaming' ||
        blocks.any((block) => block['type'] == 'thinkingLine');
    if (showThinkingLine) {
      parts.add(
        FlowCustomPart(
          type: 'thinkingLine',
          data: {
            'active': isGeneratingMessage(source),
          },
        ),
      );
    }
    if (blocks.isNotEmpty) {
      for (final block in blocks) {
        final type = block['type']?.toString() ?? '';
        if (type == 'toolCall') {
          parts.add(FlowCustomPart(type: 'tool', data: block));
        } else if (type == 'thinking') {
          // Thinking is represented by the persistent inline activity line.
          // Do not add a second expandable card for the same turn.
        } else if (type == 'text') {
          final value = _withoutThinking(block['text']?.toString() ?? '');
          final todo = _parseTodo(value);
          if (todo == null) {
            if (value.trim().isNotEmpty) parts.add(FlowTextPart(value));
          } else {
            final before = todo['before']?.toString().trim() ?? '';
            final after = todo['after']?.toString().trim() ?? '';
            if (before.isNotEmpty) parts.add(FlowTextPart(before));
            parts.add(
              FlowCustomPart(
                type: 'todo',
                data: {
                  'title': todo['title'],
                  'items': todo['items'],
                },
              ),
            );
            if (after.isNotEmpty) parts.add(FlowTextPart(after));
          }
        }
      }
    } else {
      if (text.trim().isNotEmpty) {
        final value = _withoutThinking(text);
        final todo = _parseTodo(value);
        if (todo == null) {
          if (value.trim().isNotEmpty) parts.add(FlowTextPart(value));
        } else {
          final before = todo['before']?.toString().trim() ?? '';
          final after = todo['after']?.toString().trim() ?? '';
          if (before.isNotEmpty) parts.add(FlowTextPart(before));
          parts.add(
            FlowCustomPart(
              type: 'todo',
              data: {
                'title': todo['title'],
                'items': todo['items'],
              },
            ),
          );
          if (after.isNotEmpty) parts.add(FlowTextPart(after));
        }
      }
      final calls = (source['toolCalls'] as List?)
              ?.whereType<Map>()
              .map((call) => <String, dynamic>{
                    ...Map<String, dynamic>.from(call),
                    'type': 'toolCall',
                  }) ??
          const <Map<String, dynamic>>[];
      for (final call in calls) {
        parts.add(FlowCustomPart(type: 'tool', data: call));
      }
    }
    final effectiveStatus = parts.isEmpty && status == FlowMessageStatus.streaming
        ? FlowMessageStatus.pending
        : status;
    return FlowMessageData(
      id: 'agent-message-$index',
      role: FlowMessageRole.assistant,
      parts: parts,
      status: effectiveStatus,
    );
  }

  static bool isGeneratingMessage(Map<String, dynamic> source) =>
      source['phase']?.toString() == 'streaming';

  static String _withoutThinking(String value) {
    if (value.trim().isEmpty) return '';
    final withoutThinking = value
        .replaceAll(
          RegExp(r'<(think|thought)>[\s\S]*?(?:</\1>|$)',
              caseSensitive: false),
          '',
        )
        .trim();
    return _normalizeMarkup(withoutThinking);
  }

  static String _normalizeMarkup(String value) {
    var normalized = value
        .replaceAll(
          RegExp(r'<pre[^>]*>\s*<code[^>]*>', caseSensitive: false),
          '\n```\n',
        )
        .replaceAll(
          RegExp(r'</code>\s*</pre>', caseSensitive: false),
          '\n```\n',
        )
        .replaceAll(
          RegExp(r'<br\s*/?>', caseSensitive: false),
          '\n',
        )
        .replaceAll(
          RegExp(r'</?(p|div|section|article|blockquote)>', caseSensitive: false),
          '\n\n',
        )
        .replaceAll(
          RegExp(r'<h[1-6][^>]*>', caseSensitive: false),
          '### ',
        )
        .replaceAll(
          RegExp(r'</h[1-6]>', caseSensitive: false),
          '\n\n',
        )
        .replaceAll(
          RegExp(r'<li[^>]*>', caseSensitive: false),
          '- ',
        )
        .replaceAll(
          RegExp(r'</li>', caseSensitive: false),
          '\n',
        )
        .replaceAll(
          RegExp(r'<(?:ul|ol)[^>]*>', caseSensitive: false),
          '\n',
        )
        .replaceAll(
          RegExp(r'</(?:ul|ol)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(
          RegExp(r'<(?:table|thead|tbody)[^>]*>', caseSensitive: false),
          '\n',
        )
        .replaceAll(
          RegExp(r'</(?:table|thead|tbody)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(
          RegExp(r'<tr[^>]*>', caseSensitive: false),
          '\n',
        )
        .replaceAll(
          RegExp(r'</tr>', caseSensitive: false),
          '\n',
        )
        .replaceAll(
          RegExp(r'<t[dh][^>]*>', caseSensitive: false),
          '| ',
        )
        .replaceAll(
          RegExp(r'</t[dh]>', caseSensitive: false),
          ' | ',
        )
        .replaceAll(
          RegExp(r'<hr\s*/?>', caseSensitive: false),
          '\n---\n',
        )
        .replaceAll(
          RegExp(r'<(strong|b)[^>]*>', caseSensitive: false),
          '**',
        )
        .replaceAll(
          RegExp(r'</(strong|b)>', caseSensitive: false),
          '**',
        )
        .replaceAll(
          RegExp(r'<(em|i)[^>]*>', caseSensitive: false),
          '*',
        )
        .replaceAll(
          RegExp(r'</(em|i)>', caseSensitive: false),
          '*',
        )
        .replaceAll(
          RegExp(r'<code[^>]*>', caseSensitive: false),
          '`',
        )
        .replaceAll(
          RegExp(r'</code>', caseSensitive: false),
          '`',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '');
    return normalized
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Converts the checkbox syntax agents commonly emit into a first-class
  /// card. Keeping it as a custom part avoids trying to reproduce a todo
  /// panel with markdown and gives the UI one consistent divider and row
  /// rhythm.
  static Map<String, dynamic>? _parseTodo(String value) {
    final lines = value.split('\n');
    final taskIndexes = <int>[];
    final items = <Map<String, dynamic>>[];
    final taskPattern = RegExp(
      r'^\s*(?:[-*]|\d+\.)\s*\[([ xX])\]\s*(.+?)\s*$',
    );
    for (var index = 0; index < lines.length; index++) {
      final match = taskPattern.firstMatch(lines[index]);
      if (match == null) continue;
      taskIndexes.add(index);
      items.add({
        'done': match.group(1)!.toLowerCase() == 'x',
        'label': match.group(2)!.trim(),
      });
    }
    if (items.isEmpty) return null;

    final first = taskIndexes.first;
    final last = taskIndexes.last;
    final beforeLines = lines.take(first).toList();
    final afterLines = lines.skip(last + 1).toList();
    var title = 'Todos';
    if (beforeLines.isNotEmpty) {
      final candidate = beforeLines.last
          .replaceFirst(RegExp(r'^#+\s*'), '')
          .trim();
      if (candidate.isNotEmpty &&
          RegExp(r'todo|task|plan|étape|etape', caseSensitive: false)
              .hasMatch(candidate)) {
        title = candidate;
        beforeLines.removeLast();
      }
    }
    return {
      'title': title,
      'items': items,
      'before': beforeLines.join('\n'),
      'after': afterLines.join('\n'),
    };
  }

  static String? _attachmentKind(String? name) {
    if (name == null || name.isEmpty) return null;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1).toUpperCase();
  }

  static Map<String, dynamic> _toolArgs(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Keep the card usable even when a provider sends malformed JSON.
      }
    }
    return <String, dynamic>{};
  }

  Widget _buildCustomPart(
    BuildContext context,
    FlowMessageData message,
    FlowCustomPart part,
  ) {
    final data = part.data is Map
        ? Map<String, dynamic>.from(part.data as Map)
        : <String, dynamic>{};
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = Theme.of(context).colorScheme.onSurface;
    final muted = foreground.withValues(alpha: 0.58);

    final rawResult = data['result']?.toString();
    final normalizedResult = rawResult == null
        ? null
        : _normalizeMarkup(_withoutThinking(rawResult));
    final args = _toolArgs(data['args'] ?? data['arguments']);

    return switch (part.type) {
      'tool' => PandaAgentFlowToolCard(
          toolName: (data['name'] ?? data['toolName'] ?? 'outil').toString(),
          args: args,
          result: normalizedResult,
          status: (data['status'] ?? 'done').toString(),
          dark: dark,
          foreground: foreground,
          muted: muted,
          onAllow: onToolApproval == null
              ? null
              : () => onToolApproval!(true),
          onAlways: onAlwaysAllowTools == null
              ? null
              : () {
                  onAlwaysAllowTools!();
                  onToolApproval?.call(true);
                },
          onDeny: onToolApproval == null
              ? null
              : () => onToolApproval!(false),
          onOpen: onOpenTool == null
              ? null
              : () => onOpenTool!(
                    (data['name'] ?? data['toolName'] ?? '').toString(),
                    args,
                    normalizedResult,
                  ),
        ),
      'thinkingLine' => PandaAgentFlowThinkingLine(
          active: data['active'] == true &&
              isGenerating &&
              message.status == FlowMessageStatus.streaming,
        ),
      'todo' => PandaAgentTodoCard(
          title: data['title']?.toString() ?? 'Todos',
          items: (data['items'] as List?)
                  ?.whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList() ??
              const <Map<String, dynamic>>[],
        ),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final flowMessages = _flowMessages();
    return FlowThread(
      messages: flowMessages,
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      itemSpacing: 24,
      customPartBuilder: _buildCustomPart,
      messageFooter: null,
      onRetry: onRetry == null
          ? null
          : (message) {
              final index = int.tryParse(
                message.id.replaceFirst('agent-message-', ''),
              );
              if (index != null) onRetry!(index);
            },
      retryLabel: 'Réessayer',
      thinkingLabel: null,
      markdown: true,
    );
  }
}

class PandaAgentTodoCard extends StatefulWidget {
  const PandaAgentTodoCard({
    super.key,
    required this.title,
    required this.items,
  });

  final String title;
  final List<Map<String, dynamic>> items;

  @override
  State<PandaAgentTodoCard> createState() => _PandaAgentTodoCardState();
}

class _PandaAgentTodoCardState extends State<PandaAgentTodoCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completed = widget.items
        .where((item) => item['done'] == true)
        .length;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Broken.arrow_down_2 : Broken.arrow_right_2,
                    size: 19,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${widget.title} ($completed/${widget.items.length})',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Broken.task,
                    size: 19,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: !_expanded
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: colors.outlineVariant.withValues(alpha: 0.7),
                      ),
                      for (final item in widget.items)
                        _PandaTodoRow(
                          label: item['label']?.toString() ?? '',
                          done: item['done'] == true,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PandaTodoRow extends StatelessWidget {
  const _PandaTodoRow({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 7, 13, 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              done ? Broken.tick_circle : Broken.radio,
              size: 20,
              color: done ? colors.tertiary : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: FlowMarkdown(
              text: label,
              isStreaming: false,
              style: TextStyle(
                color: done
                    ? colors.onSurfaceVariant
                    : colors.onSurface,
                fontSize: 13.5,
                height: 1.35,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PandaAgentFlowThinkingLine extends StatelessWidget {
  const PandaAgentFlowThinkingLine({
    super.key,
    this.active = false,
  });

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Row(
        children: [
          FlowThinkingIndicator(
            label: 'Thinking',
            active: active,
            size: 12,
            color: colors.primary,
          ),
        ],
      ),
    );
  }
}

class PandaAgentFlowToolCard extends StatelessWidget {
  const PandaAgentFlowToolCard({
    super.key,
    required this.toolName,
    required this.args,
    required this.result,
    required this.status,
    required this.dark,
    required this.foreground,
    required this.muted,
    this.onAllow,
    this.onAlways,
    this.onDeny,
    this.onOpen,
  });

  final String toolName;
  final Map<String, dynamic> args;
  final String? result;
  final String status;
  final bool dark;
  final Color foreground;
  final Color muted;
  final VoidCallback? onAllow;
  final VoidCallback? onAlways;
  final VoidCallback? onDeny;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => _PandaToolCardInteraction(card: this);

  String get _command {
    for (final key in const [
      'command',
      'cmd',
      'path',
      'file_path',
      'pattern',
      'query',
      'url',
    ]) {
      final value = args[key]?.toString();
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return args.values.map((value) => value?.toString() ?? '').join(' ');
  }

  String get _formattedArgs {
    if (args.isEmpty) return '';
    try {
      return const JsonEncoder.withIndent('  ').convert(args);
    } catch (_) {
      return args.toString();
    }
  }

  bool get _isShellCommand {
    final value = toolName.toLowerCase();
    return value.contains('shell') ||
        value.contains('command') ||
        value.contains('terminal') ||
        value.contains('exec') ||
        value.contains('bash') ||
        value == 'run';
  }

  bool get _failed {
    final value = result?.toLowerCase() ?? '';
    return status == 'error' ||
        status == 'failed' ||
        value.contains('command not found') ||
        value.contains('error:') ||
        value.contains('failed');
  }

  Widget _buildCard(
    BuildContext context, {
    required bool collapsed,
    required VoidCallback onToggle,
  }) {
    final approval = status == 'pending' || status == 'pending_approval';
    final running = status == 'running';
    final shell = _isShellCommand;
    final hasDetails = approval ||
        _command.trim().isNotEmpty ||
        (result?.trim().isNotEmpty ?? false);
    final accent = approval
        ? Colors.amber.shade700
        : shell
            ? (_failed ? Colors.redAccent : Colors.green)
            : foreground;

    Widget iconTile() {
      final child = shell && !approval
          ? Text(
              '>_',
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
              ),
            )
          : Icon(
              approval ? Broken.warning_2 : pandaAgentToolIcon(toolName),
              size: 17,
              color: accent,
            );
      return Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: foreground.withValues(alpha: 0.07)),
        ),
        child: child,
      );
    }

    Widget statusWidget() {
      if (running) {
        return const SizedBox.square(
          dimension: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        );
      }
      if (onOpen != null) {
        return IconButton(
          tooltip: 'Ouvrir dans un onglet',
          onPressed: onOpen,
          icon: Icon(Broken.export, size: 14, color: muted),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 24, height: 24),
        );
      }
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: hasDetails ? onToggle : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  iconTile(),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      approval
                          ? 'Approbation requise · $toolName'
                          : toolName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  statusWidget(),
                  const SizedBox(width: 2),
                  if (hasDetails)
                    Icon(
                      collapsed ? Broken.arrow_right_2 : Broken.arrow_down_2,
                      size: 17,
                      color: muted,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (hasDetails)
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: collapsed
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 2),
                    child: _buildDetails(
                      approval: approval,
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _buildDetails({
    required bool approval,
  }) {
    final shell = _isShellCommand;
    final running = status == 'running';
    final panelBorder = foreground.withValues(alpha: dark ? 0.14 : 0.12);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: panelBorder),
      ),
      child: approval
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  args.isEmpty
                      ? 'Cette action demande votre autorisation.'
                      : _formattedArgs,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.75),
                    fontSize: 11,
                    height: 1.35,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _approvalButton(
                      label: 'Autoriser',
                      icon: Broken.check,
                      color: Colors.green,
                      onPressed: onAllow,
                    ),
                    _approvalButton(
                      label: 'Toujours',
                      icon: Broken.tick_circle,
                      color: Colors.blue,
                      onPressed: onAlways,
                    ),
                    _approvalButton(
                      label: 'Refuser',
                      icon: Broken.close_circle,
                      color: Colors.redAccent,
                      onPressed: onDeny,
                    ),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_command.isNotEmpty || shell)
                  Row(
                    children: [
                      if (shell)
                        Text(
                          '>_',
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.72),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        )
                      else
                        Icon(
                          pandaAgentToolIcon(toolName),
                          size: 13,
                          color: muted,
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _command.isEmpty ? toolName : _command,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.82),
                            fontSize: 10.5,
                            height: 1.25,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (running)
                        const SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.3),
                        )
                      else if (shell && result?.trim().isNotEmpty == true)
                        Icon(
                          _failed ? Broken.close_circle : Broken.tick_circle,
                          size: 14,
                          color: _failed ? Colors.redAccent : Colors.green,
                        ),
                    ],
                  ),
                if ((_command.isNotEmpty || shell) &&
                    result != null &&
                    result!.trim().isNotEmpty)
                  const SizedBox(height: 6),
                if (result != null && result!.trim().isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        child: FlowMarkdown(
                          text: result!.trim(),
                          isStreaming: false,
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.82),
                            fontSize: 10.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _approvalButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
  }
}

class _PandaToolCardInteraction extends StatefulWidget {
  const _PandaToolCardInteraction({required this.card});

  final PandaAgentFlowToolCard card;

  @override
  State<_PandaToolCardInteraction> createState() =>
      _PandaToolCardInteractionState();
}

class _PandaToolCardInteractionState extends State<_PandaToolCardInteraction> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return card._buildCard(
      context,
      collapsed: _collapsed,
      onToggle: () => setState(() => _collapsed = !_collapsed),
    );
  }
}

class PandaAgentFlowSpinner extends StatefulWidget {
  const PandaAgentFlowSpinner({
    super.key,
    this.size = 12,
    this.color = Colors.blueAccent,
  });

  final double size;
  final Color color;

  @override
  State<PandaAgentFlowSpinner> createState() => _PandaAgentFlowSpinnerState();
}

class _PandaAgentFlowSpinnerState extends State<PandaAgentFlowSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) => Transform.rotate(
        angle: _controller.value * 6.283185,
        child: child,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(2),
        ),
        child: SizedBox.square(dimension: widget.size),
      ),
    );
  }
}

IconData pandaAgentToolIcon(String name) {
  final value = name.toLowerCase();
  if (value.contains('think') || value.contains('reason')) {
    return Broken.cpu;
  }
  if (value.contains('skill') ||
      value.contains('capability') ||
      value.contains('load')) {
    return Broken.magic_star;
  }
  if (value.contains('read') || value.contains('list') || value.contains('file')) {
    return Broken.document;
  }
  if (value.contains('write') ||
      value.contains('edit') ||
      value.contains('create')) {
    return Broken.edit;
  }
  if (value.contains('search') ||
      value.contains('grep') ||
      value.contains('find') ||
      value.contains('web')) {
    return Broken.search_normal;
  }
  if (value.contains('terminal') ||
      value.contains('bash') ||
      value.contains('exec') ||
      value.contains('run') ||
      value.contains('shell')) {
    return Broken.command;
  }
  if (value.contains('git')) return Broken.programming_arrows;
  if (value.contains('delete') || value.contains('remove')) {
    return Broken.trash;
  }
  return Broken.setting_3;
}
