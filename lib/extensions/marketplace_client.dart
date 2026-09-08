/// Unified extension marketplace client.
///
/// The official Visual Studio Marketplace is queried first. Open VSX is kept
/// as a compatibility fallback for extensions which are not published there.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models/marketplace_extension.dart';
import 'open_vsx_client.dart';

class MarketplaceContent {
  final String content;
  final bool isHtml;

  const MarketplaceContent(this.content, {required this.isHtml});
}

class ExtensionMarketplaceClient {
  static const _galleryUrl =
      'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery';
  static const _publisher = 'Microsoft.VisualStudio.Code';
  static const _timeout = Duration(seconds: 20);

  final http.Client _http;
  final OpenVsxClient _openVsx;

  ExtensionMarketplaceClient({http.Client? client})
      : _http = client ?? http.Client(),
        _openVsx = OpenVsxClient(client: client);

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
              {'filterType': 8, 'value': _publisher},
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
        'flags': 914,
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
      return _parseSearch(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {
      return _openVsx.search(
        query: query,
        offset: offset,
        size: size,
        category: category,
        sortBy: sortBy == 'relevance' ? 'relevance' : 'downloadCount',
      );
    }
  }

  Future<MarketplaceSearchResult> featured({int size = 20}) =>
      search(query: '', size: size, sortBy: 'downloadCount');

  Future<String> getDownloadUrl(
      String namespace, String name, String version) async {
    try {
      final extension = await _queryOne(namespace, name);
      final versions = _versions(extension);
      final match = versions.firstWhere(
        (v) => v['version']?.toString() == version,
        orElse: () => versions.isNotEmpty ? versions.first : const {},
      );
      final url = _assetUrl(match, 'Microsoft.VisualStudio.Services.VSIXPackage');
      if (url != null && url.isNotEmpty) return url;
    } catch (_) {}
    return _openVsx.getDownloadUrl(namespace, name, version);
  }

  Future<MarketplaceContent?> getReadme(
      String namespace, String name, String version) async {
    try {
      final extension = await _queryOne(namespace, name);
      final versions = _versions(extension);
      final match = versions.firstWhere(
        (v) => v['version']?.toString() == version,
        orElse: () => versions.isNotEmpty ? versions.first : const {},
      );
      final url = _assetUrl(match, 'Microsoft.VisualStudio.Services.Content.Details');
      if (url != null) {
        final response =
            await _http.get(Uri.parse(url)).timeout(_timeout);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final body = response.body.trim();
          if (body.isNotEmpty) {
            return MarketplaceContent(body, isHtml: _looksLikeHtml(body));
          }
        }
      }
    } catch (_) {}

    final fallback = await _openVsx.getReadme(namespace, name, version);
    return fallback == null || fallback.trim().isEmpty
        ? null
        : MarketplaceContent(fallback, isHtml: false);
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
                  {'filterType': 8, 'value': _publisher},
                ],
              },
            ],
            'flags': 914,
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
    return MarketplaceExtension(
      namespace: namespace,
      name: name,
      displayName: value['displayName']?.toString() ?? name,
      description: value['shortDescription']?.toString() ?? '',
      version: version,
      iconUrl: _assetUrl(latest, 'Microsoft.VisualStudio.Services.Icons.Default'),
      averageRating: _number(statistics['averagerating']),
      downloadCount: _number(statistics['install'])?.toInt() ?? 0,
      categories: (value['categories'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      tags: (value['tags'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      repository: value['repositoryUrl']?.toString(),
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
    _openVsx.dispose();
  }
}