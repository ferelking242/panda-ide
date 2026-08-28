import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/broken_icons.dart';

// ── DESIGN SYSTEM & CONSTANTS ────────────────────────────────────────────────
class BeautifulUITheme {
  static const Color darkBg = Color(0xff0b0c10);
  static const Color cardBgDark = Color(0xff16171d);
  static const Color accentColor = Color(0xff5090c8);
  static const Color neonGreen = Color(0xff10b981);
  static const Color neonPurple = Color(0xff8b5cf6);
  static const Color neonPink = Color(0xffec4899);
  static const Color warningRed = Color(0xffef4444);

  static BoxDecoration glass({
    required bool isDark,
    Color? activeColor,
    double radius = 12.0,
  }) {
    final borderCol = activeColor ?? (isDark ? const Color(0xff2d2d2d) : const Color(0xffdddddd));
    return BoxDecoration(
      color: isDark ? const Color(0x1a000000) : const Color(0x0fffffff),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderCol.withOpacity(isDark ? 0.15 : 0.4),
        width: 0.8,
      ),
    );
  }

  static List<BoxShadow> softShadow() {
    return [
      BoxShadow(
        color: const Color(0xff000000).withOpacity(0.12),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ];
  }
}

// ── 1. LOADING STATE (Shimmer Skeleton) ──────────────────────────────────────
class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const ShimmerLoading({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8.0,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xff1e1e1e) : const Color(0xffe0e0e0);
    final highlightColor = isDark ? const Color(0xff2d2d2d) : const Color(0xfff5f5f5);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                _controller.value - 0.3,
                _controller.value,
                _controller.value + 0.3,
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── 2. THINKING (Animated Gemini-style Thinking Panel) ──────────────────────
class ThinkingWidget extends StatefulWidget {
  final List<String> thoughts;
  final bool isExpanded;
  final Duration elapsedTime;
  final VoidCallback? onToggle;

  const ThinkingWidget({
    super.key,
    required this.thoughts,
    required this.isExpanded,
    required this.elapsedTime,
    this.onToggle,
  });

  @override
  State<ThinkingWidget> createState() => _ThinkingWidgetState();
}

class _ThinkingWidgetState extends State<ThinkingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotateCtrl;

  @override
  void initState() {
    super.initState();
    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _rotateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderC = isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd);
    final textC = isDark ? Colors.grey[400]! : Colors.grey[700]!;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1a1b1f) : const Color(0xfff5f5f7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderC, width: 0.5),
        boxShadow: BeautifulUITheme.softShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  RotationTransition(
                    turns: _rotateCtrl,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          colors: [
                            Color(0xff4285f4),
                            Color(0xffea4335),
                            Color(0xfffbbc04),
                            Color(0xff34a853),
                            Color(0xff4285f4),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Panda réfléchit...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.elapsedTime.inSeconds}s',
                    style: TextStyle(fontSize: 11, color: textC, fontFamily: 'monospace'),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    widget.isExpanded ? Broken.arrow_up_1 : Broken.arrow_down_1,
                    size: 14,
                    color: textC,
                  ),
                ],
              ),
            ),
          ),
          if (widget.isExpanded && widget.thoughts.isNotEmpty) ...[
            const Divider(height: 1, thickness: 0.5),
            Container(
              padding: const EdgeInsets.all(12),
              color: isDark ? const Color(0xff121316) : const Color(0xfffafafa),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.thoughts
                    .map((t) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '> ',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: BeautifulUITheme.accentColor,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  t,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: textC,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 3. STREAMING TEXT (Fading Word Reveal Effect) ───────────────────────────
class StreamingTextView extends StatefulWidget {
  final String fullText;
  final TextStyle? style;
  final Duration revealDuration;

  const StreamingTextView({
    super.key,
    required this.fullText,
    this.style,
    this.revealDuration = const Duration(milliseconds: 300),
  });

  @override
  State<StreamingTextView> createState() => _StreamingTextViewState();
}

class _StreamingTextViewState extends State<StreamingTextView> {
  List<String> _words = [];
  int _visibleWords = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _splitText();
    _startReveal();
  }

  @override
  void didUpdateWidget(StreamingTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fullText != oldWidget.fullText) {
      final oldText = oldWidget.fullText;
      final newText = widget.fullText;
      if (newText.startsWith(oldText) && oldText.isNotEmpty) {
        final extraText = newText.substring(oldText.length);
        final extraWords = extraText.split(RegExp(r'(?<=\s)|(?=\s)'));
        setState(() {
          _words.addAll(extraWords);
        });
        _resumeReveal();
      } else {
        _splitText();
        _startReveal();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _splitText() {
    _words = widget.fullText.split(RegExp(r'(?<=\s)|(?=\s)'));
  }

  void _startReveal() {
    _timer?.cancel();
    _visibleWords = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 25), (timer) {
      if (_visibleWords < _words.length) {
        setState(() {
          _visibleWords++;
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  void _resumeReveal() {
    if (_timer == null || !_timer!.isActive) {
      _timer = Timer.periodic(const Duration(milliseconds: 25), (timer) {
        if (_visibleWords < _words.length) {
          setState(() {
            _visibleWords++;
          });
        } else {
          _timer?.cancel();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textToShow = _words.take(_visibleWords).join('');
    return Text(
      textToShow,
      style: widget.style,
    );
  }
}

// ── 3B. PIXEL GRID LOADER COMPONENTS ─────────────────────────────────────────
class PixelGridCell extends StatefulWidget {
  final int? delay;
  final int durationMs;
  final bool round;
  final Color color;

  const PixelGridCell({
    super.key,
    required this.delay,
    required this.durationMs,
    required this.round,
    required this.color,
  });

  @override
  State<PixelGridCell> createState() => _PixelGridCellState();
}

class _PixelGridCellState extends State<PixelGridCell> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMs),
    );

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.15, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.15).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
    ]).animate(_controller);

    if (widget.delay == null) {
      // Static dim state
    } else {
      _delayTimer = Timer(Duration(milliseconds: widget.delay!), () {
        if (mounted) {
          _controller.repeat();
        }
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.delay == null) {
      return Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.07),
          borderRadius: widget.round ? BorderRadius.circular(2) : BorderRadius.circular(1),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(_opacityAnimation.value),
            borderRadius: widget.round ? BorderRadius.circular(2) : BorderRadius.circular(1),
          ),
        );
      },
    );
  }
}

class ElapsedTimerWidget extends StatefulWidget {
  const ElapsedTimerWidget({super.key});

  @override
  State<ElapsedTimerWidget> createState() => _ElapsedTimerWidgetState();
}

class _ElapsedTimerWidgetState extends State<ElapsedTimerWidget> {
  int _ds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          _ds++;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double total = _ds / 10.0;
    final String text;
    if (total < 60) {
      text = '${total.toStringAsFixed(1)}s';
    } else {
      final minutes = (total / 60).floor();
      final seconds = (total % 60).toStringAsFixed(1);
      text = '${minutes}m ${seconds}s';
    }

    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: Colors.grey,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}

class ShimmerText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const ShimmerText({super.key, required this.text, this.style});

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final highlightColor = isDark ? Colors.white : Colors.black;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                _controller.value - 0.3,
                _controller.value,
                _controller.value + 0.3,
              ],
            ).createShader(bounds);
          },
          child: Text(
            widget.text,
            style: (widget.style ?? const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)).copyWith(
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}

class LoadingStateWidget extends StatelessWidget {
  final String label;
  final String variant; // 'Drive', 'Dots', 'Orbit'
  final Color color;

  const LoadingStateWidget({
    super.key,
    required this.label,
    this.variant = 'Drive',
    this.color = const Color(0xff5090c8),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _SpinningSquare(color: color),
        const SizedBox(width: 8),
        ShimmerText(
          text: label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

/// Animated spinning square indicator (Replit Agent style).
class _SpinningSquare extends StatefulWidget {
  final Color color;
  const _SpinningSquare({required this.color});

  @override
  State<_SpinningSquare> createState() => _SpinningSquareState();
}

class _SpinningSquareState extends State<_SpinningSquare>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _anim = Tween<double>(begin: 0, end: 1).animate(
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
      animation: _anim,
      builder: (_, __) => Transform.rotate(
        angle: _anim.value * math.pi * 2,
        child: Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(2.5),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.4),
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

// ── 4. APPROVAL CARD (Micro-Interactive Approvals) ───────────────────────────
class ApprovalCard extends StatelessWidget {
  final String actionTitle;
  final String actionDetails;
  final VoidCallback onApproved;
  final VoidCallback onRejected;

  const ApprovalCard({
    super.key,
    required this.actionTitle,
    required this.actionDetails,
    required this.onApproved,
    required this.onRejected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textC = isDark ? Colors.grey[300]! : Colors.grey[700]!;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1f1717) : const Color(0xfffef2f2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: BeautifulUITheme.warningRed.withOpacity(0.3),
          width: 0.8,
        ),
        boxShadow: BeautifulUITheme.softShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Broken.info_circle, color: BeautifulUITheme.warningRed, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  actionTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            actionDetails,
            style: TextStyle(fontSize: 11, color: textC, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onRejected,
                child: Text(
                  'Refuser',
                  style: TextStyle(color: BeautifulUITheme.warningRed, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: onApproved,
                style: ElevatedButton.styleFrom(
                  backgroundColor: BeautifulUITheme.neonGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'Autoriser',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 5. TOOL CHIPS (Status Pills) ─────────────────────────────────────────────
enum ToolStatus { active, success, failed }

class ToolChip extends StatelessWidget {
  final String toolName;
  final String argumentSummary;
  final ToolStatus status;

  const ToolChip({
    super.key,
    required this.toolName,
    required this.argumentSummary,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = status == ToolStatus.active
        ? BeautifulUITheme.accentColor
        : status == ToolStatus.success
            ? BeautifulUITheme.neonGreen
            : BeautifulUITheme.warningRed;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == ToolStatus.active)
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: BeautifulUITheme.accentColor),
            )
          else
            Icon(
              status == ToolStatus.success ? Broken.tick_circle : Broken.close_square,
              size: 12,
              color: color,
            ),
          const SizedBox(width: 6),
          Text(
            toolName,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
          if (argumentSummary.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              '($argumentSummary)',
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.grey[500]! : Colors.grey[600]!,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 6. TASK ROWS (Timeline Alignments) ───────────────────────────────────────
class AgentTask {
  final String label;
  final ToolStatus status;
  AgentTask({required this.label, required this.status});
}

class TaskRowsWidget extends StatelessWidget {
  final List<AgentTask> tasks;

  const TaskRowsWidget({super.key, required this.tasks});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineCol = isDark ? const Color(0xff2d2d2d) : const Color(0xffe0e0e0);

    return Column(
      children: List.generate(tasks.length, (index) {
        final t = tasks[index];
        return IntrinsicHeight(
          child: Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.status == ToolStatus.success
                          ? BeautifulUITheme.neonGreen
                          : t.status == ToolStatus.failed
                              ? BeautifulUITheme.warningRed
                              : BeautifulUITheme.accentColor,
                    ),
                    child: Center(
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      ),
                    ),
                  ),
                  if (index < tasks.length - 1)
                    Expanded(
                      child: Container(width: 1.5, color: lineCol),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    t.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[300]! : Colors.grey[800]!,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ── 7. CHAT (Viewport with bounce physics) ───────────────────────────────────
class ChatViewport extends StatelessWidget {
  final List<Widget> children;
  final ScrollController scrollController;

  const ChatViewport({
    super.key,
    required this.children,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }
}

// ── 8. PROMPT BAR (Unified Input Field) ──────────────────────────────────────
class PromptBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmitted;
  final bool isGenerating;
  final VoidCallback onCancel;
  final List<Widget> contextCards;
  final List<Widget> recommendationCards;
  final Widget? footer;

  const PromptBar({
    super.key,
    required this.controller,
    required this.onSubmitted,
    required this.isGenerating,
    required this.onCancel,
    this.contextCards = const [],
    this.recommendationCards = const [],
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xff16171d) : const Color(0xfff5f5f7);
    final borderC = isDark ? const Color(0xff2a2a2f) : const Color(0xffe0e0e0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Collated/Docked upper context/recommendations panel
        if (contextCards.isNotEmpty || recommendationCards.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xff0d0e12) : const Color(0xfffafafa),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border.all(color: borderC, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (contextCards.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: contextCards,
                  ),
                if (contextCards.isNotEmpty && recommendationCards.isNotEmpty)
                  const SizedBox(height: 8),
                if (recommendationCards.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(children: recommendationCards),
                  ),
              ],
            ),
          ),
        // Saisie input box below (joint directly without padding)
        Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: contextCards.isNotEmpty || recommendationCards.isNotEmpty
                ? const BorderRadius.vertical(bottom: Radius.circular(16))
                : BorderRadius.circular(16),
            border: Border.all(color: borderC, width: 0.8),
            boxShadow: BeautifulUITheme.softShadow(),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: 4,
                minLines: 1,
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black),
                decoration: const InputDecoration(
                  hintText: 'Écrire un message à Panda Agent...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
                onSubmitted: (_) => onSubmitted(),
              ),
              if (footer != null) ...[
                const SizedBox(height: 6),
                footer!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── 9. RECOMMENDATION CARD (Prompts Ask Suggestions) ─────────────────────────
class RecommendationCard extends StatelessWidget {
  final String promptText;
  final IconData icon;
  final VoidCallback onTap;

  const RecommendationCard({
    super.key,
    required this.promptText,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xff1d1e24) : const Color(0xffe2e8f0);

    return MarginWidget(
      margin: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: BeautifulUITheme.accentColor),
              const SizedBox(width: 6),
              Text(
                promptText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 10. CONTEXT CARDS (Puces d'Ancrages de Fichiers) ─────────────────────────
class ContextCard extends StatelessWidget {
  final String fileName;
  final VoidCallback onRemove;

  const ContextCard({
    super.key,
    required this.fileName,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BeautifulUITheme.accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BeautifulUITheme.accentColor.withOpacity(0.2), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Broken.document, size: 11, color: BeautifulUITheme.accentColor),
          const SizedBox(width: 4),
          Text(
            fileName,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: BeautifulUITheme.accentColor),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 10, color: BeautifulUITheme.accentColor),
          ),
        ],
      ),
    );
  }
}

// ── 11. DIFF TABLE (Vue comparateur de fichiers) ─────────────────────────────
class DiffLine {
  final String type; // '+', '-', ' '
  final int? oldLineNo;
  final int? newLineNo;
  final String content;

  DiffLine({required this.type, this.oldLineNo, this.newLineNo, required this.content});
}

class DiffTable extends StatelessWidget {
  final List<DiffLine> diffLines;

  const DiffTable({super.key, required this.diffLines});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff121316) : const Color(0xfffafafa),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? const Color(0xff2d2d2d) : const Color(0xffe0e0e0), width: 0.5),
      ),
      child: Column(
        children: diffLines.map((line) {
          final isAdd = line.type == '+';
          final isDel = line.type == '-';
          final bg = isAdd
              ? (isDark ? const Color(0x2210b981) : const Color(0x1110b981))
              : isDel
                  ? (isDark ? const Color(0x22ef4444) : const Color(0x11ef4444))
                  : Colors.transparent;
          final fg = isAdd
              ? BeautifulUITheme.neonGreen
              : isDel
                  ? BeautifulUITheme.warningRed
                  : (isDark ? Colors.grey[300]! : Colors.grey[800]!);

          return Container(
            color: bg,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    line.oldLineNo?.toString() ?? '',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.grey),
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Text(
                    line.newLineNo?.toString() ?? '',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.grey),
                  ),
                ),
                Text(
                  line.type,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: fg, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line.content,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: fg),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── 12. RECORDS TABLE (Vue Impact des Fichiers) ──────────────────────────────
class FileRecord {
  final String path;
  final String action; // 'created', 'modified', 'deleted'
  FileRecord({required this.path, required this.action});
}

class RecordsTable extends StatelessWidget {
  final List<FileRecord> records;

  const RecordsTable({super.key, required this.records});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rowBorder = BorderSide(color: isDark ? const Color(0xff2d2d2d) : const Color(0xffe0e0e0), width: 0.5);

    return Table(
      border: TableBorder(horizontalInside: rowBorder, bottom: rowBorder),
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(1),
      },
      children: records.map((rec) {
        final col = rec.action == 'created'
            ? BeautifulUITheme.neonGreen
            : rec.action == 'deleted'
                ? BeautifulUITheme.warningRed
                : BeautifulUITheme.neonPurple;

        return TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                rec.path,
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black, fontFamily: 'monospace'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: col.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(
                  rec.action,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: col),
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

// ── 13. FILTER TABLE (Tableau Triable & Filtrable) ───────────────────────────
class FilterTable extends StatefulWidget {
  final List<String> columns;
  final List<List<String>> data;

  const FilterTable({super.key, required this.columns, required this.data});

  @override
  State<FilterTable> createState() => _FilterTableState();
}

class _FilterTableState extends State<FilterTable> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderC = isDark ? const Color(0xff2d2d2d) : const Color(0xffe0e0e0);

    final filtered = widget.data.where((row) {
      return row.any((cell) => cell.toLowerCase().contains(_query.toLowerCase()));
    }).toList();

    return Column(
      children: [
        TextField(
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Filtrer les lignes...',
            prefixIcon: const Icon(Icons.search, size: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        Table(
          border: TableBorder(horizontalInside: BorderSide(color: borderC, width: 0.5)),
          children: [
            TableRow(
              decoration: BoxDecoration(color: isDark ? const Color(0xff1d1e24) : const Color(0xfff1f5f9)),
              children: widget.columns
                  .map((col) => Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(col, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ))
                  .toList(),
            ),
            ...filtered.map((row) => TableRow(
                  children: row
                      .map((cell) => Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(cell, style: const TextStyle(fontSize: 11)),
                          ))
                      .toList(),
                ))
          ],
        ),
      ],
    );
  }
}

// ── 14. SIDEBAR NAV (Barre latérale de Panda Agent) ─────────────────────────
class SidebarNav extends StatelessWidget {
  final int selectedIndex;
  final List<IconData> icons;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  const SidebarNav({
    super.key,
    required this.selectedIndex,
    required this.icons,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xff101114) : const Color(0xfff1f1f3);

    return Container(
      width: 50,
      color: bg,
      child: Column(
        children: List.generate(icons.length, (index) {
          final isSelected = index == selectedIndex;
          return Tooltip(
            message: labels[index],
            child: InkWell(
              onTap: () => onChanged(index),
              child: Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  border: isSelected
                      ? const Border(left: BorderSide(color: BeautifulUITheme.accentColor, width: 2.5))
                      : null,
                ),
                child: Icon(
                  icons[index],
                  size: 20,
                  color: isSelected
                      ? BeautifulUITheme.accentColor
                      : (isDark ? Colors.grey[500]! : Colors.grey[600]!),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── 15. SEARCH (Recherche Contextuelle) ──────────────────────────────────────
class ContextSearch extends StatelessWidget {
  final ValueChanged<String> onQueryChanged;
  final String placeholder;

  const ContextSearch({
    super.key,
    required this.onQueryChanged,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1a1b1f) : const Color(0xffe2e8f0),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDark ? const Color(0xff2d2d2d) : const Color(0xffcbd5e1), width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Icon(Icons.search, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: placeholder,
                hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onQueryChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 16. INSIGHT CARDS (Analyses Métriques) ───────────────────────────────────
class InsightCard extends StatelessWidget {
  final String title;
  final double score; // 0.0 à 1.0
  final String feedback;

  const InsightCard({
    super.key,
    required this.title,
    required this.score,
    required this.feedback,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scoreCol = score > 0.8
        ? BeautifulUITheme.neonGreen
        : score > 0.5
            ? BeautifulUITheme.neonPurple
            : BeautifulUITheme.warningRed;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff16171d) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xff2d2d2d) : const Color(0xffcbd5e1), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: score,
                  backgroundColor: isDark ? const Color(0xff25252b) : const Color(0xfff1f5f9),
                  color: scoreCol,
                  minHeight: 6,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(score * 100).toInt()}%',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: scoreCol),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            feedback,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ── 17. CODE BLOCK (Premium Code Viewer) ─────────────────────────────────────
class CodeBlockWidget extends StatelessWidget {
  final String codeContent;
  final String fileExtension;

  const CodeBlockWidget({
    super.key,
    required this.codeContent,
    required this.fileExtension,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xff0d0e12) : const Color(0xfff8fafc);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xff2d2d2d) : const Color(0xffe2e8f0), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xff16171d) : const Color(0xfff1f5f9),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  fileExtension.toUpperCase(),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: codeContent));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copié dans le presse-papiers !'), duration: Duration(seconds: 1)),
                    );
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.copy, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      const Text('Copier', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                codeContent,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 18. FINE-TUNE CARD (Agent Config Parameters) ─────────────────────────────
class AgentConfig {
  double temperature;
  String customPrompt;
  AgentConfig({required this.temperature, required this.customPrompt});
}

class FineTuneCard extends StatefulWidget {
  final AgentConfig currentConfig;
  final ValueChanged<AgentConfig> onConfigChanged;

  const FineTuneCard({
    super.key,
    required this.currentConfig,
    required this.onConfigChanged,
  });

  @override
  State<FineTuneCard> createState() => _FineTuneCardState();
}

class _FineTuneCardState extends State<FineTuneCard> {
  late double _temp;
  late TextEditingController _promptCtrl;

  @override
  void initState() {
    super.initState();
    _temp = widget.currentConfig.temperature;
    _promptCtrl = TextEditingController(text: widget.currentConfig.customPrompt);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff16171d) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xff2d2d2d) : const Color(0xffcbd5e1), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Température du Modèle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Text(_temp.toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: BeautifulUITheme.accentColor)),
            ],
          ),
          Slider(
            value: _temp,
            min: 0.0,
            max: 1.0,
            activeColor: BeautifulUITheme.accentColor,
            onChanged: (v) {
              setState(() => _temp = v);
              widget.onConfigChanged(AgentConfig(temperature: _temp, customPrompt: _promptCtrl.text));
            },
          ),
          const SizedBox(height: 8),
          const Text('Prompt Système', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _promptCtrl,
            maxLines: 4,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Écrire un prompt système...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) {
              widget.onConfigChanged(AgentConfig(temperature: _temp, customPrompt: v));
            },
          ),
        ],
      ),
    );
  }
}

// ── 19. SELECTION ACTIONS (Barre flottante d'actions rapides) ────────────────
class SelectionActionsOverlay extends StatelessWidget {
  final Offset position;
  final String selectedText;
  final Function(String action) onActionTriggered;

  const SelectionActionsOverlay({
    super.key,
    required this.position,
    required this.selectedText,
    required this.onActionTriggered,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xe6101114) : const Color(0xe6ffffff),
            borderRadius: BorderRadius.circular(8),
            boxShadow: BeautifulUITheme.softShadow(),
            border: Border.all(color: isDark ? const Color(0xff2d2d2d) : const Color(0xffcbd5e1), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _btn('Expliquer', () => onActionTriggered('explain')),
              _divider(),
              _btn('Optimiser', () => onActionTriggered('optimize')),
              _divider(),
              _btn('Créer Test', () => onActionTriggered('test')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: BeautifulUITheme.accentColor),
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 12,
      color: Colors.grey.withOpacity(0.3),
    );
  }
}

// Helper utility widget
class MarginWidget extends StatelessWidget {
  final Widget child;
  final EdgeInsets margin;
  const MarginWidget({super.key, required this.child, required this.margin});
  @override
  Widget build(BuildContext context) {
    return Padding(padding: margin, child: child);
  }
}
