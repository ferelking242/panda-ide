/// Marketplace — Play Store pixel-perfect redesign.
///
/// Sections:
///   - Home: Featured banner, categories grid, trending, recommended
///   - Search: Full-text search with category chips
///   - Installed: Manage installed extensions
///   - Detail: VS Code-style extension detail page
library;


import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:percent_indicator/percent_indicator.dart';

import '../models/marketplace_extension.dart';
import '../open_vsx_client.dart';
import '../extension_registry.dart';
import '../vsix_installer.dart';
import 'extension_settings_page.dart';
import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../utils/constants.dart';
import '../../utils/languages.dart' as lang;
import '../../local_models/ui/local_models_page.dart';

// ═══════════════════════════════════════════════════════════════
// Categories (Play Store style)
// ═══════════════════════════════════════════════════════════════

class _Category {
  final String name;
  final IconData icon;
  final Color color;
  const _Category(this.name, this.icon, this.color);
}

const _categories = [
  _Category('Themes', Icons.palette_rounded, Color(0xFF9C27B0)),
  _Category('Languages', Icons.code_rounded, Color(0xFF2196F3)),
  _Category('Linters', Icons.check_circle_outline, Color(0xFF4CAF50)),
  _Category('Formatters', Icons.format_align_left, Color(0xFFFF9800)),
  _Category('Debuggers', Icons.bug_report_rounded, Color(0xFFF44336)),
  _Category('Snippets', Icons.shortcut_rounded, Color(0xFF00BCD4)),
  _Category('Keymaps', Icons.keyboard_rounded, Color(0xFF607D8B)),
  _Category('AI Tools', Icons.smart_toy_rounded, Color(0xFFE91E63)),
];

// ═══════════════════════════════════════════════════════════════
// MarketplacePage — main entry
// ═══════════════════════════════════════════════════════════════

enum _Tab { home, search, installed }

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

  _Tab _currentTab = _Tab.home;
  List<MarketplaceExtension> _results = [];
  List<MarketplaceExtension> _featured = [];
  bool _loading = false;
  String? _error;
  int _offset = 0;
  int _totalSize = 0;
  bool _loadingMore = false;
  String _selectedCategory = 'All';
  String _sortBy = 'relevance';
  final Map<String, _InstallState> _installStates = {};
  Timer? _debounce;

  // Detail overlay
  MarketplaceExtension? _detailExt;

  @override
  void initState() {
    super.initState();
    _loadFeatured();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _debounce?.cancel();
    _client.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  // ── Data loading ──────────────────────────────────────────────────────

  Future<void> _loadFeatured() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await _client.featured(size: 20);
      if (!mounted) return;
      setState(() {
        _featured = result.extensions;
        _totalSize = result.totalSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      _loadFeatured();
      return;
    }
    setState(() { _loading = true; _error = null; _offset = 0; });
    try {
      final result = await _client.search(
        query: query.trim(),
        offset: 0,
        size: 20,
        category: _selectedCategory == 'All' ? null : _selectedCategory,
        sortBy: _sortBy,
      );
      if (!mounted) return;
      setState(() {
        _results = result.extensions;
        _totalSize = result.totalSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _results.isEmpty) return;
    setState(() { _loadingMore = true; });
    try {
      _offset += 20;
      final result = await _client.search(
        query: _searchCtrl.text.trim(),
        offset: _offset,
        size: 20,
        category: _selectedCategory == 'All' ? null : _selectedCategory,
        sortBy: _sortBy,
      );
      if (!mounted) return;
      setState(() {
        _results.addAll(result.extensions);
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loadingMore = false; });
    }
  }

  // ── Install ───────────────────────────────────────────────────────────

  Future<void> _install(MarketplaceExtension ext) async {
    setState(() => _installStates[ext.id] = _InstallState.installing);
    try {
      final url = await _client.getDownloadUrl(ext.namespace, ext.name, ext.version);
      final installer = VsixInstaller();
      await installer.installFromUrl(url);
      await ExtensionRegistry.instance.load();
      if (!mounted) return;
      setState(() => _installStates[ext.id] = _InstallState.installed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ext.displayName} installed')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _installStates[ext.id] = _InstallState.error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Install failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      body: _detailExt != null
          ? _buildDetailPage(theme, cs)
          : Column(
              children: [
                _buildHeader(theme, cs, isDark),
                _buildTabBar(theme, cs, isDark),
                if (_currentTab == _Tab.search) _buildSearchBar(theme, cs, isDark),
                if (_currentTab == _Tab.search) _buildCategoryChips(theme, cs, isDark),
                Expanded(child: _buildBody(theme, cs, isDark)),
              ],
            ),
      bottomNavigationBar: _detailExt != null ? null : _buildBottomNav(theme, cs, isDark),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader(ThemeData theme, ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Icon(Icons.storefront_rounded, color: cs.primary, size: 28),
          const SizedBox(width: 10),
          Text(
            'Marketplace',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          // Installed badge
          if (ExtensionRegistry.instance.all.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${ExtensionRegistry.instance.all.length}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary),
              ),
            ),
        ],
      ),
    );
  }

  // ── Tab Bar ───────────────────────────────────────────────────────────

  Widget _buildTabBar(ThemeData theme, ColorScheme cs, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          _tabItem(_Tab.home, Icons.home_rounded, 'Home', cs),
          _tabItem(_Tab.search, Icons.search_rounded, 'Search', cs),
          _tabItem(_Tab.installed, Icons.check_circle_outline, 'Installed', cs),
        ],
      ),
    );
  }

  Widget _tabItem(_Tab tab, IconData icon, String label, ColorScheme cs) {
    final isSelected = _currentTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _currentTab = tab;
          _detailExt = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? cs.primary.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isSelected ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Search Bar ────────────────────────────────────────────────────────

  Widget _buildSearchBar(ThemeData theme, ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        style: TextStyle(fontSize: 14, color: cs.onSurface),
        decoration: InputDecoration(
          hintText: 'Search extensions...',
          hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          prefixIcon: Icon(Icons.search, size: 20, color: cs.onSurfaceVariant),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () { _searchCtrl.clear(); _search(''); },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEEEEEE),
        ),
      ),
    );
  }

  // ── Category Chips ────────────────────────────────────────────────────

  Widget _buildCategoryChips(ThemeData theme, ColorScheme cs, bool isDark) {
    final cats = ['All', ..._categories.map((c) => c.name)];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = cats[i];
          final isSelected = _selectedCategory == cat;
          return FilterChip(
            label: Text(cat, style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.white : cs.onSurface,
            )),
            selected: isSelected,
            onSelected: (_) {
              setState(() => _selectedCategory = cat);
              _search(_searchCtrl.text);
            },
            selectedColor: cs.primary,
            backgroundColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEEEEEE),
            side: BorderSide.none,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────

  Widget _buildBody(ThemeData theme, ColorScheme cs, bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text('Something went wrong', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(_error!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _loadFeatured, child: const Text('Retry')),
          ],
        ),
      );
    }

    switch (_currentTab) {
      case _Tab.home:
        return _buildHomeTab(theme, cs, isDark);
      case _Tab.search:
        return _buildSearchResults(theme, cs, isDark);
      case _Tab.installed:
        return _buildInstalledTab(theme, cs, isDark);
    }
  }

  // ── Home Tab ──────────────────────────────────────────────────────────

  Widget _buildHomeTab(ThemeData theme, ColorScheme cs, bool isDark) {
    final extensions = _featured.isNotEmpty ? _featured : _results;
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // Categories grid
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Browse by Category', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface,
          )),
        ),
        _buildCategoriesGrid(cs, isDark),

        // Featured / Trending
        if (extensions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Row(
              children: [
                Icon(Icons.trending_up_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('Trending Extensions', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface,
                )),
              ],
            ),
          ),
          ...extensions.take(6).map((ext) => _buildExtensionCard(ext, theme, cs, isDark)),
        ],

        // Recommended for you
        if (extensions.length > 6) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('Recommended for You', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface,
            )),
          ),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: extensions.length - 6,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _buildHorizontalCard(extensions[i + 6], theme, cs, isDark),
            ),
          ),
        ],
      ],
    );
  }

  // ── Categories Grid (Play Store style) ────────────────────────────────

  Widget _buildCategoriesGrid(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
        ),
        itemCount: _categories.length,
        itemBuilder: (_, i) {
          final cat = _categories[i];
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = cat.name;
                _currentTab = _Tab.search;
              });
              _search(_searchCtrl.text);
            },
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      cat.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  Icon(cat.icon, size: 28, color: cat.color),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Extension Card (Play Store style) ─────────────────────────────────

  Widget _buildExtensionCard(MarketplaceExtension ext, ThemeData theme, ColorScheme cs, bool isDark) {
    final installState = _installStates[ext.id] ?? _InstallState.notInstalled;
    final alreadyInstalled = ExtensionRegistry.instance.get(ext.id) != null;

    return GestureDetector(
      onTap: () => setState(() => _detailExt = ext),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            // Icon
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ext.iconUrl != null
                  ? Image.network(ext.iconUrl!, width: 52, height: 52, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _defaultIcon(52, cs))
                  : _defaultIcon(52, cs),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ext.displayName.isNotEmpty ? ext.displayName : ext.name,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ext.namespace,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.star_rounded, size: 14, color: Colors.amber[600]),
                      const SizedBox(width: 2),
                      Text(
                        ext.averageRating != null ? ext.averageRating!.toStringAsFixed(1) : '—',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.download_rounded, size: 13, color: cs.onSurfaceVariant),
                      const SizedBox(width: 2),
                      Text(
                        _formatDownloads(ext.downloadCount),
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Install button
            if (alreadyInstalled || installState == _InstallState.installed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Installed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary)),
              )
            else if (installState == _InstallState.installing)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              FilledButton(
                onPressed: () => _install(ext),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: Size.zero,
                ),
                child: const Text('Install', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  // ── Horizontal Card (for recommended section) ────────────────────────

  Widget _buildHorizontalCard(MarketplaceExtension ext, ThemeData theme, ColorScheme cs, bool isDark) {
    return GestureDetector(
      onTap: () => setState(() => _detailExt = ext),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ext.iconUrl != null
                  ? Image.network(ext.iconUrl!, width: 48, height: 48, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _defaultIcon(48, cs))
                  : _defaultIcon(48, cs),
            ),
            const SizedBox(height: 10),
            Text(
              ext.displayName.isNotEmpty ? ext.displayName : ext.name,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Row(
              children: [
                Icon(Icons.star_rounded, size: 12, color: Colors.amber[600]),
                const SizedBox(width: 2),
                Text(
                  ext.averageRating != null ? ext.averageRating!.toStringAsFixed(1) : '—',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurface),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Search Results ────────────────────────────────────────────────────

  Widget _buildSearchResults(ThemeData theme, ColorScheme cs, bool isDark) {
    if (_results.isEmpty && !_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              _searchCtrl.text.isEmpty ? 'Search for extensions' : 'No results found',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _results.length + (_loadingMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _results.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _buildExtensionCard(_results[i], theme, cs, isDark);
      },
    );
  }

  // ── Installed Tab ─────────────────────────────────────────────────────

  Widget _buildInstalledTab(ThemeData theme, ColorScheme cs, bool isDark) {
    final installed = ExtensionRegistry.instance.all;
    if (installed.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.extension_off_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('No extensions installed', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
            const SizedBox(height: 8),
            Text(
              'Browse the marketplace to find extensions',
              style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 12),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: installed.length,
      itemBuilder: (_, i) {
        final ext = installed[i];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.extension_rounded, color: cs.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ext.manifest.displayName ?? ext.manifest.name,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
                    ),
                    Text(
                      ext.manifest.version,
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.settings_outlined, size: 18, color: cs.onSurfaceVariant),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ExtensionSettingsPage(extension: ext),
                  ));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Detail Page (VS Code style) ──────────────────────────────────────

  Widget _buildDetailPage(ThemeData theme, ColorScheme cs) {
    final ext = _detailExt!;
    final installState = _installStates[ext.id] ?? _InstallState.notInstalled;
    final alreadyInstalled = ExtensionRegistry.instance.get(ext.id) != null;

    return Column(
      children: [
        // Top bar
        Container(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                onPressed: () => setState(() => _detailExt = null),
              ),
              Expanded(
                child: Text(
                  ext.displayName.isNotEmpty ? ext.displayName : ext.name,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),

        // Hero header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ext.iconUrl != null
                    ? Image.network(ext.iconUrl!, width: 72, height: 72, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _defaultIcon(72, cs))
                    : _defaultIcon(72, cs),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ext.displayName.isNotEmpty ? ext.displayName : ext.name,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(ext.namespace, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Text('v${ext.version}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (alreadyInstalled || installState == _InstallState.installed)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded, size: 14, color: cs.primary),
                                const SizedBox(width: 4),
                                Text('Installed', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
                              ],
                            ),
                          )
                        else if (installState == _InstallState.installing)
                          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        else
                          FilledButton.icon(
                            onPressed: () => _install(ext),
                            icon: const Icon(Icons.download_rounded, size: 16),
                            label: const Text('Install'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            ),
                          ),
                        const SizedBox(width: 12),
                        // Stats
                        _statBadge(Icons.star_rounded, '${ext.averageRating?.toStringAsFixed(1) ?? "—"}', Colors.amber[600]!),
                        const SizedBox(width: 8),
                        _statBadge(Icons.download_rounded, _formatDownloads(ext.downloadCount), cs.onSurfaceVariant),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),

        // README content
        Expanded(
          child: _DetailReadme(client: _client, ext: ext),
        ),
      ],
    );
  }

  Widget _statBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  // ── Bottom Nav ────────────────────────────────────────────────────────

  Widget _buildBottomNav(ThemeData theme, ColorScheme cs, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            _bottomNavItem(_Tab.home, Icons.home_rounded, 'Home', cs),
            _bottomNavItem(_Tab.search, Icons.search_rounded, 'Search', cs),
            _bottomNavItem(_Tab.installed, Icons.check_circle_outline, 'Installed', cs),
          ],
        ),
      ),
    );
  }

  Widget _bottomNavItem(_Tab tab, IconData icon, String label, ColorScheme cs) {
    final isSelected = _currentTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _currentTab = tab;
          _detailExt = null;
        }),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: isSelected ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  Widget _defaultIcon(double size, ColorScheme cs) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Icon(Icons.extension_rounded, size: size * 0.5, color: cs.primary),
    );
  }

  String _formatDownloads(int? count) {
    if (count == null) return '—';
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

// ═══════════════════════════════════════════════════════════════
// Detail README widget (loads async)
// ═══════════════════════════════════════════════════════════════

class _DetailReadme extends StatefulWidget {
  final OpenVsxClient client;
  final MarketplaceExtension ext;
  const _DetailReadme({required this.client, required this.ext});

  @override
  State<_DetailReadme> createState() => _DetailReadmeState();
}

class _DetailReadmeState extends State<_DetailReadme> {
  String? _readme;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.client.getReadme(
          widget.ext.namespace, widget.ext.name, widget.ext.version);
      if (!mounted) return;
      setState(() { _readme = r; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_readme == null || _readme!.isEmpty) {
      return Center(
        child: Text(
          widget.ext.description,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Text(
        _readme!,
        style: TextStyle(fontSize: 13, color: cs.onSurface, height: 1.5),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Enums
// ═══════════════════════════════════════════════════════════════

enum _InstallState { notInstalled, installing, installed, error }
