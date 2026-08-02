import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/browser_controller.dart';
import 'browser_tab_item.dart';

/// Barre d'onglets horizontale et scrollable avec bouton [+] et [⚙].
class BrowserTabBar extends StatelessWidget {
  const BrowserTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl   = context.watch<BrowserController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? const Color(0xff252526) : const Color(0xffececec);
    final sub    = isDark ? Colors.grey[500]! : Colors.grey[500]!;

    return Container(
      height: 34,
      color: bg,
      child: Row(
        children: [
          // Liste d'onglets scrollable
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ctrl.tabs.asMap().entries.map((entry) {
                  final idx     = entry.key;
                  final tab     = entry.value;
                  final profile = ctrl.profileForId(tab.profileId);
                  return BrowserTabItem(
                    key:        ValueKey('tab_item_${tab.id}'),
                    tab:        tab,
                    profile:    profile,
                    selected:   idx == ctrl.activeTabIndex,
                    controller: ctrl,
                  );
                }).toList(),
              ),
            ),
          ),

          // Bouton [+] nouveau onglet
          _TabBarButton(
            icon: Icons.add,
            tooltip: 'Nouvel onglet',
            color: sub,
            onTap: () => ctrl.addTab(),
          ),

          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _TabBarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _TabBarButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}
