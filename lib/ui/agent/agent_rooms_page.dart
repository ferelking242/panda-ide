/// Salles d'agents pour Panda IDE :
///  • [ConferenceRoomView] — salle de conférence (agent principal ↔ sous-agents)
///  • [MultiAgentRoomsView] — rooms multi-agents (agent + pairs, chacun peut
///    avoir ses propres sous-agents).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../core/broken_icons.dart';
import '../../utils/subagent_orchestrator.dart';

const _kAccent   = Color(0xff6366f1);
const _kDanger   = Color(0xffe05252);
const _kChatBg   = Color(0xff0f0f1a);

Future<String> _currentWorkspacePath() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final rawRecent = prefs.getString('recent');
    if (rawRecent == null || rawRecent.isEmpty) return '';
    final recent = jsonDecode(rawRecent);
    if (recent is List && recent.isNotEmpty && recent.first is Map) {
      final first = recent.first;
      return first['rootDir']?.toString() ?? first['path']?.toString() ?? '';
    }
  } catch (_) {}
  return '';
}

/// Injecte la config AI courante dans l'orchestrateur (appelé par l'hôte).
void syncOrchestratorConfig(BuildContext context) {
  try {
    SubagentOrchestrator.instance.aiConfig =
        Map<String, dynamic>.from(context.read<AIBloc>().state.config);
  } catch (_) {}
}

// ─────────────────────────────────────────────────────────────────────────────
// Conversation générique d'une salle
// ─────────────────────────────────────────────────────────────────────────────

class RoomConversationView extends StatefulWidget {
  final AgentRoom room;
  /// Hauteur fixe; <= 0 → prend tout l'espace disponible (parent doit fournir
  /// un Expanded/SizedBox).
  final double height;
  const RoomConversationView({super.key, required this.room, this.height = 340});

  @override
  State<RoomConversationView> createState() => _RoomConversationViewState();
}

class _RoomConversationViewState extends State<RoomConversationView> {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();
    setState(() => _sending = true);
    syncOrchestratorConfig(context);
    final ws = await _currentWorkspacePath();
    await SubagentOrchestrator.instance
        .broadcast(widget.room, text, workspacePath: ws);
    if (mounted) setState(() => _sending = false);
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orch = SubagentOrchestrator.instance;
    return AnimatedBuilder(
      animation: orch,
      builder: (context, _) {
        final msgs = widget.room.messages;
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: widget.height <= 0 ? null : widget.height,
            color: _kChatBg,
            child: Column(children: [
              Expanded(
                child: msgs.isEmpty
                    ? Center(
                        child: Text(
                          'Envoyez un message — chaque agent participant répondra à tour de rôle.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(10),
                        itemCount: msgs.length,
                        itemBuilder: (_, i) {
                          final m = msgs[i];
                          final isUser = m.authorId == 'user';
                          if (isUser) {
                            return Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                margin: const EdgeInsets.only(
                                    top: 4, bottom: 4, left: 48),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _kAccent,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(14),
                                    topRight: Radius.circular(4),
                                    bottomLeft: Radius.circular(14),
                                    bottomRight: Radius.circular(14),
                                  ),
                                ),
                                child: Text(m.text,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.white,
                                        height: 1.4)),
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: m.isError ? _kDanger : _kAccent,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(m.author,
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: m.isError
                                              ? _kDanger
                                              : Colors.grey[400])),
                                ]),
                                const SizedBox(width: 0),
                                Padding(
                                  padding: const EdgeInsets.only(left: 13, top: 2),
                                  child: SelectableText(m.text,
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.5,
                                          color: m.isError
                                              ? _kDanger
                                              : Colors.grey[200])),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              if (_sending)
                const LinearProgressIndicator(minHeight: 2, color: _kAccent),
              Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xff151520),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                ),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 12.5, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Parler à la salle…',
                        hintStyle:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: _sending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.8, color: _kAccent))
                        : const Icon(Broken.send_1, size: 16, color: _kAccent),
                    onPressed: _send,
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Salle de conférence (agent principal ↔ sous-agents)
// ─────────────────────────────────────────────────────────────────────────────

class ConferenceRoomView extends StatelessWidget {
  final int maxAgents;
  const ConferenceRoomView({super.key, this.maxAgents = 4});

  @override
  Widget build(BuildContext context) {
    final orch = SubagentOrchestrator.instance;
    return AnimatedBuilder(
      animation: orch,
      builder: (context, _) {
        final room = orch.conferenceRoom();
        final enabled = orch.subAgents.where((s) => s.enabled).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 5, runSpacing: 5, children: [
            for (final s in enabled)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
                ),
                child: Text('${s.name}${s.role.isEmpty ? '' : ' · ${s.role}'}',
                    style: const TextStyle(
                        fontSize: 10, color: _kAccent)),
              ),
            if (enabled.isEmpty)
              Text(
                'Aucun sous-agent actif — configurez-en jusqu\'à $maxAgents ci-dessus.',
                style: TextStyle(fontSize: 10.5, color: Colors.grey[500]),
              ),
          ]),
          const SizedBox(height: 8),
          RoomConversationView(room: room),
        ]);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rooms multi-agents (agent + pairs)
// ─────────────────────────────────────────────────────────────────────────────

class MultiAgentRoomsView extends StatefulWidget {
  final bool isDark;
  final Color card, fg, muted, border;

  const MultiAgentRoomsView({
    super.key,
    required this.isDark,
    required this.card,
    required this.fg,
    required this.muted,
    required this.border,
  });

  @override
  State<MultiAgentRoomsView> createState() => _MultiAgentRoomsViewState();
}

class _MultiAgentRoomsViewState extends State<MultiAgentRoomsView> {
  void _openRoom(AgentRoom room) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _RoomPage(room: room),
    ));
  }

  Future<void> _createRoom() async {
    final orch = SubagentOrchestrator.instance;
    syncOrchestratorConfig(context);
    final aiState = context.read<AIBloc>().state;
    final candidates = aiState.config.entries
        .where((e) => e.key.startsWith('agent_'))
        .map((e) {
      final cfg = e.value is Map ? Map<String, dynamic>.from(e.value as Map) : <String, dynamic>{};
      return (
        key: e.key,
        label: ((cfg['modelName'] ?? e.key).toString()),
      );
    }).toList();

    final nameCtrl = TextEditingController();
    final selected = <String>{};
    String? error;

    final created = await showDialog<AgentRoom>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: widget.card,
          title: Text('Nouvelle room multi-agents',
              style: TextStyle(fontSize: 15, color: widget.fg)),
          content: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameCtrl,
                style: TextStyle(fontSize: 13, color: widget.fg),
                decoration: InputDecoration(
                  hintText: 'Nom de la room',
                  hintStyle: TextStyle(fontSize: 12, color: widget.muted),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: widget.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kAccent)),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Participants (≥ 2)',
                    style: TextStyle(fontSize: 11, color: widget.muted)),
              ),
              const SizedBox(height: 6),
              ...candidates.map((c) => CheckboxListTile(
                    dense: true,
                    value: selected.contains(c.key),
                    activeColor: _kAccent,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(c.label,
                        style: TextStyle(fontSize: 12, color: widget.fg)),
                    subtitle: Text(c.key,
                        style: TextStyle(fontSize: 9.5, color: widget.muted)),
                    onChanged: (v) => setDialog(() {
                      v == true ? selected.add(c.key) : selected.remove(c.key);
                    }),
                  )),
              if (candidates.isEmpty)
                Text('Configurez au moins deux providers dans Tools → Settings.',
                    style: TextStyle(fontSize: 11, color: widget.muted)),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(error!,
                      style: const TextStyle(fontSize: 11, color: _kDanger)),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kAccent),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) {
                  setDialog(() => error = 'Donnez un nom à la room.');
                  return;
                }
                if (selected.length < 2) {
                  setDialog(() => error = 'Sélectionnez au moins 2 agents.');
                  return;
                }
                Navigator.pop(ctx, orch.createMultiAgentRoom(nameCtrl.text, selected.toList()));
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    if (created != null) _openRoom(created);
  }

  @override
  Widget build(BuildContext context) {
    final orch = SubagentOrchestrator.instance;
    return AnimatedBuilder(
      animation: orch,
      builder: (context, _) {
        final rooms = orch.rooms.where((r) => !r.isConference).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (rooms.isEmpty)
            Text(
              'Réunissez plusieurs agents (avec leurs modèles différents) dans une même room de travail.',
              style: TextStyle(fontSize: 11, color: widget.muted,
                  fontStyle: FontStyle.italic),
            )
          else
            for (final room in rooms)
              InkWell(
                onTap: () => _openRoom(room),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: widget.border, width: 0.5)),
                  ),
                  child: Row(children: [
                    const Icon(Broken.people, size: 15, color: _kAccent),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(room.name,
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w500, color: widget.fg)),
                    ),
                    Text('${room.participantCfgKeys.length} agents',
                        style: TextStyle(fontSize: 10.5, color: widget.muted)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Broken.close_square,
                          size: 13, color: widget.muted),
                      onPressed: () => orch.removeRoom(room.id),
                    ),
                  ]),
                ),
              ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _kAccent,
              side: BorderSide(color: _kAccent.withValues(alpha: 0.4)),
            ),
            onPressed: _createRoom,
            icon: const Icon(Broken.add_square, size: 13),
            label: const Text('Nouvelle room',
                style: TextStyle(fontSize: 12)),
          ),
        ]);
      },
    );
  }
}

class _RoomPage extends StatelessWidget {
  final AgentRoom room;
  const _RoomPage({required this.room});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kChatBg,
      appBar: AppBar(
        backgroundColor: const Color(0xff151520),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Column(children: [
          Text(room.name,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          Text('${room.participantCfgKeys.length} agents',
              style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ]),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(child: RoomConversationView(room: room, height: 0)),
        ]),
      ),
    );
  }
}
