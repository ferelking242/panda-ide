/// Résultat de recherche Open VSX — https://open-vsx.org/api/-/search
library;

class MarketplaceExtension {
  final String namespace;   // publisher
  final String name;
  final String displayName;
  final String description;
  final String version;
  final String? iconUrl;
  final double? averageRating;
  final int reviewCount;
  final int downloadCount;
  final DateTime? timestamp;
  final List<String> categories;
  final List<String> tags;
  final String? license;
  final String? repository;

  /// URL de téléchargement du .vsix pour la version courante.
  final String? downloadUrl;

  const MarketplaceExtension({
    required this.namespace,
    required this.name,
    required this.displayName,
    required this.description,
    required this.version,
    this.iconUrl,
    this.averageRating,
    this.reviewCount = 0,
    this.downloadCount = 0,
    this.timestamp,
    this.categories = const [],
    this.tags = const [],
    this.license,
    this.repository,
    this.downloadUrl,
  });

  String get id => '$namespace.$name';

  factory MarketplaceExtension.fromSearchJson(Map<String, dynamic> json) {
    List<String> _strings(String key) {
      final v = json[key];
      if (v is List) return v.whereType<String>().toList();
      return const [];
    }

    DateTime? _date(String key) {
      final v = json[key] as String?;
      if (v == null) return null;
      try {
        return DateTime.parse(v);
      } catch (_) {
        return null;
      }
    }

    // Open VSX search result format
    // https://open-vsx.org/swagger-ui/#/registry-api/search
    return MarketplaceExtension(
      namespace: json['namespace'] as String? ?? json['publisher'] as String? ?? 'unknown',
      name: json['name'] as String? ?? 'unknown',
      displayName: json['displayName'] as String? ?? json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      version: json['version'] as String? ?? '0.0.0',
      iconUrl: json['files']?['icon'] as String?,
      averageRating: (json['averageRating'] as num?)?.toDouble(),
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      downloadCount: (json['downloadCount'] as num?)?.toInt() ?? 0,
      timestamp: _date('timestamp'),
      categories: _strings('categories'),
      tags: _strings('tags'),
      license: json['license'] as String?,
      repository: json['repository'] as String?,
      downloadUrl: json['files']?['download'] as String?,
    );
  }

  /// Construit l'URL de téléchargement direct depuis l'API Open VSX.
  String buildDownloadUrl() {
    if (downloadUrl != null) return downloadUrl!;
    return 'https://open-vsx.org/api/$namespace/$name/$version/file/$namespace.$name-$version.vsix';
  }

  Map<String, dynamic> toJson() => {
    'namespace': namespace,
    'name': name,
    'displayName': displayName,
    'description': description,
    'version': version,
    if (iconUrl != null) 'iconUrl': iconUrl,
    if (averageRating != null) 'averageRating': averageRating,
    'reviewCount': reviewCount,
    'downloadCount': downloadCount,
    if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
    'categories': categories,
    'tags': tags,
    if (license != null) 'license': license,
    if (repository != null) 'repository': repository,
    if (downloadUrl != null) 'downloadUrl': downloadUrl,
  };

  @override
  String toString() => 'MarketplaceExtension($id@$version)';
}

/// Résultat paginé d'une recherche Open VSX.
class MarketplaceSearchResult {
  final List<MarketplaceExtension> extensions;
  final int offset;
  final int totalSize;

  const MarketplaceSearchResult({
    required this.extensions,
    required this.offset,
    required this.totalSize,
  });

  bool get hasMore => offset + extensions.length < totalSize;

  factory MarketplaceSearchResult.fromJson(Map<String, dynamic> json) {
    final extensions = (json['extensions'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MarketplaceExtension.fromSearchJson)
        .toList();

    return MarketplaceSearchResult(
      extensions: extensions,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      totalSize: (json['totalSize'] as num?)?.toInt() ?? extensions.length,
    );
  }
}
