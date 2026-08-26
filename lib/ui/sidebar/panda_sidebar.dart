import 'package:flutter/material.dart';
import '../../core/broken_icons.dart';
import '../../ui/home_models.dart';
import '../../utils/themes.dart';

/// VS Code-style sidebar panel container.
/// The frame (header, title, close, physical shape) is reusable;
/// the content is provided via [panelBuilder].
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
  static const Color _kSidebarBgDark = Color(0xff252526);
  static const Color _kSidebarBgLight = Color(0xfff5f5f5);

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

  static const TextStyle _kSectionTitle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  @override
  Widget build(BuildContext context) {
    final isDark = appTheme.isDark;
    final bg = isDark ? _kSidebarBgDark : _kSidebarBgLight;
    final titleColor = isDark ? Colors.grey[400]! : Colors.grey[700]!;
    final borderColor =
        isDark ? const Color(0xff3c3c3c) : const Color(0xffdddddd);

    return Container(
      color: bg,
      child: SizedBox(
        width: kSidebarWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Panel header
            Container(
              height: 35,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _titles[activeRail] ?? '',
                      style: _kSectionTitle.copyWith(color: titleColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: onClose,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Broken.close_circle,
                          size: 14, color: titleColor),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _SidebarCard(
                  isFirst: true,
                  isLast: true,
                  child: panelBuilder(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// VS Code-style sidebar card (rounded corners, minimal border).
class _SidebarCard extends StatelessWidget {
  final bool isFirst;
  final bool isLast;
  final Widget child;

  const _SidebarCard({
    required this.isFirst,
    required this.isLast,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(6) : Radius.zero,
          bottom: isLast ? const Radius.circular(6) : Radius.zero,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
