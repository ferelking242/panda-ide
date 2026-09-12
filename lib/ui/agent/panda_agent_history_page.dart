import 'package:flutter/material.dart';

import '../../core/broken_icons.dart';
import '../../utils/agent_history_service.dart';
import 'panda_agent_controller.dart';

/// Full-page conversation history. It deliberately does not use a sheet so
/// the user can browse, archive, and return to the chat without losing context.
class PandaAgentHistoryPage extends StatefulWidget {
  const PandaAgentHistoryPage({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onNewConversation,
  });

  final PandaAgentController controller;
  final VoidCallback onBack;
  final VoidCallback onNewConversation;

  @override
  State<PandaAgentHistoryPage> createState() => _PandaAgentHistoryPageState();
}

class _PandaAgentHistoryPageState extends State<PandaAgentHistoryPage> {
  bool _showArchived = false;

  List<AgentSession> _visibleSessions() => widget.controller.history
      .where((session) => session.archived == _showArchived)
      .toList();

  String _dateLabel(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} · $hour:$minute';
  }

  Future<void> _rename(AgentSession session) async {
    final textController = TextEditingController(text: session.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renommer la conversation'),
        content: TextField(
          controller: textController,
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          decoration: const InputDecoration(hintText: 'Nom de la conversation'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, textController.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (title != null) await widget.controller.renameHistorySession(session, title);
  }

  Future<void> _delete(AgentSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer cette conversation ?'),
        content: const Text('Cette action ne peut pas être annulée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.deleteHistorySession(session.id);
    }
  }

  void _showActions(AgentSession session) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Broken.edit_2),
              title: const Text('Renommer'),
              onTap: () {
                Navigator.pop(sheetContext);
                _rename(session);
              },
            ),
            ListTile(
              leading: Icon(
                session.archived ? Broken.archive_tick : Broken.archive,
              ),
              title: Text(session.archived ? 'Désarchiver' : 'Archiver'),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.controller.archiveHistorySession(session);
              },
            ),
            ListTile(
              leading: const Icon(Broken.trash, color: Colors.redAccent),
              title: const Text('Supprimer'),
              onTap: () {
                Navigator.pop(sheetContext);
                _delete(session);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final sessions = _visibleSessions();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Retour au chat',
                    onPressed: widget.onBack,
                    icon: const Icon(Broken.arrow_left_2),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Historique',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Nouvelle conversation',
                    onPressed: widget.onNewConversation,
                    icon: const Icon(Broken.add_square),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: Row(
                children: [
                  _HistoryFilter(
                    label: 'Conversations',
                    selected: !_showArchived,
                    onTap: () => setState(() => _showArchived = false),
                  ),
                  const SizedBox(width: 8),
                  _HistoryFilter(
                    label: 'Archivées',
                    selected: _showArchived,
                    onTap: () => setState(() => _showArchived = true),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            if (widget.controller.historyLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (sessions.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    _showArchived
                        ? 'Aucune conversation archivée'
                        : 'Aucune conversation enregistrée',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final selected =
                        session.id == widget.controller.sessionId;
                    return Material(
                      color: selected
                          ? colors.primaryContainer.withValues(alpha: 0.45)
                          : colors.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          session.archived ? Broken.archive : Broken.message_2,
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                        title: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_dateLabel(session.updatedAt)} · ${session.messages.length} message${session.messages.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Options',
                          onPressed: () => _showActions(session),
                          icon: const Icon(Broken.more, size: 19),
                        ),
                        onTap: () {
                          widget.controller.selectHistorySession(session);
                          widget.onBack();
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HistoryFilter extends StatelessWidget {
  const _HistoryFilter({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.14)
              : colors.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? colors.primary : colors.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}