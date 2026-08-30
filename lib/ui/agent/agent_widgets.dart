import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/broken_icons.dart';
import 'package:markdown_widget/markdown_widget.dart';
import '../agent_runner.dart' show AgentPhase;
import 'agent_models.dart';
import 'beui/beui_theme.dart';

// ── LightWavePainter ───────────────────────────────────────────────────────

class LightWavePainter extends CustomPainter {
  final Animation<double> animation;
  final Color color;
  LightWavePainter({required this.animation, required this.color}) : super(repaint: animation);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(-1.0 + 2.0 * animation.value, 0),
        end: Alignment(-0.5 + 2.0 * animation.value, 0),
        colors: [color.withValues(alpha: 0.0), color.withValues(alpha: 0.3), color.withValues(alpha: 0.0)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }
  @override
  bool shouldRepaint(LightWavePainter old) => old.animation.value != animation.value;
}

/// The single active activity card — always at the bottom.
class ActiveActivityCard extends StatefulWidget {
  final AgentActivityEvent activity;
  final bool isDark;
  final Color fg;
  final Color muted;
  const ActiveActivityCard({super.key, required this.activity, required this.isDark, required this.fg, required this.muted});
  @override
  State<ActiveActivityCard> createState() => ActiveActivityCardState();
}

class ActiveActivityCardState extends State<ActiveActivityCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveCtrl;
  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }
  @override
  void dispose() { _waveCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    final isError = a.status == AgentActivityStatus.error;
    final accent = isError ? Colors.redAccent : widget.isDark ? const Color(0xff8b5cf6) : const Color(0xff6366f1);
    // Compact line-style: same height as history entries, with light wave
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
        child: Row(
          key: ValueKey(a.label),
          children: [
            if (isError)
              Icon(Icons.error_outline, size: 13, color: Colors.redAccent)
            else
              SizedBox(
                width: 13, height: 13,
                child: BeUIPulsingSquare(size: 13, color: accent),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRect(
                child: CustomPaint(
                  painter: LightWavePainter(animation: _waveCtrl, color: accent),
                  child: Text(
                    a.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.fg.withValues(alpha: 0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact history entry — expandable.
class ActivityHistoryEntry extends StatelessWidget {
  final AgentActivityEvent event;
  final bool isDark;
  final Color fg;
  final Color muted;
  final VoidCallback onToggle;
  const ActivityHistoryEntry({super.key, required this.event, required this.isDark, required this.fg, required this.muted, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final e = event;
    final isError = e.status == AgentActivityStatus.error;
    final checkColor = isError ? Colors.redAccent : const Color(0xff22c55e);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      InkWell(
        onTap: (e.toolName != null || e.outputText != null) ? onToggle : null,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            Icon(Icons.check_circle, size: 13, color: checkColor),
            const SizedBox(width: 8),
            Expanded(child: Text(e.label, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.8)), maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (e.toolName != null || e.outputText != null)
              Icon(e.isExpanded ? Icons.expand_less : Icons.expand_more, size: 14, color: muted),
          ]),
        ),
      ),
      if (e.isExpanded) _buildDetails(e),
    ]);
  }

  Widget _buildDetails(AgentActivityEvent e) {
    final lines = <Widget>[];
    if (e.toolName != null) lines.add(_detailRow('Tool', e.toolName!));
    if (e.toolArgs != null && e.toolArgs!.isNotEmpty) {
      for (final entry in e.toolArgs!.entries) {
        final v = entry.value?.toString() ?? '';
        if (v.isNotEmpty && v.length < 200) lines.add(_detailRow(entry.key, v.length > 100 ? '${v.substring(0, 100)}\u2026' : v));
      }
    }
    if (e.toolResult != null && e.toolResult!.isNotEmpty) {
      final r = e.toolResult!;
      lines.add(_detailRow('Output', r.length > 300 ? '${r.substring(0, 300)}\u2026' : r));
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(33, 0, 12, 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1a1a1a).withValues(alpha: 0.4) : const Color(0xfff5f5f5).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: RichText(text: TextSpan(children: [
        TextSpan(text: '$label: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.7))),
        TextSpan(text: value, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: fg.withValues(alpha: 0.6), height: 1.4)),
      ])),
    );
  }
}

/// Complete activity feed: history + active card.
class AgentActivityFeed extends StatelessWidget {
  final AgentActivityController controller;
  final bool isDark;
  final Color fg;
  final Color muted;
  const AgentActivityFeed({super.key, required this.controller, required this.isDark, required this.fg, required this.muted});

  @override
  Widget build(BuildContext context) {
    final history = controller.history;
    final active = controller.activeActivity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final event in history)
          ActivityHistoryEntry(event: event, isDark: isDark, fg: fg, muted: muted, onToggle: () => controller.toggleExpand(event.id)),
        if (active != null)
          ActiveActivityCard(activity: active, isDark: isDark, fg: fg, muted: muted),
      ],
    );
  }
}
class ReflectionBox extends StatefulWidget {
  final String content;
  final bool isActive;
  final bool isDark;
  final Color fg;
  final Color muted;

  const ReflectionBox({super.key, 
    required this.content,
    required this.isActive,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  State<ReflectionBox> createState() => ReflectionBoxState();
}

class ReflectionBoxState extends State<ReflectionBox> {
  bool _userToggled = false;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // Pendant la génération la box reste dépliée ; une fois la phase
    // terminée elle se replie automatiquement (sauf bascule manuelle).
    final showBody = _userToggled ? _expanded : widget.isActive;
    final content = widget.content.trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _expanded = !(_userToggled ? _expanded : widget.isActive);
                _userToggled = true;
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.psychology,
                      size: 14, color: widget.fg.withValues(alpha: 0.75)),
                  const SizedBox(width: 6),
                  Text(
                    widget.isActive ? 'Réflexion en cours\u2026' : 'Réflexion',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: widget.fg.withValues(alpha: 0.85),
                    ),
                  ),
                  const Spacer(),
                  if (widget.isActive)
                    BeUIPulsingSquare(size: 10, color: widget.muted)
                  else
                    Icon(
                      showBody ? Broken.arrow_up_2 : Broken.arrow_down_2,
                      size: 12,
                      color: widget.muted,
                    ),
                ],
              ),
            ),
          ),
          if (showBody && content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 4, 4),
              child: InlineMdText(
                markdown: wrapLongTokensForDisplay(content),
                baseStyle: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  fontStyle: FontStyle.italic,
                  color: widget.fg.withValues(alpha: 0.65),
                ),
                codeStyle: TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  fontStyle: FontStyle.normal,
                  color: widget.isDark ? Colors.amber[300] : Colors.blue[900],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
class AgentToolCallBlock extends StatefulWidget {
  final String toolName;
  final Map<String, dynamic> args;
  final String? result;
  final String status; // 'pending_approval' | 'running' | 'done' | 'error'
  final bool isDark;
  final Color fg;
  final Color muted;
  final VoidCallback? onApprove;
  final VoidCallback? onDeny;
  final VoidCallback? onAutopilot;
  final VoidCallback? onAllowSession;
  final VoidCallback? onWhitelist;
  /// Quand false, le resultat n'est pas rendu inline : une carte Output
  /// separee (ToolOutputBlock) s'en charge dans la timeline.
  final bool showResultInline;
  final VoidCallback? onOpenInEditor;

  const AgentToolCallBlock({super.key, 
    required this.toolName,
    required this.args,
    required this.result,
    required this.status,
    required this.isDark,
    required this.fg,
    required this.muted,
    this.onApprove,
    this.onOpenInEditor,
    this.onDeny,
    this.onAutopilot,
    this.onAllowSession,
    this.onWhitelist,
    this.showResultInline = true,
  });

  @override
  State<AgentToolCallBlock> createState() => AgentToolCallBlockState();
}

class AgentToolCallBlockState extends State<AgentToolCallBlock> {
  bool _expanded = false;

  // Icône par catégorie d'outil
  static IconData _iconFor(String name) {
    if (name.contains('read') || name.contains('Read')) return Broken.document_text;
    if (name.contains('write') || name.contains('Write') ||
        name.contains('edit') || name.contains('Edit')) {
      return Broken.edit;
    }
    if (name.contains('delete') || name.contains('Delete')) return Broken.trash;
    if (name.contains('shell') || name.contains('Shell') ||
        name.contains('command') || name.contains('Command')) {
      return Broken.command_square;
    }
    if (name.contains('git') || name.contains('Git')) return Broken.code_circle;
    if (name.contains('search') || name.contains('Search') ||
        name.contains('grep') || name.contains('Grep') ||
        name.contains('glob') || name.contains('Glob')) {
      return Broken.search_normal;
    }
    if (name.contains('list') || name.contains('List')) return Broken.folder;
    if (name.contains('web') || name.contains('Web') ||
        name.contains('link') || name.contains('Link')) {
      return Broken.global;
    }
    return Broken.code_1;
  }

  // Résumé compact des args (1 ligne max)
  static String _argsSummary(Map<String, dynamic> args) {
    if (args.isEmpty) return '';
    final first = args.values.first?.toString() ?? '';
    final preview = first.length > 40 ? '${first.substring(0, 40)}\u2026' : first;
    return preview;
  }

  static String _argsSummaryFull(Map<String, dynamic> args) {
    if (args.isEmpty) return '';
    final cmd = args['command']?.toString() ?? args['cmd']?.toString() ?? '';
    if (cmd.isNotEmpty) return cmd;
    return args.values.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).join('  ');
  }

  @override
  Widget build(BuildContext context) {
    final isPending = widget.status == 'pending_approval';
    final isRunning = widget.status == 'running';
    final isError   = widget.result?.startsWith('Error') ?? false;

    if (isPending) {
      final cmdStr = widget.args['command']?.toString() ??
          widget.args.values.join(' ') ??
          widget.toolName;

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: widget.fg.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined,
                    size: 16, color: widget.fg.withValues(alpha: 0.85)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Demande d\'autorisation d\'exécution',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: widget.fg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: widget.fg.withValues(alpha: 0.18)),
              ),
              child: SelectableText(
                cmdStr,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: widget.fg,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                InkWell(
                  onTap: widget.onDeny,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: widget.fg.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.close, size: 12, color: widget.fg),
                        const SizedBox(width: 4),
                        Text(
                          'Refuser',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: widget.fg,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: widget.onApprove,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: widget.fg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check,
                            size: 12,
                            color: widget.isDark ? Colors.black : Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          'Approuver',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: widget.isDark ? Colors.black : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 16, color: widget.fg),
                  tooltip: 'Options d\'autorisation',
                  onSelected: (val) {
                    if (val == 'autopilot') {
                      widget.onAutopilot?.call();
                    } else if (val == 'session') {
                      widget.onAllowSession?.call();
                    } else if (val == 'whitelist') {
                      widget.onWhitelist?.call();
                    } else if (val == 'deny') {
                      widget.onDeny?.call();
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'autopilot',
                      child: Row(
                        children: [
                          Icon(Broken.send_2, size: 14, color: widget.fg.withValues(alpha: 0.8)),
                          const SizedBox(width: 8),
                          const Text('Passer en mode Autopilote', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'session',
                      child: Row(
                        children: [
                          Icon(Broken.flash_1, size: 14, color: widget.fg.withValues(alpha: 0.8)),
                          const SizedBox(width: 8),
                          const Text('Autoriser toutes les commandes (session)', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'whitelist',
                      child: Row(
                        children: [
                          Icon(Broken.shield_tick, size: 14, color: widget.fg.withValues(alpha: 0.8)),
                          const SizedBox(width: 8),
                          const Text('Toujours autoriser cette commande', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'deny',
                      child: Row(
                        children: [
                          Icon(Broken.close_circle, size: 14, color: widget.fg.withValues(alpha: 0.8)),
                          const SizedBox(width: 8),
                          const Text('Refuser et annuler', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: (widget.showResultInline && widget.result != null)
          ? () => setState(() => _expanded = !_expanded)
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header row ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                children: [
                  // Status indicator
                  if (isRunning)
                    BeUIPulsingSquare(size: 12, color: widget.muted)
                  else
                    agentToolIconWidget(widget.toolName, 12,
                        isError
                            ? widget.fg.withValues(alpha: 0.85)
                            : widget.fg.withValues(alpha: 0.5)),
                  const SizedBox(width: 6),
                  // Tool name
                  Text(
                    widget.toolName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: widget.fg,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: Text(
                        _argsSummaryFull(widget.args),
                        softWrap: false,
                        maxLines: 1,
                        style: TextStyle(fontSize: 10, color: widget.muted),
                      ),
                    ),
                  ),
                  if (widget.onOpenInEditor != null)
                    InkWell(
                      onTap: widget.onOpenInEditor,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(Icons.open_in_new,
                            size: 13, color: widget.fg.withValues(alpha: 0.55)),
                      ),
                    ),
                  // Expand chevron (only when result available inline)
                  if (widget.result != null && widget.showResultInline)
                    Icon(
                      _expanded ? Broken.arrow_up_2 : Broken.arrow_down_2,
                      size: 12,
                      color: widget.muted,
                    ),
                ],
              ),
            ),
            // ── Expanded result ────────────────────────────────────────
            if (widget.showResultInline && _expanded && widget.result != null)
              Container(
                padding: const EdgeInsets.fromLTRB(26, 0, 8, 8),
                width: double.infinity,
                child: SelectableText(
                  widget.result!.length > 2000
                      ? '${widget.result!.substring(0, 2000)}\n\u2026 (tronqué)'
                      : widget.result!,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: widget.fg.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------
// ToolOutputBlock - carte Output associee a son Tool Call mais rendue comme
// un bloc FRERE dans la timeline (jamais a l'interieur d'une Reflexion).
// ------------------------------------------------------------------------------

class ToolOutputBlock extends StatefulWidget {
  final String output;
  final bool isDark;
  final Color fg;
  final Color muted;

  const ToolOutputBlock({super.key, 
    required this.output,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  State<ToolOutputBlock> createState() => ToolOutputBlockState();
}

class ToolOutputBlockState extends State<ToolOutputBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final output = widget.output.trim();
    final isError =
        output.startsWith('Error') || output.startsWith('Blocage');
    final preview =
        output.length > 300 ? '${output.substring(0, 300)}…' : output;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 14, top: 2, bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isError ? Colors.redAccent.withValues(alpha: 0.5) : widget.fg.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: InkWell(
        onTap:
            output.length > 300 ? () => setState(() => _expanded = !_expanded) : null,
        borderRadius: BorderRadius.circular(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Broken.document_text, size: 11, color: widget.muted),
                const SizedBox(width: 5),
                Text(
                  'Output',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: widget.muted,
                  ),
                ),
                if (isError) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.warning_amber_rounded,
                      size: 11, color: Colors.redAccent.withValues(alpha: 0.9)),
                ],
                const Spacer(),
                if (output.length > 300)
                  Icon(
                    _expanded ? Broken.arrow_up_2 : Broken.arrow_down_2,
                    size: 12,
                    color: widget.muted,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              _expanded ? wrapLongTokensForDisplay(output) : wrapLongTokensForDisplay(preview),
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                height: 1.4,
                color: widget.fg.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated spinning indicator for agent thinking / streaming states.
class AnimatedOrb extends StatefulWidget {
  final AgentPhase phase;
  final Color color;

  const AnimatedOrb({super.key, required this.phase, required this.color});

  @override
  State<AnimatedOrb> createState() => AnimatedOrbState();
}

class AnimatedOrbState extends State<AnimatedOrb> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();
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
      builder: (context, child) {
        return CustomPaint(
          size: const Size(14, 14),
          painter: _OrbPainter(
            phase: widget.phase,
            color: widget.color,
            progress: _ctrl.value,
          ),
        );
      },
    );
  }
}

class _OrbPainter extends CustomPainter {
  final AgentPhase phase;
  final Color color;
  final double progress;

  _OrbPainter({required this.phase, required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2 - 2;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    if (phase == AgentPhase.thinking) {
      for (int i = 0; i < 3; i++) {
        final angle = (progress * 2 * math.pi) + (i * 2 * math.pi / 3);
        final offset = Offset(
          center.dx + math.cos(angle) * (baseRadius),
          center.dy + math.sin(angle) * (baseRadius),
        );
        canvas.drawCircle(offset, 2.5, paint..color = color.withValues(alpha: 0.8));
      }
      canvas.drawCircle(center, 2, paint..color = color.withValues(alpha: 0.4));
    } else if (phase == AgentPhase.toolRunning) {
      final scale = 1.0 + 0.3 * math.sin(progress * 2 * math.pi);
      final glowPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.4 * scale)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(center, baseRadius * scale, glowPaint);
      canvas.drawCircle(center, baseRadius * 0.8, paint..color = color);
    } else if (phase == AgentPhase.streaming) {
      final path = Path();
      final points = 8;
      for (int i = 0; i < points; i++) {
        final angle = (i * 2 * math.pi / points);
        final radiusOffset = math.sin((progress * 4 * math.pi) + angle * 3) * 1.5;
        final r = baseRadius + radiusOffset;
        final p = Offset(center.dx + math.cos(angle) * r, center.dy + math.sin(angle) * r);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    } else if (phase == AgentPhase.error) {
      final shake = math.sin(progress * 10 * math.pi) * 2;
      canvas.drawCircle(Offset(center.dx + shake, center.dy), baseRadius, paint);
    } else if (phase == AgentPhase.toolDone) {
      for (int i = 0; i < 4; i++) {
        final angle = (i * math.pi / 2) + (progress * math.pi / 2);
        final r = baseRadius + (progress * 4);
        final offset = Offset(center.dx + math.cos(angle) * r, center.dy + math.sin(angle) * r);
        canvas.drawCircle(offset, 1.5 * (1 - progress), paint);
      }
      canvas.drawCircle(center, baseRadius, paint);
    } else {
      canvas.drawCircle(center, baseRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.phase != phase || oldDelegate.color != color;
}

class AgentPhaseChip extends StatefulWidget {
  final AgentPhase phase;
  final bool       isDark;
  final String     toolName;
  final Color      fg;
  final Color      muted;

  const AgentPhaseChip({super.key, 
    required this.phase,
    required this.isDark,
    this.toolName = '',
    required this.fg,
    required this.muted,
  });

  @override
  State<AgentPhaseChip> createState() => AgentPhaseChipState();
}

class AgentPhaseChipState extends State<AgentPhaseChip> {
  bool _isFrench = true;

  @override
  void initState() {
    super.initState();
    _detectLanguage();
  }

  Future<void> _detectLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLang = prefs.getString('app_language') ?? '';
      if (savedLang.isNotEmpty) {
        if (mounted) {
          setState(() {
            _isFrench = savedLang.toLowerCase().contains('fran');
          });
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      final locale = Localizations.maybeLocaleOf(context)?.languageCode ?? 'fr';
      setState(() {
        _isFrench = locale.startsWith('fr');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.phase == AgentPhase.idle || widget.phase == AgentPhase.done) {
      return const SizedBox.shrink();
    }

    final String label;
    final String variant;

    switch (widget.phase) {
      case AgentPhase.thinking:
        label = _isFrench ? 'Réflexion en cours\u2026' : 'Thinking\u2026';
        variant = 'Orbit';
        break;
      case AgentPhase.streaming:
        label = _isFrench ? 'Génération de la réponse\u2026' : 'Generating\u2026';
        variant = 'Dots';
        break;
      case AgentPhase.error:
        label = _isFrench ? 'Erreur' : 'Error';
        variant = 'Drive';
        break;
      case AgentPhase.toolRunning:
        variant = 'Drive';
        final tName = widget.toolName;
        if (tName.contains('runShellCommand') || tName.contains('run_command')) {
          label = _isFrench ? 'Exécution d\'une commande\u2026' : 'Running command\u2026';
        } else if (tName.contains('codeEditorWrite') || tName.contains('create_file') || tName.contains('edit_file') || tName.contains('multi_edit_file')) {
          label = _isFrench ? 'Écriture de code\u2026' : 'Coding\u2026';
        } else if (tName.contains('gitClone') || tName.contains('clone')) {
          label = _isFrench ? 'Clonage du dépôt\u2026' : 'Cloning repository\u2026';
        } else if (tName.contains('compileApplet') || tName.contains('compile_applet')) {
          label = _isFrench ? 'Compilation de l\'applet\u2026' : 'Compiling applet\u2026';
        } else {
          label = _isFrench ? 'Travail en cours\u2026' : 'Working\u2026';
        }
        break;
      default:
        label = _isFrench ? 'Traitement\u2026' : 'Working\u2026';
        variant = 'Drive';
    }

    final Color accent;
    switch (widget.phase) {
      case AgentPhase.error:
        accent = Colors.redAccent;
        break;
      case AgentPhase.toolRunning:
        accent = widget.isDark ? const Color(0xff8b5cf6) : const Color(0xff6366f1);
        break;
      default:
        accent = widget.isDark ? const Color(0xff8b5cf6) : const Color(0xff6366f1);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BeUIPulsingSquare(size: 11, color: accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Curseur clignotant animé pendant le streaming.
class BlinkingCursor extends StatefulWidget {
  final Color color;
  const BlinkingCursor({super.key, required this.color});

  @override
  State<BlinkingCursor> createState() => BlinkingCursorState();
}

class BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>    _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0, end: 1).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 2,
        height: 13,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MsgActionBtn — small icon+label action button for message bubbles
// ─────────────────────────────────────────────────────────────────────────────

class MsgActionBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  final Color    muted;

  const MsgActionBtn({super.key, 
    required this.icon,
    required this.label,
    required this.onTap,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: muted),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(fontSize: 11, color: muted)),
        ]),
      ),
    );
  }
}

class AgentMarkdownView extends StatelessWidget {
  final String markdown;
  final bool isDark;
  final Color fg;
  final bool isError;
  final bool isStreaming;

  const AgentMarkdownView({super.key, 
    required this.markdown,
    required this.isDark,
    required this.fg,
    required this.isError,
    required this.isStreaming,
  });

  @override
  Widget build(BuildContext context) {
    if (isError) {
      return Text(
        markdown,
        style: TextStyle(color: Colors.red[400], fontSize: 13),
      );
    }
    if (markdown.isEmpty && isStreaming) {
      return const SizedBox.shrink();
    }

    final displayMarkdown = isStreaming ? '$markdown ▋' : markdown;

    final baseConfig = isDark ? MarkdownConfig.darkConfig : MarkdownConfig.defaultConfig;
    final config = baseConfig.copy(
      configs: [
        PConfig(textStyle: TextStyle(color: fg, fontSize: 13, height: 1.45)),
        CodeConfig(style: TextStyle(color: isDark ? Colors.amber[300] : Colors.blue[900], fontSize: 12, fontFamily: 'monospace')),
        PreConfig(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xff181825) : const Color(0xfff8fafc),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? const Color(0xff313244) : const Color(0xffe2e8f0),
            ),
          ),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          textStyle: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: isDark ? const Color(0xffcdd6f4) : const Color(0xff0f172a),
          ),
          wrapper: (child, code, language) {
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xff181825) : const Color(0xfff8fafc),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? const Color(0xff313244) : const Color(0xffe2e8f0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xff11111b) : const Color(0xffe2e8f0),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          language.isNotEmpty ? language : 'code',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.grey[400] : Colors.grey[700],
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Code copié !', style: TextStyle(fontSize: 12)),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Row(
                              children: [
                                Icon(Broken.copy, size: 12, color: isDark ? Colors.grey[400] : Colors.grey[700]),
                                const SizedBox(width: 4),
                                Text(
                                  'Copier',
                                  style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[700]),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(10),
                    child: child,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );

    return MarkdownWidget(
      data: displayMarkdown,
      shrinkWrap: true,
      config: config,
    );
  }
}
class AgentToolCallsGroup extends StatefulWidget {
  final List<Map<String, dynamic>> toolCalls;
  final bool isStreaming;
  final String currentTool;
  final bool isDark;
  final Color fg;
  final Color muted;

  const AgentToolCallsGroup({super.key, 
    required this.toolCalls,
    required this.isStreaming,
    required this.currentTool,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  State<AgentToolCallsGroup> createState() => AgentToolCallsGroupState();
}

class AgentToolCallsGroupState extends State<AgentToolCallsGroup> {
  bool _expanded = false;

  static IconData _iconForTool(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('read') || lower.contains('list') || lower.contains('file')) return Broken.document_text;
    if (lower.contains('write') || lower.contains('edit') || lower.contains('create')) return Broken.edit;
    if (lower.contains('shell') || lower.contains('command') || lower.contains('terminal') || lower.contains('exec')) return Broken.command_square;
    if (lower.contains('web') || lower.contains('search') || lower.contains('link') || lower.contains('http')) return Broken.global;
    if (lower.contains('git') || lower.contains('commit') || lower.contains('push')) return Broken.code_circle;
    if (lower.contains('str_replace') || lower.contains('replace')) return Broken.edit;
    if (lower.contains('grep') || lower.contains('glob') || lower.contains('search')) return Broken.search_normal;
    return Broken.code_1;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xff1e1e24) : const Color(0xfff4f4f8);
    final border = isDark ? const Color(0xff333342) : const Color(0xffe0e0ea);

    final count = widget.toolCalls.length;
    final runningCount = widget.toolCalls.where((t) => t['status'] == 'running').length;
    final doneCount = widget.toolCalls.where((t) => t['status'] == 'done').length;
    final errorCount = widget.toolCalls.where((t) => (t['result']?.toString() ?? '').startsWith('Error')).length;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Compact Header with chevron ──
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  children: [
                    Icon(Broken.command_square, size: 14, color: widget.fg.withValues(alpha: 0.8)),
                    const SizedBox(width: 6),
                    Text(
                      _expanded ? 'Outils ex\u00e9cut\u00e9s' : '$count outil${count > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: widget.fg.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Compact inline pill chips for each tool
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: widget.toolCalls.map((call) {
                            final name = call['name'] as String? ?? '';
                            final icon = _iconForTool(name);
                            final status = call['status'] as String? ?? 'done';
                            final isRunning = status == 'running';
                            final isError = (call['result']?.toString() ?? '').startsWith('Error');
                            Color chipBg = isDark ? const Color(0xff2a2a35) : const Color(0xffe8e8f0);
                            if (isRunning) chipBg = widget.fg.withValues(alpha: 0.12);
                            if (isError) chipBg = const Color(0xff3a1a1a);

                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: chipBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isRunning)
                                      SizedBox(
                                        width: 8, height: 8,
                                        child: BeUIPulsingSquare(size: 8, color: widget.fg.withValues(alpha: 0.7)),
                                      )
                                    else
                                      Icon(icon, size: 10, color: widget.fg.withValues(alpha: 0.7)),
                                    const SizedBox(width: 3),
                                    Text(
                                      name.length > 12 ? '${name.substring(0, 12)}\u2026' : name,
                                      style: TextStyle(fontSize: 9, fontFamily: 'monospace', color: widget.fg.withValues(alpha: 0.8)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    if (widget.isStreaming) ...[
                      const SizedBox(width: 4),
                      BeUIPulsingSquare(size: 10, color: widget.fg),
                    ],
                    const SizedBox(width: 6),
                    Icon(
                      _expanded ? Broken.arrow_up_2 : Broken.arrow_down_2,
                      size: 12,
                      color: widget.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Expanded content: detailed tool call blocks ──
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 8),
                  ...widget.toolCalls.map((call) => AgentToolCallBlock(
                    toolName: call['name'] as String? ?? call['toolName'] as String? ?? '',
                    args: (call['args'] as Map?)?.cast<String, dynamic>() ?? {},
                    result: call['result'] as String?,
                    status: call['status'] as String? ?? 'done',
                    isDark: isDark,
                    fg: widget.fg,
                    muted: widget.muted,
                  )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Spinning square animation with glowing accent (Replit Agent square style)
class SpinningSquareIndicator extends StatefulWidget {
  final Color color;
  final double size;

  const SpinningSquareIndicator({super.key, 
    this.color = const Color(0xff9c27b0),
    this.size = 11,
  });

  @override
  State<SpinningSquareIndicator> createState() => SpinningSquareIndicatorState();
}

class SpinningSquareIndicatorState extends State<SpinningSquareIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _spin;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
    _spin = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _spin,
      builder: (_, __) => Transform.rotate(
        angle: _spin.value * 3.14159 * 2,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(2.5),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.5),
                blurRadius: 4,
                spreadRadius: 0.5,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
String wrapLongTokensForDisplay(String input, {int threshold = 48}) {
  if (input.isEmpty) return input;
  final out = StringBuffer();
  for (final token in input.split(' ')) {
    if (token.length > threshold) {
      for (var i = 0; i < token.length; i++) {
        out.write(token[i]);
        if (i > 0 && (i + 1) % threshold == 0 && i + 1 < token.length) out.write('\u200b');
      }
    } else {
      out.write(token);
    }
    out.write(' ');
  }
  return out.toString().trimRight();
}

String formatAgentDuration(int ms) {
  final s = ms ~/ 1000;
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  final r = s % 60;
  if (m < 60) return '${m}m ${r}s';
  return '${m ~/ 60}h ${m % 60}m';
}

Widget agentToolIconWidget(String name, double size, Color color) {
  final n = name.toLowerCase();
  if (n.contains('shell') || n.contains('command') || n.contains('bash') || n.contains('cmd')) {
    return Text('>_', style: TextStyle(fontSize: size + 1.5, height: 1.0, fontWeight: FontWeight.w800, fontFamily: 'monospace', color: color));
  }
  IconData icon;
  if (n.contains('grep') || n.contains('search') || n.contains('glob') || n.contains('find')) {
    icon = Broken.search_normal;
  } else if (n.contains('edit') || n.contains('write') || n.contains('save')) icon = Broken.edit;
  else if (n.contains('read') || n.contains('open') || n.contains('view')) icon = Broken.document_text;
  else if (n.contains('git')) icon = Broken.code_circle;
  else if (n.contains('web') || n.contains('fetch') || n.contains('http') || n.contains('download')) icon = Broken.global;
  else if (n.contains('list') || n.contains('dir')) icon = Broken.folder;
  else if (n.contains('delete') || n.contains('remove')) icon = Broken.trash;
  else icon = Broken.code_1;
  return Icon(icon, size: size, color: color);
}

class InlineMdText extends StatelessWidget {
  final String markdown;
  final TextStyle baseStyle;
  final TextStyle codeStyle;
  const InlineMdText({super.key, required this.markdown, required this.baseStyle, required this.codeStyle});

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'\*\*([^*]+)\*\*|\*([^*\n]+)\*|`([^`]+)`');
    var last = 0;
    for (final m in regex.allMatches(markdown)) {
      if (m.start > last) spans.add(TextSpan(text: markdown.substring(last, m.start)));
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: baseStyle.copyWith(fontWeight: FontWeight.w700)));
      } else if (m.group(2) != null) spans.add(TextSpan(text: m.group(2)));
      else if (m.group(3) != null) spans.add(TextSpan(text: m.group(3), style: codeStyle));
      last = m.end;
    }
    if (last < markdown.length) spans.add(TextSpan(text: markdown.substring(last)));
    return SelectableText.rich(TextSpan(children: spans, style: baseStyle));
  }
}

class AgentActionStrip extends StatefulWidget {
  final List<Map<String, dynamic>> events;
  final bool isDark;
  final Color fg;
  final Color muted;
  final WidgetBuilder buildExpanded;
  const AgentActionStrip({super.key, required this.events, required this.isDark, required this.fg, required this.muted, required this.buildExpanded});
  @override
  State<AgentActionStrip> createState() => AgentActionStripState();
}

class AgentActionStripState extends State<AgentActionStrip> {
  bool _expanded = false;
  static const int _maxChips = 6;

  @override
  Widget build(BuildContext context) {
    final events = widget.events;
    var hadError = false;
    for (final e in events) {
      final st = (e['status'] as String?) ?? '';
      final res = ((e['result'] as String?) ?? '').trim();
      if (st == 'error' || res.startsWith('Error') || res.startsWith('Blocage')) { hadError = true; break; }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(children: [
            for (var ci = 0; ci < events.length && ci < _maxChips; ci++)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(color: widget.fg.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(6)),
                  child: Center(
                    child: (events[ci]['type'] as String? ?? '') == 'thinking'
                        ? Icon(Icons.psychology, size: 13, color: widget.fg.withValues(alpha: 0.55))
                        : agentToolIconWidget(((events[ci]['name'] ?? events[ci]['toolName']) ?? '').toString(), 11, widget.fg.withValues(alpha: 0.55)),
                  ),
                ),
              ),
            if (events.length > _maxChips)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(color: widget.fg.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(6)),
                  child: Center(child: Text('\u00b7\u00b7\u00b7', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: widget.muted))),
                ),
              ),
            const SizedBox(width: 4),
            Text('${events.length} action${events.length > 1 ? 's' : ''}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: hadError ? Colors.redAccent.withValues(alpha: 0.9) : widget.muted)),
            const Spacer(),
            Icon(_expanded ? Broken.arrow_up_2 : Broken.arrow_down_2, size: 12, color: widget.muted),
          ]),
        ),
      ),
      if (_expanded) ...[
        widget.buildExpanded(context),
        InkWell(
          onTap: () => setState(() => _expanded = false),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(children: [Icon(Broken.arrow_up_2, size: 12, color: widget.muted), const SizedBox(width: 4), Text('Show less', style: TextStyle(fontSize: 10.5, color: widget.muted))]),
          ),
        ),
      ],
    ]);
  }
}

class AgentCheckpointCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool isDark;
  final Color fg;
  final Color muted;
  final VoidCallback onRestore;
  final VoidCallback onOpenGit;
  const AgentCheckpointCard({super.key, required this.data, required this.isDark, required this.fg, required this.muted, required this.onRestore, required this.onOpenGit});
  @override
  State<AgentCheckpointCard> createState() => AgentCheckpointCardState();
}

class AgentCheckpointCardState extends State<AgentCheckpointCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final durMs = (widget.data['durationMs'] as num?)?.toInt() ?? 0;
    final files = (widget.data['filesCount'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(children: [
              Icon(Icons.speed, size: 13, color: widget.muted),
              const SizedBox(width: 6),
              Text('Travaill\u00e9 pendant ${formatAgentDuration(durMs)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: widget.fg.withValues(alpha: 0.7))),
              if (files > 0) ...[const SizedBox(width: 8), Text('$files fichier${files > 1 ? 's' : ''}', style: TextStyle(fontSize: 10, color: widget.muted))],
              const Spacer(),
              Icon(_expanded ? Broken.arrow_up_2 : Broken.arrow_down_2, size: 12, color: widget.muted),
            ]),
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(left: 2, top: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: widget.fg.withValues(alpha: 0.1)), borderRadius: BorderRadius.circular(6)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Checkpoint local', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: widget.muted)),
              const SizedBox(height: 6),
              Text("L'agent a modifi\u00e9 $files fichier${files > 1 ? 's' : ''}. Un snapshot a \u00e9t\u00e9 cr\u00e9\u00e9 pour restaurer.", style: TextStyle(fontSize: 10.5, color: widget.fg.withValues(alpha: 0.6))),
              const SizedBox(height: 8),
              Row(children: [
                TextButton.icon(onPressed: widget.onRestore, icon: Icon(Icons.restore, size: 13, color: widget.fg), label: Text('Restaurer', style: TextStyle(fontSize: 11, color: widget.fg))),
                const SizedBox(width: 8),
                TextButton.icon(onPressed: widget.onOpenGit, icon: Icon(Broken.programming_arrows, size: 13, color: widget.fg), label: Text('Git panel', style: TextStyle(fontSize: 11, color: widget.fg))),
              ]),
            ]),
          ),
      ]),
    );
  }
}
