/// VS Code status bar — faithful Flutter port.
///
/// Ported from microsoft/vscode (MIT), analyzed locally under
/// `reference/vscode/src/vs/workbench/browser/parts/statusbar/`:
///   - statusbarPart.ts / statusbarModel.ts / statusbarItem.ts
///   - media/statusbarpart.css (metrics: 22px bar, 12px font, item paddings)
///   - common/theme.ts (colors)
///   - contrib/markers/browser/markers.contribution.ts (Problems entry)
///   - browser/parts/notifications/notificationsStatus.ts (bell entry)
///
/// VS Code behaviours replicated here:
///   * Problems entry is ALWAYS visible on the left (priority 50):
///     `✗ N ⚠ N` + `ⓘ N` only when infos > 0, white on the bar color,
///     numbers packed (999+ → "1K", 10K+ → "10K+"),
///     tooltip "Errors: x, Warnings: y" or "No Problems".
///   * Notification bell is ALWAYS visible rightmost:
///     bell → bell-dot when unread/in-progress → bell-slash in DND mode,
///     with the same tooltip logic as notificationsStatus.ts and a beak
///     while the notification center is open.
///   * Items: hover = white @12%, pressed = white @18%, tabular numerals,
///     first-left / last-right edge paddings, max-width 40vw truncation.
///   * Entry kinds (error/warning/prominent/remote/offline) use the
///     darkened backgrounds computed from theme.ts.
library;
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import '../../extensions/language_feature_router.dart';
import '../../extensions/ui/status_bar_manager.dart';





// ═══════════════════════════════════════════════════════════════
// Theme tokens — src/vs/workbench/common/theme.ts
// ═══════════════════════════════════════════════════════════════

abstract final class StatusBarColors {
  /// statusBar.background (dark & light).
  static const Color background = Color(0xff1e1e1e); // dark theme (no blue)

  /// statusBar.noFolderBackground.
  static const Color noFolderBackground = Color(0xFF68217A);

  /// statusBar.foreground.
  static const Color foreground = Color(0xFFFFFFFF);

  /// statusBarItem.hoverBackground — white @ 12%.
  static const Color hoverBackground = Color(0x1FFFFFFF);

  /// statusBarItem.activeBackground — white @ 18%.
  static const Color activeBackground = Color(0x2EFFFFFF);

  // ── Entry kinds (dark values from theme.ts) ──

  /// statusBarItem.errorBackground = darken(editorError.foreground #F14C4C, .4)
  static const Color errorKindBackground = Color(0xFFB00D0D);

  /// statusBarItem.warningBackground = darken(editorWarning.foreground #CCA700, .4)
  static const Color warningKindBackground = Color(0xFF7F6700);

  /// statusBarItem.prominentBackground = black @ 50%.
  static const Color prominentKindBackground = Color(0x80000000);

  /// statusBarItem.remoteBackground = activityBarBadge.background.
  static const Color remoteKindBackground = Color(0xff2d2d2d);

  /// statusBarItem.offlineBackground.
  static const Color offlineKindBackground = Color(0xFF6C1717);
}

enum StatusBarEntryKind { normal, error, warning, prominent, remote, offline }

Color? _kindBackground(StatusBarEntryKind kind) => switch (kind) {
      StatusBarEntryKind.normal => null,
      StatusBarEntryKind.error => StatusBarColors.errorKindBackground,
      StatusBarEntryKind.warning => StatusBarColors.warningKindBackground,
      StatusBarEntryKind.prominent => StatusBarColors.prominentKindBackground,
      StatusBarEntryKind.remote => StatusBarColors.remoteKindBackground,
      StatusBarEntryKind.offline => StatusBarColors.offlineKindBackground,
    };

// ═══════════════════════════════════════════════════════════════
// Generic status entry (extensions / custom app entries)
// ═══════════════════════════════════════════════════════════════

/// A free-form status bar entry, equivalent to VS Code's `IStatusbarEntry`.
class StatusEntry {
  final String id;
  final String name;

  /// Text shown after [icon]. Supports a leading codicon token like
  /// `$(sync) Syncing…` which is mapped to a Material icon.
  final String text;
  final IconData? icon;
  final Color? foreground;
  final StatusBarEntryKind kind;
  final VoidCallback? onTap;

  /// compact items use tighter paddings (statusbarpart.css `.compact-*`).
  final bool compact;

  /// Draws the little triangle notch (`.has-beak`) — used while a popup
  /// anchored to this entry is open.
  final bool showBeak;

  /// Higher priority sorts further left within its side.
  final int priority;

  const StatusEntry({
    required this.id,
    required this.name,
    this.text = '',
    this.icon,
    this.foreground,
    this.kind = StatusBarEntryKind.normal,
    this.onTap,
    this.compact = false,
    this.showBeak = false,
    this.priority = 0,
  });
}

// ═══════════════════════════════════════════════════════════════
// Main widget — .part.statusbar
// ═══════════════════════════════════════════════════════════════

class PandaStatusBar extends StatelessWidget {
  const PandaStatusBar({
    super.key,
    this.height = 22,
    this.background = StatusBarColors.background,

    // ── Left: remote indicator (kind: remote) ──
    this.remoteName,
    this.onRemoteTap,

    // ── Left: git branch + sync ──
    this.branchName,
    this.hasUpstream = false,
    this.unpushedCount = 0,
    this.unpulledCount = 0,
    this.onBranchTap,
    this.onSyncTap,

    // ── Left: problems (always visible, like markers.contribution.ts) ──
    this.errorCount = 0,
    this.warningCount = 0,
    this.infoCount = 0,
    this.onProblemsTap,

    // ── Left: workspace fallback when no branch is available ──
    this.workspaceName,
    this.onWorkspaceTap,

    // ── Right: editor state (each hidden when its data is null) ──
    this.cursorLine,
    this.cursorColumn,
    this.onCursorTap,
    this.indentation,
    this.onIndentationTap,
    this.encoding,
    this.onEncodingTap,
    this.endOfLine,
    this.onEndOfLineTap,
    this.language,
    this.onLanguageTap,

    // ── Right: AI status (hidden when aiLabel == null) ──
    this.aiLabel,
    this.aiActive = false,
    this.onAiTap,

    // ── Right: notifications (always visible) ──
    this.unreadNotifications = 0,
    this.notificationsInProgress = 0,
    this.notificationsCenterOpen = false,
    this.doNotDisturb = false,
    this.onNotificationsTap,

    // ── Generic entries merged with extension-provided ones ──
    this.entries = const <StatusEntry>[],

    /// Invoked for extension entries that declare a command.
    this.onExtensionCommand,
  });

  final double height;
  final Color background;

  final String? remoteName;
  final VoidCallback? onRemoteTap;

  final String? branchName;
  final bool hasUpstream;
  final int unpushedCount;
  final int unpulledCount;
  final VoidCallback? onBranchTap;
  final VoidCallback? onSyncTap;

  final int errorCount;
  final int warningCount;
  final int infoCount;
  final VoidCallback? onProblemsTap;

  final String? workspaceName;
  final VoidCallback? onWorkspaceTap;

  final int? cursorLine;
  final int? cursorColumn;
  final VoidCallback? onCursorTap;
  final String? indentation;
  final VoidCallback? onIndentationTap;
  final String? encoding;
  final VoidCallback? onEncodingTap;
  final String? endOfLine;
  final VoidCallback? onEndOfLineTap;
  final String? language;
  final VoidCallback? onLanguageTap;

  final String? aiLabel;
  final bool aiActive;
  final VoidCallback? onAiTap;

  final int unreadNotifications;
  final int notificationsInProgress;
  final bool notificationsCenterOpen;
  final bool doNotDisturb;
  final VoidCallback? onNotificationsTap;

  final List<StatusEntry> entries;

  final void Function(String command)? onExtensionCommand;

  // ── Problems entry text — markers.contribution.ts getMarkersText() ──

  /// `packNumber`: >9999 → "10K+", >999 → "1K", else plain number.
  static String packNumber(int n) {
    if (n > 9999) return '10K+';
    if (n > 999) return '${n ~/ 1000}K';
    return '$n';
  }

  /// Tooltip: "Errors: x, Warnings: y, Infos: z" or "No Problems".
  static String problemsTooltip(int errors, int warnings, int infos) {
    final titles = <String>[
      if (errors > 0) 'Errors: $errors',
      if (warnings > 0) 'Warnings: $warnings',
      if (infos > 0) 'Infos: $infos',
    ];
    return titles.isEmpty ? 'No Problems' : titles.join(', ');
  }

  /// Tooltip logic of notificationsStatus.ts getTooltip().
  String _bellTooltip() {
    if (doNotDisturb) return 'Do Not Disturb Mode is Enabled';
    if (notificationsCenterOpen) return 'Hide Notifications';
    final unread = unreadNotifications;
    final progress = notificationsInProgress;
    if (unread == 0 && progress == 0) return 'No Notifications';
    if (progress == 0) {
      return unread == 1 ? '1 New Notification' : '$unread New Notifications';
    }
    if (unread == 0) return 'No New Notifications ($progress in progress)';
    if (unread == 1) return '1 New Notification ($progress in progress)';
    return '$unread New Notifications ($progress in progress)';
  }

  Widget _problemsItem() {
    return _StatusItemView(
      tooltip: problemsTooltip(errorCount, warningCount, infoCount),
      onTap: onProblemsTap,
      background: background,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cancel_outlined, size: 13),
          const SizedBox(width: 3),
          Text(packNumber(errorCount)),
          const SizedBox(width: 8),
          const Icon(Icons.warning_amber_outlined, size: 13),
          const SizedBox(width: 3),
          Text(packNumber(warningCount)),
          if (infoCount > 0) ...[
            const SizedBox(width: 8),
            const Icon(Icons.info_outline, size: 13),
            const SizedBox(width: 3),
            Text(packNumber(infoCount)),
          ],
        ],
      ),
    );
  }

  Widget _branchItem() {
    return _StatusItemView(
      tooltip: branchName!,
      onTap: onBranchTap,
      background: background,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.call_split_rounded, size: 13),
          const SizedBox(width: 3),
          Text(branchName!),
        ],
      ),
    );
  }

  Widget? _syncItem() {
    if (!hasUpstream || (unpushedCount == 0 && unpulledCount == 0)) return null;
    return _StatusItemView(
      tooltip: [
        if (unpushedCount > 0) '$unpushedCount↑',
        if (unpulledCount > 0) '$unpulledCount↓',
      ].join(' '),
      onTap: onSyncTap,
      background: background,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sync, size: 13),
          if (unpushedCount > 0) ...[
            const SizedBox(width: 2),
            Text('$unpushedCount↑'),
          ],
          if (unpulledCount > 0) ...[
            const SizedBox(width: 4),
            Text('$unpulledCount↓'),
          ],
        ],
      ),
    );
  }

  Widget _remoteItem() {
    return _StatusItemView(
      tooltip: 'Remote: $remoteName',
      onTap: onRemoteTap,
      background: background,
      kindBackground: remoteName != null ? StatusBarColors.remoteKindBackground : null,
      compact: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.computer_outlined, size: 13),
          const SizedBox(width: 3),
          Text(remoteName!),
        ],
      ),
    );
  }

  Widget _workspaceItem() {
    return _StatusItemView(
      tooltip: workspaceName ?? 'Open Workspace',
      onTap: onWorkspaceTap,
      background: background,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            workspaceName != null
                ? Icons.folder_open_outlined
                : Icons.folder_outlined,
            size: 13,
          ),
          if (workspaceName != null) ...[
            const SizedBox(width: 3),
            Text(workspaceName!),
          ],
        ],
      ),
    );
  }

  Widget? _editorStateItems() {
    final parts = <Widget>[];
    void add(String? label, String tooltip, VoidCallback? onTap) {
      if (label == null) return;
      parts.add(_StatusItemView(
        tooltip: tooltip,
        onTap: onTap,
        background: background,
        child: Text(label),
      ));
    }

    if (cursorLine != null && cursorColumn != null) {
      add('Ln ${cursorLine!}, Col ${cursorColumn!}', 'Go to Line/Column', onCursorTap);
    }
    add(indentation, 'Select Indentation', onIndentationTap);
    add(encoding, 'Select Encoding', onEncodingTap);
    add(endOfLine, 'Select End of Line Sequence', onEndOfLineTap);
    add(language, 'Select Language Mode', onLanguageTap);
    if (parts.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: parts);
  }

  Widget? _aiItem() {
    final label = aiLabel;
    if (label == null) return null;
    return _StatusItemView(
      tooltip: 'AI: $label${aiActive ? '' : ' (offline)'}',
      onTap: onAiTap,
      background: background,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome,
            size: 13,
            color: aiActive ? const Color(0xFF4EC9B0) : Colors.white60,
          ),
          const SizedBox(width: 3),
          Text(label),
        ],
      ),
    );
  }

  /// Bell entry — notificationsStatus.ts updateNotificationsCenterStatusItem().
  Widget _bellItem() {
    final hasActivity =
        unreadNotifications > 0 || notificationsInProgress > 0;
    return _StatusItemView(
      tooltip: _bellTooltip(),
      onTap: onNotificationsTap,
      background: background,
      showBeak: notificationsCenterOpen,
      child: doNotDisturb
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_off_outlined, size: 14),
                if (hasActivity)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: _bellDot(),
                  ),
              ],
            )
          : hasActivity
              ? Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none, size: 14),
                    Positioned(right: -2, top: -1, child: _bellDot()),
                  ],
                )
              : const Icon(Icons.notifications_none, size: 14),
    );
  }

  static Widget _bellDot() => Container(
        width: 5,
        height: 5,
        decoration: const BoxDecoration(
          color: Color(0xFFFFFFFF),
          shape: BoxShape.circle,
        ),
      );

  // ── Extension entries via StatusBarManager (vscode.* API shim) ──

  Widget _extensionEntries({required bool left}) {
    return ListenableBuilder(
      listenable: StatusBarManager.instance,
      builder: (context, _) {
        final items = left
            ? StatusBarManager.instance.leftItems
            : StatusBarManager.instance.rightItems;
        if (items.isEmpty) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              _StatusItemView(
                key: ValueKey('ext-${item.id}-${left ? 'l' : 'r'}'),
                tooltip: item.tooltip ?? item.id,
                onTap:
                    item.command != null && onExtensionCommand != null
                        ? () => onExtensionCommand!(item.command!)
                        : null,
                background: background,
                kindBackground: item.colorHex != null
                    ? item.color.withValues(alpha: 0.25)
                    : null,
                child: Builder(builder: (_) {
                  final parsed = parseCodicon(item.text);
                  final codicon = parsed.$1;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (codicon != null) ...[
                        Icon(codicon, size: 13),
                        if (parsed.$2.isNotEmpty) const SizedBox(width: 3),
                      ],
                      if (parsed.$2.isNotEmpty) Text(parsed.$2),
                    ],
                  );
                }),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final leftItems = <Widget>[];
    final rightItems = <Widget>[];

    // ── LEFT (priority order like statusbarModel.ts sort()) ──
    if (remoteName != null) leftItems.add(_remoteItem());
    if (branchName != null) leftItems.add(_branchItem());
    final sync = _syncItem();
    if (sync != null) leftItems.add(sync);

    // Problems entry — always visible (priority 50, medium).
    leftItems.add(_problemsItem());

    // Workspace fallback when no git repo is detected.
    if (branchName == null) leftItems.add(_workspaceItem());

    leftItems.add(_extensionEntries(left: true));

    // ── RIGHT ──
    for (final entry in entries) {
      rightItems.add(_genericEntry(entry));
    }
    final ai = _aiItem();
    if (ai != null) rightItems.insert(0, ai);
    final editorState = _editorStateItems();
    if (editorState != null) rightItems.insert(0, editorState);

    // The bell sits rightmost (priority -Infinity in VS Code).
    rightItems.add(_bellItem());
    rightItems.add(_extensionEntries(left: false));

    return Container(
      height: height,
      decoration: BoxDecoration(color: background),
      child: Row(
        children: [
          // left-items: flex-grow 1 pushes right items to the far end.
          Expanded(
            child: Row(children: [_edgePadding(left: true), ...leftItems]),
          ),
          Row(children: [...rightItems, _edgePadding(left: false)]),
        ],
      ),
    );
  }

  Widget _edgePadding({required bool left}) {
    // statusbarpart.css: first-visible-item (left) gets padding-left 2px;
    // last-visible-item (right) gets padding-right 2px. Both sides always
    // contain at least one visible entry, so render a constant spacer.
    return const SizedBox(width: 2);
  }

  Widget _genericEntry(StatusEntry entry) {
    return _StatusItemView(
      tooltip: entry.name,
      onTap: entry.onTap,
      background: background,
      foreground: entry.foreground,
      kindBackground: _kindBackground(entry.kind),
      compact: entry.compact,
      showBeak: entry.showBeak,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.icon != null) ...[
            Icon(entry.icon, size: 13),
            if (entry.text.isNotEmpty) const SizedBox(width: 3),
          ],
          if (entry.text.isNotEmpty) Text(entry.text),
        ],
      ),
    );
  }
}

/// Maps a leading `$(codicon)` token to a Material icon, returning
/// `(icon?, remainingText)` — mirrors how VS Code renders `$()` labels.
(IconData?, String) parseCodicon(String raw) {
  final match = RegExp(r'^\$\(([a-z-]+)\)\s*(.*)$').firstMatch(raw.trim());
  if (match == null) return (null, raw);

  const map = <String, IconData>{
    'error': Icons.cancel_outlined,
    'warning': Icons.warning_amber_outlined,
    'info': Icons.info_outline,
    'bell': Icons.notifications_none,
    'sync': Icons.sync,
    'check': Icons.check,
    'pass': Icons.check_circle_outline,
    'circle-check': Icons.check_circle_outline,
    'cloud': Icons.cloud_outlined,
    'cloud-upload': Icons.cloud_upload_outlined,
    'cloud-download': Icons.cloud_download_outlined,
    'remote': Icons.computer_outlined,
    'terminal': Icons.terminal,
    'git-branch': Icons.call_split_rounded,
    'account': Icons.account_circle_outlined,
    'beaker': Icons.science_outlined,
    'rocket': Icons.rocket_launch_outlined,
    'zap': Icons.bolt,
    'shield': Icons.shield_outlined,
    'loading': Icons.refresh,
    'debug-start': Icons.play_arrow_outlined,
    'debug-stop': Icons.stop_outlined,
    'play': Icons.play_arrow_outlined,
    'server': Icons.dns_outlined,
    'broadcast': Icons.podcasts,
  };
  final icon = map[match.group(1)];
  return (icon, match.group(2) ?? '');
}

// ═══════════════════════════════════════════════════════════════
// Workspace diagnostics bridge
// ═══════════════════════════════════════════════════════════════

/// Rebuilds its child whenever workspace diagnostics change
/// ([LanguageFeatureRouter.diagnosticsVersion] — the same source the
/// Problems panel listens to) and exposes error/warning/info counts,
/// mirroring how markers.contribution.ts feeds the Problems entry.
class WorkspaceDiagnosticsListener extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    int errors,
    int warnings,
    int infos,
  ) builder;

  const WorkspaceDiagnosticsListener({super.key, required this.builder});

  @override
  State<WorkspaceDiagnosticsListener> createState() =>
      _WorkspaceDiagnosticsListenerState();
}

class _WorkspaceDiagnosticsListenerState
    extends State<WorkspaceDiagnosticsListener> {
  late final ValueNotifier<int> _version;

  @override
  void initState() {
    super.initState();
    _version = LanguageFeatureRouter.instance.diagnosticsVersion;
    _version.addListener(_onDiagnosticsChanged);
  }

  void _onDiagnosticsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _version.removeListener(_onDiagnosticsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var errors = 0;
    var warnings = 0;
    var infos = 0;
    // ExtensionDiagnostic severity: 0=Error 1=Warning 2=Info 3=Hint.
    LanguageFeatureRouter.instance.allDiagnostics.forEach((_, diags) {
      for (final d in diags) {
        if (d.severity == 0) {
          errors++;
        } else if (d.severity == 1) {
          warnings++;
        } else {
          infos++;
        }
      }
    });
    return widget.builder(context, errors, warnings, infos);
  }
}

// ═══════════════════════════════════════════════════════════════
// Individual item — .statusbar-item / .statusbar-item-label
// ═══════════════════════════════════════════════════════════════

class _StatusItemView extends StatefulWidget {
  const _StatusItemView({
    super.key,
    required this.child,
    required this.background,
    this.tooltip = '',
    this.onTap,
    this.foreground,
    this.kindBackground,
    this.compact = false,
    this.showBeak = false,
  });

  final Widget child;
  final String tooltip;
  final VoidCallback? onTap;
  final Color background;

  /// Item-level foreground override (kind foreground / custom color).
  final Color? foreground;

  /// Full-item background for kinds (error/warning/prominent/remote/…).
  final Color? kindBackground;
  final bool compact;
  final bool showBeak;

  @override
  State<_StatusItemView> createState() => _StatusItemViewState();
}

class _StatusItemViewState extends State<_StatusItemView> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _hasCommand => widget.onTap != null;

  Color get _effectiveForeground =>
      widget.foreground ?? ((widget.kindBackground != null) ? Colors.white : StatusBarColors.foreground);

  Color get _effectiveBackground {
    var base = widget.kindBackground ?? widget.background;
    if (_pressed && _hasCommand) {
      base = Color.alphaBlend(StatusBarColors.activeBackground, base);
    } else if (_hovered && _hasCommand) {
      base = Color.alphaBlend(StatusBarColors.hoverBackground, base);
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    final label = Container(
      // .statusbar-item-label: margin 3px + padding 5px (compact: 3px/5px alt)
      margin: EdgeInsets.symmetric(horizontal: widget.compact ? 0 : 3),
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 3 : 5),
      height: double.infinity,
      child: DefaultTextStyle(
        style: TextStyle(
          // .part.statusbar: font-size 12px; tabular-nums for stable counts.
          fontSize: 12,
          height: 1.0,
          color: _effectiveForeground,
          fontFeatures: const [FontFeature.tabularFigures()],
          overflow: TextOverflow.ellipsis,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        child: IconTheme.merge(
          data: IconThemeData(size: 13, color: _effectiveForeground),
          child: widget.child,
        ),
      ),
    );

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 650),
      triggerMode: TooltipTriggerMode.longPress,
      child: MouseRegion(
        cursor: _hasCommand ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _hasCommand ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: _hasCommand ? () => setState(() => _pressed = false) : null,
          onTapUp: _hasCommand
              ? (_) => setState(() {
                    _pressed = false;
                    widget.onTap?.call();
                  })
              : null,
          child: Container(
            // .statusbar-item: max-width 40vw, full height.
            constraints: BoxConstraints(maxWidth: screenWidth * 0.4),
            height: double.infinity,
            color: _effectiveBackground,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                label,
                if (widget.showBeak)
                  // .has-beak: 10x5 notch centered at the top edge.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: CustomPaint(
                        size: const Size(10, 4),
                        painter: _BeakPainter(color: _effectiveBackground),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BeakPainter extends CustomPainter {
  const _BeakPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BeakPainter oldDelegate) => oldDelegate.color != color;
}

// ═══════════════════════════════════════════════════════════
// Editor status hub (cursor position / language of the active editor)
// ═══════════════════════════════════════════════════════════

/// Global bridge from the editor surface to the status bar.
/// EditorPage pushes the active cursor position + language; home's status
/// bar listens and shows `Ln x, Col y` / the language mode like VS Code.
class EditorStatusHub extends ChangeNotifier {
  static final EditorStatusHub instance = EditorStatusHub._();

  EditorStatusHub._();

  int? cursorLine;
  int? cursorColumn;
  String? language;

  /// Recomputes Ln/Col from [offset] with a single scan (no list split)
  /// and notifies only when something actually changed.
  void updateCursor(String text, int offset, String? languageName) {
    if (offset < 0) offset = 0;
    if (offset > text.length) offset = text.length;

    var line = 1;
    var lastNewline = -1;
    for (var i = 0; i < offset; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        line++;
        lastNewline = i;
      }
    }

    final newColumn = offset - lastNewline;
    if (cursorLine == line &&
        cursorColumn == newColumn &&
        language == languageName) {
      return;
    }

    cursorLine = line;
    cursorColumn = newColumn;
    language = languageName;
    notifyListeners();
  }

  void clear() {
    if (cursorLine == null && cursorColumn == null && language == null) return;
    cursorLine = null;
    cursorColumn = null;
    language = null;
    notifyListeners();
  }
}
