import 'package:flutter/material.dart';

/// Represents a single editor tab
class EditorTab {
  final String id;
  final String filePath;
  final String fileName;
  bool isDirty;
  bool isPinned;
  final String? language;
  final DateTime openedAt;
  DateTime lastAccessed;
  String? content;

  EditorTab({
    required this.id,
    required this.filePath,
    required this.fileName,
    this.isDirty = false,
    this.isPinned = false,
    this.language,
    DateTime? openedAt,
    DateTime? lastAccessed,
    this.content,
  })  : openedAt = openedAt ?? DateTime.now(),
        lastAccessed = lastAccessed ?? DateTime.now();
}

/// Represents an editor group (column/row)
class EditorGroup {
  final String id;
  final List<EditorTab> tabs;
  int activeTabIndex;
  String? splitDirection; // 'horizontal', 'vertical', null

  EditorGroup({
    required this.id,
    List<EditorTab>? tabs,
    this.activeTabIndex = 0,
    this.splitDirection,
  }) : tabs = tabs ?? [];

  EditorTab? get activeTab =>
      activeTabIndex >= 0 && activeTabIndex < tabs.length
          ? tabs[activeTabIndex]
          : null;
}

/// Tab manager for the editor
class TabManager extends ChangeNotifier {
  final List<EditorGroup> _groups = [];
  final List<String> _tabHistory = [];
  int _activeGroupIndex = 0;
  final int _maxTabsPerGroup = 20;

  List<EditorGroup> get groups => _groups;
  int get activeGroupIndex => _activeGroupIndex;
  EditorGroup? get activeGroup =>
      _activeGroupIndex < _groups.length
          ? _groups[_activeGroupIndex]
          : null;
  EditorTab? get activeTab => activeGroup?.activeTab;

  TabManager() {
    _groups.add(EditorGroup(id: _generateId()));
  }

  String _generateId() => 'tab_${DateTime.now().microsecondsSinceEpoch}';

  // ── Tab Operations ──────────────────────────────────────────────

  /// Open a file in a tab (or activate existing)
  void openFile(String filePath, String fileName,
      {String? language, String? content}) {
    final group = activeGroup;
    if (group == null) return;

    // Check if already open
    final existing = group.tabs.where((t) => t.filePath == filePath).toList();
    if (existing.isNotEmpty) {
      final tab = existing.first;
      group.activeTabIndex = group.tabs.indexOf(tab);
      tab.lastAccessed = DateTime.now();
      _trackHistory(tab.id);
      notifyListeners();
      return;
    }

    // Close oldest non-pinned if at max
    if (group.tabs.length >= _maxTabsPerGroup) {
      final nonPinned = group.tabs.where((t) => !t.isPinned).toList();
      if (nonPinned.isNotEmpty) {
        nonPinned.sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));
        closeTab(nonPinned.first.id);
      }
    }

    final tab = EditorTab(
      id: _generateId(),
      filePath: filePath,
      fileName: fileName,
      language: language,
      content: content,
    );
    group.tabs.add(tab);
    group.activeTabIndex = group.tabs.length - 1;
    _trackHistory(tab.id);
    notifyListeners();
  }

  /// Close a tab
  void closeTab(String tabId) {
    for (final group in _groups) {
      final idx = group.tabs.indexWhere((t) => t.id == tabId);
      if (idx != -1) {
        group.tabs.removeAt(idx);
        if (group.activeTabIndex >= group.tabs.length) {
          group.activeTabIndex = group.tabs.length - 1;
        }
        if (group.activeTabIndex < 0) group.activeTabIndex = 0;

        // Remove empty groups (keep at least one)
        if (group.tabs.isEmpty && _groups.length > 1) {
          final groupIdx = _groups.indexOf(group);
          _groups.remove(group);
          if (_activeGroupIndex >= _groups.length) {
            _activeGroupIndex = _groups.length - 1;
          }
        }
        notifyListeners();
        return;
      }
    }
  }

  /// Close all tabs in active group
  void closeAllTabs({bool keepPinned = true}) {
    final group = activeGroup;
    if (group == null) return;

    if (keepPinned) {
      group.tabs.removeWhere((t) => !t.isPinned);
    } else {
      group.tabs.clear();
    }
    group.activeTabIndex = 0;
    notifyListeners();
  }

  /// Close tabs to the right
  void closeTabsRight(String tabId) {
    final group = activeGroup;
    if (group == null) return;

    final idx = group.tabs.indexWhere((t) => t.id == tabId);
    if (idx == -1) return;

    group.tabs.removeRange(idx + 1, group.tabs.length);
    if (group.activeTabIndex >= group.tabs.length) {
      group.activeTabIndex = group.tabs.length - 1;
    }
    notifyListeners();
  }

  /// Close tabs to the left
  void closeTabsLeft(String tabId) {
    final group = activeGroup;
    if (group == null) return;

    final idx = group.tabs.indexWhere((t) => t.id == tabId);
    if (idx <= 0) return;

    // Keep pinned tabs on the left
    final pinnedLeft = group.tabs
        .takeWhile((t) => t.isPinned)
        .map((t) => t.id)
        .toList();

    group.tabs.removeRange(
        0, idx);
    // Re-add pinned ones at the beginning
    final pinned = pinnedLeft.where((id) =>
        !group.tabs.any((t) => t.id == id)).toList();

    if (group.activeTabIndex >= group.tabs.length) {
      group.activeTabIndex = group.tabs.length - 1;
    }
    notifyListeners();
  }

  /// Close other tabs (keep only the specified one)
  void closeOtherTabs(String tabId) {
    final group = activeGroup;
    if (group == null) return;

    final keep = group.tabs.firstWhere((t) => t.id == tabId);
    group.tabs.clear();
    group.tabs.add(keep);
    group.activeTabIndex = 0;
    notifyListeners();
  }

  /// Toggle pin on a tab
  void togglePin(String tabId) {
    for (final group in _groups) {
      final tab = group.tabs.where((t) => t.id == tabId).firstOrNull;
      if (tab != null) {
        tab.isPinned = !tab.isPinned;
        // Sort: pinned first
        final pinned = group.tabs.where((t) => t.isPinned).toList();
        final unpinned = group.tabs.where((t) => !t.isPinned).toList();
        group.tabs.clear();
        group.tabs.addAll(pinned);
        group.tabs.addAll(unpinned);
        group.activeTabIndex =
            group.tabs.indexWhere((t) => t.id == tabId);
        notifyListeners();
        return;
      }
    }
  }

  /// Mark tab as dirty
  void markDirty(String tabId, bool dirty) {
    for (final group in _groups) {
      final tab = group.tabs.where((t) => t.id == tabId).firstOrNull;
      if (tab != null) {
        tab.isDirty = dirty;
        notifyListeners();
        return;
      }
    }
  }

  /// Reorder tabs via drag-drop
  void reorderTab(int oldIndex, int newIndex) {
    final group = activeGroup;
    if (group == null) return;

    if (newIndex > oldIndex) newIndex--;
    final tab = group.tabs.removeAt(oldIndex);
    group.tabs.insert(newIndex, tab);
    group.activeTabIndex = newIndex;
    notifyListeners();
  }

  /// Move tab to another group
  void moveTabToGroup(String tabId, int targetGroupIndex) {
    EditorTab? tab;
    int sourceGroupIdx = -1;

    for (int i = 0; i < _groups.length; i++) {
      final idx = _groups[i].tabs.indexWhere((t) => t.id == tabId);
      if (idx != -1) {
        tab = _groups[i].tabs.removeAt(idx);
        sourceGroupIdx = i;
        break;
      }
    }

    if (tab == null || targetGroupIndex >= _groups.length) return;

    _groups[targetGroupIndex].tabs.add(tab);
    _groups[targetGroupIndex].activeTabIndex =
        _groups[targetGroupIndex].tabs.length - 1;

    // Clean up empty source group
    if (_groups[sourceGroupIdx].tabs.isEmpty && _groups.length > 1) {
      _groups.removeAt(sourceGroupIdx);
      if (_activeGroupIndex >= _groups.length) {
        _activeGroupIndex = _groups.length - 1;
      }
    }

    notifyListeners();
  }

  // ── Group Operations ────────────────────────────────────────────

  /// Split editor horizontally (side by side)
  void splitHorizontal() {
    if (_groups.length >= 4) return; // Max 4 columns

    final newGroup = EditorGroup(
      id: _generateId(),
      splitDirection: 'horizontal',
    );

    // Clone active tab to new group
    if (activeTab != null) {
      final clone = EditorTab(
        id: _generateId(),
        filePath: activeTab!.filePath,
        fileName: activeTab!.fileName,
        language: activeTab!.language,
        content: activeTab!.content,
      );
      newGroup.tabs.add(clone);
    }

    _groups.add(newGroup);
    _activeGroupIndex = _groups.length - 1;
    notifyListeners();
  }

  /// Split editor vertically (stacked)
  void splitVertical() {
    if (_groups.length >= 4) return;

    final newGroup = EditorGroup(
      id: _generateId(),
      splitDirection: 'vertical',
    );

    if (activeTab != null) {
      final clone = EditorTab(
        id: _generateId(),
        filePath: activeTab!.filePath,
        fileName: activeTab!.fileName,
        language: activeTab!.language,
        content: activeTab!.content,
      );
      newGroup.tabs.add(clone);
    }

    _groups.add(newGroup);
    _activeGroupIndex = _groups.length - 1;
    notifyListeners();
  }

  /// Close a group
  void closeGroup(int groupIndex) {
    if (groupIndex < 0 || groupIndex >= _groups.length) return;
    if (_groups.length <= 1) return;

    _groups.removeAt(groupIndex);
    if (_activeGroupIndex >= _groups.length) {
      _activeGroupIndex = _groups.length - 1;
    }
    notifyListeners();
  }

  /// Set active group
  void setActiveGroup(int index) {
    if (index >= 0 && index < _groups.length) {
      _activeGroupIndex = index;
      notifyListeners();
    }
  }

  // ── Navigation ──────────────────────────────────────────────────

  /// Go back in history
  void goBack() {
    if (_tabHistory.isEmpty) return;

    final tabId = _tabHistory.removeLast();
    for (final group in _groups) {
      final idx = group.tabs.indexWhere((t) => t.id == tabId);
      if (idx != -1) {
        _activeGroupIndex = _groups.indexOf(group);
        group.activeTabIndex = idx;
        notifyListeners();
        return;
      }
    }
  }

  /// Activate next tab
  void nextTab() {
    final group = activeGroup;
    if (group == null || group.tabs.length <= 1) return;

    final unpinned =
        group.tabs.where((t) => !t.isPinned).toList();
    if (unpinned.isEmpty) return;

    final currentIdx =
        unpinned.indexWhere((t) => t.id == group.activeTab?.id);
    final nextIdx = (currentIdx + 1) % unpinned.length;
    group.activeTabIndex = group.tabs.indexOf(unpinned[nextIdx]);
    _trackHistory(unpinned[nextIdx].id);
    notifyListeners();
  }

  /// Activate previous tab
  void previousTab() {
    final group = activeGroup;
    if (group == null || group.tabs.length <= 1) return;

    final unpinned =
        group.tabs.where((t) => !t.isPinned).toList();
    if (unpinned.isEmpty) return;

    final currentIdx =
        unpinned.indexWhere((t) => t.id == group.activeTab?.id);
    final prevIdx = (currentIdx - 1 + unpinned.length) % unpinned.length;
    group.activeTabIndex = group.tabs.indexOf(unpinned[prevIdx]);
    _trackHistory(unpinned[prevIdx].id);
    notifyListeners();
  }

  void _trackHistory(String tabId) {
    _tabHistory.remove(tabId);
    _tabHistory.add(tabId);
    // Limit history
    if (_tabHistory.length > 50) {
      _tabHistory.removeAt(0);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────

  /// Get tab count across all groups
  int get totalTabCount => _groups.fold(0, (s, g) => s + g.tabs.length);

  /// Get dirty tab count
  int get dirtyTabCount =>
      _groups.fold(0, (s, g) => s + g.tabs.where((t) => t.isDirty).length);

  /// Check if file is already open
  bool isFileOpen(String filePath) {
    return _groups.any((g) => g.tabs.any((t) => t.filePath == filePath));
  }

  /// Get the group that has a file open
  int? getGroupForFile(String filePath) {
    for (int i = 0; i < _groups.length; i++) {
      if (_groups[i].tabs.any((t) => t.filePath == filePath)) {
        return i;
      }
    }
    return null;
  }
}

/// Widget: Tab bar for an editor group
class EditorTabBar extends StatefulWidget {
  final EditorGroup group;
  final TabManager manager;
  final int groupIndex;
  final Function(String filePath) onTabTap;
  final Function(String tabId) onClose;
  final Function(String tabId, String action) onContextMenu;

  const EditorTabBar({
    super.key,
    required this.group,
    required this.manager,
    required this.groupIndex,
    required this.onTabTap,
    required this.onClose,
    required this.onContextMenu,
  });

  @override
  State<EditorTabBar> createState() => _EditorTabBarState();
}

class _EditorTabBarState extends State<EditorTabBar> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: const Color(0xFF181825),
      child: Row(
        children: [
          // Tabs
          Expanded(
            child: ReorderableListView(
              scrollDirection: Axis.horizontal,
              onReorder: (old, new_) {
                widget.manager.reorderTab(old, new_);
              },
              children: widget.group.tabs.map((tab) {
                final isActive = tab.id == widget.group.activeTab?.id;
                return GestureDetector(
                  key: ValueKey(tab.id),
                  onTap: () {
                    widget.manager.setActiveGroup(widget.groupIndex);
                    widget.onTabTap(tab.filePath);
                  },
                  onSecondaryTapDown: (details) {
                    _showContextMenu(context, details.globalPosition, tab);
                  },
                  child: Container(
                    width: 160,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF313244)
                          : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: isActive
                              ? const Color(0xFF89B4FA)
                              : Colors.transparent,
                          width: 2,
                        ),
                        right: const BorderSide(
                          color: Color(0xFF45475A),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Pin icon
                        if (tab.isPinned)
                          Icon(Icons.push_pin, size: 12,
                              color: Colors.white38),

                        // File name
                        Expanded(
                          child: Text(
                            tab.fileName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),

                        // Dirty indicator
                        if (tab.isDirty)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFAB387),
                              shape: BoxShape.circle,
                            ),
                          ),

                        // Close button
                        GestureDetector(
                          onTap: () => widget.onClose(tab.id),
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Split buttons
          SizedBox(
            width: 36,
            height: 36,
            child: PopupMenuButton(
              icon: const Icon(Icons.more_vert, size: 14, color: Colors.white54),
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'split_h', child: Text('Split Right')),
                const PopupMenuItem(value: 'split_v', child: Text('Split Down')),
                const PopupMenuItem(value: 'close_group', child: Text('Close Group')),
              ],
              onSelected: (v) {
                if (v == 'split_h') widget.manager.splitHorizontal();
                if (v == 'split_v') widget.manager.splitVertical();
                if (v == 'close_group') {
                  widget.manager.closeGroup(widget.groupIndex);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(
      BuildContext context, Offset position, EditorTab tab) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: <PopupMenuEntry<dynamic>>[
        const PopupMenuItem(value: 'close', child: Text('Close')),
        const PopupMenuItem(value: 'close_others', child: Text('Close Others')),
        const PopupMenuItem(value: 'close_right', child: Text('Close to the Right')),
        const PopupMenuItem(value: 'close_left', child: Text('Close to the Left')),
        const PopupMenuItem(value: 'close_all', child: Text('Close All')),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'pin',
          child: Text(tab.isPinned ? 'Unpin' : 'Pin'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'copy_path', child: Text('Copy Path')),
        const PopupMenuItem(value: 'copy_name', child: Text('Copy Name')),
        const PopupMenuItem(value: 'reveal_in_explorer', child: Text('Reveal in Explorer')),
      ],
    ).then((value) {
      if (value == null) return;
      widget.onContextMenu(tab.id, value);
    });
  }
}
