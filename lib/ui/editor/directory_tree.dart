import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:code_forge/code_forge.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_json/flutter_json.dart';
import 'package:flutter_svg/svg.dart';
import 'package:http/http.dart' as http;
import '../utils/llama_wrapper.dart';
import 'package:markdown_widget/config/configs.dart';
import 'package:markdown_widget/widget/all.dart';
import 'package:path/path.dart' as path;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:re_highlight/re_highlight.dart' show Mode;
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:panda/utils/agentic_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bloc/repo_bloc/repo_bloc.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../terminal/terminal.dart';
import '../utils/ai.dart';
import '../utils/copilot_chat.dart';
import '../utils/functions.dart';
import '../utils/languages.dart';
import '../utils/themes.dart';
import '../utils/constants.dart';

// File tree viewer
// Extracted from widgets.dart

class DirectoryTreeViewerCustom extends StatefulWidget {
  final String rootPath;
  final bool isUnfoldedFirst;
  final bool enableCreateFolderOption;
  final bool enableCreateFileOption;
  final bool enableDeleteFolderOption;
  final bool enableDeleteFileOption;
  final bool enableRenameFolderOption;
  final bool enableRenameFileOption;
  final bool enableGitFeatures;
  final FolderStyle? folderStyle;
  final FileStyle? fileStyle;
  final EditingFieldStyle? editingFieldStyle;
  final void Function(File)? onFileTap;
  final List<Widget>? folderActions;
  final List<Widget>? fileActions;
  final Widget Function(String fileExtension)? fileIconBuilder;
  final AppTheme appTheme;
  final ActiveEditorState? activeEditorState;

  const DirectoryTreeViewerCustom({
    super.key,
    required this.rootPath,
    required this.appTheme,
    this.onFileTap,
    this.folderActions,
    this.fileActions,
    this.folderStyle,
    this.fileStyle,
    this.isUnfoldedFirst = true,
    this.editingFieldStyle,
    this.enableCreateFileOption = false,
    this.enableCreateFolderOption = false,
    this.enableDeleteFileOption = false,
    this.enableDeleteFolderOption = false,
    this.enableRenameFolderOption = false,
    this.enableRenameFileOption = false,
    this.enableGitFeatures = false,
    this.fileIconBuilder,
    this.activeEditorState,
  });

  @override
  State<DirectoryTreeViewerCustom> createState() => _DirectoryTreeViewerState();
}

class _DirectoryTreeViewerState extends State<DirectoryTreeViewerCustom> {
  static const double _guideIndentWidth = 14;
  static const double _guideRowHeight = 30;

  String? newEntryPath;
  String? renamingPath;
  bool isFolderCreation = false;
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _renameController = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _renameController.dispose();
    super.dispose();
  }

  (Color, String?) _getFileColor(File file, RepoStatusState repoState, String? highlightedPath) {
    final isHighlighted = highlightedPath != null && path.normalize(file.path) == path.normalize(highlightedPath);
    final defaultColor = !isHighlighted
      ? widget.appTheme.selectScreenCardTextColor
      : widget.appTheme.isDark ? Colors.blue[200]! : Colors.blue[600]!;
    if (repoState is! RepoStatusLoaded) return (defaultColor, null);
    final relativePath = path.relative(file.path, from: widget.rootPath);
    for (final line in repoState.staged) {
      final fileName = _extractGitFilename(line);
      if (fileName == relativePath) {
        final status = line.substring(0, 2).trim();
        final indicator = gitFileStatus[status];
        return (indicator?.$2 ?? defaultColor, indicator?.$1);
      }
    }
    for (final line in repoState.unstaged) {
      final fileName = _extractGitFilename(line);
      if (fileName == relativePath) {
        final status = line.substring(0, 2).trim();
        final indicator = gitFileStatus[status];
        return (indicator?.$2 ?? defaultColor, indicator?.$1);
      }
    }
    return (defaultColor, null);
  }

  bool isUnfolded(String dirPath) => context.read<FolderBloc>().state.folderStates[dirPath] ?? false;
  void toggleFolder(String dirPath) => context.read<FolderBloc>().toggleFolder(dirPath);

  bool _isPathWithinRoot(String entityPath) {
    final normalizedRoot = path.normalize(widget.rootPath);
    final normalizedEntity = path.normalize(entityPath);
    return normalizedEntity == normalizedRoot || normalizedEntity.startsWith('$normalizedRoot${path.separator}');
  }

  String? _activeFilePath() {
    final editorState = widget.activeEditorState;
    final editors = editorState?.activeEditors;
    if (editors == null || editors.isEmpty) return null;

    final activeIndex = editors.indexWhere((editor) => editor.isActive);
    final activeEditor = activeIndex >= 0 ? editors[activeIndex] : editors.first;
    return activeEditor.file.path;
  }

  bool _isPathOnHighlightPath(String candidatePath, String? highlightPath) {
    if (highlightPath == null) return false;
    final normalizedCandidate = path.normalize(candidatePath);
    final normalizedHighlight = path.normalize(highlightPath);
    if (normalizedCandidate == normalizedHighlight) return true;
    return normalizedHighlight.startsWith('$normalizedCandidate${path.separator}');
  }

  String? _resolveHighlightPath(FolderState folderState) {
    final activeFilePath = _activeFilePath();
    if (activeFilePath != null && _isPathWithinRoot(activeFilePath)) {
      return path.normalize(activeFilePath);
    }

    final lastUnfoldedFolderPath = folderState.lastUnfoldedFolderPath;
    if (lastUnfoldedFolderPath == null) return null;
    if (!_isPathWithinRoot(lastUnfoldedFolderPath)) return null;
    return path.normalize(lastUnfoldedFolderPath);
  }

  void startCreating(String parentPath, bool isFolder) {
    setState(() {
      newEntryPath = parentPath;
      isFolderCreation = isFolder;
      _controller.clear();
      renamingPath = null;
    });
    if (!isUnfolded(parentPath)) {
      toggleFolder(parentPath);
    }
  }

  void stopCreating() {
    setState(() {
      newEntryPath = null;
    });
  }

  void startRenaming(String entityPath) {
    setState(() {
      renamingPath = entityPath;
      _renameController.text = path.basename(entityPath);
      newEntryPath = null;
    });
  }

  void stopRenaming() {
    setState(() {
      renamingPath = null;
      _renameController.clear();
    });
  }

  Future<void> createEntry(Directory parent) async {
    final value = _controller.text.trim();
    if (value.isNotEmpty) {
      final newPath = path.join(parent.path, value);
      try {
        if (isFolderCreation) {
          await Directory(newPath).create(recursive: true);
        } else {
          await File(newPath).create(recursive: true);
        }
      } catch (e) {
        debugPrint('createEntry error: $e');
      }
    }
    stopCreating();
    try {
      context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.rootPath));
    } catch (_) {}
  }

  Future<void> renameEntry(String oldPath, bool isFolder) async {
    final value = _renameController.text.trim();
    if (value.isNotEmpty && value != path.basename(oldPath)) {
      final parentDir = path.dirname(oldPath);
      final newPath = path.join(parentDir, value);
      try {
        if (isFolder) {
          await Directory(oldPath).rename(newPath);
        } else {
          await File(oldPath).rename(newPath);
        }
      } catch (e) {
        debugPrint('renameEntry error: $e');
      }
    }
    stopRenaming();
    try {
      context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.rootPath));
    } catch (_) {}
  }

  void _showFolderContextMenu(
    BuildContext context,
    Directory directory,
    Offset tapPosition,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final isRootDirectory = directory.path == widget.rootPath;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (widget.enableCreateFileOption)
          PopupMenuItem(
            child: Row(
              children: [
                widget.folderStyle?.iconForCreateFile ?? FolderStyle().iconForCreateFile,
                const SizedBox(width: 15),
                Text(
                  'New File',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () => Future.delayed(
              Duration.zero,
              () => startCreating(directory.path, false),
            ),
          ),
        if (widget.enableCreateFolderOption)
          PopupMenuItem(
            child: Row(
              children: [
                widget.folderStyle?.iconForCreateFolder ??
                    FolderStyle().iconForCreateFolder,
                const SizedBox(width: 11),
                Text(
                  'New Folder',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () => Future.delayed(
              Duration.zero,
              () => startCreating(directory.path, true),
            ),
          ),
        if (widget.enableRenameFolderOption && !isRootDirectory)
          PopupMenuItem(
            child: Row(
              children: [
                Icon(
                  Icons.edit,
                  size: 25,
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Rename Folder',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () => Future.delayed(
              Duration.zero,
              () => startRenaming(directory.path),
            ),
          ),
        if (isRootDirectory)
          PopupMenuItem(
            child: Row(
              children: [
                Icon(
                  Icons.refresh,
                  size: 25,
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Refresh Explorer',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () => Future.delayed(Duration.zero, () {
              if (context.mounted) {
                try {
                  context.read<RepoStatusBloc>().add(
                    LoadRepoStatus(widget.rootPath),
                  );
                } catch (_) {}
              }
            }),
          ),
        if (isRootDirectory)
          PopupMenuItem(
            child: Row(
              children: [
                Icon(
                  Icons.unfold_more,
                  size: 25,
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Expand All',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () =>
                Future.delayed(Duration.zero, () => _expandAllFolders()),
          ),
        if (isRootDirectory)
          PopupMenuItem(
            child: Row(
              children: [
                Icon(
                  Icons.unfold_less,
                  size: 25,
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Collapse All',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () =>
                Future.delayed(Duration.zero, () => _collapseAllFolders()),
          ),
        if (widget.enableDeleteFolderOption && !isRootDirectory)
          PopupMenuItem(
            child: Row(
              children: [
                Icon(Icons.delete, size: 25, color: Colors.red[300]),
                const SizedBox(width: 8),
                Text(
                  'Delete Folder',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () => _showDeleteFolderConfirmation(context, directory),
          ),
      ],
    );
  }

  void _showFileContextMenu(
    BuildContext context,
    File file,
    Offset tapPosition,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final tc = widget.appTheme.selectScreenCardTextColor;

    Widget _item(IconData icon, String label, {Color? color, bool enabled = true}) {
      final c = color ?? tc;
      return Row(children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13, color: c)),
      ]);
    }

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<dynamic>>[
        // ── New ──
        if (widget.enableCreateFileOption)
          PopupMenuItem<dynamic>(child: _item(Icons.add_circle_outline, 'New File...'),
            onTap: () => Future.delayed(Duration.zero, () => startCreating(path.dirname(file.path), false))),
        if (widget.enableCreateFolderOption)
          PopupMenuItem<dynamic>(child: _item(Icons.create_new_folder_outlined, 'New Folder...'),
            onTap: () => Future.delayed(Duration.zero, () => startCreating(path.dirname(file.path), true))),
        const PopupMenuDivider(),
        // ── Copy paths ──
        PopupMenuItem<dynamic>(child: _item(Icons.content_copy, 'Copy Path'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: file.path));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Path copied'), duration: Duration(seconds: 1)));
          }),
        PopupMenuItem<dynamic>(child: _item(Icons.copy_outlined, 'Copy Relative Path'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: path.relative(file.path, from: widget.rootPath)));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Relative path copied'), duration: Duration(seconds: 1)));
          }),
        const PopupMenuDivider(),
        // ── Cut / Copy ──
        PopupMenuItem<dynamic>(child: _item(Icons.content_cut, 'Cut'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: 'cut:\${file.path}'));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Cut \${path.basename(file.path)}'), duration: const Duration(seconds: 1)));
          }),
        PopupMenuItem<dynamic>(child: _item(Icons.copy, 'Copy'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: 'copy:\${file.path}'));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Copied \${path.basename(file.path)}'), duration: const Duration(seconds: 1)));
          }),
        const PopupMenuDivider(),
        // ── Open in terminal ──
        PopupMenuItem<dynamic>(child: _item(Icons.terminal, 'Open in Terminal'), enabled: false),
        const PopupMenuDivider(),
        // ── Modify ──
        if (widget.enableRenameFileOption)
          PopupMenuItem<dynamic>(child: _item(Icons.edit, 'Rename (F2)'),
            onTap: () => Future.delayed(Duration.zero, () => startRenaming(file.path))),
        if (widget.enableDeleteFileOption)
          PopupMenuItem<dynamic>(child: _item(Icons.delete_outline, 'Delete (Del)', color: Colors.red[300]),
            onTap: () => _showDeleteFileConfirmation(context, file)),
      ],
    );
  }


  /// Helper for consistent context menu item styling.
  Widget _ctxItem(IconData icon, String label, {Color? color}) {
    final tc = widget.appTheme.selectScreenCardTextColor;
    final c = color ?? tc;
    return Row(children: [
      Icon(icon, size: 18, color: c),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontSize: 13, color: c)),
    ]);
  }

  Widget _buildDirectoryTree(
    Directory directory,
    RepoStatusState repoState,
    FolderState folderState,
  ) {
    final highlightedPath = _resolveHighlightPath(folderState);
    return _buildDirectoryTreeNode(
      directory,
      repoState,
      ancestorHasNext: const [],
      ancestorPaths: const [],
      highlightedPath: highlightedPath,
      isRoot: true,
      isLast: true,
    );
  }

  Widget _buildDirectoryTreeNode(
    Directory directory,
    RepoStatusState repoState, {
    required List<bool> ancestorHasNext,
    required List<String> ancestorPaths,
    required String? highlightedPath,
    required bool isRoot,
    required bool isLast,
  }) {
    final entries = directory.listSync();
    entries.sort((a, b) {
      if (a is Directory && b is File) return -1;
      if (a is File && b is Directory) return 1;
      return a.path.compareTo(b.path);
    });

    final ownPrefix = isRoot ? const SizedBox.shrink()
    : _buildTreePrefix(
        ancestorHasNext: ancestorHasNext,
        ancestorPaths: ancestorPaths,
        currentPath: directory.path,
        highlightedPath: highlightedPath,
        isLast: isLast,
      );

  final childAncestorHasNext = [...ancestorHasNext, !isLast];
  final childAncestorPaths = [...ancestorPaths, directory.path];
  final isHighlighted = highlightedPath != null && path.normalize(directory.path) == path.normalize(highlightedPath);
  final folderNameBaseStyle = widget.folderStyle?.folderNameStyle ?? FolderStyle().folderNameStyle ?? const TextStyle();
  final folderNameStyle = folderNameBaseStyle.copyWith(
    color: isHighlighted
      ? widget.appTheme.isDark ? Colors.white : Colors.black
      : (folderNameBaseStyle.color ?? widget.appTheme.selectScreenCardTextColor),
  );

    if (renamingPath == directory.path) {
      return _buildRenameField(directory.path, true, prefix: ownPrefix);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => toggleFolder(directory.path),
          onLongPressStart: (details) => _showFolderContextMenu(
            context,
            directory,
            details.globalPosition,
          ),
          child: Container(
            height: _guideRowHeight,
            decoration: BoxDecoration(
              color: isHighlighted ? widget.appTheme.editorPageToolSelectedBgColor.withAlpha(200) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                ownPrefix,
                isUnfolded(directory.path)
                  ? widget.folderStyle?.folderOpenedicon ?? FolderStyle().folderOpenedicon
                  : widget.folderStyle?.folderClosedicon ?? FolderStyle().folderClosedicon,
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    path.basename(directory.path),
                    style: folderNameStyle,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (widget.folderActions != null) ...widget.folderActions!,
              ],
            ),
          ),
        ),
        if (isUnfolded(directory.path))
          Padding(
            padding: const EdgeInsets.only(right: 7.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: () {
                final children = <Widget>[];
                final total = entries.length;

                for (int i = 0; i < entries.length; i++) {
                  final entry = entries[i];
                  final entryIsLast = i == total - 1 && newEntryPath != directory.path;

                  if (entry is Directory) {
                    children.add(
                      _buildDirectoryTreeNode(
                        entry,
                        repoState,
                        ancestorHasNext: childAncestorHasNext,
                        ancestorPaths: childAncestorPaths,
                        highlightedPath: highlightedPath,
                        isRoot: false,
                        isLast: entryIsLast,
                      ),
                    );
                  } else {
                    children.add(
                      _buildFileItem(
                        entry as File,
                        repoState,
                        ancestorHasNext: childAncestorHasNext,
                        ancestorPaths: childAncestorPaths,
                        highlightedPath: highlightedPath,
                        isLast: entryIsLast,
                      ),
                    );
                  }
                }

                if (newEntryPath == directory.path) {
                  children.add(
                    _buildNewEntryField(
                      directory,
                      prefix: _buildTreePrefix(
                        ancestorHasNext: childAncestorHasNext,
                        ancestorPaths: childAncestorPaths,
                        currentPath: directory.path,
                        highlightedPath: highlightedPath,
                        isLast: true,
                      ),
                    ),
                  );
                }
                return children;
              }(),
            ),
          ),
      ],
    );
  }

  Widget _buildTreePrefix({
    required List<bool> ancestorHasNext,
    required List<String> ancestorPaths,
    required String currentPath,
    required String? highlightedPath,
    required bool isLast,
  }) {
    final guideColor = widget.appTheme.selectScreenCardTextColor.withValues(
      alpha: widget.appTheme.isDark ? 0.24 : 0.32,
    );
    final highlightedGuideColor = widget.appTheme.editorPageToolSelectedColor.withValues(
      alpha: widget.appTheme.isDark ? 0.95 : 0.80,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < ancestorHasNext.length; i++)
          _GuideSegment(
            width: _guideIndentWidth,
            height: _guideRowHeight,
            lineColor: _isPathOnHighlightPath(
              i < ancestorPaths.length ? ancestorPaths[i] : '',
              highlightedPath,
            )
                ? highlightedGuideColor
                : guideColor,
            showVertical: ancestorHasNext[i],
          ),
        _GuideSegment(
          width: _guideIndentWidth,
          height: _guideRowHeight,
          lineColor: _isPathOnHighlightPath(currentPath, highlightedPath)
              ? highlightedGuideColor
              : guideColor,
          showVertical: true,
          isNodeConnector: true,
          isLast: isLast,
        ),
      ],
    );
  }

  Widget _buildNewEntryField(Directory parent, {Widget? prefix}) {
    return Row(
      children: [
        prefix ?? const SizedBox.shrink(),
        isFolderCreation
          ? widget.editingFieldStyle?.folderIcon ?? EditingFieldStyle().folderIcon
          : widget.editingFieldStyle?.fileIcon ?? EditingFieldStyle().fileIcon,
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: widget.editingFieldStyle?.textFieldHeight,
            child: TextField(
              style: widget.editingFieldStyle?.textStyle,
              textAlignVertical: widget.editingFieldStyle?.verticalTextAlign,
              cursorRadius: widget.editingFieldStyle?.cursorRadius,
              cursorWidth: widget.editingFieldStyle?.cursorWidth ?? 2.0,
              cursorHeight: widget.editingFieldStyle?.cursorHeight,
              cursorColor: widget.editingFieldStyle?.cursorColor,
              autofocus: true,
              decoration:
                widget.editingFieldStyle?.textfieldDecoration ??
                EditingFieldStyle().textfieldDecoration,
              controller: _controller,
              onSubmitted: (_) => createEntry(parent),
            ),
          ),
        ),
        IconButton(
          icon:
            widget.editingFieldStyle?.doneIcon ??
            EditingFieldStyle().doneIcon,
          onPressed: () => createEntry(parent),
        ),
        IconButton(
          icon:
            widget.editingFieldStyle?.cancelIcon ??
            EditingFieldStyle().cancelIcon,
          onPressed: stopCreating,
        ),
      ],
    );
  }

  Widget _buildRenameField(String entityPath, bool isFolder, {Widget? prefix}) {
    return Row(
      children: [
        prefix ?? const SizedBox.shrink(),
        isFolder
          ? widget.editingFieldStyle?.folderIcon ?? EditingFieldStyle().folderIcon
          : widget.editingFieldStyle?.fileIcon ?? EditingFieldStyle().fileIcon,
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: widget.editingFieldStyle?.textFieldHeight,
            child: TextField(
              style: widget.editingFieldStyle?.textStyle,
              textAlignVertical: widget.editingFieldStyle?.verticalTextAlign,
              cursorRadius: widget.editingFieldStyle?.cursorRadius,
              cursorWidth: widget.editingFieldStyle?.cursorWidth ?? 2.0,
              cursorHeight: widget.editingFieldStyle?.cursorHeight,
              cursorColor: widget.editingFieldStyle?.cursorColor,
              autofocus: true,
              decoration: (
                widget.editingFieldStyle?.textfieldDecoration
                  ?? EditingFieldStyle().textfieldDecoration
                ).copyWith(hintText: path.basename(entityPath)),
              controller: _renameController,
              onSubmitted: (_) => renameEntry(entityPath, isFolder),
            ),
          ),
        ),
        IconButton(
          icon:
            widget.editingFieldStyle?.doneIcon ??
            EditingFieldStyle().doneIcon,
          onPressed: () => renameEntry(entityPath, isFolder),
        ),
        IconButton(
          icon: widget.editingFieldStyle?.cancelIcon ?? EditingFieldStyle().cancelIcon,
          onPressed: stopRenaming,
        ),
      ],
    );
  }

  Widget _buildFileItem(
    File file,
    RepoStatusState repoState, {
    required List<bool> ancestorHasNext,
    required List<String> ancestorPaths,
    required String? highlightedPath,
    required bool isLast,
  }) {
    final baseStyle = widget.fileStyle?.fileNameStyle ?? FileStyle().fileNameStyle ?? const TextStyle();

    final prefix = _buildTreePrefix(
      ancestorHasNext: ancestorHasNext,
      ancestorPaths: ancestorPaths,
      currentPath: file.path,
      highlightedPath: highlightedPath,
      isLast: isLast,
    );

    if (renamingPath == file.path) {
      return _buildRenameField(file.path, false, prefix: prefix);
    }

    final (color, letter) = _getFileColor(file, repoState, highlightedPath);
    final isHighlighted = highlightedPath != null && path.normalize(file.path) == path.normalize(highlightedPath);
    final key = GlobalKey();
    return InkWell(
      key: key,
      onTap: () => widget.onFileTap?.call(file),
      onLongPress: () {
        final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
        final position = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
        _showFileContextMenu(context, file, position);
      },
      child: Container(
        height: _guideRowHeight,
        decoration: BoxDecoration(
          color: isHighlighted ? widget.appTheme.editorPageToolSelectedBgColor.withAlpha(200) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            prefix,
            widget.fileIconBuilder?.call(path.extension(file.path).toLowerCase())
            ?? widget.fileStyle?.fileIcon
            ?? FileStyle().fileIcon,
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                path.basename(file.path),
                style: baseStyle.copyWith(
                  color: color,
                  height: 1.0,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (letter != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  letter,
                  style: baseStyle.copyWith(
                    color: color,
                    fontSize: 15,
                  ),
                ),
              ),
            if (widget.fileActions != null) ...widget.fileActions!,
          ],
        ),
      ),
    );
  }

  void _expandAllFolders() {
    final folderBloc = context.read<FolderBloc>();
    final allPaths = _getAllDirectoryPaths(Directory(widget.rootPath));
    folderBloc.setAllFoldersExpanded(allPaths, true);
  }

  void _collapseAllFolders() {
    final folderBloc = context.read<FolderBloc>();
    final allPaths = _getAllDirectoryPaths(Directory(widget.rootPath));
    folderBloc.setAllFoldersExpanded(allPaths, false);
  }

  List<String> _getAllDirectoryPaths(Directory directory) {
    final paths = <String>[];
    try {
      final entries = directory.listSync(recursive: true);
      for (final entry in entries) {
        if (entry is Directory) {
          paths.add(entry.path);
        }
      }
    } catch (_) {}
    return paths;
  }

  void _showDeleteFolderConfirmation(
    BuildContext context,
    Directory directory,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: widget.appTheme.isDark
            ? const Color(0xff2b2b2b)
            : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange[400],
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Delete Folder',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Are you sure you want to delete "${path.basename(directory.path)}" and all its contents? This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor.withValues(
                      alpha: 0.8,
                    ),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        _performFolderDeletion(context, directory);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[400],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _performFolderDeletion(BuildContext context, Directory directory) async {
    try {
      await directory.delete(recursive: true);
      if (mounted) setState(() {});
      if (context.mounted) {
        try {
          context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.rootPath));
        } catch (_) {}
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete folder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDeleteFileConfirmation(BuildContext context, File file) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: widget.appTheme.isDark
            ? const Color(0xff2b2b2b)
            : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange[400],
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Delete File',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Are you sure you want to delete "${path.basename(file.path)}"? This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor.withValues(
                      alpha: 0.8,
                    ),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        _performFileDeletion(context, file);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[400],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _performFileDeletion(BuildContext context, File file) async {
    try {
      await file.delete();
      if (mounted) setState(() {});
      if (context.mounted) {
        try {
          context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.rootPath));
        } catch (_) {}
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rootDirectory = Directory(widget.rootPath);
    if (!rootDirectory.existsSync()) {
      return const Center(child: Text('Directory does not exist'));
    }
    if (widget.enableGitFeatures) {
      return BlocBuilder<RepoStatusBloc, RepoStatusState>(
        builder: (context, repoState) {
          return BlocBuilder<FolderBloc, FolderState>(
            builder: (context, folderState) {
              return SingleChildScrollView(
                child: _buildDirectoryTree(
                  rootDirectory,
                  repoState,
                  folderState,
                ),
              );
            },
          );
        },
      );
    } else {
      return BlocBuilder<FolderBloc, FolderState>(
        builder: (context, folderState) {
          return SingleChildScrollView(
            child: _buildDirectoryTree(
              rootDirectory,
              const RepoStatusInitial(),
              folderState,
            ),
          );
        },
      );
    }
  }
}

class _GuideSegment extends StatelessWidget {
  final double width;
  final double height;
  final Color lineColor;
  final bool showVertical;
  final bool isNodeConnector;
  final bool isLast;

  const _GuideSegment({
    required this.width,
    required this.height,
    required this.lineColor,
    required this.showVertical,
    this.isNodeConnector = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _GuideSegmentPainter(
          color: lineColor,
          showVertical: showVertical,
          isNodeConnector: isNodeConnector,
          isLast: isLast,
        ),
      ),
    );
  }
}

class _GuideSegmentPainter extends CustomPainter {
  final Color color;
  final bool showVertical;
  final bool isNodeConnector;
  final bool isLast;

  const _GuideSegmentPainter({
    required this.color,
    required this.showVertical,
    required this.isNodeConnector,
    required this.isLast,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final x = size.width / 2;
    final yMid = size.height / 2;

    if (showVertical && !isNodeConnector) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      return;
    }

    if (!isNodeConnector) return;

    canvas.drawLine(Offset(x, 0), Offset(x, yMid), paint);
    if (!isLast) {
      canvas.drawLine(Offset(x, yMid), Offset(x, size.height), paint);
    }
    canvas.drawLine(Offset(x, yMid), Offset(size.width, yMid), paint);
  }

  @override
  bool shouldRepaint(covariant _GuideSegmentPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.showVertical != showVertical ||
        oldDelegate.isNodeConnector != isNodeConnector ||
        oldDelegate.isLast != isLast;
  }
}

class FindWordWidget extends StatefulWidget {
