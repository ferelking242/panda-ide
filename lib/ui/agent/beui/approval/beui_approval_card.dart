import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIApprovalCard — surface de décision agent (human-in-the-loop).
///
///   • Question avec description
///   • Choix unique (radio) ou multiple (checkbox)
///   • Réponse texte libre optionnelle
///   • Progress dots pour les étapes multiples
/// ═══════════════════════════════════════════════════════════════════════════

class BeUIApprovalOption {
  final String label;
  final String? description;

  const BeUIApprovalOption({required this.label, this.description});
}

class BeUIApprovalCard extends StatefulWidget {
  final String question;
  final String? description;
  final List<BeUIApprovalOption> options;
  final bool multiSelect;
  final bool allowTextInput;
  final String? textInputPlaceholder;
  final List<int> totalSteps;
  final int currentStep;
  final ValueChanged<List<int>> onOptionsSelected;
  final ValueChanged<String>? onTextSubmitted;
  final VoidCallback? onDeny;
  final bool isDark;

  const BeUIApprovalCard({
    super.key,
    required this.question,
    this.description,
    this.options = const [],
    this.multiSelect = false,
    this.allowTextInput = false,
    this.textInputPlaceholder,
    this.totalSteps = const [],
    this.currentStep = 0,
    required this.onOptionsSelected,
    this.onTextSubmitted,
    this.onDeny,
    this.isDark = true,
  });

  @override
  State<BeUIApprovalCard> createState() => _BeUIApprovalCardState();
}

class _BeUIApprovalCardState extends State<BeUIApprovalCard> {
  final Set<int> _selected = {};
  final TextEditingController _textCtrl = TextEditingController();
  bool _showTextInput = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = BeUIColors.accentOf(widget.isDark);
    final fg = widget.isDark ? Colors.grey[300]! : Colors.grey[800]!;
    final muted = widget.isDark ? Colors.grey[500]! : Colors.grey[500]!;
    final border = BeUIColors.borderOf(widget.isDark);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BeUIColors.deepSurfaceOf(widget.isDark),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Step progress dots ─────────────────────────────
          if (widget.totalSteps.length > 1)
            _StepDots(
              total: widget.totalSteps.length,
              current: widget.currentStep,
              accent: accent,
              muted: muted,
            ),

          // ── Question ───────────────────────────────────────
          Text(
            widget.question,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),

          if (widget.description != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.description!,
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],

          const SizedBox(height: 10),

          // ── Options ────────────────────────────────────────
          for (var i = 0; i < widget.options.length; i++)
            _buildOption(i, widget.options[i], accent, fg, muted),

          // ── Text input ─────────────────────────────────────
          if (widget.allowTextInput) ...[
            const SizedBox(height: 8),
            if (!_showTextInput)
              GestureDetector(
                onTap: () => setState(() => _showTextInput = true),
                child: Text(
                  'Autre réponse…',
                  style: TextStyle(
                    fontSize: 12,
                    color: accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              TextField(
                controller: _textCtrl,
                autofocus: true,
                style: TextStyle(fontSize: 13, color: fg),
                decoration: InputDecoration(
                  hintText: widget.textInputPlaceholder ?? 'Votre réponse…',
                  hintStyle: TextStyle(fontSize: 13, color: muted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: border),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  suffixIcon: GestureDetector(
                    onTap: () {
                      if (_textCtrl.text.trim().isNotEmpty) {
                        widget.onTextSubmitted?.call(_textCtrl.text.trim());
                      }
                    },
                    child: Icon(Icons.send, size: 16, color: accent),
                  ),
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) widget.onTextSubmitted?.call(v.trim());
                },
              ),
          ],

          const SizedBox(height: 10),

          // ── Deny button ────────────────────────────────────
          if (widget.onDeny != null)
            GestureDetector(
              onTap: widget.onDeny,
              child: Text(
                'Annuler',
                style: TextStyle(fontSize: 12, color: BeUIColors.error),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOption(int index, BeUIApprovalOption opt, Color accent, Color fg, Color muted) {
    final isSelected = _selected.contains(index);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (widget.multiSelect) {
            if (isSelected) {
              _selected.remove(index);
            } else {
              _selected.add(index);
            }
          } else {
            _selected.clear();
            _selected.add(index);
          }
        });
        widget.onOptionsSelected(_selected.toList());
      },
      child: AnimatedContainer(
        duration: BeUIDurations.fast,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.12)
              : BeUIColors.surfaceOf(widget.isDark),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? accent : BeUIColors.borderOf(widget.isDark),
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            // Radio / Checkbox
            AnimatedContainer(
              duration: BeUIDurations.fast,
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: widget.multiSelect ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: widget.multiSelect ? BorderRadius.circular(4) : null,
                color: isSelected ? accent : Colors.transparent,
                border: Border.all(
                  color: isSelected ? accent : muted,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Icon(
                        widget.multiSelect ? Icons.check : Icons.circle,
                        size: widget.multiSelect ? 12 : 8,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    opt.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? accent : fg,
                    ),
                  ),
                  if (opt.description != null)
                    Text(
                      opt.description!,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step dots for multi-step flow ─────────────────────────────────────────

class _StepDots extends StatelessWidget {
  final int total;
  final int current;
  final Color accent;
  final Color muted;

  const _StepDots({
    required this.total,
    required this.current,
    required this.accent,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          for (var i = 0; i < total; i++)
            AnimatedContainer(
              duration: BeUIDurations.fast,
              width: i == current ? 16 : 6,
              height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: i <= current ? accent : muted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}
