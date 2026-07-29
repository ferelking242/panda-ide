/// Gestionnaire des Output Channels des extensions.
/// Chaque extension peut créer un canal (ex: "ESLint", "Prettier") et y écrire du texte.
/// Le contenu est affiché dans un panneau dédié (style VSCode Output panel).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Modèle ────────────────────────────────────────────────────────────────

class OutputChannel {
  final String name;
  final StringBuffer _buffer = StringBuffer();
  final List<VoidCallback> _listeners = [];

  OutputChannel(this.name);

  String get content => _buffer.toString();

  void append(String text) {
    _buffer.write(text);
    _notify();
  }

  void appendLine(String text) {
    _buffer.writeln(text);
    _notify();
  }

  void clear() {
    _buffer.clear();
    _notify();
  }

  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);

  void _notify() {
    for (final cb in List.of(_listeners)) cb();
  }
}

// ── Singleton manager ─────────────────────────────────────────────────────

class OutputChannelManager {
  static final OutputChannelManager instance = OutputChannelManager._();
  OutputChannelManager._();

  final Map<String, OutputChannel> _channels = {};
  String? _activeChannel;

  // Notifie le widget OutputChannelPanel des changements
  final List<VoidCallback> _panelListeners = [];

  void addPanelListener(VoidCallback cb) => _panelListeners.add(cb);
  void removePanelListener(VoidCallback cb) => _panelListeners.remove(cb);
  void _notifyPanel() {
    for (final cb in List.of(_panelListeners)) cb();
  }

  void create(String name) {
    _channels.putIfAbsent(name, () => OutputChannel(name));
    _notifyPanel();
  }

  void append(String name, String text) {
    _channels[name]?.append(text);
    _notifyPanel();
  }

  void appendLine(String name, String text) {
    _channels[name]?.appendLine(text);
    _notifyPanel();
  }

  void clear(String name) {
    _channels[name]?.clear();
    _notifyPanel();
  }

  void show(BuildContext context, String name, {bool preserveFocus = false}) {
    create(name);
    _activeChannel = name;
    _notifyPanel();
    if (!preserveFocus) {
      OutputChannelPanelSheet.show(context);
    }
  }

  void dispose(String name) {
    _channels.remove(name);
    if (_activeChannel == name) _activeChannel = null;
    _notifyPanel();
  }

  List<String> get channelNames => _channels.keys.toList();
  OutputChannel? get(String name) => _channels[name];
  String? get activeChannelName => _activeChannel;

  void setActive(String name) {
    _activeChannel = name;
    _notifyPanel();
  }
}

// ── Widget ────────────────────────────────────────────────────────────────

/// Sheet modal style VSCode Output Panel.
class OutputChannelPanelSheet extends StatefulWidget {
  const OutputChannelPanelSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const OutputChannelPanelSheet(),
    );
  }

  @override
  State<OutputChannelPanelSheet> createState() =>
      _OutputChannelPanelSheetState();
}

class _OutputChannelPanelSheetState extends State<OutputChannelPanelSheet> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    OutputChannelManager.instance.addPanelListener(_onUpdate);
  }

  @override
  void dispose() {
    OutputChannelManager.instance.removePanelListener(_onUpdate);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) {
      setState(() {});
      // Auto-scroll vers le bas
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mgr     = OutputChannelManager.instance;
    final names   = mgr.channelNames;
    final active  = mgr.activeChannelName ?? (names.isNotEmpty ? names.first : null);
    final channel = active != null ? mgr.get(active) : null;
    final content = channel?.content ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.15,
      maxChildSize: 0.65,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xff1e1e1e),
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          border: Border(top: BorderSide(color: Color(0xff3c3c3c))),
        ),
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────
            Container(
              height: 35,
              color: const Color(0xff252526),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Text('OUTPUT',
                      style: TextStyle(
                          color: Color(0xff858585),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2)),
                  const SizedBox(width: 12),
                  // Sélecteur de canal
                  if (names.isNotEmpty)
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: names.map((name) {
                            final isActive = name == active;
                            return GestureDetector(
                              onTap: () => setState(
                                  () => mgr.setActive(name)),
                              child: Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: isActive
                                    ? const BoxDecoration(
                                        border: Border(
                                            bottom: BorderSide(
                                                color: Color(0xff5090c8),
                                                width: 2)))
                                    : null,
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    color: isActive
                                        ? Colors.white
                                        : const Color(0xff858585),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  // Boutons
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14,
                        color: Color(0xff858585)),
                    onPressed: content.isNotEmpty
                        ? () => Clipboard.setData(
                            ClipboardData(text: content))
                        : null,
                    tooltip: 'Copier',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear_all, size: 14,
                        color: Color(0xff858585)),
                    onPressed: active != null
                        ? () => mgr.clear(active)
                        : null,
                    tooltip: 'Effacer',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 14,
                        color: Color(0xff858585)),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Fermer',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            ),
            // ── Contenu ───────────────────────────────────────────────
            Expanded(
              child: content.isEmpty
                  ? const Center(
                      child: Text('Aucune sortie',
                          style: TextStyle(
                              color: Color(0xff858585), fontSize: 12)))
                  : Scrollbar(
                      controller: _scrollCtrl,
                      child: SingleChildScrollView(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          content,
                          style: const TextStyle(
                            color: Color(0xffcccccc),
                            fontSize: 12,
                            fontFamily: 'firaCode',
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
