// ═══════════════════════════════════════════════════════════════════════════
// WorkbenchPanelFrame — shell visuel partagé de tous les panneaux Workbench.
//
// Toute vue de nature « panneau Workbench » (Explorer, Search, Git, Tunnel,
// Copilot, Outline, Timeline, Extensions, panel inférieur…) passe par ce
// frame : un seul système de radius / bordure / fond / header / clipping.
//
// Principe VS Code : le header (titre uppercase + actions + fermeture)
// appartient au panneau, une seule structure visuelle — jamais de carte
// arrondie dans une carte arrondie.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import '../../core/broken_icons.dart';
import 'workbench_tokens.dart';

class WorkbenchPanelFrame extends StatelessWidget {
  /// Contenu de la vue (déjà wrappé dans son propre scroll si besoin).
  final Widget body;

  /// Titre uppercase affiché dans le header (ex: 'EXPLORATEUR').
  final String title;

  /// Actions spécifiques à la vue, placées à droite du header.
  final List<Widget> actions;

  /// Callback de fermeture du panneau ; null masque le bouton.
  final VoidCallback? onClose;

  final bool isDark;

  /// Padding horizontal appliqué au body (0 pour les vues pleine largeur
  /// comme l'arbre de fichiers).
  final EdgeInsets bodyPadding;

  const WorkbenchPanelFrame({
    super.key,
    required this.body,
    required this.title,
    required this.isDark,
    this.actions = const <Widget>[],
    this.onClose,
    this.bodyPadding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final fg = WorkbenchTokens.sidebarHeaderFg(isDark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header : titre + actions + close (sidebarpart.css .title) ──────
        Container(
          height: WorkbenchTokens.panelHeaderHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: WorkbenchTokens.spaceM,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: WorkbenchTokens.panelTitle(isDark),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              ...actions,
              if (onClose != null)
                _PanelCloseButton(onClose: onClose!, color: fg),
            ],
          ),
        ),
        // ── Body : même surface que le header, clip propre, aucun double fond
        Expanded(
          child: ClipRect(
            child: Padding(padding: bodyPadding, child: body),
          ),
        ),
      ],
    );
  }
}

/// Bouton de fermeture discret (VS Code : chevron/close 16px, hover subtil).
class _PanelCloseButton extends StatefulWidget {
  final VoidCallback onClose;
  final Color color;

  const _PanelCloseButton({required this.onClose, required this.color});

  @override
  State<_PanelCloseButton> createState() => _PanelCloseButtonState();
}

class _PanelCloseButtonState extends State<_PanelCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Fermer le panneau',
      child: Tooltip(
        message: 'Fermer le panneau',
        child: InkWell(
          onTap: widget.onClose,
          onHover: (h) => setState(() => _hovered = h),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              Broken.close_circle,
              size: 14,
              color: _hovered
                  ? widget.color.withValues(alpha: 1)
                  : widget.color.withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    );
  }
}
