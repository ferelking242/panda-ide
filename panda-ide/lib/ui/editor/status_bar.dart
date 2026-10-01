// ═══════════════════════════════════════════════════════════════════════════
// PandaStatusBar — barre d'état du Workbench, fidèle à VS Code.
//
// Rendu porté depuis microsoft/vscode (MIT) :
//   * statusbarpart.css : barre fine 22px (26px tactile), police 12px,
//     item max-width 40vw, hover = statusBarItem.hoverBackground,
//     premier/dernier item padding 2px, tabular-nums.
//   * notificationsStatus.ts : cloche à l'extrémité droite (bell →
//     bell-dot si non-lus → bell-slash en DND), tooltip équivalent.
//   * markers.contribution.ts : entrée Problems toujours visible à gauche,
//     compteur compact `✗ N  ⚠ N` (+ infos si > 0), packNumber 999→1K.
//
// Les couleurs proviennent des WorkbenchTokens (dark + light). Les états
// sont TOUS injectés par home.dart depuis les vraies sources (diagnostics,
// RepoStatusBloc, CopilotBloc, PandaNotifications, EditorStatusHub).
//
// Responsive : priorité VS Code — les items secondaires (encodage,
// indentation, fins de ligne) disparaissent avant tout overflow.
// ═══════════════════════════════════════════════════════════════════════════
library;
import 'package:flutter/material.dart';
import '../../extensions/language_feature_router.dart';
import '../workbench/workbench_responsive.dart';
import '../workbench/workbench_tokens.dart';

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
  final VoidCallback? onTap;

  /// compact items use tighter paddings (statusbarpart.css `.compact-*`).
  final bool compact;

  /// Higher priority sorts further left within its side.
  final int priority;

  const StatusEntry({
    required this.id,
    required this.name,
    this.text = '',
    this.icon,
    this.foreground,
    this.onTap,
    this.compact = false,
    this.priority = 0,
  });
}

// ═══════════════════════════════════════════════════════════════
// Main widget — .part.statusbar
// ═══════════════════════════════════════════════════════════════

class PandaStatusBar extends StatelessWidget {
  const PandaStatusBar({
    super.key,
    this.height,

    // ── Left: remote indicator ──
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
  });

  /// Null → auto : 22px desktop, 26px sur écran tactile (pointer_kind).
  final double? height;

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

  Widget _problemsItem(bool dark) {
    return _StatusItemView(
      dark: dark,
      tooltip: problemsTooltip(errorCount, warningCount, infoCount),
      semanticLabel: 'Problèmes : $errorCount erreurs, $warningCount avertissements',
      onTap: onProblemsTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error, size: 13, color: WorkbenchTokens.errorFg),
          const SizedBox(width: 3),
          Text(packNumber(errorCount)),
          const SizedBox(width: 8),
          const Icon(Icons.warning, size: 13, color: WorkbenchTokens.warningFg),
          const SizedBox(width: 3),
          Text(packNumber(warningCount)),
          if (infoCount > 0) ...[
            const SizedBox(width: 8),
            const Icon(Icons.info, size: 13, color: WorkbenchTokens.infoFg),
            const SizedBox(width: 3),
            Text(packNumber(infoCount)),
          ],
        ],
      ),
    );
  }

  Widget _branchItem(bool dark) {
    return _StatusItemView(
      dark: dark,
      tooltip: branchName!,
      semanticLabel: 'Branche Git : $branchName',
      onTap: onBranchTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.merge_type, size: 13),
          const SizedBox(width: 3),
          Flexible(child: Text(branchName!, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget? _syncItem(bool dark) {
    if (!hasUpstream || (unpushedCount == 0 && unpulledCount == 0)) return null;
    return _StatusItemView(
      dark: dark,
      tooltip: '$unpushedCount↑ $unpulledCount↓',
      semanticLabel: 'Synchroniser Git : $unpushedCount à pousser, $unpulledCount à tirer',
      onTap: onSyncTap,
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

  Widget _remoteItem(bool dark) {
    return _StatusItemView(
      dark: dark,
      tooltip: 'Remote: $remoteName',
      semanticLabel: 'Distant : $remoteName',
      onTap: onRemoteTap,
      compact: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.computer, size: 13),
          const SizedBox(width: 3),
          Text(remoteName!),
        ],
      ),
    );
  }

  Widget _workspaceItem(bool dark) {
    return _StatusItemView(
      dark: dark,
      tooltip: workspaceName ?? 'Open Workspace',
      semanticLabel: 'Espace de travail : ${workspaceName ?? "aucun"}',
      onTap: onWorkspaceTap,
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
            Flexible(child: Text(workspaceName!, overflow: TextOverflow.ellipsis)),
          ],
        ],
      ),
    );
  }

  /// État de l'éditeur : Ln/Col (priorité moyenne), indentation / encodage /
  /// fins de ligne (priorité basse — masquées les premières sur mobile).
  List<Widget> _editorStateItems(bool dark, double width) {
    final compact = WorkbenchResponsive.isCompact(width);
    final parts = <Widget>[];
    void add(String? label, String tooltip, String semantics, VoidCallback? onTap,
        {bool lowPriority = false}) {
      if (label == null) return;
      // Priorité basse : masqué en mode compact pour éviter tout overflow.
      if (lowPriority && compact) return;
      parts.add(_StatusItemView(
        dark: dark,
        tooltip: tooltip,
        semanticLabel: '$semantics : $label',
        onTap: onTap,
        child: Text(label),
      ));
    }

    if (cursorLine != null && cursorColumn != null) {
      // Étroit : forme abrégée « 42:17 » ; large : « Ln 42, Col 17 ».
      final label = width < 420
          ? '$cursorLine:$cursorColumn'
          : 'Ln $cursorLine, Col $cursorColumn';
      add(label, 'Go to Line/Column', 'Position curseur', onCursorTap);
    }
    add(language, 'Select Language Mode', 'Langage', onLanguageTap);
    add(indentation, 'Select Indentation', 'Indentation', onIndentationTap,
        lowPriority: true);
    add(encoding, 'Select Encoding', 'Encodage', onEncodingTap, lowPriority: true);
    add(endOfLine, 'Select End of Line Sequence', 'Fins de ligne', onEndOfLineTap,
        lowPriority: true);
    return parts;
  }

  Widget? _aiItem(bool dark) {
    final label = aiLabel;
    if (label == null) return null;
    return _StatusItemView(
      dark: dark,
      tooltip: aiActive
          ? 'Panda AI : $label'
          : 'Panda AI indisponible — $label',
      semanticLabel: 'Assistant AI : $label',
      onTap: onAiTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (aiActive) ...[
            const SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                valueColor: AlwaysStoppedAnimation(WorkbenchTokens.aiActiveFg),
              ),
            ),
          ] else
            Icon(
              Icons.auto_awesome,
              size: 13,
              color: dark ? Colors.white54 : Colors.black38,
            ),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
    );
  }

  /// Bell entry — notificationsStatus.ts updateNotificationsCenterStatusItem().
  Widget _bellItem(bool dark) {
    final hasActivity =
        unreadNotifications > 0 || notificationsInProgress > 0;
    return _StatusItemView(
      dark: dark,
      tooltip: _bellTooltip(),
      semanticLabel: _bellTooltip(),
      onTap: onNotificationsTap,
      compact: true,
      child: doNotDisturb
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_off, size: 14),
                if (hasActivity) Positioned(right: -2, top: -2, child: _bellDot()),
              ],
            )
          : hasActivity
              ? Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications, size: 14),
                    Positioned(right: -2, top: -1, child: _bellDot()),
                  ],
                )
              : const Icon(Icons.notifications, size: 14),
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

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    // Écran tactile → barre légèrement plus haute mais toujours compacte.
    final effectiveHeight =
        height ?? WorkbenchResponsive.statusBarHeight(width, false);

    final leftItems = <Widget>[];
    final rightItems = <Widget>[];

    // ── LEFT (priority order like statusbarModel.ts sort()) ──
    if (remoteName != null) leftItems.add(_remoteItem(dark));
    if (branchName != null) leftItems.add(_branchItem(dark));
    final sync = _syncItem(dark);
    if (sync != null) leftItems.add(sync);

    // Problems entry — always visible (priority 50, medium).
    leftItems.add(_problemsItem(dark));

    // Workspace fallback when no git repo is detected.
    if (branchName == null) leftItems.add(_workspaceItem(dark));

    // ── Extension / custom entries (StatusEntry API) ──
    for (final entry in entries) {
      leftItems.add(_StatusItemView(
        dark: dark,
        tooltip: entry.text.isEmpty ? entry.name : entry.text,
        semanticLabel: entry.name,
        onTap: entry.onTap,
        compact: true,
        child: entry.icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(entry.icon, size: 13, color: entry.foreground),
                  const SizedBox(width: 3),
                  Text(entry.text, style: TextStyle(color: entry.foreground)),
                ],
              )
            : Text(entry.text, style: TextStyle(color: entry.foreground)),
      ));
    }

    // ── RIGHT ──
    rightItems.addAll(_editorStateItems(dark, width));
    final ai = _aiItem(dark);
    if (ai != null) rightItems.insert(0, ai);

    // The bell sits rightmost (priority -Infinity in VS Code).
    rightItems.add(_bellItem(dark));

    return Container(
      height: effectiveHeight,
      decoration: BoxDecoration(
        color: WorkbenchTokens.statusBarBg(dark),
        border: Border(
          top: BorderSide(color: WorkbenchTokens.panelBorderFg(dark), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Région gauche : absorbe l'espace libre et DÉFILE au lieu de
          // déborder quand la branche ou les entrées sont longues.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  const SizedBox(width: 2),
                  ...leftItems,
                ],
              ),
            ),
          ),
          // Essentiels : épinglés à droite, maintenus étroits par les règles
          // de largeur (jamais de débordement sur mobile).
          Row(children: [...rightItems, const SizedBox(width: 2)]),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Individual item — .statusbar-item / .statusbar-item-label
// ═══════════════════════════════════════════════════════════════

class _StatusItemView extends StatefulWidget {
  const _StatusItemView({
    required this.child,
    required this.dark,
    this.tooltip = '',
    this.semanticLabel,
    this.onTap,
    this.compact = false,
  });

  final Widget child;
  final bool dark;
  final String tooltip;

  /// Label Semantics pour l'accessibilité (tooltip suffit sur desktop).
  final String? semanticLabel;
  final VoidCallback? onTap;
  final bool compact;

  @override
  State<_StatusItemView> createState() => _StatusItemViewState();
}

class _StatusItemViewState extends State<_StatusItemView> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _hasCommand => widget.onTap != null;

  Color get _effectiveBackground {
    if (_pressed && _hasCommand) {
      return WorkbenchTokens.statusActive(widget.dark);
    }
    if (_hovered && _hasCommand) {
      return WorkbenchTokens.statusHover(widget.dark);
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    final label = Container(
      // .statusbar-item-label: margin 3px + padding 5px (compact: 3px).
      margin: EdgeInsets.symmetric(horizontal: widget.compact ? 0 : 3),
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 3 : 5),
      height: double.infinity,
      child: DefaultTextStyle(
        style: WorkbenchTokens.statusText(widget.dark),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        child: IconTheme.merge(
          data: IconThemeData(
            size: 13,
            color: WorkbenchTokens.statusBarFg(widget.dark),
          ),
          child: widget.child,
        ),
      ),
    );

    final item = MouseRegion(
      cursor: _hasCommand ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _hasCommand ? (_) => setState(() => _pressed = true) : null,
        onTapCancel:
            _hasCommand ? () => setState(() => _pressed = false) : null,
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
            children: [label],
          ),
        ),
      ),
    );

    // Tooltip sur desktop, Semantics sur mobile/accessibilité.
    if (widget.semanticLabel != null) {
      return Semantics(
        button: _hasCommand,
        label: widget.semanticLabel,
        child: Tooltip(
          message: widget.tooltip,
          waitDuration: const Duration(milliseconds: 650),
          triggerMode: TooltipTriggerMode.longPress,
          child: item,
        ),
      );
    }
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 650),
      triggerMode: TooltipTriggerMode.longPress,
      child: item,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Workspace diagnostics bridge
// ═══════════════════════════════════════════════════════════

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
