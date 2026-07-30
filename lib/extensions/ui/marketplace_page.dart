/// Page Marketplace Open VSX — Phase 8.
///
/// Permet de chercher, filtrer et installer des extensions depuis open-vsx.org.
/// Utilise OpenVsxClient pour les requêtes et VsixInstaller pour l'installation.
///
/// Usage :
///   Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketplacePage()));
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/marketplace_extension.dart';
import '../open_vsx_client.dart';
import '../extension_registry.dart';
import '../vsix_installer.dart';

/// Catégories Open VSX affichées comme filtres.
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

/// Tris disponibles.
const _kSortOptions = {
  'Relevance': 'relevance',
  'Downloads': 'downloadCount',
  'Rating': 'rating',
  'Recent': 'timestamp',
};

class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  final _client = OpenVsxClient();
  final _searchCtrl = TextEditingController();

  List<MarketplaceExtension> _results = [];
  bool _loading = false;
  String? _error;
  int _offset = 0;
  int _totalSize = 0;
  bool _loadingMore = false;

  String _selectedCategory = 'All';
  String _sortBy = 'relevance';

  // Install state per extension id
  final Map<String, _InstallState> _installStates = {};

  Timer? _debounce;
  final _scrollCtrl = ScrollController();

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

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _loadFeatured() async {
    setState(() {
      _loading = true;
      _error = null;
      _offset = 0;
    });
    try {
      final result = await _client.featured(size: 20);
      if (!mounted) return;
      setState(() {
        _results = result.extensions;
        _totalSize = result.totalSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _search({bool reset = true}) async {
    final query = _searchCtrl.text.trim();
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _offset = 0;
        _results = [];
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final category = _selectedCategory == 'All' ? null : _selectedCategory;
      final result = await _client.search(
        query: query,
        offset: _offset,
        size: 20,
        category: category,
        sortBy: _sortBy,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _results = result.extensions;
        } else {
          _results = [..._results, ...result.extensions];
        }
        _totalSize = result.totalSize;
        _offset += result.extensions.length;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (_searchCtrl.text.trim().isEmpty) {
        _loadFeatured();
      } else {
        _search();
      }
    });
  }

  void _onScroll() {
    if (_loadingMore || _loading) return;
    if (_offset >= _totalSize) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      _offset = _results.length;
      _search(reset: false);
    }
  }

  // ── Install ────────────────────────────────────────────────────────────────

  Future<void> _install(MarketplaceExtension ext) async {
    setState(() => _installStates[ext.id] = _InstallState.installing);

    final installer = VsixInstaller(
      onProgress: (p, msg) {
        // Could update progress UI here if needed
      },
    );

    try {
      final url = ext.buildDownloadUrl();
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red[700] : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : theme.scaffoldBackgroundColor;
    final cardColor = isDark ? const Color(0xFF252526) : Colors.white;
    final divColor = isDark ? const Color(0xFF3C3C3C) : const Color(0xFFE0E0E0);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF2D2D2D) : null,
        elevation: 0,
        title: const Text('Extensions', style: TextStyle(fontSize: 16)),
        actions: [
          // Sort dropdown
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, size: 20),
            tooltip: 'Sort by',
            onSelected: (v) {
              setState(() => _sortBy = v);
              _searchCtrl.text.isEmpty ? _loadFeatured() : _search();
            },
            itemBuilder: (_) => _kSortOptions.entries
                .map((e) => PopupMenuItem(
                      value: e.value,
                      child: Row(children: [
                        if (_sortBy == e.value)
                          const Icon(Icons.check, size: 16, color: Color(0xFF0066B8)),
                        const SizedBox(width: 8),
                        Text(e.key),
                      ]),
                    ))
                .toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar ──────────────────────────────────────────────────
          Container(
            color: isDark ? const Color(0xFF2D2D2D) : theme.appBarTheme.backgroundColor,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher des extensions…',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _loadFeatured();
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? const Color(0xFF3C3C3C) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: divColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: divColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF0066B8), width: 1.5),
                ),
              ),
            ),
          ),

          // ── Category chips ───────────────────────────────────────────────
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _kCategories.length,
              itemBuilder: (_, i) {
                final cat = _kCategories[i];
                final selected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(cat, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    selectedColor: const Color(0xFF0066B8).withOpacity(0.2),
                    checkmarkColor: const Color(0xFF0066B8),
                    side: BorderSide(
                      color: selected ? const Color(0xFF0066B8) : divColor,
                    ),
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

          const SizedBox(height: 4),

          // ── Results ───────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorView(error: _error!, onRetry: _loadFeatured)
                    : _results.isEmpty
                        ? Center(
                            child: Text(
                              'Aucune extension trouvée',
                              style: TextStyle(
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.all(8),
                            itemCount: _results.length + (_loadingMore ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i == _results.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              return _ExtensionCard(
                                ext: _results[i],
                                cardColor: cardColor,
                                installState: _installStates[_results[i].id] ??
                                    _InstallState.notInstalled,
                                onInstall: () => _install(_results[i]),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ── Extension card widget ─────────────────────────────────────────────────────

enum _InstallState { notInstalled, installing, installed, error }

class _ExtensionCard extends StatelessWidget {
  final MarketplaceExtension ext;
  final Color cardColor;
  final _InstallState installState;
  final VoidCallback onInstall;

  const _ExtensionCard({
    required this.ext,
    required this.cardColor,
    required this.installState,
    required this.onInstall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final subColor = isDark ? Colors.white54 : Colors.black54;

    // Check if already installed in local registry
    final alreadyInstalled = ExtensionRegistry.instance.isInstalled(ext.id) ||
        installState == _InstallState.installed;

    return Card(
      color: cardColor,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark ? const Color(0xFF3C3C3C) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ext.iconUrl != null
                  ? Image.network(
                      ext.iconUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const _DefaultExtIcon(size: 40),
                    )
                  : const _DefaultExtIcon(size: 40),
            ),
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
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        'v${ext.version}',
                        style: TextStyle(fontSize: 10, color: subColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ext.namespace,
                    style: TextStyle(fontSize: 11, color: subColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ext.description,
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (ext.averageRating != null) ...[
                        const Icon(Icons.star, size: 12, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          ext.averageRating!.toStringAsFixed(1),
                          style: TextStyle(fontSize: 11, color: subColor),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (ext.downloadCount > 0) ...[
                        Icon(Icons.download, size: 12, color: subColor),
                        const SizedBox(width: 2),
                        Text(
                          _formatCount(ext.downloadCount),
                          style: TextStyle(fontSize: 11, color: subColor),
                        ),
                      ],
                      if (ext.categories.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0066B8).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ext.categories.first,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF0066B8),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
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
    );
  }

  static String _formatCount(int n) {
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
    switch (state) {
      case _InstallState.notInstalled:
        return SizedBox(
          height: 30,
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              backgroundColor: const Color(0xFF0066B8).withOpacity(0.1),
              foregroundColor: const Color(0xFF0066B8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('Install', style: TextStyle(fontSize: 12)),
          ),
        );
      case _InstallState.installing:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _InstallState.installed:
        return const Icon(Icons.check_circle, color: Colors.green, size: 24);
      case _InstallState.error:
        return const Icon(Icons.error_outline, color: Colors.red, size: 24);
    }
  }
}

class _DefaultExtIcon extends StatelessWidget {
  final double size;
  const _DefaultExtIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0066B8).withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(Icons.extension, size: size * 0.6, color: const Color(0xFF0066B8)),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              'Impossible de charger les extensions',
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
