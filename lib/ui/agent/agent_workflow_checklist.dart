import 'package:flutter/material.dart';

import '../../core/broken_icons.dart';

/// Compact workflow view inspired by the task composer used in Panda Agent.
///
/// The widget is intentionally self-contained so it can be hosted in the
/// agent side panel or as a full page without duplicating the workflow chrome.
class AgentWorkflowChecklist extends StatefulWidget {
  const AgentWorkflowChecklist({
    super.key,
    this.onSubmit,
    this.onClose,
    this.onModeTap,
    this.onAddAttachment,
    this.onStop,
    this.initialAttachment = 'AGENT_WORKFLOW_ANALYSIS.md',
  });

  final ValueChanged<String>? onSubmit;
  final VoidCallback? onClose;
  final VoidCallback? onModeTap;
  final VoidCallback? onAddAttachment;
  final VoidCallback? onStop;
  final String? initialAttachment;

  @override
  State<AgentWorkflowChecklist> createState() => _AgentWorkflowChecklistState();
}

enum _WorkflowTaskStatus { complete, active, pending }

class _WorkflowTask {
  const _WorkflowTask(this.title, this.status);

  final String title;
  final _WorkflowTaskStatus status;

  _WorkflowTask copyWith({_WorkflowTaskStatus? status}) =>
      _WorkflowTask(title, status ?? this.status);
}

class _AgentWorkflowChecklistState extends State<AgentWorkflowChecklist> {
  var _expanded = true;
  late List<_WorkflowTask> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = [
      const _WorkflowTask(
        'Inspect agent workflow root cause',
        _WorkflowTaskStatus.complete,
      ),
      const _WorkflowTask(
        'Patch workflow and state handling',
        _WorkflowTaskStatus.active,
      ),
      const _WorkflowTask(
        'Validate through analysis/build',
        _WorkflowTaskStatus.pending,
      ),
      const _WorkflowTask(
        'Commit and push to GitHub',
        _WorkflowTaskStatus.pending,
      ),
    ];
  }

  @override
  void dispose() {
    super.dispose();
  }

  int get _progress =>
      _tasks.where((task) => task.status != _WorkflowTaskStatus.pending).length;

  void _toggleTask(int index) {
    setState(() {
      final task = _tasks[index];
      final next = task.status == _WorkflowTaskStatus.complete
          ? _WorkflowTaskStatus.pending
          : _WorkflowTaskStatus.complete;
      _tasks[index] = task.copyWith(status: next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xff0d1016) : colors.surface;
    final card = dark ? const Color(0xff11141c) : colors.surfaceContainerLow;
    final foreground = dark ? const Color(0xffe7eaf2) : colors.onSurface;
    final muted = dark ? const Color(0xff89909f) : colors.onSurfaceVariant;
    final line = dark ? const Color(0xff303540) : colors.outlineVariant;

    return ColoredBox(
      color: surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: card,
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(
                      foreground: foreground,
                      muted: muted,
                      line: line,
                    ),
                    if (_expanded) ...[
                      _buildBody(
                        foreground: foreground,
                        muted: muted,
                        line: line,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required Color foreground,
    required Color muted,
    required Color line,
  }) {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: line)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Row(
          children: [
            Icon(
              _expanded ? Broken.arrow_down_2 : Broken.arrow_right_2,
              size: 20,
              color: muted,
            ),
            const SizedBox(width: 10),
            Text(
              'Todos ($_progress/${_tasks.length})',
              style: TextStyle(
                color: foreground,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Fermer',
              onPressed: widget.onClose,
              icon: Icon(Broken.close_square, size: 20, color: muted),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: 'Options de la liste',
              onPressed: () {},
              icon: Icon(Broken.menu, size: 20, color: muted),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody({
    required Color foreground,
    required Color muted,
    required Color line,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: Column(
            children: [
              for (var index = 0; index < _tasks.length; index++)
                _buildTaskRow(
                  task: _tasks[index],
                  index: index,
                  foreground: foreground,
                  muted: muted,
                ),
            ],
          ),
        ),
        Container(height: 1, color: line),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
          child: _buildAttachmentRow(muted: muted),
        ),
      ],
    );
  }

  Widget _buildTaskRow({
    required _WorkflowTask task,
    required int index,
    required Color foreground,
    required Color muted,
  }) {
    final (icon, color) = switch (task.status) {
      _WorkflowTaskStatus.complete => (Broken.tick_circle, const Color(0xff8ce39d)),
      _WorkflowTaskStatus.active => (Broken.record_circle, const Color(0xff62a7ff)),
      _WorkflowTaskStatus.pending => (Broken.radio, foreground),
    };
    final textColor = task.status == _WorkflowTaskStatus.pending
        ? foreground
        : foreground.withValues(alpha: 0.95);

    return Semantics(
      button: true,
      label: task.title,
      child: InkWell(
        onTap: () => _toggleTask(index),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 23, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.25,
                  ),
                ),
              ),
              if (task.status == _WorkflowTaskStatus.active)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Broken.more_circle, size: 16, color: muted),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentRow({required Color muted}) {
    final file = widget.initialAttachment;
    return InkWell(
      onTap: widget.onAddAttachment,
      borderRadius: BorderRadius.circular(7),
      child: CustomPaint(
        painter: _DashedRoundedRectPainter(
          color: muted.withValues(alpha: 0.28),
          radius: 7,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Broken.add, size: 22, color: muted),
              if (file != null && file.isNotEmpty) ...[
                const SizedBox(width: 10),
                Icon(
                  Broken.arrow_down,
                  size: 17,
                  color: const Color(0xff57b7e8),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    file,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: muted,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

}

class _DashedRoundedRectPainter extends CustomPainter {
  const _DashedRoundedRectPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    const dash = 5.0;
    const gap = 4.0;
    for (var x = rect.left; x < rect.right; x += dash + gap) {
      canvas.drawLine(
        Offset(x, rect.top),
        Offset((x + dash).clamp(rect.left, rect.right).toDouble(), rect.top),
        paint,
      );
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(
          (x + dash).clamp(rect.left, rect.right).toDouble(),
          rect.bottom,
        ),
        paint,
      );
    }
    for (var y = rect.top; y < rect.bottom; y += dash + gap) {
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(
          rect.left,
          (y + dash).clamp(rect.top, rect.bottom).toDouble(),
        ),
        paint,
      );
      canvas.drawLine(
        Offset(rect.right, y),
        Offset(
          rect.right,
          (y + dash).clamp(rect.top, rect.bottom).toDouble(),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRoundedRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}