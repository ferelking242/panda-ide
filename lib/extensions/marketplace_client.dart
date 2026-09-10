/// Unified extension marketplace client.
///
/// This targets the official Visual Studio Marketplace Gallery only.
/// Open VSX is intentionally not mixed into the results or install flow.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models/marketplace_extension.dart';

class MarketplaceContent {
  final String content;
  final bool isHtml;
  final Uri? baseUri;

  const MarketplaceContent(
    this.content, {
    required this.isHtml,
    this.baseUri,
  });
}

class ExtensionMarketplaceClient {
  static const _galleryUrl =
      'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery'
      '?api-version=7.2-preview.1';
  static const _timeout = Duration(seconds: 20);

  final http.Client _http;

  ExtensionMarketplaceClient({http.Client? client}) : _http = client ?? http.Client();

  Future<MarketplaceSearchResult> search({
    required String query,
    int offset = 0,
    int size = 20,
    String? category,
    String sortBy = 'relevance',
  }) async {
    try {
      final body = <String, dynamic>{
        'filters': [
          {
            'criteria': [
              if (query.trim().isNotEmpty)
                {'filterType': 10, 'value': query.trim()},
              if (category != null)
                {'filterType': 5, 'value': category},
            ],
            'pageNumber': (offset ~/ size) + 1,
            'pageSize': size,
            'sortBy': _sortValue(sortBy),
          },
        ],
        // Latest version files/properties, statistics, asset URI and
        // category/tag data, matching the data used by VS Code's view.
        'flags': 918,
      };
      final response = await _http
          .post(
            Uri.parse(_galleryUrl),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'User-Agent': 'PandaIDE/2.3 (Android; arm64)',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      _assertOk(response);
      final parsed =
          _parseSearch(jsonDecode(response.body) as Map<String, dynamic>);
      return parsed;
    } catch (error) {
      throw StateError('Marketplace Microsoft indisponible : $error');
    }
  }

  Future<MarketplaceSearchResult> featured({int size = 20}) =>
      search(query: '', size: size, sortBy: 'downloadCount');

  Future<String> getDownloadUrl(
      String namespace, String name, String version) async {
    final extension = await _queryOne(namespace, name);
    final versions = _versions(extension);
    final match = versions.firstWhere(
      (v) => v['version']?.toString() == version,
      orElse: () => versions.isNotEmpty ? versions.first : const {},
    );
    final url = _assetUrl(match, 'Microsoft.VisualStudio.Services.VSIXPackage');
    if (url == null || url.isEmpty) {
      throw StateError('VSIX introuvable pour $namespace.$name@$version');
    }
    return url;
  }

  Future<MarketplaceContent> getReadme(
      String namespace, String name, String version) async {
    return _getContent(
      namespace,
      name,
      version,
      'Microsoft.VisualStudio.Services.Content.Details',
      'README',
    );
  }

  Future<MarketplaceContent> getChangelog(
      String namespace, String name, String version) {
    return _getContent(
      namespace,
      name,
      version,
      'Microsoft.VisualStudio.Services.Content.Changelog',
      'Changelog',
    );
  }

  Future<MarketplaceContent> _getContent(
    String namespace,
    String name,
    String version,
    String assetType,
    String label,
  ) async {
    final extension = await _queryOne(namespace, name);
    final versions = _versions(extension);
    final match = versions.firstWhere(
      (v) => v['version']?.toString() == version,
      orElse: () => versions.isNotEmpty ? versions.first : const {},
    );
    final url = _assetUrl(match, assetType);
    if (url == null || url.isEmpty) {
      throw StateError('$label introuvable pour $namespace.$name@$version');
    }
    final response = await _http.get(Uri.parse(url)).timeout(_timeout);
    _assertOk(response);
    final body = response.body.trim();
    if (body.isEmpty) {
      throw StateError('$label vide pour $namespace.$name@$version');
    }
    final rawBase = match['assetUri']?.toString();
    final fallbackBase =
        Uri.tryParse(url)?.resolve('./') ??
        Uri.parse('https://marketplace.visualstudio.com/');
    final baseUri = rawBase == null
        ? fallbackBase
        : Uri.tryParse(rawBase.endsWith('/') ? rawBase : '$rawBase/') ??
            fallbackBase;
    return MarketplaceContent(
      body,
      isHtml: _looksLikeHtml(body),
      baseUri: baseUri,
    );
  }

  Future<Map<String, dynamic>> _queryOne(String namespace, String name) async {
    final response = await _http
        .post(
          Uri.parse(_galleryUrl),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'User-Agent': 'PandaIDE/2.3 (Android; arm64)',
          },
          body: jsonEncode({
            'filters': [
              {
                'criteria': [
                  {'filterType': 7, 'value': '$namespace.$name'},
                ],
              },
            ],
            'flags': 918,
          }),
        )
        .timeout(_timeout);
    _assertOk(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'] as List? ?? const [];
    final first = results.isNotEmpty ? results.first : null;
    final extensions = first is Map ? first['extensions'] as List? : null;
    if (extensions == null || extensions.isEmpty || extensions.first is! Map) {
      throw StateError('Extension $namespace.$name not found');
    }
    return Map<String, dynamic>.from(extensions.first as Map);
  }

  MarketplaceSearchResult _parseSearch(Map<String, dynamic> data) {
    final results = data['results'] as List? ?? const [];
    final first = results.isNotEmpty && results.first is Map
        ? Map<String, dynamic>.from(results.first as Map)
        : <String, dynamic>{};
    final extensions = (first['extensions'] as List? ?? const [])
        .whereType<Map>()
        .map(_toMarketplaceExtension)
        .toList();
    final metadata = first['resultMetadata'] as Map?;
    final count = (metadata?['resultCount'] as num?)?.toInt() ??
        extensions.length;
    final page = (first['paging'] as Map?)?['pageNumber'];
    final pageOffset = page is num ? (page.toInt() - 1) * extensions.length : 0;
    return MarketplaceSearchResult(
      extensions: extensions,
      offset: pageOffset,
      totalSize: count,
    );
  }

  MarketplaceExtension _toMarketplaceExtension(Map value) {
    final publisher = value['publisher'] is Map
        ? Map<String, dynamic>.from(value['publisher'] as Map)
        : <String, dynamic>{};
    final namespace = publisher['publisherName']?.toString() ??
        publisher['publisherId']?.toString() ??
        'unknown';
    final name = value['extensionName']?.toString() ?? 'unknown';
    final versions = _versions(Map<String, dynamic>.from(value));
    final latest = versions.isNotEmpty ? versions.first : const <String, dynamic>{};
    final version = latest['version']?.toString() ?? '0.0.0';
    final statistics = (value['statistics'] as List? ?? const [])
        .whereType<Map>()
        .fold<Map<String, dynamic>>({}, (out, item) {
      final key = item['statisticName']?.toString();
      if (key != null) out[key] = item['value'];
      return out;
    });
    final properties = _properties(latest);
    return MarketplaceExtension(
      namespace: namespace,
      name: name,
      displayName: value['displayName']?.toString() ?? name,
      description: value['shortDescription']?.toString() ?? '',
      version: version,
      iconUrl: _assetUrl(latest, 'Microsoft.VisualStudio.Services.Icons.Default'),
      publisherDisplayName: publisher['displayName']?.toString(),
      publisherDomain: publisher['domain']?.toString(),
      averageRating: _number(statistics['averagerating']),
      reviewCount: _number(statistics['ratingcount'])?.toInt() ?? 0,
      downloadCount: _number(statistics['install'])?.toInt() ?? 0,
      releaseDate: DateTime.tryParse(value['releaseDate']?.toString() ?? ''),
      lastUpdated: DateTime.tryParse(value['lastUpdated']?.toString() ?? '') ??
          DateTime.tryParse(latest['lastUpdated']?.toString() ?? ''),
      categories: (value['categories'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      tags: (value['tags'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      repository: value['repositoryUrl']?.toString(),
      homepage: properties['Microsoft.VisualStudio.Services.Links.Getstarted'] ??
          properties['Microsoft.VisualStudio.Services.Links.Learn'],
      supportUrl: properties['Microsoft.VisualStudio.Services.Links.Support'],
      sourceUrl: properties['Microsoft.VisualStudio.Services.Links.Source'] ??
          properties['Microsoft.VisualStudio.Services.Links.GitHub'],
      sponsorUrl: properties['Microsoft.VisualStudio.Code.SponsorLink'],
      engine: properties['Microsoft.VisualStudio.Code.Engine'],
      extensionKind: properties['Microsoft.VisualStudio.Code.ExtensionKind'],
      isVerified: publisher['flags']?.toString().contains('verified') == true,
      contentBaseUrl: latest['assetUri']?.toString(),
      detailsUrl: _assetUrl(
        latest,
        'Microsoft.VisualStudio.Services.Content.Details',
      ),
      changelogUrl: _assetUrl(
        latest,
        'Microsoft.VisualStudio.Services.Content.Changelog',
      ),
      downloadUrl: _assetUrl(
        latest,
        'Microsoft.VisualStudio.Services.VSIXPackage',
      ),
    );
  }

  List<Map<String, dynamic>> _versions(Map<String, dynamic> extension) =>
      (extension['versions'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  Map<String, String> _properties(Map<String, dynamic> version) {
    final properties = <String, String>{};
    for (final item in (version['properties'] as List? ?? const [])) {
      if (item is Map && item['key'] != null && item['value'] != null) {
        properties[item['key'].toString()] = item['value'].toString();
      }
    }
    return properties;
  }

  String? _assetUrl(Map<String, dynamic> version, String assetType) {
    final files = (version['files'] as List? ?? const []).whereType<Map>();
    for (final file in files) {
      if (file['assetType']?.toString() == assetType) {
        return file['source']?.toString() ?? file['uri']?.toString();
      }
    }
    return null;
  }

  static int _sortValue(String sortBy) {
    switch (sortBy) {
      case 'timestamp':
        return 4;
      case 'downloadCount':
        return 3;
      case 'rating':
        return 2;
      default:
        return 0;
    }
  }

  static double? _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  static bool _looksLikeHtml(String value) =>
      RegExp(r'<\s*(html|body|div|p|h[1-6]|section|img|table)\b',
              caseSensitive: false)
          .hasMatch(value);

  static void _assertOk(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Marketplace HTTP ${response.statusCode}');
    }
  }

  void dispose() {
    _http.close();
  }
}