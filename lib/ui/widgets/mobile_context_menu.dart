import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// VS Code-style context menu triggered by long press on mobile.
class MobileContextMenu extends StatelessWidget {
  final Widget child;
  final List<ContextMenuAction> actions;
  final VoidCallback? onLongPress;

  const MobileContextMenu({
    super.key,
    required this.child,
    required this.actions,
    this.onLongPress,
  });

  static Future<void> show({
    required BuildContext context,
    required Offset position,
    required List<ContextMenuAction> actions,
  }) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy,
        position.dx + 1, position.dy + 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: actions.map((a) => PopupMenuItem<String>(
        value: a.label,
        child: Row(
          children: [
            Icon(a.icon, size: 16, color: a.isDestructive ? Colors.red : null),
            const SizedBox(width: 10),
            Text(a.label, style: TextStyle(
              fontSize: 13,
              color: a.isDestructive ? Colors.red : null,
            )),
            if (a.shortcut != null) ...[
              const Spacer(),
              Text(a.shortcut!, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ],
        ),
      )).toList(),
    );

    if (result != null) {
      final action = actions.firstWhere((a) => a.label == result);
      action.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (details) {
        onLongPress?.call();
        show(
          context: context,
          position: details.globalPosition,
          actions: actions,
        );
      },
      child: child,
    );
  }
}

/// A single context menu action.
class ContextMenuAction {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? shortcut;
  final bool isDestructive;

  const ContextMenuAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.shortcut,
    this.isDestructive = false,
  });
}

/// Pre-built actions for file items.
class FileActions {
  static List<ContextMenuAction> forFile({
    required String fileName,
    required VoidCallback onCopyPath,
    required VoidCallback onCopyName,
    required VoidCallback onRename,
    required VoidCallback onDelete,
    required VoidCallback onOpen,
  }) {
    return [
      ContextMenuAction(label: 'Open', icon: Icons.open_in_new, onTap: onOpen),
      ContextMenuAction(label: 'Copy Name', icon: Icons.copy, onTap: onCopyName),
      ContextMenuAction(label: 'Copy Path', icon: Icons.route, onTap: onCopyPath),
      ContextMenuAction(label: 'Rename', icon: Icons.edit, onTap: onRename),
      ContextMenuAction(label: 'Delete', icon: Icons.delete, onTap: onDelete, isDestructive: true),
    ];
  }

  static List<ContextMenuAction> forTab({
    required VoidCallback onClose,
    required VoidCallback onCloseOthers,
    required VoidCallback onCloseAll,
    required VoidCallback onCopyPath,
    required VoidCallback onSplitRight,
  }) {
    return [
      ContextMenuAction(label: 'Close', icon: Icons.close, onTap: onClose, shortcut: 'Ctrl+W'),
      ContextMenuAction(label: 'Close Others', icon: Icons.close_fullscreen, onTap: onCloseOthers),
      ContextMenuAction(label: 'Close All', icon: Icons.clear_all, onTap: onCloseAll),
      const ContextMenuAction(label: '', icon: Icons.maximize), // separator
      ContextMenuAction(label: 'Copy Path', icon: Icons.route, onTap: onCopyPath),
      ContextMenuAction(label: 'Split Right', icon: Icons.vertical_split, onTap: onSplitRight),
    ];
  }

  static List<ContextMenuAction> forFolder({
    required VoidCallback onNewFile,
    required VoidCallback onNewFolder,
    required VoidCallback onCopyPath,
    required VoidCallback onRename,
    required VoidCallback onDelete,
  }) {
    return [
      ContextMenuAction(label: 'New File', icon: Icons.note_add, onTap: onNewFile),
      ContextMenuAction(label: 'New Folder', icon: Icons.create_new_folder, onTap: onNewFolder),
      ContextMenuAction(label: 'Copy Path', icon: Icons.route, onTap: onCopyPath),
      ContextMenuAction(label: 'Rename', icon: Icons.edit, onTap: onRename),
      ContextMenuAction(label: 'Delete', icon: Icons.delete, onTap: onDelete, isDestructive: true),
    ];
  }
}
