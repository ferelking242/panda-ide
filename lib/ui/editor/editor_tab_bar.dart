import 'package:flutter/material.dart';
import '../../core/broken_icons.dart';
import '../home_models.dart';

/// VS Code-style editor tab bar: tabs, split button, context menu.
class EditorTabBar extends StatelessWidget {
  final List<TabDef> tabs;
  final int activeTabIdx;
  final bool isPrimary;
  final bool splitEditor;
  final void Function(int idx) onTapTab;
  final void Function(int idx) onCloseTab;
  final void Function() onToggleSplit;
  final void Function() onCloseSplit;
  final void Function(BuildContext ctx, bool isDark, bool isPrimary)
      onShowMenu;

  const EditorTabBar({
    super.key,
    required this.tabs,
    required this.activeTabIdx,
    this.isPrimary = true,
    this.splitEditor = false,
    required this.onTapTab,
    required this.onCloseTab,
    required this.onToggleSplit,
    required this.onCloseSplit,
    required this.onShowMenu,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tabBg =
        isDark ? const Color(0xff252526) : const Color(0xfff3f3f3);
    final activeTabBg =
        isDark ? const Color(0xff1e1e1e) : Colors.white;
    final inactiveFg =
        isDark ? Colors.grey[500]! : Colors.grey[600]!;
    final activeFg =
        isDark ? Colors.grey[300]! : Colors.grey[800]!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 35,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(color: tabBg),
          child: Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(tabs.length, (i) {
                    final tab = tabs[i];
                    final isActive = i == activeTabIdx;
                    return GestureDetector(
                      onTap: () => onTapTab(i),
                      child: Container(
                        height: 35,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: isActive
                              ? activeTabBg
                              : Colors.transparent,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8)),
                        ),
                        child: Row(children: [
                          Icon(tab.icon,
                              size: 13,
                              color:
                                  isActive ? activeFg : inactiveFg),
                          const SizedBox(width: 6),
                          Text(tab.title,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: tab.isPreview ? FontStyle.italic : FontStyle.normal,
                                  color: isActive
                                      ? activeFg
                                      : inactiveFg)),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => onCloseTab(i),
                            child: Icon(Broken.close_circle,
                                size: 12,
                                color: isActive
                                    ? inactiveFg
                                    : inactiveFg
                                        .withValues(alpha: 0.3)),
                          ),
                        ]),
                      ),
                    );
                  }),
                ),
              ),
            ),
            // ── Right-side buttons ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Builder(
                builder: (ctx) => Row(children: [
                  if (isPrimary && !splitEditor)
                    Tooltip(
                      message: "Diviser l'éditeur",
                      child: InkWell(
                        onTap: onToggleSplit,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4),
                          child: Icon(Broken.element_2,
                              size: 15, color: inactiveFg),
                        ),
                      ),
                    ),
                  Tooltip(
                    message: "Plus d'actions",
                    child: InkWell(
                      onTap: () =>
                          onShowMenu(ctx, isDark, isPrimary),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4),
                        child: Icon(Broken.more_circle,
                            size: 15, color: inactiveFg),
                      ),
                    ),
                  ),
                  if (!isPrimary)
                    Tooltip(
                      message: 'Fermer la division',
                      child: InkWell(
                        onTap: onCloseSplit,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4),
                          child: Icon(Broken.close_circle,
                              size: 15, color: inactiveFg),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

/// Shows the VS Code-style editor context menu (Close, Close Others, Split...).
void showEditorContextMenu(
  BuildContext ctx,
  bool isDark,
  bool isPrimary,
  List<TabDef> tabs,
  int activeTabIdx,
  void Function(String action, int idx) onAction,
) {
  final fg = isDark ? Colors.grey[300]! : Colors.grey[800]!;
  final fgDim = isDark ? Colors.grey[500]! : Colors.grey[500]!;
  final bg =
      isDark ? const Color(0xff252526) : const Color(0xfff3f3f3);
  final shortcutStyle = TextStyle(fontSize: 11, color: fgDim);

  PopupMenuItem<String> _mi(String value, String label,
      [String? shortcut]) {
    return PopupMenuItem<String>(
        value: value,
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 13, color: fg)),
              if (shortcut != null)
                Text(shortcut, style: shortcutStyle),
            ]));
  }

  showMenu<String>(
    context: ctx,
    position: const RelativeRect.fromLTRB(0, 35, 0, 0),
    color: bg,
    shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    items: [
      _mi('close', 'Close', 'Ctrl+W'),
      _mi('close_others', 'Close Others', 'Ctrl+K Ctrl+W'),
      _mi('close_right', 'Close to the Right'),
      _mi('close_saved', 'Close Saved', 'Ctrl+K U'),
      _mi('close_all', 'Close All', 'Ctrl+K W'),
      const PopupMenuDivider(height: 1),
      _mi('reopen', 'Reopen Editor With...'),
      const PopupMenuDivider(height: 1),
      _mi('keep_open', 'Keep Open'),
      _mi('pin', 'Pin'),
      _mi('unpin', 'Unpin'),
      const PopupMenuDivider(height: 1),
      _mi('split_right', 'Split Right', 'Ctrl+\\\\'),
      _mi('split_down', 'Split Down'),
      const PopupMenuDivider(height: 1),
      _mi('move_new_window', 'Move into New Window'),
      _mi('copy_new_window', 'Copy into New Window'),
      const PopupMenuDivider(height: 1),
      _mi('share', 'Share'),
      const PopupMenuDivider(height: 1),
      _mi('show_opened', 'Show Opened Editors'),
      _mi('enable_preview', 'Enable Preview Editors'),
    ],
  ).then((value) {
    if (value == null) return;
    onAction(value, activeTabIdx);
  });
}
