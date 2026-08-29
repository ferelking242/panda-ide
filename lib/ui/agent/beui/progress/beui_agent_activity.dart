import 'dart:async';
import 'package:flutter/material.dart';
import '../beui_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════════════════════

enum BeUIStepType { status, tool, reasoning }
enum BeUIStepStatus { pending, running, success, error }

class BeUIAgentStep {
  final String id;
  final DateTime timestamp;
  BeUIStepType type;
  BeUIStepStatus status;
  String title;
  String? toolName;
  Map<String, dynamic>? toolArgs;
  String? toolResult;
  String? outputText;
  Duration? duration;
  bool isExpanded;

  BeUIAgentStep({
    required this.id,
    DateTime? timestamp,
    this.type = BeUIStepType.status,
    this.status = BeUIStepStatus.running,
    this.title = '',
    this.toolName,
    this.toolArgs,
    this.toolResult,
    this.outputText,
    this.duration,
    this.isExpanded = false,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isError => status == BeUIStepStatus.error;
  bool get isRunning => status == BeUIStepStatus.running;
  bool get isDone => status == BeUIStepStatus.success;

  IconData get icon {
    if (type == BeUIStepType.reasoning) return Icons.psychology;
    return BeUIHumanLabels.iconForTool(toolName ?? '');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Human-readable labels (ported from home.dart toolHumanLabel)
// ═══════════════════════════════════════════════════════════════════════════

class BeUIHumanLabels {
  BeUIHumanLabels._();

  static String toolLabel(String toolName, Map<String, dynamic> args) {
    final n = toolName.toLowerCase();
    if (n.contains('shell') || n.contains('command')) {
      final cmd = (args['command'] ?? '').toString();
      if (cmd.contains('git clone')) return 'Cloning…';
      if (cmd.contains('git push')) return 'Push vers GitHub…';
      if (cmd.contains('git commit')) return 'Création du commit…';
      if (cmd.contains('npm install') || cmd.contains('pip install')) {
        return 'Installation des dépendances…';
      }
      if (cmd.contains('flutter build')) return 'Build en cours…';
      if (cmd.contains('flutter test')) return 'Tests en cours…';
      final preview =
          cmd.length > 30 ? '${cmd.substring(0, 30)}…' : cmd;
      return preview.isEmpty ? 'Exécution…' : 'Exécution : $preview';
    }
    if (n.contains('read')) return 'Lecture du fichier…';
    if (n.contains('write') || n.contains('edit') || n.contains('multi')) {
      return 'Édition du fichier…';
    }
    if (n.contains('search') || n.contains('grep') || n.contains('glob')) {
      return 'Recherche…';
    }
    if (n.contains('list') || n.contains('dir')) return 'Exploration…';
    if (n.contains('web') || n.contains('fetch') || n.contains('http')) {
      return 'Recherche internet…';
    }
    if (n.contains('git')) return 'Commande Git…';
    if (n.contains('delete')) return 'Suppression…';
    return 'Action en cours…';
  }

  static IconData iconForTool(String name) {
    final n = name.toLowerCase();
    if (n.contains('shell') || n.contains('command')) {
      return Icons.terminal;
    }
    if (n.contains('read')) return Icons.article_outlined;
    if (n.contains('write') || n.contains('edit')) return Icons.edit;
    if (n.contains('search') || n.contains('grep')) {
      return Icons.search;
    }
    if (n.contains('list')) return Icons.folder;
    if (n.contains('web') || n.contains('fetch')) return Icons.language;
    if (n.contains('git')) return Icons.code;
    if (n.contains('delete')) return Icons.delete_outline;
    return Icons.settings;
  }

  static String phaseLabel(String phase, String toolName) {
    switch (phase) {
      case 'thinking':
        return 'Réflexion…';
      case 'streaming':
        return 'Génération…';
      case 'error':
        return 'Erreur';
      default:
        if (toolName.isNotEmpty) return toolLabel(toolName, {});
        return 'Travail en cours…';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Controller — API compatible avec l'ancien AgentActivityController
// ═══════════════════════════════════════════════════════════════════════════

class BeUIAgentActivityController {
  final List<BeUIAgentStep> history = [];
  BeUIAgentStep? activeActivity;
  bool isToolRunning = false;
  String? activeToolId;
  VoidCallback? _onUpdate;

  void setOnUpdate(VoidCallback cb) => _onUpdate = cb;
  void _notify() => _onUpdate?.call();
  String _nextId() => 'step_${DateTime.now().microsecondsSinceEpoch}';

  void startRun() {
    reset();
    activeActivity = BeUIAgentStep(
      id: _nextId(),
      title: 'Génération…',
      type: BeUIStepType.status,
      status: BeUIStepStatus.running,
    );
    _notify();
  }

  void updateNarrative(String label) {
    if (isToolRunning) return;
    // If current active is reasoning → archive it first
    if (activeActivity?.type == BeUIStepType.reasoning) {
      _archiveActive();
    }
    activeActivity ??= BeUIAgentStep(
      id: _nextId(),
      type: BeUIStepType.status,
      status: BeUIStepStatus.running,
    );
    activeActivity!.title = label;
    _notify();
  }

  void startTool({
    required String toolId,
    required String toolName,
    required Map<String, dynamic> args,
  }) {
    _archiveActive();
    final label = BeUIHumanLabels.toolLabel(toolName, args);
    activeActivity = BeUIAgentStep(
      id: toolId,
      type: BeUIStepType.tool,
      status: BeUIStepStatus.running,
      title: label,
      toolName: toolName,
      toolArgs: args,
    );
    isToolRunning = true;
    activeToolId = toolId;
    _notify();
  }

  void completeTool({required String toolId, String? result}) {
    if (activeToolId != toolId) return;
    final a = activeActivity;
    if (a == null) return;
    a.status = BeUIStepStatus.success;
    a.toolResult = result;
    a.duration = DateTime.now().difference(a.timestamp);
    a.isExpanded = false;
    history.add(a);
    activeActivity = null;
    isToolRunning = false;
    activeToolId = null;
    // New idle card
    activeActivity = BeUIAgentStep(
      id: _nextId(),
      type: BeUIStepType.status,
      status: BeUIStepStatus.running,
      title: 'Génération…',
    );
    _notify();
  }

  void failTool({required String toolId, String? error}) {
    if (activeToolId != toolId) return;
    final a = activeActivity;
    if (a == null) return;
    a.status = BeUIStepStatus.error;
    a.toolResult = error;
    a.duration = DateTime.now().difference(a.timestamp);
    a.isExpanded = false;
    history.add(a);
    activeActivity = null;
    isToolRunning = false;
    activeToolId = null;
    _notify();
  }

  void pushReasoning(String text) {
    if (text.trim().isEmpty) return;
    if (activeActivity?.type == BeUIStepType.reasoning) {
      activeActivity!.outputText =
          (activeActivity!.outputText ?? '') + text;
      _notify();
      return;
    }
    _archiveActive();
    activeActivity = BeUIAgentStep(
      id: _nextId(),
      type: BeUIStepType.reasoning,
      status: BeUIStepStatus.running,
      title: 'Réflexion',
      outputText: text,
    );
    _notify();
  }

  void finishRun({String? error}) {
    if (activeActivity != null) {
      final a = activeActivity!;
      a.status = error != null ? BeUIStepStatus.error : BeUIStepStatus.success;
      if (error != null) a.title = error;
      a.duration = DateTime.now().difference(a.timestamp);
      a.isExpanded = false;
      history.add(a);
      activeActivity = null;
    }
    isToolRunning = false;
    activeToolId = null;
    _notify();
  }

  void toggleExpand(String id) {
    for (final e in history) {
      if (e.id == id) {
        e.isExpanded = !e.isExpanded;
        _notify();
        return;
      }
    }
  }

  void reset() {
    history.clear();
    activeActivity = null;
    isToolRunning = false;
    activeToolId = null;
    _notify();
  }

  void _archiveActive() {
    if (activeActivity != null) {
      final a = activeActivity!;
      a.status = BeUIStepStatus.success;
      a.duration = DateTime.now().difference(a.timestamp);
      a.isExpanded = false;
      history.add(a);
      activeActivity = null;
    }
    isToolRunning = false;
    activeToolId = null;
  }

  int get totalCompleted => history.where((s) => !s.isError).length;
  int get totalErrors => history.where((s) => s.isError).length;
  int get totalCount => history.length + (activeActivity != null ? 1 : 0);
}

// ═══════════════════════════════════════════════════════════════════════════
// BeUIAgentActivity — le widget composite (ticker + drawer)
// ═══════════════════════════════════════════════════════════════════════════

class BeUIAgentActivity extends StatefulWidget {
  final BeUIAgentActivityController controller;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final bool isDark;
  final Color fg;
  final Color muted;

  const BeUIAgentActivity({
    super.key,
    required this.controller,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  State<BeUIAgentActivity> createState() => _BeUIAgentActivityState();
}

class _BeUIAgentActivityState extends State<BeUIAgentActivity>
    with SingleTickerProviderStateMixin {
  late final VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _listener = () {
      if (mounted) setState(() {});
    };
    widget.controller.setOnUpdate(_listener);
  }

  @override
  void didUpdateWidget(covariant BeUIAgentActivity old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.setOnUpdate(() {});
      widget.controller.setOnUpdate(_listener);
    }
  }

  @override
  void dispose() {
    widget.controller.setOnUpdate(() {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final hasHistory = ctrl.history.isNotEmpty;
    final hasActive = ctrl.activeActivity != null;
    if (!hasHistory && !hasActive) return const SizedBox.shrink();

    return AnimatedSize(
      duration: BeUIDurations.medium,
      curve: BeUICurves.morph,
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Drawer (unrolled) ─────────────────────────────────────
          if (widget.isExpanded && hasHistory)
            _BeUIActivityDrawer(
              controller: ctrl,
              isDark: widget.isDark,
              fg: widget.fg,
              muted: widget.muted,
            ),

          // ── Ticker (always visible when active or history exists) ─
          _BeUIActivityTicker(
            controller: ctrl,
            isExpanded: widget.isExpanded,
            onToggle: widget.onToggleExpanded,
            isDark: widget.isDark,
            fg: widget.fg,
            muted: widget.muted,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _BeUIActivityTicker — le carré animé + texte, ancré en bas
// ═══════════════════════════════════════════════════════════════════════════

class _BeUIActivityTicker extends StatefulWidget {
  final BeUIAgentActivityController controller;
  final bool isExpanded;
  final VoidCallback onToggle;
  final bool isDark;
  final Color fg;
  final Color muted;

  const _BeUIActivityTicker({
    required this.controller,
    required this.isExpanded,
    required this.onToggle,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  State<_BeUIActivityTicker> createState() => _BeUIActivityTickerState();
}

class _BeUIActivityTickerState extends State<_BeUIActivityTicker> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.controller.activeActivity;
    final count = widget.controller.history.length;
    final accent = BeUIColors.accentOf(widget.isDark);

    // Completed state: show compact summary
    if (active == null && count > 0) {
      return _buildCompletedSummary(count, accent);
    }
    if (active == null) return const SizedBox.shrink();

    final elapsed = DateTime.now().difference(active.timestamp);
    final label = active.type == BeUIStepType.reasoning
        ? 'Réflexion…'
        : active.title;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: BeUIColors.deepSurfaceOf(widget.isDark),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: accent.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              BeUIPulsingSquare(size: 12, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.fg.withValues(alpha: 0.85),
                  ),
                ),
              ),
              if (elapsed.inSeconds > 0)
                Text(
                  '${elapsed.inSeconds}s',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: widget.muted,
                  ),
                ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: widget.isExpanded ? 0.5 : 0,
                duration: BeUIDurations.fast,
                child: Icon(
                  Icons.keyboard_arrow_up,
                  size: 14,
                  color: widget.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletedSummary(int count, Color accent) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: BeUIColors.deepSurfaceOf(widget.isDark),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 13, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$count action${count > 1 ? 's' : ''} exécutée${count > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.fg.withValues(alpha: 0.7),
                  ),
                ),
              ),
              AnimatedRotation(
                turns: widget.isExpanded ? 0.5 : 0,
                duration: BeUIDurations.fast,
                child: Icon(
                  Icons.keyboard_arrow_up,
                  size: 14,
                  color: widget.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _BeUIActivityDrawer — historique déroulable avec cartes accordéon
// ═══════════════════════════════════════════════════════════════════════════

class _BeUIActivityDrawer extends StatelessWidget {
  final BeUIAgentActivityController controller;
  final bool isDark;
  final Color fg;
  final Color muted;

  const _BeUIActivityDrawer({
    required this.controller,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final steps = controller.history;
    final total = steps.length;
    final errors = steps.where((s) => s.isError).length;

    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: BeUIColors.deepSurfaceOf(isDark),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: BeUIColors.borderOf(isDark),
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.linear_scale, size: 13, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$total action${total > 1 ? 's' : ''} exécutée${total > 1 ? 's' : ''}'
                    '${errors > 0 ? ' · $errors erreur${errors > 1 ? 's' : ''}' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, size: 14, color: muted),
              ],
            ),
          ),

          Divider(height: 1, thickness: 0.5, color: BeUIColors.borderOf(isDark)),

          // ── Step list ───────────────────────────────────────────
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: steps.length,
              itemBuilder: (_, i) => BeUIPopIn(
                child: _BeUIStepCard(
                  step: steps[i],
                  isDark: isDark,
                  fg: fg,
                  muted: muted,
                  onToggle: () => controller.toggleExpand(steps[i].id),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _BeUIStepCard — carte d'action accordéon (tap anywhere to expand)
// ═══════════════════════════════════════════════════════════════════════════

class _BeUIStepCard extends StatelessWidget {
  final BeUIAgentStep step;
  final bool isDark;
  final Color fg;
  final Color muted;
  final VoidCallback onToggle;

  const _BeUIStepCard({
    required this.step,
    required this.isDark,
    required this.fg,
    required this.muted,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: (step.toolName != null || step.outputText != null) ? onToggle : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Main row ─────────────────────────────────────────
            Row(
              children: [
                _statusIcon(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: step.isError
                          ? Colors.redAccent
                          : fg.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                if (step.duration != null)
                  Text(
                    _formatDuration(step.duration!),
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: muted,
                    ),
                  ),
                if (step.toolName != null || step.outputText != null) ...[
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: step.isExpanded ? 0.5 : 0,
                    duration: BeUIDurations.fast,
                    child: Icon(Icons.expand_more, size: 14, color: muted),
                  ),
                ],
              ],
            ),

            // ── Expanded details ─────────────────────────────────
            if (step.isExpanded) ...[
              const SizedBox(height: 6),
              _buildDetails(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusIcon() {
    if (step.isError) {
      return Icon(Icons.error_outline, size: 13, color: Colors.redAccent);
    }
    if (step.isDone) {
      return _AnimatedCheckIcon(
        size: 13,
        color: step.isError ? Colors.redAccent : Colors.green,
      );
    }
    return BeUIRotatingSquare(size: 12, color: muted);
  }

  Widget _buildDetails() {
    final lines = <Widget>[];
    if (step.toolName != null) {
      lines.add(_detailRow('Tool', step.toolName!));
    }
    if (step.toolArgs != null && step.toolArgs!.isNotEmpty) {
      for (final e in step.toolArgs!.entries) {
        final v = e.value?.toString() ?? '';
        if (v.isNotEmpty && v.length < 200) {
          lines.add(_detailRow(e.key, v.length > 100 ? '${v.substring(0, 100)}…' : v));
        }
      }
    }
    if (step.toolResult != null && step.toolResult!.isNotEmpty) {
      final r = step.toolResult!;
      lines.add(_detailRow('Output', r.length > 300 ? '${r.substring(0, 300)}…' : r));
    }
    if (step.outputText != null && step.outputText!.isNotEmpty) {
      final t = step.outputText!;
      lines.add(_detailRow('Thinking', t.length > 300 ? '${t.substring(0, 300)}…' : t));
    }
    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: BeUIColors.deepSurfaceOf(isDark),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg.withValues(alpha: 0.7),
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: fg.withValues(alpha: 0.6),
              height: 1.4,
            ),
          ),
        ]),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    return '${d.inMinutes}m${d.inSeconds % 60}s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _AnimatedCheckIcon — cercle + check animé par PathMetric
// ═══════════════════════════════════════════════════════════════════════════

class _AnimatedCheckIcon extends StatefulWidget {
  final double size;
  final Color color;

  const _AnimatedCheckIcon({required this.size, required this.color});

  @override
  State<_AnimatedCheckIcon> createState() => _AnimatedCheckIconState();
}

class _AnimatedCheckIconState extends State<_AnimatedCheckIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: BeUIDurations.medium,
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _ctrl, curve: BeUICurves.outCurve);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _CheckPainter(
            progress: curved.value,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;

  _CheckPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Circle (draws first 60% of animation)
    final circleProgress = (progress / 0.6).clamp(0.0, 1.0);
    final circlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2,
      3.14159 * 2 * circleProgress,
      false,
      circlePaint,
    );

    // Check (draws from 60% to 100%)
    if (progress > 0.6) {
      final checkProgress = ((progress - 0.6) / 0.4).clamp(0.0, 1.0);
      final checkPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.14
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path()
        ..moveTo(size.width * 0.28, size.height * 0.52)
        ..lineTo(size.width * 0.44, size.height * 0.68)
        ..lineTo(size.width * 0.72, size.height * 0.34);

      final metrics = path.computeMetrics().first;
      final extracted = metrics.extractPath(
        0,
        metrics.length * checkProgress,
      );
      canvas.drawPath(extracted, checkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) => old.progress != progress;
}
