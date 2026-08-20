import 'dart:async';

import 'package:flutter/material.dart';

import '../../logging/logging.dart';
import '../../utils/themes.dart';

/// Main Logs Explorer page.
class LogsExplorerPage extends StatefulWidget {
  const LogsExplorerPage({super.key});

  @override
  State<LogsExplorerPage> createState() => _LogsExplorerPageState();
}


/// Time formatting helpers (replaces intl dependency)
String _fmtTime(DateTime dt) {
  String p2(int v) => v.toString().padLeft(2, '0');
  String p3(int v) => v.toString().padLeft(3, '0');
  return '\${p2(dt.hour)}:\${p2(dt.minute)}:\${p2(dt.second)}.\${p3(dt.millisecond)}';
}
String _fmtDateTime(DateTime dt) {
  String p2(int v) => v.toString().padLeft(2, '0');
  return '\${dt.year}-\${p2(dt.month)}-\${p2(dt.day)} \${_fmtTime(dt)}';
}
String _fmtHM(DateTime dt) {
  String p2(int v) => v.toString().padLeft(2, '0');
  return '\${p2(dt.hour)}:\${p2(dt.minute)}';
}
String _fmtTimeShort(DateTime dt) {
  String p2(int v) => v.toString().padLeft(2, '0');
  return '\${p2(dt.hour)}:\${p2(dt.minute)}:\${p2(dt.second)}';
}

class _LogsExplorerPageState extends State<LogsExplorerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool _liveMode = false;
  StreamSubscription<PandaLogEvent>? _liveSub;
  final List<PandaLogEvent> _displayEvents = [];

  PandaLogLevel? _levelFilter;
  PandaLogCategory? _categoryFilter;
  DateTimeRange? _dateRange;

  // Detail panel
  PandaLogEvent? _selectedEvent;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadLogs();
  }

  void _loadLogs() {
    _applyFilters();
  }

  void _applyFilters() {
    _displayEvents.clear();
    var events = PandaLogger.recentEvents.toList();

    if (_levelFilter != null) {
      events = events.where((e) => e.level == _levelFilter).toList();
    }
    if (_categoryFilter != null) {
      events = events.where((e) => e.category == _categoryFilter).toList();
    }
    if (_dateRange != null) {
      events = events
          .where((e) =>
              e.timestamp.isAfter(_dateRange!.start) &&
              e.timestamp.isBefore(_dateRange!.end.add(const Duration(days: 1))))
          .toList();
    }
    if (_searchCtrl.text.isNotEmpty) {
      final q = _searchCtrl.text.toLowerCase();
      events = events
          .where((e) => e.message.toLowerCase().contains(q))
          .toList();
    }

    setState(() => _displayEvents.addAll(events));
  }

  void _toggleLive() {
    setState(() {
      _liveMode = !_liveMode;
      if (_liveMode) {
        _liveSub = PandaLogger.liveStream.listen((event) {
          if (mounted) {
            setState(() {
              _displayEvents.insert(0, event);
              if (_displayEvents.length > 500) _displayEvents.removeLast();
            });
          }
        });
      } else {
        _liveSub?.cancel();
        _liveSub = null;
      }
    });
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xff1a1a24) : const Color(0xfff8f8fc);
    final fg = isDark ? Colors.white : const Color(0xff1a1a2e);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: fg,
        title: Row(
          children: [
            const Icon(Icons.terminal, size: 20),
            const SizedBox(width: 8),
            const Text('Logs Explorer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const Spacer(),
            // Live toggle
            GestureDetector(
              onTap: _toggleLive,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _liveMode
                      ? const Color(0xff10b981).withValues(alpha: 0.2)
                      : (isDark ? const Color(0xff2a2a35) : const Color(0xffe8e8f0)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _liveMode ? const Color(0xff10b981) : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _liveMode ? const Color(0xff10b981) : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text('Live', style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _liveMode ? const Color(0xff10b981) : fg.withValues(alpha: 0.6),
                    )),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: fg,
          unselectedLabelColor: fg.withValues(alpha: 0.5),
          indicatorColor: _kAccent,
          tabs: const [
            Tab(text: 'All Logs'),
            Tab(text: 'Agent Runs'),
            Tab(text: 'Diagnostics'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Search & Filters ──
          _buildFilterBar(isDark, fg),
          // ── Content ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLogsList(isDark, fg),
                _buildAgentRunsTab(isDark, fg),
                _buildDiagnosticsTab(isDark, fg),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool isDark, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1e1e28) : Colors.white,
        border: Border(
          bottom: BorderSide(color: fg.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        children: [
          // Search bar
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => _applyFilters(),
            style: TextStyle(color: fg, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search logs...',
              hintStyle: TextStyle(color: fg.withValues(alpha: 0.4), fontSize: 13),
              prefixIcon: Icon(Icons.search, size: 16, color: fg.withValues(alpha: 0.5)),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, size: 14, color: fg.withValues(alpha: 0.5)),
                      onPressed: () {
                        _searchCtrl.clear();
                        _applyFilters();
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: fg.withValues(alpha: 0.15)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: fg.withValues(alpha: 0.15)),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xff252530) : const Color(0xfff4f4f8),
            ),
          ),
          const SizedBox(height: 6),
          // Level filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', _levelFilter == null, () {
                  setState(() => _levelFilter = null);
                  _applyFilters();
                }),
                for (final level in PandaLogLevel.values)
                  _filterChip(level.label, _levelFilter == level, () {
                    setState(() => _levelFilter = level);
                    _applyFilters();
                  }, color: _colorForLevel(level)),
                const SizedBox(width: 8),
                // Category filter
                PopupMenuButton<PandaLogCategory?>(
                  onSelected: (cat) {
                    setState(() => _categoryFilter = cat);
                    _applyFilters();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _categoryFilter != null
                          ? _kAccent.withValues(alpha: 0.15)
                          : isDark ? const Color(0xff2a2a35) : const Color(0xffe8e8f0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _categoryFilter?.label ?? 'Category',
                          style: TextStyle(
                            fontSize: 10,
                            color: _categoryFilter != null ? _kAccent : fg.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.arrow_drop_down, size: 12, color: fg.withValues(alpha: 0.5)),
                      ],
                    ),
                  ),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: null, child: Text('All Categories')),
                    for (final cat in PandaLogCategory.values)
                      PopupMenuItem(value: cat, child: Text(cat.label)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList(bool isDark, Color fg) {
    if (_displayEvents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 48, color: fg.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text('No logs yet', style: TextStyle(color: fg.withValues(alpha: 0.5), fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              _liveMode ? 'Waiting for events...' : 'Logs will appear here',
              style: TextStyle(color: fg.withValues(alpha: 0.3), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        // Log list
        Expanded(
          flex: _selectedEvent != null ? 2 : 3,
          child: ListView.builder(
            controller: _scrollCtrl,
            itemCount: _displayEvents.length,
            itemBuilder: (context, i) {
              final event = _displayEvents[i];
              final isSelected = _selectedEvent?.id == event.id;
              return _LogEventTile(
                event: event,
                isSelected: isSelected,
                isDark: isDark,
                fg: fg,
                onTap: () => setState(() => _selectedEvent = event),
              );
            },
          ),
        ),
        // Detail panel
        if (_selectedEvent != null)
          Expanded(
            flex: 2,
            child: _DetailPanel(
              event: _selectedEvent!,
              isDark: isDark,
              fg: fg,
              onClose: () => setState(() => _selectedEvent = null),
            ),
          ),
      ],
    );
  }

  Widget _buildAgentRunsTab(bool isDark, Color fg) {
    // Group events by agentRunId
    final runIds = <String>{};
    for (final e in _displayEvents) {
      if (e.agentRunId != null) runIds.add(e.agentRunId!);
    }

    if (runIds.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy, size: 48, color: fg.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text('No agent runs yet', style: TextStyle(color: fg.withValues(alpha: 0.5))),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: runIds.length,
      itemBuilder: (context, i) {
        final runId = runIds.elementAt(i);
        final events = PandaLogger.getLogsForAgentRun(runId);
        return _AgentRunCard(runId: runId, events: events, isDark: isDark, fg: fg);
      },
    );
  }

  Widget _buildDiagnosticsTab(bool isDark, Color fg) {
    final errors = PandaLogger.getErrors(limit: 10);
    final buildLogs = PandaLogger.getRecentBuildLogs(limit: 5);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats cards
          _buildStatsRow(isDark, fg),
          const SizedBox(height: 16),
          // Recent errors
          Text('Recent Errors', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: fg,
          )),
          const SizedBox(height: 8),
          if (errors.isEmpty)
            Text('No errors', style: TextStyle(color: fg.withValues(alpha: 0.4), fontSize: 12))
          else
            for (final e in errors)
              _DiagnosticErrorCard(event: e, isDark: isDark, fg: fg),
          const SizedBox(height: 16),
          // Recent builds
          Text('Recent Builds', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: fg,
          )),
          const SizedBox(height: 8),
          if (buildLogs.isEmpty)
            Text('No builds logged', style: TextStyle(color: fg.withValues(alpha: 0.4), fontSize: 12))
          else
            for (final e in buildLogs)
              _DiagnosticBuildCard(event: e, isDark: isDark, fg: fg),
        ],
      ),
    );
  }

  Widget _buildStatsRow(bool isDark, Color fg) {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final todayErrors = PandaLogger.recentEvents
        .where((e) =>
            e.level == PandaLogLevel.error &&
            e.timestamp.isAfter(todayStart))
        .length;
    final todayWarnings = PandaLogger.recentEvents
        .where((e) =>
            e.level == PandaLogLevel.warning &&
            e.timestamp.isAfter(todayStart))
        .length;

    return Row(
      children: [
        _StatCard(label: 'Errors Today', value: '$todayErrors', color: const Color(0xffef4444), isDark: isDark, fg: fg),
        const SizedBox(width: 8),
        _StatCard(label: 'Warnings', value: '$todayWarnings', color: const Color(0xfff59e0b), isDark: isDark, fg: fg),
        const SizedBox(width: 8),
        _StatCard(label: 'Total', value: '${PandaLogger.recentEvents.length}', color: _kAccent, isDark: isDark, fg: fg),
      ],
    );
  }

  static const _kAccent = Color(0xff6366f1);

  Color _colorForLevel(PandaLogLevel level) {
    switch (level) {
      case PandaLogLevel.debug:   return Colors.grey;
      case PandaLogLevel.trace:   return Colors.grey;
      case PandaLogLevel.info:    return const Color(0xff3b82f6);
      case PandaLogLevel.success: return const Color(0xff10b981);
      case PandaLogLevel.warning: return const Color(0xfff59e0b);
      case PandaLogLevel.error:   return const Color(0xffef4444);
      case PandaLogLevel.fatal:   return const Color(0xffdc2626);
    }
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? (color ?? _kAccent).withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? (color ?? _kAccent).withValues(alpha: 0.4) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: selected ? (color ?? _kAccent) : Colors.grey,
          ),
        ),
      ),
    );
  }
}

// ── Log Event Tile ────────────────────────────────────────────────────────

class _LogEventTile extends StatelessWidget {
  final PandaLogEvent event;
  final bool isSelected;
  final bool isDark;
  final Color fg;
  final VoidCallback onTap;

  const _LogEventTile({
    required this.event,
    required this.isSelected,
    required this.isDark,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final time = _fmtTime(event.timestamp);
    final color = _colorForLevel(event.level);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? _kAccent.withValues(alpha: 0.1)
              : (isDark ? const Color(0xff1e1e28) : Colors.white),
          border: Border(
            bottom: BorderSide(color: fg.withValues(alpha: 0.05)),
            left: BorderSide(color: color, width: 3),
          ),
        ),
        child: Row(
          children: [
            // Level indicator
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 8),
            // Timestamp
            Text(time, style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: fg.withValues(alpha: 0.4),
            )),
            const SizedBox(width: 8),
            // Category badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(event.category.label, style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: fg.withValues(alpha: 0.6),
                fontFamily: 'monospace',
              )),
            ),
            const SizedBox(width: 8),
            // Message
            Expanded(
              child: Text(
                event.message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.8)),
              ),
            ),
            // Duration badge
            if (event.durationMs != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xff10b981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('${event.durationMs}ms', style: const TextStyle(
                  fontSize: 8,
                  color: Color(0xff10b981),
                  fontFamily: 'monospace',
                )),
              ),
            // Exit code
            if (event.exitCode != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  color: event.exitCode == 0
                      ? const Color(0xff10b981).withValues(alpha: 0.1)
                      : const Color(0xffef4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('exit:${event.exitCode}', style: TextStyle(
                  fontSize: 8,
                  color: event.exitCode == 0
                      ? const Color(0xff10b981)
                      : const Color(0xffef4444),
                  fontFamily: 'monospace',
                )),
              ),
          ],
        ),
      ),
    );
  }

  static const _kAccent = Color(0xff6366f1);

  Color _colorForLevel(PandaLogLevel level) {
    switch (level) {
      case PandaLogLevel.debug:   return Colors.grey;
      case PandaLogLevel.trace:   return Colors.grey;
      case PandaLogLevel.info:    return const Color(0xff3b82f6);
      case PandaLogLevel.success: return const Color(0xff10b981);
      case PandaLogLevel.warning: return const Color(0xfff59e0b);
      case PandaLogLevel.error:   return const Color(0xffef4444);
      case PandaLogLevel.fatal:   return const Color(0xffdc2626);
    }
  }
}

// ── Detail Panel ──────────────────────────────────────────────────────────

class _DetailPanel extends StatelessWidget {
  final PandaLogEvent event;
  final bool isDark;
  final Color fg;
  final VoidCallback onClose;

  const _DetailPanel({
    required this.event,
    required this.isDark,
    required this.fg,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1a1a24) : const Color(0xfff0f0f8),
        border: Border(left: BorderSide(color: fg.withValues(alpha: 0.1))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: fg.withValues(alpha: 0.1))),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: _colorForLevel(event.level)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Log Detail',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 14, color: fg.withValues(alpha: 0.5)),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('Level', event.level.label, _colorForLevel(event.level)),
                  _detailRow('Category', event.category.label),
                  _detailRow('Time', _fmtDateTime(event.timestamp)),
                  _detailRow('Message', event.message),
                  if (event.sessionId != null) _detailRow('Session', event.sessionId!),
                  if (event.agentRunId != null) _detailRow('Agent Run', event.agentRunId!),
                  if (event.toolCallId != null) _detailRow('Tool Call', event.toolCallId!),
                  if (event.source != null) _detailRow('Source', event.source!),
                  if (event.durationMs != null) _detailRow('Duration', '${event.durationMs}ms'),
                  if (event.filePath != null) _detailRow('File', event.filePath!),
                  if (event.line != null) _detailRow('Line', '${event.line}:${event.column ?? 0}'),
                  if (event.command != null) _detailRow('Command', event.command!),
                  if (event.cwd != null) _detailRow('CWD', event.cwd!),
                  if (event.exitCode != null) _detailRow('Exit Code', '${event.exitCode}'),
                  if (event.metadata != null && event.metadata!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Metadata', style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.6),
                    )),
                    const SizedBox(height: 4),
                    ...event.metadata!.entries.map((e) =>
                        _detailRow(e.key, '${e.value}')),
                  ],
                  if (event.error != null) ...[
                    const SizedBox(height: 8),
                    Text('Error', style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xffef4444),
                    )),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xffef4444).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(event.error!, style: TextStyle(
                        fontSize: 11, fontFamily: 'monospace', color: fg,
                      )),
                    ),
                  ],
                  if (event.stackTrace != null) ...[
                    const SizedBox(height: 8),
                    Text('Stack Trace', style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.6),
                    )),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xff252530) : const Color(0xffe8e8f0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectableText(
                        event.stackTrace!,
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: fg.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(
              fontSize: 10,
              color: fg.withValues(alpha: 0.5),
            )),
          ),
          Expanded(
            child: Text(value, style: TextStyle(
              fontSize: 11,
              color: color ?? fg.withValues(alpha: 0.9),
              fontFamily: label == 'Command' || label == 'CWD' ? 'monospace' : null,
            )),
          ),
        ],
      ),
    );
  }

  Color _colorForLevel(PandaLogLevel level) {
    switch (level) {
      case PandaLogLevel.debug:   return Colors.grey;
      case PandaLogLevel.trace:   return Colors.grey;
      case PandaLogLevel.info:    return const Color(0xff3b82f6);
      case PandaLogLevel.success: return const Color(0xff10b981);
      case PandaLogLevel.warning: return const Color(0xfff59e0b);
      case PandaLogLevel.error:   return const Color(0xffef4444);
      case PandaLogLevel.fatal:   return const Color(0xffdc2626);
    }
  }
}

// ── Agent Run Card ────────────────────────────────────────────────────────

class _AgentRunCard extends StatelessWidget {
  final String runId;
  final List<PandaLogEvent> events;
  final bool isDark;
  final Color fg;

  const _AgentRunCard({
    required this.runId,
    required this.events,
    required this.isDark,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    final startTime = events.isNotEmpty ? events.first.timestamp : DateTime.now();
    final endTime = events.length > 1 ? events.last.timestamp : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1e1e28) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.smart_toy, size: 14, color: _kAccent),
              const SizedBox(width: 6),
              Text('Run #${runId.substring(0, runId.length.clamp(0, 8))}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
              const Spacer(),
              Text(_fmtTimeShort(startTime), style: TextStyle(
                fontSize: 10, color: fg.withValues(alpha: 0.4), fontFamily: 'monospace',
              )),
            ],
          ),
          const SizedBox(height: 8),
          // Timeline
          for (final event in events) ...[
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _colorForLevel(event.level),
                  ),
                ),
                const SizedBox(width: 8),
                Text(event.category.label, style: TextStyle(
                  fontSize: 9,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: fg.withValues(alpha: 0.5),
                )),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(event.message, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.8))),
                ),
                if (event.durationMs != null)
                  Text('${event.durationMs}ms', style: TextStyle(
                    fontSize: 9, color: const Color(0xff10b981), fontFamily: 'monospace',
                  )),
              ],
            ),
            if (event != events.last)
              Padding(
                padding: const EdgeInsets.only(left: 3.5, top: 2, bottom: 2),
                child: Container(width: 1, height: 10, color: fg.withValues(alpha: 0.15)),
              ),
          ],
        ],
      ),
    );
  }

  static const _kAccent = Color(0xff6366f1);

  Color _colorForLevel(PandaLogLevel level) {
    switch (level) {
      case PandaLogLevel.debug:   return Colors.grey;
      case PandaLogLevel.trace:   return Colors.grey;
      case PandaLogLevel.info:    return const Color(0xff3b82f6);
      case PandaLogLevel.success: return const Color(0xff10b981);
      case PandaLogLevel.warning: return const Color(0xfff59e0b);
      case PandaLogLevel.error:   return const Color(0xffef4444);
      case PandaLogLevel.fatal:   return const Color(0xffdc2626);
    }
  }
}

// ── Diagnostic Cards ──────────────────────────────────────────────────────

class _DiagnosticErrorCard extends StatelessWidget {
  final PandaLogEvent event;
  final bool isDark;
  final Color fg;

  const _DiagnosticErrorCard({required this.event, required this.isDark, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xffef4444).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xffef4444).withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, size: 12, color: Color(0xffef4444)),
              const SizedBox(width: 4),
              Text(_fmtTimeShort(event.timestamp), style: TextStyle(
                fontSize: 10, color: fg.withValues(alpha: 0.4), fontFamily: 'monospace',
              )),
              const SizedBox(width: 6),
              Text(event.category.label, style: TextStyle(
                fontSize: 9, fontFamily: 'monospace', color: fg.withValues(alpha: 0.5),
              )),
            ],
          ),
          const SizedBox(height: 4),
          Text(event.message, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: fg)),
        ],
      ),
    );
  }
}

class _DiagnosticBuildCard extends StatelessWidget {
  final PandaLogEvent event;
  final bool isDark;
  final Color fg;

  const _DiagnosticBuildCard({required this.event, required this.isDark, required this.fg});

  @override
  Widget build(BuildContext context) {
    final success = event.exitCode == 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: (success ? const Color(0xff10b981) : const Color(0xffef4444))
            .withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (success ? const Color(0xff10b981) : const Color(0xffef4444))
              .withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            success ? Icons.check_circle_outline : Icons.error_outline,
            size: 14,
            color: success ? const Color(0xff10b981) : const Color(0xffef4444),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.command ?? 'build', style: TextStyle(
                  fontSize: 11, fontFamily: 'monospace', color: fg,
                )),
                if (event.durationMs != null)
                  Text('${event.durationMs}ms', style: TextStyle(
                    fontSize: 10, color: fg.withValues(alpha: 0.4),
                  )),
              ],
            ),
          ),
          Text(_fmtHM(event.timestamp), style: TextStyle(
            fontSize: 10, color: fg.withValues(alpha: 0.4), fontFamily: 'monospace',
          )),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;
  final Color fg;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xff1e1e28) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: fg.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: color,
            )),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(
              fontSize: 10, color: fg.withValues(alpha: 0.5),
            )),
          ],
        ),
      ),
    );
  }
}
