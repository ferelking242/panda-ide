/// Gestionnaire des StatusBarItems des extensions.
/// Chaque extension peut créer des items dans la barre de statut.
library;

import 'package:flutter/material.dart';

// ── Modèle ────────────────────────────────────────────────────────────────

class StatusBarItemData {
  final String id;
  final int alignment; // 1 = Left, 2 = Right
  final int priority;
  String text;
  String? tooltip;
  String? colorHex;
  String? command;
  bool visible;

  StatusBarItemData({
    required this.id,
    required this.alignment,
    required this.priority,
    this.text = '',
    this.tooltip,
    this.colorHex,
    this.command,
    this.visible = false,
  });

  Color get color {
    if (colorHex == null) return Colors.white;
    try {
      final hex = colorHex!.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.white;
    }
  }
}

// ── Singleton manager ─────────────────────────────────────────────────────

class StatusBarManager extends ChangeNotifier {
  static final StatusBarManager instance = StatusBarManager._();
  StatusBarManager._();

  final Map<String, StatusBarItemData> _items = {};

  void create({
    required String id,
    required int alignment,
    required int priority,
  }) {
    _items.putIfAbsent(
      id,
      () => StatusBarItemData(
          id: id, alignment: alignment, priority: priority),
    );
    notifyListeners();
  }

  void update(Map<String, dynamic> data) {
    final id = data['id'] as String?;
    if (id == null) return;
    final item = _items[id];
    if (item == null) return;

    if (data.containsKey('text'))    item.text     = data['text']    as String? ?? '';
    if (data.containsKey('tooltip')) item.tooltip  = data['tooltip'] as String?;
    if (data.containsKey('color'))   item.colorHex = data['color']   as String?;
    if (data.containsKey('command')) item.command  = data['command'] as String?;
    if (data.containsKey('visible')) item.visible  = data['visible'] as bool? ?? false;

    notifyListeners();
  }

  void dispose(String id) {
    _items.remove(id);
    notifyListeners();
  }

  List<StatusBarItemData> get leftItems => _items.values
      .where((i) => i.visible && i.alignment == 1)
      .toList()
    ..sort((a, b) => b.priority.compareTo(a.priority));

  List<StatusBarItemData> get rightItems => _items.values
      .where((i) => i.visible && i.alignment == 2)
      .toList()
    ..sort((a, b) => a.priority.compareTo(b.priority));
}

// ── Widget à insérer dans la barre de statut de l'app ────────────────────
//
// Usage dans home.dart :
//   ExtensionStatusBarItems(side: StatusBarSide.left)
//   ExtensionStatusBarItems(side: StatusBarSide.right)

enum StatusBarSide { left, right }

class ExtensionStatusBarItems extends StatelessWidget {
  final StatusBarSide side;
  final void Function(String command)? onCommand;

  const ExtensionStatusBarItems({
    super.key,
    required this.side,
    this.onCommand,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StatusBarManager.instance,
      builder: (ctx, _) {
        final items = side == StatusBarSide.left
            ? StatusBarManager.instance.leftItems
            : StatusBarManager.instance.rightItems;

        if (items.isEmpty) return const SizedBox.shrink();

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: items.map((item) => _StatusBarChip(
            item: item,
            onTap: item.command != null
                ? () => onCommand?.call(item.command!)
                : null,
          )).toList(),
        );
      },
    );
  }
}

class _StatusBarChip extends StatelessWidget {
  final StatusBarItemData item;
  final VoidCallback? onTap;

  const _StatusBarChip({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item.tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            item.text,
            style: TextStyle(
              color: item.color,
              fontSize: 12,
              fontFamily: 'firaCode',
            ),
          ),
        ),
      ),
    );
  }
}
