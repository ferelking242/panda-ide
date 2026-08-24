import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUITodoList — liste de tâches collapsible avec marques morphing.
///
/// Parse les plans Agent au format `- [ ] Tâche` / `- [x] Tâche`.
/// Header : compteur N/M + collapse toggle.
/// Chaque item : cercle → spinner → check animé avec strikethrough.
/// ═══════════════════════════════════════════════════════════════════════════

enum BeUITodoStatus { pending, running, done }

class BeUITodoItem {
  String title;
  BeUITodoStatus status;
  bool isExpanded;
  String? details;

  BeUITodoItem({
    required this.title,
    this.status = BeUITodoStatus.pending,
    this.isExpanded = false,
    this.details,
  });
}

class BeUITodoList extends StatefulWidget {
  final List<BeUITodoItem> items;
  final bool isDark;
  final Color fg;
  final Color muted;

  const BeUITodoList({
    super.key,
    required this.items,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  State<BeUITodoList> createState() => _BeUITodoListState();
}

class _BeUITodoListState extends State<BeUITodoList> {
  bool _collapsed = false;

  int get _doneCount =>
      widget.items.where((i) => i.status == BeUITodoStatus.done).length;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();

    final accent = BeUIColors.accentOf(widget.isDark);
    final doneCount = _doneCount;
    final total = items.length;
    final allDone = doneCount == total;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: BeUIColors.deepSurfaceOf(widget.isDark),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BeUIColors.borderOf(widget.isDark), width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _collapsed = !_collapsed),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    allDone ? Icons.check_circle : Icons.task_alt,
                    size: 14,
                    color: allDone ? BeUIColors.success : accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$doneCount/$total terminées',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.fg.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _collapsed ? 0.5 : 0,
                    duration: BeUIDurations.fast,
                    child: Icon(Icons.keyboard_arrow_down, size: 14, color: widget.muted),
                  ),
                ],
              ),
            ),
          ),

          // ── Items ─────────────────────────────────────────────
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildItemList(items, accent),
            crossFadeState:
                _collapsed ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            duration: BeUIDurations.medium,
            firstCurve: BeUICurves.inCurve,
            secondCurve: BeUICurves.outCurve,
          ),
        ],
      ),
    );
  }

  Widget _buildItemList(List<BeUITodoItem> items, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++)
            _TodoItemTile(
              item: items[i],
              index: i,
              isDark: widget.isDark,
              fg: widget.fg,
              muted: widget.muted,
              accent: accent,
            ),
        ],
      ),
    );
  }
}

class _TodoItemTile extends StatelessWidget {
  final BeUITodoItem item;
  final int index;
  final bool isDark;
  final Color fg;
  final Color muted;
  final Color accent;

  const _TodoItemTile({
    required this.item,
    required this.index,
    required this.isDark,
    required this.fg,
    required this.muted,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusMark(),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: BeUIDurations.medium,
              style: TextStyle(
                fontSize: 12,
                color: item.status == BeUITodoStatus.done
                    ? muted
                    : fg.withValues(alpha: 0.85),
                decoration: item.status == BeUITodoStatus.done
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                decorationColor: muted.withValues(alpha: 0.5),
              ),
              child: Text(item.title, maxLines: 3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusMark() {
    switch (item.status) {
      case BeUITodoStatus.done:
        return _AnimatedCheckIcon(size: 14, color: BeUIColors.success);
      case BeUITodoStatus.running:
        return BeUIRotatingSquare(size: 14, color: accent);
      case BeUITodoStatus.pending:
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: muted, width: 1.5),
          ),
        );
    }
  }
}

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
    _ctrl = AnimationController(vsync: this, duration: BeUIDurations.medium)..forward();
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
      builder: (context, _) => CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _CheckPainter(progress: _ctrl.value, color: widget.color),
      ),
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
    final cp = (progress / 0.6).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708, 6.2832 * cp, false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.12
        ..strokeCap = StrokeCap.round,
    );
    if (progress > 0.6) {
      final tp = ((progress - 0.6) / 0.4).clamp(0.0, 1.0);
      final path = Path()
        ..moveTo(size.width * 0.28, size.height * 0.52)
        ..lineTo(size.width * 0.44, size.height * 0.68)
        ..lineTo(size.width * 0.72, size.height * 0.34);
      canvas.drawPath(
        path.computeMetrics().first.extractPath(0, path.computeMetrics().first.length * tp),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.14
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CheckPainter o) => o.progress != progress;
}
