/// VS Code-style Workspace Picker (Quick Pick).
///
/// When the user clicks the workspace box in the top bar, this picker opens
/// with:
/// - "folders & workspaces" section (recent folders/projects)
/// - "files" section (recently opened files)
/// - Each entry has a × button to remove from recently opened
/// - Search/filter at the top
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

library;



/// A recently opened item (folder or file).
class RecentItem {
  final String path;
  final bool isFolder;
  final DateTime lastOpened;

  const RecentItem({
    required this.path,
    required this.isFolder,
    required this.lastOpened,
  });

  String get name => p.basename(path);
  String get parentDir => p.dirname(path);
}

/// Shows the VS Code-style workspace picker.
class WorkspacePicker extends StatefulWidget {
  final String? currentWorkspace;
  final List<RecentItem> recentFolders;
  final List<RecentItem> recentFiles;
  final void Function(String path) onOpen;
  final void Function(String path) onRemoveRecent;
  final VoidCallback onOpenFolder;
  final VoidCallback onOpenFile;

  const WorkspacePicker({
    super.key,
    this.currentWorkspace,
    this.recentFolders = const [],
    this.recentFiles = const [],
    required this.onOpen,
    required this.onRemoveRecent,
    required this.onOpenFolder,
    required this.onOpenFile,
  });

  static Future<void> show(
    BuildContext context, {
    String? currentWorkspace,
    List<RecentItem> recentFolders = const [],
    List<RecentItem> recentFiles = const [],
    required void Function(String path) onOpen,
    required void Function(String path) onRemoveRecent,
    required VoidCallback onOpenFolder,
    required VoidCallback onOpenFile,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WorkspacePicker(
        currentWorkspace: currentWorkspace,
        recentFolders: recentFolders,
        recentFiles: recentFiles,
        onOpen: onOpen,
        onRemoveRecent: onRemoveRecent,
        onOpenFolder: onOpenFolder,
        onOpenFile: onOpenFile,
      ),
    );
  }

  @override
  State<WorkspacePicker> createState() => _WorkspacePickerState();
}

class _WorkspacePickerState extends State<WorkspacePicker> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Filter items by search query
    final filteredFolders = _query.isEmpty
        ? widget.recentFolders
        : widget.recentFolders
            .where((f) => f.name.toLowerCase().contains(_query.toLowerCase()) ||
                f.path.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    final filteredFiles = _query.isEmpty
        ? widget.recentFiles
        : widget.recentFiles
            .where((f) => f.name.toLowerCase().contains(_query.toLowerCase()) ||
                f.path.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      builder: (ctx, controller) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF252526) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: 'Search files and folders...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontSize: 13,
                  ),
                  prefixIcon: Icon(Icons.search, size: 16, color: Colors.white38),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF3C3C3C) : const Color(0xFFF3F3F3),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Content
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  // Actions section
                  _buildSectionHeader('ACTIONS', isDark),
                  _buildActionTile(
                    icon: Icons.folder_open,
                    label: 'Open Folder...',
                    onTap: () {
                      Navigator.pop(context);
                      widget.onOpenFolder();
                    },
                    isDark: isDark,
                  ),
                  _buildActionTile(
                    icon: Icons.description,
                    label: 'Open File...',
                    onTap: () {
                      Navigator.pop(context);
                      widget.onOpenFile();
                    },
                    isDark: isDark,
                  ),

                  // Current workspace
                  if (widget.currentWorkspace != null) ...[
                    const SizedBox(height: 8),
                    _buildSectionHeader('CURRENT WORKSPACE', isDark),
                    _buildRecentItemTile(
                      item: RecentItem(
                        path: widget.currentWorkspace!,
                        isFolder: true,
                        lastOpened: DateTime.now(),
                      ),
                      isActive: true,
                      onRemove: null,
                      isDark: isDark,
                    ),
                  ],

                  // Recent folders
                  if (filteredFolders.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildSectionHeader('FOLDERS & WORKSPACES', isDark),
                    for (final folder in filteredFolders)
                      _buildRecentItemTile(
                        item: folder,
                        isActive: folder.path == widget.currentWorkspace,
                        onRemove: () => widget.onRemoveRecent(folder.path),
                        isDark: isDark,
                      ),
                  ],

                  // Recent files
                  if (filteredFiles.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildSectionHeader('FILES', isDark),
                    for (final file in filteredFiles)
                      _buildRecentItemTile(
                        item: file,
                        isActive: false,
                        onRemove: () => widget.onRemoveRecent(file.path),
                        isDark: isDark,
                      ),
                  ],

                  // Empty state
                  if (filteredFolders.isEmpty && filteredFiles.isEmpty && _query.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No results found',
                          style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white54 : Colors.black45,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(icon, size: 16, color: isDark ? Colors.white70 : Colors.black54),
      title: Text(label, style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
      onTap: onTap,
      hoverColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
    );
  }

  Widget _buildRecentItemTile({
    required RecentItem item,
    required bool isActive,
    required VoidCallback? onRemove,
    required bool isDark,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(
        item.isFolder ? Icons.folder_outlined : Icons.description,
        size: 16,
        color: isActive
            ? const Color(0xFF007ACC)
            : (isDark ? Colors.white70 : Colors.black54),
      ),
      title: Text(
        item.name,
        style: TextStyle(
          fontSize: 13,
          color: isActive
              ? const Color(0xFF007ACC)
              : (isDark ? Colors.white : Colors.black87),
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        item.parentDir,
        style: TextStyle(
          fontSize: 11,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onRemove != null
          ? GestureDetector(
              onTap: onRemove,
              child: Icon(
                Icons.close,
                size: 14,
                color: isDark ? Colors.white38 : Colors.black26,
              ),
            )
          : null,
      onTap: () {
        Navigator.pop(context);
        widget.onOpen(item.path);
      },
      hoverColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
    );
  }
}
