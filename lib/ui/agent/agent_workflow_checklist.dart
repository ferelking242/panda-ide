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
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  var _mode = 'Auto';
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
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  int get _progress =>
      _tasks.where((task) => task.status != _WorkflowTaskStatus.pending).length;

  void _submit() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit?.call(text);
    _inputController.clear();
    _inputFocusNode.requestFocus();
  }

  void _toggleTask(int index) {
    setState(() {
      final task = _tasks[index];
      final next = task.status == _WorkflowTaskStatus.complete
          ? _WorkflowTaskStatus.pending
          : _WorkflowTaskStatus.complete;
      _tasks[index] = task.copyWith(status: next);
    });
  }

  void _cycleMode() {
    setState(() => _mode = _mode == 'Auto' ? 'Ask' : 'Auto');
    widget.onModeTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xff0d1016) : colors.surface;
    final card = dark ? const Color(0xff11141c) : colors.surfaceContainerLow;
    final input = dark ? const Color(0xff090b10) : colors.surface;
    final foreground = dark ? const Color(0xffe7eaf2) : colors.onSurface;
    final muted = dark ? const Color(0xff89909f) : colors.onSurfaceVariant;
    final line = dark ? const Color(0xff303540) : colors.outlineVariant;

    return ColoredBox(
      color: surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: card,
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                _buildHeader(
                  foreground: foreground,
                  muted: muted,
                  line: line,
                ),
                if (_expanded) ...[
                  Expanded(
                    child: _buildBody(
                      foreground: foreground,
                      muted: muted,
                      line: line,
                      input: input,
                    ),
                  ),
                  _buildComposer(
                    foreground: foreground,
                    muted: muted,
                    line: line,
                    input: input,
                  ),
                  _buildFooter(foreground: foreground, muted: muted),
                ],
              ],
            ),
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
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: line)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Row(
          children: [
            Icon(
              _expanded ? Broken.arrow_down_2 : Broken.arrow_right_2,
              size: 22,
              color: muted,
            ),
            const SizedBox(width: 10),
            Text(
              'Todos ($_progress/${_tasks.length})',
              style: TextStyle(
                color: foreground,
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Fermer',
              onPressed: widget.onClose,
              icon: Icon(Broken.close_circle, size: 23, color: muted),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: 'Options de la liste',
              onPressed: () {},
              icon: Icon(Broken.menu, size: 23, color: muted),
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
    required Color input,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      children: [
        for (var index = 0; index < _tasks.length; index++)
          _buildTaskRow(
            task: _tasks[index],
            index: index,
            foreground: foreground,
            muted: muted,
          ),
        const SizedBox(height: 12),
        Container(height: 1, color: line),
        const SizedBox(height: 12),
        _buildAttachmentRow(foreground: foreground, muted: muted, input: input),
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 27, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    height: 1.25,
                  ),
                ),
              ),
              if (task.status == _WorkflowTaskStatus.active)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Broken.more_circle, size: 18, color: muted),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentRow({
    required Color foreground,
    required Color muted,
    required Color input,
  }) {
    final file = widget.initialAttachment;
    return Row(
      children: [
        _roundIconButton(
          icon: Broken.add,
          color: muted,
          tooltip: 'Ajouter une pièce jointe',
          onTap: widget.onAddAttachment,
        ),
        const SizedBox(width: 8),
        if (file != null && file.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: input,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: muted.withValues(alpha: 0.24)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Broken.arrow_down, size: 18, color: const Color(0xff57b7e8)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    file,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: muted,
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const Spacer(),
        Icon(Broken.document_text, size: 17, color: muted),
      ],
    );
  }

  Widget _buildComposer({
    required Color foreground,
    required Color muted,
    required Color line,
    required Color input,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: input,
          border: Border.all(color: line.withValues(alpha: 0.85)),
          borderRadius: BorderRadius.circular(11),
        ),
        child: TextField(
          controller: _inputController,
          focusNode: _inputFocusNode,
          minLines: 2,
          maxLines: 4,
          onSubmitted: (_) => _submit(),
          textInputAction: TextInputAction.newline,
          style: TextStyle(color: foreground, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Describe what to build',
            hintStyle: TextStyle(color: muted, fontSize: 15),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter({required Color foreground, required Color muted}) {
    final accent = const Color(0xffaeb6c8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Row(
        children: [
          _roundIconButton(
            icon: Broken.add,
            color: muted,
            tooltip: 'Ajouter',
            onTap: widget.onAddAttachment,
          ),
          const SizedBox(width: 8),
          _footerPill(
            icon: Broken.cpu,
            label: 'Agent',
            color: foreground,
            onTap: () {},
          ),
          const SizedBox(width: 8),
          _footerPill(
            icon: Broken.arrow_down_2,
            label: _mode,
            color: foreground,
            onTap: _cycleMode,
          ),
          const Spacer(),
          _roundIconButton(
            icon: Broken.slider_horizontal,
            color: accent,
            tooltip: 'Options',
            onTap: () {},
          ),
          const SizedBox(width: 8),
          _roundIconButton(
            icon: Broken.stop_circle,
            color: const Color(0xff8791a5),
            tooltip: 'Arrêter',
            onTap: widget.onStop,
          ),
        ],
      ),
    );
  }

  Widget _footerPill({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(child: Icon(icon, size: 21, color: color)),
        ),
      ),
    );
  }
}