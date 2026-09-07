import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'flow_ui/models/flow_attachment.dart';
import 'flow_ui/models/flow_message_data.dart';
import 'flow_ui/models/flow_message_part.dart';
import 'flow_ui/widgets/flow_markdown.dart';
import 'flow_ui/widgets/flow_shimmer_text.dart';
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
    this.currentTool = '',
    this.onRetry,
    this.onToolApproval,
    this.onAlwaysAllowTools,
    this.onOpenTool,
  });

  final List<Map<String, dynamic>> messages;
  final ScrollController scrollController;
  final bool isGenerating;
  final String phase;
  final String currentTool;
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
    if (blocks.isNotEmpty) {
      for (final block in blocks) {
        final type = block['type']?.toString() ?? '';
        if (type == 'toolCall') {
          parts.add(FlowCustomPart(type: 'tool', data: block));
        } else if (type == 'thinking') {
          final thinking = block['thinking']?.toString() ?? '';
          if (thinking.trim().isNotEmpty) {
            parts.add(FlowCustomPart(type: 'thinking', data: block));
          }
        } else if (type == 'text') {
          final value = _withoutThinking(block['text']?.toString() ?? '');
          if (value.trim().isNotEmpty) parts.add(FlowTextPart(value));
        }
      }
    } else {
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
    if (parts.isEmpty &&
        sourcePhase == 'streaming' &&
        isGeneratingMessage(source)) {
      parts.add(
        const FlowCustomPart(
          type: 'thinking',
          data: {'thinking': 'Réflexion en cours…'},
        ),
      );
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
      'thinking' => PandaAgentFlowThinkingBlock(
          text: data['thinking']?.toString() ?? '',
          active: isGenerating && message.status == FlowMessageStatus.streaming,
        ),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final flowMessages = _flowMessages();
    final latest = flowMessages.isEmpty ? null : flowMessages.last;
    final hasThinking = latest?.parts.any(
          (part) => part is FlowCustomPart && part.type == 'thinking',
        ) ??
        false;
    final activity = switch (phase) {
      'thinking' => hasThinking ? 'Thinking' : 'Starting',
      'toolRunning' => currentTool.isEmpty
          ? 'Working'
          : 'Running ${currentTool.replaceAll('runShellCommand', 'command')}',
      'streaming' => 'Writing',
      _ => 'Starting',
    };

    return Column(
      children: [
        Expanded(
          child: FlowThread(
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
            thinkingLabel: 'Thinking',
            markdown: true,
          ),
        ),
        if (isGenerating)
          _PandaAgentLiveActivity(
            label: activity,
          ),
      ],
    );
  }
}

class _PandaAgentLiveActivity extends StatelessWidget {
  const _PandaAgentLiveActivity({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 9),
      child: Row(
        children: [
          FlowThinkingIndicator(
            label: label,
            active: true,
            size: 13,
            color: colors.primary,
          ),
        ],
      ),
    );
  }
}

class PandaAgentFlowThinkingBlock extends StatefulWidget {
  const PandaAgentFlowThinkingBlock({
    super.key,
    required this.text,
    this.active = false,
  });

  final String text;
  final bool active;

  @override
  State<PandaAgentFlowThinkingBlock> createState() =>
      _PandaAgentFlowThinkingBlockState();
}

class _PandaAgentFlowThinkingBlockState
    extends State<PandaAgentFlowThinkingBlock> {
  bool _expanded = false;

  @override
  void didUpdateWidget(PandaAgentFlowThinkingBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = widget.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 17,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: widget.active
                        ? FlowShimmerText(
                            text: 'Thinking',
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : Text(
                            'Thinking',
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(36, 0, 14, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        text,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
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
    required bool showFullCommand,
  }) {
    final approval = status == 'pending' || status == 'pending_approval';
    final running = status == 'running';
    final shell = _isShellCommand;
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
              if (shell && !approval)
                Text(
                  '>_',
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                )
              else
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
                  approval
                      ? 'Approbation requise · $toolName'
                      : shell
                          ? (running
                              ? 'Command running'
                              : _failed
                                  ? 'Command failed'
                                  : 'Command executed')
                          : toolName,
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
              else if (shell)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (_failed ? Colors.redAccent : Colors.green)
                        .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    _failed ? 'FAIL' : 'OK',
                    color: _failed ? Colors.redAccent : Colors.green,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
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
          if (_command.isNotEmpty && !approval && !collapsed) ...[
            const SizedBox(height: 7),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: dark ? Colors.black.withValues(alpha: 0.28) : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: foreground.withValues(alpha: 0.08)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r'$',
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.46),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      showFullCommand
                          ? _command
                          : pandaWrapLongTokensForDisplay(_command),
                      maxLines: showFullCommand ? null : 1,
                      overflow: showFullCommand
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.82),
                        fontSize: 11,
                        height: 1.4,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (result != null &&
              result!.trim().isNotEmpty &&
              !approval &&
              !collapsed) ...[
            const SizedBox(height: 7),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: dark ? Colors.black26 : Colors.white70,
                borderRadius: BorderRadius.circular(6),
              ),
              child: FlowMarkdown(
                text: result!.trim(),
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.82),
                  fontSize: 11,
                  height: 1.4,
                ),
                charactersPerSecond: 1000,
              ),
            ),
          ],
          if (approval) ...[
            const SizedBox(height: 8),
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

class _PandaToolCardInteraction extends StatefulWidget {
  const _PandaToolCardInteraction({required this.card});

  final PandaAgentFlowToolCard card;

  @override
  State<_PandaToolCardInteraction> createState() =>
      _PandaToolCardInteractionState();
}

class _PandaToolCardInteractionState extends State<_PandaToolCardInteraction> {
  Timer? _holdTimer;
  bool _held = false;
  bool _collapsed = false;
  bool _showFullCommand = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _pressStarted() {
    if (!widget.card._isShellCommand) return;
    _held = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      setState(() {
        _held = true;
        _showFullCommand = true;
        _collapsed = false;
      });
    });
  }

  void _pressEnded() {
    _holdTimer?.cancel();
    if (_held) {
      _held = false;
      return;
    }
    if (widget.card._isShellCommand) {
      setState(() => _collapsed = !_collapsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return Listener(
      onPointerDown: (_) => _pressStarted(),
      onPointerUp: (_) => _pressEnded(),
      onPointerCancel: (_) => _holdTimer?.cancel(),
      child: card._buildCard(
        context,
        collapsed: _collapsed,
        showFullCommand: _showFullCommand,
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