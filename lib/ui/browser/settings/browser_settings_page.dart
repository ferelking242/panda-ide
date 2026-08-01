import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../models/browser_profile.dart';
import '../state/browser_controller.dart';
import '../state/profile_store.dart';
import '../widgets/profile_badge.dart';

// Couleurs VSCode
const _kBg    = Color(0xff1e1e1e);
const _kBgL   = Color(0xfffafafa);
const _kHdr   = Color(0xff252526);
const _kHdrL  = Color(0xffececec);
const _kAccent= Color(0xff5090c8);

/// Page de paramètres du navigateur.
/// Peut être affichée de façon autonome (depuis Settings) ou comme
/// un onglet dans le navigateur lui-même.
class BrowserSettingsPage extends StatefulWidget {
  /// Si [controller] est fourni, les changements s'appliquent immédiatement.
  /// Sinon la page crée un état local temporaire.
  final BrowserController? controller;
  const BrowserSettingsPage({super.key, this.controller});

  @override
  State<BrowserSettingsPage> createState() => _BrowserSettingsPageState();
}

class _BrowserSettingsPageState extends State<BrowserSettingsPage> {
  // Utilisé uniquement si controller est null (depuis Settings global)
  String _searchEngine = 'https://www.google.com/search?q=%s';
  String _homeUrl      = 'https://www.google.com';
  int    _maxProfiles  = 3;

  final _homeUrlCtrl = TextEditingController();
  bool _loadedPrefs  = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    _searchEngine = await ProfileStore.loadSearchEngine();
    _homeUrl      = await ProfileStore.loadHomeUrl();
    _maxProfiles  = await ProfileStore.loadMaxProfiles();
    _homeUrlCtrl.text = _homeUrl;
    if (mounted) setState(() => _loadedPrefs = true);
  }

  @override
  void dispose() {
    _homeUrlCtrl.dispose();
    super.dispose();
  }

  BrowserController? get _ctrl =>
      widget.controller ??
      (context.mounted
          ? context.read<BrowserController?>()
          : null);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? _kBg    : _kBgL;
    final hdr    = isDark ? _kHdr   : _kHdrL;
    final fg     = isDark ? Colors.grey[200]! : Colors.grey[850]!;
    final sub    = isDark ? Colors.grey[500]! : Colors.grey[600]!;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: hdr,
        foregroundColor: fg,
        elevation: 0,
        title: Text(
          'Paramètres — Navigateur',
          style: TextStyle(fontSize: 16, color: fg),
        ),
      ),
      body: _loadedPrefs
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Section(title: 'MOTEUR DE RECHERCHE', fg: sub),
                _SearchEngineSelector(
                  current: _searchEngine,
                  fg: fg,
                  sub: sub,
                  onChanged: (engine) async {
                    setState(() => _searchEngine = engine);
                    await ProfileStore.saveSearchEngine(engine);
                    await _ctrl?.updateSearchEngine(engine);
                  },
                ),
                const SizedBox(height: 20),

                _Section(title: 'PAGE D\'ACCUEIL', fg: sub),
                _HomeUrlField(
                  ctrl: _homeUrlCtrl,
                  fg: fg,
                  sub: sub,
                  onSubmit: (url) async {
                    await ProfileStore.saveHomeUrl(url);
                    await _ctrl?.updateHomeUrl(url);
                  },
                ),
                const SizedBox(height: 20),

                _Section(title: 'PROFILS', fg: sub),
                _ProfileList(
                  maxProfiles: _maxProfiles,
                  fg: fg,
                  sub: sub,
                ),
                const SizedBox(height: 20),

                _Section(title: 'NOMBRE MAX DE PROFILS', fg: sub),
                _MaxProfilesSlider(
                  value: _maxProfiles,
                  fg: fg,
                  sub: sub,
                  onChanged: (v) async {
                    setState(() => _maxProfiles = v);
                    await ProfileStore.saveMaxProfiles(v);
                  },
                ),
                const SizedBox(height: 20),

                _Section(title: 'DONNÉES', fg: sub),
                _DataSection(fg: fg, sub: sub),
                const SizedBox(height: 40),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

// ── Sections ──────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final Color fg;
  const _Section({required this.title, required this.fg});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: fg,
          ),
        ),
      );
}

// ── Moteur de recherche ───────────────────────────────────────────────────────

class _SearchEngineSelector extends StatelessWidget {
  final String current;
  final Color fg, sub;
  final ValueChanged<String> onChanged;

  const _SearchEngineSelector({
    required this.current,
    required this.fg,
    required this.sub,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xff2d2d2d) : Colors.white;
    final border = isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd);

    return Container(
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Column(
        children: kSearchEngines.entries.map((entry) {
          final label   = entry.key;
          final url     = entry.value;
          final selected = url == current;
          return RadioListTile<String>(
            dense: true,
            title: Text(label, style: TextStyle(fontSize: 13, color: fg)),
            subtitle: Text(
              url.replaceAll('%s', '...'),
              style: TextStyle(fontSize: 11, color: sub),
              overflow: TextOverflow.ellipsis,
            ),
            value: url,
            groupValue: current,
            activeColor: _kAccent,
            onChanged: (v) { if (v != null) onChanged(v); },
          );
        }).toList(),
      ),
    );
  }
}

// ── URL d'accueil ─────────────────────────────────────────────────────────────

class _HomeUrlField extends StatelessWidget {
  final TextEditingController ctrl;
  final Color fg, sub;
  final ValueChanged<String> onSubmit;

  const _HomeUrlField({
    required this.ctrl,
    required this.fg,
    required this.sub,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: ctrl,
      style: TextStyle(fontSize: 13, color: fg),
      decoration: InputDecoration(
        hintText: 'https://www.google.com',
        hintStyle: TextStyle(color: sub, fontSize: 13),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kAccent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        filled: true,
        fillColor: isDark ? const Color(0xff2d2d2d) : Colors.white,
      ),
      onSubmitted: onSubmit,
      textInputAction: TextInputAction.done,
    );
  }
}

// ── Liste de profils ──────────────────────────────────────────────────────────

class _ProfileList extends StatefulWidget {
  final int maxProfiles;
  final Color fg, sub;
  const _ProfileList({
    required this.maxProfiles,
    required this.fg,
    required this.sub,
  });

  @override
  State<_ProfileList> createState() => _ProfileListState();
}

class _ProfileListState extends State<_ProfileList> {
  List<BrowserProfile> _profiles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await ProfileStore.loadProfiles();
    if (mounted) setState(() => _profiles = p);
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final tileBg  = isDark ? const Color(0xff2d2d2d) : Colors.white;
    final border  = isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd);

    return Container(
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Column(
        children: [
          ..._profiles.map((p) => _ProfileRow(
            profile: p,
            fg: widget.fg,
            sub: widget.sub,
            canDelete: _profiles.length > 1,
            onDelete: () async {
              await ProfileStore.saveProfiles(
                _profiles..removeWhere((x) => x.id == p.id),
              );
              _load();
            },
            onRename: (name) async {
              final idx = _profiles.indexWhere((x) => x.id == p.id);
              if (idx < 0) return;
              _profiles[idx] = p.copyWith(name: name);
              await ProfileStore.saveProfiles(_profiles);
              _load();
            },
          )),
          if (_profiles.length < widget.maxProfiles)
            ListTile(
              dense: true,
              leading: const Icon(Icons.add, size: 18, color: _kAccent),
              title: const Text(
                'Ajouter un profil',
                style: TextStyle(fontSize: 13, color: _kAccent),
              ),
              onTap: () => _showCreateDialog(context),
            ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    Color color = kProfileColors[_profiles.length % kProfileColors.length];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: const Text('Nouveau profil'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Nom du profil',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: kProfileColors.map((c) => GestureDetector(
                  onTap: () => ss(() => color = c),
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: c == color
                          ? Border.all(color: Colors.white, width: 2.5)
                          : null,
                    ),
                    child: c == color
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                _profiles.add(BrowserProfile(
                  id:    ProfileStore.generateId(),
                  name:  name,
                  color: color,
                ));
                await ProfileStore.saveProfiles(_profiles);
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
  }
}

class _ProfileRow extends StatelessWidget {
  final BrowserProfile profile;
  final Color fg, sub;
  final bool canDelete;
  final VoidCallback onDelete;
  final ValueChanged<String> onRename;

  const _ProfileRow({
    required this.profile,
    required this.fg,
    required this.sub,
    required this.canDelete,
    required this.onDelete,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: ProfileBadge(profile: profile, size: 26),
      title: Text(profile.name, style: TextStyle(fontSize: 13, color: fg)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.edit_outlined, size: 16, color: sub),
            tooltip: 'Renommer',
            onPressed: () => _showRenameDialog(context),
          ),
          if (canDelete)
            IconButton(
              icon: Icon(Icons.delete_outline, size: 16, color: Colors.redAccent[200]),
              tooltip: 'Supprimer',
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: profile.name);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer le profil'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) onRename(name);
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }
}

// ── Slider nombre max de profils ──────────────────────────────────────────────

class _MaxProfilesSlider extends StatelessWidget {
  final int value;
  final Color fg, sub;
  final ValueChanged<int> onChanged;

  const _MaxProfilesSlider({
    required this.value,
    required this.fg,
    required this.sub,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.person_outline, size: 16, color: sub),
        const SizedBox(width: 8),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: '$value profil${value > 1 ? 's' : ''}',
            activeColor: _kAccent,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: fg),
          ),
        ),
      ],
    );
  }
}

// ── Données / cache ───────────────────────────────────────────────────────────

class _DataSection extends StatelessWidget {
  final Color fg, sub;
  const _DataSection({required this.fg, required this.sub});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileBg = isDark ? const Color(0xff2d2d2d) : Colors.white;
    final border = isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd);

    return Container(
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Icon(Icons.cleaning_services_outlined, size: 18, color: sub),
            title: Text('Vider les cookies', style: TextStyle(fontSize: 13, color: fg)),
            onTap: () async {
              await _confirm(context,
                  'Vider les cookies de tous les profils ?', () async {
                final CookieManager cm = CookieManager.instance();
                await cm.deleteAllCookies();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cookies supprimés')),
                  );
                }
              });
            },
          ),
          Divider(height: 1, color: border),
          ListTile(
            dense: true,
            leading: Icon(Icons.storage_outlined, size: 18, color: sub),
            title: Text('Vider tout le cache', style: TextStyle(fontSize: 13, color: fg)),
            onTap: () async {
              await _confirm(context, 'Vider tout le cache navigateur ?', () async {
                final CookieManager cm = CookieManager.instance();
                await cm.deleteAllCookies();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cache vidé')),
                  );
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    String message,
    Future<void> Function() action,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),  child: const Text('Confirmer')),
        ],
      ),
    );
    if (ok == true) await action();
  }
}

