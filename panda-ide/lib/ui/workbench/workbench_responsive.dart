// ═══════════════════════════════════════════════════════════════════════════
// WorkbenchResponsive — points de rupture et helpers responsive.
//
// Le Workbench reste LE MÊME système sur tous les écrans : il se compacte
// (masquage des éléments secondaires, réductions de paddings) au lieu de
// basculer sur une seconde interface.
// ═══════════════════════════════════════════════════════════════════════════
import 'workbench_tokens.dart';

enum WorkbenchDevice { phone, tablet, desktop }

abstract final class WorkbenchResponsive {
  static WorkbenchDevice deviceOf(double width) {
    if (width < WorkbenchBreakpoints.phone) return WorkbenchDevice.phone;
    if (width < WorkbenchBreakpoints.tablet) return WorkbenchDevice.tablet;
    return WorkbenchDevice.desktop;
  }

  /// Vrai sur téléphone : les éléments secondaires (encoding, indentation,
  /// fins de ligne…) se masquent avant de provoquer le moindre overflow.
  static bool isCompact(double width) => width < WorkbenchBreakpoints.phone;

  /// Les espacements se resserrent sur téléphone.
  static double gutter(double width) =>
      isCompact(width) ? WorkbenchTokens.spaceXS : WorkbenchTokens.spaceM;

  /// Hauteur de Status Bar : 22px desktop, 26px sur écran tactile.
  static double statusBarHeight(double width, bool isTouch) =>
      isTouch || isCompact(width)
          ? WorkbenchTokens.statusBarHeightTouch
          : WorkbenchTokens.statusBarHeight;
}
