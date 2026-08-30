/// Compatibility shim — maps old BEUI class names to Flow UI components.
///
/// This file exists so home.dart compiles while we migrate from BEUI to Flow UI.
/// All classes here are thin wrappers around Flow UI widgets.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'flow_ui/widgets/flow_chat_view.dart';
import 'flow_ui/widgets/flow_composer.dart';
import 'flow_ui/widgets/flow_message.dart';
import 'flow_ui/widgets/flow_markdown.dart';
import 'flow_ui/widgets/flow_thinking_indicator.dart';
import 'flow_ui/widgets/flow_code_block.dart';
import 'flow_ui/widgets/flow_message_actions.dart';
import 'flow_ui/widgets/flow_greeting.dart';
import 'flow_ui/models/flow_message_data.dart';
import 'flow_ui/styles/flow_message_style.dart';
import 'flow_ui/theme/flow_theme.dart';
import 'flow_ui/theme/flow_colors.dart';
import '../../core/broken_icons.dart';
import 'agent_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Enums matching old BEUI names
// ═══════════════════════════════════════════════════════════════════════════

enum BeUIMessageRole { user, assistant }

enum BeUIBubbleTone { user, assistant }

// ═══════════════════════════════════════════════════════════════════════════
// BeUIPromptInput → wraps FlowComposer-style input
// ═══════════════════════════════════════════════════════════════════════════

class BeUIPromptInput extends StatelessWidget {
  final TextEditingController controller;
  final bool isGenerating;
  final VoidCallback onSubmitted;
  final VoidCallback onCancel;
  final bool isDark;
  final List<Widget>? contextCards;
  final Widget? footer;

  const BeUIPromptInput({
    super.key,
    required this.controller,
    required this.isGenerating,
    required this.onSubmitted,
    required this.onCancel,
    required this.isDark,
    this.contextCards,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xff2a2a2e) : const Color(0xfff0f0f0);
    final fg = isDark ? const Color(0xffe0e0e0) : const Color(0xff222222);
    final hintColor = isDark ? const Color(0xff666666) : const Color(0xff999999);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (contextCards != null && contextCards!.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: contextCards!,
            ),
          ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
            child: footer!,
          ),
        Container(
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xff3a3a3e) : const Color(0xffe0e0e0),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  style: TextStyle(fontSize: 14, color: fg),
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Écrire un message à Panda Agent...',
                    hintStyle: TextStyle(color: hintColor, fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onSubmitted: (_) => onSubmitted(),
                ),
              ),
              if (isGenerating)
                IconButton(
                  icon: const Icon(Icons.stop_rounded, color: Colors.redAccent, size: 22),
                  onPressed: onCancel,
                )
              else
                IconButton(
                  icon: Icon(Icons.send_rounded, color: fg.withValues(alpha: 0.7), size: 20),
                  onPressed: onSubmitted,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BeUIMessageScroller → wraps a ListView.builder
// ═══════════════════════════════════════════════════════════════════════════

class BeUIMessageScroller extends StatelessWidget {
  final ScrollController? scrollController;
  final bool isStreaming;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const BeUIMessageScroller({
    super.key,
    this.scrollController,
    this.isStreaming = false,
    this.backgroundColor,
    this.padding,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: padding ?? const EdgeInsets.all(8),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BeUIMessage + BeUIMessageBubble
// ═══════════════════════════════════════════════════════════════════════════

class BeUIMessage extends StatelessWidget {
  final BeUIMessageRole role;
  final bool isGrouped;
  final Widget child;

  const BeUIMessage({
    super.key,
    required this.role,
    this.isGrouped = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = role == BeUIMessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
  }
}

class BeUIMessageBubble extends StatelessWidget {
  final BeUIBubbleTone tone;
  final String text;
  final bool expandable;
  final bool animateIn;

  const BeUIMessageBubble({
    super.key,
    required this.tone,
    required this.text,
    this.expandable = true,
    this.animateIn = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = tone == BeUIBubbleTone.user;
    final bg = isUser
        ? (isDark ? const Color(0xff2d5a8a) : const Color(0xffd4e5f7))
        : (isDark ? const Color(0xff2a2a2e) : const Color(0xfff5f5f5));
    final fg = isDark ? const Color(0xffe0e0e0) : const Color(0xff222222);

    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SelectableText(text, style: TextStyle(fontSize: 14, color: fg, height: 1.5)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AgentActivityFeed
// ═══════════════════════════════════════════════════════════════════════════

class AgentActivityFeed extends StatelessWidget {
  final dynamic controller;
  final bool isDark;
  final Color fg;
  final Color muted;

  const AgentActivityFeed({
    super.key,
    required this.controller,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    // Minimal activity feed — shows thinking indicator when active
    return const SizedBox.shrink();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AgentCheckpointCard
// ═══════════════════════════════════════════════════════════════════════════

class AgentCheckpointCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isDark;
  final Color fg;
  final Color muted;
  final VoidCallback onRestore;
  final VoidCallback onOpenGit;

  const AgentCheckpointCard({
    super.key,
    required this.data,
    required this.isDark,
    required this.fg,
    required this.muted,
    required this.onRestore,
    required this.onOpenGit,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xff1e2a1e) : const Color(0xffe8f5e8);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xff4caf50).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.commit, size: 16, color: Color(0xff4caf50)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              data['message']?.toString() ?? 'Checkpoint',
              style: TextStyle(fontSize: 12, color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onRestore,
            child: const Text('Restaurer', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AgentMarkdownView
// ═══════════════════════════════════════════════════════════════════════════

class AgentMarkdownView extends StatelessWidget {
  final String markdown;
  final bool isDark;
  final Color fg;
  final bool isError;
  final bool isStreaming;

  const AgentMarkdownView({
    super.key,
    required this.markdown,
    required this.isDark,
    required this.fg,
    this.isError = false,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    if (markdown.trim().isEmpty) return const SizedBox.shrink();
    return FlowMarkdown(
      text: markdown,
      isStreaming: isStreaming,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MsgActionBtn
// ═══════════════════════════════════════════════════════════════════════════

class MsgActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color muted;

  const MsgActionBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: muted),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ReflectionBox
// ═══════════════════════════════════════════════════════════════════════════

class ReflectionBox extends StatelessWidget {
  final String content;
  final bool isActive;
  final bool isDark;
  final Color fg;
  final Color muted;

  const ReflectionBox({
    super.key,
    required this.content,
    required this.isActive,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xff1a1e2a) : const Color(0xffeef2ff);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isDark ? const Color(0xff4a5a8a) : const Color(0xffb0c4de)).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isActive)
            FlowThinkingIndicator(
              active: true,
              color: isDark ? const Color(0xff6a8aff) : const Color(0xff3366cc),
              size: 14,
            )
          else
            Icon(Icons.psychology, size: 14, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              content,
              style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.8), height: 1.5),
              maxLines: isActive ? null : 4,
              overflow: isActive ? null : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BeUIToolApproval
// ═══════════════════════════════════════════════════════════════════════════

class BeUIToolApproval extends StatelessWidget {
  final String toolName;
  final Map<String, dynamic> args;
  final VoidCallback onAllow;
  final VoidCallback onAlways;
  final VoidCallback onDeny;
  final bool isDark;

  const BeUIToolApproval({
    super.key,
    required this.toolName,
    required this.args,
    required this.onAllow,
    required this.onAlways,
    required this.onDeny,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xff2a2220) : const Color(0xfffff8e1);
    final fg = isDark ? const Color(0xffe0e0e0) : const Color(0xff222222);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
              const SizedBox(width: 6),
              Text('Approbation requise', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
            ],
          ),
          const SizedBox(height: 6),
          Text(toolName, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: fg.withValues(alpha: 0.8))),
          if (args.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(args.toString(), style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: fg.withValues(alpha: 0.6), height: 1.3)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                onPressed: onAllow,
                icon: const Icon(Icons.check, size: 14),
                label: const Text('Autoriser', style: TextStyle(fontSize: 11)),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xff4caf50), minimumSize: const Size(0, 32)),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: onAlways,
                icon: const Icon(Icons.done_all, size: 14),
                label: const Text('Toujours', style: TextStyle(fontSize: 11)),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xff2196f3), minimumSize: const Size(0, 32)),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: onDeny,
                icon: const Icon(Icons.close, size: 14),
                label: const Text('Refuser', style: TextStyle(fontSize: 11)),
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, minimumSize: const Size(0, 32)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AgentToolCallBlock
// ═══════════════════════════════════════════════════════════════════════════

class AgentToolCallBlock extends StatelessWidget {
  final String toolName;
  final Map<String, dynamic> args;
  final String? result;
  final String status;
  final bool isDark;
  final Color fg;
  final Color muted;
  final VoidCallback? onOpenInEditor;
  final bool showResultInline;

  const AgentToolCallBlock({
    super.key,
    required this.toolName,
    required this.args,
    this.result,
    this.status = 'done',
    required this.isDark,
    required this.fg,
    required this.muted,
    this.onOpenInEditor,
    this.showResultInline = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xff1e1e22) : const Color(0xfff5f5f5);
    final isRunning = status == 'running' || status == 'pending';
    final cmd = _extractCommand(args);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isRunning
              ? const Color(0xff6a8aff).withValues(alpha: 0.4)
              : (isDark ? const Color(0xff333338) : const Color(0xffe0e0e0)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              agentToolIconWidget(toolName, 14, fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  toolName,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace', color: fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isRunning)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: const Color(0xff6a8aff)),
                )
              else if (onOpenInEditor != null)
                InkWell(
                  onTap: onOpenInEditor,
                  child: Icon(Icons.open_in_new, size: 13, color: muted),
                ),
            ],
          ),
          if (cmd.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              cmd,
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: fg.withValues(alpha: 0.7), height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  static String _extractCommand(Map<String, dynamic> args) {
    for (final key in const ['command', 'cmd', 'path', 'file_path', 'pattern', 'query', 'url']) {
      final v = args[key]?.toString();
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    if (args.isEmpty) return '';
    return args.values.map((e) => e?.toString() ?? '').join(' ');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BeUIToolResult
// ═══════════════════════════════════════════════════════════════════════════

class BeUIToolResult extends StatelessWidget {
  final String title;
  final String output;
  final bool isRunning;
  final bool isDark;

  const BeUIToolResult({
    super.key,
    required this.title,
    required this.output,
    this.isRunning = false,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (output.trim().isEmpty) return const SizedBox.shrink();
    final bg = isDark ? const Color(0xff141418) : const Color(0xfffafafa);
    final fg = isDark ? const Color(0xffcccccc) : const Color(0xff333333);

    return Container(
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectableText(
        output,
        style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: fg.withValues(alpha: 0.85), height: 1.4),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AgentActionStrip (collapsible group of tool calls)
// ═══════════════════════════════════════════════════════════════════════════

class AgentActionStrip extends StatefulWidget {
  final List<Map<String, dynamic>> events;
  final bool isDark;
  final Color fg;
  final Color muted;
  final Widget Function(BuildContext) buildExpanded;

  const AgentActionStrip({
    super.key,
    required this.events,
    required this.isDark,
    required this.fg,
    required this.muted,
    required this.buildExpanded,
  });

  @override
  State<AgentActionStrip> createState() => _AgentActionStripState();
}

class _AgentActionStripState extends State<AgentActionStrip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.events.length;
    final toolNames = widget.events
        .map((e) => (e['name'] as String?) ?? (e['toolName'] as String?) ?? '?')
        .join(', ');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xff1e1e22) : const Color(0xfff8f8f8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Transform.rotate(
                    angle: _expanded ? 3.14159 / 2 : 0,
                    child: Icon(Icons.chevron_right, size: 16, color: widget.muted),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.build_circle_outlined, size: 14, color: widget.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$count action${count > 1 ? 's' : ''}: $toolNames',
                      style: TextStyle(fontSize: 11, color: widget.muted, fontFamily: 'monospace'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: widget.buildExpanded(context),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SpinningSquareIndicator
// ═══════════════════════════════════════════════════════════════════════════

class SpinningSquareIndicator extends StatefulWidget {
  final double size;
  final Color color;

  const SpinningSquareIndicator({super.key, this.size = 12, this.color = Colors.blueAccent});

  @override
  State<SpinningSquareIndicator> createState() => _SpinningSquareIndicatorState();
}

class _SpinningSquareIndicatorState extends State<SpinningSquareIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.rotate(
        angle: _ctrl.value * 6.283,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PandaAgentBeUI (main agent chat container)
// ═══════════════════════════════════════════════════════════════════════════

class PandaAgentBeUI extends StatelessWidget {
  final List<Map<String, dynamic>> messages;
  final ScrollController? scrollController;
  final bool isGenerating;
  final String phase;
  final dynamic activityController;
  final void Function(int)? onRetry;
  final void Function(bool)? onToolApproval;
  final VoidCallback? onAlwaysAllowTools;
  final void Function(String, Map<String, dynamic>, String?)? onOpenTool;
  final bool isDark;

  const PandaAgentBeUI({
    super.key,
    required this.messages,
    this.scrollController,
    required this.isGenerating,
    required this.phase,
    this.activityController,
    this.onRetry,
    this.onToolApproval,
    this.onAlwaysAllowTools,
    this.onOpenTool,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: FlowGreeting(
          text: 'Panda Agent — Comment puis-je vous aider ?',
        ),
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final isUser = msg['role'] == 'user';
        final text = msg['text'] as String? ?? '';
        return FlowMessage(
          FlowMessageData.text(
            id: '$index',
            role: isUser ? FlowMessageRole.user : FlowMessageRole.assistant,
            text: text,
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Utility functions referenced in home.dart
// ═══════════════════════════════════════════════════════════════════════════

Widget agentToolIconWidget(String name, double size, Color color) {
  final lower = name.toLowerCase();
  IconData icon;
  if (lower.contains('read') || lower.contains('file')) {
    icon = Icons.description_outlined;
  } else if (lower.contains('write') || lower.contains('create')) {
    icon = Icons.edit_note;
  } else if (lower.contains('search') || lower.contains('grep') || lower.contains('find')) {
    icon = Icons.search;
  } else if (lower.contains('terminal') || lower.contains('bash') || lower.contains('exec') || lower.contains('run')) {
    icon = Icons.terminal;
  } else if (lower.contains('git')) {
    icon = Icons.account_tree;
  } else if (lower.contains('delete') || lower.contains('remove')) {
    icon = Icons.delete_outline;
  } else if (lower.contains('list') || lower.contains('dir')) {
    icon = Icons.folder_open;
  } else {
    icon = Icons.build_outlined;
  }
  return Icon(icon, size: size, color: color);
}

String wrapLongTokensForDisplay(String text) {
  if (text.isEmpty) return text;
  // Insert zero-width spaces after common delimiters to allow line breaks
  return text
      .replaceAll('/', '/\u200B')
      .replaceAll('\\', '\\\u200B')
      .replaceAll('.', '.\u200B')
      .replaceAll('-', '-\u200B')
      .replaceAll('_', '_\u200B')
      .replaceAll(':', ':\u200B');
}
