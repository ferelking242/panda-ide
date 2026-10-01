import 'package:flutter/material.dart';
import '../../utils/themes.dart';
import '../workbench/workbench_panel_frame.dart';
import '../workbench/workbench_tokens.dart';

/// VS Code-style sidebar panel container.
///
/// Il ne possède SON AUCUN style visuel propre : il délègue exactement la même
/// structure que `home.dart` → `_buildSidebarPanel()` (header + fond + bordure +
/// clipping). Une seule architecture, jamais deux systèmes concurrents.
///
/// Les coins arrondis appartiennent à la silhouette du Workbench (le ClipRRect
/// du shell dans `home.dart`) : ici les séparations internes restent droites.
class PandaSidebarPanel extends StatelessWidget {
  final AppTheme appTheme;
  final int activeRail;
  final VoidCallback onClose;
  final Widget Function(BuildContext context) panelBuilder;

  const PandaSidebarPanel({
    super.key,
    required this.appTheme,
    required this.activeRail,
    required this.onClose,
    required this.panelBuilder,
  });

  static const double kSidebarWidth = 280;

  static const Map<int, String> _titles = {
    1: 'EXPLORATEUR',
    2: 'RECHERCHER',
    3: 'CONTRÔLE GIT',
    4: 'EXÉCUTER / DEBUG',
    5: 'TUNNEL / SSH',
    6: 'MARKETPLACE',
    7: 'GATEWAY AI',
    8: 'NAVIGATEUR',
    9: 'GITHUB COPILOT',
    10: 'PANDA AGENT',
    11: 'MODÈLES LOCAUX',
  };

  @override
  Widget build(BuildContext context) {
    final isDark = appTheme.isDark;
    // Même shell que home.dart : un seul WorkbenchPanelFrame, header ET contenu
    // dans la même surface, sans carte arrondie imbriquée.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WorkbenchTokens.sidebarBg(isDark),
        border: Border(
          right: BorderSide(color: WorkbenchTokens.panelBorderFg(isDark)),
        ),
      ),
      child: WorkbenchPanelFrame(
        title: _titles[activeRail] ?? '',
        isDark: isDark,
        onClose: onClose,
        body: panelBuilder(context),
      ),
    );
  }
}
