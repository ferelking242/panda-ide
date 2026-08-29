import 'dart:async';
import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIMessageScroller — viewport conversation avec follow-edge.
///
/// Pendant le streaming, l'viewport suit automatiquement le bas.
/// Dès que l'utilisateur scrolle vers le haut (dépasse un seuil) → relâchement :
///   • Un bouton "↓ Live" apparaît en floating pill
///   • Un tap dessus ramène au bas avec animation douce
/// ═══════════════════════════════════════════════════════════════════════════
class BeUIMessageScroller extends StatefulWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final bool isStreaming;
  final ScrollController? scrollController;
  final double releaseThreshold;
  final EdgeInsetsGeometry? padding;

  const BeUIMessageScroller({super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.isStreaming = false,
    this.scrollController,
    this.releaseThreshold = 100,
    this.padding,
  });

  @override
  State<BeUIMessageScroller> createState() => BeUIMessageScrollerState();
}

class BeUIMessageScrollerState extends State<BeUIMessageScroller> {
  late final ScrollController _ctrl;
  bool _following = true;
  bool _showJumpButton = false;
  int _prevItemCount = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.scrollController ?? ScrollController();
    _ctrl.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant BeUIMessageScroller old) {
    super.didUpdateWidget(old);
    // New items while following → scroll to bottom
    if (widget.itemCount > _prevItemCount && _following && widget.isStreaming) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    _prevItemCount = widget.itemCount;
  }

  @override
  void dispose() {
    if (widget.scrollController == null) _ctrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_ctrl.hasClients) return;
    final pos = _ctrl.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - widget.releaseThreshold;

    if (atBottom && !_following) {
      setState(() {
        _following = true;
        _showJumpButton = false;
      });
    } else if (!atBottom && _following) {
      setState(() {
        _following = false;
        _showJumpButton = true;
      });
    }
  }

  void _scrollToBottom() {
    if (!_ctrl.hasClients) return;
    _ctrl.animateTo(
      _ctrl.position.maxScrollExtent,
      duration: BeUIDurations.medium,
      curve: BeUICurves.outCurve,
    );
  }

  void jumpToLive() {
    setState(() {
      _following = true;
      _showJumpButton = false;
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Message list ──────────────────────────────────────
        ListView.builder(
          controller: _ctrl,
          padding: widget.padding ?? const EdgeInsets.symmetric(vertical: 8),
          itemCount: widget.itemCount,
          itemBuilder: widget.itemBuilder,
        ),

        // ── Jump to live button ───────────────────────────────
        AnimatedSlide(
          offset: _showJumpButton ? Offset.zero : const Offset(0, 0.5),
          duration: BeUIDurations.medium,
          curve: BeUICurves.outCurve,
          child: AnimatedOpacity(
            opacity: _showJumpButton ? 1.0 : 0.0,
            duration: BeUIDurations.medium,
            child: Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: jumpToLive,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: BeUIColors.accentOf(
                        Theme.of(context).brightness == Brightness.dark,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.white),
                        SizedBox(width: 2),
                        Text(
                          'Live',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
