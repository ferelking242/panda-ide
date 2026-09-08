import 'package:flutter/material.dart';

import '../../core/broken_icons.dart';
import '../../utils/agentic_tools.dart';
import '../../utils/editors/edit_hunks.dart';
import 'panda_agent_controller.dart';

/// The pending-edit strip shown between the activity stream and the composer.
///
/// Agentic writes are already applied to the workspace, but their hunks stay
/// pending until the user keeps or rejects them. This widget reads that same
/// store as the editor, so the composer never invents a second change list.
class PandaAgentPendingChangesBar extends StatefulWidget {
  const PandaAgentPendingChangesBar({
    super.key,
    required this.workspacePath,
    this.revision = 0,
  });

  final String workspacePath;
  final int revision;

  @override
  State<PandaAgentPendingChangesBar> createState() =>
      _PandaAgentPendingChangesBarState();
}

class _PandaAgentPendingChangesBarState
    extends State<PandaAgentPendingChangesBar> {
  Map<String, PendingEditFile> _pending = const {};
  bool _expanded = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PandaAgentPendingChangesBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspacePath != widget.workspacePath ||
        oldWidget.revision != widget.revision) {
      _load();
    }
  }

  Future<void> _load() async {
    final all = await PendingEditFile.getAllFromPrefs();
    if (!mounted) return;
    final root = widget.workspacePath.trim();
    final filtered = root.isEmpty
        ? all
        : Map<String, PendingEditFile>.fromEntries(
            all.entries.where(
              (entry) =>
                  entry.key.startsWith(root) || entry.key.startsWith('./'),
            ),
          );
    setState(() => _pending = filtered);
  }

  int _lineCount(String? value) {
    if (value == null || value.isEmpty) return 0;
    return value.split('\n').where((line) => line.isNotEmpty).length;
  }

  ({int added, int removed}) get _counts {
    var added = 0;
    var removed = 0;
    for (final file in _pending.values) {
      for (final hunk in file.editHunks) {
        added += _lineCount(hunk.addedText);
        removed += _lineCount(hunk.removedText);
      }
    }
    return (added: added, removed: removed);
  }

  Future<void> _keepAll() async {
    if (_working) return;
    setState(() => _working = true);
    await PendingEditFile.clearAll();
    if (!mounted) return;
    setState(() {
      _pending = const {};
      _working = false;
    });
  }

  Future<void> _undoAll() async {
    if (_working) return;
    setState(() => _working = true);
    final tools = AgenticTools(
      context: context,
      workspacePath: widget.workspacePath,
    );
    for (final file in _pending.values) {
      await tools.rejectAllPendingEdits(file.filePath);
    }
    if (!mounted) return;
    setState(() {
      _pending = const {};
      _working = false;
    });
  }

  void _showDiff() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fichiers modifiés'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final file in _pending.values) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Broken.document_text, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _shortPath(file.filePath),
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final hunk in file.editHunks) ...[
                  if ((hunk.removedText ?? '').trim().isNotEmpty)
                    _DiffLine(
                      text: hunk.removedText!.trim(),
                      color: colors.error,
                      prefix: '−',
                    ),
                  if ((hunk.addedText ?? '').trim().isNotEmpty)
                    _DiffLine(
                      text: hunk.addedText!.trim(),
                      color: const Color(0xff2c9a4b),
                      prefix: '+',
                    ),
                ],
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Fermer', style: TextStyle(color: theme.colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  String _shortPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.length > 2
        ? '${parts[parts.length - 2]}/${parts.last}'
        : normalized;
  }

  @override
  Widget build(BuildContext context) {
    if (_pending.isEmpty) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    final counts = _counts;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.46),
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.8)),
          bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.8)),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Broken.arrow_down_2
                        : Broken.arrow_right_2,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_pending.length} fichier${_pending.length == 1 ? '' : 's'} modifié${_pending.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (counts.added > 0)
                    Text(
                      '+${counts.added}',
                      style: const TextStyle(
                        color: Color(0xff54d27d),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (counts.removed > 0) ...[
                    const SizedBox(width: 5),
                    Text(
                      '-${counts.removed}',
                      style: const TextStyle(
                        color: Color(0xfff16b78),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const Spacer(),
                  _ActionButton(
                    label: 'Keep',
                    color: const Color(0xff2c9a4b),
                    onPressed: _working ? null : _keepAll,
                  ),
                  const SizedBox(width: 6),
                  _ActionButton(
                    label: 'Undo',
                    color: colors.surfaceContainerHighest,
                    foreground: colors.onSurface,
                    onPressed: _working ? null : _undoAll,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Voir le diff',
                    onPressed: _working ? null : _showDiff,
                    icon: Icon(Broken.copy,
                        size: 19, color: colors.onSurfaceVariant),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 0, 14, 8),
              child: Column(
                children: [
                  for (final file in _pending.values)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _shortPath(file.filePath),
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({
    required this.text,
    required this.color,
    required this.prefix,
  });

  final String text;
  final Color color;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 26, bottom: 2),
      child: Text(
        '$prefix $text',
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.3,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.foreground = Colors.white,
  });

  final String label;
  final Color color;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: foreground,
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

/// Controls below the composer: local execution placeholder, approval mode,
/// and a compact circular context/credit meter.
class PandaAgentComposerFooter extends StatelessWidget {
  const PandaAgentComposerFooter({
    super.key,
    required this.approvalMode,
    required this.usedTokens,
    required this.maxTokens,
    required this.onApprovalTap,
  });

  final String approvalMode;
  final int usedTokens;
  final int maxTokens;
  final VoidCallback onApprovalTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final auto = approvalMode == 'autopilot';
    final usage = maxTokens <= 0 ? 0.0 : (usedTokens / maxTokens).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(Broken.monitor,
              size: 17, color: colors.onSurfaceVariant),
          const SizedBox(width: 7),
          Text(
            'Local',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 18),
          Icon(
            auto ? Broken.magicpen : Broken.shield_tick,
            size: 17,
            color: auto ? const Color(0xffe2bd36) : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onApprovalTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
              child: Text(
                auto
                    ? 'Autopilot'
                    : approvalMode == 'every'
                        ? 'Every tool'
                        : 'Approval mode',
                style: TextStyle(
                  color: auto ? const Color(0xffe2bd36) : colors.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const Spacer(),
          Tooltip(
            message: '~$usedTokens / $maxTokens tokens de contexte',
            child: _UsageRing(value: usage, label: '${(usage * 100).round()}'),
          ),
        ],
      ),
    );
  }
}

class _UsageRing extends StatelessWidget {
  const _UsageRing({required this.value, required this.label});

  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: 27,
      height: 27,
      child: CustomPaint(
        painter: _UsageRingPainter(value: value, color: color),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 7,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Prompts submitted while the current turn is running.
class PandaAgentQueueBar extends StatelessWidget {
  const PandaAgentQueueBar({
    super.key,
    required this.items,
    required this.onRemove,
    required this.onEdit,
  });

  final List<QueuedAgentPrompt> items;
  final ValueChanged<int> onRemove;
  final void Function(int index, String text) onEdit;

  Future<void> _edit(BuildContext context, int index, QueuedAgentPrompt item) async {
    final editor = TextEditingController(text: item.text);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Modifier le message en attente'),
        content: TextField(
          controller: editor,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Message à envoyer après le tour actuel',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, editor.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    editor.dispose();
    if (result != null && result.isNotEmpty) onEdit(index, result);
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 2),
      padding: const EdgeInsets.fromLTRB(9, 6, 5, 6),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Broken.task, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                'File d’attente · ${items.length}/5',
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          for (var index = 0; index < items.length; index++)
            Row(
              children: [
                Expanded(
                  child: Text(
                    items[index].text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                  ),
                ),
                IconButton(
                  tooltip: 'Modifier',
                  onPressed: () => _edit(context, index, items[index]),
                  icon: const Icon(Broken.edit, size: 15),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Retirer',
                  onPressed: () => onRemove(index),
                  icon: const Icon(Broken.close_circle, size: 15),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _UsageRingPainter extends CustomPainter {
  const _UsageRingPainter({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;
    final base = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final active = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius, base);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708,
      6.2832 * value,
      false,
      active,
    );
  }

  @override
  bool shouldRepaint(_UsageRingPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}