import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

/// Represents a single timeline entry (file change).
class TimelineEntry {
  final String hash;
  final String message;
  final String author;
  final DateTime date;
  final String? changeType; // 'modified', 'added', 'deleted'

  const TimelineEntry({
    required this.hash,
    required this.message,
    required this.author,
    required this.date,
    this.changeType,
  });
}

/// VS Code-style timeline panel showing file history.
class TimelineView extends StatefulWidget {
  final String filePath;
  final String workspacePath;

  const TimelineView({
    super.key,
    required this.filePath,
    required this.workspacePath,
  });

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  List<TimelineEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final relativePath = p.relative(widget.filePath, from: widget.workspacePath);
      final result = await Process.run(
        'git',
        ['log', '--format=%H%x01%s%x01%an%x01%ai', '--follow', '--', relativePath],
        workingDirectory: widget.workspacePath,
      );
      if (result.exitCode != 0) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final entries = <TimelineEntry>[];
      for (final line in (result.stdout as String).split('\n')) {
        if (line.trim().isEmpty) continue;
        final parts = line.split('\x01');
        if (parts.length >= 4) {
          entries.add(TimelineEntry(
            hash: parts[0],
            message: parts[1],
            author: parts[2],
            date: DateTime.tryParse(parts[3]) ?? DateTime.now(),
          ));
        }
      }
      if (mounted) setState(() { _entries = entries; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Icon(Icons.timeline, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('TIMELINE', style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.5,
              )),
              const Spacer(),
              if (_entries.isNotEmpty)
                Text('${_entries.length}', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _entries.isEmpty
                  ? Center(
                      child: Text(
                        'No history for this file',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _entries.length,
                      itemBuilder: (ctx, i) => _buildEntry(_entries[i], cs),
                    ),
        ),
      ],
    );
  }

  Widget _buildEntry(TimelineEntry entry, ColorScheme cs) {
    final isToday = DateUtils.isSameDay(entry.date, DateTime.now());
    final isYesterday = DateUtils.isSameDay(
      entry.date,
      DateTime.now().subtract(const Duration(days: 1)),
    );
    final dateStr = isToday
        ? 'Today ${DateFormat.Hm().format(entry.date)}'
        : isYesterday
            ? 'Yesterday ${DateFormat.Hm().format(entry.date)}'
            : DateFormat('MMM d, yyyy').format(entry.date);

    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: entry.hash));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Commit ${entry.hash.substring(0, 7)} copied')),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline dot + line
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primary,
                    ),
                  ),
                  Container(width: 1, height: 20, color: cs.outlineVariant),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.message,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.author} • $dateStr',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            // Hash badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.hash.substring(0, 7),
                style: TextStyle(fontSize: 9, fontFamily: 'monospace', color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
