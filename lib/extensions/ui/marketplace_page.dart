/// Marketplace Open VSX — redesigned.
///
/// Fixes:
///  1. Full dark-theme compliance — no hardcoded colours, uses ColorScheme.
///  2. Filter button in header toggles category chips; larger icons; header
///     colour = scaffold bg (consistent); top pill nav (no bottom dock);
///     pills compact/stick to header on scroll.
///  3. Null-check operator crash on install → graceful error path.
///  4. Extension detail = single VSCode-style scrollable page, opens inside
///     the panel (not rootNavigator / fullscreen).
///  5. Bottom dock removed; Extensions / Runtimes / SDK / Panda Ext. / Installed
///     are top pills; downloads inline with progress (no separate page).
///  6. Panda Extensions pill replaces the separate Downloads page.
///  7. Download buttons trigger inline download+progress via PackageDownloader.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

import '../models/marketplace_extension.dart';
import '../open_vsx_client.dart';
import '../extension_registry.dart';
import '../vsix_installer.dart';
import 'extension_settings_page.dart';
import '../../ui/adb_setup_page.dart';
import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../utils/constants.dart';
import '../../utils/languages.dart';
import '../../services/package_downloader.dart';

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
enum _Section { extensions, runtimes, sdks, pandaExt, installed }

// ══════════════════════════════════════════════════════════════════════════════
// MarketplacePage
// ══════════════════════════════════════════════════════════════════════════════
class MarketplacePage extends StatefulWidget {
  final bool embedded;
  const MarketplacePage({super.key, this.embedded = false});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  final _client     = OpenVsxClient();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  _Section _section = _Section.extensions;

  List<MarketplaceExtension> _results = [];
  bool   _loading      = false;
  String? _error;
  int    _offset       = 0;
  int    _totalSize    = 0;
  bool   _loadingMore  = false;

  String _selectedCategory = 'All';
  String _sortBy = 'relevance';

  final Map<String, _InstallState> _installStates = {};

  Timer? _debounce;

  // Scroll-driven collapse
  bool   _searchCollapsed  = false;
  bool   _pillsCompact     = false;   // pills shrink on scroll
  bool   _filtersVisible   = false;   // filter chip panel toggle
  double _lastScroll       = 0;

  // Detail overlay (opens in-panel instead of rootNavigator push)
  MarketplaceExtension? _detailExt;

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

  // ── Scroll ──────────────────────────────────────────────────────────────────

  void _onScroll() {
    final pos          = _scrollCtrl.position.pixels;
    final scrollingDown = pos > _lastScroll + 6;
    final scrollingUp   = pos < _lastScroll - 6;

    if (scrollingDown) {
      if (!_searchCollapsed) setState(() => _searchCollapsed = true);
      if (!_pillsCompact)    setState(() => _pillsCompact = true);
      if (_filtersVisible)   setState(() => _filtersVisible = false);
    } else if (scrollingUp) {
      if (_searchCollapsed) setState(() => _searchCollapsed = false);
      if (_pillsCompact)    setState(() => _pillsCompact = false);
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

  // ── Data ────────────────────────────────────────────────────────────────────

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
        _results  = reset ? r.extensions : [..._results, ...r.extensions];
        _totalSize = r.totalSize;
        _offset   += r.extensions.length;
        _loading     = false;
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

  // ── Install ──────────────────────────────────────────────────────────────────

  Future<void> _install(MarketplaceExtension ext) async {
    setState(() => _installStates[ext.id] = _InstallState.installing);
    try {
      final installer = VsixInstaller(onProgress: (_, __) {});
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Detail ───────────────────────────────────────────────────────────────────

  void _openExtensionDetail(MarketplaceExtension ext) {
    setState(() => _detailExt = ext);
  }

  void _closeDetail() => setState(() => _detailExt = null);

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    Widget body = Column(
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        _MarketplaceHeader(
          section:         _section,
          searchCtrl:      _searchCtrl,
          collapsed:       _searchCollapsed,
          filtersVisible:  _filtersVisible,
          embedded:        widget.embedded,
          sortBy:          _sortBy,
          onSortChanged:   (v) {
            setState(() => _sortBy = v);
            _searchCtrl.text.isEmpty ? _loadFeatured() : _search();
          },
          onSearchExpand:  () => setState(() => _searchCollapsed = false),
          onFilterToggle:  () => setState(() => _filtersVisible = !_filtersVisible),
        ),

        // ── Top pill nav (replaces bottom dock) ──────────────────────────────
        _TopPillNav(
          current:  _section,
          compact:  _pillsCompact,
          onTap:    (s) => setState(() {
            _section        = s;
            _searchCollapsed = false;
            _pillsCompact   = false;
          }),
        ),

        // ── Category filter chips (toggled by filter button) ─────────────────
        if (_section == _Section.extensions)
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _filtersVisible
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: _kCategories.length,
                itemBuilder: (_, i) {
                  final cat = _kCategories[i];
                  final sel = cat == _selectedCategory;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(cat, style: const TextStyle(fontSize: 12)),
                      selected: sel,
                      selectedColor: cs.primary.withValues(alpha: 0.18),
                      checkmarkColor: cs.primary,
                      side: BorderSide(color: sel ? cs.primary : cs.outlineVariant),
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
            secondChild: const SizedBox(height: 2),
          ),

        // ── Body ─────────────────────────────────────────────────────────────
        Expanded(child: _buildSectionBody(theme, cs)),
      ],
    );

    // Detail overlay — slides in-panel over the list
    if (_detailExt != null) {
      body = Stack(
        children: [
          body,
          _ExtensionDetailOverlay(
            ext:          _detailExt!,
            client:       _client,
            installState: _installStates[_detailExt!.id] ?? _InstallState.notInstalled,
            onInstall:    () => _install(_detailExt!),
            onClose:      _closeDetail,
          ),
        ],
      );
    }

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
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
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
              ext:          ext,
              installState: _installStates[ext.id] ?? _InstallState.notInstalled,
              onInstall:    () => _install(ext),
              onTap:        () => _openExtensionDetail(ext),
            );
          },
        );

      case _Section.runtimes:
        return _RuntimesSection(scrollCtrl: _scrollCtrl, showSdks: false);

      case _Section.sdks:
        return _RuntimesSection(scrollCtrl: _scrollCtrl, showSdks: true);

      case _Section.pandaExt:
        return _PandaExtensionsSection(scrollCtrl: _scrollCtrl);

      case _Section.installed:
        return _InstalledSection(
          onTap: (ext) => _openExtensionDetail(ext),
          client: _client,
        );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Animated header
// ══════════════════════════════════════════════════════════════════════════════

class _MarketplaceHeader extends StatelessWidget {
  final _Section section;
  final TextEditingController searchCtrl;
  final bool collapsed;
  final bool filtersVisible;
  final bool embedded;
  final String sortBy;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onSearchExpand;
  final VoidCallback onFilterToggle;

  const _MarketplaceHeader({
    required this.section,
    required this.searchCtrl,
    required this.collapsed,
    required this.filtersVisible,
    required this.embedded,
    required this.sortBy,
    required this.onSortChanged,
    required this.onSearchExpand,
    required this.onFilterToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final cs       = theme.colorScheme;
    // Use scaffold background so header matches the rest of the app
    final headerBg = theme.scaffoldBackgroundColor;
    final onHeader = cs.onSurface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        embedded ? 6 : MediaQuery.of(context).padding.top + 6,
        8,
        8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top bar ─────────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.storefront_rounded, size: 22, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Marketplace',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: onHeader,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),

              // Filter button (toggles category chips) — extensions only
              if (section == _Section.extensions) ...[
                IconButton(
                  icon: Icon(
                    filtersVisible ? Icons.filter_list_off : Icons.filter_list_rounded,
                    size: 22,
                    color: filtersVisible
                        ? cs.primary
                        : onHeader.withValues(alpha: 0.65),
                  ),
                  tooltip: filtersVisible ? 'Hide filters' : 'Show filters',
                  onPressed: onFilterToggle,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                // Sort
                _SortButton(sortBy: sortBy, onSelected: onSortChanged),
              ],

              // Search restore (when collapsed)
              if (collapsed && section == _Section.extensions)
                IconButton(
                  icon: Icon(Icons.search, size: 22, color: onHeader.withValues(alpha: 0.65)),
                  tooltip: 'Search',
                  onPressed: onSearchExpand,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
            ],
          ),

          // ── Search bar (Extensions only, collapses on scroll) ────────────
          if (section == _Section.extensions)
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: collapsed
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: searchCtrl,
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Search extensions…',
                    hintStyle: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.4)),
                    prefixIcon: Icon(Icons.search, size: 20, color: cs.onSurface.withValues(alpha: 0.5)),
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
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      icon: Icon(Icons.sort_rounded, size: 22, color: cs.onSurface.withValues(alpha: 0.65)),
      tooltip: 'Sort',
      onSelected: onSelected,
      itemBuilder: (_) => _kSortOptions.entries.map((e) => PopupMenuItem(
        value: e.value,
        child: Row(children: [
          if (sortBy == e.value)
            Icon(Icons.check, size: 14, color: cs.primary),
          const SizedBox(width: 8),
          Text(e.key),
        ]),
      )).toList(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Top pill navigation (replaces bottom dock)
// ══════════════════════════════════════════════════════════════════════════════

class _TopPillNav extends StatelessWidget {
  final _Section current;
  final bool compact;
  final ValueChanged<_Section> onTap;
  const _TopPillNav({required this.current, required this.compact, required this.onTap});

  static const _items = [
    _NavItem(_Section.extensions, Icons.extension_outlined, Icons.extension,         'Extensions'),
    _NavItem(_Section.runtimes,   Icons.terminal_rounded,   Icons.terminal_rounded,  'Runtimes'),
    _NavItem(_Section.sdks,       Icons.layers_outlined,    Icons.layers_rounded,    'SDK'),
    _NavItem(_Section.pandaExt,   Icons.download_outlined,  Icons.download_rounded,  'Panda Ext.'),
    _NavItem(_Section.installed,  Icons.check_circle_outline, Icons.check_circle,   'Installed'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      height: compact ? 36 : 46,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: _items.map((item) {
          final sel = item.section == current;
          return GestureDetector(
            onTap: () => onTap(item.section),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.symmetric(
                horizontal: 4,
                vertical: compact ? 4 : 6,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 14,
                vertical: compact ? 2 : 4,
              ),
              decoration: BoxDecoration(
                color: sel ? cs.primary.withValues(alpha: 0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: sel ? Border.all(color: cs.primary.withValues(alpha: 0.3)) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    sel ? item.activeIcon : item.icon,
                    size: compact ? 16 : 18,
                    color: sel ? cs.primary : cs.onSurface.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 5),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: compact ? 11 : 12,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel ? cs.primary : cs.onSurface.withValues(alpha: 0.7),
                    ),
                    child: Text(item.label),
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
    final cs    = theme.colorScheme;
    final sub   = cs.onSurface.withValues(alpha: 0.55);
    final alreadyInstalled = ExtensionRegistry.instance.isInstalled(ext.id) ||
        installState == _InstallState.installed;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
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
                    ? Image.network(ext.iconUrl!, width: 44, height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _DefaultExtIcon(size: 44))
                    : _DefaultExtIcon(size: 44),
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
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('v${ext.version}',
                          style: TextStyle(fontSize: 10, color: sub)),
                    ]),
                    const SizedBox(height: 2),
                    Text(ext.namespace, style: TextStyle(fontSize: 11, color: sub)),
                    const SizedBox(height: 4),
                    Text(ext.description,
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.8)),
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
                            color: cs.primary.withValues(alpha: 0.1),
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
              const SizedBox(width: 8),

              // Install button
              _InstallButton(
                state: alreadyInstalled ? _InstallState.installed : installState,
                onPressed: alreadyInstalled ? null : onInstall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
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
              backgroundColor: cs.primary.withValues(alpha: 0.12),
              foregroundColor: cs.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('Install', style: TextStyle(fontSize: 12)),
          ),
        );
      case _InstallState.installing:
        return SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
        );
      case _InstallState.installed:
        return Icon(Icons.check_circle_rounded, color: cs.primary, size: 22);
      case _InstallState.error:
        return Icon(Icons.error_outline, color: cs.error, size: 22);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Extension detail — in-panel overlay (VSCode-style single scrollable section)
// ══════════════════════════════════════════════════════════════════════════════

class _ExtensionDetailOverlay extends StatefulWidget {
  final MarketplaceExtension ext;
  final OpenVsxClient client;
  final _InstallState installState;
  final VoidCallback onInstall;
  final VoidCallback onClose;

  const _ExtensionDetailOverlay({
    required this.ext,
    required this.client,
    required this.installState,
    required this.onInstall,
    required this.onClose,
  });

  @override
  State<_ExtensionDetailOverlay> createState() => _ExtensionDetailOverlayState();
}

class _ExtensionDetailOverlayState extends State<_ExtensionDetailOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<Offset>   _slide;

  String? _readme;
  bool    _readmeLoading = true;
  late _InstallState _installState;

  @override
  void initState() {
    super.initState();
    _installState = widget.installState;
    _anim  = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _slide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
    _loadReadme();
  }

  @override
  void dispose() {
    _anim.dispose();
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
      setState(() { _readmeLoading = false; });
    }
  }

  Future<void> _close() async {
    await _anim.reverse();
    widget.onClose();
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
    final cs    = theme.colorScheme;
    final ext   = widget.ext;
    final alreadyInstalled = ExtensionRegistry.instance.isInstalled(ext.id) ||
        _installState == _InstallState.installed;

    return SlideTransition(
      position: _slide,
      child: Material(
        color: theme.scaffoldBackgroundColor,
        child: Column(
          children: [
            // ── Bar ──────────────────────────────────────────────────────
            Container(
              height: 44,
              color: theme.scaffoldBackgroundColor,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        size: 18, color: cs.onSurface),
                    onPressed: _close,
                    tooltip: 'Back',
                  ),
                  Expanded(
                    child: Text(
                      ext.displayName.isNotEmpty ? ext.displayName : ext.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),

            // ── Scrollable body ───────────────────────────────────────────
            Expanded(
              child: ListView(
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
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(ext.namespace,
                                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
                            const SizedBox(height: 8),
                            if (alreadyInstalled)
                              _OutlineBadge(
                                icon: Icons.check_circle_rounded,
                                label: 'Installed',
                                color: cs.primary,
                              )
                            else if (_installState == _InstallState.installing)
                              SizedBox(
                                width: 24, height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                              )
                            else
                              FilledButton.icon(
                                onPressed: _doInstall,
                                icon: const Icon(Icons.download_rounded, size: 16),
                                label: const Text('Install'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                          color: cs.onSurface.withValues(alpha: 0.85))),
                  const SizedBox(height: 16),

                  // Stats
                  _StatsRow(ext: ext),
                  const SizedBox(height: 16),

                  // Meta
                  _InfoTile(label: 'Publisher', value: ext.namespace),
                  _InfoTile(label: 'Version',   value: ext.version),
                  if (ext.license != null && ext.license!.isNotEmpty)
                    _InfoTile(label: 'License', value: ext.license!),
                  if (ext.categories.isNotEmpty)
                    _InfoTile(label: 'Categories', value: ext.categories.join(', ')),
                  if (ext.tags.isNotEmpty)
                    _InfoTile(label: 'Tags', value: ext.tags.take(8).join(', ')),
                  if (ext.repository != null && ext.repository!.isNotEmpty)
                    _InfoTile(label: 'Repository', value: ext.repository!),

                  // Settings / uninstall (if installed)
                  if (alreadyInstalled) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        final installed = ExtensionRegistry.instance.get(ext.id);
                        if (installed != null && context.mounted) {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ExtensionSettingsPage(extension: installed),
                          ));
                        }
                      },
                      icon: const Icon(Icons.settings_outlined, size: 16),
                      label: const Text('Extension Settings'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Uninstall'),
                      style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                    ),
                  ],

                  // README
                  if (_readmeLoading) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                  ] else if (_readme != null && _readme!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    _MarkdownText(source: _readme!),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stats row ──────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final MarketplaceExtension ext;
  const _StatsRow({required this.ext});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        if (ext.averageRating != null)
          _StatChip(
            icon: Icons.star_rounded,
            iconColor: Colors.amber,
            label: ext.averageRating!.toStringAsFixed(1),
            sub: '${ext.reviewCount} reviews',
          ),
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
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   label;
  final String   sub;
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
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              Text(sub, style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.55))),
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
                    color: cs.onSurface.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 12, color: cs.onSurface)),
          ),
        ],
      ),
    );
  }
}

class _OutlineBadge extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  const _OutlineBadge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.08),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Runtimes / SDKs section
// ══════════════════════════════════════════════════════════════════════════════

class _RuntimeInfo {
  final String  key;
  final String  name;
  final String  description;
  final String  version;
  final String  longDescription;
  final String  website;
  final Widget  icon;
  final String  useCase;
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

// ── SDKs ──────────────────────────────────────────────────────────────────────
final _kSdks = <_RuntimeInfo>[
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
    name: 'Android SDK',
    description: 'adb, fastboot — required for flutter run',
    version: 'r35+',
    longDescription:
        'Android SDK platform-tools provides the adb (Android Debug Bridge) '
        'binary for ARM64 Android. This is required for "flutter run" '
        'and for wireless debugging. Install this alongside the Flutter SDK.',
    website: 'https://developer.android.com/studio/releases/platform-tools',
    useCase: 'flutter run, adb install, adb shell, wireless debugging',
    icon: const FaIcon(FontAwesomeIcons.android, size: 26, color: Color(0xFF3DDC84)),
  ),
];

// ── Language Runtimes ──────────────────────────────────────────────────────────
final _kRuntimes = <_RuntimeInfo>[
  _RuntimeInfo(
    key: 'node',
    name: 'Node.js',
    description: 'JavaScript / TypeScript runtime',
    version: '22.x LTS',
    longDescription:
        'Node.js is an open-source, cross-platform JavaScript runtime. '
        'Executes JavaScript outside a browser using V8. '
        'Ideal for servers, CLI tools, and full-stack TypeScript projects.',
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
        'Comes with pip and supports the full data-science & ML ecosystem.',
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
        'Java JDK 21 (Eclipse Temurin) — LTS release with virtual threads, '
        'pattern matching, and record classes.',
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
        'Modern, statically typed language on the JVM. '
        'Preferred language for Android and Kotlin Multiplatform.',
    website: 'https://kotlinlang.org',
    useCase: 'Android, Kotlin Multiplatform, server-side',
    icon: const FaIcon(FontAwesomeIcons.k, size: 26, color: Color(0xFF7F52FF)),
  ),
  _RuntimeInfo(
    key: 'dart',
    name: 'Dart',
    description: 'Dart SDK standalone',
    version: '3.x',
    longDescription:
        'Dart is an optimised language for fast apps on any platform. '
        'Paired with Flutter for cross-platform mobile, web, and desktop.',
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
        'Statically typed, compiled with built-in concurrency primitives. '
        'Produces small, fast binaries — great for CLIs and cloud-native.',
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
        'Systems language focused on safety, speed, and concurrency. '
        'Memory-safe without a garbage collector.',
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
        'Clang front-end for C, C++, and Objective-C. '
        'Required for Rust and Go on Android. Full C17/C++23 support.',
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
        'Dynamic, reflective, object-oriented language. '
        'Popular for Ruby on Rails. Bundler and RubyGems included.',
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
        'Lightweight, high-level scripting language designed for embedding. '
        'Used in game engines (Love2D, Roblox) and as an extension language.',
    website: 'https://lua.org',
    useCase: 'Game scripting, embedded configs, Neovim plugins',
    icon: const Icon(Icons.code, size: 26, color: Color(0xFF000080)),
  ),
];

// ──────────────────────────────────────────────────────────────────────────────
// Runtimes / SDKs section — with inline download progress
// ──────────────────────────────────────────────────────────────────────────────

class _RuntimesSection extends StatefulWidget {
  final ScrollController scrollCtrl;
  final bool showSdks;
  const _RuntimesSection({required this.scrollCtrl, required this.showSdks});

  @override
  State<_RuntimesSection> createState() => _RuntimesSectionState();
}

class _RuntimesSectionState extends State<_RuntimesSection> {
  @override
  Widget build(BuildContext context) {
    final catalogState = context.watch<PackageCatalogCubit>().state;
    final items = widget.showSdks ? _kSdks : _kRuntimes;

    // Map _RuntimeInfo.key → catalog index (needed for DownloadManagerBloc)
    final Map<String, int> keyToIndex = {};
    for (int i = 0; i < catalogState.runtimes.length; i++) {
      keyToIndex[catalogState.runtimes[i].parentName.toLowerCase()] = i;
    }

    return ListView.builder(
      controller: widget.scrollCtrl,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final info = items[i];
        final resolvedKey = PackageDownloader.resolveAlias(info.key);
        final idx  = keyToIndex[resolvedKey];
        // Find the catalog RunTime for url/archiveName
        RunTime? rt;
        if (idx != null) {
          rt = catalogState.runtimes[idx];
        }
        return _RuntimeCard(
          info: info,
          catalogIndex: idx,
          catalogRuntime: rt,
          catalogState: catalogState,
        );
      },
    );
  }
}

class _RuntimeCard extends StatelessWidget {
  final _RuntimeInfo info;
  final int? catalogIndex;
  final RunTime? catalogRuntime;
  final PackageCatalogState catalogState;

  const _RuntimeCard({
    required this.info,
    required this.catalogIndex,
    required this.catalogRuntime,
    required this.catalogState,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => _RuntimeDetailPage(
              info: info,
              catalogIndex: catalogIndex,
              catalogRuntime: catalogRuntime,
              catalogState: catalogState,
            ))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Icon circle
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Center(child: info.icon),
              ),
              const SizedBox(width: 14),

              // Name + desc
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600, color: cs.onSurface)),
                    const SizedBox(height: 2),
                    Text(info.description,
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
                  ],
                ),
              ),

              // Version chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(info.version,
                    style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),

              // Inline download button / progress
              if (catalogIndex != null)
                _InlineDownloadButton(
                  index: catalogIndex!,
                  onDownload: () => _triggerDownload(context),
                  installDir: Directory('$runtimesDir/${info.key}'),
                )
              else
                Icon(Icons.download_rounded, size: 22, color: cs.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }

  void _triggerDownload(BuildContext context) {
    final rt = catalogRuntime;
    final idx = catalogIndex;
    if (rt == null || idx == null) return;
    PackageDownloader.startDownload(
      context: context,
      index: idx,
      url: rt.url,
      archiveName: rt.archiveName,
      targetDir: downloadsDir,
      isExtension: false,
      packageParentName: rt.parentName,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Inline download button — shows progress bar while downloading
// ══════════════════════════════════════════════════════════════════════════════

class _InlineDownloadButton extends StatelessWidget {
  final int index;
  final VoidCallback onDownload;
  final Directory installDir;

  const _InlineDownloadButton({
    required this.index,
    required this.onDownload,
    required this.installDir,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return BlocBuilder<DownloadManagerBloc, DownloadManagerState>(
      builder: (context, dlState) {
        final percent         = dlState.downloadProgress[index] ?? 0.0;
        final isExtracting    = dlState.isExtracting(index);
        final extractPct      = dlState.extractionProgress[index] ?? 0.0;
        final isFullyDone     = dlState.isFullyCompleted(index);
        final isInstalled     = isFullyDone || installDir.existsSync();

        // Completion wins over any final 80%/100% progress event. The bloc
        // clears those transient values, but this ordering also protects the
        // button from a stale frame during the state transition.
        if (isInstalled) {
          return Icon(Icons.check_circle_rounded, color: cs.primary, size: 26);
        }

        // ── Extracting ──────────────────────────────────────────────────
        if (isExtracting) {
          return SizedBox(
            width: 90,
            child: LinearPercentIndicator(
              progressColor: Colors.greenAccent.withValues(alpha: 0.7),
              percent: (extractPct / 100).clamp(0.0, 1.0),
              width: 86,
              lineHeight: 36,
              barRadius: const Radius.circular(18),
              center: Text(
                extractPct > 0 ? '${extractPct.toStringAsFixed(0)}%' : '…',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          );
        }

        // ── Downloading ─────────────────────────────────────────────────
        if (percent > 0.0 && percent < 100.0) {
          return SizedBox(
            width: 90,
            child: LinearPercentIndicator(
              progressColor: cs.primary.withValues(alpha: 0.7),
              percent: (percent / 100).clamp(0.0, 1.0),
              width: 86,
              lineHeight: 36,
              barRadius: const Radius.circular(18),
              center: Text('${percent.toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 11)),
            ),
          );
        }

        // ── Starting (index active but 0 progress) ──────────────────────
        if (PackageDownloader.isActive(index)) {
          return SizedBox(
            width: 90,
            child: LinearPercentIndicator(
              progressColor: cs.primary.withValues(alpha: 0.5),
              percent: 0.0,
              width: 86,
              lineHeight: 36,
              barRadius: const Radius.circular(18),
              center: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: cs.primary),
              ),
            ),
          );
        }

        // ── Not started ─────────────────────────────────────────────────
        return IconButton(
          icon: Icon(Icons.download_rounded, size: 22, color: cs.primary),
          onPressed: onDownload,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Runtime detail page
// ══════════════════════════════════════════════════════════════════════════════

class _RuntimeDetailPage extends StatelessWidget {
  final _RuntimeInfo info;
  final int? catalogIndex;
  final RunTime? catalogRuntime;
  final PackageCatalogState catalogState;

  const _RuntimeDetailPage({
    required this.info,
    required this.catalogIndex,
    required this.catalogRuntime,
    required this.catalogState,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;
    final idx   = catalogIndex;
    final rt    = catalogRuntime;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: cs.onSurface,
        iconTheme: IconThemeData(color: cs.onSurface),
        title: Text(info.name, style: TextStyle(color: cs.onSurface, fontSize: 16)),
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
                            fontWeight: FontWeight.w700, color: cs.onSurface)),
                    const SizedBox(height: 4),
                    Text(info.description,
                        style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.55))),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text('v${info.version}',
                          style: TextStyle(fontSize: 12, color: cs.primary,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Install button — inline with progress
          if (idx != null && rt != null)
            BlocBuilder<DownloadManagerBloc, DownloadManagerState>(
              builder: (context, dlState) {
                final percent      = dlState.downloadProgress[idx] ?? 0.0;
                final isExtracting = dlState.isExtracting(idx);
                final extractPct   = dlState.extractionProgress[idx] ?? 0.0;
                final isInstalled  = Directory('$runtimesDir/${info.key}').existsSync() ||
                    dlState.isFullyCompleted(idx);

                if (isExtracting || (percent > 0 && percent < 100) || PackageDownloader.isActive(idx)) {
                  final pct = isExtracting ? extractPct : percent;
                  return Column(
                    children: [
                      LinearProgressIndicator(
                        value: (pct / 100).clamp(0.0, 1.0),
                        backgroundColor: cs.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isExtracting ? 'Extracting… ${extractPct.toStringAsFixed(0)}%'
                            : 'Downloading… ${percent.toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  );
                }

                if (isInstalled) {
                  return OutlinedButton.icon(
                    onPressed: null,
                    icon: Icon(Icons.check_circle_rounded, color: cs.primary, size: 16),
                    label: Text('Installed',
                        style: TextStyle(color: cs.primary)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
                    ),
                  );
                }

                return FilledButton.icon(
                  onPressed: () => PackageDownloader.startDownload(
                    context: context,
                    index: idx,
                    url: rt.url,
                    archiveName: rt.archiveName,
                    targetDir: downloadsDir,
                    isExtension: false,
                    packageParentName: rt.parentName,
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text('Installer ${info.name}'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
            )
          else
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text('Installer ${info.name}'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

          // ADB Setup (Flutter SDK only)
          if (info.extraAction != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdbSetupPage())),
              icon: const Icon(Icons.usb_rounded, size: 16),
              label: Text(info.extraAction!),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
          const SizedBox(height: 20),

          // About
          _SectionHeader(title: 'À propos'),
          const SizedBox(height: 8),
          Text(info.longDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.85), height: 1.6)),
          const SizedBox(height: 20),

          // Use cases
          _SectionHeader(title: 'Cas d\'utilisation'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 18, color: cs.primary.withValues(alpha: 0.8)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(info.useCase,
                      style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.85))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Website
          _SectionHeader(title: 'Site officiel'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.language, size: 18, color: cs.onSurface.withValues(alpha: 0.55)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(info.website,
                      style: TextStyle(fontSize: 13, color: cs.primary,
                          decoration: TextDecoration.underline)),
                ),
                Icon(Icons.open_in_new, size: 14, color: cs.onSurface.withValues(alpha: 0.4)),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Panda Extensions section — LSP servers & tools (former Downloads page)
// ══════════════════════════════════════════════════════════════════════════════

class _PandaExtensionsSection extends StatefulWidget {
  final ScrollController scrollCtrl;
  const _PandaExtensionsSection({required this.scrollCtrl});

  @override
  State<_PandaExtensionsSection> createState() => _PandaExtensionsSectionState();
}

class _PandaExtensionsSectionState extends State<_PandaExtensionsSection> {
  @override
  Widget build(BuildContext context) {
    final theme        = Theme.of(context);
    final cs           = theme.colorScheme;
    final catalogState = context.watch<PackageCatalogCubit>().state;
    final extItems     = catalogState.extensions;

    if (catalogState.isSyncing && extItems.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (extItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download_outlined, size: 52, color: cs.onSurface.withValues(alpha: 0.3)),
              const SizedBox(height: 14),
              Text('No Panda extensions available',
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.6))),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => context.read<PackageCatalogCubit>().refreshCatalog(),
                child: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    // extensions list uses offset runtimes.length for DownloadManagerBloc index
    final runtimeCount = catalogState.runtimes.length;

    return ListView.builder(
      controller: widget.scrollCtrl,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      itemCount: extItems.length,
      itemBuilder: (_, i) {
        final ext = extItems[i];
        final extIdx = i + runtimeCount;
        return _PandaExtCard(
          ext: ext,
          index: extIdx,
          hasUpdate: catalogState.extensionUpdates.contains(ext.parentName),
        );
      },
    );
  }
}

class _PandaExtCard extends StatelessWidget {
  final Extension ext;
  final int index;
  final bool hasUpdate;

  const _PandaExtCard({
    required this.ext,
    required this.index,
    required this.hasUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final cs     = theme.colorScheme;
    final sub    = cs.onSurface.withValues(alpha: 0.55);
    final extDir = Directory('$extensionDir/${ext.parentName}');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon
            ext.icon,
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(ext.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600, color: cs.onSurface),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (hasUpdate)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Update',
                            style: TextStyle(
                                color: Colors.orange, fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                  ]),
                  const SizedBox(height: 3),
                  Text(ext.details,
                      style: TextStyle(fontSize: 11, color: sub),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  Text('${ext.archiveSize} MB',
                      style: TextStyle(fontSize: 11, color: sub)),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Inline download button / progress
            _InlineDownloadButton(
              index: index,
              onDownload: () => PackageDownloader.startDownload(
                context: context,
                index: index,
                url: ext.url,
                archiveName: ext.archiveName,
                targetDir: downloadsDir,
                isExtension: true,
                packageParentName: ext.parentName,
                extensionMetadata: ext,
              ),
              installDir: extDir,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

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
          color: cs.onSurface.withValues(alpha: 0.7),
          letterSpacing: 0.4,
        ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Installed section
// ══════════════════════════════════════════════════════════════════════════════

class _InstalledSection extends StatelessWidget {
  final void Function(MarketplaceExtension ext) onTap;
  final OpenVsxClient client;
  const _InstalledSection({required this.onTap, required this.client});

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
    final cs        = theme.colorScheme;
    final installed = ExtensionRegistry.instance.allInstalled();

    if (installed.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.extension_outlined, size: 52, color: cs.onSurface.withValues(alpha: 0.3)),
              const SizedBox(height: 14),
              Text('No extensions installed',
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.6))),
              const SizedBox(height: 6),
              Text('Browse Extensions to install one.',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.45)),
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
        final ext   = ExtensionRegistry.instance.get(extId);
        final name  = ext?.manifest.displayName ?? extId;
        final desc  = ext?.manifest.description ?? 'Installed';

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          elevation: 0,
          color: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              // Build a minimal MarketplaceExtension from installed info
              final mExt = MarketplaceExtension(
                namespace:   ext?.manifest.publisher ?? extId.split('.').first,
                name:        ext?.manifest.name ?? extId,
                displayName: name,
                description: desc,
                version:     ext?.manifest.version ?? '?',
                categories:  ext?.manifest.categories ?? [],
                tags:        ext?.manifest.keywords ?? [],
                repository:  ext?.manifest.repository,
                license:     null,
              );
              onTap(mExt);
            },
            child: ListTile(
              leading: _DefaultExtIcon(size: 40),
              title: Text(name,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
              subtitle: Text(desc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.55))),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ext != null)
                    IconButton(
                      icon: Icon(Icons.settings_outlined, size: 18,
                          color: cs.onSurface.withValues(alpha: 0.55)),
                      tooltip: 'Settings',
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ExtensionSettingsPage(extension: ext),
                      )),
                    ),
                  Icon(Icons.check_circle_rounded, color: cs.primary, size: 18),
                ],
              ),
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
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.extension_rounded, size: size * 0.55, color: cs.primary),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String      error;
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
            Icon(Icons.cloud_off_outlined, size: 48, color: cs.onSurface.withValues(alpha: 0.35)),
            const SizedBox(height: 12),
            Text('Could not load extensions',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(error,
                style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)),
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

/// Minimal markdown renderer — preserves line breaks and highlights headings/code.
class _MarkdownText extends StatelessWidget {
  final String source;
  const _MarkdownText({required this.source});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;
    final lines = source.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        if (line.startsWith('### ')) {
          return Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(line.substring(4),
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700, color: cs.onSurface)),
          );
        }
        if (line.startsWith('## ')) {
          return Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 6),
            child: Text(line.substring(3),
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: cs.onSurface)),
          );
        }
        if (line.startsWith('# ')) {
          return Padding(
            padding: const EdgeInsets.only(top: 22, bottom: 8),
            child: Text(line.substring(2),
                style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700, color: cs.onSurface)),
          );
        }
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
                style: TextStyle(fontSize: 12, fontFamily: 'monospace',
                    color: cs.onSurface.withValues(alpha: 0.8))),
          );
        }
        if (line.trim() == '---' || line.trim() == '___') {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: cs.outlineVariant),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text(line,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.85), height: 1.6)),
        );
      }).toList(),
    );
  }
}
