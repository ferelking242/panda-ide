/// Command Palette v2 — fuzzy search, categories, recent commands, context-sensitive.
///
/// Improvements over v1:
///   - Fuzzy matching (not just substring)
///   - Category groups (File, Edit, View, Git, etc.)
///   - Recent commands (most used first)
///   - Keyboard navigation (arrows, Enter, Esc)
///   - Workspace actions (new file, new folder, save, etc.)
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A command that can be executed from the palette.
class PaletteCommand {
  final String id;
  final String label;
  final String? category;
  final String? description;
  final IconData? icon;
  final List<String> aliases;
  final VoidCallback? onExecute;
  final int useCount;

  const PaletteCommand({
    required this.id,
    required this.label,
    this.category,
    this.description,
    this.icon,
    this.aliases = const [],
    this.onExecute,
    this.useCount = 0,
  });

  PaletteCommand copyWith({int? useCount, VoidCallback? onExecute}) {
    return PaletteCommand(
      id: id, label: label, category: category, description: description,
      icon: icon, aliases: aliases,
      onExecute: onExecute ?? this.onExecute,
      useCount: useCount ?? this.useCount,
    );
  }
}

/// Built-in workspace commands.
List<PaletteCommand> builtinCommands() => [
  const PaletteCommand(id: 'file.newFile', label: 'New File', category: 'File', icon: Icons.note_add_outlined),
  const PaletteCommand(id: 'file.newFolder', label: 'New Folder', category: 'File', icon: Icons.create_new_folder_outlined),
  const PaletteCommand(id: 'file.save', label: 'Save', category: 'File', icon: Icons.save_outlined, aliases: ['Ctrl+S']),
  const PaletteCommand(id: 'file.saveAll', label: 'Save All', category: 'File', icon: Icons.save),
  const PaletteCommand(id: 'file.open', label: 'Open File', category: 'File', icon: Icons.folder_open),
  const PaletteCommand(id: 'file.closeTab', label: 'Close Tab', category: 'File', icon: Icons.close),
  const PaletteCommand(id: 'file.closeAll', label: 'Close All Tabs', category: 'File', icon: Icons.close_fullscreen),
  const PaletteCommand(id: 'edit.undo', label: 'Undo', category: 'Edit', icon: Icons.undo, aliases: ['Ctrl+Z']),
  const PaletteCommand(id: 'edit.redo', label: 'Redo', category: 'Edit', icon: Icons.redo, aliases: ['Ctrl+Shift+Z']),
  const PaletteCommand(id: 'edit.find', label: 'Find in File', category: 'Edit', icon: Icons.find_replace, aliases: ['Ctrl+F']),
  const PaletteCommand(id: 'edit.findInFiles', label: 'Find in Files', category: 'Edit', icon: Icons.search, aliases: ['Ctrl+Shift+F']),
  const PaletteCommand(id: 'edit.format', label: 'Format Document', category: 'Edit', icon: Icons.format_align_left, aliases: ['Shift+Alt+F']),
  const PaletteCommand(id: 'edit.gotoLine', label: 'Go to Line', category: 'Edit', icon: Icons.numbers, aliases: ['Ctrl+G']),
  const PaletteCommand(id: 'view.toggleSidebar', label: 'Toggle Sidebar', category: 'View', icon: Icons.view_sidebar_outlined, aliases: ['Ctrl+B']),
  const PaletteCommand(id: 'view.toggleTerminal', label: 'Toggle Terminal', category: 'View', icon: Icons.terminal, aliases: ['Ctrl+`']),
  const PaletteCommand(id: 'view.toggleWordWrap', label: 'Toggle Word Wrap', category: 'View', icon: Icons.wrap_text, aliases: ['Alt+Z']),
  const PaletteCommand(id: 'view.zoomIn', label: 'Zoom In', category: 'View', icon: Icons.zoom_in, aliases: ['Ctrl+=']),
  const PaletteCommand(id: 'view.zoomOut', label: 'Zoom Out', category: 'View', icon: Icons.zoom_out, aliases: ['Ctrl+-']),
  const PaletteCommand(id: 'view.resetZoom', label: 'Reset Zoom', category: 'View', icon: Icons.zoom_out_map),
  const PaletteCommand(id: 'git.commit', label: 'Git: Commit', category: 'Git', icon: Icons.check),
  const PaletteCommand(id: 'git.push', label: 'Git: Push', category: 'Git', icon: Icons.upload),
  const PaletteCommand(id: 'git.pull', label: 'Git: Pull', category: 'Git', icon: Icons.download),
  const PaletteCommand(id: 'git.branch', label: 'Git: Create Branch', category: 'Git', icon: Icons.call_split),
  const PaletteCommand(id: 'git.diff', label: 'Git: View Changes', category: 'Git', icon: Icons.diff),
  const PaletteCommand(id: 'git.log', label: 'Git: Show Log', category: 'Git', icon: Icons.history),
  const PaletteCommand(id: 'editor.fold', label: 'Fold All', category: 'Editor', icon: Icons.unfold_less),
  const PaletteCommand(id: 'editor.unfold', label: 'Unfold All', category: 'Editor', icon: Icons.unfold_more),
  const PaletteCommand(id: 'editor.symbols', label: 'Go to Symbol', category: 'Editor', icon: Icons.symbolize, aliases: ['Ctrl+Shift+O']),
  const PaletteCommand(id: 'editor.multiCursor.selectAll', label: 'Select All Occurrences', category: 'Editor', icon: Icons.select_all, aliases: ['Ctrl+Shift+L']),
  const PaletteCommand(id: 'editor.multiCursor.next', label: 'Add Cursor at Next Occurrence', category: 'Editor', icon: Icons.control_point, aliases: ['Ctrl+D']),
  const PaletteCommand(id: 'ext.openMarketplace', label: 'Open Marketplace', category: 'Extensions', icon: Icons.storefront_outlined),
  const PaletteCommand(id: 'ext.manageInstalled', label: 'Manage Installed Extensions', category: 'Extensions', icon: Icons.extension),
  const PaletteCommand(id: 'settings.open', label: 'Open Settings', category: 'Preferences', icon: Icons.settings_outlined),
  const PaletteCommand(id: 'settings.keyboard', label: 'Keyboard Shortcuts', category: 'Preferences', icon: Icons.keyboard),
  const PaletteCommand(id: 'settings.theme', label: 'Color Theme', category: 'Preferences', icon: Icons.palette_outlined),
  const PaletteCommand(id: 'help.about', label: 'About Panda IDE', category: 'Help', icon: Icons.info_outline),
  const PaletteCommand(id: 'help.docs', label: 'Documentation', category: 'Help', icon: Icons.menu_book),
];

/// Fuzzy score — higher is better match.
double _fuzzyScore(String query, String text) {
  if (query.isEmpty) return 50;
  final q = query.toLowerCase();
  final t = text.toLowerCase();

  // Exact match
  if (t == q) return 100;
  // Starts with
  if (t.startsWith(q)) return 90;
  // Contains
  if (t.contains(q)) return 70;

  // Fuzzy character match
  var qi = 0;
  var score = 0;
  var consecutive = 0;
  for (var ti = 0; ti < t.length && qi < q.length; ti++) {
    if (t[ti] == q[qi]) {
      qi++;
      consecutive++;
      score += consecutive * 2;
      // Bonus for word boundaries
      if (ti == 0 || t[ti - 1] == ' ' || t[ti - 1] == '.' || t[ti - 1] == '_') {
        score += 10;
      }
    } else {
      consecutive = 0;
    }
  }

  return qi == q.length ? score.toDouble() : 0;
}

/// Shows the command palette.
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CommandPalette(),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  List<PaletteCommand> _allCommands = [];
  List<PaletteCommand> _filtered = [];
  int _selectedIndex = 0;
  String _selectedCategory = 'All';
  static final SplayTreeMap<String, int> _useCounts = SplayTreeMap();

  @override
  void initState() {
    super.initState();
    _allCommands = builtinCommands();
    _filtered = _allCommands;
    _ctrl.addListener(_onQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onQuery);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onQuery() {
    final q = _ctrl.text.trim();
    setState(() {
      _filtered = _search(q, _selectedCategory);
      _selectedIndex = 0;
    });
  }

  List<PaletteCommand> _search(String query, String category) {
    var cmds = _allCommands;

    // Filter by category
    if (category != 'All') {
      cmds = cmds.where((c) => c.category == category).toList();
    }

    if (query.isEmpty) {
      // Sort by use count
      cmds = List.from(cmds)..sort((a, b) {
        final aCount = _useCounts[a.id] ?? 0;
        final bCount = _useCounts[b.id] ?? 0;
        return bCount.compareTo(aCount);
      });
      return cmds;
    }

    // Fuzzy search
    final scored = <(PaletteCommand, double)>[];
    for (final cmd in cmds) {
      var score = _fuzzyScore(query, cmd.label);
      score += _fuzzyScore(query, cmd.id) * 0.5;
      for (final alias in cmd.aliases) {
        score += _fuzzyScore(query, alias) * 0.3;
      }
      // Use count bonus
      score += (_useCounts[cmd.id] ?? 0) * 0.1;

      if (score > 10) {
        scored.add((cmd, score));
      }
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.map((s) => s.$1).toList();
  }

  void _execute(PaletteCommand cmd) {
    _useCounts[cmd.id] = (_useCounts[cmd.id] ?? 0) + 1;
    Navigator.of(context).pop();
    cmd.onExecute?.call();
  }

  List<String> get _categories {
    final cats = _allCommands.map((c) => c.category ?? 'Other').toSet().toList();
    return ['All', ...cats]..sort();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20)],
        ),
        child: Column(
          children: [
            // Handle
            Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(color: cs.onSurfaceVariant.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),

            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (e) {
                  if (e is! KeyDownEvent) return;
                  if (e.logicalKey == LogicalKeyboardKey.arrowDown) setState(() => _selectedIndex = (_selectedIndex + 1).clamp(0, _filtered.length - 1));
                  if (e.logicalKey == LogicalKeyboardKey.arrowUp) setState(() => (_selectedIndex - 1).clamp(0, _filtered.length - 1));
                  if (e.logicalKey == LogicalKeyboardKey.enter && _filtered.isNotEmpty) _execute(_filtered[_selectedIndex]);
                  if (e.logicalKey == LogicalKeyboardKey.escape) Navigator.pop(context);
                },
                child: TextField(
                  controller: _ctrl, focusNode: _focus,
                  style: TextStyle(color: cs.onSurface, fontSize: 15),
                  cursorColor: cs.primary,
                  decoration: InputDecoration(
                    hintText: 'Type a command...',
                    hintStyle: TextStyle(color: cs.onSurfaceVariant),
                    prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant, size: 20),
                    suffixIcon: _ctrl.text.isNotEmpty
                        ? IconButton(icon: Icon(Icons.clear, size: 18, color: cs.onSurfaceVariant), onPressed: () => _ctrl.clear())
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    filled: true, fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),

            // Category chips
            SizedBox(
              height: 36,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final cat = _categories[i];
                  final isSelected = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.white : cs.onSurface)),
                    selected: isSelected,
                    onSelected: (_) => setState(() { _selectedCategory = cat; _onQuery(); }),
                    selectedColor: cs.primary,
                    backgroundColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEEEEEE),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),

            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),

            // Count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('${_filtered.length} commands', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ),

            // Results
            Expanded(
              child: _filtered.isEmpty
                  ? Center(child: Text('No commands match', style: TextStyle(color: cs.onSurfaceVariant)))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemExtent: 44,
                      itemBuilder: (_, i) {
                        final cmd = _filtered[i];
                        final isSelected = i == _selectedIndex;
                        return Material(
                          color: isSelected ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
                          child: InkWell(
                            onTap: () => _execute(cmd),
                            onHover: (_) => setState(() => _selectedIndex = i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              child: Row(
                                children: [
                                  if (cmd.icon != null) ...[
                                    Icon(cmd.icon, size: 16, color: cs.onSurfaceVariant),
                                    const SizedBox(width: 10),
                                  ] else
                                    const SizedBox(width: 26),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(cmd.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
                                        if (cmd.description != null)
                                          Text(cmd.description!, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  if (cmd.category != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                      child: Text(cmd.category!, style: TextStyle(fontSize: 9, color: cs.primary, fontWeight: FontWeight.w600)),
                                    ),
                                  if (cmd.aliases.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(cmd.aliases.first, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.5), fontFamily: 'monospace')),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
