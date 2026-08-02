/// Page Marketplace Open VSX — redesigned.
///
/// Design: Telegram-style bottom pill navigation, animated collapsible search,
/// VSCode-like extension detail pages, runtime detail pages, real FA icons,
/// full app-theme compliance (zero hardcoded colours).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../models/marketplace_extension.dart';
import '../open_vsx_client.dart';
import '../extension_registry.dart';
import '../vsix_installer.dart';
import 'extension_settings_page.dart';
import '../../ui/adb_setup_page.dart';
import '../../services/flutter_sdk_service.dart';

// ── Categories ─────────────────────────────────────────────────────────────────
const _kCategories = [
  'All',
  'Programming Languages',
  'Snippets',
  'Linters',
  'Themes',
  'Debuggers',
  'Formatters',
  'Keymaps',
  'Other',
];

const _kSortOptions = {
  'Relevance': 'relevance',
  'Downloads': 'downloadCount',
  'Rating': 'rating',
  'Recent': 'timestamp',
};

// ── Section enum ───────────────────────────────────────────────────────────────
enum _Section { extensions, runtimes, installed }

// ── MarketplacePage ────────────────────────────────────────────────────────────
class MarketplacePage extends StatefulWidget {
  final bool embedded;
  const MarketplacePage({super.key, this.embedded = false});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  final _client = OpenVsxClient();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  _Section _section = _Section.extensions;

  List<MarketplaceExtension> _results = [];
  bool _loading = false;
  String? _error;
  int _offset = 0;
  int _totalSize = 0;
  bool _loadingMore = false;

  String _selectedCategory = 'All';
  String _sortBy = 'relevance';

  final Map<String, _InstallState> _installStates = {};

  Timer? _debounce;

  // Scroll-driven search collapse
  bool _searchCollapsed = false;
  double _lastScroll = 0;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _scrollCtrl.addListener(_onScroll);
    _loadFeatured();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _client.dispose();
    super.dispose();
  }

  // ── Scroll ─────────────────────────────────────────────────────────────────

  void _onScroll() {
    final pos = _scrollCtrl.position.pixels;
    final scrollingDown = pos > _lastScroll + 6;
    final scrollingUp   = pos < _lastScroll - 6;

    if (scrollingDown && !_searchCollapsed) {
      setState(() => _searchCollapsed = true);
    } else if (scrollingUp && _searchCollapsed) {
      setState(() => _searchCollapsed = false);
    }
    _lastScroll = pos;

    // Infinite scroll
    if (!_loadingMore && !_loading && _offset < _totalSize) {
      if (pos >= _scrollCtrl.position.maxScrollExtent - 200) {
        _offset = _results.length;
        _search(reset: false);
      }
    }
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _loadFeatured() async {
    setState(() { _loading = true; _error = null; _offset = 0; });
    try {
      final r = await _client.featured(size: 20);
      if (!mounted) return;
      setState(() { _results = r.extensions; _totalSize = r.totalSize; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _search({bool reset = true}) async {
    if (reset) {
      setState(() { _loading = true; _error = null; _offset = 0; _results = []; });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final category = _selectedCategory == 'All' ? null : _selectedCategory;
      final r = await _client.search(
        query: _searchCtrl.text.trim(),
        offset: _offset,
        size: 20,
        category: category,
        sortBy: _sortBy,
      );
      if (!mounted) return;
      setState(() {
        _results = reset ? r.extensions : [..._results, ...r.extensions];
        _totalSize = r.totalSize;
        _offset += r.extensions.length;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; _loadingMore = false; });
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _searchCtrl.text.trim().isEmpty ? _loadFeatured() : _search();
    });
  }

  // ── Install ────────────────────────────────────────────────────────────────

  Future<void> _install(MarketplaceExtension ext) async {
    setState(() => _installStates[ext.id] = _InstallState.installing);
    final installer = VsixInstaller(onProgress: (_, __) {});
    try {
      final result = await installer.installFromUrl(ext.buildDownloadUrl());
      if (!mounted) return;
      switch (result) {
        case InstallSuccess():
          setState(() => _installStates[ext.id] = _InstallState.installed);
          _showSnack('${ext.displayName} installed ✓');
        case InstallFailure(:final reason):
          setState(() => _installStates[ext.id] = _InstallState.error);
          _showSnack('Error: $reason', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _installStates[ext.id] = _InstallState.error);
      _showSnack('Error: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    Widget body = Column(
      children: [
        // ── Animated header ────────────────────────────────────────────────
        _MarketplaceHeader(
          section: _section,
          searchCtrl: _searchCtrl,
          collapsed: _searchCollapsed,
          sortBy: _sortBy,
          onSortChanged: (v) {
            setState(() => _sortBy = v);
            _searchCtrl.text.isEmpty ? _loadFeatured() : _search();
          },
          onSearchExpand: () => setState(() => _searchCollapsed = false),
        ),

        // ── Category chips (only for Extensions) ──────────────────────────
        if (_section == _Section.extensions)
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _kCategories.length,
              itemBuilder: (_, i) {
                final cat = _kCategories[i];
                final sel = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(cat, style: const TextStyle(fontSize: 12)),
                    selected: sel,
                    selectedColor: cs.primary.withOpacity(0.18),
                    checkmarkColor: cs.primary,
                    side: BorderSide(color: sel ? cs.primary : cs.outline),
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() => _selectedCategory = cat);
                      _searchCtrl.text.isEmpty ? _loadFeatured() : _search();
                    },
                  ),
                );
              },
            ),
          ),

        if (_section == _Section.extensions) const SizedBox(height: 4),

        // ── Body ──────────────────────────────────────────────────────────
        Expanded(child: _buildSectionBody(theme, cs)),

        // ── Bottom pill nav ───────────────────────────────────────────────
        _BottomPillNav(
          current: _section,
          onTap: (s) {
            setState(() {
              _section = s;
              _searchCollapsed = false;
            });
          },
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(body: body);
  }

  Widget _buildSectionBody(ThemeData theme, ColorScheme cs) {
    switch (_section) {
      case _Section.extensions:
        if (_loading) return const Center(child: CircularProgressIndicator());
        if (_error != null) return _ErrorView(error: _error!, onRetry: _loadFeatured);
        if (_results.isEmpty) return Center(
          child: Text('No extensions found',
              style: TextStyle(color: cs.onSurface.withOpacity(0.5))),
        );
        return ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          itemCount: _results.length + (_loadingMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == _results.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final ext = _results[i];
            return _ExtensionCard(
              ext: ext,
              installState: _installStates[ext.id] ?? _InstallState.notInstalled,
              onInstall: () => _install(ext),
              onTap: () => _openExtensionDetail(ext),
            );
          },
        );

      case _Section.runtimes:
        return _RuntimesSection(scrollCtrl: _scrollCtrl);

      case _Section.installed:
        return _InstalledSection();
    }
  }

  void _openExtensionDetail(MarketplaceExtension ext) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _ExtensionDetailPage(
        ext: ext,
        client: _client,
        installState: _installStates[ext.id] ?? _InstallState.notInstalled,
        onInstall: () => _install(ext),
      ),
    ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Animated header
// ══════════════════════════════════════════════════════════════════════════════

class _MarketplaceHeader extends StatelessWidget {
  final _Section section;
  final TextEditingController searchCtrl;
  final bool collapsed;
  final String sortBy;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onSearchExpand;

  const _MarketplaceHeader({
    required this.section,
    required this.searchCtrl,
    required this.collapsed,
    required this.sortBy,
    required this.onSortChanged,
    required this.onSearchExpand,
  });

  static const _sectionTitles = {
    _Section.extensions: 'Extensions',
    _Section.runtimes:   'Runtimes',
    _Section.installed:  'Installed',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;
    final title = _sectionTitles[section] ?? 'Marketplace';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      color: theme.appBarTheme.backgroundColor ?? cs.surface,
      padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 6, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Title row with collapse toggle ──────────────────────────────
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (section == _Section.extensions) ...[
                if (collapsed)
                  IconButton(
                    icon: Icon(Icons.search, color: cs.onSurface),
                    tooltip: 'Search',
                    onPressed: onSearchExpand,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                if (collapsed)
                  _SortButton(sortBy: sortBy, onSelected: onSortChanged),
              ],
            ],
          ),

          // ── Animated search bar ─────────────────────────────────────────
          if (section == _Section.extensions)
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: collapsed
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchCtrl,
                        style: theme.textTheme.bodyMedium,
                        decoration: InputDecoration(
                          hintText: 'Search extensions…',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withOpacity(0.4),
                          ),
                          prefixIcon: Icon(Icons.search, size: 18, color: cs.onSurface.withOpacity(0.5)),
                          suffixIcon: searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () => searchCtrl.clear(),
                                )
                              : null,
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: cs.primary, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _SortButton(sortBy: sortBy, onSelected: onSortChanged),
                  ],
                ),
              ),
              secondChild: const SizedBox(height: 2),
            ),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final String sortBy;
  final ValueChanged<String> onSelected;
  const _SortButton({required this.sortBy, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.sort, size: 20, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
      tooltip: 'Sort',
      onSelected: onSelected,
      itemBuilder: (_) => _kSortOptions.entries.map((e) => PopupMenuItem(
        value: e.value,
        child: Row(children: [
          if (sortBy == e.value)
            Icon(Icons.check, size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(e.key),
        ]),
      )).toList(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Bottom pill navigation (Telegram-style)
// ══════════════════════════════════════════════════════════════════════════════

class _BottomPillNav extends StatelessWidget {
  final _Section current;
  final ValueChanged<_Section> onTap;
  const _BottomPillNav({required this.current, required this.onTap});

  static const _items = [
    _NavItem(_Section.extensions, Icons.extension_outlined, Icons.extension,    'Extensions'),
    _NavItem(_Section.runtimes,   Icons.memory_outlined,    Icons.memory,        'Runtimes'),
    _NavItem(_Section.installed,  Icons.check_circle_outline, Icons.check_circle,'Installed'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor ?? cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.5))),
      ),
      padding: EdgeInsets.only(
        left: 12, right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: _items.map((item) {
          final sel = item.section == current;
          return GestureDetector(
            onTap: () => onTap(item.section),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? cs.primary.withOpacity(0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    sel ? item.activeIcon : item.icon,
                    size: 20,
                    color: sel ? cs.primary : cs.onSurface.withOpacity(0.55),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: sel
                        ? Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.primary,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _NavItem {
  final _Section section;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.section, this.icon, this.activeIcon, this.label);
}

// ══════════════════════════════════════════════════════════════════════════════
// Extension card
// ══════════════════════════════════════════════════════════════════════════════

enum _InstallState { notInstalled, installing, installed, error }

class _ExtensionCard extends StatelessWidget {
  final MarketplaceExtension ext;
  final _InstallState installState;
  final VoidCallback onInstall;
  final VoidCallback onTap;

  const _ExtensionCard({
    required this.ext,
    required this.installState,
    required this.onInstall,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sub = cs.onSurface.withOpacity(0.55);
    final alreadyInstalled = ExtensionRegistry.instance.isInstalled(ext.id) ||
        installState == _InstallState.installed;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ext.iconUrl != null
                    ? Image.network(ext.iconUrl!, width: 42, height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _DefaultExtIcon(size: 42))
                    : _DefaultExtIcon(size: 42),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          ext.displayName.isNotEmpty ? ext.displayName : ext.name,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('v${ext.version}',
                          style: TextStyle(fontSize: 10, color: sub)),
                    ]),
                    const SizedBox(height: 1),
                    Text(ext.namespace, style: TextStyle(fontSize: 11, color: sub)),
                    const SizedBox(height: 4),
                    Text(ext.description,
                        style: TextStyle(fontSize: 12,
                            color: cs.onSurface.withOpacity(0.8)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Row(children: [
                      if (ext.averageRating != null) ...[
                        const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(ext.averageRating!.toStringAsFixed(1),
                            style: TextStyle(fontSize: 11, color: sub)),
                        const SizedBox(width: 8),
                      ],
                      if (ext.downloadCount > 0) ...[
                        Icon(Icons.download_outlined, size: 12, color: sub),
                        const SizedBox(width: 2),
                        Text(_fmtCount(ext.downloadCount),
                            style: TextStyle(fontSize: 11, color: sub)),
                      ],
                      if (ext.categories.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(ext.categories.first,
                              style: TextStyle(fontSize: 10, color: cs.primary)),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // Install / download button
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _InstallButton(
                    state: alreadyInstalled ? _InstallState.installed : installState,
                    onPressed: alreadyInstalled ? null : onInstall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }
}

class _InstallButton extends StatelessWidget {
  final _InstallState state;
  final VoidCallback? onPressed;
  const _InstallButton({required this.state, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (state) {
      case _InstallState.notInstalled:
        return SizedBox(
          height: 30,
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              backgroundColor: cs.primary.withOpacity(0.1),
              foregroundColor: cs.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('Install', style: TextStyle(fontSize: 12)),
          ),
        );
      case _InstallState.installing:
        return const SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _InstallState.installed:
        return Icon(Icons.check_circle_rounded,
            color: Theme.of(context).colorScheme.primary, size: 22);
      case _InstallState.error:
        return Icon(Icons.error_outline,
            color: Theme.of(context).colorScheme.error, size: 22);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Extension detail page (VSCode-style)
// ══════════════════════════════════════════════════════════════════════════════

class _ExtensionDetailPage extends StatefulWidget {
  final MarketplaceExtension ext;
  final OpenVsxClient client;
  final _InstallState installState;
  final VoidCallback onInstall;

  const _ExtensionDetailPage({
    required this.ext,
    required this.client,
    required this.installState,
    required this.onInstall,
  });

  @override
  State<_ExtensionDetailPage> createState() => _ExtensionDetailPageState();
}

class _ExtensionDetailPageState extends State<_ExtensionDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String? _readme;
  bool _readmeLoading = true;
  late _InstallState _installState;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _installState = widget.installState;
    _loadReadme();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadReadme() async {
    try {
      final r = await widget.client.getReadme(
          widget.ext.namespace, widget.ext.name, widget.ext.version);
      if (!mounted) return;
      setState(() { _readme = r; _readmeLoading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() _readmeLoading = false);
    }
  }

  Future<void> _doInstall() async {
    setState(() => _installState = _InstallState.installing);
    try {
      widget.onInstall();
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) setState(() => _installState = _InstallState.installed);
    } catch (e) {
      if (mounted) setState(() => _installState = _InstallState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ext = widget.ext;
    final alreadyInstalled = ExtensionRegistry.instance.isInstalled(ext.id) ||
        _installState == _InstallState.installed;

    return Scaffold(
      appBar: AppBar(
        title: Text(ext.displayName.isNotEmpty ? ext.displayName : ext.name,
            style: const TextStyle(fontSize: 16)),
        elevation: 0,
        bottom: TabBar(
          controller: _tab,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurface.withOpacity(0.55),
          indicatorColor: cs.primary,
          indicatorWeight: 2.5,
          tabs: const [
            Tab(text: 'Details'),
            Tab(text: 'Readme'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          // ── Details tab ──────────────────────────────────────────────
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Hero
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ext.iconUrl != null
                        ? Image.network(ext.iconUrl!, width: 72, height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _DefaultExtIcon(size: 72))
                        : _DefaultExtIcon(size: 72),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ext.displayName.isNotEmpty ? ext.displayName : ext.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(ext.namespace,
                            style: TextStyle(fontSize: 12,
                                color: cs.onSurface.withOpacity(0.55))),
                        const SizedBox(height: 8),
                        // Install / installed button
                        if (alreadyInstalled)
                          _OutlineBadge(
                            icon: Icons.check_circle_rounded,
                            label: 'Installed',
                            color: cs.primary,
                          )
                        else if (_installState == _InstallState.installing)
                          const SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          FilledButton.icon(
                            onPressed: _doInstall,
                            icon: const Icon(Icons.download_rounded, size: 16),
                            label: const Text('Install'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Description
              Text(ext.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withOpacity(0.8))),
              const SizedBox(height: 20),

              // Stats row
              _StatsRow(ext: ext),
              const SizedBox(height: 20),

              // Meta info
              _InfoTile(label: 'Publisher', value: ext.namespace),
              _InfoTile(label: 'Version', value: ext.version),
              if (ext.license != null && ext.license!.isNotEmpty)
                _InfoTile(label: 'License', value: ext.license!),
              if (ext.categories.isNotEmpty)
                _InfoTile(label: 'Categories', value: ext.categories.join(', ')),
              if (ext.tags.isNotEmpty)
                _InfoTile(label: 'Tags', value: ext.tags.take(8).join(', ')),
              if (ext.repository != null && ext.repository!.isNotEmpty) ...[
                const SizedBox(height: 4),
                _InfoTile(label: 'Repository', value: ext.repository!),
              ],
              const SizedBox(height: 20),

              // Settings button (only if installed)
              if (alreadyInstalled) ...[
                OutlinedButton.icon(
                  onPressed: () {
                    final installed = ExtensionRegistry.instance.get(ext.id);
                    if (installed != null) {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ExtensionSettingsPage(extension: installed),
                      ));
                    }
                  },
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('Extension Settings'),
                ),
                const SizedBox(height: 8),
              ],

              // Uninstall / reinstall
              if (alreadyInstalled)
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Uninstall'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error),
                ),
            ],
          ),

          // ── Readme tab ───────────────────────────────────────────────
          _readmeLoading
              ? const Center(child: CircularProgressIndicator())
              : _readme == null || _readme!.isEmpty
                  ? Center(
                      child: Text('No readme available',
                          style: TextStyle(
                              color: cs.onSurface.withOpacity(0.5))))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: _MarkdownText(source: _readme!),
                    ),
        ],
      ),
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final MarketplaceExtension ext;
  const _StatsRow({required this.ext});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = cs.onSurface.withOpacity(0.55);
    return Row(
      children: [
        if (ext.averageRating != null) ...[
          _StatChip(
            icon: Icons.star_rounded,
            iconColor: Colors.amber,
            label: ext.averageRating!.toStringAsFixed(1),
            sub: '${ext.reviewCount} reviews',
          ),
          const SizedBox(width: 12),
        ],
        if (ext.downloadCount > 0)
          _StatChip(
            icon: Icons.download_rounded,
            iconColor: cs.primary,
            label: _fmtCount(ext.downloadCount),
            sub: 'installs',
          ),
      ],
    );
  }

  static String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String sub;
  const _StatChip({required this.icon, required this.iconColor,
      required this.label, required this.sub});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
              Text(sub, style: TextStyle(
                  fontSize: 10, color: cs.onSurface.withOpacity(0.55))),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: TextStyle(fontSize: 12,
                    color: cs.onSurface.withOpacity(0.55),
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _OutlineBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _OutlineBadge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(20),
        color: color.withOpacity(0.08),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color,
              fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Runtimes section
// ══════════════════════════════════════════════════════════════════════════════

class _RuntimeInfo {
  final String key;
  final String name;
  final String description;
  final String version;
  final String longDescription;
  final String website;
  final Widget icon;
  final String useCase;
  /// Optional label for an extra action button shown in the detail page.
  final String? extraAction;

  const _RuntimeInfo({
    required this.key,
    required this.name,
    required this.description,
    required this.version,
    required this.longDescription,
    required this.website,
    required this.icon,
    required this.useCase,
    this.extraAction,
  });
}

final _kRuntimes = <_RuntimeInfo>[
  _RuntimeInfo(
    key: 'flutter',
    name: 'Flutter SDK',
    description: 'Flutter framework + Dart SDK + flutter run',
    version: '3.x stable',
    longDescription:
        'The full Flutter SDK for ARM64 Android. Includes the flutter CLI, '
        'Dart SDK, pub package manager, and everything needed to run '
        '"flutter run", "flutter build apk", and "flutter pub get" '
        'directly on this device — no computer required.\n\n'
        'After installing, open the ADB Setup page to enable '
        '"flutter run" on your device via Shizuku or Wireless ADB.',
    website: 'https://flutter.dev',
    useCase: 'flutter run / build / pub get directly on your phone',
    icon: const Icon(Icons.flutter_dash, size: 26, color: Color(0xFF54C5F8)),
    extraAction: 'ADB Setup for flutter run',
  ),
  _RuntimeInfo(
    key: 'android-sdk',
    name: 'Android SDK (platform-tools)',
    description: 'adb, fastboot — required for flutter run',
    version: 'r35+',
    longDescription:
        'Android SDK platform-tools provides the adb (Android Debug Bridge) '
        'binary for ARM64 Android. This is required for "flutter run" '
        'and for wireless debugging. Install this alongside the Flutter SDK.',
    website: 'https://developer.android.com/studio/releases/platform-tools',
    useCase: 'flutter run, adb install, adb shell, wireless debugging',
    icon: const FaIcon(FontAwesomeIcons.android, size: 26,
        color: Color(0xFF3DDC84)),
  ),
  _RuntimeInfo(
    key: 'node',
    name: 'Node.js',
    description: 'JavaScript / TypeScript runtime',
    version: '22.x LTS',
    longDescription:
        'Node.js is an open-source, cross-platform JavaScript runtime environment. '
        'It executes JavaScript outside a web browser using V8, the same engine that powers Chrome. '
        'Ideal for server-side scripting, CLI tools, and full-stack TypeScript projects.',
    website: 'https://nodejs.org',
    useCase: 'Web servers, REST APIs, CLI tools, TypeScript apps',
    icon: const FaIcon(FontAwesomeIcons.nodeJs, size: 26, color: Color(0xFF539E43)),
  ),
  _RuntimeInfo(
    key: 'python',
    name: 'Python',
    description: 'Python 3 interpreter & pip',
    version: '3.12',
    longDescription:
        'Python is a high-level, general-purpose language renowned for its readability. '
        'Comes with pip for package management and supports NumPy, pandas, Django, Flask, '
        'FastAPI, and the entire data-science & ML ecosystem.',
    website: 'https://python.org',
    useCase: 'Data science, ML, scripting, web (Django/Flask)',
    icon: const FaIcon(FontAwesomeIcons.python, size: 26, color: Color(0xFF3776AB)),
  ),
  _RuntimeInfo(
    key: 'java',
    name: 'Java',
    description: 'JDK 21 Temurin (LTS)',
    version: '21 LTS',
    longDescription:
        'Java is a class-based, object-oriented language designed for portability. '
        'JDK 21 (Eclipse Temurin) is a long-term-support release with virtual threads '
        'via Project Loom, pattern matching, and record classes.',
    website: 'https://adoptium.net',
    useCase: 'Android dev, enterprise apps, Spring Boot',
    icon: const FaIcon(FontAwesomeIcons.java, size: 26, color: Color(0xFFED8B00)),
  ),
  _RuntimeInfo(
    key: 'kotlin',
    name: 'Kotlin',
    description: 'Kotlin SDK & Gradle',
    version: '2.x',
    longDescription:
        'Kotlin is a modern, statically typed language that runs on the JVM. '
        'It is 100 % interoperable with Java and is the preferred language for Android development. '
        'Also supports Kotlin Multiplatform for sharing code across iOS, Android, and web.',
    website: 'https://kotlinlang.org',
    useCase: 'Android, Kotlin Multiplatform, server-side',
    icon: const FaIcon(FontAwesomeIcons.k, size: 26, color: Color(0xFF7F52FF)),
  ),
  _RuntimeInfo(
    key: 'dart',
    name: 'Dart',
    description: 'Dart SDK & Flutter CLI',
    version: '3.x',
    longDescription:
        'Dart is an optimised language for building fast apps on any platform. '
        'Paired with Flutter it enables beautiful, natively compiled applications '
        'for mobile, web, and desktop from a single codebase.',
    website: 'https://dart.dev',
    useCase: 'Flutter apps, CLI tools, server-side Dart',
    icon: const Icon(Icons.flutter_dash, size: 26, color: Color(0xFF0175C2)),
  ),
  _RuntimeInfo(
    key: 'go',
    name: 'Go',
    description: 'Go toolchain',
    version: '1.22',
    longDescription:
        'Go (Golang) is a statically typed, compiled language with built-in concurrency '
        'primitives (goroutines & channels). Produces small, fast binaries with no runtime '
        'dependencies — great for CLI tools, microservices, and cloud-native apps.',
    website: 'https://go.dev',
    useCase: 'CLIs, microservices, cloud-native backends',
    icon: const FaIcon(FontAwesomeIcons.golang, size: 26, color: Color(0xFF00ADD8)),
  ),
  _RuntimeInfo(
    key: 'rust',
    name: 'Rust',
    description: 'Rust toolchain (rustup)',
    version: 'stable',
    longDescription:
        'Rust is a systems programming language focused on safety, speed, and concurrency. '
        'Its ownership model guarantees memory safety without a garbage collector. '
        'Requires Clang runtime.',
    website: 'https://rust-lang.org',
    useCase: 'Systems, WebAssembly, CLI tools, embedded',
    icon: const FaIcon(FontAwesomeIcons.rust, size: 26, color: Color(0xFFDEA584)),
  ),
  _RuntimeInfo(
    key: 'clang',
    name: 'Clang / LLVM',
    description: 'C / C++ compiler suite',
    version: '21',
    longDescription:
        'Clang is a compiler front-end for C, C++, and Objective-C using LLVM as its back-end. '
        'Required as a dependency for Rust and Go on Android. '
        'Provides full C17/C++23 support with sanitizers.',
    website: 'https://clang.llvm.org',
    useCase: 'C/C++ native code, required for Rust & Go',
    icon: const FaIcon(FontAwesomeIcons.c, size: 26, color: Color(0xFF00599C)),
  ),
  _RuntimeInfo(
    key: 'ruby',
    name: 'Ruby',
    description: 'Ruby interpreter & gems',
    version: '3.3',
    longDescription:
        'Ruby is a dynamic, reflective, object-oriented language. '
        'Popular for its elegant syntax and the Ruby on Rails web framework. '
        'Bundler and RubyGems come included.',
    website: 'https://ruby-lang.org',
    useCase: 'Web (Rails), scripting, DevOps automation',
    icon: const FaIcon(FontAwesomeIcons.gem, size: 24, color: Color(0xFFCC342D)),
  ),
  _RuntimeInfo(
    key: 'lua',
    name: 'Lua',
    description: 'Lightweight scripting language',
    version: '5.4',
    longDescription:
        'Lua is a lightweight, high-level, multi-paradigm scripting language designed '
        'for embedded use. Widely used in game engines (Love2D, Roblox) and as an '
        'extension language for applications.',
    website: 'https://lua.org',
    useCase: 'Game scripting, embedded configs, Neovim plugins',
    icon: const Icon(Icons.code, size: 26, color: Color(0xFF000080)),
  ),
];

class _RuntimesSection extends StatelessWidget {
  final ScrollController scrollCtrl;
  const _RuntimesSection({required this.scrollCtrl});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      itemCount: _kRuntimes.length,
      itemBuilder: (_, i) => _RuntimeCard(info: _kRuntimes[i]),
    );
  }
}

class _RuntimeCard extends StatelessWidget {
  final _RuntimeInfo info;
  const _RuntimeCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => _RuntimeDetailPage(info: info))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Icon circle
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Center(child: info.icon),
              ),
              const SizedBox(width: 14),

              // Name + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(info.description,
                        style: TextStyle(fontSize: 12,
                            color: cs.onSurface.withOpacity(0.55))),
                  ],
                ),
              ),

              // Version chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(info.version,
                    style: TextStyle(fontSize: 11,
                        color: cs.primary, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),

              // Download icon
              IconButton(
                icon: Icon(Icons.download_rounded,
                    size: 20, color: cs.primary),
                tooltip: 'Install ${info.name}',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => _RuntimeDetailPage(info: info))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Runtime detail page
// ══════════════════════════════════════════════════════════════════════════════

class _RuntimeDetailPage extends StatelessWidget {
  final _RuntimeInfo info;
  const _RuntimeDetailPage({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(info.name),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Hero
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(child: info.icon),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(info.description,
                        style: TextStyle(fontSize: 13,
                            color: cs.onSurface.withOpacity(0.55))),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text('v${info.version}',
                          style: TextStyle(fontSize: 12,
                              color: cs.primary, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Install button
          FilledButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Installing ${info.name}…'),
                behavior: SnackBarBehavior.floating,
              ));
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text('Install ${info.name}'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),

          // Extra action (e.g. ADB Setup for Flutter SDK)
          if (info.extraAction != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AdbSetupPage())),
              icon: const Icon(Icons.usb_rounded, size: 16),
              label: Text(info.extraAction!),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
          const SizedBox(height: 20),

          // About
          _SectionHeader(title: 'About'),
          const SizedBox(height: 8),
          Text(info.longDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.85), height: 1.6)),
          const SizedBox(height: 20),

          // Use cases
          _SectionHeader(title: 'Use Cases'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 18,
                    color: cs.primary.withOpacity(0.8)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(info.useCase,
                      style: TextStyle(fontSize: 13,
                          color: cs.onSurface.withOpacity(0.85))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Website
          _SectionHeader(title: 'Official Website'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.language, size: 18,
                    color: cs.onSurface.withOpacity(0.55)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(info.website,
                      style: TextStyle(fontSize: 13, color: cs.primary,
                          decoration: TextDecoration.underline)),
                ),
                Icon(Icons.open_in_new, size: 14,
                    color: cs.onSurface.withOpacity(0.4)),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: cs.onSurface.withOpacity(0.7),
          letterSpacing: 0.4,
        ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Installed section
// ══════════════════════════════════════════════════════════════════════════════

class _InstalledSection extends StatelessWidget {
  const _InstalledSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final installed = ExtensionRegistry.instance.allInstalled();

    if (installed.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.extension_outlined, size: 52,
                  color: cs.onSurface.withOpacity(0.3)),
              const SizedBox(height: 14),
              Text('No extensions installed',
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.6))),
              const SizedBox(height: 6),
              Text('Browse Extensions to install one.',
                  style: TextStyle(fontSize: 12,
                      color: cs.onSurface.withOpacity(0.45)),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      itemCount: installed.length,
      itemBuilder: (_, i) {
        final extId = installed[i];
        final ext = ExtensionRegistry.instance.get(extId);
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
          ),
          child: ListTile(
            leading: _DefaultExtIcon(size: 40),
            title: Text(
              ext?.manifest.displayName ?? extId,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              ext?.manifest.description ?? 'Installed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11,
                  color: cs.onSurface.withOpacity(0.55)),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ext != null)
                  IconButton(
                    icon: Icon(Icons.settings_outlined, size: 18,
                        color: cs.onSurface.withOpacity(0.55)),
                    tooltip: 'Settings',
                    onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ExtensionSettingsPage(extension: ext),
                    )),
                  ),
                Icon(Icons.check_circle_rounded, color: cs.primary, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared helpers
// ══════════════════════════════════════════════════════════════════════════════

class _DefaultExtIcon extends StatelessWidget {
  final double size;
  const _DefaultExtIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.extension_rounded,
          size: size * 0.55, color: cs.primary),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48,
                color: cs.onSurface.withOpacity(0.35)),
            const SizedBox(height: 12),
            Text('Could not load extensions',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(error,
                style: TextStyle(fontSize: 11,
                    color: cs.onSurface.withOpacity(0.5)),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Very basic markdown renderer — just preserves line breaks and
/// shows code blocks in a monospace style. No extra dependencies needed.
class _MarkdownText extends StatelessWidget {
  final String source;
  const _MarkdownText({required this.source});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final lines = source.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        // Headings
        if (line.startsWith('### ')) {
          return Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(line.substring(4),
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700)),
          );
        }
        if (line.startsWith('## ')) {
          return Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 6),
            child: Text(line.substring(3),
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700)),
          );
        }
        if (line.startsWith('# ')) {
          return Padding(
            padding: const EdgeInsets.only(top: 22, bottom: 8),
            child: Text(line.substring(2),
                style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700)),
          );
        }
        // Code block fence — just show as monospace
        if (line.startsWith('```')) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(line,
                style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: cs.onSurface.withOpacity(0.8))),
          );
        }
        // Horizontal rule
        if (line.trim() == '---' || line.trim() == '___') {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: cs.outlineVariant),
          );
        }
        // Normal text
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text(line,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.85), height: 1.6)),
        );
      }).toList(),
    );
  }
}
