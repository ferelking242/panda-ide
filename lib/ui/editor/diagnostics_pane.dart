import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:panda/bloc/repo_bloc/repo_bloc.dart';
import 'package:panda/ui/mdview.dart';
import 'package:panda/utils/constants.dart';
import '../webview.dart';
import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../extensions/extension_host.dart';
import '../../terminal/terminal.dart';
import '../../utils/languages.dart';
import '../../utils/functions.dart';
import '../../utils/themes.dart';
import 'status_bar.dart';
import '../widgets.dart';

// Diagnostics pane for editor
// Extracted from editor_page.dart

  Widget _buildDiagnosticSummaryCard({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
    required AppTheme appTheme,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: appTheme.editorPageDrawerBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 5),
            Text(
              '$count',
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: appTheme.editorPageToolColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticSection({
    required String title,
    required List<LspErrors> diagnostics,
    required ActiveEditor editor,
    required AppTheme appTheme,
  }) {
    if (diagnostics.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: appTheme.selectScreenCardTextColor,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        ...diagnostics.map((diag) {
          final severityColor = _diagnosticSeverityColor(diag.severity, appTheme);
          final start = Map<String, dynamic>.from(diag.range['start'] ?? {});
          final line = ((start['line'] as num?) ?? 0).toInt() + 1;
          final character = ((start['character'] as num?) ?? 0).toInt() + 1;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  final offset = _offsetFromLineAndCharacter(
                    editor.controller.text,
                    line - 1,
                    character - 1,
                  );
                  editor.controller.selection = TextSelection.collapsed(
                    offset: offset,
                  );
                  _showDiagnosticDetailsSheet(
                    context,
                    editor,
                    diag,
                    appTheme,
                  );
                },
                child: Ink(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: appTheme.editorPageDrawerBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: severityColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          _diagnosticSeverityIcon(diag.severity),
                          color: severityColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              diag.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: appTheme.selectScreenCardTextColor,
                                fontSize: 14,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Line $line:$character',
                              style: TextStyle(
                                color: appTheme.editorPageToolColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDiagnosticsPane(
    AppTheme appTheme,
    ActiveEditorState editorState,
  ) {
    final activeEditor = _resolveActiveEditor(editorState.activeEditors);
    if (activeEditor == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Open a file to view diagnostics.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: appTheme.editorPageToolColor,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    if (_isPreviewEditor(activeEditor)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Diagnostics are not available for image/SVG/PDF preview tabs.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: appTheme.editorPageToolColor,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    final diagnostics = activeEditor.controller.diagnostics;
    final errors = diagnostics.where((diag) => diag.severity == 1).toList();
    final warnings = diagnostics.where((diag) => diag.severity == 2).toList();
    final infos = diagnostics
      .where((diag) => diag.severity == 3 || diag.severity == 4)
      .toList();

    if (diagnostics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.task_alt_rounded,
                color: appTheme.editorPageToolColor,
                size: 34,
              ),
              const SizedBox(height: 10),
              Text(
                'No diagnostics in this file',
                style: TextStyle(
                  color: appTheme.selectScreenCardTextColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'LSP issues will appear here when available.',
                textAlign: TextAlign.center,
                style: TextStyle(color: appTheme.editorPageToolColor),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      children: [
        Text(
          'DIAGNOSTICS',
          style: TextStyle(
            color: appTheme.selectScreenCardTextColor,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildDiagnosticSummaryCard(
              label: 'Errors',
              count: errors.length,
              color: _diagnosticSeverityColor(1, appTheme),
              icon: _diagnosticSeverityIcon(1),
              appTheme: appTheme,
            ),
            const SizedBox(width: 8),
            _buildDiagnosticSummaryCard(
              label: 'Warnings',
              count: warnings.length,
              color: _diagnosticSeverityColor(2, appTheme),
              icon: _diagnosticSeverityIcon(2),
              appTheme: appTheme,
            ),
            const SizedBox(width: 8),
            _buildDiagnosticSummaryCard(
              label: 'Info',
              count: infos.length,
              color: _diagnosticSeverityColor(3, appTheme),
              icon: _diagnosticSeverityIcon(3),
              appTheme: appTheme,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildDiagnosticSection(
          title: 'Errors',
          diagnostics: errors,
          editor: activeEditor,
          appTheme: appTheme,
        ),
        if (errors.isNotEmpty) const SizedBox(height: 8),
        _buildDiagnosticSection(
          title: 'Warnings',
          diagnostics: warnings,
          editor: activeEditor,
          appTheme: appTheme,
        ),
        if (warnings.isNotEmpty) const SizedBox(height: 8),
        _buildDiagnosticSection(
          title: 'Info & Hints',
          diagnostics: infos,
          editor: activeEditor,
          appTheme: appTheme,
        ),
      ],
    );
  }

  Future<void> _saveEditor(
    BuildContext actionContext,
    ActiveEditor editor,
  ) async {
    if (!_isTrackableEditor(editor)) return;

    try {
      editor.controller.saveFile();
      _savedSnapshotByController[editor.controller] = editor.controller.text;
      _dirtyControllers.remove(editor.controller);
      if (mounted) {
        try {
          actionContext.read<RepoStatusBloc>().add(
            LoadRepoStatus(widget.rootDir),
          );
        } catch (_) {}
        setState(() {});
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _saveActiveEditor(
    BuildContext actionContext,
    List<ActiveEditor> editors,
  ) async {
    if (editors.isEmpty) return;

    final activeIndex =
        tabController != null && tabController!.index < editors.length
        ? tabController!.index
        : editors.indexWhere((item) => item.isActive);
    final safeIndex = activeIndex < 0 ? 0 : activeIndex;
    await _saveEditor(actionContext, editors[safeIndex]);
  }

  Future<bool> _handleExitWithUnsavedPrompt(
    BuildContext actionContext,
    List<ActiveEditor> editors,
  ) async {
    final unsavedEditors = editors.where(_isEditorDirty).toList();
    if (unsavedEditors.isEmpty) {
      return true;
    }
    final appTheme = actionContext.read<AppThemeBloc>().state.appTheme;

    final action = await showDialog<String>(
      context: actionContext,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: appTheme.isDark
              ? const Color(0xff2b2b2b)
              : const Color.fromARGB(255, 240, 240, 240),
          icon: const Icon(Icons.warning_amber_rounded, size: 34),
          iconColor: Colors.orange[700],
          title: Text(
            'Unsaved Changes',
            style: TextStyle(
              color: appTheme.selectScreenCardTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          content: Text(
            unsavedEditors.length == 1
                ? 'Save changes to ${path.basename(unsavedEditors.first.file.path)} before exiting?'
                : 'Save changes to ${unsavedEditors.length} files before exiting?',
            style: TextStyle(color: Colors.grey[appTheme.isDark ? 400 : 700]),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: appTheme.editorPageToolColor,
              ),
              onPressed: () => Navigator.of(dialogContext).pop('cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red[400]),
              onPressed: () => Navigator.of(dialogContext).pop('discard'),
              child: const Text("Don't Save"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: appTheme.editorPageToolSelectedBgColor,
                foregroundColor: appTheme.editorPageToolSelectedColor,
              ),
              onPressed: () => Navigator.of(dialogContext).pop('save'),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (action == 'cancel' || action == null) {
      return false;
    }

    if (action == 'save' && context.mounted) {
      for (final editor in unsavedEditors) {
        await _saveEditor(actionContext, editor);
      }
    }

    return true;
  }


  Widget _buildRunPanel(
