import 'dart:async';

import 'package:flutter/material.dart';

import 'package:panda/utils/apk_service.dart';
import 'package:panda/utils/debian_setup.dart';

/// Visual apk package manager for the embedded Alpine Linux environment.
/// Real backend: every action runs `apk` through PRoot (ApkService).
class PackageManagerPage extends StatefulWidget {
  const PackageManagerPage({super.key});

  @override
  State<PackageManagerPage> createState() => _PackageManagerPageState();
}

enum _Filter { all, installed }

class _PackageManagerPageState extends State<PackageManagerPage> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<ApkPackage> _results = [];
  Set<String> _installed = {};
  _Filter _filter = _filter_all;

  // Compatibility alias so the enum reads naturally below.
  static const _Filter _filter_all = _Filter.all;

  /// Un seul auto-update par session d'app — l'utilisateur n'a RIEN à
  /// presser : les dépôts se rafraîchissent en silence à l'ouverture.
  static bool _autoUpdatedThisSession = false;

  @override
  void initState() {
    super.initState();
    _refreshInstalled(); // instantané (lecture directe de la DB apk)
    _autoUpdateReposIfNeeded();
  }

  /// `apk update` silencieux en arrière-plan à la première ouverture du
  /// store. Pas de bottom-sheet, pas d'attente visible : quand il termine,
  /// les métadonnées sont simplement déjà à jour.
  Future<void> _autoUpdateReposIfNeeded() async {
    if (_autoUpdatedThisSession) return;
    _autoUpdatedThisSession = true;
    if (!DebianSetup.isRootfsComplete()) return;
    unawaited(ApkService.updateRepos().catchError((_) {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshInstalled() async {
    final names = await ApkService.listInstalled();
    if (!mounted) return;
    setState(() => _installed = names.toSet());
    if (_searchCtrl.text.trim().isEmpty) {
      setState(() {
        _results =
            names.map(ApkPackage.bare).toList(growable: false);
        _loading = false;
        _error = null;
      });
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _runSearch());
  }

  Future<void> _runSearch() async {
    final q = _searchCtrl.text.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (q.isEmpty) {
        await _refreshInstalled();
        return;
      }
      final pkgs = await ApkService.search(q);
      if (!mounted) return;
      setState(() {
        _results = pkgs;
        _loading = false;
        if (pkgs.isEmpty && _installed.isEmpty) {
          _error = 'Aucun résultat. Lancez d\'abord « Mettre à jour » (icône ↻).';
        } else if (pkgs.isEmpty) {
          _error = 'Aucun paquet trouvé pour « $q »';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _updateRepos() async {
    await _runWithLog(
      title: 'Mise à jour des dépôts',
      task: (onLine) => ApkService.updateRepos(onLine: onLine),
    );
    await _refreshInstalled();
  }

  Future<void> _upgradeAll() async {
    await _runWithLog(
      title: 'Mise à jour des paquets',
      task: (onLine) => ApkService.upgrade(onLine: onLine),
    );
    await _refreshInstalled();
  }

  Future<void> _openDetail(ApkPackage pkg) async {
    final detail = await ApkService.detail(pkg);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PackageDetailSheet(pkg: detail ?? pkg),
    );
  }

  Future<void> _install(ApkPackage pkg) async {
    final res = await _runWithLog(
      title: 'Installer ${pkg.name}',
      task: (onLine) => ApkService.install(pkg.name, onLine: onLine),
    );
    if (res != null && res.ok) await _refreshInstalled();
  }

  Future<void> _uninstall(ApkPackage pkg) async {
    final res = await _runWithLog(
      title: 'Désinstaller ${pkg.name}',
      task: (onLine) => ApkService.uninstall(pkg.name, onLine: onLine),
    );
    if (res != null && res.ok) await _refreshInstalled();
  }

  /// Runs a mutating apk command and streams its output into a log sheet.
  /// Returns the ApkResult (null only when Alpine is not ready).
  Future<ApkResult?> _runWithLog({
    required String title,
    required Future<ApkResult> Function(void Function(String)) task,
  }) async {
    if (!DebianSetup.isRootfsComplete()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Linux n\'est pas encore initialisé'),
      ));
      return null;
    }
    final controller = TextEditingController();
    final logKey = GlobalKey<_LogViewState>();

    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _LogSheet(
          title: title, controller: controller, viewKey: logKey),
    ));

    final result = await task((line) {
      controller.text = '${controller.text}$line\n';
      logKey.currentState?.scrollToBottom();
    });

    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    // Dispose after the sheet close animation finished rendering.
    Future.delayed(const Duration(milliseconds: 800), controller.dispose);

    if (!mounted) return result;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      content: Text(
        result.ok ? '$title ✓' : '$title — erreur (code ${result.exitCode})',
        style: const TextStyle(fontSize: 12),
      ),
      duration: const Duration(seconds: 2),
    ));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xff1e1e1e) : const Color(0xfffefefe);
    final fg = isDark ? const Color(0xffcfcfcf) : const Color(0xff333333);
    final muted = isDark ? Colors.grey[500]! : Colors.grey[600]!;
    final fieldBg = isDark ? const Color(0xff2d2d2d) : const Color(0xffececec);

    final visible = _filter == _Filter.installed
        ? _results.where((p) => _installed.contains(p.name)).toList()
        : _results;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        toolbarHeight: 44,
        elevation: 0,
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: fg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 17),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inventory_2_outlined, size: 17, color: muted),
          const SizedBox(width: 8),
          Text('Paquets APK',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Mettre à jour les dépôts',
            onPressed: _loading ? null : _updateRepos,
            icon: const Icon(Icons.sync_rounded, size: 19),
          ),
          IconButton(
            tooltip: 'Mettre à jour tous les paquets',
            onPressed: _loading ? null : _upgradeAll,
            icon: const Icon(Icons.system_update_alt_rounded, size: 19),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── Search + filters ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _runSearch(),
              style: TextStyle(fontSize: 13, color: fg),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: fieldBg,
                hintText: 'Rechercher un paquet… (ex: git, python3)',
                hintStyle: TextStyle(fontSize: 12, color: muted),
                prefixIcon: Icon(Icons.search, size: 17, color: muted),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close, size: 14, color: muted),
                        onPressed: () {
                          _searchCtrl.clear();
                          _runSearch();
                        },
                      ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              _chip('Tous', _Filter.all, muted, fg, fieldBg),
              const SizedBox(width: 6),
              _chip('Installés (${_installed.length})', _Filter.installed,
                  muted, fg, fieldBg),
              const Spacer(),
              Text('${visible.length}',
                  style: TextStyle(fontSize: 11, color: muted)),
            ]),
          ),
          Divider(height: 14, thickness: 0.5, color: muted.withValues(alpha: 0.3)),
          // ── Results ─────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _error != null && visible.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded,
                                size: 40, color: muted.withValues(alpha: 0.5)),
                            const SizedBox(height: 10),
                            Text(_error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: muted)),
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              onPressed: _updateRepos,
                              icon: const Icon(Icons.sync_rounded, size: 15),
                              label: const Text('Mettre à jour les dépôts'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        strokeWidth: 2,
                        onRefresh: () async =>
                            _searchCtrl.text.trim().isEmpty
                                ? _refreshInstalled()
                                : _runSearch(),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, thickness: 0.4, indent: 44,
                                  color: muted.withValues(alpha: 0.25)),
                          itemBuilder: (ctx, i) =>
                              _tile(visible[i], isDark, fg, muted),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, _Filter value, Color muted, Color fg, Color bg) {
    final active = _filter == value;
    return InkWell(
      onTap: () => setState(() => _filter = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: active ? const Color(0xff094771) : bg,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: active ? const Color(0xff2b7bd3) : muted.withValues(alpha: 0.35),
            width: 0.7,
          ),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? Colors.white : muted)),
      ),
    );
  }

  Widget _tile(ApkPackage p, bool isDark, Color fg, Color muted) {
    final isInstalled = _installed.contains(p.name);
    return InkWell(
      onTap: () => _openDetail(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isInstalled
                    ? Colors.green.withValues(alpha: 0.14)
                    : Colors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Icon(
                isInstalled
                    ? Icons.check_circle_outline_rounded
                    : Icons.download_outlined,
                size: 17,
                color: isInstalled ? Colors.green.shade400 : Colors.blue.shade300,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: fg)),
                    ),
                    if (p.version.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Text(p.version,
                          style: TextStyle(fontSize: 10.5, color: muted)),
                    ],
                  ]),
                  if (p.description.isNotEmpty)
                    Text(p.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 28,
              child: isInstalled
                  ? OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        minimumSize: Size.zero,
                        side: BorderSide(
                            color: Colors.red.shade300.withValues(alpha: 0.6),
                            width: 0.8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => _uninstall(p),
                      child: Text('Suppr.',
                          style: TextStyle(
                              fontSize: 10.5, color: Colors.red.shade300)),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        minimumSize: Size.zero,
                        backgroundColor: const Color(0xff2b7bd3),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => _install(p),
                      child: const Text('Installer',
                          style: TextStyle(fontSize: 10.5)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Package detail sheet ────────────────────────────────────────────────────

class _PackageDetailSheet extends StatelessWidget {
  final ApkPackage pkg;
  const _PackageDetailSheet({required this.pkg});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xff252526) : Colors.white;
    final fg = isDark ? const Color(0xffcfcfcf) : const Color(0xff222222);
    final muted = isDark ? Colors.grey[500]! : Colors.grey[600]!;

    String stateLabel;
    Color stateColor;
    if (pkg.installed) {
      stateLabel = 'Installé';
      stateColor = Colors.green.shade400;
    } else {
      stateLabel = 'Non installé';
      stateColor = Colors.orange.shade400;
    }

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 18, offset: Offset(0, -2))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(pkg.name,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: fg)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(stateLabel,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: stateColor)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('Version : ${pkg.version.isEmpty ? '?' : pkg.version}',
                style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 10),
            Text(pkg.description.isEmpty ? 'Pas de description.' : pkg.description,
                style: TextStyle(fontSize: 12.5, height: 1.35, color: fg)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: muted.withValues(alpha: 0.45)),
                    foregroundColor: fg,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 15),
                  label: const Text('Fermer', style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Operation log sheet ─────────────────────────────────────────────────────

class _LogSheet extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final GlobalKey<_LogViewState> viewKey;

  const _LogSheet({
    required this.title,
    required this.controller,
    required this.viewKey,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xff181818) : const Color(0xff1e1e1e);
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(8),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24, width: 0.6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Row(children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
            Flexible(
              child: _LogView(key: viewKey, controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogView extends StatefulWidget {
  final TextEditingController controller;
  const _LogView({super.key, required this.controller});

  @override
  State<_LogView> createState() => _LogViewState();
}

class _LogViewState extends State<_LogView> {
  final _scroll = ScrollController();

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
    // Rebuild to pick up new text from the shared controller.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: SelectableText(
        widget.controller.text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 10.5,
          height: 1.35,
          color: Color(0xff9cdcfe),
        ),
      ),
    );
  }
}
