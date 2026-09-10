/// Official Visual Studio Marketplace view.
///
/// The view is deliberately a sidebar surface, not an editor tab. It follows
/// the VS Code extensions view model: search/filter/list on the left and an
/// extension detail surface with Details and Changelog sections.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../extension_host_manager.dart';
import '../extension_registry.dart';
import '../marketplace_client.dart';
import '../models/marketplace_extension.dart';
import '../vsix_installer.dart';
import 'extension_readme_view.dart';
import 'extension_settings_page.dart';

class MarketplacePage extends StatefulWidget {
  final bool embedded;

  const MarketplacePage({super.key, this.embedded = false});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  final _client = ExtensionMarketplaceClient();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  final _categories = const [
    'All',
    'Programming Languages',
    'Snippets',
    'Linters',
    'Formatters',
    'Themes',
    'Debuggers',
    'Other',
  ];
  final _sorts = const [
    ('Relevance', 'relevance'),
    ('Most installs', 'downloadCount'),
    ('Top rated', 'rating'),
    ('Recently updated', 'timestamp'),
  ];

  List<MarketplaceExtension> _extensions = [];
  String _category = 'All';
  String _sort = 'relevance';
  MarketplaceExtension? _selected;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  int _offset = 0;
  Timer? _debounce;
  final Map<String, _InstallStatus> _installStatus = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreWhenNeeded);
    _loadExtensions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _client.dispose();
    super.dispose();
  }

  void _loadMoreWhenNeeded() {
    if (_selected != null ||
        _loadingMore ||
        !_hasMore ||
        !_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.extentAfter < 280) {
      _loadMore();
    }
  }

  Future<void> _loadExtensions({bool refresh = true}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
        _offset = 0;
        _extensions = [];
      });
    }
    try {
      final result = await _client.search(
        query: _searchController.text.trim(),
        offset: refresh ? 0 : _offset,
        size: 20,
        category: _category == 'All' || _category == 'Other' ? null : _category,
        sortBy: _sort,
      );
      if (!mounted) return;
      setState(() {
        if (refresh) {
          _extensions = result.extensions;
        } else {
          _extensions = [..._extensions, ...result.extensions];
        }
        _offset = result.offset + result.extensions.length;
        _hasMore = result.hasMore && result.extensions.isNotEmpty;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await _loadExtensions(refresh: false);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 420),
      () => _loadExtensions(),
    );
    setState(() {});
  }

  void _selectCategory(String value) {
    if (_category == value) return;
    setState(() => _category = value);
    _loadExtensions();
  }

  void _selectSort(String value) {
    if (_sort == value) return;
    setState(() => _sort = value);
    _loadExtensions();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final surface = dark ? const Color(0xff252526) : const Color(0xfff5f5f5);
    final content = Container(
      color: surface,
      child: _selected == null
          ? _buildBrowse(theme, dark)
          : _buildDetails(theme, dark, _selected!),
    );

    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        title: const Text('Extensions'),
        elevation: 0,
      ),
      body: content,
    );
  }

  Widget _buildBrowse(ThemeData theme, bool dark) {
    final foreground = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      children: [
        _buildSearchHeader(theme, dark),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(child: _buildError(theme, _error!))
        else if (_extensions.isEmpty)
          Expanded(child: _buildEmpty(theme))
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadExtensions(),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 16),
                itemCount: _extensions.length + (_loadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _extensions.length) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  return _buildExtensionTile(
                    theme,
                    dark,
                    _extensions[index],
                    foreground,
                    muted,
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchHeader(ThemeData theme, bool dark) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _loadExtensions(),
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search extensions in Marketplace',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        _loadExtensions();
                        setState(() {});
                      },
                    ),
              filled: true,
              fillColor: dark ? const Color(0xff333333) : Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _CompactDropdown(
                  value: _category,
                  values: _categories,
                  label: 'Filter',
                  onChanged: _selectCategory,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: _CompactDropdown(
                  value: _sort,
                  values: _sorts.map((item) => item.$2).toList(),
                  labels: _sorts.map((item) => item.$1).toList(),
                  label: 'Sort',
                  onChanged: _selectSort,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExtensionTile(
    ThemeData theme,
    bool dark,
    MarketplaceExtension extension,
    Color foreground,
    Color muted,
  ) {
    final installed = ExtensionRegistry.instance.get(extension.id);
    final status = _installStatus[extension.id] ?? _InstallStatus.idle;
    final update = installed != null &&
        _compareVersions(extension.version, installed.manifest.version) > 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: 0,
      color: dark ? const Color(0xff2d2d2d) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(5),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: () => setState(() => _selected = extension),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ExtensionIcon(url: extension.iconUrl, size: 42),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      extension.displayName.isEmpty
                          ? extension.name
                          : extension.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            extension.publisherDisplayName ??
                                extension.namespace,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: muted),
                          ),
                        ),
                        if (extension.isVerified) ...[
                          const SizedBox(width: 3),
                          Icon(Icons.verified, size: 12, color: Colors.blue[400]),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      extension.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.star, size: 12, color: Colors.amber[700]),
                        const SizedBox(width: 2),
                        Text(
                          extension.averageRating?.toStringAsFixed(1) ?? '—',
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                        const SizedBox(width: 7),
                        Icon(Icons.download, size: 11, color: muted),
                        const SizedBox(width: 2),
                        Text(
                          _formatCount(extension.downloadCount),
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _InstallButton(
                compact: true,
                status: status,
                installed: installed != null,
                updateAvailable: update,
                onPressed: () => _install(extension, force: update),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetails(ThemeData theme, bool dark, MarketplaceExtension extension) {
    final cs = theme.colorScheme;
    final installed = ExtensionRegistry.instance.get(extension.id);
    final status = _installStatus[extension.id] ?? _InstallStatus.idle;
    final update = installed != null &&
        _compareVersions(extension.version, installed.manifest.version) > 0;
    return Column(
      children: [
        SizedBox(
          height: 38,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back to extensions',
                icon: const Icon(Icons.arrow_back, size: 18),
                onPressed: () => setState(() => _selected = null),
              ),
              Expanded(
                child: Text(
                  'Extension Details',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh details',
                icon: const Icon(Icons.refresh, size: 17),
                onPressed: () => setState(() {}),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ExtensionIcon(url: extension.iconUrl, size: 64),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            extension.displayName.isEmpty
                                ? extension.name
                                : extension.displayName,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            extension.publisherDisplayName ??
                                extension.namespace,
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'v${extension.version}',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  extension.description,
                  style: TextStyle(color: cs.onSurface, fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _InstallButton(
                        status: status,
                        installed: installed != null,
                        updateAvailable: update,
                        onPressed: () => _install(extension, force: update),
                      ),
                    ),
                    if (installed != null) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Extension settings',
                        icon: const Icon(Icons.settings_outlined, size: 19),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ExtensionSettingsPage(extension: installed),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (installed != null) ...[
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: () => _restartExtension(extension.id),
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: const Text('Restart extension host'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(34),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _buildStats(theme, extension),
                const SizedBox(height: 12),
                _buildLinks(theme, extension),
                const SizedBox(height: 12),
                DefaultTabController(
                  length: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TabBar(
                        isScrollable: true,
                        labelPadding: const EdgeInsets.only(right: 22),
                        tabAlignment: TabAlignment.start,
                        labelColor: cs.primary,
                        unselectedLabelColor: cs.onSurfaceVariant,
                        indicatorSize: TabBarIndicatorSize.label,
                        tabs: const [
                          Tab(text: 'Details'),
                          Tab(text: 'Changelog'),
                        ],
                      ),
                      SizedBox(
                        height: 560,
                        child: TabBarView(
                          children: [
                            _RemoteContent(
                              key: ValueKey('details-${extension.id}-${extension.version}'),
                              client: _client,
                              extension: extension,
                              changelog: false,
                            ),
                            _RemoteContent(
                              key: ValueKey('changelog-${extension.id}-${extension.version}'),
                              client: _client,
                              extension: extension,
                              changelog: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStats(ThemeData theme, MarketplaceExtension extension) {
    final color = theme.colorScheme.onSurfaceVariant;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        _MetaValue(
          label: 'Installs',
          value: _formatCount(extension.downloadCount),
          color: color,
        ),
        _MetaValue(
          label: 'Rating',
          value: extension.averageRating?.toStringAsFixed(1) ?? '—',
          color: color,
        ),
        _MetaValue(
          label: 'Reviews',
          value: _formatCount(extension.reviewCount),
          color: color,
        ),
        _MetaValue(label: 'Version', value: extension.version, color: color),
        if (extension.engine != null)
          _MetaValue(label: 'VS Code', value: extension.engine!, color: color),
      ],
    );
  }

  Widget _buildLinks(ThemeData theme, MarketplaceExtension extension) {
    final links = <String, String>{
      if (extension.homepage != null) 'Homepage': extension.homepage!,
      if (extension.sourceUrl != null) 'Repository': extension.sourceUrl!,
      if (extension.supportUrl != null) 'Support': extension.supportUrl!,
      if (extension.sponsorUrl != null) 'Sponsor': extension.sponsorUrl!,
    };
    if (links.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 5,
      runSpacing: 4,
      children: links.entries
          .map(
            (entry) => ActionChip(
              label: Text(entry.key, style: const TextStyle(fontSize: 11)),
              avatar: const Icon(Icons.open_in_new, size: 13),
              onPressed: () => _openUrl(entry.value),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              visualDensity: VisualDensity.compact,
            ),
          )
          .toList(),
    );
  }

  Widget _buildError(ThemeData theme, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, color: theme.colorScheme.error, size: 30),
            const SizedBox(height: 8),
            Text(
              'Marketplace unavailable',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 5),
            Text(
              message,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: () => _loadExtensions(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Text(
        _searchController.text.isEmpty
            ? 'No extensions found'
            : 'No extension matches this search',
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
      ),
    );
  }

  Future<void> _install(MarketplaceExtension extension, {bool force = false}) async {
    setState(() => _installStatus[extension.id] = _InstallStatus.installing);
    try {
      await ExtensionRegistry.instance.load();
      final url = extension.downloadUrl ??
          await _client.getDownloadUrl(
            extension.namespace,
            extension.name,
            extension.version,
          );
      final existing = ExtensionRegistry.instance.get(extension.id);
      if (existing != null) {
        await ExtensionHostManager.instance.deactivate(extension.id);
      }
      final result = await VsixInstaller().installFromUrl(url, force: force);
      if (result is! InstallSuccess) {
        throw StateError(
          result is InstallFailure ? result.reason : 'Installation interrompue',
        );
      }
      await ExtensionRegistry.instance.load();
      if (!mounted) return;
      setState(() => _installStatus[extension.id] = _InstallStatus.installed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${extension.displayName} installed'),
          action: SnackBarAction(
            label: 'Restart',
            onPressed: () => _restartExtension(extension.id),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _installStatus[extension.id] = _InstallStatus.error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Install failed: $error'),
          backgroundColor: themeError(context),
        ),
      );
    }
  }

  Future<void> _restartExtension(String extensionId) async {
    try {
      await ExtensionHostManager.instance.deactivate(extensionId);
      final extension = ExtensionRegistry.instance.get(extensionId);
      if (extension != null && extension.isRunnable) {
        await ExtensionHostManager.instance.activate(extension);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Extension host restarted')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restart unavailable: $error'),
          backgroundColor: themeError(context),
        ),
      );
    }
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _RemoteContent extends StatefulWidget {
  final ExtensionMarketplaceClient client;
  final MarketplaceExtension extension;
  final bool changelog;

  const _RemoteContent({
    super.key,
    required this.client,
    required this.extension,
    required this.changelog,
  });

  @override
  State<_RemoteContent> createState() => _RemoteContentState();
}

class _RemoteContentState extends State<_RemoteContent> {
  MarketplaceContent? _content;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final content = widget.changelog
          ? await widget.client.getChangelog(
              widget.extension.namespace,
              widget.extension.name,
              widget.extension.version,
            )
          : await widget.client.getReadme(
              widget.extension.namespace,
              widget.extension.name,
              widget.extension.version,
            );
      if (!mounted) return;
      setState(() => _content = content);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_content != null) {
      return ExtensionReadmeView(
        content: _content!.content,
        isHtml: _content!.isHtml,
        baseUri: _content!.baseUri,
      );
    }
    if (_error != null) {
      return Center(
        child: Text(
          widget.changelog ? 'No changelog available.' : 'Unable to load details.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    return const Center(child: CircularProgressIndicator(strokeWidth: 2));
  }
}

class _ExtensionIcon extends StatelessWidget {
  final String? url;
  final double size;

  const _ExtensionIcon({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * .15),
      ),
      child: Icon(Icons.extension_outlined, color: cs.primary, size: size * .5),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .15),
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

class _InstallButton extends StatelessWidget {
  final _InstallStatus status;
  final bool installed;
  final bool updateAvailable;
  final VoidCallback onPressed;
  final bool compact;

  const _InstallButton({
    required this.status,
    required this.installed,
    required this.updateAvailable,
    required this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (status == _InstallStatus.installing) {
      return const SizedBox(
        width: 19,
        height: 19,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final label = updateAvailable
        ? 'Update'
        : installed
            ? 'Installed'
            : 'Install';
    return FilledButton(
      onPressed: installed && !updateAvailable ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: compact ? Size.zero : const Size.fromHeight(34),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 12,
          vertical: compact ? 5 : 8,
        ),
        textStyle: TextStyle(fontSize: compact ? 10 : 12),
      ),
      child: Text(label),
    );
  }
}

class _CompactDropdown extends StatelessWidget {
  final String value;
  final List<String> values;
  final List<String>? labels;
  final String label;
  final ValueChanged<String> onChanged;

  const _CompactDropdown({
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
    this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final index = values.indexOf(value);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 10),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: values.contains(value) ? value : values.first,
          isDense: true,
          isExpanded: true,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          items: values.asMap().entries
              .map(
                (entry) => DropdownMenuItem<String>(
                  value: entry.value,
                  child: Text(
                    labels != null && entry.key < labels!.length
                        ? labels![entry.key]
                        : entry.value,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (selected) {
            if (selected != null) onChanged(selected);
          },
        ),
      ),
    );
  }
}

class _MetaValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetaValue({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 9, color: color)),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

enum _InstallStatus { idle, installing, installed, error }

int _compareVersions(String left, String right) {
  final a = left.split(RegExp(r'[-+]')).first.split('.').map(int.tryParse);
  final b = right.split(RegExp(r'[-+]')).first.split('.').map(int.tryParse);
  final av = a.map((value) => value ?? 0).toList();
  final bv = b.map((value) => value ?? 0).toList();
  for (var index = 0; index < 3; index++) {
    final x = index < av.length ? av[index] : 0;
    final y = index < bv.length ? bv[index] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

Color themeError(BuildContext context) => Theme.of(context).colorScheme.error;

String _formatCount(int count) {
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
  return count.toString();
}