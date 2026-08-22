/// Diagnostics Panel — shows errors, warnings, infos from LSP diagnostics.
library;

import 'package:flutter/material.dart';

/// Severity levels matching LSP protocol.
enum DiagnosticSeverity { error, warning, info, hint }

/// A single diagnostic entry.
class DiagnosticEntry {
  final String file;
  final int line;
  final int column;
  final String message;
  final DiagnosticSeverity severity;
  final String? source;
  final String? code;

  const DiagnosticEntry({
    required this.file,
    required this.line,
    required this.column,
    required this.message,
    required this.severity,
    this.source,
    this.code,
  });

  String get severityLabel {
    switch (severity) {
      case DiagnosticSeverity.error: return 'Error';
      case DiagnosticSeverity.warning: return 'Warning';
      case DiagnosticSeverity.info: return 'Info';
      case DiagnosticSeverity.hint: return 'Hint';
    }
  }
}

/// Manages diagnostics across the workspace.
class DiagnosticsManager {
  final Map<String, List<DiagnosticEntry>> _diagnostics = {};

  /// Callback when diagnostics change.
  void Function()? onUpdate;

  Map<String, List<DiagnosticEntry>> get all => Map.unmodifiable(_diagnostics);

  List<DiagnosticEntry> forFile(String filePath) => _diagnostics[filePath] ?? [];

  List<DiagnosticEntry> get allEntries {
    final entries = <DiagnosticEntry>[];
    for (final list in _diagnostics.values) {
      entries.addAll(list);
    }
    entries.sort((a, b) {
      final severityOrder = {0: 0, 1: 1, 2: 2, 3: 3};
      return (severityOrder[a.severity.index] ?? 0).compareTo(severityOrder[b.severity.index] ?? 0);
    });
    return entries;
  }

  int get errorCount => allEntries.where((e) => e.severity == DiagnosticSeverity.error).length;
  int get warningCount => allEntries.where((e) => e.severity == DiagnosticSeverity.warning).length;
  int get infoCount => allEntries.where((e) => e.severity == DiagnosticSeverity.info).length;

  /// Set diagnostics for a file.
  void set(String filePath, List<DiagnosticEntry> entries) {
    if (entries.isEmpty) {
      _diagnostics.remove(filePath);
    } else {
      _diagnostics[filePath] = entries;
    }
    onUpdate?.call();
  }

  /// Clear all diagnostics.
  void clear() {
    _diagnostics.clear();
    onUpdate?.call();
  }

  /// Clear diagnostics for a file.
  void clearFile(String filePath) {
    _diagnostics.remove(filePath);
    onUpdate?.call();
  }
}

/// Diagnostics panel widget.
class DiagnosticsPanel extends StatelessWidget {
  final DiagnosticsManager manager;
  final void Function(DiagnosticEntry entry)? onJumpToFile;

  const DiagnosticsPanel({
    super.key,
    required this.manager,
    this.onJumpToFile,
  });

  @override
  Widget build(BuildContext context) {
    final entries = manager.allEntries;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
          ),
          child: Row(
            children: [
              if (manager.errorCount > 0)
                _badge(Icons.error_outline, '${manager.errorCount}', Colors.red),
              if (manager.warningCount > 0) ...[
                const SizedBox(width: 8),
                _badge(Icons.warning_amber, '${manager.warningCount}', Colors.orange),
              ],
              if (manager.infoCount > 0) ...[
                const SizedBox(width: 8),
                _badge(Icons.info_outline, '${manager.infoCount}', Colors.blue),
              ],
              if (entries.isEmpty) ...[
                Icon(Icons.check_circle, size: 16, color: Colors.green),
                const SizedBox(width: 6),
                Text('No problems', style: TextStyle(fontSize: 12, color: Colors.green)),
              ],
            ],
          ),
        ),
        // Entries list
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('No diagnostics', style: TextStyle(fontSize: 12)))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) => _buildEntry(entries[i], cs),
                ),
        ),
      ],
    );
  }

  Widget _buildEntry(DiagnosticEntry entry, ColorScheme cs) {
    return InkWell(
      onTap: () => onJumpToFile?.call(entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(_severityIcon(entry.severity), size: 14, color: _severityColor(entry.severity)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.message, style: TextStyle(fontSize: 12, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${entry.file.split('/').last}:${entry.line + 1}', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(count, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  IconData _severityIcon(DiagnosticSeverity s) {
    switch (s) {
      case DiagnosticSeverity.error: return Icons.error_outline;
      case DiagnosticSeverity.warning: return Icons.warning_amber;
      case DiagnosticSeverity.info: return Icons.info_outline;
      case DiagnosticSeverity.hint: return Icons.lightbulb_outline;
    }
  }

  Color _severityColor(DiagnosticSeverity s) {
    switch (s) {
      case DiagnosticSeverity.error: return Colors.red;
      case DiagnosticSeverity.warning: return Colors.orange;
      case DiagnosticSeverity.info: return Colors.blue;
      case DiagnosticSeverity.hint: return Colors.grey;
    }
  }
}
