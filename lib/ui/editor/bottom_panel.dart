/// VS Code-style Bottom Panel for Panda IDE.
///
/// Tabs: Problems | Output | Debug Console | Terminal
/// The Problems tab shows errors, warnings, infos with file:line:col.
/// Clicking an error navigates to that location.
import 'dart:math';
import 'package:flutter/material.dart';

library;


// ═══════════════════════════════════════════════════════════════
// Bottom Panel Tab
// ═══════════════════════════════════════════════════════════════

enum BottomPanelTab { problems, output, debugConsole, terminal }

// ═══════════════════════════════════════════════════════════════
// Terminal Tab Model (VS Code-style multi-terminal)
// ═══════════════════════════════════════════════════════════════

class TerminalTab {
  final String id;
  String name;
  bool isActive;

  TerminalTab({
    required this.id,
    required this.name,
    this.isActive = false,
  });
}

// ═══════════════════════════════════════════════════════════════
// Diagnostic (Problem)
// ═══════════════════════════════════════════════════════════════

enum DiagnosticSeverity { error, warning, info, hint }

class Diagnostic {
  final String message;
  final DiagnosticSeverity severity;
  final String source; // "dart", "eslint", "pylint", …
  final String? filePath;
  final int line;
  final int column;
  final int? endLine;
  final int? endColumn;
  final String? code;
  final List<DiagnosticRelatedInformation>? relatedInformation;
  final bool hasQuickFix;

  const Diagnostic({
    required this.message,
    required this.severity,
    this.source = '',
    this.filePath,
    this.line = 1,
    this.column = 1,
    this.endLine,
    this.endColumn,
    this.code,
    this.relatedInformation,
    this.hasQuickFix = false,
  });

  Color get color => switch (severity) {
    DiagnosticSeverity.error => const Color(0xFFF14C4C),
    DiagnosticSeverity.warning => const Color(0xFFCCA700),
    DiagnosticSeverity.info => const Color(0xFF75BEFF),
    DiagnosticSeverity.hint => const Color(0xFF808080),
  };

  IconData get icon => switch (severity) {
    DiagnosticSeverity.error => Icons.error,
    DiagnosticSeverity.warning => Icons.warning,
    DiagnosticSeverity.info => Icons.info_outline,
    DiagnosticSeverity.hint => Icons.lightbulb_outline,
  };

  String get location {
    final parts = <String>[];
    if (filePath != null) parts.add(filePath!.split('/').last);
    parts.add('$line:$column');
    return parts.join(':');
  }
}

class DiagnosticRelatedInformation {
  final String message;
  final String? filePath;
  final int line;

  const DiagnosticRelatedInformation({
    required this.message,
    this.filePath,
    this.line = 1,
  });
}

// ═══════════════════════════════════════════════════════════════
// Bottom Panel State
// ═══════════════════════════════════════════════════════════════

class BottomPanelState {
  final BottomPanelTab activeTab;
  final List<Diagnostic> diagnostics;
  final bool isVisible;
  final double height;
  final List<TerminalTab> terminalTabs;
  final String? activeTerminalId;

  const BottomPanelState({
    this.activeTab = BottomPanelTab.problems,
    this.diagnostics = const [],
    this.isVisible = false,
    this.height = 200,
    this.terminalTabs = const [],
    this.activeTerminalId,
  });

  BottomPanelState copyWith({
    BottomPanelTab? activeTab,
    List<Diagnostic>? diagnostics,
    bool? isVisible,
    double? height,
    List<TerminalTab>? terminalTabs,
    String? activeTerminalId,
  }) {
    return BottomPanelState(
      activeTab: activeTab ?? this.activeTab,
      diagnostics: diagnostics ?? this.diagnostics,
      isVisible: isVisible ?? this.isVisible,
      height: height ?? this.height,
      terminalTabs: terminalTabs ?? this.terminalTabs,
      activeTerminalId: activeTerminalId ?? this.activeTerminalId,
    );
  }

  int get errorCount => diagnostics.where((d) => d.severity == DiagnosticSeverity.error).length;
  int get warningCount => diagnostics.where((d) => d.severity == DiagnosticSeverity.warning).length;
  int get infoCount => diagnostics.where((d) => d.severity == DiagnosticSeverity.info).length;
}

// ═══════════════════════════════════════════════════════════════
// Bottom Panel Widget
// ═══════════════════════════════════════════════════════════════

class BottomPanel extends StatefulWidget {
  final BottomPanelState state;
  final ValueChanged<BottomPanelState> onUpdate;
  final ValueChanged<Diagnostic>? onDiagnosticTap;
  final Widget? terminalChild;
  final String projectDir;
  final void Function(String id)? onCreateTerminal;
  final void Function(String id)? onCloseTerminal;
  final void Function(String id)? onSwitchTerminal;

  const BottomPanel({
    super.key,
    required this.state,
    required this.onUpdate,
    this.onDiagnosticTap,
    this.terminalChild,
    this.projectDir = '/',
    this.onCreateTerminal,
    this.onCloseTerminal,
    this.onSwitchTerminal,
  });

  @override
  State<BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<BottomPanel> {
  final _filterCtrl = TextEditingController();
  DiagnosticSeverity? _filterSeverity;
  String _filterQuery = '';

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  void _switchTab(BottomPanelTab tab) {
    widget.onUpdate(widget.state.copyWith(activeTab: tab, isVisible: true));
  }

  void _toggle() {
    widget.onUpdate(widget.state.copyWith(isVisible: !widget.state.isVisible));
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Tab bar ──
        _buildTabBar(state, cs),

        // ── Panel content ──
        if (state.isVisible)
          SizedBox(
            height: state.height,
            child: _buildContent(state, cs),
          ),
      ],
    );
  }

  Widget _buildTabBar(BottomPanelState state, ColorScheme cs) {
    return Container(
      height: 35,
      decoration: BoxDecoration(
        color: const Color(0xFF007ACC), // VS Code blue header
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),

          // Tab items
          _tabChip(BottomPanelTab.problems, 'PROBLEMS', state),
          _tabChip(BottomPanelTab.output, 'OUTPUT', state),
          _tabChip(BottomPanelTab.debugConsole, 'DEBUG CONSOLE', state),
          _tabChip(BottomPanelTab.terminal, 'TERMINAL', state),

          const Spacer(),

          // Toggle / minimize
          IconButton(
            icon: Icon(
              state.isVisible ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              size: 16,
              color: Colors.white70,
            ),
            onPressed: _toggle,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            tooltip: state.isVisible ? 'Minimize Panel' : 'Maximize Panel',
          ),
        ],
      ),
    );
  }

  Widget _tabChip(BottomPanelTab tab, String label, BottomPanelState state) {
    final isActive = state.activeTab == tab && state.isVisible;
    final count = tab == BottomPanelTab.problems ? state.diagnostics.length : 0;
    final hasErrors = tab == BottomPanelTab.problems && state.errorCount > 0;

    return GestureDetector(
      onTap: () => _switchTab(tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF1E1E2E)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(0),
          border: Border(
            bottom: BorderSide(
              color: isActive ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: hasErrors
                      ? const Color(0xFFF14C4C)
                      : Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BottomPanelState state, ColorScheme cs) {
    return Container(
      color: const Color(0xFF1E1E2E),
      child: switch (state.activeTab) {
        BottomPanelTab.problems => _buildProblemsTab(state, cs),
        BottomPanelTab.output => _buildOutputTab(cs),
        BottomPanelTab.debugConsole => _buildDebugConsoleTab(cs),
        BottomPanelTab.terminal => _buildTerminalTab(),
      },
    );
  }

  // ── Problems Tab ─────────────────────────────────────────────

  Widget _buildProblemsTab(BottomPanelState state, ColorScheme cs) {
    final filtered = _filterDiagnostics(state.diagnostics);

    return Column(
      children: [
        // Filter bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 26,
                  child: TextField(
                    controller: _filterCtrl,
                    onChanged: (v) => setState(() => _filterQuery = v),
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Filter problems...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                      prefixIcon: Icon(Icons.search, size: 14, color: Colors.white38),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF313244),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Severity filter chips
              _severityChip(DiagnosticSeverity.error, state.errorCount, cs),
              _severityChip(DiagnosticSeverity.warning, state.warningCount, cs),
              _severityChip(DiagnosticSeverity.info, state.infoCount, cs),
            ],
          ),
        ),

        // Diagnostic list
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, size: 32, color: const Color(0xFF4CAF50)),
                      const SizedBox(height: 8),
                      Text(
                        'No problems detected',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) => _buildDiagnosticItem(filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _severityChip(DiagnosticSeverity severity, int count, ColorScheme cs) {
    final isActive = _filterSeverity == severity;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filterSeverity = isActive ? null : severity;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF45475A)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? Colors.white24 : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              switch (severity) {
                DiagnosticSeverity.error => Icons.error,
                DiagnosticSeverity.warning => Icons.warning,
                DiagnosticSeverity.info => Icons.info_outline,
                DiagnosticSeverity.hint => Icons.lightbulb_outline,
              },
              size: 12,
              color: switch (severity) {
                DiagnosticSeverity.error => const Color(0xFFF14C4C),
                DiagnosticSeverity.warning => const Color(0xFFCCA700),
                DiagnosticSeverity.info => const Color(0xFF75BEFF),
                DiagnosticSeverity.hint => const Color(0xFF808080),
              },
            ),
            const SizedBox(width: 3),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticItem(Diagnostic diag) {
    return InkWell(
      onTap: () => widget.onDiagnosticTap?.call(diag),
      hoverColor: const Color(0xFF45475A),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: [
            // Severity icon
            Icon(diag.icon, size: 14, color: diag.color),
            const SizedBox(width: 8),

            // Source + message
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  children: [
                    if (diag.source.isNotEmpty)
                      TextSpan(
                        text: '[${diag.source}] ',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    TextSpan(text: diag.message),
                    if (diag.code != null)
                      TextSpan(
                        text: ' (${diag.code})',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(width: 8),

            // File:line:col
            Text(
              diag.location,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white38,
                fontFamily: 'monospace',
              ),
            ),

            // Quick fix
            if (diag.hasQuickFix) ...[
              const SizedBox(width: 6),
              Icon(Icons.bolt, size: 12, color: const Color(0xFF75BEFF)),
            ],
          ],
        ),
      ),
    );
  }

  List<Diagnostic> _filterDiagnostics(List<Diagnostic> diagnostics) {
    return diagnostics.where((d) {
      if (_filterSeverity != null && d.severity != _filterSeverity) return false;
      if (_filterQuery.isNotEmpty) {
        final q = _filterQuery.toLowerCase();
        return d.message.toLowerCase().contains(q) ||
               d.source.toLowerCase().contains(q) ||
               (d.filePath?.toLowerCase().contains(q) ?? false);
      }
      return true;
    }).toList();
  }

  // ── Output Tab ───────────────────────────────────────────────

  Widget _buildOutputTab(ColorScheme cs) {
    return const Center(
      child: Text(
        'No output',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      ),
    );
  }

  // ── Debug Console Tab ────────────────────────────────────────

  Widget _buildDebugConsoleTab(ColorScheme cs) {
    return const Center(
      child: Text(
        'Debug console is not available',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      ),
    );
  }

  // ── Terminal Tab ─────────────────────────────────────────────

  Widget _buildTerminalTab() {
    final tabs = widget.state.terminalTabs;
    final activeId = widget.state.activeTerminalId;

    return Column(
      children: [
        // Terminal tab bar
        Container(
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFF252526),
            border: Border(
              bottom: BorderSide(color: Color(0xFF3C3C3C), width: 0.5),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 4),
              // Terminal tabs
              for (final tab in tabs)
                _terminalTabChip(tab, activeId == tab.id),
              // New terminal button
              GestureDetector(
                onTap: () {
                  final newId = 'terminal-${DateTime.now().millisecondsSinceEpoch}';
                  final newTabs = [
                    ...tabs,
                    TerminalTab(id: newId, name: 'Terminal ${tabs.length + 1}'),
                  ];
                  widget.onUpdate(widget.state.copyWith(
                    terminalTabs: newTabs,
                    activeTerminalId: newId,
                  ));
                  widget.onCreateTerminal?.call(newId);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: const Icon(Icons.add, size: 14, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
        // Terminal content
        Expanded(
          child: tabs.isEmpty
              ? const Center(
                  child: Text(
                    'No terminal open. Click + to create one.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                )
              : widget.terminalChild ?? const Center(
                  child: Text(
                    'Terminal not available',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _terminalTabChip(TerminalTab tab, bool isActive) {
    return GestureDetector(
      onTap: () {
        widget.onUpdate(widget.state.copyWith(activeTerminalId: tab.id));
        widget.onSwitchTerminal?.call(tab.id);
      },
      onLongPress: () {
        // Show rename/delete menu
        showModalBottomSheet(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit, size: 18),
                  title: const Text('Rename', style: TextStyle(fontSize: 13)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _renameTerminal(tab);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFF14C4C)),
                  title: const Text('Kill Terminal', style: TextStyle(fontSize: 13, color: Color(0xFFF14C4C))),
                  onTap: () {
                    Navigator.pop(ctx);
                    _closeTerminalTab(tab);
                  },
                ),
              ],
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1E1E2E) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tab.name,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _closeTerminalTab(tab),
              child: Icon(
                Icons.close,
                size: 12,
                color: isActive ? Colors.white70 : Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _renameTerminal(TerminalTab tab) {
    final ctrl = TextEditingController(text: tab.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Terminal', style: TextStyle(fontSize: 14)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Terminal name',
            isDense: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              tab.name = ctrl.text.isEmpty ? tab.name : ctrl.text;
              widget.onUpdate(widget.state.copyWith(terminalTabs: [...widget.state.terminalTabs]));
              Navigator.pop(ctx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _closeTerminalTab(TerminalTab tab) {
    final newTabs = widget.state.terminalTabs.where((t) => t.id != tab.id).toList();
    String? newActiveId = widget.state.activeTerminalId;
    if (newActiveId == tab.id) {
      newActiveId = newTabs.isNotEmpty ? newTabs.last.id : null;
    }
    widget.onUpdate(widget.state.copyWith(
      terminalTabs: newTabs,
      activeTerminalId: newActiveId,
    ));
    widget.onCloseTerminal?.call(tab.id);
  }
}
