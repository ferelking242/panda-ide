/// Page Marketplace — Panda IDE
///
/// Header fixe (icône + titre + loupe + 3-points).
/// Barre de recherche + category pills collapsibles au scroll.
/// Navigation par pills en bas (3 onglets).
/// Tap sur une extension → fiche détail (bottom sheet).
/// Tap sur un runtime  → fiche détail avec paramètres.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/marketplace_extension.dart';
import '../open_vsx_client.dart';
import '../extension_registry.dart';
import '../vsix_installer.dart';

// ── Constantes ────────────────────────────────────────────────────────────────

const _kAccent = Color(0xFF0078D4);

const _kCategories = [
  'All', 'Programming Languages', 'Snippets', 'Linters',
  'Themes', 'Debuggers', 'Formatters', 'Keymaps', 'Other',
];

const _kSortOptions = {
  'Relevance': 'relevance',
  'Downloads': 'downloadCount',
  'Rating': 'rating',
  'Recent': 'timestamp',
};

// ─────────────────────────────────────────────────────────────────────────────
// MarketplacePage
// ─────────────────────────────────────────────────────────────────────────────

class MarketplacePage extends StatefulWidget {
  final bool embedded;
  const MarketplacePage({super.key, this.embedded = false});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage>
    with SingleTickerProviderStateMixin {

  final _client      = OpenVsxClient();
  final _searchCtrl  = TextEditingController();
  final _scrollCtrl  = ScrollController();
  late  TabController _tabCtrl;

  // Extensions tab state
  List<MarketplaceExtension> _results     = [];
  bool   _loading     = false;
  String? _error;
  int    _offset      = 0;
  int    _totalSize   = 0;
  bool   _loadingMore = false;
  String _selectedCategory = 'All';
  String _sortBy           = 'relevance';
  final Map<String, _InstallState> _installStates = {};

  // Header collapse state
  bool _headerExpanded = true; // true = search bar + pills visible

  Timer? _debounce;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(_onSearchChanged);
    _scrollCtrl.addListener(_onScroll);
    _loadFeatured();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _client.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

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
        _results   = reset ? r.extensions : [..._results, ...r.extensions];
        _totalSize = r.totalSize;
        _offset   += r.extensions.length;
        _loading = _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = _loadingMore = false; });
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _searchCtrl.text.trim().isEmpty ? _loadFeatured() : _search();
    });
  }

  void _onScroll() {
    // Collapse / expand collapsible header zone
    final collapsed = _scrollCtrl.hasClients && _scrollCtrl.offset > 56;
    if (collapsed == _headerExpanded) {
      setState(() => _headerExpanded = !collapsed);
    }
    // Infinite scroll
    if (_loadingMore || _loading || _offset >= _totalSize) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      _offset = _results.length;
      _search(reset: false);
    }
  }

  // ── Install ────────────────────────────────────────────────────────────────

  Future<void> _install(MarketplaceExtension ext) async {
    setState(() => _installStates[ext.id] = _InstallState.installing);
    final installer = VsixInstaller(onProgress: (_, __) {});
    try {
      final url    = ext.buildDownloadUrl();
      final result = await installer.installFromUrl(url);
      if (!mounted) return;
      switch (result) {
        case InstallSuccess():
          setState(() => _installStates[ext.id] = _InstallState.installed);
          _showSnack('${ext.displayName} installé ✓');
        case InstallFailure(:final reason):
          setState(() => _installStates[ext.id] = _InstallState.error);
          _showSnack('Erreur : $reason', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _installStates[ext.id] = _InstallState.error);
      _showSnack('Erreur : $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Detail sheets ──────────────────────────────────────────────────────────

  void _openExtensionDetail(MarketplaceExtension ext) {
    final installState = ExtensionRegistry.instance.isInstalled(ext.id)
        ? _InstallState.installed
        : _installStates[ext.id] ?? _InstallState.notInstalled;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExtensionDetailSheet(
        ext: ext,
        installState: installState,
        onInstall: () async {
          Navigator.pop(context);
          await _install(ext);
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final body = Column(
      children: [
        // ── Fixed header ──────────────────────────────────────────────────
        _MarketplaceHeader(
          expanded: _headerExpanded,
          searchCtrl: _searchCtrl,
          sortBy: _sortBy,
          selectedCategory: _selectedCategory,
          onSearchIconTap: () {
            if (!_headerExpanded) setState(() => _headerExpanded = true);
            if (_scrollCtrl.hasClients) {
              _scrollCtrl.animateTo(0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut);
            }
          },
          onSortChanged: (v) {
            setState(() => _sortBy = v);
            _searchCtrl.text.isEmpty ? _loadFeatured() : _search();
          },
          onClearSearch: () {
            _searchCtrl.clear();
            _loadFeatured();
          },
          onCategoryChanged: (cat) {
            setState(() => _selectedCategory = cat);
            _searchCtrl.text.isEmpty ? _loadFeatured() : _search();
          },
        ),

        // ── Tab content ───────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              // Tab 0 — Extensions
              _ExtensionsTab(
                results: _results,
                loading: _loading,
                loadingMore: _loadingMore,
                error: _error,
                scrollCtrl: _scrollCtrl,
                installStates: _installStates,
                onInstall: _install,
                onTap: _openExtensionDetail,
                onRetry: _loadFeatured,
              ),

              // Tab 1 — Runtimes
              const _RuntimesTab(),

              // Tab 2 — Installed
              const _InstalledTab(),
            ],
          ),
        ),

        // ── Bottom pill navigation ────────────────────────────────────────
        _BottomPillNav(
          controller: _tabCtrl,
          onSelect: (i) => _tabCtrl.animateTo(i),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(backgroundColor: cs.surface, body: body);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header with collapsible search + chips
// ─────────────────────────────────────────────────────────────────────────────

class _MarketplaceHeader extends StatelessWidget {
  final bool expanded;
  final TextEditingController searchCtrl;
  final String sortBy;
  final String selectedCategory;
  final VoidCallback onSearchIconTap;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onCategoryChanged;

  const _MarketplaceHeader({
    required this.expanded,
    required this.searchCtrl,
    required this.sortBy,
    required this.selectedCategory,
    required this.onSearchIconTap,
    required this.onSortChanged,
    required this.onClearSearch,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top;

    return Container(
      color: cs.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Fixed row: icon / title / actions ────────────────────────
          SizedBox(
            height: top + 52,
            child: Padding(
              padding: EdgeInsets.only(top: top, left: 4, right: 4),
              child: Row(
                children: [
                  // Store icon
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.store_rounded, size: 22,
                        color: cs.onSurfaceVariant),
                  ),
                  // Title
                  Text('Marketplace',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  // Search icon (visible when collapsed, or always tappable)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: expanded
                        ? const SizedBox(width: 40)
                        : IconButton(
                            key: const ValueKey('search_icon'),
                            icon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                            tooltip: 'Rechercher',
                            onPressed: onSearchIconTap,
                          ),
                  ),
                  // Sort menu
                  PopupMenuButton<String>(
                    icon: Icon(Icons.sort_rounded, size: 20,
                        color: cs.onSurfaceVariant),
                    tooltip: 'Trier par',
                    onSelected: onSortChanged,
                    itemBuilder: (_) => _kSortOptions.entries.map((e) =>
                      PopupMenuItem(
                        value: e.value,
                        child: Row(children: [
                          Icon(sortBy == e.value ? Icons.check : Icons.radio_button_unchecked,
                              size: 16, color: sortBy == e.value ? _kAccent : null),
                          const SizedBox(width: 10),
                          Text(e.key),
                        ]),
                      ),
                    ).toList(),
                  ),
                  // 3-dot menu
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, size: 20,
                        color: cs.onSurfaceVariant),
                    tooltip: 'Plus',
                    onSelected: (_) {},
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'refresh',
                          child: Text('Actualiser')),
                      PopupMenuItem(value: 'about',
                          child: Text('À propos')),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Collapsible: search bar + category chips ──────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            child: expanded
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Search bar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: TextField(
                          controller: searchCtrl,
                          style: TextStyle(fontSize: 14, color: cs.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Rechercher des extensions…',
                            hintStyle: TextStyle(
                                fontSize: 14, color: cs.onSurfaceVariant),
                            prefixIcon: Icon(Icons.search_rounded, size: 20,
                                color: cs.onSurfaceVariant),
                            suffixIcon: searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 18),
                                    onPressed: onClearSearch,
                                  )
                                : null,
                            filled: true,
                            fillColor: cs.surfaceContainerHigh,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                  color: cs.outlineVariant, width: 0.8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                  color: cs.outlineVariant, width: 0.8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: _kAccent, width: 1.5),
                            ),
                          ),
                        ),
                      ),

                      // Category chips
                      SizedBox(
                        height: 36,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                          itemCount: _kCategories.length,
                          itemBuilder: (_, i) {
                            final cat      = _kCategories[i];
                            final selected = cat == selectedCategory;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(cat,
                                    style: const TextStyle(fontSize: 11)),
                                selected: selected,
                                onSelected: (_) => onCategoryChanged(cat),
                                selectedColor: _kAccent.withOpacity(0.15),
                                checkmarkColor: _kAccent,
                                labelStyle: TextStyle(
                                  color: selected ? _kAccent : cs.onSurfaceVariant,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                                side: BorderSide(
                                  color: selected
                                      ? _kAccent.withOpacity(0.6)
                                      : cs.outlineVariant,
                                ),
                                showCheckmark: false,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 0),
                                visualDensity: VisualDensity.compact,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          // Bottom border
          Divider(height: 1, thickness: 0.5, color: cs.outlineVariant),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom pill navigation bar
// ─────────────────────────────────────────────────────────────────────────────

class _BottomPillNav extends StatefulWidget {
  final TabController controller;
  final ValueChanged<int> onSelect;
  const _BottomPillNav({required this.controller, required this.onSelect});

  @override
  State<_BottomPillNav> createState() => _BottomPillNavState();
}

class _BottomPillNavState extends State<_BottomPillNav> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() => _index = widget.controller.index);
  }

  static const _tabs = [
    (Icons.extension_rounded, 'Extensions'),
    (Icons.settings_applications_rounded, 'Runtimes'),
    (Icons.check_circle_rounded, 'Installées'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottom + 10),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final (icon, label) = _tabs[i];
          final selected = i == _index;
          return Expanded(
            child: GestureDetector(
              onTap: () => widget.onSelect(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? _kAccent.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                      size: 18,
                      color: selected ? _kAccent : cs.onSurfaceVariant,
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: selected
                          ? Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _kAccent,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 0 — Extensions
// ─────────────────────────────────────────────────────────────────────────────

class _ExtensionsTab extends StatelessWidget {
  final List<MarketplaceExtension> results;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final ScrollController scrollCtrl;
  final Map<String, _InstallState> installStates;
  final Future<void> Function(MarketplaceExtension) onInstall;
  final void Function(MarketplaceExtension) onTap;
  final VoidCallback onRetry;

  const _ExtensionsTab({
    required this.results,
    required this.loading,
    required this.loadingMore,
    required this.error,
    required this.scrollCtrl,
    required this.installStates,
    required this.onInstall,
    required this.onTap,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return _ErrorView(error: error!, onRetry: onRetry);
    }
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48,
                color: cs.onSurfaceVariant.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text('Aucune extension trouvée',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: results.length + (loadingMore ? 1 : 0),
      separatorBuilder: (_, __) =>
          Divider(height: 1, indent: 68, endIndent: 16,
              color: cs.outlineVariant.withOpacity(0.5)),
      itemBuilder: (_, i) {
        if (i == results.length) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final ext = results[i];
        final state = ExtensionRegistry.instance.isInstalled(ext.id)
            ? _InstallState.installed
            : installStates[ext.id] ?? _InstallState.notInstalled;
        return _ExtensionRow(
          ext: ext,
          installState: state,
          onInstall: () => onInstall(ext),
          onTap: () => onTap(ext),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension row (list item)
// ─────────────────────────────────────────────────────────────────────────────

class _ExtensionRow extends StatelessWidget {
  final MarketplaceExtension ext;
  final _InstallState installState;
  final VoidCallback onInstall;
  final VoidCallback onTap;

  const _ExtensionRow({
    required this.ext,
    required this.installState,
    required this.onInstall,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final sub = cs.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            _ExtIcon(url: ext.iconUrl, size: 44),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ext.displayName.isNotEmpty ? ext.displayName : ext.name,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('v${ext.version}',
                          style: TextStyle(fontSize: 10, color: sub)),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(ext.namespace,
                      style: TextStyle(fontSize: 11, color: _kAccent)),
                  const SizedBox(height: 3),
                  Text(
                    ext.description,
                    style: TextStyle(fontSize: 12, color: sub),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  // Stats row
                  Row(
                    children: [
                      if (ext.averageRating != null) ...[
                        const Icon(Icons.star_rounded,
                            size: 12, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(ext.averageRating!.toStringAsFixed(1),
                            style: TextStyle(fontSize: 10, color: sub)),
                        const SizedBox(width: 8),
                      ],
                      if (ext.downloadCount > 0) ...[
                        Icon(Icons.download_rounded, size: 12, color: sub),
                        const SizedBox(width: 2),
                        Text(_fmt(ext.downloadCount),
                            style: TextStyle(fontSize: 10, color: sub)),
                        const SizedBox(width: 8),
                      ],
                      if (ext.categories.isNotEmpty)
                        _Tag(ext.categories.first),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Install / status button
            _InstallBtn(state: installState, onPressed: onInstall),
          ],
        ),
      ),
    );
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension detail bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ExtensionDetailSheet extends StatelessWidget {
  final MarketplaceExtension ext;
  final _InstallState installState;
  final VoidCallback onInstall;

  const _ExtensionDetailSheet({
    required this.ext,
    required this.installState,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final sub = cs.onSurfaceVariant;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ExtIcon(url: ext.iconUrl, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ext.displayName.isNotEmpty ? ext.displayName : ext.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(ext.namespace,
                            style: const TextStyle(
                              fontSize: 13,
                              color: _kAccent,
                              fontWeight: FontWeight.w500,
                            )),
                        const SizedBox(height: 4),
                        Row(children: [
                          if (ext.averageRating != null) ...[
                            Row(
                              children: List.generate(5, (i) => Icon(
                                i < ext.averageRating!.round()
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 14,
                                color: Colors.amber,
                              )),
                            ),
                            const SizedBox(width: 4),
                            Text(ext.averageRating!.toStringAsFixed(1),
                                style: TextStyle(fontSize: 12, color: sub)),
                            Text(' (${ext.reviewCount})',
                                style: TextStyle(fontSize: 12, color: sub)),
                            const SizedBox(width: 10),
                          ],
                          if (ext.downloadCount > 0)
                            Row(children: [
                              Icon(Icons.download_rounded, size: 13, color: sub),
                              const SizedBox(width: 2),
                              Text(_fmtCount(ext.downloadCount),
                                  style: TextStyle(fontSize: 12, color: sub)),
                            ]),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Install button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                child: _DetailInstallBtn(
                  state: installState,
                  onPressed: installState == _InstallState.notInstalled
                      ? onInstall : null,
                ),
              ),
            ),
            const SizedBox(height: 16),

            Divider(height: 1, color: cs.outlineVariant),

            // Scrollable details
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  // Description
                  _DetailSection(
                    title: 'Description',
                    child: Text(
                      ext.description.isNotEmpty
                          ? ext.description
                          : 'Aucune description disponible.',
                      style: TextStyle(fontSize: 13.5, color: cs.onSurface,
                          height: 1.5),
                    ),
                  ),

                  // Meta info
                  _DetailSection(
                    title: 'Informations',
                    child: Column(
                      children: [
                        _InfoRow('Identifiant',  ext.id),
                        _InfoRow('Version',      'v${ext.version}'),
                        _InfoRow('Éditeur',      ext.namespace),
                        if (ext.license != null)
                          _InfoRow('Licence', ext.license!),
                        if (ext.timestamp != null)
                          _InfoRow('Mis à jour',
                              _fmtDate(ext.timestamp!)),
                        _InfoRow('Source', 'open-vsx.org'),
                      ],
                    ),
                  ),

                  // Categories & tags
                  if (ext.categories.isNotEmpty || ext.tags.isNotEmpty)
                    _DetailSection(
                      title: 'Catégories & Tags',
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final c in ext.categories) _Tag(c),
                          for (final t in ext.tags.take(8))
                            _Tag(t, muted: true),
                        ],
                      ),
                    ),

                  // Repository
                  if (ext.repository != null)
                    _DetailSection(
                      title: 'Dépôt',
                      child: Row(children: [
                        Icon(Icons.open_in_new_rounded, size: 14,
                            color: _kAccent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(ext.repository!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: _kAccent,
                              decoration: TextDecoration.underline,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 — Runtimes
// ─────────────────────────────────────────────────────────────────────────────

class _RuntimesTab extends StatelessWidget {
  const _RuntimesTab();

  static const _runtimes = [
    _RuntimeInfo(
      name: 'Node.js',
      description: 'Runtime JavaScript / TypeScript côté serveur',
      icon: Icons.javascript_rounded,
      version: '22.x LTS',
      source: 'nodejs.org/dist (binaire officiel)',
      longDesc:
          'Node.js est un environnement d\'exécution JavaScript construit '
          'sur le moteur V8 de Chrome. Il permet d\'exécuter du JavaScript '
          'en dehors du navigateur, côté serveur.',
      features: ['npm / npx', 'ESModules', 'TypeScript (via ts-node)', 'WASM'],
      parameters: [
        _Param('--max-old-space-size', 'Limite la mémoire heap V8 (en Mo)'),
        _Param('NODE_ENV', 'Environnement (development / production)'),
        _Param('--experimental-fetch', 'Active l\'API Fetch native'),
      ],
    ),
    _RuntimeInfo(
      name: 'Python',
      description: 'Interpréteur Python 3 + pip + venv',
      icon: Icons.code_rounded,
      version: '3.12',
      source: 'python.org/ftp (CPython officiel)',
      longDesc:
          'Python est un langage de programmation polyvalent et lisible. '
          'La distribution CPython inclut pip, venv et la bibliothèque standard complète.',
      features: ['pip / pip3', 'venv', 'jupyter', 'asyncio', 'type hints'],
      parameters: [
        _Param('PYTHONPATH', 'Chemins de recherche des modules'),
        _Param('PYTHONDONTWRITEBYTECODE', 'Désactive les fichiers .pyc'),
        _Param('-O', 'Mode optimisé (supprime les assertions)'),
      ],
    ),
    _RuntimeInfo(
      name: 'Dart',
      description: 'Dart SDK + Flutter toolkit',
      icon: Icons.flutter_dash,
      version: '3.x stable',
      source: 'storage.googleapis.com/dart-archive',
      longDesc:
          'Dart est le langage de Google optimisé pour le développement '
          'cross-platform. Inclut Flutter, pub, dart:core et dart:async.',
      features: ['Flutter', 'pub get/run', 'AOT/JIT', 'FFI', 'null safety'],
      parameters: [
        _Param('PUB_CACHE', 'Dossier cache des packages pub'),
        _Param('--sound-null-safety', 'Force le null safety strict'),
        _Param('FLUTTER_ROOT', 'Chemin vers le SDK Flutter'),
      ],
    ),
    _RuntimeInfo(
      name: 'Go',
      description: 'Toolchain Go — compilateur + modules',
      icon: Icons.speed_rounded,
      version: '1.22',
      source: 'go.dev/dl (archive officielle)',
      longDesc:
          'Go (Golang) est un langage compilé, concurrent et statiquement typé '
          'conçu par Google. Il produit des binaires autonomes sans dépendances.',
      features: ['go build/run/test', 'go modules', 'goroutines', 'CGO'],
      parameters: [
        _Param('GOPATH', 'Espace de travail Go'),
        _Param('GOFLAGS', 'Flags passés à toutes les commandes go'),
        _Param('CGO_ENABLED', '0 = compilation pure Go, 1 = CGO activé'),
      ],
    ),
    _RuntimeInfo(
      name: 'Rust',
      description: 'Rustup + cargo + compilateur stable',
      icon: Icons.build_rounded,
      version: 'stable',
      source: 'sh.rustup.rs (rustup officiel)',
      longDesc:
          'Rust est un langage système axé sur la sécurité mémoire sans '
          'ramasse-miettes. Cargo gère les projets et les dépendances (crates).',
      features: ['cargo build/run/test', 'crates.io', 'wasm-pack', 'clippy', 'rustfmt'],
      parameters: [
        _Param('CARGO_HOME', 'Répertoire d\'installation de cargo'),
        _Param('RUSTFLAGS', 'Flags passés au compilateur rustc'),
        _Param('--release', 'Compilation optimisée (mode release)'),
      ],
    ),
    _RuntimeInfo(
      name: 'Java',
      description: 'JDK 21 LTS (Temurin / Eclipse Adoptium)',
      icon: Icons.coffee_rounded,
      version: '21 LTS',
      source: 'adoptium.net (Eclipse Temurin)',
      longDesc:
          'Java est un langage orienté objet à compilation intermédiaire (bytecode). '
          'Le JDK Temurin est la distribution open-source de référence.',
      features: ['javac / java', 'Maven / Gradle', 'JVM tunning', 'JShell', 'modules JPMS'],
      parameters: [
        _Param('JAVA_HOME', 'Chemin racine du JDK'),
        _Param('-Xmx', 'Mémoire heap maximale (ex: -Xmx512m)'),
        _Param('-Xms', 'Mémoire heap initiale'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      children: [
        Text('Environnements d\'exécution',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
              color: cs.onSurface)),
        const SizedBox(height: 4),
        Text('Installez et gérez les runtimes disponibles dans Panda IDE.',
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 14),
        for (final r in _runtimes)
          _RuntimeRow(runtime: r),
      ],
    );
  }
}

class _RuntimeInfo {
  final String name, description, version, source, longDesc;
  final IconData icon;
  final List<String> features;
  final List<_Param> parameters;

  const _RuntimeInfo({
    required this.name,
    required this.description,
    required this.icon,
    required this.version,
    required this.source,
    required this.longDesc,
    required this.features,
    required this.parameters,
  });
}

class _Param {
  final String name, desc;
  const _Param(this.name, this.desc);
}

class _RuntimeRow extends StatelessWidget {
  final _RuntimeInfo runtime;
  const _RuntimeRow({required this.runtime});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: cs.surfaceContainerLow,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant, width: 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openRuntimeDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(runtime.icon, color: _kAccent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(runtime.name,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                    const SizedBox(height: 2),
                    Text(runtime.description,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(runtime.version,
                      style: const TextStyle(fontSize: 11, color: _kAccent,
                          fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 6),
                  Icon(Icons.arrow_forward_ios_rounded, size: 12,
                      color: cs.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openRuntimeDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RuntimeDetailSheet(runtime: runtime),
    );
  }
}

// ── Runtime detail sheet ──────────────────────────────────────────────────────

class _RuntimeDetailSheet extends StatefulWidget {
  final _RuntimeInfo runtime;
  const _RuntimeDetailSheet({required this.runtime});

  @override
  State<_RuntimeDetailSheet> createState() => _RuntimeDetailSheetState();
}

class _RuntimeDetailSheetState extends State<_RuntimeDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r  = widget.runtime;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: _kAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(r.icon, color: _kAccent, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name,
                          style: TextStyle(fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface)),
                        Text(r.version,
                          style: const TextStyle(fontSize: 13,
                              color: _kAccent,
                              fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  // Install button
                  FilledButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Installation de ${r.name}…'),
                            behavior: SnackBarBehavior.floating),
                      );
                    },
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Installer'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _kAccent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tab bar
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
                ),
              ),
              child: TabBar(
                controller: _tab,
                labelColor: _kAccent,
                unselectedLabelColor: cs.onSurfaceVariant,
                indicatorColor: _kAccent,
                indicatorWeight: 2,
                tabs: const [
                  Tab(text: 'Détails'),
                  Tab(text: 'Paramètres'),
                ],
              ),
            ),

            // Tab views
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  // Détails
                  ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      _DetailSection(
                        title: 'Description',
                        child: Text(r.longDesc,
                          style: TextStyle(fontSize: 13.5,
                              color: cs.onSurface, height: 1.6)),
                      ),
                      _DetailSection(
                        title: 'Source',
                        child: Row(children: [
                          Icon(Icons.link_rounded, size: 14, color: _kAccent),
                          const SizedBox(width: 6),
                          Expanded(child: Text(r.source,
                            style: const TextStyle(fontSize: 13,
                                color: _kAccent),
                            overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                      _DetailSection(
                        title: 'Fonctionnalités incluses',
                        child: Wrap(
                          spacing: 6, runSpacing: 6,
                          children: [
                            for (final f in r.features) _Tag(f),
                          ],
                        ),
                      ),
                      _DetailSection(
                        title: 'Infos',
                        child: Column(children: [
                          _InfoRow('Version', r.version),
                          _InfoRow('Source', r.source),
                        ]),
                      ),
                    ],
                  ),

                  // Paramètres
                  ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      Text('Variables et flags disponibles',
                        style: TextStyle(fontSize: 13,
                            color: cs.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      for (final p in r.parameters)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: cs.outlineVariant, width: 0.8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _kAccent.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(p.name,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: _kAccent,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'monospace',
                                  )),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(p.desc,
                                  style: TextStyle(fontSize: 12.5,
                                      color: cs.onSurface)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2 — Installed
// ─────────────────────────────────────────────────────────────────────────────

class _InstalledTab extends StatelessWidget {
  const _InstalledTab();

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final installed = ExtensionRegistry.instance.allInstalled();

    if (installed.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.extension_off_rounded, size: 56,
                  color: cs.onSurfaceVariant.withOpacity(0.3)),
              const SizedBox(height: 16),
              Text('Aucune extension installée',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
              const SizedBox(height: 6),
              Text('Parcourez l\'onglet Extensions pour en installer.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: installed.length,
      separatorBuilder: (_, __) => Divider(
        height: 1, indent: 68, endIndent: 16,
        color: cs.outlineVariant.withOpacity(0.5)),
      itemBuilder: (_, i) {
        final id = installed[i];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: const _ExtIcon(url: null, size: 44),
          title: Text(id,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600,
                color: cs.onSurface),
            overflow: TextOverflow.ellipsis),
          subtitle: Text('Installée',
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded,
                  color: Colors.green.shade400, size: 18),
              const SizedBox(width: 4),
              Icon(Icons.more_vert_rounded, size: 18,
                  color: cs.onSurfaceVariant),
            ],
          ),
          onTap: () {},
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Extension icon with network fallback.
class _ExtIcon extends StatelessWidget {
  final String? url;
  final double  size;
  const _ExtIcon({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url!,
          width: size, height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(cs),
        ),
      );
    }
    return _fallback(cs);
  }

  Widget _fallback(ColorScheme cs) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      color: _kAccent.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(Icons.extension_rounded,
        size: size * 0.55, color: _kAccent),
  );
}

// Install button — compact icon style for list
enum _InstallState { notInstalled, installing, installed, error }

class _InstallBtn extends StatelessWidget {
  final _InstallState state;
  final VoidCallback? onPressed;
  const _InstallBtn({required this.state, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (state) {
      _InstallState.notInstalled => SizedBox(
        width: 36, height: 36,
        child: Material(
          color: _kAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: const Icon(Icons.download_rounded,
                size: 18, color: _kAccent),
          ),
        ),
      ),
      _InstallState.installing => SizedBox(
        width: 22, height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2, color: _kAccent)),
      _InstallState.installed => Icon(Icons.check_circle_rounded,
          color: Colors.green.shade400, size: 22),
      _InstallState.error => Icon(Icons.error_outline_rounded,
          color: cs.error, size: 22),
    };
  }
}

// Install button — full width for detail sheet
class _DetailInstallBtn extends StatelessWidget {
  final _InstallState state;
  final VoidCallback? onPressed;
  const _DetailInstallBtn({required this.state, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      _InstallState.notInstalled => FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.download_rounded, size: 18),
        label: const Text('Installer'),
        style: FilledButton.styleFrom(
          backgroundColor: _kAccent,
          padding: const EdgeInsets.symmetric(vertical: 13),
          textStyle: const TextStyle(fontSize: 14,
              fontWeight: FontWeight.w600),
        ),
      ),
      _InstallState.installing => const Center(
        child: SizedBox(width: 26, height: 26,
          child: CircularProgressIndicator(strokeWidth: 2,
              color: _kAccent))),
      _InstallState.installed => FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_circle_rounded, size: 18),
        label: const Text('Installée'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.green.shade600,
          disabledBackgroundColor: Colors.green.shade600,
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
      _InstallState.error => FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Réessayer'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.red.shade600,
          padding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    };
  }
}

/// A small tag/chip label.
class _Tag extends StatelessWidget {
  final String  label;
  final bool    muted;
  const _Tag(this.label, {this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: muted
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : _kAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
        style: TextStyle(
          fontSize: 10.5,
          color: muted
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : _kAccent,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Section title + content block in detail sheet.
class _DetailSection extends StatelessWidget {
  final String  title;
  final Widget  child;
  const _DetailSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Key/value info row.
class _InfoRow extends StatelessWidget {
  final String key, value;
  const _InfoRow(this.key, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(key,
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
              style: TextStyle(fontSize: 12.5, color: cs.onSurface,
                  fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error view
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String   error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 52,
                color: cs.onSurfaceVariant.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text('Impossible de charger les extensions',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                  color: cs.onSurface),
              textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(error,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Réessayer'),
              style: FilledButton.styleFrom(backgroundColor: _kAccent),
            ),
          ],
        ),
      ),
    );
  }
}
