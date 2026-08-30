import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'flow_ui/models/flow_attachment.dart';
import 'flow_ui/models/flow_message_data.dart';
import 'flow_ui/models/flow_message_part.dart';
import 'flow_ui/widgets/flow_message_actions.dart';
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
    required this.phase,
    this.onRetry,
    this.onToolApproval,
    this.onAlwaysAllowTools,
    this.onOpenTool,
  });

  final List<Map<String, dynamic>> messages;
  final ScrollController scrollController;
  final bool isGenerating;
  final String phase;
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
    final thinking = source['thinking']?.toString() ?? '';

    if (blocks.isNotEmpty) {
      for (final block in blocks) {
        final type = block['type']?.toString() ?? '';
        if (type == 'thinking') {
          final value = block['thinking']?.toString() ?? '';
          if (value.trim().isNotEmpty) {
            parts.add(FlowCustomPart(type: 'thinking', data: block));
          }
        } else if (type == 'toolCall') {
          parts.add(FlowCustomPart(type: 'tool', data: block));
        } else if (type == 'text') {
          final value = _withoutThinking(block['text']?.toString() ?? '');
          if (value.trim().isNotEmpty) parts.add(FlowTextPart(value));
        }
      }
    } else {
      if (thinking.trim().isNotEmpty) {
        parts.add(
          FlowCustomPart(
            type: 'thinking',
            data: <String, dynamic>{'thinking': thinking},
          ),
        );
      }
      if (text.trim().isNotEmpty) {
        final value = _withoutThinking(text);
        if (value.trim().isNotEmpty) parts.add(FlowTextPart(value));
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

  static String _withoutThinking(String value) {
    if (value.trim().isEmpty) return '';
    return value
        .replaceAll(
          RegExp(r'<(think|thought)>[\s\S]*?(?:</\1>|$)',
              caseSensitive: false),
          '',
        )
        .trim();
  }

  static String? _attachmentKind(String? name) {
    if (name == null || name.isEmpty) return null;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1).toUpperCase();
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

    return switch (part.type) {
      'thinking' => PandaAgentFlowThinking(
          content: (data['thinking'] ?? '').toString(),
          active: isGenerating && phase == 'thinking',
          dark: dark,
          foreground: foreground,
          muted: muted,
        ),
      'tool' => PandaAgentFlowToolCard(
          toolName: (data['name'] ?? data['toolName'] ?? 'outil').toString(),
          args: (data['args'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{},
          result: data['result']?.toString(),
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
                    (data['args'] as Map?)?.cast<String, dynamic>() ??
                        const <String, dynamic>{},
                    data['result']?.toString(),
                  ),
        ),
      _ => const SizedBox.shrink(),
    };
  }

  Widget? _messageFooter(FlowMessageData message) {
    if (message.role != FlowMessageRole.assistant) return null;
    final index = int.tryParse(message.id.replaceFirst('agent-message-', ''));
    if (index == null) return null;
    final text = message.parts
        .whereType<FlowTextPart>()
        .map((part) => part.text)
        .join('\n')
        .trim();
    final actions = <FlowMessageAction>[
      if (text.isNotEmpty)
        FlowMessageAction.copy(
          tooltip: 'Copier la réponse',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
          },
        ),
    ];
    if (actions.isEmpty) return null;
    return FlowMessageActions(actions: actions);
  }

  @override
  Widget build(BuildContext context) {
    return FlowThread(
      messages: _flowMessages(),
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      itemSpacing: 24,
      customPartBuilder: _buildCustomPart,
      messageFooter: _messageFooter,
      onRetry: onRetry == null
          ? null
          : (message) {
              final index = int.tryParse(
                message.id.replaceFirst('agent-message-', ''),
              );
              if (index != null) onRetry!(index);
            },
      retryLabel: 'Réessayer',
      thinkingLabel: 'Panda réfléchit…',
      markdown: true,
    );
  }
}

class PandaAgentFlowThinking extends StatelessWidget {
  const PandaAgentFlowThinking({
    super.key,
    required this.content,
    required this.active,
    required this.dark,
    required this.foreground,
    required this.muted,
  });

  final String content;
  final bool active;
  final bool dark;
  final Color foreground;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final background = dark
        ? const Color(0xff202033)
        : const Color(0xfff0f2ff);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (dark ? const Color(0xff7886d8) : const Color(0xff9ba8e8))
              .withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (active)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: FlowThinkingIndicator(size: 15, active: true),
            )
          else
            Icon(Icons.psychology_outlined, size: 16, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              content.trim(),
              style: TextStyle(
                color: foreground.withValues(alpha: 0.82),
                fontSize: 12,
                height: 1.5,
              ),
            ),
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

  @override
  Widget build(BuildContext context) {
    final approval = status == 'pending' || status == 'pending_approval';
    final running = status == 'running';
    final background = dark
        ? const Color(0xff202024)
        : const Color(0xfff5f5f7);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: approval
            ? (dark ? const Color(0xff302719) : const Color(0xfffff8e5))
            : background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: approval
              ? Colors.amber.withValues(alpha: 0.5)
              : foreground.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                approval
                    ? Icons.warning_amber_rounded
                    : pandaAgentToolIcon(toolName),
                size: 16,
                color: approval ? Colors.amber[700] : foreground,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  approval ? 'Approbation requise · $toolName' : toolName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (running)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else if (onOpen != null)
                IconButton(
                  tooltip: 'Ouvrir dans un onglet',
                  onPressed: onOpen,
                  icon: Icon(Icons.open_in_new, size: 14, color: muted),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 24, height: 24),
                ),
            ],
          ),
          if (_command.isNotEmpty && !approval) ...[
            const SizedBox(height: 7),
            SelectableText(
              pandaWrapLongTokensForDisplay(_command),
              style: TextStyle(
                color: foreground.withValues(alpha: 0.75),
                fontSize: 11,
                height: 1.4,
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (result != null && result!.trim().isNotEmpty && !approval) ...[
            const SizedBox(height: 7),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: dark ? Colors.black26 : Colors.white70,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                pandaWrapLongTokensForDisplay(result!.trim()),
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.82),
                  fontSize: 11,
                  height: 1.4,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
          if (approval) ...[
            const SizedBox(height: 8),
            Text(
              args.isEmpty ? 'Cette action demande votre autorisation.' : args.toString(),
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
                  icon: Icons.check,
                  color: Colors.green,
                  onPressed: onAllow,
                ),
                _approvalButton(
                  label: 'Toujours',
                  icon: Icons.done_all,
                  color: Colors.blue,
                  onPressed: onAlways,
                ),
                _approvalButton(
                  label: 'Refuser',
                  icon: Icons.close,
                  color: Colors.redAccent,
                  onPressed: onDeny,
                ),
              ],
            ),
          ],
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
  if (value.contains('read') || value.contains('list') || value.contains('file')) {
    return Icons.description_outlined;
  }
  if (value.contains('write') ||
      value.contains('edit') ||
      value.contains('create')) {
    return Icons.edit_note;
  }
  if (value.contains('search') ||
      value.contains('grep') ||
      value.contains('find') ||
      value.contains('web')) {
    return Icons.search;
  }
  if (value.contains('terminal') ||
      value.contains('bash') ||
      value.contains('exec') ||
      value.contains('run') ||
      value.contains('shell')) {
    return Icons.terminal;
  }
  if (value.contains('git')) return Icons.account_tree;
  if (value.contains('delete') || value.contains('remove')) {
    return Icons.delete_outline;
  }
  return Icons.build_outlined;
}

String pandaWrapLongTokensForDisplay(String text) {
  return text
      .replaceAll('/', '/\u200B')
      .replaceAll('\\', '\\\u200B')
      .replaceAll('.', '.\u200B')
      .replaceAll('-', '-\u200B')
      .replaceAll('_', '_\u200B')
      .replaceAll(':', ':\u200B');
}