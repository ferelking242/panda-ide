// ═══════════════════════════════════════════════════════════════════════════
// WorkbenchTokens — source unique de vérité visuelle du Workbench Panda.
//
// Métriques portées depuis microsoft/vscode (MIT) :
//   * src/vs/workbench/browser/parts/statusbar/media/statusbarpart.css
//       → barre 22px, police 12px, item max-width 40vw, paddings 2/3/5px
//   * src/vs/workbench/browser/parts/editor/media/multieditortabscontrol.css
//       → hauteur d'onglet 35px, bordure inférieure 1px, accent haut 1px
//   * src/vs/workbench/browser/parts/sidebar/media/sidebarpart.css
//       → titre uppercase, actions de titre à droite
//   * src/vs/workbench/common/theme.ts → couleurs dark/light
//
// Adapté au thème Panda (scaffoldBg 0xff181818) : les surfaces dérivent du
// theme.ts mais se calent sur le gris Panda pour que l'ensemble reste
// homogène. Dark + Light couverts.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

/// Breakpoints du Workbench (une seule interface qui se compacte, jamais
/// une seconde interface « mobile »).
abstract final class WorkbenchBreakpoints {
  static const double phone = 600;
  static const double tablet = 1024;

  static bool isPhone(double width) => width < phone;
  static bool isTabletOrLarger(double width) => width >= tablet;
}

abstract final class WorkbenchTokens {
  // ── Métriques de barres (theme.ts + statusbarpart.css) ──────────────────
  /// Hauteur de la Title Bar / barre supérieure.
  static const double titleBarHeight = 35;

  /// Hauteur de la Tab Bar (VS Code : 35px).
  static const double tabBarHeight = 35;

  /// Hauteur de la Status Bar (VS Code : 22px ; 26px sur écran tactile).
  static const double statusBarHeight = 22;
  static const double statusBarHeightTouch = 26;

  /// Hauteur du header des panneaux (sidebar / bottom panel).
  static const double panelHeaderHeight = 35;

  /// Largeur de l'Activity Bar (VS Code : 48px).
  static const double activityBarWidth = 48;

  /// Hauteur d'entrée de la Status Bar côté tactile.
  static const double statusItemMinTap = 28;

  // ── Rayons ──────────────────────────────────────────────────────────────
  // Aucun rayon « par panneau » : arrondir le sidebar ET l'éditeur produit deux
  // surfaces qui se font face (« SIDEBAR ) ( EDITOR »). Le seul rayon du
  // Workbench est celui de la silhouette (shellRadius, ci-dessous).

  // ── SILHOUETTE du Workbench (une seule forme extérieure) ────────────────
  // Le Workbench entier (Title Bar + Activity | Sidebar | Editor + Status Bar)
  // est découpé par UN SEUL ClipRRect : seuls les coins EXTERIEURS sont
  // arrondis, toutes les séparations internes restent droites. Il ne doit donc
  // JAMAIS y avoir d'arrondi propre au sidebar côté éditeur ni d'éditeur arrondi
  // côté sidebar (pas de « SIDEBAR ) ( EDITOR »).
  static const double shellRadius = 16;

  /// Marge entre le bord de l'écran et le shell. Elle rend les coins arrondis
  /// lisibles dans les deux thèmes (en dark les surfaces et le scaffold sont
  /// proches : sans marge + filet, la silhouette serait invisible).
  static const double shellInset = 8;

  /// Filet 1px qui trace la silhouette (et ses coins) même en dark.
  static Color shellBorder(bool dark) =>
      dark ? const Color(0xff2f2f2f) : const Color(0xffdcdcdc);

  // ── Espacements ─────────────────────────────────────────────────────────
  static const double spaceXXS = 2;
  static const double spaceXS = 4;
  static const double spaceS = 6;
  static const double spaceM = 10;
  static const double spaceL = 14;

  /// Durée des micro-animations (VS Code reste un IDE : discret).
  static const Duration fastAnim = Duration(milliseconds: 180);
  static const Duration panelAnim = Duration(milliseconds: 220);
  static const Curve panelCurve = Curves.easeOutCubic;

  // ── Accent Panda (indicateur actif / sélection) ─────────────────────────
  static const Color accent = Color(0xff6366f1);

  // ── Couleurs éditeur & chrome (theme.ts + Dark Modern) ──────────────────
  static Color editorBg(bool dark) => dark ? const Color(0xff1f1f1f) : Colors.white;
  static Color tabBarBg(bool dark) => dark ? const Color(0xff181818) : const Color(0xffececec);
  static Color tabActiveBg(bool dark) => dark ? const Color(0xff1f1f1f) : Colors.white;
  static Color tabInactiveFg(bool dark) => dark ? const Color(0xff9d9d9d) : const Color(0xff616161);
  static Color tabActiveFg(bool dark) => dark ? const Color(0xffcccccc) : const Color(0xff3b3b3b);

  /// Bordure 1px sous la Tab Bar (tabs-border-bottom).
  static Color tabBarBorder(bool dark) => dark ? const Color(0xff2b2b2b) : const Color(0xffdcdcdc);

  static Color activityBg(bool dark) => dark ? const Color(0xff181818) : const Color(0xffe8e8e8);
  static Color activityFg(bool dark) => dark ? const Color(0xff858585) : const Color(0xff616161);
  static Color activitySelectedFg(bool dark) => dark ? Colors.white : const Color(0xff1a1a1a);

  static Color sidebarBg(bool dark) => dark ? const Color(0xff202020) : const Color(0xfff3f3f3);
  static Color sidebarHeaderFg(bool dark) => dark ? const Color(0xffbbbbbb) : const Color(0xff616161);
  static Color titleBarBg(bool dark) => dark ? const Color(0xff181818) : const Color(0xffe8e8e8);
  static Color panelBg(bool dark) => dark ? const Color(0xff181818) : const Color(0xfff3f3f3);
  static Color panelBorderFg(bool dark) => dark ? const Color(0xff2b2b2b) : const Color(0xffdcdcdc);
  static Color inputBg(bool dark) => dark ? const Color(0xff313131) : Colors.white;

  /// Fond de la Status Bar — VS Code : statusBar.background.
  static Color statusBarBg(bool dark) => dark ? const Color(0xff181818) : const Color(0xffe8e8e8);

  /// Texte de la Status Bar — contraste inversé par rapport au fond.
  static Color statusBarFg(bool dark) => dark ? const Color(0xffcccccc) : const Color(0xff3b3b3b);

  /// statusBarItem.hoverBackground / activeBackground.
  static Color statusHover(bool dark) => dark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06);
  static Color statusActive(bool dark) => dark ? Colors.white.withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.10);

  /// Couleurs d'erreur / warning (theme.ts editorError/editorWarning).
  static const Color errorFg = Color(0xfff14c4c);
  static const Color warningFg = Color(0xffcca700);
  static const Color infoFg = Color(0xff3794ff);

  /// Indicateur AI/Copilot actif.
  static const Color aiActiveFg = Color(0xff4ec9b0);

  // ── Sidebar : largeur par breakpoints ───────────────────────────────────
  /// Desktop ≥1024px : 280–320px.
  static double sidebarWidthDesktop(double width) => (width * 0.22).clamp(280.0, 320.0);

  /// Tablette 600–1024px : 260–300px.
  static double sidebarWidthTablet(double width) => (width * 0.30).clamp(260.0, 300.0);

  /// Téléphone <600px : on réserve d'abord le shell (marge), l'Activity Bar
  /// et une largeur d'éditeur utilisable — le sidebar pousse l'éditeur, il ne
  /// doit jamais lui laisser 10px de place.
  static double sidebarWidthPhone(double width) {
    final available = width - (shellInset * 2) - activityBarWidth;
    return (available * 0.70).clamp(170.0, 285.0);
  }

  static double sidebarWidth(double width) {
    if (WorkbenchBreakpoints.isTabletOrLarger(width)) return sidebarWidthDesktop(width);
    if (WorkbenchBreakpoints.isPhone(width)) return sidebarWidthPhone(width);
    return sidebarWidthTablet(width);
  }

  // ── Typographie des en-têtes (sidebarpart.css : uppercase, discret) ─────
  static TextStyle panelTitle(bool dark) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
        color: sidebarHeaderFg(dark),
      );

  static TextStyle statusText(bool dark) => TextStyle(
        fontSize: 12,
        height: 1.0,
        color: statusBarFg(dark),
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
