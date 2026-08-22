import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:code_forge/code_forge.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';

import 'alpine_setup.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:panda/utils/agentic_tool_catalog.dart';
import 'package:panda/bloc/ui_bloc/ui_bloc.dart';
import 'package:panda/utils/constants.dart';
import 'package:panda/utils/functions.dart';

typedef AgentConfirmCallback = Future<bool> Function({
  required String toolName,
  required String command,
  required String details,
});

class AgenticTools {
  final BuildContext context;
  final String workspacePath;
  final AgentConfirmCallback? onConfirmRequired;
  final String approvalMode; // 'default' | 'autonome' | 'autopilot'

  static bool allowAllCommandsThisSession = false;
  static Set<String> approvedCommandsWhitelist = {};

  static List<AgenticToolSpec> get toolSpecs => agenticToolSpecs;

  AgenticTools({
    required this.workspacePath,
    required this.context,
    this.onConfirmRequired,
    this.approvalMode = 'default',
  }) : _activeEditor = _readActiveEditor(context);

  final ActiveEditor? _activeEditor;

  static ActiveEditor? _readActiveEditor(BuildContext context) {
    try {
      return context
          .read<ActiveEditorBloc>()
          .state
          .activeEditors
          .where((editor) => editor.isActive)
          .firstOrNull;
    } catch (_) {
      // Panda Agent is rendered beside the editor, not inside its local
      // ActiveEditorBloc scope. A missing editor must not abort the chat run.
      return null;
    }
  }

  List<ActiveEditor> _readActiveEditors() {
    try {
      return context.read<ActiveEditorBloc>().state.activeEditors;
    } catch (_) {
      return <ActiveEditor>[];
    }
  }

  String _canonicalWorkspacePath() => Directory(workspacePath).absolute.path;

  String _canonicalFilePath(String filePath) {
    final resolvedPath = path.isAbsolute(filePath)
      ? filePath
      : path.join(workspacePath, filePath);
    return File(resolvedPath).absolute.path;
  }

  List<Map<String, dynamic>> _applyToolSelectionFilter(
    List<Map<String, dynamic>> tools,
  ) {
    Map<String, bool> selections = const <String, bool>{};
    try {
      selections = context.read<AIChatUIBloc>().state.agenticToolSelections;
    } catch (_) {
      // Keep all catalog tools enabled when the optional UI bloc is absent.
    }
    return filterAgenticToolsBySelection(tools, selections);
  }

  bool _isInsideWorkspace(String canonicalPath) {
    final canonicalWorkspace = _canonicalWorkspacePath();
    return canonicalPath == canonicalWorkspace ||
        path.isWithin(canonicalWorkspace, canonicalPath);
  }

  String _diagnosticSeverityLabel(int severity) {
    switch (severity) {
      case 1:
        return 'Error';
      case 2:
        return 'Warning';
      case 3:
        return 'Info';
      case 4:
        return 'Hint';
      default:
        return 'Issue';
    }
  }

  bool _hasLspDiagnosticsAvailability() {
    final editors = _readActiveEditors();
    return editors.any((editor) => editor.controller.lspConfig != null);
  }

  Future<ToolResult<Map<String, dynamic>>> getLspDiagnostics([
    String? filePath,
  ]) async {
    try {
      final editors = _readActiveEditors();
      final lspEditors = editors
          .where((editor) => editor.controller.lspConfig != null)
          .toList();

      if (lspEditors.isEmpty) {
        return ToolResult.error(
          'LSP diagnostics are unavailable because no active editor has an LSP server attached.',
        );
      }

      final requestedCanonicalPath =
          filePath == null ? null : _canonicalFilePath(filePath);

      if (requestedCanonicalPath != null &&
          !_isInsideWorkspace(requestedCanonicalPath)) {
        return ToolResult.error(
          'Permission denied: File is outside the workspace.',
        );
      }

      final selectedEditors = requestedCanonicalPath == null
        ? lspEditors
        : lspEditors.where((editor) => _canonicalFilePath(editor.file.path) == requestedCanonicalPath).toList();

      if (selectedEditors.isEmpty) {
        return ToolResult.error(
          requestedCanonicalPath == null
            ? 'No LSP-enabled editors are currently open.'
            : 'No open LSP-enabled editor found for file: $filePath',
        );
      }

      final diagnostics = <Map<String, dynamic>>[];
      for (final editor in selectedEditors) {
        final relativePath = path.relative(editor.file.path, from: workspacePath);

        for (final diagnostic in editor.controller.diagnostics) {
          final start = Map<String, dynamic>.from(
            diagnostic.range['start'] ?? {},
          );
          final end = Map<String, dynamic>.from(diagnostic.range['end'] ?? {});

          final startLine = ((start['line'] as num?) ?? 0).toInt() + 1;
          final startCharacter =
              ((start['character'] as num?) ?? 0).toInt() + 1;
          final endLine = ((end['line'] as num?) ?? 0).toInt() + 1;
          final endCharacter = ((end['character'] as num?) ?? 0).toInt() + 1;

          diagnostics.add({
            'filePath': relativePath,
            'message': diagnostic.message,
            'severity': diagnostic.severity,
            'severityLabel': _diagnosticSeverityLabel(diagnostic.severity),
            'range': {
              'start': {
                'line': startLine,
                'character': startCharacter,
              },
              'end': {
                'line': endLine,
                'character': endCharacter,
              },
            },
          });
        }
      }

      return ToolResult.success({
        'count': diagnostics.length,
        'diagnostics': diagnostics,
      });
    } catch (e) {
      return ToolResult.error('Error getting LSP diagnostics: $e');
    }
  }

  Future<ToolResult<String>> activeEditorFile() async {
    try {
      if (_activeEditor == null) return ToolResult.error('No active editor');
      return ToolResult.success(_activeEditor!.file.path);
    } catch (e) {
      return ToolResult.error("An error occured: ${e.toString()}");
    }
  }

  Future<ToolResult<Map<String, dynamic>>> currentlySelectedText() async {
    try {
      if (_activeEditor == null) return ToolResult.error('No active editor');
      final controller = _activeEditor!.controller;
      final selStart = controller.getLineAtOffset(
        controller.selection.baseOffset,
      );
      final selEnd = controller.getLineAtOffset(
        controller.selection.extentOffset,
      );
      return ToolResult.success({
        "startLine": selStart,
        "endLine": selEnd,
        "selectedText": controller.text.substring(
          controller.selection.baseOffset,
          controller.selection.extentOffset,
        ),
      });
    } catch (e) {
      return ToolResult.error("An error occured: ${e.toString()}");
    }
  }

  Future<ToolResult<String>> readFile(
    String filePath, [
    int? startLine,
    int? endLine,
  ]) async {
    try {
      final canonicalPath = _canonicalFilePath(filePath);
      final file = File(canonicalPath);

      if (!_isInsideWorkspace(canonicalPath)) {
        return ToolResult.error(
          'Permission denied: File is outside the workspace\n'
          'Workspace: $workspacePath\n'
          'Requested file: $filePath\n',
        );
      }

      if (!await file.exists()) {
        return ToolResult.error('File not found: $filePath');
      }

      if (startLine == null && endLine == null) {
        final content = await file.readAsString();
        return ToolResult.success(content);
      }

      final controller = CodeForgeController()
        ..text = await file.readAsString();
      final startLineIndex = controller.getLineStartOffset(startLine ?? 0);
      final endLineIndex = controller.getLineStartOffset(
        endLine ?? controller.lineCount - 1,
      );
      return ToolResult.success(
        controller.text.substring(startLineIndex, endLineIndex),
      );
    } catch (e) {
      return ToolResult.error('Error reading file: $e');
    }
  }

  Future<void> _trackPendingEditsForWrite(
    String canonicalPath,
    String oldContent,
    String newContent,
  ) async {
    if (oldContent == newContent) {
      return;
    }

    final diffs = diff(oldContent, newContent);
    final patches = patchMake(diffs);
    if (patches.isEmpty) {
      return;
    }

    final patchController = CodeForgeController()..text = newContent;
    final oldController = CodeForgeController()..text = oldContent;

    final pendingEdit = PendingEditFile(
      filePath: canonicalPath,
      oldText: oldContent,
      editHunks: PendingEditFile.patchesToHunks(
        patches,
        patchController,
        oldController,
      ),
    );

    patchController.dispose();
    oldController.dispose();

    await pendingEdit.saveToPrefs();
  }

  Future<void> _refreshPendingDecorationsForPath(String canonicalPath) async {
    if (_activeEditor == null) return;
    if (_canonicalFilePath(_activeEditor!.file.path) != canonicalPath) {
      return;
    }

    final pending = await PendingEditFile.getForFile(canonicalPath);
    if (pending == null || pending.editHunks.isEmpty) {
      _activeEditor!.controller.clearGitDiffDecorations();
    } else {
      pending.applyDecorations(_activeEditor!.controller);
    }
  }

  Future<ToolResult<void>> _writeWithPendingDiff(
    String canonicalPath,
    String oldContent,
    String newContent,
  ) async {
    if (oldContent == newContent) {
      return ToolResult.success(null);
    }

    final diffs = diff(oldContent, newContent);
    final patches = patchMake(diffs);

    final patchController = CodeForgeController()..text = newContent;
    final oldController = CodeForgeController()..text = oldContent;

    final pendingEdit = PendingEditFile(
      filePath: canonicalPath,
      oldText: oldContent,
      editHunks: PendingEditFile.patchesToHunks(
        patches,
        patchController,
        oldController,
      ),
    );

    patchController.dispose();
    oldController.dispose();

    await pendingEdit.saveToPrefs();

    final writeResult = await writeFile(
      canonicalPath,
      newContent,
      trackPendingEdits: false,
    );
    if (!writeResult.success) {
      return writeResult;
    }

    await _refreshPendingDecorationsForPath(canonicalPath);
    return ToolResult.success(null);
  }

  Future<ToolResult<void>> writeFile(
    String filePath,
    String content, {
    bool trackPendingEdits = true,
  }) async {
    try {
      final canonicalPath = _canonicalFilePath(filePath);
      final file = File(canonicalPath);

      if (!_isInsideWorkspace(canonicalPath)) {
        return ToolResult.error(
          'Permission denied: File is outside the workspace\n'
          'Workspace: $workspacePath\n'
          'Requested file: $filePath\n',
        );
      }

      String? oldContent;
      if (trackPendingEdits) {
        oldContent = await file.exists() ? await file.readAsString() : '';
      }

      await file.parent.create(recursive: true);
      await file.writeAsString(content);

      if (trackPendingEdits && oldContent != null) {
        await _trackPendingEditsForWrite(canonicalPath, oldContent, content);
      }

      if (_activeEditor != null && _canonicalFilePath(_activeEditor!.file.path) == canonicalPath) {
        _activeEditor!.controller.refetchFile();

        if (trackPendingEdits) {
          final pending = await PendingEditFile.getForFile(canonicalPath);
          if (pending == null || pending.editHunks.isEmpty) {
            _activeEditor!.controller.clearGitDiffDecorations();
          } else {
            pending.applyDecorations(_activeEditor!.controller);
          }
        }
      }

      return ToolResult.success(null);
    } catch (e) {
      return ToolResult.error('Error writing file: $e');
    }
  }

  Future<ToolResult<List<String>>> listFiles(
    String directoryPath, {
    String? pattern,
    bool recursive = false,
  }) async {
    try {
      String resolvedPath = directoryPath;
      if (!path.isAbsolute(directoryPath)) {
        resolvedPath = path.join(workspacePath, directoryPath);
      }

      final dir = Directory(resolvedPath);
      final canonicalPath = dir.absolute.path;
      final canonicalWorkspace = Directory(workspacePath).absolute.path;

      if (!path.isWithin(canonicalWorkspace, canonicalPath) &&
          canonicalPath != canonicalWorkspace) {
        return ToolResult.error(
          'Permission denied: File is outside the workspace\n'
          'Workspace: $canonicalWorkspace\n'
          'Path tried to access: $canonicalPath\n',
        );
      }

      if (!await dir.exists()) {
        return ToolResult.error('Directory not found: $directoryPath');
      }

      final entities = await dir.list(recursive: recursive).toList();
      final files = entities
          .whereType<File>()
          .map((f) => path.relative(f.path, from: workspacePath))
          .toList();

      if (pattern != null) {
        final regex = _globToRegex(pattern);
        return ToolResult.success(
          files.where((f) => regex.hasMatch(f)).toList(),
        );
      }

      return ToolResult.success(files);
    } catch (e) {
      return ToolResult.error('Error listing files: $e');
    }
  }

  /// Asks for user confirmation before executing a command or destructive action.
  /// Uses inline UI callback if provided, otherwise checks autopilot/session permissions.
  Future<bool> _confirmDestructive({
    required String title,
    required String body,
    String toolName = 'runShellCommand',
    String command = '',
  }) async {
    // 1. Autopilot / session bypass
    if (approvalMode == 'autopilot' || approvalMode == 'autonome' || allowAllCommandsThisSession) {
      return true;
    }
    if (command.isNotEmpty && approvedCommandsWhitelist.contains(command.trim())) {
      return true;
    }

    // 2. Inline UI callback (no modal pop up)
    if (onConfirmRequired != null) {
      return await onConfirmRequired!(
        toolName: toolName,
        command: command.isNotEmpty ? command : body,
        details: body,
      );
    }

    // Fallback if no callback set
    return false;
  }

  Future<ToolResult<void>> deleteFile(String filePath) async {
    try {
      final canonicalPath = _canonicalFilePath(filePath);
      if (!_isInsideWorkspace(canonicalPath)) {
        return ToolResult.error(
          'Permission denied: Path is outside workspace.',
        );
      }

      final file = File(canonicalPath);
      if (!await file.exists()) {
        return ToolResult.error('File not found: $filePath');
      }

      final confirmed = await _confirmDestructive(
        title: 'Supprimer le fichier ?',
        body: 'L\'agent veut supprimer :\n$filePath\n\nCette action est irréversible.',
      );
      if (!confirmed) {
        return ToolResult.error('Suppression annulée par l\'utilisateur.');
      }

      await file.delete();
      await PendingEditFile.removeFile(canonicalPath);

      if (_activeEditor != null && _canonicalFilePath(_activeEditor!.file.path) == canonicalPath) {
        _activeEditor!.controller.clearGitDiffDecorations();
      }

      return ToolResult.success(null);
    } catch (e) {
      return ToolResult.error('Error deleting file: $e');
    }
  }

  Future<ToolResult<void>> renamePath(String oldPath, String newPath) async {
    try {
      final canonicalOldPath = _canonicalFilePath(oldPath);
      final canonicalNewPath = _canonicalFilePath(newPath);

      if (!_isInsideWorkspace(canonicalOldPath) ||
          !_isInsideWorkspace(canonicalNewPath)) {
        return ToolResult.error(
          'Permission denied: Path is outside workspace.',
        );
      }

      final oldType = await FileSystemEntity.type(canonicalOldPath);
      if (oldType == FileSystemEntityType.notFound) {
        return ToolResult.error('Path not found: $oldPath');
      }

      final newType = await FileSystemEntity.type(canonicalNewPath);
      if (newType != FileSystemEntityType.notFound) {
        return ToolResult.error('Target path already exists: $newPath');
      }

      await Directory(path.dirname(canonicalNewPath)).create(recursive: true);

      if (oldType == FileSystemEntityType.directory) {
        await Directory(canonicalOldPath).rename(canonicalNewPath);

        final allPending = await PendingEditFile.getAllFromPrefs();
        for (final entry in allPending.entries) {
          final pendingPath = entry.key;
          if (pendingPath == canonicalOldPath ||
              path.isWithin(canonicalOldPath, pendingPath)) {
            final relativePendingPath = path.relative(
              pendingPath,
              from: canonicalOldPath,
            );
            final movedPendingPath = relativePendingPath == '.'
                ? canonicalNewPath
                : path.join(canonicalNewPath, relativePendingPath);

            await PendingEditFile.removeFile(pendingPath);
            await PendingEditFile.upsert(
              entry.value.copyWith(filePath: movedPendingPath),
            );
          }
        }
      } else {
        await File(canonicalOldPath).rename(canonicalNewPath);
        final pending = await PendingEditFile.getForFile(canonicalOldPath);
        if (pending != null) {
          await PendingEditFile.removeFile(canonicalOldPath);
          await PendingEditFile.upsert(
            pending.copyWith(filePath: canonicalNewPath),
          );
        }
      }

      if (_activeEditor == null) return ToolResult.error("No active editor");
      final activePath = _canonicalFilePath(_activeEditor!.file.path);
      if (activePath == canonicalOldPath ||
          path.isWithin(canonicalOldPath, activePath)) {
        _activeEditor!.controller.clearGitDiffDecorations();
      }

      return ToolResult.success(null);
    } catch (e) {
      return ToolResult.error('Error renaming path: $e');
    }
  }

  Future<ToolResult<void>> rename(String oldPath, String newPath) {
    return renamePath(oldPath, newPath);
  }

  Future<ToolResult<void>> insertAtLine(
    String filePath,
    int line,
    String text, {
    String position = 'before',
  }) async {
    try {
      final canonicalPath = _canonicalFilePath(filePath);
      if (!_isInsideWorkspace(canonicalPath)) {
        return ToolResult.error('Permission denied: Path is outside workspace.');
      }

      final readResult = await readFile(canonicalPath);
      if (!readResult.success) {
        return ToolResult.error(readResult.error ?? 'Error reading file');
      }

      if (line < 1) {
        return ToolResult.error('Line must be 1 or greater.');
      }

      final oldContent = readResult.data ?? '';
      final lines = oldContent.isEmpty ? <String>[] : oldContent.split('\n');
      final insertLines = text.split('\n');

      final normalizedPosition = position.toLowerCase();
      if (normalizedPosition != 'before' && normalizedPosition != 'after') {
        return ToolResult.error("position must be 'before' or 'after'.");
      }

      int insertIndex;
      if (normalizedPosition == 'before') {
        if (line > lines.length + 1) {
          return ToolResult.error(
            'Line out of range. Max valid line is ${lines.length + 1}.',
          );
        }
        insertIndex = line - 1;
      } else {
        if (line > lines.length) {
          return ToolResult.error(
            'Line out of range. Max valid line is ${lines.length}.',
          );
        }
        insertIndex = line;
      }

      lines.insertAll(insertIndex, insertLines);
      final newContent = lines.join('\n');

      return _writeWithPendingDiff(canonicalPath, oldContent, newContent);
    } catch (e) {
      return ToolResult.error('Error inserting text at line: $e');
    }
  }

  Future<ToolResult<Map<String, dynamic>>> replaceAllInFile(
    String filePath,
    String oldText,
    String newText, {
    bool useRegex = false,
    int? maxReplacements,
    bool caseSensitive = true,
  }) async {
    try {
      if (oldText.isEmpty) {
        return ToolResult.error('oldText cannot be empty.');
      }

      if (maxReplacements != null && maxReplacements <= 0) {
        return ToolResult.error('maxReplacements must be greater than 0.');
      }

      final canonicalPath = _canonicalFilePath(filePath);
      if (!_isInsideWorkspace(canonicalPath)) {
        return ToolResult.error('Permission denied: Path is outside workspace.');
      }

      final readResult = await readFile(canonicalPath);
      if (!readResult.success) {
        return ToolResult.error(readResult.error ?? 'Error reading file');
      }

      final oldContent = readResult.data ?? '';
      final pattern = useRegex ? oldText : RegExp.escape(oldText);
      final regex = RegExp(pattern, caseSensitive: caseSensitive);
      final matches = regex.allMatches(oldContent).toList();

      if (matches.isEmpty) {
        return ToolResult.error('No matches found in file.');
      }

      final limit = maxReplacements == null
          ? matches.length
          : math.min(maxReplacements, matches.length);

      final buffer = StringBuffer();
      var cursor = 0;
      for (var i = 0; i < limit; i++) {
        final match = matches[i];
        buffer.write(oldContent.substring(cursor, match.start));
        buffer.write(newText);
        cursor = match.end;
      }
      buffer.write(oldContent.substring(cursor));
      final newContent = buffer.toString();

      final writeResult = await _writeWithPendingDiff(
        canonicalPath,
        oldContent,
        newContent,
      );
      if (!writeResult.success) {
        return ToolResult.error(writeResult.error ?? 'Error replacing text.');
      }

      return ToolResult.success({
        'replacements': limit,
        'totalMatches': matches.length,
      });
    } catch (e) {
      return ToolResult.error('Error replacing text in file: $e');
    }
  }

  Future<ToolResult<List<Map<String, dynamic>>>> readFilesBatch(
    List<dynamic> files,
  ) async {
    try {
      final results = <Map<String, dynamic>>[];

      for (final fileItem in files) {
        if (fileItem is! Map) {
          results.add({
            'success': false,
            'error': 'Each files item must be an object.',
          });
          continue;
        }

        final map = Map<String, dynamic>.from(fileItem);
        final filePath = map['filePath']?.toString();
        if (filePath == null || filePath.isEmpty) {
          results.add({
            'success': false,
            'error': 'filePath is required.',
          });
          continue;
        }

        final startLine = map['startLine'] is int ? map['startLine'] as int : null;
        final endLine = map['endLine'] is int ? map['endLine'] as int : null;

        final readResult = await readFile(filePath, startLine, endLine);
        if (readResult.success) {
          results.add({
            'filePath': filePath,
            'success': true,
            'content': readResult.data ?? '',
          });
        } else {
          results.add({
            'filePath': filePath,
            'success': false,
            'error': readResult.error ?? 'Error reading file',
          });
        }
      }

      return ToolResult.success(results);
    } catch (e) {
      return ToolResult.error('Error reading files batch: $e');
    }
  }

  Future<ToolResult<List<String>>> globSearchFiles(
    String pattern, {
    String directoryPath = '.',
    List<String>? excludePatterns,
    bool recursive = true,
    int? maxResults,
  }) async {
    try {
      final canonicalDir = _canonicalFilePath(directoryPath);
      if (!_isInsideWorkspace(canonicalDir)) {
        return ToolResult.error(
          'Permission denied: Path is outside workspace.',
        );
      }

      final dir = Directory(canonicalDir);
      if (!await dir.exists()) {
        return ToolResult.error('Directory not found: $directoryPath');
      }

      final includeRegex = _globToRegex(pattern);
      final excludeRegexes = (excludePatterns ?? [])
          .map((glob) => _globToRegex(glob))
          .toList();

      final results = <String>[];
      await for (final entity in dir.list(recursive: recursive)) {
        if (entity is! File) continue;

        final relativePath = path.relative(entity.path, from: workspacePath);
        if (!includeRegex.hasMatch(relativePath)) continue;

        var excluded = false;
        for (final regex in excludeRegexes) {
          if (regex.hasMatch(relativePath)) {
            excluded = true;
            break;
          }
        }
        if (excluded) continue;

        results.add(relativePath);
        if (maxResults != null && results.length >= maxResults) break;
      }

      return ToolResult.success(results);
    } catch (e) {
      return ToolResult.error('Error searching files by glob: $e');
    }
  }

  Future<ToolResult<List<GrepResult>>> grepInFiles(
    String query, {
    String? filePattern,
    bool caseSensitive = false,
    bool matchWholeWord = false,
    bool useRegex = false,
    int before = 2,
    int after = 2,
    int? maxResults,
  }) async {
    try {
      final results = <GrepResult>[];
      final dir = Directory(workspacePath);

      String pattern = useRegex ? query : RegExp.escape(query);
      if (matchWholeWord) {
        pattern = r'\b$pattern\b';
      }
      final regex = RegExp(pattern, caseSensitive: caseSensitive);

      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;

        final relativePath = path.relative(entity.path, from: workspacePath);
        if (filePattern != null) {
          final fileRegex = _globToRegex(filePattern);
          if (!fileRegex.hasMatch(relativePath)) continue;
        }

        try {
          final content = await entity.readAsString();
          final lines = content.split('\n');

          for (var i = 0; i < lines.length; i++) {
            if (!regex.hasMatch(lines[i])) continue;

            final beforeStart = math.max(0, i - before);
            final afterEnd = math.min(lines.length - 1, i + after);

            results.add(
              GrepResult(
                filePath: relativePath,
                lineNumber: i + 1,
                lineContent: lines[i],
                beforeContext: lines.sublist(beforeStart, i),
                afterContext: lines.sublist(i + 1, afterEnd + 1),
              ),
            );

            if (maxResults != null && results.length >= maxResults) {
              return ToolResult.success(results);
            }
          }
        } catch (_) {
          continue;
        }
      }

      return ToolResult.success(results);
    } catch (e) {
      return ToolResult.error('Error grepping files: $e');
    }
  }

  Future<ToolResult<List<SearchResult>>> searchInFiles(
    String query, {
    String? filePattern,
    bool caseSensitive = false,
    bool matchWholeWord = false,
    bool useRegex = false,
  }) async {
    try {
      final results = <SearchResult>[];
      final dir = Directory(workspacePath);

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final relativePath = path.relative(entity.path, from: workspacePath);

          if (filePattern != null) {
            final regex = _globToRegex(filePattern);
            if (!regex.hasMatch(relativePath)) continue;
          }

          try {
            final content = await entity.readAsString();

            final controller = CodeForgeController()..text = content;

            String pattern;
            if (useRegex) {
              pattern = query;
            } else {
              pattern = RegExp.escape(query);
            }
            if (matchWholeWord) {
              pattern = r'\b' + pattern + r'\b';
            }

            final regex = RegExp(pattern, caseSensitive: caseSensitive);
            final matches = regex.allMatches(content);

            if (matches.isNotEmpty) {
              final lines = content.split('\n');
              final processedLines = <int>{};

              for (final match in matches) {
                final lineNumber = controller.getLineAtOffset(match.start);

                if (!processedLines.contains(lineNumber)) {
                  processedLines.add(lineNumber);

                  if (lineNumber < lines.length) {
                    results.add(
                      SearchResult(
                        filePath: relativePath,
                        lineNumber: lineNumber + 1,
                        lineContent: lines[lineNumber].trim(),
                      ),
                    );
                  }
                }
              }
            }

            controller.dispose();
          } catch (e) {
            continue;
          }
        }
      }

      return ToolResult.success(results);
    } catch (e) {
      return ToolResult.error('Error searching files: $e');
    }
  }

  Future<ToolResult<void>> editFile(
    String filePath,
    String oldText,
    String newText,
  ) async {
    try {
      if (oldText.isEmpty) {
        return ToolResult.error('Old text cannot be empty for editFile.');
      }

      final canonicalPath = _canonicalFilePath(filePath);
      if (!_isInsideWorkspace(canonicalPath)) {
        return ToolResult.error(
          'Permission denied: Path is outside workspace.',
        );
      }

      final readResult = await readFile(canonicalPath);
      if (!readResult.success) {
        return ToolResult.error(readResult.error ?? 'Error reading file');
      }

      final content = readResult.data ?? '';
      final oldMatches = RegExp(
        RegExp.escape(oldText),
      ).allMatches(content).length;
      if (oldMatches == 0) {
        return ToolResult.error(
          'Old text not found in file. This may be due to the file being modified.',
        );
      }
      if (oldMatches > 1) {
        return ToolResult.error(
          'Old text appears multiple times in file. Provide a more specific oldText to avoid ambiguous edits.',
        );
      }

      final newContent = content.replaceFirst(oldText, newText);
      final diffs = diff(content, newContent);
      final patches = patchMake(diffs);

      final patchController = CodeForgeController()..text = newContent;
      final oldController = CodeForgeController()..text = content;

      final pendingEdit = PendingEditFile(
        filePath: canonicalPath,
        oldText: content,
        editHunks: PendingEditFile.patchesToHunks(
          patches,
          patchController,
          oldController,
        ),
      );

      patchController.dispose();
      oldController.dispose();

      await pendingEdit.saveToPrefs();
      final writeResult = await writeFile(
        canonicalPath,
        newContent,
        trackPendingEdits: false,
      );
      if (!writeResult.success) {
        return writeResult;
      }

      if (_activeEditor != null && _canonicalFilePath(_activeEditor!.file.path) == canonicalPath) {
        final refreshedPending = await PendingEditFile.getForFile(
          canonicalPath,
        );
        if (refreshedPending == null || refreshedPending.editHunks.isEmpty) {
          _activeEditor!.controller.clearGitDiffDecorations();
        } else {
          refreshedPending.applyDecorations(_activeEditor!.controller);
        }
      }

      return ToolResult.success(null);
    } catch (e) {
      return ToolResult.error('Error editing file: $e');
    }
  }

  Future<Map<String, String>> _buildAgentShellEnvironment(
    String workingDirectory,
  ) async {
    final sharedPath = await NativeChannel.getLibraryPath();
    return <String, String>{
      'HOME': homeDir,
      'PWD': workingDirectory,
      'PS1': r' \[\e[32m\]\w \[\e[0m\]\$ ',
      'PATH': '$binDir:$runtimesDir/node/bin:/bin:/usr/bin:/sbin:/usr/sbin',
      'PROMPT_DIRTRIM': '2',
      'ROXUM_SHARED_PATH': sharedPath,
      'LD_LIBRARY_PATH': '$sharedPath:$libDir:$runtimesDir/clang',
      'PREFIX': '/data/data/com.panda.ide',
      'JAVA_HOME': '$runtimesDir/java-21-openjdk',
      'GIT_EXEC_PATH': '$binDir/git-core',
      'GIT_SSL_CAINFO': '$certDir/cacert.pem',
      'CARGO_HTTP_CAINFO': '$certDir/cacert.pem',
      'RUSTFLAGS': '--sysroot $runtimesDir/rust',
      'GOROOT': '$runtimesDir/go',
    };
  }

  /// Exécute [script] dans l'environnement Alpine de l'agent en utilisant
  /// EXACTEMENT la même recette proot que le terminal interactif (binaire
  /// localisé via AlpineSetup, loader embarqué, PROOT_TMP_DIR, binds
  /// conditionnels, kill-on-exit). C'était la cause des timeouts : l'agent
  /// lançait un vieux binaire $binDir/proot sans loader ni binds.
  Future<ProcessResult> _runGuestShell(
    String script, {
    Map<String, String> envs = const {},
    required Duration timeout,
    required String timeoutLabel,
  }) async {
    final rootfsDir = AlpineSetup.alpineDir;

    if (AlpineSetup.isRootfsComplete()) {
      try {
        await AlpineSetup.ensureAlpineRuntimeFiles();
      } catch (_) {}
      final prootBin = await AlpineSetup.locateProotBinary(rootfsDir);
      if (prootBin != null) {
        final prootArgs = <String>[
          '-0',
          '--link2symlink',
          '--sysvipc',
          '--kill-on-exit',
          '--rootfs=$rootfsDir',
          '-b', '/dev',
          '-b', '/proc',
          '-b', '/sys',
        ];
        void addBind(String hostPath, [String? guestPath]) {
          try {
            final host = hostPath.split(':').first;
            if (Directory(host).existsSync() || File(host).existsSync()) {
              prootArgs.addAll(['-b', guestPath != null ? '$hostPath:$guestPath' : hostPath]);
            }
          } catch (_) {}
        }

        addBind('/dev/pts');
        addBind('/dev/urandom');
        addBind('/dev/shm');
        addBind('/proc/self/fd', '/dev/fd');
        addBind('/system');
        addBind('/apex');
        addBind('/linkerconfig');
        addBind('/vendor');
        addBind('/sdcard');
        addBind('/storage');
        addBind(appDir);
        addBind(tempDir, '/tmp');

        // Le workspace hôte est monté au point stable /root/workspace.
        final ws = workspacePath.trim();
        final wsReadable = ws.isNotEmpty && AlpineSetup.isDirAccessible(ws);
        if (wsReadable) addBind(ws, AlpineSetup.workspaceMount);
        final guestCwd = wsReadable ? AlpineSetup.workspaceMount : '/root';

        // PATH invité d'abord (outils musl), fallback binaires hôtes ensuite.
        // Les extras ne doivent pas écraser le PATH invité : les paquets
        // installés par l'utilisateur via apk (terminal ou UI) restent ainsi
        // prioritaires sur les binaires hôtes embarqués.
        final hostExtras = Map<String, String>.from(envs)..remove('PATH');
        final env =
            await AlpineSetup.prootSessionEnvironment(extra: hostExtras);

        // Un git installé par l'utilisateur (apk add git) doit être utilisé
        // en entier : on retire l'override GIT_EXEC_PATH qui pointerait sur
        // le git-core hôte bionic et casserait le git musl de l'invité.
        if (File('$rootfsDir/usr/bin/git').existsSync()) {
          env.remove('GIT_EXEC_PATH');
          // Le git apk utilise ses propres CA (/etc/ssl/certs du rootfs).
          env.remove('GIT_SSL_CAINFO');
        }
        env['PATH'] =
            '${env['PATH'] ?? ''}:$binDir:$libDir:$runtimesDir/node/bin';

        return Process.run(
          prootBin,
          [...prootArgs, '-w', '/root', '/bin/sh', '-c', 'cd "$guestCwd" 2>/dev/null; $script'],
          environment: env,
          workingDirectory: appDir,
        ).timeout(
          timeout,
          onTimeout: () => throw TimeoutException('$timeoutLabel exceeded ${timeout.inSeconds} s timeout'),
        );
      }
    }

    // Rootfs indisponible : repli sur le shell hôte Android.
    return Process.run(
      '/system/bin/sh',
      ['-c', script],
      environment: envs,
      workingDirectory: workspacePath.trim().isNotEmpty ? workspacePath : appDir,
    ).timeout(
      timeout,
      onTimeout: () => throw TimeoutException('$timeoutLabel exceeded ${timeout.inSeconds} s timeout'),
    );
  }

  Future<ProcessResult> _runGitCommand(List<String> args) async {
    final env = await _buildAgentShellEnvironment(workspacePath);
    final guest = await _runGuestShell(
      'git ${args.map((a) => "'$a'").join(' ')}',
      envs: env,
      timeout: const Duration(seconds: 120),
      timeoutLabel: 'git ${args.first}',
    );
    // git absent de l'invité (exit 127) → repli binaire git hôte.
    final out = '${guest.stdout}${guest.stderr}';
    if (guest.exitCode == 127 || out.contains('not found')) {
      return Process.run(
        'git',
        args,
        environment: env,
        workingDirectory: workspacePath.trim().isNotEmpty ? workspacePath : appDir,
      );
    }
    return guest;
  }

  Future<ToolResult<GitStatusInfo>> gitStatus() async {
    try {
      final process = await _runGitCommand(['status', '--porcelain=1', '-b']);
      if (process.exitCode != 0) {
        return ToolResult.error(
          process.stderr.toString().trim().isEmpty
              ? 'git status failed'
              : process.stderr.toString().trim(),
        );
      }

      final output = process.stdout.toString();
      final lines = output
          .split('\n')
          .map((line) => line.trimRight())
          .where((line) => line.isNotEmpty)
          .toList();

      var branch = 'unknown';
      var ahead = 0;
      var behind = 0;
      final staged = <String>[];
      final unstaged = <String>[];
      final untracked = <String>[];
      final conflicts = <String>[];

      if (lines.isNotEmpty && lines.first.startsWith('## ')) {
        final statusLine = lines.first.substring(3);
        branch = statusLine.split('...').first.trim();

        final aheadMatch = RegExp(r'ahead\s+(\d+)').firstMatch(statusLine);
        final behindMatch = RegExp(r'behind\s+(\d+)').firstMatch(statusLine);
        if (aheadMatch != null) {
          ahead = int.tryParse(aheadMatch.group(1) ?? '0') ?? 0;
        }
        if (behindMatch != null) {
          behind = int.tryParse(behindMatch.group(1) ?? '0') ?? 0;
        }
      }

      for (var i = 1; i < lines.length; i++) {
        final line = lines[i];
        if (line.length < 3) continue;

        final x = line[0];
        final y = line[1];
        final filePath = line.substring(3).trim();

        if (x == '?' && y == '?') {
          untracked.add(filePath);
          continue;
        }

        final isConflict =
            x == 'U' ||
            y == 'U' ||
            (x == 'A' && y == 'A') ||
            (x == 'D' && y == 'D');
        if (isConflict) {
          conflicts.add(filePath);
          continue;
        }

        if (x != ' ') staged.add(filePath);
        if (y != ' ') unstaged.add(filePath);
      }

      return ToolResult.success(
        GitStatusInfo(
          branch: branch,
          ahead: ahead,
          behind: behind,
          staged: staged,
          unstaged: unstaged,
          untracked: untracked,
          conflicts: conflicts,
        ),
      );
    } catch (e) {
      return ToolResult.error('Error getting git status: $e');
    }
  }

  Future<ToolResult<String>> gitDiff({
    String? filePath,
    bool staged = false,
    int contextLines = 3,
  }) async {
    try {
      final args = <String>['diff', '-U$contextLines'];
      if (staged) {
        args.add('--staged');
      }

      if (filePath != null && filePath.isNotEmpty) {
        final canonicalPath = _canonicalFilePath(filePath);
        if (!_isInsideWorkspace(canonicalPath)) {
          return ToolResult.error(
            'Permission denied: Path is outside workspace.',
          );
        }
        args.addAll(['--', path.relative(canonicalPath, from: workspacePath)]);
      }

      final process = await _runGitCommand(args);
      if (process.exitCode != 0) {
        return ToolResult.error(
          process.stderr.toString().trim().isEmpty
              ? 'git diff failed'
              : process.stderr.toString().trim(),
        );
      }

      return ToolResult.success(process.stdout.toString());
    } catch (e) {
      return ToolResult.error('Error getting git diff: $e');
    }
  }

  Future<ToolResult<List<GitCommitInfo>>> gitLog({
    int limit = 20,
    String? filePath,
  }) async {
    try {
      final safeLimit = limit.clamp(1, 200);
      final args = <String>[
        'log',
        '--date=iso',
        '--pretty=format:%H%x1f%an%x1f%ad%x1f%s',
        '-n',
        '$safeLimit',
      ];

      if (filePath != null && filePath.isNotEmpty) {
        final canonicalPath = _canonicalFilePath(filePath);
        if (!_isInsideWorkspace(canonicalPath)) {
          return ToolResult.error(
            'Permission denied: Path is outside workspace.',
          );
        }
        args.addAll(['--', path.relative(canonicalPath, from: workspacePath)]);
      }

      final process = await _runGitCommand(args);
      if (process.exitCode != 0) {
        return ToolResult.error(
          process.stderr.toString().trim().isEmpty
              ? 'git log failed'
              : process.stderr.toString().trim(),
        );
      }

      final commits = <GitCommitInfo>[];
      final lines = process.stdout
          .toString()
          .split('\n')
          .where((line) => line.trim().isNotEmpty);

      for (final line in lines) {
        final parts = line.split('\u001f');
        if (parts.length < 4) continue;
        commits.add(
          GitCommitInfo(
            hash: parts[0],
            author: parts[1],
            date: parts[2],
            message: parts.sublist(3).join('\u001f'),
          ),
        );
      }

      return ToolResult.success(commits);
    } catch (e) {
      return ToolResult.error('Error getting git log: $e');
    }
  }

  Future<ToolResult<PendingEditFile?>> getPendingEditsForFile(
    String filePath,
  ) async {
    try {
      final canonicalPath = _canonicalFilePath(filePath);
      if (!_isInsideWorkspace(canonicalPath)) {
        return ToolResult.error(
          'Permission denied: Path is outside workspace.',
        );
      }
      final pending = await PendingEditFile.getForFile(canonicalPath);
      return ToolResult.success(pending);
    } catch (e) {
      return ToolResult.error('Error loading pending edits: $e');
    }
  }

  Future<ToolResult<void>> applyPendingDecorationsForFile(
    String filePath,
    CodeForgeController controller,
  ) async {
    try {
      final canonicalPath = _canonicalFilePath(filePath);
      if (!_isInsideWorkspace(canonicalPath)) {
        return ToolResult.error(
          'Permission denied: Path is outside workspace.',
        );
      }

      final pending = await PendingEditFile.getForFile(canonicalPath);
      if (pending == null || pending.editHunks.isEmpty) {
        controller.clearGitDiffDecorations();
        return ToolResult.success(null);
      }

      pending.applyDecorations(controller);
      return ToolResult.success(null);
    } catch (e) {
      return ToolResult.error('Error applying pending decorations: $e');
    }
  }

  Future<ToolResult<void>> keepPendingEditHunk(
    String filePath,
    String hunkId,
  ) async {
    try {
      final canonicalPath = _canonicalFilePath(filePath);
      if (!_isInsideWorkspace(canonicalPath)) {
        return ToolResult.error(
          'Permission denied: Path is outside workspace.',
        );
      }

      await PendingEditFile.removeHunk(canonicalPath, hunkId);

      if (_activeEditor != null && _canonicalFilePath(_activeEditor!.file.path) == canonicalPath) {
        final pending = await PendingEditFile.getForFile(canonicalPath);
        if (pending == null || pending.editHunks.isEmpty) {
          _activeEditor!.controller.clearGitDiffDecorations();
        } else {
          pending.applyDecorations(_activeEditor!.controller);
        }
      }

      return ToolResult.success(null);
    } catch (e) {
      return ToolResult.error('Error keeping pending hunk: $e');
    }
  }

  Future<ToolResult<void>> keepAllPendingEdits(String filePath) async {
    try {
      final canonicalPath = _canonicalFilePath(filePath);
      if (!_isInsideWorkspace(canonicalPath)) {
        return ToolResult.error(
          'Permission denied: Path is outside workspace.',
        );
      }

      await PendingEditFile.removeFile(canonicalPath);
      if (_activeEditor != null && _canonicalFilePath(_activeEditor!.file.path) == canonicalPath) {
        _activeEditor!.controller.clearGitDiffDecorations();
      }
      return ToolResult.success(null);
    } catch (e) {
      return ToolResult.error('Error keeping all pending edits: $e');
    }
  }

  Future<ToolResult<void>> rejectPendingEditHunk(
    String filePath,
    String hunkId,
  ) async {
    try {
      final canonicalPath = _canonicalFilePath(filePath);
      if (!_isInsideWorkspace(canonicalPath)) {
        return ToolResult.error(
          'Permission denied: Path is outside workspace.',
        );
      }

      final pending = await PendingEditFile.getForFile(canonicalPath);
      if (pending == null) {
        return ToolResult.error('No pending edits found for file.');
      }

      EditHunk? hunk;
      for (final item in pending.editHunks) {
        if (item.id == hunkId) {
          hunk = item;
          break;
        }
      }
      if (hunk == null) {
        return ToolResult.error('Pending hunk not found.');
      }

      final readResult = await readFile(canonicalPath);
      if (!readResult.success) {
        return ToolResult.error(readResult.error ?? 'Error reading file');
      }
      final content = readResult.data ?? '';

      if (!content.contains(hunk.newText)) {
        return ToolResult.error(
          'Cannot reject hunk because edited content no longer matches current file.',
        );
      }

      final reverted = content.replaceFirst(hunk.newText, hunk.oldText);
      final writeResult = await writeFile(
        canonicalPath,
        reverted,
        trackPendingEdits: false,
      );
      if (!writeResult.success) {
        return writeResult;
      }

      await PendingEditFile.removeHunk(canonicalPath, hunkId);

      if (_activeEditor != null && _canonicalFilePath(_activeEditor!.file.path) == canonicalPath) {
        final refreshed = await PendingEditFile.getForFile(canonicalPath);
        if (refreshed == null || refreshed.editHunks.isEmpty) {
          _activeEditor!.controller.clearGitDiffDecorations();
        } else {
          refreshed.applyDecorations(_activeEditor!.controller);
        }
      }

      return ToolResult.success(null);
    } catch (e) {
      return ToolResult.error('Error rejecting pending hunk: $e');
    }
  }

  Future<ToolResult<void>> rejectAllPendingEdits(String filePath) async {
    try {
      final canonicalPath = _canonicalFilePath(filePath);
      if (!_isInsideWorkspace(canonicalPath)) {
        return ToolResult.error(
          'Permission denied: Path is outside workspace.',
        );
      }

      final pending = await PendingEditFile.getForFile(canonicalPath);
      if (pending == null) {
        return ToolResult.error('No pending edits found for file.');
      }

      final writeResult = await writeFile(
        canonicalPath,
        pending.oldText,
        trackPendingEdits: false,
      );
      if (!writeResult.success) {
        return writeResult;
      }

      await PendingEditFile.removeFile(canonicalPath);
      if (_activeEditor != null && _canonicalFilePath(_activeEditor!.file.path) == canonicalPath) {
        _activeEditor!.controller.clearGitDiffDecorations();
      }
      return ToolResult.success(null);
    } catch (e) {
      return ToolResult.error('Error rejecting all pending edits: $e');
    }
  }

  Future<ToolResult<FileInfo>> getFileInfo(String filePath) async {
    try {
      final canonicalPath = _canonicalFilePath(filePath);
      if (!_isInsideWorkspace(canonicalPath)) {
        return ToolResult.error('Permission denied: Path is outside workspace');
      }
      final file = File(canonicalPath);

      final stat = await file.stat();

      return ToolResult.success(
        FileInfo(
          path: path.relative(canonicalPath, from: workspacePath),
          size: stat.size,
          modified: stat.modified,
          isDirectory: stat.type == FileSystemEntityType.directory,
        ),
      );
    } catch (e) {
      return ToolResult.error('Error getting file info: $e');
    }
  }

  Future<ToolResult<WebPageContent>> openLinks(String url) async {
    final completer = Completer<String>();
    late HeadlessInAppWebView headless;
    Timer? timeoutTimer;
    bool isProcessing = false;
    bool isDisposed = false;

    timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!completer.isCompleted) {
        completer.complete("");
        if (!isDisposed) {
          isDisposed = true;
          headless.dispose();
        }
      }
    });

    headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        cacheEnabled: false,
        clearCache: true,
        userAgent:
            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120 Safari/537.36",
      ),
      onLoadStop: (controller, _) async {
        if (isProcessing || completer.isCompleted || isDisposed) {
          return;
        }

        isProcessing = true;

        try {
          await controller.evaluateJavascript(
            source: """
            (async () => {
              const start = Date.now();
              const timeout = 10000;
              while (Date.now() - start < timeout) {
                if (
                  document.querySelector("main") ||
                  document.querySelector("article") ||
                  document.readyState === 'complete' && document.body.innerText.length > 1000
                ) {
                  return true;
                }
                await new Promise(r => setTimeout(r, 200));
              }
              return false;
            })();
          """,
          );

          if (isDisposed) return;
          await Future.delayed(const Duration(milliseconds: 500));
          if (isDisposed) return;

          final html = await controller.evaluateJavascript(
            source: "document.documentElement.outerHTML;",
          );

          if (!completer.isCompleted && !isDisposed) {
            completer.complete(html?.toString() ?? "");
            timeoutTimer?.cancel();
            isDisposed = true;
            await headless.dispose();
          }
        } catch (e) {
          if (!completer.isCompleted && !isDisposed) {
            completer.complete("");
            timeoutTimer?.cancel();
            isDisposed = true;
            await headless.dispose();
          }
        } finally {
          isProcessing = false;
        }
      },
    );

    await headless.run();

    try {
      final htmlString = await completer.future;

      if (htmlString.isEmpty) {
        return ToolResult.error("Failed to fetch content");
      }

      final parsed = _parseWebContent(htmlString, url);
      return ToolResult.success(parsed);
    } finally {
      timeoutTimer.cancel();
      if (!isDisposed) {
        isDisposed = true;
        await headless.dispose();
      }
    }
  }

  // Commands that require explicit user confirmation before running.
  static const _kDangerousCommands = {
    'rm', 'rmdir', 'sudo', 'chmod', 'chown', 'mkfs', 'dd',
    'shutdown', 'reboot', 'halt', 'poweroff', 'kill', 'killall',
    'format', 'fdisk', 'parted', 'shred', 'wipe', 'truncate',
    'curl', 'wget', // network downloads
    'apt', 'apt-get', 'dpkg', 'brew', 'pip', 'npm', 'yarn', 'gradle',
  };

  Future<ToolResult<Map<String, String>>> runShellCommand(
    String command, [
    List<String> args = const [],
    Map<String, String> envs = const {},
  ]) async {
    try {
      final baseCmd = command.split('/').last.split(' ').first.toLowerCase();
      final argsStr = args.isEmpty ? '' : ' ${args.join(' ')}';
      final fullCmdStr = '$command$argsStr'.trim();

      if (_kDangerousCommands.contains(baseCmd) || approvalMode == 'default') {
        final confirmed = await _confirmDestructive(
          title: 'Exécuter une commande système ?',
          body: fullCmdStr,
          toolName: 'runShellCommand',
          command: fullCmdStr,
        );
        if (!confirmed) {
          return ToolResult.error('Commande annulée par l\'utilisateur.');
        }
      }

      final env = await _buildAgentShellEnvironment(workspacePath);
      env.addAll(envs);
      final process = await _runGuestShell(fullCmdStr,
          envs: env,
          timeout: const Duration(seconds: 120),
          timeoutLabel: 'runShellCommand "$command"');
      return ToolResult.success({
        "pid": process.pid.toString(),
        "exitCode": process.exitCode.toString(),
        "stdout": process.stdout.toString(),
        "stderr": process.stderr.toString(),
      });
    } catch (e) {
      return ToolResult.error('Error running command: $e');
    }
  }

  WebPageContent _parseWebContent(String htmlString, String url) {
    final document = html.parse(htmlString);
    final title = _extractTitle(document);
    final description = _extractDescription(document);
    final metadata = _extractMetadata(document);
    final headings = _extractHeadings(document);
    final mainContent = _extractMainContent(document);
    final links = _extractLinks(document, url);

    return WebPageContent(
      url: url,
      title: title,
      description: description,
      mainContent: mainContent,
      headings: headings,
      links: links,
      metadata: metadata,
    );
  }

  String _extractTitle(dom.Document document) {
    return document.querySelector('title')?.text.trim() ??
      document.querySelector('meta[property="og:title"]')
        ?.attributes['content']
        ?.trim() ??
      document.querySelector('h1')?.text.trim() ??
      'Untitled Page';
  }

  String? _extractDescription(dom.Document document) {
    return document
            .querySelector('meta[name="description"]')
            ?.attributes['content']
            ?.trim() ??
        document
            .querySelector('meta[property="og:description"]')
            ?.attributes['content']
            ?.trim() ??
        document
            .querySelector('meta[name="twitter:description"]')
            ?.attributes['content']
            ?.trim();
  }

  Map<String, String> _extractMetadata(dom.Document document) {
    final metadata = <String, String>{};
    final author =
      document.querySelector('meta[name="author"]')?.attributes['content']?.trim() ??
      document.querySelector('meta[property="article:author"]')?.attributes['content']?.trim() ??
      document.querySelector('[rel="author"]')?.text.trim();
    if (author != null && author.isNotEmpty) metadata['author'] = author;

    final publishedTime =
      document.querySelector('meta[property="article:published_time"]')?.attributes['content']?.trim() ??
      document.querySelector('time[datetime]')?.attributes['datetime']?.trim();
    if (publishedTime != null && publishedTime.isNotEmpty) {
      metadata['published'] = publishedTime;
    }

    final siteName = document.querySelector('meta[property="og:site_name"]')?.attributes['content']?.trim();
    if (siteName != null && siteName.isNotEmpty) metadata['site_name'] = siteName;

    final type = document.querySelector('meta[property="og:type"]')?.attributes['content']?.trim();
    if (type != null && type.isNotEmpty) metadata['type'] = type;

    final lang = document.documentElement?.attributes['lang']?.trim();
    if (lang != null && lang.isNotEmpty) metadata['language'] = lang;

    return metadata;
  }

  List<String> _extractHeadings(dom.Document document) {
    final headings = <String>[];

    for (final tag in ['h1', 'h2', 'h3']) {
      final elements = document.querySelectorAll(tag);
      for (final el in elements) {
        final text = _cleanText(el.text);
        if (text.isNotEmpty && text.length < 200 && !text.contains('\n')) {
          headings.add(text);
        }
      }
    }

    return headings;
  }

  String _extractMainContent(dom.Document document) {
    dom.Element? mainContent;

    final semanticSelectors = [
      'main',
      'article',
      '[role="main"]',
      '[role="article"]',
    ];

    for (final selector in semanticSelectors) {
      mainContent = document.querySelector(selector);
      if (mainContent != null) break;
    }

    if (mainContent == null) {
      final commonSelectors = [
        '.post-content',
        '.article-content',
        '.entry-content',
        '.content',
        '#content',
        '.main-content',
        '#main-content',
        '.post-body',
        '.article-body',
      ];

      for (final selector in commonSelectors) {
        mainContent = document.querySelector(selector);
        if (mainContent != null && mainContent.text.trim().length > 100) break;
      }
    }

    if (mainContent == null) {
      final candidates = document.querySelectorAll('div, section, article');
      dom.Element? bestCandidate;
      int maxLength = 0;

      for (final candidate in candidates) {
        final clone = candidate.clone(true);
        _removeUnwantedElements(clone);

        final textLength = clone.text.trim().length;
        if (textLength > maxLength && textLength > 200) {
          maxLength = textLength;
          bestCandidate = candidate;
        }
      }

      mainContent = bestCandidate;
    }

    mainContent ??= document.body;

    if (mainContent != null) {
      final clone = mainContent.clone(true);
      _removeUnwantedElements(clone);
      return _cleanText(clone.text);
    }

    return '';
  }

  void _removeUnwantedElements(dom.Element element) {
    final unwantedSelectors = [
      'script',
      'style',
      'noscript',
      'iframe',
      'nav',
      'header',
      'footer',
      'aside',
      '.advertisement',
      '.ad',
      '.ads',
      '.social-share',
      '.comments',
      '.comment-section',
      '[role="navigation"]',
      '[role="banner"]',
      '[role="contentinfo"]',
      '[role="complementary"]',
      '.sidebar',
      '.menu',
      '.nav',
      '.navigation',
    ];

    for (final selector in unwantedSelectors) {
      element.querySelectorAll(selector).forEach((el) => el.remove());
    }
  }

  List<LinkInfo> _extractLinks(dom.Document document, String baseUrl) {
    final links = <LinkInfo>[];
    final seenUrls = <String>{};

    dom.Element? contentArea;
    for (final selector in ['main', 'article', '.content', '#content']) {
      contentArea = document.querySelector(selector);
      if (contentArea != null) break;
    }

    final searchArea = contentArea ?? document.body;
    if (searchArea == null) return links;

    final anchorElements = searchArea.querySelectorAll('a[href]');

    for (final anchor in anchorElements) {
      final href = anchor.attributes['href'];
      final text = _cleanText(anchor.text);

      if (href == null || href.isEmpty || text.isEmpty) continue;
      if (text.length > 100) continue;

      final absoluteUrl = _resolveUrl(href, baseUrl);

      if (seenUrls.contains(absoluteUrl)) continue;
      if (absoluteUrl.startsWith('#')) continue;
      if (absoluteUrl.startsWith('javascript:')) continue;
      if (absoluteUrl.startsWith('mailto:')) continue;

      seenUrls.add(absoluteUrl);
      links.add(LinkInfo(text: text, url: absoluteUrl));

      if (links.length >= 50) break;
    }

    return links;
  }

  String _resolveUrl(String href, String baseUrl) {
    try {
      final base = Uri.parse(baseUrl);
      final resolved = base.resolve(href);
      return resolved.toString();
    } catch (e) {
      return href;
    }
  }

  String _cleanText(String text) {
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
  }

  Future<ToolResult<List<WebResult>>> searchInWeb(String searchQuery) async {
    try {
      final cleanQuery = searchQuery.trim();
      if (cleanQuery.isEmpty) return ToolResult.error('Query parameter cannot be empty');
      final encodedQuery = Uri.encodeComponent(cleanQuery);
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Accept-Language': 'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7',
      };

      final results = <WebResult>[];

      // Helper for cleaning HTML tags and unescaping entities
      String cleanText(String input) {
        if (input.isEmpty) return '';
        var text = input.replaceAll(RegExp(r'<[^>]*>'), '');
        text = text
            .replaceAll('&quot;', '"')
            .replaceAll('&amp;', '&')
            .replaceAll('&#39;', "'")
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&nbsp;', ' ');
        return text.trim();
      }

      // 1. Primary: DuckDuckGo HTML endpoint
      try {
        final url = "https://html.duckduckgo.com/html/?q=$encodedQuery";
        final response = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final document = html.parse(response.body);
          final resultDivs = document.querySelectorAll('.result');
          for (final div in resultDivs) {
            final titleAnchor = div.querySelector('.result__a');
            final snippetEl = div.querySelector('.result__snippet');
            final urlAnchor = div.querySelector('.result__url');

            if (titleAnchor == null) continue;

            final title = cleanText(titleAnchor.text);
            final snippet = cleanText(snippetEl?.text ?? '');
            String? realUrl;

            if (urlAnchor != null) {
              final rawHref = urlAnchor.attributes['href'] ?? titleAnchor.attributes['href'];
              if (rawHref != null) {
                if (rawHref.contains('uddg=')) {
                  try {
                    final uri = Uri.parse(rawHref.startsWith('//') ? 'https:$rawHref' : rawHref);
                    final uddg = uri.queryParameters['uddg'];
                    if (uddg != null) realUrl = Uri.decodeComponent(uddg);
                  } catch (_) {}
                }
                realUrl ??= rawHref.startsWith('//') ? 'https:$rawHref' : rawHref;
              }
            }

            if (title.isNotEmpty && realUrl != null) {
              results.add(WebResult(title: title, url: realUrl, snippet: snippet));
            }
          }
        }
      } catch (e) {
        debugPrint('searchInWeb Primary DDG HTML search failed: $e');
      }

      // 2. Fallback / Source: DuckDuckGo Lite endpoint
      if (results.length < 3) {
        try {
          final url = "https://lite.duckduckgo.com/lite/?q=$encodedQuery";
          final response = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 6));
          if (response.statusCode == 200) {
            final document = html.parse(response.body);
            final rows = document.querySelectorAll('tr');
            String lastTitle = '';
            String lastUrl = '';
            for (final row in rows) {
              final link = row.querySelector('a.result-link');
              final snippetTd = row.querySelector('td.result-snippet');
              if (link != null) {
                lastTitle = cleanText(link.text);
                lastUrl = link.attributes['href'] ?? '';
              } else if (snippetTd != null && lastTitle.isNotEmpty) {
                results.add(WebResult(title: lastTitle, url: lastUrl, snippet: cleanText(snippetTd.text)));
                lastTitle = '';
                lastUrl = '';
              }
            }
          }
        } catch (e) {
          debugPrint('searchInWeb DDG Lite fallback failed: $e');
        }
      }

      // 3. Fallback / Source: Wikipedia Search API (FR + EN)
      if (results.length < 4) {
        for (final lang in ['fr', 'en']) {
          try {
            final wikiUrl = "https://$lang.wikipedia.org/w/api.php?action=query&list=search&srsearch=$encodedQuery&format=json&origin=*";
            final response = await http.get(Uri.parse(wikiUrl)).timeout(const Duration(seconds: 5));
            if (response.statusCode == 200) {
              final data = jsonDecode(response.body) as Map<String, dynamic>;
              final searchList = (data['query']?['search'] as List?) ?? [];
              for (final item in searchList.take(3)) {
                final pageTitle = item['title']?.toString() ?? '';
                final pageSnippet = cleanText(item['snippet']?.toString() ?? '');
                if (pageTitle.isNotEmpty) {
                  final wikiPageUrl = "https://$lang.wikipedia.org/wiki/${Uri.encodeComponent(pageTitle)}";
                  results.add(WebResult(
                    title: "$pageTitle - Wikipedia (${lang.toUpperCase()})",
                    url: wikiPageUrl,
                    snippet: pageSnippet,
                  ));
                }
              }
            }
          } catch (e) {
            debugPrint('searchInWeb Wikipedia $lang fallback failed: $e');
          }
        }
      }

      // 4. Fallback / Source: Pub.dev API (Flutter/Dart)
      final lowerQuery = cleanQuery.toLowerCase();
      if (results.length < 5 && (lowerQuery.contains('flutter') || lowerQuery.contains('dart') || lowerQuery.contains('pub') || lowerQuery.contains('package') || lowerQuery.contains('widget'))) {
        try {
          final pubUrl = "https://pub.dev/api/search?q=$encodedQuery";
          final response = await http.get(Uri.parse(pubUrl)).timeout(const Duration(seconds: 5));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final packages = (data['packages'] as List?) ?? [];
            for (final pkg in packages.take(3)) {
              final pkgName = pkg['package']?.toString() ?? '';
              if (pkgName.isNotEmpty) {
                results.add(WebResult(
                  title: "$pkgName | Pub.dev Package",
                  url: "https://pub.dev/packages/$pkgName",
                  snippet: "Package Dart/Flutter $pkgName disponible sur Pub.dev",
                ));
              }
            }
          }
        } catch (e) {
          debugPrint('searchInWeb Pub.dev API fallback failed: $e');
        }
      }

      // 5. Fallback / Source: NPM Search API (JavaScript / Node)
      if (results.length < 5 && (lowerQuery.contains('npm') || lowerQuery.contains('js') || lowerQuery.contains('react') || lowerQuery.contains('node') || lowerQuery.contains('ts'))) {
        try {
          final npmUrl = "https://registry.npmjs.org/-/v1/search?text=$encodedQuery&size=4";
          final response = await http.get(Uri.parse(npmUrl)).timeout(const Duration(seconds: 5));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final objects = (data['objects'] as List?) ?? [];
            for (final obj in objects) {
              final pkg = obj['package'] as Map<String, dynamic>?;
              if (pkg != null) {
                final name = pkg['name']?.toString() ?? '';
                final desc = cleanText(pkg['description']?.toString() ?? '');
                final link = pkg['links']?['npm']?.toString() ?? "https://www.npmjs.com/package/$name";
                if (name.isNotEmpty) {
                  results.add(WebResult(
                    title: "$name - NPM Package",
                    url: link,
                    snippet: desc,
                  ));
                }
              }
            }
          }
        } catch (e) {
          debugPrint('searchInWeb NPM API fallback failed: $e');
        }
      }

      // 6. Fallback / Source: GitHub Repository Search
      if (results.isEmpty || lowerQuery.contains('github') || lowerQuery.contains('repo') || lowerQuery.contains('code')) {
        try {
          final ghUrl = "https://api.github.com/search/repositories?q=$encodedQuery&per_page=5";
          final ghHeaders = {...headers, 'Accept': 'application/vnd.github.v3+json'};
          final response = await http.get(Uri.parse(ghUrl), headers: ghHeaders).timeout(const Duration(seconds: 6));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final items = data['items'] as List? ?? [];
            for (final item in items) {
              results.add(WebResult(
                title: item['full_name']?.toString() ?? '',
                url: item['html_url']?.toString() ?? '',
                snippet: cleanText(item['description']?.toString() ?? 'Dépôt GitHub'),
              ));
            }
          }
        } catch (e) {
          debugPrint('searchInWeb GitHub API fallback failed: $e');
        }
      }

      // Deduplicate results by URL and title
      final uniqueResults = <WebResult>[];
      final seenUrls = <String>{};
      final seenTitles = <String>{};

      for (final res in results) {
        final normUrl = res.url.trim().toLowerCase();
        final normTitle = res.title.trim().toLowerCase();
        if (normUrl.isEmpty || seenUrls.contains(normUrl) || (normTitle.isNotEmpty && seenTitles.contains(normTitle))) {
          continue;
        }
        seenUrls.add(normUrl);
        if (normTitle.isNotEmpty) seenTitles.add(normTitle);
        uniqueResults.add(res);
      }

      if (uniqueResults.isEmpty) {
        return ToolResult.success([
          WebResult(
            title: 'Aucun résultat web direct',
            url: 'https://duckduckgo.com/?q=$encodedQuery',
            snippet: 'Aucun résultat direct pour "$cleanQuery".',
          )
        ]);
      }

      return ToolResult.success(uniqueResults);
    } catch (e) {
      return ToolResult.error('Erreur lors de la recherche web: $e');
    }
  }

  
  Future<ToolResult<String>> getSecret(String name) async {
    try {
      if (name.isEmpty) return ToolResult.error('Secret name cannot be empty.');
      final prefs = await SharedPreferences.getInstance();
      final secretJson = prefs.getString('agent_secrets') ?? '{}';
      final Map<String, dynamic> secretsMap = jsonDecode(secretJson);
      if (secretsMap.containsKey(name) && secretsMap[name].toString().isNotEmpty) {
        return ToolResult.success(secretsMap[name].toString());
      }
      if (Platform.environment.containsKey(name)) {
        return ToolResult.success(Platform.environment[name]!);
      }
      final envFile = File('$workspacePath/.env');
      if (await envFile.exists()) {
        final lines = await envFile.readAsLines();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('#') || !trimmed.contains('=')) continue;
          final parts = trimmed.split('=');
          if (parts[0].trim() == name) {
            final val = parts.sublist(1).join('=').trim().replaceAll('"', '').replaceAll("'", '');
            return ToolResult.success(val);
          }
        }
      }
      return ToolResult.error('Secret "$name" is not configured.');
    } catch (e) {
      return ToolResult.error('Error getting secret "$name": $e');
    }
  }

  Future<ToolResult<List<String>>> listSecrets() async {
    try {
      final names = <String>{};
      final prefs = await SharedPreferences.getInstance();
      final secretJson = prefs.getString('agent_secrets') ?? '{}';
      final Map<String, dynamic> secretsMap = jsonDecode(secretJson);
      names.addAll(secretsMap.keys);

      for (final key in Platform.environment.keys) {
        if (key.contains('TOKEN') || key.contains('KEY') || key.contains('SECRET') || key.contains('PAT') || key.contains('GITHUB')) {
          names.add(key);
        }
      }

      final envFile = File('$workspacePath/.env');
      if (await envFile.exists()) {
        final lines = await envFile.readAsLines();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('#') || !trimmed.contains('=')) continue;
          names.add(trimmed.split('=')[0].trim());
        }
      }
      return ToolResult.success(names.toList());
    } catch (e) {
      return ToolResult.error('Error listing secrets: $e');
    }
  }

  Future<ToolResult<Map<String, String>>> getAgentSkills() async {
    try {
      final skills = <String, String>{};
      final dirs = [
        '$workspacePath/.panda/skills',
        '$workspacePath/.agents/skills',
        '$workspacePath/skills',
      ];
      for (final dirPath in dirs) {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File && entity.path.endsWith('SKILL.md')) {
              final skillName = path.basename(entity.parent.path);
              skills[skillName] = entity.path;
            }
          }
        }
      }
      return ToolResult.success(skills);
    } catch (e) {
      return ToolResult.error('Error listing agent skills: $e');
    }
  }

  Future<ToolResult<String>> useAgentSkill(String skillName) async {
    try {
      final skillsRes = await getAgentSkills();
      if (!skillsRes.success || skillsRes.data == null) {
        return ToolResult.error('No agent skills found.');
      }
      final filePath = skillsRes.data![skillName];
      if (filePath == null) {
        return ToolResult.error('Skill "$skillName" not found. Available skills: ${skillsRes.data!.keys.join(", ")}');
      }
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        return ToolResult.success(content);
      }
      return ToolResult.error('Skill file not found at $filePath');
    } catch (e) {
      return ToolResult.error('Error using skill "$skillName": $e');
    }
  }

  List<Map<String, dynamic>> getTools({bool readAccessOnly = false}) {
    return _applyToolSelectionFilter([
      {
        "type": "function",
        "function": {
          "name": "activeEditorFile",
          "description":
              "Gets the path of the currently active/opened editor file",
          "parameters": {"type": "object", "properties": {}},
        },
      },
      {
        "type": "function",
        "function": {
          "name": "currentlySelectedText",
          "description":
              "Gets the currently selected text in the active/opened editor",
          "parameters": {"type": "object", "properties": {}},
        },
      },
      if (_hasLspDiagnosticsAvailability())
        {
          "type": "function",
          "function": {
            "name": "getLspDiagnostics",
            "description":
                "Gets diagnostics from LSP-enabled open editors including message, severity and exact range location.",
            "parameters": {
              "type": "object",
              "properties": {
                "filePath": {
                  "type": "string",
                  "description":
                      "Optional file path. If provided, diagnostics are returned only for that open file.",
                },
              },
            },
          },
        },
      {
        "type": "function",
        "function": {
          "name": "readFile",
          "description": "Reads the contents of a file",
          "parameters": {
            "type": "object",
            "properties": {
              "filePath": {
                "type": "string",
                "description": "The path to the file to read",
              },
              "startLine": {
                "type": "integer",
                "description": "Optional start line number (1-indexed)",
              },
              "endLine": {
                "type": "integer",
                "description": "Optional end line number (1-indexed)",
              },
            },
            "required": ["filePath"],
          },
        },
      },
      if (!readAccessOnly)
        {
          "type": "function",
          "function": {
            "name": "deleteFile",
            "description": "Deletes a file from the workspace",
            "parameters": {
              "type": "object",
              "properties": {
                "filePath": {
                  "type": "string",
                  "description": "The path to the file to delete",
                },
              },
              "required": ["filePath"],
            },
          },
        },
      if (!readAccessOnly)
        {
          "type": "function",
          "function": {
            "name": "rename",
            "description": "Renames or moves a file/directory path",
            "parameters": {
              "type": "object",
              "properties": {
                "oldPath": {
                  "type": "string",
                  "description": "The current path",
                },
                "newPath": {
                  "type": "string",
                  "description": "The destination path",
                },
              },
              "required": ["oldPath", "newPath"],
            },
          },
        },
      if (!readAccessOnly)
        {
          "type": "function",
          "function": {
            "name": "renamePath",
            "description": "Renames or moves a file/directory path",
            "parameters": {
              "type": "object",
              "properties": {
                "oldPath": {
                  "type": "string",
                  "description": "The current path",
                },
                "newPath": {
                  "type": "string",
                  "description": "The destination path",
                },
              },
              "required": ["oldPath", "newPath"],
            },
          },
        },
      if (!readAccessOnly)
        {
          "type": "function",
          "function": {
            "name": "insertAtLine",
            "description":
                "Inserts text before or after a specific 1-indexed line with pending diff tracking",
            "parameters": {
              "type": "object",
              "properties": {
                "filePath": {
                  "type": "string",
                  "description": "The path to the file",
                },
                "line": {
                  "type": "integer",
                  "description": "1-indexed line number",
                },
                "text": {
                  "type": "string",
                  "description": "The text to insert",
                },
                "position": {
                  "type": "string",
                  "description": "Insert position: before or after",
                },
              },
              "required": ["filePath", "line", "text"],
            },
          },
        },
      if (!readAccessOnly)
        {
          "type": "function",
          "function": {
            "name": "replaceAllInFile",
            "description":
                "Replaces all matching text in a file with pending diff tracking",
            "parameters": {
              "type": "object",
              "properties": {
                "filePath": {
                  "type": "string",
                  "description": "The path to the file",
                },
                "oldText": {
                  "type": "string",
                  "description": "Text or regex pattern to replace",
                },
                "newText": {
                  "type": "string",
                  "description": "Replacement text",
                },
                "useRegex": {
                  "type": "boolean",
                  "description": "Treat oldText as regex pattern",
                },
                "maxReplacements": {
                  "type": "integer",
                  "description": "Optional max number of replacements",
                },
                "caseSensitive": {
                  "type": "boolean",
                  "description": "Whether replacement matching is case sensitive",
                },
              },
              "required": ["filePath", "oldText", "newText"],
            },
          },
        },
      {
        "type": "function",
        "function": {
          "name": "readFilesBatch",
          "description":
              "Reads multiple files in one call with optional line ranges",
          "parameters": {
            "type": "object",
            "properties": {
              "files": {
                "type": "array",
                "description": "Array of file read requests",
                "items": {
                  "type": "object",
                  "properties": {
                    "filePath": {"type": "string"},
                    "startLine": {"type": "integer"},
                    "endLine": {"type": "integer"},
                  },
                  "required": ["filePath"],
                },
              },
            },
            "required": ["files"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "globSearchFiles",
          "description": "Finds files by glob pattern",
          "parameters": {
            "type": "object",
            "properties": {
              "pattern": {
                "type": "string",
                "description": "Glob pattern to include",
              },
              "directoryPath": {
                "type": "string",
                "description": "Optional search root directory",
              },
              "excludePatterns": {
                "type": "array",
                "description": "Optional list of glob exclude patterns",
                "items": {"type": "string"},
              },
              "recursive": {
                "type": "boolean",
                "description": "Whether to search recursively",
              },
              "maxResults": {
                "type": "integer",
                "description": "Optional max number of results",
              },
            },
            "required": ["pattern"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "grepInFiles",
          "description":
              "Searches files and returns matching lines with before/after context",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {"type": "string", "description": "Search query"},
              "filePattern": {
                "type": "string",
                "description": "Optional glob pattern to filter files",
              },
              "caseSensitive": {
                "type": "boolean",
                "description": "Whether search is case sensitive",
              },
              "matchWholeWord": {
                "type": "boolean",
                "description": "Whether to match whole words only",
              },
              "useRegex": {
                "type": "boolean",
                "description": "Treat query as regular expression",
              },
              "before": {
                "type": "integer",
                "description": "Number of lines before match",
              },
              "after": {
                "type": "integer",
                "description": "Number of lines after match",
              },
              "maxResults": {
                "type": "integer",
                "description": "Optional max number of results",
              },
            },
            "required": ["query"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "gitStatus",
          "description":
              "Returns git status details including branch, ahead/behind, and changed files",
          "parameters": {"type": "object", "properties": {}},
        },
      },
      {
        "type": "function",
        "function": {
          "name": "gitDiff",
          "description": "Returns git diff output",
          "parameters": {
            "type": "object",
            "properties": {
              "filePath": {
                "type": "string",
                "description": "Optional file path",
              },
              "staged": {
                "type": "boolean",
                "description": "Whether to diff staged changes",
              },
              "contextLines": {
                "type": "integer",
                "description": "Number of context lines",
              },
            },
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "gitLog",
          "description": "Returns recent git commits",
          "parameters": {
            "type": "object",
            "properties": {
              "limit": {
                "type": "integer",
                "description": "Max number of commits",
              },
              "filePath": {
                "type": "string",
                "description": "Optional file path to filter history",
              },
            },
          },
        },
      },
      if (!readAccessOnly)
        {
          "type": "function",
          "function": {
            "name": "writeFile",
            "description":
                "Writes content to a file, creating it if it doesn't exist",
            "parameters": {
              "type": "object",
              "properties": {
                "filePath": {
                  "type": "string",
                  "description": "The path to the file to write",
                },
                "content": {
                  "type": "string",
                  "description": "The content to write to the file",
                },
              },
              "required": ["filePath", "content"],
            },
          },
        },
      {
        "type": "function",
        "function": {
          "name": "listFiles",
          "description":
              "Lists files in a directory with optional glob pattern",
          "parameters": {
            "type": "object",
            "properties": {
              "directoryPath": {
                "type": "string",
                "description": "The path to the directory to list",
              },
              "pattern": {
                "type": "string",
                "description": "Optional glob pattern to filter files",
              },
              "recursive": {
                "type": "boolean",
                "description": "Whether to list files recursively",
              },
            },
            "required": ["directoryPath"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "searchInFiles",
          "description":
              "Searches for text content across files in workspace with advanced search options",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {
                "type": "string",
                "description":
                    "The text to search for (can be a regex pattern if useRegex is true)",
              },
              "filePattern": {
                "type": "string",
                "description": "Optional glob pattern to filter files",
              },
              "caseSensitive": {
                "type": "boolean",
                "description": "Whether the search is case sensitive",
              },
              "matchWholeWord": {
                "type": "boolean",
                "description": "Whether to match whole words only",
              },
              "useRegex": {
                "type": "boolean",
                "description":
                    "Whether to treat the query as a regular expression",
              },
            },
            "required": ["query"],
          },
        },
      },
      if (!readAccessOnly)
        {
          "type": "function",
          "function": {
            "name": "editFile",
            "description": "Applies a diff/patch to a file",
            "parameters": {
              "type": "object",
              "properties": {
                "filePath": {
                  "type": "string",
                  "description": "The path to the file to edit",
                },
                "oldText": {
                  "type": "string",
                  "description": "The text to replace",
                },
                "newText": {
                  "type": "string",
                  "description": "The new text to insert",
                },
              },
              "required": ["filePath", "oldText", "newText"],
            },
          },
        },
      {
        "type": "function",
        "function": {
          "name": "getPendingEditsForFile",
          "description": "Gets pending agentic diff hunks for a file",
          "parameters": {
            "type": "object",
            "properties": {
              "filePath": {
                "type": "string",
                "description": "The path to the file",
              },
            },
            "required": ["filePath"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "getFileInfo",
          "description":
              "Gets file/directory information including size and modification time",
          "parameters": {
            "type": "object",
            "properties": {
              "filePath": {
                "type": "string",
                "description": "The path to the file or directory",
              },
            },
            "required": ["filePath"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "openLinks",
          "description":
              "Fetches and parses web page content with structured information extraction",
          "parameters": {
            "type": "object",
            "properties": {
              "url": {
                "type": "string",
                "description": "The URL to fetch and parse",
              },
            },
            "required": ["url"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "getSecret",
          "description": "Retrieves a secret value or API key configured in settings or environment",
          "parameters": {
            "type": "object",
            "properties": {
              "name": {
                "type": "string",
                "description": "Name of secret (e.g. GITHUB_TOKEN, PAT, GEMINI_API_KEY)"
              }
            },
            "required": ["name"]
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "listSecrets",
          "description": "Lists all configured secret keys available to the agent",
          "parameters": {
            "type": "object",
            "properties": {}
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "getAgentSkills",
          "description": "Lists all available agent skills and their file paths",
          "parameters": {
            "type": "object",
            "properties": {}
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "useAgentSkill",
          "description": "Loads and returns instructions for a specific agent skill",
          "parameters": {
            "type": "object",
            "properties": {
              "skillName": {
                "type": "string",
                "description": "Name of skill to load"
              }
            },
            "required": ["skillName"]
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "searchInWeb",
          "description":
              "Searches the web using DuckDuckGo and returns results with title, URL, and snippet",
          "parameters": {
            "type": "object",
            "properties": {
              "searchQuery": {
                "type": "string",
                "description": "The search query to use",
              },
            },
            "required": ["searchQuery"],
          },
        },
      },
      if (!readAccessOnly)
        {
          "type": "function",
          "function": {
            "name": "updateProjectMemory",
            "description":
                "Writes or updates the project memory file at .panda/memory.md. "
                "Use after resolving a significant bug, making a technical decision, "
                "or discovering an important project convention. "
                "The content is injected at the start of every future conversation. "
                "Format: Markdown with sections like '## Décisions techniques', "
                "'## Conventions', '## Fichiers clés', '## Bugs connus'.",
            "parameters": {
              "type": "object",
              "properties": {
                "content": {
                  "type": "string",
                  "description":
                      "Full Markdown content to write to .panda/memory.md. "
                      "This REPLACES the existing file entirely.",
                },
              },
              "required": ["content"],
            },
          },
        },
      if (!readAccessOnly)
        {
          "type": "function",
          "function": {
            "name": "runShellCommand",
            "description":
                "Runs a shell command from the workspace directory and returns stdout/stderr and exit code. IMPORTANT: This app runs on Android, not a full Linux desktop/server environment, so full Linux access is limited. Prefer bundled binaries first. Bundled commands include: clang, clang++, clangloader, node, python, python3, npm, npx, pip, pip3, tsc, kotlinc, git, jar, jarsigner, java, javac, javadoc, javap, jcmd, jconsole, jdb, jdeprscan, jdeps, jfr, jhsdb, jimage, jinfo, jlink, jmap, jmod, jpackage, jps, jrunscript, jstack, jstat, jstatd, jwebserver, keytool, rmiregistry, serialver, bash, sh, ccls, less, pager, git-remote-https, git-remote-http. Basic commands like cd, ls, grep, etc may come from Android PATH and can vary by device. Always plan commands with Android limitations in mind.",
            "parameters": {
              "type": "object",
              "properties": {
                "command": {
                  "type": "string",
                  "description":
                      "Executable to run. Prefer the bundled Android app binaries listed in this tool description.",
                },
                "args": {
                  "type": "array",
                  "description": "Optional command arguments",
                  "items": {"type": "string"},
                },
                "envs": {
                  "type": "object",
                  "description": "Optional environment variables",
                  "additionalProperties": {"type": "string"},
                },
              },
              "required": ["command"],
            },
          },
        },
      ]);
  }

  /// Writes or updates .panda/memory.md in the workspace root.
  /// Content replaces the file entirely.
  Future<ToolResult<String>> updateProjectMemory(String content) async {
    try {
      if (content.trim().isEmpty) {
        return ToolResult.error('content must not be empty');
      }
      final workspace = _canonicalWorkspacePath();
      if (workspace.isEmpty) {
        return ToolResult.error('No workspace path configured');
      }
      final pandaDir = Directory('$workspace/.panda');
      if (!pandaDir.existsSync()) {
        await pandaDir.create(recursive: true);
      }
      final file = File('$workspace/.panda/memory.md');
      await file.writeAsString(content);
      return ToolResult.success('$workspace/.panda/memory.md');
    } catch (e) {
      return ToolResult.error('Error updating project memory: $e');
    }
  }

  RegExp _globToRegex(String glob) {
    String pattern = glob
        .replaceAll('.', r'\.')
        .replaceAll('*', '.*')
        .replaceAll('?', '.');
    return RegExp('^$pattern\$');
  }
}

class ToolResult<T> {
  final bool success;
  final T? data;
  final String? error;

  ToolResult.success(this.data) : success = true, error = null;

  ToolResult.error(this.error) : success = false, data = null;
}

class SearchResult {
  final String filePath;
  final int lineNumber;
  final String lineContent;

  SearchResult({
    required this.filePath,
    required this.lineNumber,
    required this.lineContent,
  });

  Map<String, dynamic> toJson() => {
    "filePath": filePath,
    "lineNumber": lineNumber,
    "lineContent": lineContent,
  };

  @override
  String toString() {
    return toJson().toString();
  }
}

class WebResult {
  final String title;
  final String url;
  final String snippet;

  WebResult({required this.title, required this.url, required this.snippet});

  Map<String, dynamic> toJson() => {
    "title": title,
    "url": url,
    "snippet": snippet,
  };

  @override
  String toString() {
    return '• $title\n  URL: $url\n  Snippet: $snippet\n';
  }
}

class GrepResult {
  final String filePath;
  final int lineNumber;
  final String lineContent;
  final List<String> beforeContext;
  final List<String> afterContext;

  GrepResult({
    required this.filePath,
    required this.lineNumber,
    required this.lineContent,
    required this.beforeContext,
    required this.afterContext,
  });

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'lineNumber': lineNumber,
    'lineContent': lineContent,
    'beforeContext': beforeContext,
    'afterContext': afterContext,
  };

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

class GitStatusInfo {
  final String branch;
  final int ahead;
  final int behind;
  final List<String> staged;
  final List<String> unstaged;
  final List<String> untracked;
  final List<String> conflicts;

  GitStatusInfo({
    required this.branch,
    required this.ahead,
    required this.behind,
    required this.staged,
    required this.unstaged,
    required this.untracked,
    required this.conflicts,
  });

  Map<String, dynamic> toJson() => {
    'branch': branch,
    'ahead': ahead,
    'behind': behind,
    'staged': staged,
    'unstaged': unstaged,
    'untracked': untracked,
    'conflicts': conflicts,
  };
}

class GitCommitInfo {
  final String hash;
  final String author;
  final String date;
  final String message;

  GitCommitInfo({
    required this.hash,
    required this.author,
    required this.date,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'hash': hash,
    'author': author,
    'date': date,
    'message': message,
  };
}

class FileInfo {
  final String path;
  final int size;
  final DateTime modified;
  final bool isDirectory;

  FileInfo({
    required this.path,
    required this.size,
    required this.modified,
    required this.isDirectory,
  });
}

class WebPageContent {
  final String url;
  final String title;
  final String? description;
  final String mainContent;
  final List<String> headings;
  final List<LinkInfo> links;
  final Map<String, String> metadata;

  WebPageContent({
    required this.url,
    required this.title,
    this.description,
    required this.mainContent,
    required this.headings,
    required this.links,
    required this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    if (description != null) 'description': description,
    'content': mainContent,
    'headings': headings,
    'links': links.map((l) => l.toJson()).toList(),
    'metadata': metadata,
  };

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('Title: $title');
    buffer.writeln('URL: $url');
    if (description != null) buffer.writeln('Description: $description');

    if (metadata.isNotEmpty) {
      buffer.writeln('\nMetadata:');
      metadata.forEach((key, value) {
        if (value.isNotEmpty) buffer.writeln('  $key: $value');
      });
    }

    if (headings.isNotEmpty) {
      buffer.writeln('\nHeadings:');
      for (final heading in headings.take(10)) {
        buffer.writeln('  - $heading');
      }
    }

    if (links.isNotEmpty) {
      buffer.writeln('\nImportant Links (${links.length}):');
      for (final link in links.take(10)) {
        buffer.writeln('  - ${link.text}: ${link.url}');
      }
    }

    buffer.writeln('\nContent:');
    buffer.writeln(mainContent);

    return buffer.toString();
  }
}

class LinkInfo {
  final String text;
  final String url;

  LinkInfo({required this.text, required this.url});

  Map<String, dynamic> toJson() => {'text': text, 'url': url};
}
