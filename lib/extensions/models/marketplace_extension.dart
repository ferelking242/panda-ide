/// Extension returned by the official Visual Studio Marketplace Gallery API.
library;

class MarketplaceExtension {
  final String namespace; // publisher id used by Gallery URLs
  final String name;
  final String displayName;
  final String description;
  final String version;
  final String? iconUrl;
  final String? publisherDisplayName;
  final String? publisherDomain;
  final double? averageRating;
  final int reviewCount;
  final int downloadCount;
  final DateTime? timestamp;
  final DateTime? releaseDate;
  final DateTime? lastUpdated;
  final List<String> categories;
  final List<String> tags;
  final String? license;
  final String? repository;
  final String? homepage;
  final String? supportUrl;
  final String? sourceUrl;
  final String? sponsorUrl;
  final String? engine;
  final String? extensionKind;
  final bool isVerified;
  final String? contentBaseUrl;
  final String? detailsUrl;
  final String? changelogUrl;

  /// URL de téléchargement du .vsix pour la version courante.
  final String? downloadUrl;

  const MarketplaceExtension({
    required this.namespace,
    required this.name,
    required this.displayName,
    required this.description,
    required this.version,
    this.iconUrl,
    this.publisherDisplayName,
    this.publisherDomain,
    this.averageRating,
    this.reviewCount = 0,
    this.downloadCount = 0,
    this.timestamp,
    this.releaseDate,
    this.lastUpdated,
    this.categories = const [],
    this.tags = const [],
    this.license,
    this.repository,
    this.homepage,
    this.supportUrl,
    this.sourceUrl,
    this.sponsorUrl,
    this.engine,
    this.extensionKind,
    this.isVerified = false,
    this.contentBaseUrl,
    this.detailsUrl,
    this.changelogUrl,
    this.downloadUrl,
  });

  String get id => '$namespace.$name';

  factory MarketplaceExtension.fromSearchJson(Map<String, dynamic> json) {
    List<String> strings(String key) {
      final v = json[key];
      if (v is List) return v.whereType<String>().toList();
      return const [];
    }

    DateTime? date(String key) {
      final v = json[key] as String?;
      if (v == null) return null;
      try {
        return DateTime.parse(v);
      } catch (_) {
        return null;
      }
    }

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
      timestamp: date('timestamp'),
      categories: strings('categories'),
      tags: strings('tags'),
      license: json['license'] as String?,
      repository: json['repository'] as String?,
      downloadUrl: json['files']?['download'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'namespace': namespace,
    'name': name,
    'displayName': displayName,
    'description': description,
    'version': version,
    if (iconUrl != null) 'iconUrl': iconUrl,
    if (publisherDisplayName != null) 'publisherDisplayName': publisherDisplayName,
    if (publisherDomain != null) 'publisherDomain': publisherDomain,
    if (averageRating != null) 'averageRating': averageRating,
    'reviewCount': reviewCount,
    'downloadCount': downloadCount,
    if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
    if (releaseDate != null) 'releaseDate': releaseDate!.toIso8601String(),
    if (lastUpdated != null) 'lastUpdated': lastUpdated!.toIso8601String(),
    'categories': categories,
    'tags': tags,
    if (license != null) 'license': license,
    if (repository != null) 'repository': repository,
    if (homepage != null) 'homepage': homepage,
    if (supportUrl != null) 'supportUrl': supportUrl,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
    if (sponsorUrl != null) 'sponsorUrl': sponsorUrl,
    if (engine != null) 'engine': engine,
    if (extensionKind != null) 'extensionKind': extensionKind,
    'isVerified': isVerified,
    if (contentBaseUrl != null) 'contentBaseUrl': contentBaseUrl,
    if (detailsUrl != null) 'detailsUrl': detailsUrl,
    if (changelogUrl != null) 'changelogUrl': changelogUrl,
    if (downloadUrl != null) 'downloadUrl': downloadUrl,
  };

  @override
  String toString() => 'MarketplaceExtension($id@$version)';
}

/// Paginated result from the Visual Studio Marketplace Gallery.
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
