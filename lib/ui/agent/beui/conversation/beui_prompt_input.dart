import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIPromptInput — zone de saisie agent auto-expandante.
///
///   • Auto-grow de 1 à 6 lignes
///   • Bouton send → stop avec morphing animé
///   • Footer configurable (actions, chips modèle/mode)
///   • Suggestions optionnelles
/// ═══════════════════════════════════════════════════════════════════════════
class BeUIPromptInput extends StatefulWidget {
  final TextEditingController? controller;
  final bool isGenerating;
  final VoidCallback? onSubmitted;
  final VoidCallback? onCancel;
  final String hintText;
  final Widget? footer;
  final bool isDark;

  const BeUIPromptInput({
    super.key,
    this.controller,
    this.isGenerating = false,
    this.onSubmitted,
    this.onCancel,
    this.hintText = 'Envoyer un message à l\'agent…',
    this.footer,
    this.isDark = true,
  });

  @override
  State<BeUIPromptInput> createState() => _BeUIPromptInputState();
}

class _BeUIPromptInputState extends State<BeUIPromptInput>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  final LayerLink _link = LayerLink();
  OverlayEntry? _suggestionsOverlay;
  int _maxLines = 1;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? TextEditingController();
    _focus = FocusNode();
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    if (widget.controller == null) _ctrl.dispose();
    _focus.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _ctrl.text;
    final newLines = '\n'.allMatches(text).length + 1;
    final clamped = newLines.clamp(1, 6);
    if (clamped != _maxLines) setState(() => _maxLines = clamped);
  }

  @override
  Widget build(BuildContext context) {
    final accent = BeUIColors.accentOf(widget.isDark);
    final border = BeUIColors.borderOf(widget.isDark);
    final surface = BeUIColors.deepSurfaceOf(widget.isDark);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Input container ──────────────────────────────────
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ctrl,
                focusNode: _focus,
                maxLines: _maxLines,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                style: TextStyle(
                  fontSize: 14,
                  color: widget.isDark ? Colors.grey[300] : Colors.grey[800],
                  height: 1.5,
                ),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                ),
                onSubmitted: (_) => _submit(),
              ),

              // ── Action bar ──────────────────────────────
              _buildActionBar(accent),
            ],
          ),
        ),

        // ── Footer (mode pill, model pill, etc.) ──────────
        if (widget.footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: widget.footer!,
          ),
      ],
    );
  }

  Widget _buildActionBar(Color accent) {
    final hasText = _ctrl.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 6, 6),
      child: Row(
        children: [
          const Spacer(),

          // ── Send / Stop button with morph ──────────────
          AnimatedSwitcher(
            duration: BeUIDurations.medium,
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: BeUICurves.spring),
              ),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: widget.isGenerating
                ? _StopButton(
                    key: const ValueKey('stop'),
                    onTap: widget.onCancel,
                  )
                : _SendButton(
                    key: const ValueKey('send'),
                    enabled: hasText,
                    accent: accent,
                    onTap: _submit,
                  ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (_ctrl.text.trim().isEmpty || widget.isGenerating) return;
    widget.onSubmitted?.call();
  }

  void _removeOverlay() {
    _suggestionsOverlay?.remove();
    _suggestionsOverlay = null;
  }
}

// ── Buttons ───────────────────────────────────────────────────────────────

class _SendButton extends StatelessWidget {
  final bool enabled;
  final Color accent;
  final VoidCallback onTap;

  const _SendButton({
    super.key,
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: BeUIDurations.fast,
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: enabled ? accent : accent.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.arrow_upward,
          size: 16,
          color: enabled ? Colors.white : accent.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _StopButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _StopButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: BeUIColors.error,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.stop, size: 16, color: Colors.white),
      ),
    );
  }
}
