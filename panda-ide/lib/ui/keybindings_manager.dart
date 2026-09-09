import 'package:flutter/material.dart';

/// Represents a single keybinding
class Keybinding {
  final String command;
  final String key;
  final String? when; // Context condition
  final String category;
  final String description;
  final bool isCustom;

  const Keybinding({
    required this.command,
    required this.key,
    this.when,
    required this.category,
    required this.description,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
    'command': command,
    'key': key,
    'when': when,
    'category': category,
    'description': description,
    'isCustom': isCustom,
  };

  factory Keybinding.fromJson(Map<String, dynamic> json) => Keybinding(
    command: json['command'],
    key: json['key'],
    when: json['when'],
    category: json['category'] ?? 'General',
    description: json['description'] ?? '',
    isCustom: json['isCustom'] ?? false,
  );
}

/// Default keybindings (VS Code-like)
class DefaultKeybindings {
  static const List<Keybinding> all = [
    // File operations
    Keybinding(command: 'workbench.action.files.newFile', key: 'Ctrl+N', category: 'File', description: 'New File'),
    Keybinding(command: 'workbench.action.files.openFile', key: 'Ctrl+O', category: 'File', description: 'Open File'),
    Keybinding(command: 'workbench.action.files.save', key: 'Ctrl+S', category: 'File', description: 'Save'),
    Keybinding(command: 'workbench.action.files.saveAll', key: 'Ctrl+Shift+S', category: 'File', description: 'Save All'),
    Keybinding(command: 'workbench.action.files.closeFile', key: 'Ctrl+W', category: 'File', description: 'Close Editor'),
    Keybinding(command: 'workbench.action.closeWindow', key: 'Ctrl+Shift+W', category: 'File', description: 'Close Window'),

    // Edit operations
    Keybinding(command: 'editor.action.undo', key: 'Ctrl+Z', category: 'Edit', description: 'Undo'),
    Keybinding(command: 'editor.action.redo', key: 'Ctrl+Shift+Z', category: 'Edit', description: 'Redo'),
    Keybinding(command: 'editor.action.clipboardCopyAction', key: 'Ctrl+C', category: 'Edit', description: 'Copy'),
    Keybinding(command: 'editor.action.clipboardCutAction', key: 'Ctrl+X', category: 'Edit', description: 'Cut'),
    Keybinding(command: 'editor.action.clipboardPasteAction', key: 'Ctrl+V', category: 'Edit', description: 'Paste'),
    Keybinding(command: 'editor.action.selectAll', key: 'Ctrl+A', category: 'Edit', description: 'Select All'),
    Keybinding(command: 'editor.action.find', key: 'Ctrl+F', category: 'Edit', description: 'Find'),
    Keybinding(command: 'editor.action.startFindReplaceAction', key: 'Ctrl+H', category: 'Edit', description: 'Find and Replace'),
    Keybinding(command: 'editor.action.findInFiles', key: 'Ctrl+Shift+F', category: 'Edit', description: 'Find in Files'),
    Keybinding(command: 'editor.action.replaceAll', key: 'Ctrl+Shift+H', category: 'Edit', description: 'Replace All'),
    Keybinding(command: 'editor.action.duplicateSelection', key: 'Ctrl+Shift+D', category: 'Edit', description: 'Duplicate Line'),
    Keybinding(command: 'editor.action.deleteLines', key: 'Ctrl+Shift+K', category: 'Edit', description: 'Delete Line'),
    Keybinding(command: 'editor.action.moveLinesUp', key: 'Alt+Up', category: 'Edit', description: 'Move Line Up'),
    Keybinding(command: 'editor.action.moveLinesDown', key: 'Alt+Down', category: 'Edit', description: 'Move Line Down'),
    Keybinding(command: 'editor.action.copyLinesUpAction', key: 'Shift+Alt+Up', category: 'Edit', description: 'Copy Line Up'),
    Keybinding(command: 'editor.action.copyLinesDownAction', key: 'Shift+Alt+Down', category: 'Edit', description: 'Copy Line Down'),
    Keybinding(command: 'editor.action.indentLines', key: 'Tab', category: 'Edit', description: 'Indent Line', when: 'editorTextFocus'),
    Keybinding(command: 'editor.action.outdentLines', key: 'Shift+Tab', category: 'Edit', description: 'Outdent Line', when: 'editorTextFocus'),
    Keybinding(command: 'editor.action.triggerSuggest', key: 'Ctrl+Space', category: 'Edit', description: 'Trigger Suggest'),
    Keybinding(command: 'editor.action.triggerParameterHints', key: 'Ctrl+Shift+Space', category: 'Edit', description: 'Parameter Hints'),
    Keybinding(command: 'editor.action.formatDocument', key: 'Shift+Alt+F', category: 'Edit', description: 'Format Document'),
    Keybinding(command: 'editor.action.formatSelection', key: 'Ctrl+K Ctrl+F', category: 'Edit', description: 'Format Selection'),
    Keybinding(command: 'editor.action.commentLine', key: 'Ctrl+/', category: 'Edit', description: 'Toggle Line Comment'),
    Keybinding(command: 'editor.action.blockComment', key: 'Shift+Alt+A', category: 'Edit', description: 'Toggle Block Comment'),
    Keybinding(command: 'editor.action.trimTrailingWhitespace', key: 'Ctrl+K Ctrl+X', category: 'Edit', description: 'Trim Trailing Whitespace'),

    // Navigation
    Keybinding(command: 'workbench.action.quickOpen', key: 'Ctrl+P', category: 'Navigation', description: 'Quick Open File'),
    Keybinding(command: 'workbench.action.showCommands', key: 'Ctrl+Shift+P', category: 'Navigation', description: 'Command Palette'),
    Keybinding(command: 'workbench.action.gotoLine', key: 'Ctrl+G', category: 'Navigation', description: 'Go to Line'),
    Keybinding(command: 'workbench.action.gotoSymbol', key: 'Ctrl+Shift+O', category: 'Navigation', description: 'Go to Symbol'),
    Keybinding(command: 'workbench.action.openSettings', key: 'Ctrl+,', category: 'Navigation', description: 'Open Settings'),
    Keybinding(command: 'workbench.action.openGlobalSettings', key: 'Ctrl+Shift+,', category: 'Navigation', description: 'Open User Settings'),
    Keybinding(command: 'workbench.action.toggleSidebarVisibility', key: 'Ctrl+B', category: 'Navigation', description: 'Toggle Sidebar'),
    Keybinding(command: 'workbench.action.togglePanel', key: 'Ctrl+J', category: 'Navigation', description: 'Toggle Panel'),
    Keybinding(command: 'workbench.action.toggleTerminal', key: 'Ctrl+`', category: 'Navigation', description: 'Toggle Terminal'),
    Keybinding(command: 'editor.action.toggleMinimap', key: 'Ctrl+Shift+M', category: 'Navigation', description: 'Toggle Minimap'),
    Keybinding(command: 'editor.action.toggleWordWrap', key: 'Alt+Z', category: 'Navigation', description: 'Toggle Word Wrap'),
    Keybinding(command: 'workbench.action.focusEditor', key: 'Ctrl+1', category: 'Navigation', description: 'Focus Editor'),
    Keybinding(command: 'workbench.action.focusPanel', key: 'Ctrl+2', category: 'Navigation', description: 'Focus Panel'),
    Keybinding(command: 'workbench.action.focusSidebar', key: 'Ctrl+0', category: 'Navigation', description: 'Focus Sidebar'),

    // Editor actions
    Keybinding(command: 'editor.action.duplicateSelection', key: 'Ctrl+D', category: 'Editor', description: 'Add Selection To Next Find Match', when: 'editorTextFocus'),
    Keybinding(command: 'editor.action.selectHighlights', key: 'Ctrl+Shift+L', category: 'Editor', description: 'Select All Occurrences', when: 'editorTextFocus'),
    Keybinding(command: 'editor.action.insertCursorAbove', key: 'Ctrl+Alt+Up', category: 'Editor', description: 'Add Cursor Above'),
    Keybinding(command: 'editor.action.insertCursorBelow', key: 'Ctrl+Alt+Down', category: 'Editor', description: 'Add Cursor Below'),
    Keybinding(command: 'editor.action.foldAll', key: 'Ctrl+K Ctrl+0', category: 'Editor', description: 'Fold All'),
    Keybinding(command: 'editor.action.unfoldAll', key: 'Ctrl+K Ctrl+J', category: 'Editor', description: 'Unfold All'),
    Keybinding(command: 'editor.action.fold', key: 'Ctrl+Shift+[', category: 'Editor', description: 'Fold'),
    Keybinding(command: 'editor.action.unfold', key: 'Ctrl+Shift+]', category: 'Editor', description: 'Unfold'),
    Keybinding(command: 'editor.action.revealDefinition', key: 'F12', category: 'Editor', description: 'Go to Definition'),
    Keybinding(command: 'editor.action.revealDefinitionAside', key: 'Ctrl+F12', category: 'Editor', description: 'Peek Definition'),
    Keybinding(command: 'editor.action.goToReferences', key: 'Shift+F12', category: 'Editor', description: 'Go to References'),
    Keybinding(command: 'editor.action.rename', key: 'F2', category: 'Editor', description: 'Rename Symbol'),
    Keybinding(command: 'editor.action.codeAction', key: 'Ctrl+.', category: 'Editor', description: 'Quick Fix'),
    Keybinding(command: 'editor.action.showHover', key: 'Ctrl+K Ctrl+I', category: 'Editor', description: 'Show Hover'),
    Keybinding(command: 'editor.action.wordHighlight.trigger', key: 'Ctrl+Shift+E', category: 'Editor', description: 'Toggle Occurrence Highlight'),

    // View
    Keybinding(command: 'workbench.action.zoomIn', key: 'Ctrl+=', category: 'View', description: 'Zoom In'),
    Keybinding(command: 'workbench.action.zoomOut', key: 'Ctrl+-', category: 'View', description: 'Zoom Out'),
    Keybinding(command: 'workbench.action.resetZoom', key: 'Ctrl+0', category: 'View', description: 'Reset Zoom'),
    Keybinding(command: 'workbench.action.toggleFullScreen', key: 'F11', category: 'View', description: 'Toggle Full Screen'),
    Keybinding(command: 'workbench.action.toggleMenuBar', key: 'Alt', category: 'View', description: 'Toggle Menu Bar'),
    Keybinding(command: 'workbench.action.splits.first', key: 'Ctrl+1', category: 'View', description: 'Focus First Editor Group'),
    Keybinding(command: 'workbench.action.splits.second', key: 'Ctrl+2', category: 'View', description: 'Focus Second Editor Group'),
    Keybinding(command: 'workbench.action.splitEditor', key: 'Ctrl+\\\\', category: 'View', description: 'Split Editor'),
    Keybinding(command: 'workbench.action.splitEditorVertical', key: 'Ctrl+K Ctrl+\\\\', category: 'View', description: 'Split Editor Vertical'),
    Keybinding(command: 'workbench.action.splitEditorHorizontal', key: 'Ctrl+K Ctrl+Shift+\\\\', category: 'View', description: 'Split Editor Horizontal'),
    Keybinding(command: 'workbench.action.editorLayoutThreeColumns', key: 'Ctrl+K Ctrl+3', category: 'View', description: 'Three Columns Layout'),

    // Git
    Keybinding(command: 'git.commit', key: 'Ctrl+Enter', category: 'Git', description: 'Commit', when: 'commitMessageVisible'),
    Keybinding(command: 'git.push', key: 'Ctrl+Shift+P', category: 'Git', description: 'Push', when: 'gitEnabled'),
    Keybinding(command: 'git.pull', key: 'Ctrl+Shift+P', category: 'Git', description: 'Pull', when: 'gitEnabled'),
    Keybinding(command: 'git.stage', key: 'Ctrl+K Ctrl+S', category: 'Git', description: 'Stage Changes'),
    Keybinding(command: 'git.unstage', key: 'Ctrl+K Ctrl+U', category: 'Git', description: 'Unstage Changes'),
    Keybinding(command: 'git.undoCommit', key: 'Ctrl+K Ctrl+Z', category: 'Git', description: 'Undo Last Commit'),

    // Debug
    Keybinding(command: 'debug.action.start', key: 'F5', category: 'Debug', description: 'Start/Continue'),
    Keybinding(command: 'debug.action.toggleBreakpoint', key: 'F9', category: 'Debug', description: 'Toggle Breakpoint'),
    Keybinding(command: 'debug.action.stepOver', key: 'F10', category: 'Debug', description: 'Step Over'),
    Keybinding(command: 'debug.action.stepInto', key: 'F11', category: 'Debug', description: 'Step Into'),
    Keybinding(command: 'debug.action.stepOut', key: 'Shift+F11', category: 'Debug', description: 'Step Out'),
    Keybinding(command: 'debug.action.restart', key: 'Ctrl+Shift+F5', category: 'Debug', description: 'Restart'),
    Keybinding(command: 'debug.action.stop', key: 'Shift+F5', category: 'Debug', description: 'Stop'),

    // Terminal
    Keybinding(command: 'workbench.action.terminal.new', key: 'Ctrl+Shift+`', category: 'Terminal', description: 'New Terminal'),
    Keybinding(command: 'workbench.action.terminal.kill', key: 'Ctrl+Shift+X', category: 'Terminal', description: 'Kill Terminal'),
    Keybinding(command: 'workbench.action.terminal.clear', key: 'Ctrl+K', category: 'Terminal', description: 'Clear Terminal', when: 'terminalFocus'),
    Keybinding(command: 'workbench.action.terminal.copySelection', key: 'Ctrl+Shift+C', category: 'Terminal', description: 'Copy Selection', when: 'terminalFocus'),
    Keybinding(command: 'workbench.action.terminal.paste', key: 'Ctrl+Shift+V', category: 'Terminal', description: 'Paste', when: 'terminalFocus'),

    // Extensions
    Keybinding(command: 'workbench.extensions.action.showExtensions', key: 'Ctrl+Shift+X', category: 'Extensions', description: 'Show Extensions'),
    Keybinding(command: 'extension.update', key: '', category: 'Extensions', description: 'Update Extension'),
    Keybinding(command: 'extension.uninstall', key: '', category: 'Extensions', description: 'Uninstall Extension'),
    Keybinding(command: 'extension.enable', key: '', category: 'Extensions', description: 'Enable Extension'),
    Keybinding(command: 'extension.disable', key: '', category: 'Extensions', description: 'Disable Extension'),

    // Workbench
    Keybinding(command: 'workbench.action.newWindow', key: 'Ctrl+Shift+N', category: 'Workbench', description: 'New Window'),
    Keybinding(command: 'workbench.action.closePanel', key: 'Escape', category: 'Workbench', description: 'Close Panel'),
    Keybinding(command: 'workbench.action.closeSidebar', key: 'Escape', category: 'Workbench', description: 'Close Sidebar'),
    Keybinding(command: 'workbench.action.closeActiveEditor', key: 'Ctrl+W', category: 'Workbench', description: 'Close Active Editor'),
    Keybinding(command: 'workbench.action.nextEditor', key: 'Ctrl+Tab', category: 'Workbench', description: 'Next Editor'),
    Keybinding(command: 'workbench.action.previousEditor', key: 'Ctrl+Shift+Tab', category: 'Workbench', description: 'Previous Editor'),
    Keybinding(command: 'workbench.action.openRecent', key: 'Ctrl+R', category: 'Workbench', description: 'Open Recent'),
    Keybinding(command: 'workbench.action.saveAll', key: 'Ctrl+K S', category: 'Workbench', description: 'Save All'),
    Keybinding(command: 'workbench.action.reopenClosedEditor', key: 'Ctrl+Shift+T', category: 'Workbench', description: 'Reopen Closed Editor'),
    Keybinding(command: 'workbench.action.toggleAuxiliaryBar', key: 'Ctrl+Shift+B', category: 'Workbench', description: 'Toggle Auxiliary Bar'),
  ];
}

/// Manages keybindings
class KeybindingsManager extends ChangeNotifier {
  final List<Keybinding> _bindings = [];
  final Map<String, String> _keyToCommand = {};
  final Map<String, List<String>> _commandToKeys = {};
  String? _selectedCategory;
  String _searchQuery = '';

  List<Keybinding> get bindings => _filteredBindings();
  String? get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;
  List<String> get categories => _getCategories();
  Map<String, List<String>> get conflicts => _getConflicts();

  KeybindingsManager() {
    _loadDefaults();
  }

  void _loadDefaults() {
    for (final binding in DefaultKeybindings.all) {
      _bindings.add(binding);
    }
    _buildIndex();
  }

  void _buildIndex() {
    _keyToCommand.clear();
    _commandToKeys.clear();

    for (final binding in _bindings) {
      _keyToCommand[binding.key] = binding.command;
      _commandToKeys.putIfAbsent(binding.command, () => []).add(binding.key);
    }
  }

  List<String> _getCategories() {
    final cats = <String>{};
    for (final b in _bindings) {
      cats.add(b.category);
    }
    final sorted = cats.toList()..sort();
    return ['All', ...sorted];
  }

  List<Keybinding> _filteredBindings() {
    return _bindings.where((b) {
      if (_selectedCategory != null && _selectedCategory != 'All' && b.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return b.command.toLowerCase().contains(q) ||
               b.key.toLowerCase().contains(q) ||
               b.description.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  List<String> getKeysForCommand(String command) {
    return _commandToKeys[command] ?? [];
  }

  String? getCommandForKey(String key) {
    return _keyToCommand[key];
  }

  void setCategory(String? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void addCustomBinding(String command, String key, {String? when, String category = 'Custom', String description = ''}) {
    // Check for conflicts
    final existingCommand = _keyToCommand[key];
    if (existingCommand != null && existingCommand != command) {
      // Remove old binding
      _bindings.removeWhere((b) => b.key == key && b.command == existingCommand);
    }

    final binding = Keybinding(
      command: command,
      key: key,
      when: when,
      category: category,
      description: description,
      isCustom: true,
    );
    _bindings.add(binding);
    _buildIndex();
    notifyListeners();
  }

  void removeBinding(String command, String key) {
    _bindings.removeWhere((b) => b.command == command && b.key == key);
    _buildIndex();
    notifyListeners();
  }

  void resetToDefaults() {
    _bindings.clear();
    _loadDefaults();
    notifyListeners();
  }

  void resetCommand(String command) {
    _bindings.removeWhere((b) => b.command == command);
    for (final defaultBinding in DefaultKeybindings.all) {
      if (defaultBinding.command == command) {
        _bindings.add(defaultBinding);
      }
    }
    _buildIndex();
    notifyListeners();
  }

  Map<String, List<String>> _getConflicts() {
    final conflicts = <String, List<String>>{};
    final keyGroups = <String, List<String>>{};

    for (final b in _bindings) {
      if (b.key.isEmpty) continue;
      keyGroups.putIfAbsent(b.key, () => []).add(b.command);
    }

    for (final entry in keyGroups.entries) {
      if (entry.value.length > 1) {
        conflicts[entry.key] = entry.value;
      }
    }
    return conflicts;
  }

  /// Export keybindings to JSON
  List<Map<String, dynamic>> exportToJson() {
    return _bindings.map((b) => b.toJson()).toList();
  }

  /// Import keybindings from JSON
  void importFromJson(List<Map<String, dynamic>> json) {
    _bindings.clear();
    for (final item in json) {
      _bindings.add(Keybinding.fromJson(item));
    }
    _buildIndex();
    notifyListeners();
  }

  /// Format key for display
  static String formatKey(String key) {
    if (key.isEmpty) return 'None';
    return key
        .replaceAll('Ctrl', '⌘')
        .replaceAll('Shift', '⇧')
        .replaceAll('Alt', '⌥')
        .replaceAll('+', ' ');
  }
}

/// Widget: Keybindings Page
class KeybindingsPage extends StatefulWidget {
  const KeybindingsPage({super.key});

  @override
  State<KeybindingsPage> createState() => _KeybindingsPageState();
}

class _KeybindingsPageState extends State<KeybindingsPage> {
  final KeybindingsManager _manager = KeybindingsManager();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _keyInputController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _keyInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181825),
        title: const Text('Keyboard Shortcuts', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white70),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.restore, color: Colors.white70),
            tooltip: 'Reset All',
            onPressed: () {
              setState(() => _manager.resetToDefaults());
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Keybindings reset to defaults')),
              );
            },
          ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'export', child: Text('Export')),
              const PopupMenuItem(value: 'import', child: Text('Import')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF181825),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => _manager.setSearchQuery(v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search keybindings...',
                hintStyle: TextStyle(color: Colors.white38),
                prefixIcon: Icon(Icons.search, color: Colors.white38),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: const Color(0xFF313244),
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),

          // Category chips
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _manager.categories.map((cat) {
                final isSelected = cat == (_manager.selectedCategory ?? 'All');
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat, style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 12,
                    )),
                    selected: isSelected,
                    selectedColor: const Color(0xFF89B4FA),
                    backgroundColor: const Color(0xFF313244),
                    onSelected: (_) => _manager.setCategory(cat),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                );
              }).toList(),
            ),
          ),

          // Conflicts warning
          if (_manager.conflicts.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFAB387).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Color(0xFFFAB387), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '${_manager.conflicts.length} key conflict(s) detected',
                    style: const TextStyle(color: Color(0xFFFAB387), fontSize: 12),
                  ),
                ],
              ),
            ),

          // Keybindings list
          Expanded(
            child: AnimatedBuilder(
              animation: _manager,
              builder: (ctx, _) {
                final bindings = _manager.bindings;
                if (bindings.isEmpty) {
                  return const Center(
                    child: Text('No keybindings found', style: TextStyle(color: Colors.white38)),
                  );
                }

                // Group by command
                final grouped = <String, List<Keybinding>>{};
                for (final b in bindings) {
                  grouped.putIfAbsent(b.command, () => []).add(b);
                }

                return ListView.builder(
                  itemCount: grouped.length,
                  padding: const EdgeInsets.only(bottom: 80),
                  itemBuilder: (ctx, i) {
                    final cmd = grouped.keys.elementAt(i);
                    final cmdBindings = grouped[cmd]!;
                    final first = cmdBindings.first;
                    final conflicts = _manager.conflicts;

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF313244),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        title: Text(
                          first.description.isNotEmpty ? first.description : cmd,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        subtitle: Row(
                          children: [
                            Text(
                              cmd,
                              style: TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                            if (first.when != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF585B70),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  first.when!,
                                  style: TextStyle(color: Colors.white54, fontSize: 10),
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: cmdBindings.map((b) {
                            final hasConflict = conflicts[b.key]?.isNotEmpty == true;
                            return GestureDetector(
                              onTap: () => _showEditDialog(b),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: hasConflict
                                      ? const Color(0xFFF38BA8).withValues(alpha: 0.2)
                                      : const Color(0xFF45475A),
                                  borderRadius: BorderRadius.circular(6),
                                  border: hasConflict
                                      ? Border.all(color: const Color(0xFFF38BA8), width: 1)
                                      : null,
                                ),
                                child: Text(
                                  KeybindingsManager.formatKey(b.key),
                                  style: TextStyle(
                                    color: hasConflict ? const Color(0xFFF38BA8) : const Color(0xFFCDD6F4),
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF89B4FA),
        onPressed: () => _showAddDialog(),
        child: const Icon(Icons.add, color: Color(0xFF1E1E2E)),
      ),
    );
  }

  void _showEditDialog(Keybinding binding) {
    _keyInputController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF313244),
        title: Text('Edit Keybinding', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(binding.description, style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(binding.command, style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 16),
            TextField(
              controller: _keyInputController,
              autofocus: true,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Press key combination...',
                hintStyle: TextStyle(color: Colors.white38),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                if (v.isNotEmpty) {
                  _manager.addCustomBinding(binding.command, v,
                    when: binding.when,
                    category: binding.category,
                    description: binding.description,
                  );
                }
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _manager.resetCommand(binding.command);
              Navigator.pop(ctx);
            },
            child: Text('Reset', style: TextStyle(color: Color(0xFFF38BA8))),
          ),
        ],
      ),
    );
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF313244),
        title: Text('Add Keybinding', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Command',
                labelStyle: TextStyle(color: Colors.white54),
                hintText: 'e.g. myextension.doSomething',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyInputController,
              autofocus: true,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Key',
                labelStyle: TextStyle(color: Colors.white54),
                hintText: 'e.g. Ctrl+Shift+X',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Add'),
          ),
        ],
      ),
    );
  }
}
