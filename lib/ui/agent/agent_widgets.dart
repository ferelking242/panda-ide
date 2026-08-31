import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/broken_icons.dart';
import 'agent_models.dart';

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

class SpinningSquareIndicator extends StatefulWidget {
  final double size;
  final Color color;

  const SpinningSquareIndicator({super.key, this.size = 12, this.color = Colors.blueAccent});

  @override
  State<SpinningSquareIndicator> createState() => _SpinningSquareIndicatorState();
}

class _SpinningSquareIndicatorState extends State<SpinningSquareIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
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
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * 3.14159,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              border: Border.all(color: widget.color, width: 1.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      },
    );
  }
}

class _AgentActionStripState extends State<AgentActionStrip> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

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

