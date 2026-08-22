/// VS Code-style Status Bar for Panda IDE.
///
/// LEFT items (left → right by priority):
///   - Branch name (Git)
///   - Sync status (↑↓)
///   - Errors (❌ red) + Warnings (⚠️ yellow)
///   - Remote indicator
///
/// RIGHT items (left → right by priority):
///   - Notifications bell
///   - Line : Column
///   - Indentation (Spaces: 4)
///   - Encoding (UTF-8)
///   - End of Line (LF)
///   - Language mode (Dart, Python, …)
///   - AI status (connected / model name)
///   - Extension items
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════
// Status Bar Data Model
// ═══════════════════════════════════════════════════════════════

class StatusBarState {
  // Git
  final String branchName;
  final bool gitAhead;
  final bool gitBehind;
  final int gitStagedCount;
  final int gitUnstagedCount;

  // Editor
  final int cursorLine;
  final int cursorColumn;
  final String indentation; // "Spaces: 4", "Tabs: 4"
  final String encoding; // "UTF-8"
  final String endOfLine; // "LF", "CRLF"
  final String language; // "Dart", "Python", …

  // Diagnostics
  final int errorCount;
  final int warningCount;
  final int infoCount;

  // Remote
  final String? remoteIndicator; // "SSH", "WSL", "Container"

  // AI
  final String? aiModelName;
  final bool aiConnected;

  // Notifications
  final int notificationCount;

  // Extension items (from extensions)
  final List<StatusBarItem> extensionItems;

  const StatusBarState({
    this.branchName = '',
    this.gitAhead = false,
    this.gitBehind = false,
    this.gitStagedCount = 0,
    this.gitUnstagedCount = 0,
    this.cursorLine = 1,
    this.cursorColumn = 1,
    this.indentation = 'Spaces: 4',
    this.encoding = 'UTF-8',
    this.endOfLine = 'LF',
    this.language = 'Plain Text',
    this.errorCount = 0,
    this.warningCount = 0,
    this.infoCount = 0,
    this.remoteIndicator,
    this.aiModelName,
    this.aiConnected = false,
    this.notificationCount = 0,
    this.extensionItems = const [],
  });

  StatusBarState copyWith({
    String? branchName,
    bool? gitAhead,
    bool? gitBehind,
    int? gitStagedCount,
    int? gitUnstagedCount,
    int? cursorLine,
    int? cursorColumn,
    String? indentation,
    String? encoding,
    String? endOfLine,
    String? language,
    int? errorCount,
    int? warningCount,
    int? infoCount,
    String? remoteIndicator,
    String? aiModelName,
    bool? aiConnected,
    int? notificationCount,
    List<StatusBarItem>? extensionItems,
  }) {
    return StatusBarState(
      branchName: branchName ?? this.branchName,
      gitAhead: gitAhead ?? this.gitAhead,
      gitBehind: gitBehind ?? this.gitBehind,
      gitStagedCount: gitStagedCount ?? this.gitStagedCount,
      gitUnstagedCount: gitUnstagedCount ?? this.gitUnstagedCount,
      cursorLine: cursorLine ?? this.cursorLine,
      cursorColumn: cursorColumn ?? this.cursorColumn,
      indentation: indentation ?? this.indentation,
      encoding: encoding ?? this.encoding,
      endOfLine: endOfLine ?? this.endOfLine,
      language: language ?? this.language,
      errorCount: errorCount ?? this.errorCount,
      warningCount: warningCount ?? this.warningCount,
      infoCount: infoCount ?? this.infoCount,
      remoteIndicator: remoteIndicator ?? this.remoteIndicator,
      aiModelName: aiModelName ?? this.aiModelName,
      aiConnected: aiConnected ?? this.aiConnected,
      notificationCount: notificationCount ?? this.notificationCount,
      extensionItems: extensionItems ?? this.extensionItems,
    );
  }
}

class StatusBarItem {
  final String id;
  final String text;
  final String? tooltip;
  final Color? color;
  final IconData? icon;
  final VoidCallback? onTap;
  final int priority; // lower = shown first

  const StatusBarItem({
    required this.id,
    required this.text,
    this.tooltip,
    this.color,
    this.icon,
    this.onTap,
    this.priority = 0,
  });
}

// ═══════════════════════════════════════════════════════════════
// Status Bar Provider (InheritedWidget for state access)
// ═══════════════════════════════════════════════════════════════

class StatusBarProvider extends InheritedWidget {
  final StatusBarState state;
  final ValueChanged<StatusBarState> onUpdate;

  const StatusBarProvider({
    super.key,
    required this.state,
    required this.onUpdate,
    required super.child,
  });

  static StatusBarProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<StatusBarProvider>();
  }

  static void update(BuildContext context, StatusBarState newState) {
    of(context)?.onUpdate(newState);
  }

  @override
  bool updateShouldNotify(StatusBarProvider oldWidget) =>
      state != oldWidget.state;
}

// ═══════════════════════════════════════════════════════════════
// Main Status Bar Widget
// ═══════════════════════════════════════════════════════════════

class PandaStatusBar extends StatelessWidget {
  final VoidCallback? onBranchTap;
  final VoidCallback? onErrorsTap;
  final VoidCallback? onWarningsTap;
  final VoidCallback? onLineColTap;
  final VoidCallback? onLanguageTap;
  final VoidCallback? onEncodingTap;
  final VoidCallback? onIndentTap;
  final VoidCallback? onAiStatusTap;
  final VoidCallback? onNotificationsTap;

  const PandaStatusBar({
    super.key,
    this.onBranchTap,
    this.onErrorsTap,
    this.onWarningsTap,
    this.onLineColTap,
    this.onLanguageTap,
    this.onEncodingTap,
    this.onIndentTap,
    this.onAiStatusTap,
    this.onNotificationsTap,
  });

  @override
  Widget build(BuildContext context) {
    final provider = StatusBarProvider.of(context);
    final state = provider?.state ?? const StatusBarState();

    return Container(
      height: 24,
      decoration: const BoxDecoration(
        color: Color(0xFF007ACC), // VS Code blue
      ),
      child: Row(
        children: [
          // ── LEFT ITEMS ──
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Remote indicator
                if (state.remoteIndicator != null)
                  _StatusBarItem(
                    text: state.remoteIndicator!,
                    icon: Icons.computer,
                    tooltip: 'Remote: ${state.remoteIndicator}',
                  ),

                // Git branch
                if (state.branchName.isNotEmpty)
                  _StatusBarItem(
                    icon: Icons.git_branch,
                    text: state.branchName,
                    tooltip: 'Branch: ${state.branchName}',
                    onTap: onBranchTap,
                  ),

                // Sync
                if (state.gitAhead || state.gitBehind)
                  _StatusBarItem(
                    icon: Icons.sync,
                    tooltip: state.gitAhead
                        ? 'Ahead by ${state.gitStagedCount}'
                        : 'Behind by ${state.gitUnstagedCount}',
                  ),

                // Errors
                if (state.errorCount > 0)
                  _StatusBarItem(
                    icon: Icons.error,
                    text: '${state.errorCount}',
                    color: const Color(0xFFF14C4C),
                    tooltip: '${state.errorCount} Error(s)',
                    onTap: onErrorsTap,
                  ),

                // Warnings
                if (state.warningCount > 0)
                  _StatusBarItem(
                    icon: Icons.warning,
                    text: '${state.warningCount}',
                    color: const Color(0xFFCCA700),
                    tooltip: '${state.warningCount} Warning(s)',
                    onTap: onWarningsTap,
                  ),

                // Info
                if (state.infoCount > 0)
                  _StatusBarItem(
                    icon: Icons.info_outline,
                    text: '${state.infoCount}',
                    color: const Color(0xFF75BEFF),
                    tooltip: '${state.infoCount} Info',
                  ),
              ],
            ),
          ),

          // ── RIGHT ITEMS ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // AI status
              if (state.aiModelName != null)
                _StatusBarItem(
                  icon: Icons.auto_awesome,
                  text: state.aiConnected ? state.aiModelName! : 'Offline',
                  color: state.aiConnected
                      ? const Color(0xFF4EC9B0)
                      : const Color(0xFF808080),
                  tooltip: 'AI: ${state.aiModelName}',
                  onTap: onAiStatusTap,
                ),

              // Extension items
              ...state.extensionItems
                  .where((i) => i.id.isNotEmpty)
                  .take(5)
                  .map((item) => _StatusBarItem(
                        text: item.text,
                        icon: item.icon,
                        color: item.color,
                        tooltip: item.tooltip,
                        onTap: item.onTap,
                      )),

              // Notifications bell
              if (state.notificationCount > 0)
                _StatusBarItem(
                  icon: Icons.notifications,
                  text: '${state.notificationCount}',
                  tooltip: 'Notifications',
                  onTap: onNotificationsTap,
                ),

              // Line : Column
              _StatusBarItem(
                text: 'Ln ${state.cursorLine}, Col ${state.cursorColumn}',
                tooltip: 'Go to Line/Column',
                onTap: onLineColTap,
              ),

              // Indentation
              _StatusBarItem(
                text: state.indentation,
                tooltip: 'Select Indentation',
                onTap: onIndentTap,
              ),

              // Encoding
              _StatusBarItem(
                text: state.encoding,
                tooltip: 'Select Encoding',
                onTap: onEncodingTap,
              ),

              // End of Line
              _StatusBarItem(
                text: state.endOfLine,
                tooltip: 'Select End of Line Sequence',
              ),

              // Language mode
              _StatusBarItem(
                text: state.language,
                tooltip: 'Select Language Mode',
                onTap: onLanguageTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Individual Status Bar Item
// ═══════════════════════════════════════════════════════════════

class _StatusBarItem extends StatelessWidget {
  final String? text;
  final IconData? icon;
  final String? tooltip;
  final Color? color;
  final VoidCallback? onTap;

  const _StatusBarItem({
    this.text,
    this.icon,
    this.tooltip,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final itemColor = color ?? Colors.white;

    return Tooltip(
      message: tooltip ?? text ?? '',
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          height: 24,
          decoration: const BoxDecoration(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: itemColor),
                if (text != null) const SizedBox(width: 3),
              ],
              if (text != null)
                Text(
                  text!,
                  style: TextStyle(
                    color: itemColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
