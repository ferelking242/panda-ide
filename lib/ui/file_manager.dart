/// Panda IDE File Manager — redesigned.
///
/// Features:
///   - Access to both public (/storage/emulated/0/Panda IDE/) and private app data
///   - Breadcrumbs with friendly names
///   - Search/filter
///   - Grid + List view toggle
///   - Rename, copy, paste, delete, share
///   - File size + date display
///   - Quick access sidebar
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../bloc/ui_bloc/ui_bloc.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/languages.dart';
import '../utils/themes.dart';
import 'editor_page.dart';

// ═══════════════════════════════════════════════════════════════
// Quick Access Locations
// ═══════════════════════════════════════════════════════════════

class _QuickLocation {
  final String label;
  final String path;
  final IconData icon;
  final Color color;

  const _QuickLocation({
    required this.label,
    required this.path,
    required this.icon,
    required this.color,
  });
}

List<_QuickLocation> _quickLocations() => [
      _QuickLocation(
        label: 'Projects',
        path: projectDir,
        icon: Icons.workspaces_rounded,
        color: const Color(0xFF4CAF50),
      ),
      _QuickLocation(
        label: 'Files',
        path: filesDir,
        icon: Icons.description_rounded,
        color: const Color(0xFF2196F3),
      ),
      _QuickLocation(
        label: 'Templates',
        path: templateDir,
        icon: Icons.dashboard_customize_rounded,
        color: const Color(0xFF9C27B0),
      ),
      _QuickLocation(
        label: 'Logs',
        path: pandaLogsDir,
        icon: Icons.bug_report_rounded,
        color: const Color(0xFFFF9800),
      ),
      _QuickLocation(
        label: 'Extensions',
        path: extensionDir,
        icon: Icons.extension_rounded,
        color: const Color(0xFFE91E63),
      ),
      _QuickLocation(
        label: 'Gateway',
        path: '$appDir/runtimes',
        icon: Icons.dns_rounded,
        color: const Color(0xFF00BCD4),
      ),
      _QuickLocation(
        label: 'App Data',
        path: appDir,
        icon: Icons.storage_rounded,
        color: const Color(0xFF607D8B),
      ),
      _QuickLocation(
        label: 'Public Storage',
        path: publicPandaRootDir,
        icon: Icons.folder_special_rounded,
        color: const Color(0xFFFF5722),
      ),
    ];

// ═══════════════════════════════════════════════════════════════
// FileManagerPage
// ═══════════════════════════════════════════════════════════════

class FileManagerPage extends StatefulWidget {
  final String rootPath;

  const FileManagerPage({
    super.key,
    String? rootPath,
  }) : rootPath = rootPath ?? projectDir;

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  late Directory _currentDir;
  bool _loading = true;
  List<FileSystemEntity> _entries = [];
  List<FileSystemEntity> _filteredEntries = [];
  bool _isGridView = false;
  final _searchCtrl = TextEditingController();
  String _sortBy = 'name'; // name, size, date, type
  bool _sortAsc = true;

  // Clipboard for copy/cut
  final List<FileSystemEntity> _clipboard = [];
  bool _cutMode = false;

  @override
  void initState() {
    super.initState();
    _currentDir = Directory(widget.rootPath);
    _initialize();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _ensureBaseDirs();
    await _loadEntries();
  }

  Future<void> _ensureBaseDirs() async {
    for (final dir in [projectDir, templateDir, filesDir, pandaLogsDir]) {
      await Directory(dir).create(recursive: true);
    }
    if (!mounted) return;
  }

  Future<void> _loadEntries() async {
    if (!await _currentDir.exists()) {
      await _currentDir.create(recursive: true);
    }

    final items = await _currentDir
        .list(followLinks: false)
        .where((entity) {
          final name = p.basename(entity.path);
          return !name.startsWith('.panda_') && !name.startsWith('.');
        })
        .toList();

    _sortEntries(items);

    if (!mounted) return;
    setState(() {
      _entries = items;
      _filteredEntries = items;
      _loading = false;
    });
  }

  void _sortEntries(List<FileSystemEntity> entries) {
    entries.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir != bIsDir) return aIsDir ? -1 : 1;

      int cmp;
      switch (_sortBy) {
        case 'size':
          final aSize = a is File ? a.lengthSync() : 0;
          final bSize = b is File ? b.lengthSync() : 0;
          cmp = aSize.compareTo(bSize);
          break;
        case 'date':
          cmp = a.statSync().modified.compareTo(b.statSync().modified);
          break;
        case 'type':
          cmp = p.extension(a.path).compareTo(p.extension(b.path));
          break;
        default:
          cmp = p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      }
      return _sortAsc ? cmp : -cmp;
    });
  }

  void _filterEntries(String query) {
    if (query.isEmpty) {
      _filteredEntries = _entries;
    } else {
      final q = query.toLowerCase();
      _filteredEntries = _entries.where((e) {
        return p.basename(e.path).toLowerCase().contains(q);
      }).toList();
    }
    setState(() {});
  }

  bool _isAtRoot() => p.equals(_currentDir.path, widget.rootPath);

  // ── Navigation ────────────────────────────────────────────────────────

  void _navigateTo(String path) {
    setState(() {
      _currentDir = Directory(path);
      _loading = true;
      _searchCtrl.clear();
    });
    _loadEntries();
  }

  void _goUp() {
    if (!_isAtRoot()) {
      _navigateTo(_currentDir.parent.path);
    }
  }

  // ── File Operations ───────────────────────────────────────────────────

  Future<void> _createFile() async {
    final name = await _promptForName(title: 'New File');
    if (name == null || name.isEmpty) return;
    final file = File(p.join(_currentDir.path, name));
    await file.create();
    await _loadEntries();
    _showSnack('Created $name');
  }

  Future<void> _createFolder() async {
    final name = await _promptForName(title: 'New Folder');
    if (name == null || name.isEmpty) return;
    final dir = Directory(p.join(_currentDir.path, name));
    await dir.create();
    await _loadEntries();
    _showSnack('Created $name');
  }

  Future<void> _renameEntity(FileSystemEntity entity) async {
    final oldName = p.basename(entity.path);
    final newName = await _promptForName(title: 'Rename', initial: oldName);
    if (newName == null || newName.isEmpty || newName == oldName) return;
    final newPath = p.join(p.dirname(entity.path), newName);
    await entity.rename(newPath);
    await _loadEntries();
    _showSnack('Renamed to $newName');
  }

  Future<void> _deleteEntity(FileSystemEntity entity) async {
    final name = p.basename(entity.path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Delete "$name" permanently?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      if (entity is Directory) {
        await entity.delete(recursive: true);
      } else {
        await entity.delete();
      }
      await _loadEntries();
      _showSnack('Deleted $name');
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  void _copyEntity(FileSystemEntity entity) {
    _clipboard.clear();
    _clipboard.add(entity);
    _cutMode = false;
    _showSnack('Copied ${p.basename(entity.path)}');
  }

  void _cutEntity(FileSystemEntity entity) {
    _clipboard.clear();
    _clipboard.add(entity);
    _cutMode = true;
    _showSnack('Cut ${p.basename(entity.path)}');
  }

  Future<void> _pasteEntities() async {
    if (_clipboard.isEmpty) return;
    for (final entity in _clipboard) {
      final name = p.basename(entity.path);
      final destPath = p.join(_currentDir.path, name);

      try {
        if (_cutMode) {
          await entity.rename(destPath);
        } else {
          if (entity is File) {
            await entity.copy(destPath);
          } else if (entity is Directory) {
            await _copyDirectory(entity, Directory(destPath));
          }
        }
      } catch (e) {
        _showSnack('Error pasting $name: $e', isError: true);
      }
    }

    if (_cutMode) _clipboard.clear();
    _cutMode = false;
    await _loadEntries();
    _showSnack('Pasted ${_clipboard.length} item(s)');
  }

  Future<void> _copyDirectory(Directory source, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = p.basename(entity.path);
      final destPath = p.join(dest.path, name);
      if (entity is File) {
        await entity.copy(destPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      }
    }
  }

  Future<void> _exportToStorage(FileSystemEntity entity) async {
    try {
      final name = p.basename(entity.path);
      final destPath = p.join(publicPandaRootDir, name);

      if (entity is File) {
        await entity.copy(destPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      }

      await _loadEntries();
      _showSnack('Exported to $destPath');
    } catch (e) {
      _showSnack('Export failed: $e', isError: true);
    }
  }

  // ── UI Helpers ────────────────────────────────────────────────────────

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<String?> _promptForName({required String title, String? initial}) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: initial ?? '');
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Name'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
          ],
        );
      },
    );
  }

  String _formatSize(FileSystemEntity entity) {
    if (entity is File) {
      final bytes = entity.lengthSync();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today ${DateFormat.Hm().format(dt)}';
    }
    return DateFormat('MMM d, yyyy').format(dt);
  }

  IconData _fileIcon(String name) {
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.dart':
        return Icons.code;
      case '.py':
        return Icons.code;
      case '.js':
      case '.ts':
        return Icons.javascript;
      case '.json':
        return Icons.data_object;
      case '.yaml':
      case '.yml':
        return Icons.settings;
      case '.md':
        return Icons.description;
      case '.txt':
        return Icons.text_snippet;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.svg':
        return Icons.image;
      case '.zip':
      case '.tar':
      case '.gz':
        return Icons.archive;
      case '.apk':
        return Icons.android;
      case '.so':
        return Icons.memory;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _fileColor(String name) {
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.dart':
        return const Color(0xFF00B4D8);
      case '.py':
        return const Color(0xFFFFD43B);
      case '.js':
      case '.ts':
        return const Color(0xFFF7DF1E);
      case '.json':
        return const Color(0xFF8BC34A);
      case '.yaml':
      case '.yml':
        return const Color(0xFFCB171E);
      case '.md':
        return const Color(0xFF42A5F5);
      case '.png':
      case '.jpg':
      case '.jpeg':
        return const Color(0xFFAB47BC);
      case '.zip':
        return const Color(0xFFFF7043);
      case '.apk':
        return const Color(0xFF3DDC84);
      default:
        return const Color(0xFF78909C);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<AppThemeBloc>().state.appTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: appTheme.isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
      body: Row(
        children: [
          // ── Sidebar ──
          _buildSidebar(appTheme, cs),
          // ── Main content ──
          Expanded(
            child: Column(
              children: [
                _buildToolbar(appTheme, cs),
                _buildBreadcrumbs(appTheme),
                Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
                Expanded(child: _buildFileList(appTheme, cs)),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fileManagerFab',
        onPressed: () => _showCreateMenu(context, appTheme),
        child: const Icon(Icons.add),
      ),
    );
  }

  // ── Sidebar ───────────────────────────────────────────────────────────

  Widget _buildSidebar(AppTheme appTheme, ColorScheme cs) {
    final locations = _quickLocations();
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: appTheme.isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.folder_copy_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Explorer',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
          // Quick locations
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: locations.length,
              itemBuilder: (ctx, i) {
                final loc = locations[i];
                final isCurrent = p.equals(_currentDir.path, loc.path);
                return ListTile(
                  dense: true,
                  leading: Icon(loc.icon, size: 18, color: loc.color),
                  title: Text(
                    loc.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isCurrent ? cs.primary : cs.onSurface,
                    ),
                  ),
                  selected: isCurrent,
                  selectedTileColor: cs.primary.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  onTap: () => _navigateTo(loc.path),
                );
              },
            ),
          ),
          // Clipboard indicator
          if (_clipboard.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
              ),
              child: Row(
                children: [
                  Icon(_cutMode ? Icons.content_cut : Icons.copy, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_clipboard.length} item(s) ${_cutMode ? "cut" : "copied"}',
                      style: TextStyle(fontSize: 12, color: cs.primary),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.paste, size: 16),
                    onPressed: _pasteEntities,
                    tooltip: 'Paste here',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Toolbar ───────────────────────────────────────────────────────────

  Widget _buildToolbar(AppTheme appTheme, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: appTheme.isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          // Search
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: _filterEntries,
              style: TextStyle(fontSize: 13, color: cs.onSurface),
              decoration: InputDecoration(
                hintText: 'Search files...',
                hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                prefixIcon: Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          _filterEntries('');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                filled: true,
                fillColor: appTheme.isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Sort
          PopupMenuButton<String>(
            icon: Icon(Icons.sort, size: 18, color: cs.onSurfaceVariant),
            tooltip: 'Sort',
            onSelected: (v) {
              if (v == _sortBy) {
                _sortAsc = !_sortAsc;
              } else {
                _sortBy = v;
                _sortAsc = true;
              }
              _sortEntries(_entries);
              _filterEntries(_searchCtrl.text);
            },
            itemBuilder: (_) => [
              _sortMenuItem('name', 'Name'),
              _sortMenuItem('size', 'Size'),
              _sortMenuItem('date', 'Date'),
              _sortMenuItem('type', 'Type'),
            ],
          ),
          // View toggle
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view, size: 18),
            tooltip: _isGridView ? 'List view' : 'Grid view',
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          // New file/folder
          IconButton(
            icon: const Icon(Icons.note_add_outlined, size: 18),
            tooltip: 'New file',
            onPressed: _createFile,
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            tooltip: 'New folder',
            onPressed: _createFolder,
          ),
        ],
      ),
    );
  }

  Widget _sortMenuItem(String value, String label) {
    final isSelected = _sortBy == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Text(label),
          if (isSelected) ...[
            const Spacer(),
            Icon(
              _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
            ),
          ],
        ],
      ),
    );
  }

  // ── Breadcrumbs ───────────────────────────────────────────────────────

  Widget _buildBreadcrumbs(AppTheme appTheme) {
    final root = widget.rootPath;
    final current = _currentDir.path;

    // Friendly names for known dirs
    final friendlyNames = <String, String>{
      appDir: 'App Data',
      projectDir: 'Projects',
      filesDir: 'Files',
      templateDir: 'Templates',
      pandaLogsDir: 'Logs',
      extensionDir: 'Extensions',
      publicPandaRootDir: 'Public',
      homeDir: 'Home',
    };

    final segments = <String>[];
    var dir = _currentDir;
    while (!p.equals(dir.path, p.dirname(root)) && dir.path.isNotEmpty) {
      segments.insert(0, dir.path);
      dir = dir.parent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_right, size: 14, color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.5)),
                ),
              InkWell(
                onTap: () => _navigateTo(segments[i]),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    friendlyNames[segments[i]] ?? p.basename(segments[i]),
                    style: TextStyle(
                      color: i == segments.length - 1
                          ? appTheme.selectScreenCardTextColor
                          : appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
                      fontWeight: i == segments.length - 1 ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── File List ─────────────────────────────────────────────────────────

  Widget _buildFileList(AppTheme appTheme, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              _searchCtrl.text.isNotEmpty ? 'No matching files' : 'This folder is empty',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
            if (_searchCtrl.text.isEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _createFolder,
                icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                label: const Text('Create folder'),
              ),
            ],
          ],
        ),
      );
    }

    if (_isGridView) {
      return _buildGridView(appTheme, cs);
    }
    return _buildListView(appTheme, cs);
  }

  Widget _buildListView(AppTheme appTheme, ColorScheme cs) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _filteredEntries.length,
      itemBuilder: (ctx, i) => _buildListItem(_filteredEntries[i], appTheme, cs),
    );
  }

  Widget _buildListItem(FileSystemEntity entity, AppTheme appTheme, ColorScheme cs) {
    final isDir = entity is Directory;
    final name = p.basename(entity.path);
    final stat = entity.statSync();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openEntity(entity),
        onLongPress: () => _showContextMenu(entity),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (isDir ? const Color(0xFF4CAF50) : _fileColor(name)).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isDir ? Icons.folder_rounded : _fileIcon(name),
                  size: 20,
                  color: isDir ? const Color(0xFF4CAF50) : _fileColor(name),
                ),
              ),
              const SizedBox(width: 12),
              // Name + path
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!isDir)
                      Text(
                        '${_formatSize(entity)} • ${_formatDate(stat.modified)}',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              // Menu
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 16, color: cs.onSurfaceVariant),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onSelected: (v) => _handleMenuAction(v, entity),
                itemBuilder: (_) => _buildMenuItems(entity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridView(AppTheme appTheme, ColorScheme cs) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: _filteredEntries.length,
      itemBuilder: (ctx, i) => _buildGridItem(_filteredEntries[i], appTheme, cs),
    );
  }

  Widget _buildGridItem(FileSystemEntity entity, AppTheme appTheme, ColorScheme cs) {
    final isDir = entity is Directory;
    final name = p.basename(entity.path);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openEntity(entity),
      onLongPress: () => _showContextMenu(entity),
      child: Container(
        decoration: BoxDecoration(
          color: appTheme.isDark ? const Color(0xFF2A2A2A) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isDir ? Icons.folder_rounded : _fileIcon(name),
              size: 32,
              color: isDir ? const Color(0xFF4CAF50) : _fileColor(name),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  // ── Context Menu ──────────────────────────────────────────────────────

  void _showContextMenu(FileSystemEntity entity) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open'),
              onTap: () { Navigator.pop(ctx); _openEntity(entity); },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () { Navigator.pop(ctx); _renameEntity(entity); },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () { Navigator.pop(ctx); _copyEntity(entity); },
            ),
            ListTile(
              leading: const Icon(Icons.content_cut),
              title: const Text('Cut'),
              onTap: () { Navigator.pop(ctx); _cutEntity(entity); },
            ),
            ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('Export to Public'),
              onTap: () { Navigator.pop(ctx); _exportToStorage(entity); },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(ctx); _deleteEntity(entity); },
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(FileSystemEntity entity) {
    return [
      const PopupMenuItem(value: 'open', child: Text('Open')),
      const PopupMenuItem(value: 'rename', child: Text('Rename')),
      const PopupMenuItem(value: 'copy', child: Text('Copy')),
      const PopupMenuItem(value: 'cut', child: Text('Cut')),
      const PopupMenuItem(value: 'export', child: Text('Export')),
      const PopupMenuItem(
        value: 'delete',
        child: Text('Delete', style: TextStyle(color: Colors.red)),
      ),
    ];
  }

  void _handleMenuAction(String action, FileSystemEntity entity) {
    switch (action) {
      case 'open':
        _openEntity(entity);
        break;
      case 'rename':
        _renameEntity(entity);
        break;
      case 'copy':
        _copyEntity(entity);
        break;
      case 'cut':
        _cutEntity(entity);
        break;
      case 'export':
        _exportToStorage(entity);
        break;
      case 'delete':
        _deleteEntity(entity);
        break;
    }
  }

  // ── Open Entity ───────────────────────────────────────────────────────

  void _openEntity(FileSystemEntity entity) {
    if (entity is Directory) {
      _navigateTo(entity.path);
    } else if (entity is File) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EditorPage(filePath: entity.path),
        ),
      );
    }
  }

  // ── Create Menu ───────────────────────────────────────────────────────

  void _showCreateMenu(BuildContext context, AppTheme appTheme) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('New File'),
              onTap: () { Navigator.pop(ctx); _createFile(); },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New Folder'),
              onTap: () { Navigator.pop(ctx); _createFolder(); },
            ),
          ],
        ),
      ),
    );
  }
}
