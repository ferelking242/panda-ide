part of 'package:panda/ui/agent_settings.dart';



const Color _kAccent = Color(0xff6366f1);
const Color _kDanger = Color(0xffef4444);

// Agent settings helper widgets
// Extracted from agent_settings.dart

class _SubAgentCard extends StatelessWidget {
  final SubAgentConfig config;
  final List<({String key, String label})> cfgOptions;
  final bool isDark;
  final Color card, fg, muted, border;

  const _SubAgentCard({
    required this.config,
    required this.cfgOptions,
    required this.isDark,
    required this.card,
    required this.fg,
    required this.muted,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    final orch = SubagentOrchestrator.instance;
    final provider =
        config.modelCfgKey.replaceFirst('agent_', '');
    final brain = KeyRotationBrain.instance;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: config.enabled
                ? _kAccent.withValues(alpha: 0.35)
                : border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Broken.cpu_setting, size: 13, color: _kAccent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(config.name,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            height: 20,
            width: 36,
            child: Switch(
              value: config.enabled,
              activeColor: _kAccent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) =>
                  orch.updateSubAgent(config.id, (s) => s.enabled = v),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Broken.trash, size: 14, color: muted),
            onPressed: () => orch.removeSubAgent(config.id),
          ),
        ]),
        Text('Modèle',
            style: TextStyle(fontSize: 9.5, color: muted)),
        const SizedBox(height: 3),
        DropdownButtonFormField<String>(
          value: cfgOptions.any((c) => c.key == config.modelCfgKey)
              ? config.modelCfgKey
              : (cfgOptions.isNotEmpty ? cfgOptions.first.key : null),
          dropdownColor: isDark ? const Color(0xff252526) : Colors.white,
          style: TextStyle(fontSize: 12, color: fg),
          isDense: true,
          decoration: InputDecoration(
            isDense: true,
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kAccent)),
          ),
          items: [
            for (final c in cfgOptions)
              DropdownMenuItem(
                  value: c.key,
                  child: Text(c.label,
                      style: TextStyle(fontSize: 12, color: fg),
                      overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) =>
              orch.updateSubAgent(config.id, (s) => s.modelCfgKey = v ?? s.modelCfgKey),
        ),
        const SizedBox(height: 8),
        // ── Profil de clé + rotation auto ─────────────────────────────────
        FutureBuilder<List<KeyProfile>>(
          future: brain.getProfiles(provider),
          builder: (context, snap) {
            final profiles = snap.data ?? const <KeyProfile>[];
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Profil de clé ($provider)',
                  style: TextStyle(fontSize: 9.5, color: muted)),
              const SizedBox(height: 3),
              DropdownButtonFormField<String>(
                value: profiles.any((p) => p.id == config.keyProfileId)
                    ? config.keyProfileId
                    : null,
                dropdownColor: isDark ? const Color(0xff252526) : Colors.white,
                style: TextStyle(fontSize: 12, color: fg),
                isDense: true,
                hint: Text(profiles.isEmpty
                    ? 'Aucune clé enregistrée — auto'
                    : 'Auto (rotation)',
                    style: TextStyle(fontSize: 11, color: muted)),
                decoration: InputDecoration(
                  isDense: true,
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kAccent)),
                ),
                items: [
                  const DropdownMenuItem<String>(
                      value: '',
                      child: Text('Auto (rotation)',
                          style: TextStyle(fontSize: 12))),
                  for (final p in profiles)
                    DropdownMenuItem(
                        value: p.id,
                        child: Text(p.label,
                            style: TextStyle(fontSize: 12, color: fg),
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => orch.updateSubAgent(
                    config.id, (s) => s.keyProfileId = (v == null || v.isEmpty) ? null : v),
              ),
              Row(children: [
                Text('Rotation auto',
                    style: TextStyle(fontSize: 10, color: muted)),
                const Spacer(),
                SizedBox(
                  height: 20,
                  width: 36,
                  child: Switch(
                    value: config.autoRotate,
                    activeColor: _kAccent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) =>
                        orch.updateSubAgent(config.id, (s) => s.autoRotate = v),
                  ),
                ),
              ]),
            ]);
          },
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper data classes
// ─────────────────────────────────────────────────────────────────────────────

class _ToolItem {
  final IconData icon;
  final Color color;
  final String name;
  final String desc;
  final VoidCallback onTap;
  const _ToolItem({required this.icon, required this.color, required this.name, required this.desc, required this.onTap});
}

class _ToolSpecItem {
  final AgenticToolSpec spec;
  const _ToolSpecItem({required this.spec});
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final bool isDark;
  final Color card, border;
  final Widget child;
  final EdgeInsets padding;
  const _SettingsCard({
    required this.isDark, required this.card, required this.border,
    required this.child, this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: border),
    ),
    child: child,
  );
}

class _SettingsField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final bool obscure;
  final bool isDark;
  final Color card, fg, muted, border;
  final Widget? suffix;
  const _SettingsField({
    required this.controller, required this.label, required this.hint,
    this.obscure = false, required this.isDark, required this.card,
    required this.fg, required this.muted, required this.border, this.suffix,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(
          color: card, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              style: TextStyle(fontSize: 13, color: fg),
              decoration: InputDecoration(
                hintText: hint, hintStyle: TextStyle(fontSize: 12, color: muted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: InputBorder.none, isDense: true,
              ),
            ),
          ),
          if (suffix != null) suffix!,
        ]),
      ),
    ],
  );
}

class _ChatSmallIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  const _ChatSmallIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        icon: Icon(icon, size: 16, color: onTap == null ? color.withValues(alpha: 0.35) : color),
      );
}

class _ChatActionGroup extends StatefulWidget {
  final List<Map<String, dynamic>> calls;
  final bool isDark;
  final Color fg;
  final Color muted;

  const _ChatActionGroup({
    required this.calls,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  State<_ChatActionGroup> createState() => _ChatActionGroupState();
}

class _ChatActionGroupState extends State<_ChatActionGroup> {
  bool _expanded = false;

  IconData _groupIcon() {
    final names = widget.calls.map((call) => call['name']?.toString() ?? '').toList();
    if (names.any((name) => name == 'runShellCommand')) return Broken.code_1;
    if (names.any((name) => name.startsWith('write') || name.startsWith('edit'))) {
      return Broken.edit;
    }
    if (names.any((name) => name.startsWith('git'))) return Broken.hierarchy_2;
    if (names.any((name) => name.startsWith('search') || name.startsWith('grep'))) {
      return Broken.search_normal;
    }
    return Broken.setting_2;
  }

  String _title() {
    final names = widget.calls.map((call) => call['name']?.toString() ?? '').toList();
    if (names.any((n) => n == 'runShellCommand' || n.contains('Shell') || n.contains('cmd'))) {
      return 'Exécution de commandes terminal';
    }
    if (names.any((n) => n.startsWith('search') || n.startsWith('grep') || n.startsWith('find') || n.startsWith('glob'))) {
      return 'Recherche & Exploration de code';
    }
    if (names.any((n) => n.startsWith('write') || n.startsWith('edit') || n.startsWith('replace') || n.startsWith('create'))) {
      return 'Modification de fichiers';
    }
    if (names.any((n) => n.startsWith('read') || n.startsWith('list'))) {
      return 'Lecture du projet';
    }
    if (names.any((n) => n.startsWith('git'))) {
      return 'Opérations Git';
    }
    return 'Actions de Panda Agent';
  }

  String _labelFor(String name) {
    if (name.isEmpty) return 'Action';
    final spaced = name.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)!.toLowerCase()}',
    );
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  IconData _iconFor(String name) {
    if (name == 'runShellCommand') return Broken.code_1;
    if (name.startsWith('write') || name.startsWith('edit') ||
        name.startsWith('replace') || name.startsWith('insert')) {
      return Broken.edit;
    }
    if (name.startsWith('read')) return Broken.document_1;
    if (name.startsWith('delete')) return Broken.trash;
    if (name.startsWith('list') || name.startsWith('glob')) return Broken.folder_2;
    if (name.startsWith('grep') || name.startsWith('search')) return Broken.search_normal;
    if (name.startsWith('git')) return Broken.hierarchy_2;
    if (name.startsWith('openLinks')) return Broken.global_search;
    if (name.startsWith('updateProject') || name.startsWith('memory')) return Broken.note_2;
    if (name.startsWith('getLsp') || name.startsWith('diagnostic')) return Broken.warning_2;
    return Broken.cpu_setting;
  }

  String? _argsSummary(Map<String, dynamic>? args) {
    if (args == null || args.isEmpty) return null;
    final val = args['command'] ??
        args['CommandLine'] ??
        args['cmd'] ??
        args['path'] ??
        args['target'] ??
        args['pattern'] ??
        args['query'] ??
        args.values.first;
    if (val is! String) return null;
    final clean = val.replaceAll('\n', ' ').trim();
    if (clean.isEmpty) return null;
    return clean.length > 60 ? '${clean.substring(0, 60)}…' : clean;
  }

  @override
  Widget build(BuildContext context) {
    final border = widget.isDark ? const Color(0xff2a2a3e) : const Color(0xffd0d7de);
    final running = widget.calls.any((call) => call['status'] == 'running');
    final groupColor = running ? const Color(0xfff5a623) : widget.muted;

    final cardBg = widget.isDark ? const Color(0xff161622) : const Color(0xfff8f9fa);
    final cardBorder = widget.isDark ? const Color(0xff262638) : const Color(0xffe1e4e8);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: running ? groupColor.withValues(alpha: 0.45) : cardBorder),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(9),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                children: [
                  Icon(_groupIcon(), size: 15, color: groupColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _title(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: widget.fg, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text('${widget.calls.length} actions',
                      style: TextStyle(fontSize: 10, color: widget.muted)),
                  const SizedBox(width: 7),
                  if (running)
                    _DotsIndicator(color: groupColor, size: 3.5)
                  else
                    Icon(_expanded ? Broken.arrow_up_2 : Broken.arrow_down_2,
                        size: 13, color: widget.muted),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: _expanded
                ? Column(
                    children: [
                      Divider(height: 1, color: border),
                      ...widget.calls.map((call) {
                        final name = call['name']?.toString() ?? '';
                        final result = call['result']?.toString() ?? '';
                        final args = (call['args'] as Map?)?.cast<String, dynamic>();
                        final itemRunning = call['status'] == 'running';
                        final summary = _argsSummary(args);
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(11, 7, 11, 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(itemRunning ? Broken.more_circle : Broken.tick_circle,
                                  size: 13,
                                  color: itemRunning ? groupColor : _kSuccess),
                              const SizedBox(width: 7),
                              Icon(_iconFor(name), size: 13, color: widget.muted),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_labelFor(name),
                                        style: TextStyle(fontSize: 11, color: widget.fg)),
                                    if (summary != null)
                                      Text(summary,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: widget.muted,
                                              fontStyle: FontStyle.italic)),
                                    if (result.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 5),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(7),
                                          decoration: BoxDecoration(
                                            color: widget.isDark
                                                ? const Color(0xff0d1117)
                                                : const Color(0xfff6f8fa),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: SelectableText(
                                            result.length > 700
                                                ? '${result.substring(0, 700)}\n…'
                                                : result,
                                            style: TextStyle(
                                                fontSize: 10,
                                                height: 1.45,
                                                color: widget.muted,
                                                fontFamily: 'monospace'),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _ProviderPicker extends StatelessWidget {
  final List<ProviderDef> providers;
  final String selected;
  final bool isDark;
  final Color card, fg, muted, border;
  final ValueChanged<String> onChanged;
  const _ProviderPicker({
    required this.providers, required this.selected, required this.isDark,
    required this.card, required this.fg, required this.muted, required this.border,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pDef = providers.firstWhere((p) => p.id == selected, orElse: () => providers.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Provider', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: card, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: DropdownButton<String>(
            value: selected,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: card,
            style: TextStyle(fontSize: 13, color: fg),
            items: providers.map((p) => DropdownMenuItem(
              value: p.id,
              child: Row(children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(color: p.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Icon(p.icon, size: 14, color: p.color),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(p.name, style: TextStyle(fontSize: 13, color: fg))),
              ]),
            )).toList(),
            onChanged: (v) { if (v != null) onChanged(v); },
          ),
        ),
        const SizedBox(height: 4),
        Text(pDef.description, style: TextStyle(fontSize: 11, color: muted)),
      ],
    );
  }
}

class _ModelCard extends StatelessWidget {
  final String id, name, provider;
  final ProviderDef pDef;
  final bool isDark;
  final Color card, fg, muted, border;
  final VoidCallback onRemove;
  const _ModelCard({
    required this.id, required this.name, required this.provider,
    required this.pDef, required this.isDark, required this.card,
    required this.fg, required this.muted, required this.border,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: card, borderRadius: BorderRadius.circular(10),
      border: Border.all(color: border),
    ),
    child: Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: pDef.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
        child: Icon(pDef.icon, size: 16, color: pDef.color),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pDef.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
          Text(name, style: TextStyle(fontSize: 11, color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
      IconButton(
        icon: Icon(Broken.trash, size: 15, color: _kDanger.withValues(alpha: 0.7)),
        tooltip: 'Supprimer',
        onPressed: onRemove,
      ),
    ]),
  );
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorSwatch({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: color, shape: BoxShape.circle,
        border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2.5),
        boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 1)] : [],
      ),
      child: selected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat sub-widgets (local to this file, avoid duplicating from home.dart)
// ─────────────────────────────────────────────────────────────────────────────

class _ChatActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color muted;
  final VoidCallback onTap;
  const _ChatActionBtn({required this.icon, required this.label, required this.muted, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: muted),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: muted)),
      ]),
    ),
  );
}

class _ChatPhaseChip extends StatelessWidget {
  final String label;
  final bool isDark;
  const _ChatPhaseChip({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: _kAccent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(label, style: const TextStyle(fontSize: 11, color: _kAccent)),
  );
}

// ─── DotsIndicator — 3 points animés (thinking / loading) ───────────────────

class _DotsIndicator extends StatefulWidget {
  final Color color;
  final double size;
  const _DotsIndicator({required this.color, this.size = 4.0});
  @override
  State<_DotsIndicator> createState() => _DotsIndicatorState();
}

class _DotsIndicatorState extends State<_DotsIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 3 + 8,
      height: widget.size * 2,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              // chaque point bounce avec un décalage de phase
              final phase = ((_ctrl.value * 3) - i).clamp(0.0, 1.0);
              final bounce = Curves.easeInOut.transform(
                (phase < 0.5 ? phase * 2 : (1 - phase) * 2).clamp(0.0, 1.0),
              );
              return Transform.translate(
                offset: Offset(0, -bounce * widget.size * 0.9),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.4 + bounce * 0.6),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ─── Thinking block — collapsible avec icône cerveau ────────────────────────

class _ChatThinkingBlock extends StatefulWidget {
  final String thinking;
  final bool isDark;
  final bool isStreaming;   // true = le modèle pense encore
  final Color fg, muted;
  const _ChatThinkingBlock({
    required this.thinking,
    required this.isDark,
    required this.fg,
    required this.muted,
    this.isStreaming = false,
  });
  @override
  State<_ChatThinkingBlock> createState() => _ChatThinkingBlockState();
}

class _ChatThinkingBlockState extends State<_ChatThinkingBlock>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _pulse;
  late Animation<double> _pulseAnim;

  static const _kThinkPurple = Color(0xff9b7de8);
  static const _kThinkBorder = Color(0xff7c5cbf);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _pulseAnim = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    if (widget.isStreaming) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_ChatThinkingBlock old) {
    super.didUpdateWidget(old);
    if (widget.isStreaming && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.isStreaming && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = _kThinkBorder.withValues(alpha: widget.isDark ? 0.08 : 0.05);
    final border = _kThinkBorder.withValues(alpha: 0.3);
    final charCount = widget.thinking.length;
    final hint = charCount > 0
        ? '${(charCount / 1000).toStringAsFixed(1)}k'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(children: [
                  // Cerveau animé
                  FadeTransition(
                    opacity: widget.isStreaming ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
                    child: const Icon(Broken.cpu, size: 16, color: _kThinkPurple),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isStreaming ? 'Réflexion en cours…' : 'Réflexion interne',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _kThinkPurple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (hint.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: _kThinkBorder.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(hint,
                          style: TextStyle(fontSize: 9.5, color: widget.muted)),
                    ),
                  ],
                  const Spacer(),
                  if (widget.isStreaming)
                    _DotsIndicator(color: _kThinkPurple.withValues(alpha: 0.7))
                  else
                    Icon(
                      _expanded ? Broken.arrow_up_2 : Broken.arrow_down_2,
                      size: 13,
                      color: _kThinkPurple,
                    ),
                ]),
              ),
            ),
          ),
          // ── Contenu déplié ──────────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: _expanded && widget.thinking.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(height: 1, color: border),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: SelectableText(
                          widget.thinking,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.muted,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ─── Tool call block — icône par type, résultat expandable ──────────────────

class _ChatToolCallBlock extends StatefulWidget {
  final String toolName, status;
  final String? result;
  final Map<String, dynamic>? args;
  final bool isDark;
  final Color fg, muted;
  const _ChatToolCallBlock({
    required this.toolName,
    required this.status,
    this.result,
    this.args,
    required this.isDark,
    required this.fg,
    required this.muted,
  });
  @override
  State<_ChatToolCallBlock> createState() => _ChatToolCallBlockState();
}

class _ChatToolCallBlockState extends State<_ChatToolCallBlock> {
  bool _expanded = false;

  // ── Icône selon le nom de l'outil ─────────────────────────────────────────
  IconData _iconFor(String name) {
    if (name == 'runShellCommand') return Broken.code_1;
    if (name.startsWith('write') || name.startsWith('edit') ||
        name.startsWith('replace') || name.startsWith('insert')) return Broken.edit;
    if (name.startsWith('read')) return Broken.document_1;
    if (name.startsWith('delete')) return Broken.trash;
    if (name.startsWith('list') || name.startsWith('glob')) return Broken.folder_2;
    if (name.startsWith('grep') || name.startsWith('search')) return Broken.search_normal;
    if (name.startsWith('git')) return Broken.hierarchy_2;
    if (name.startsWith('searchInWeb') || name.startsWith('openLinks')) return Broken.global_search;
    if (name.startsWith('updateProject') || name.startsWith('memory')) return Broken.note_2;
    if (name.startsWith('getLsp') || name.startsWith('diagnostic')) return Broken.warning_2;
    if (name.startsWith('rename') || name.startsWith('move')) return Broken.document_text;
    if (name.startsWith('getFile') || name.startsWith('info')) return Broken.info_circle;
    if (name.startsWith('activeEditor') || name.startsWith('currentlySelected')) return Broken.code_circle;
    return Broken.cpu_setting;
  }

  // ── Label lisible (camelCase → "Camel case") ──────────────────────────────
  String _labelFor(String name) {
    if (name.isEmpty) return name;
    final spaced = name.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (m) => ' ${m.group(1)!.toLowerCase()}',
    );
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  // ── Résumé court des args ─────────────────────────────────────────────────
  String? _argsSummary(Map<String, dynamic>? args) {
    if (args == null || args.isEmpty) return null;
    final first = args.values.first;
    if (first is String) {
      final trimmed = first.replaceAll('\n', ' ').trim();
      return trimmed.length > 55 ? '${trimmed.substring(0, 55)}…' : trimmed;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = widget.status == 'running';
    const runColor = Color(0xfff97316);
    final border = widget.isDark ? const Color(0xff2a2a3a) : const Color(0xffe0e0e0);
    final cardBg = widget.isDark ? const Color(0xff1a1a2a) : const Color(0xfff4f4f8);
    final hasResult = (widget.result ?? '').isNotEmpty;
    final icon = _iconFor(widget.toolName);
    final label = _labelFor(widget.toolName);
    final argHint = _argsSummary(widget.args);

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: isRunning ? runColor.withValues(alpha: 0.06) : cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isRunning ? runColor.withValues(alpha: 0.4) : border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hasResult ? () => setState(() => _expanded = !_expanded) : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row ─────────────────────────────────────────────
                Row(children: [
                  // Status badge
                  if (isRunning)
                    _DotsIndicator(color: runColor, size: 3.5)
                  else
                    Icon(Broken.tick_circle, size: 13, color: _kSuccess),
                  const SizedBox(width: 7),
                  // Tool icon
                  Icon(icon, size: 13,
                      color: isRunning
                          ? runColor.withValues(alpha: 0.85)
                          : widget.fg.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  // Label + arg hint
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        text: label,
                        style: TextStyle(
                          fontSize: 12,
                          color: isRunning ? runColor : widget.fg,
                          fontWeight: FontWeight.w500,
                        ),
                        children: argHint != null
                            ? [
                                TextSpan(
                                  text: '  $argHint',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w400,
                                    color: widget.muted,
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              ]
                            : null,
                      ),
                    ),
                  ),
                  if (hasResult)
                    Icon(
                      _expanded ? Broken.arrow_up_2 : Broken.arrow_down_2,
                      size: 12,
                      color: widget.muted,
                    ),
                ]),

                // ── Résultat déplié ────────────────────────────────────────
                AnimatedSize(
                  duration: const Duration(milliseconds: 190),
                  curve: Curves.easeOut,
                  child: _expanded && hasResult
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Divider(height: 1, color: border),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: widget.isDark
                                      ? const Color(0xff0d1117)
                                      : const Color(0xfff6f8fa),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: SelectableText(
                                  () {
                                    final r = widget.result!;
                                    const limit = 900;
                                    if (r.length > limit) {
                                      return '${r.substring(0, limit)}\n… [${r.length - limit} chars tronqués]';
                                    }
                                    return r;
                                  }(),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: widget.muted,
                                    fontFamily: 'monospace',
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatMarkdownResponse extends StatelessWidget {
  final String markdown;
  final bool isDark;
  final Color fg;
  const _ChatMarkdownResponse({
    required this.markdown,
    required this.isDark,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    final config = isDark ? MarkdownConfig.darkConfig : MarkdownConfig.defaultConfig;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff11121a) : const Color(0xfff8f9fb),
        borderRadius: BorderRadius.circular(8),
      ),
      child: MarkdownWidget(
        data: markdown,
        config: config.copy(configs: [
          PConfig(
            textStyle: TextStyle(fontSize: 13.5, color: fg, height: 1.55),
          ),
        ]),
      ),
    );
  }
}

class _ChatBlinkingCursor extends StatefulWidget {
  final Color color;
  const _ChatBlinkingCursor({required this.color});
  @override
  State<_ChatBlinkingCursor> createState() => _ChatBlinkingCursorState();
}

class _ChatBlinkingCursorState extends State<_ChatBlinkingCursor> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.0, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(width: 2, height: 14, color: widget.color),
  );
}


Widget _buildAgentSettingsContent(BuildContext context, bool isDark, Color bg,
    Color card, Color fg, Color muted, Color border) {
  return _AgentSettingsView(
    isDark: isDark,
    bg: bg,
    card: card,
    fg: fg,
    muted: muted,
    border: border,
  );
}

class _AgentSettingsView extends StatefulWidget {
  final bool isDark;
  final Color bg;
  final Color card;
  final Color fg;
  final Color muted;
  final Color border;

  const _AgentSettingsView({
    required this.isDark,
    required this.bg,
    required this.card,
    required this.fg,
    required this.muted,
    required this.border,
  });

  @override
  State<_AgentSettingsView> createState() => _AgentSettingsViewState();
}

class _AgentSettingsViewState extends State<_AgentSettingsView> {
  final TextEditingController _promptCtrl = TextEditingController();
  final TextEditingController _rulesCtrl = TextEditingController();
  Map<String, String> _secrets = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _promptCtrl.text = prefs.getString('agent_custom_prompt') ?? '';

    final secretJson = prefs.getString('agent_secrets') ?? '{}';
    try {
      final Map<String, dynamic> decoded = jsonDecode(secretJson);
      _secrets = decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {}

    setState(() => _loading = false);
  }

  Future<void> _savePrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('agent_custom_prompt', _promptCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prompt personnalisé enregistré !', style: TextStyle(fontSize: 12))),
      );
    }
  }

  Future<void> _saveSecrets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('agent_secrets', jsonEncode(_secrets));
    setState(() {});
  }

  void _addSecretDialog() {
    final keyCtrl = TextEditingController();
    final valCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter un secret / clé API', style: TextStyle(fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyCtrl,
              decoration: const InputDecoration(labelText: 'Nom (ex: GITHUB_TOKEN, PAT)', isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: valCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Valeur', isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              final k = keyCtrl.text.trim();
              final v = valCtrl.text.trim();
              if (k.isNotEmpty && v.isNotEmpty) {
                _secrets[k] = v;
                _saveSecrets();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── Custom System Prompt ──────────────────────────────
        Text(
          'Prompt Système Personnalisé',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: widget.fg),
        ),
        const SizedBox(height: 4),
        Text(
          "Instructions supplémentaires injectées au début de chaque session d'agent.",
          style: TextStyle(fontSize: 11, color: widget.muted),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _promptCtrl,
          maxLines: 4,
          style: TextStyle(fontSize: 12, color: widget.fg),
          decoration: InputDecoration(
            hintText: 'Ex: Toujours répondre de manière concise en français...',
            hintStyle: TextStyle(fontSize: 12, color: widget.muted.withValues(alpha: 0.6)),
            filled: true,
            fillColor: widget.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: widget.border),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _savePrompt,
            icon: const Icon(Broken.document_upload, size: 14),
            label: const Text('Enregistrer le Prompt', style: TextStyle(fontSize: 11)),
          ),
        ),
        const Divider(height: 24),

        // ── Secrets & API Keys ──────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secrets & Clés API',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: widget.fg),
                ),
                Text(
                  "Utilisés automatiquement par l'agent pour git, API, etc.",
                  style: TextStyle(fontSize: 11, color: widget.muted),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Broken.add_circle, size: 18),
              onPressed: _addSecretDialog,
              tooltip: 'Ajouter un secret',
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_secrets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Aucun secret configuré.',
              style: TextStyle(fontSize: 11, color: widget.muted, fontStyle: FontStyle.italic),
            ),
          )
        else
          Column(
            children: _secrets.entries.map((e) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.card,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: widget.border),
                ),
                child: Row(
                  children: [
                    Icon(Broken.key, size: 14, color: widget.fg),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.key,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: widget.fg),
                      ),
                    ),
                    Text(
                      '••••••••',
                      style: TextStyle(fontSize: 11, color: widget.muted),
                    ),
                    IconButton(
                      icon: const Icon(Broken.trash, size: 14, color: Colors.redAccent),
                      onPressed: () {
                        _secrets.remove(e.key);
                        _saveSecrets();
                      },
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider page widgets — vrais logos + grille de modèles + rotation
// ─────────────────────────────────────────────────────────────────────────────

/// Ligne compacte d'un provider connecté (logo réel, modèle, badge actif).
class _ProviderRowCompact extends StatelessWidget {
  final String name, model, providerId;
  final bool isActive;
  final bool isDark;
  final Color card, fg, muted, border;
  final VoidCallback onRemove;

  const _ProviderRowCompact({
    required this.name,
    required this.model,
    required this.providerId,
    required this.isActive,
    required this.isDark,
    required this.card,
    required this.fg,
    required this.muted,
    required this.border,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isActive ? _kSuccess.withValues(alpha: 0.45) : border),
      ),
      child: Row(children: [
        ProviderLogoBadge(providerId: providerId, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(name,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: fg),
                      overflow: TextOverflow.ellipsis),
                ),
                if (isActive) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: _kSuccess.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('ACTIF',
                        style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: _kSuccess)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text(model,
                  style: TextStyle(fontSize: 11, color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Broken.trash, size: 15, color: _kDanger.withValues(alpha: 0.7)),
          tooltip: 'Supprimer',
          onPressed: onRemove,
        ),
      ]),
    );
  }
}

/// Tuile de modèle pour la grille 1-2 colonnes : vrai logo du provider,
/// nom, id, contexte estimé et étoile si modèle par défaut.
class _ModelGridTile extends StatelessWidget {
  final String modelId, displayName, providerId;
  final bool isDefault;
  final bool isDark;
  final Color card, fg, muted, border;
  final VoidCallback onTap;

  const _ModelGridTile({
    required this.modelId,
    required this.displayName,
    required this.providerId,
    required this.isDefault,
    required this.isDark,
    required this.card,
    required this.fg,
    required this.muted,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = AiProviderLogos.colorFor(providerId);
    final caps = ModelCapabilities.of(modelId);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: isDefault ? brand.withValues(alpha: 0.08) : card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color:
                  isDefault ? brand.withValues(alpha: 0.55) : border,
              width: isDefault ? 1.2 : 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              ProviderLogoBadge(providerId: providerId, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(displayName,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: fg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (isDefault)
                Icon(Icons.star_rounded, size: 14, color: brand)
              else
                Icon(Icons.circle_outlined, size: 12, color: muted.withValues(alpha: 0.6)),
            ]),
            const SizedBox(height: 3),
            Text(modelId,
                style: TextStyle(fontSize: 9.5, color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Row(children: [
              _MiniBadge(label: caps.contextWindowStr, color: muted, fg: fg),
              if (caps.hasThinking) ...[
                const SizedBox(width: 4),
                const _MiniBadge(label: 'think', color: Color(0xff9b7de8), fg: Colors.white),
              ],
              if (caps.hasVision) ...[
                const SizedBox(width: 4),
                _MiniBadge(label: 'vision', color: const Color(0xff4285f4), fg: Colors.white),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;
  final Color color, fg;
  const _MiniBadge({required this.label, required this.color, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// Cerveau de rotation — moniteur des clés de tous les providers :
/// requêtes, erreurs, cooldown restant et reset de quota par clé.
class _RotationMonitor extends StatefulWidget {
  final bool isDark;
  final Color card, fg, muted, border;

  const _RotationMonitor({
    required this.isDark,
    required this.card,
    required this.fg,
    required this.muted,
    required this.border,
  });

  @override
  State<_RotationMonitor> createState() => _RotationMonitorState();
}

class _RotationMonitorState extends State<_RotationMonitor> {
  @override
  Widget build(BuildContext context) {
    final brain = KeyRotationBrain.instance;
    return AnimatedBuilder(
      animation: brain,
      builder: (context, _) {
        final snapshot = brain.snapshotSync();
        final pDefs = providerDefs
            .where((p) => snapshot.containsKey(p.id))
            .toList();

        return _SettingsCard(
          isDark: widget.isDark,
          card: widget.card,
          border: widget.border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Broken.setting_2, size: 17, color: _kAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Cerveau de rotation des clés',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: widget.fg)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(
                'Surveillance automatique : requêtes, quota, cooldowns. '
                'La meilleure clé est choisie à chaque requête.',
                style: TextStyle(fontSize: 11, color: widget.muted),
              ),
              const SizedBox(height: 10),

              if (pDefs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Aucune clé enregistrée. Ajoutez une clé via un provider ci-dessus.',
                    style: TextStyle(fontSize: 11.5, color: widget.muted,
                        fontStyle: FontStyle.italic),
                  ),
                )
              else
                for (final pDef in pDefs)
                  _providerSection(pDef, snapshot[pDef.id]!, brain),
            ],
          ),
        );
      },
    );
  }

  Widget _providerSection(
      ProviderDef pDef, List<KeyProfile> profiles, KeyRotationBrain brain) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.border, width: 0.6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ProviderLogoBadge(providerId: pDef.id, size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Text(pDef.name,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: widget.fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text('rotation auto',
              style: TextStyle(fontSize: 10, color: widget.muted)),
          const SizedBox(width: 4),
          SizedBox(
            height: 18,
            width: 34,
            child: Switch(
              value: brain.autoRotateSync(pDef.id),
              activeColor: _kAccent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => brain.setAutoRotate(pDef.id, v),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        for (final profile in profiles)
          _keyRow(pDef.id, profile, brain),
      ]),
    );
  }

  Widget _keyRow(String providerId, KeyProfile profile, KeyRotationBrain brain) {
    final stats = brain.statsSync(providerId, profile.id);
    final isActive = brain.activeProfileId(providerId) == profile.id && !brain.autoRotateSync(providerId);
    final cooling = stats != null && stats.isCoolingDown;
    final statusLabel = cooling
        ? (stats!.quotaResetAt != null && stats.quotaResetAt!.isAfter(DateTime.now())
            ? 'quota → reset ${stats.quotaResetLabel}'
            : 'cooldown ${stats.cooldownRemaining}')
        : (profile.enabled ? 'prête' : 'désactivée');
    final statusColor = cooling
        ? const Color(0xfff5a623)
        : (profile.enabled ? _kSuccess : widget.muted);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => brain.setActiveProfile(providerId, profile.id),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(
              isActive ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 15,
              color: isActive ? _kAccent : widget.muted,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(profile.label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: widget.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                Text(profile.masked,
                    style: TextStyle(fontSize: 9.5, color: widget.muted)),
              ]),
              const SizedBox(height: 1),
              Text(
                '${stats?.requests ?? 0} req · ${stats?.errors ?? 0} err · $statusLabel',
                style: TextStyle(fontSize: 9.5, color: statusColor),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 18,
          width: 34,
          child: Switch(
            value: profile.enabled,
            activeColor: _kAccent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => brain.setProfileEnabled(providerId, profile.id, v),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => brain.removeProfile(providerId, profile.id),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Broken.trash, size: 13, color: widget.muted),
          ),
        ),
      ]),
    );
  }
}
