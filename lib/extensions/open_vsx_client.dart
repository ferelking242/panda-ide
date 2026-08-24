/// Client REST pour le marketplace Open VSX (https://open-vsx.org).
/// Utilisé pour chercher, lire les métadonnées et récupérer les .vsix.
///
/// API docs : https://open-vsx.org/swagger-ui/index.html
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models/marketplace_extension.dart';

library;




class OpenVsxClient {
  static const String _baseUrl = 'https://open-vsx.org';
  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _http;

  OpenVsxClient({http.Client? client}) : _http = client ?? http.Client();

  // ── Recherche ────────────────────────────────────────────────────────────

  /// Recherche des extensions par texte.
  /// [query]    : texte libre
  /// [offset]   : pagination (défaut 0)
  /// [size]     : nombre de résultats par page (max 50 côté serveur)
  /// [category] : filtre catégorie (ex: "Programming Languages")
  /// [sortBy]   : "relevance" | "timestamp" | "downloadCount" | "rating"
  Future<MarketplaceSearchResult> search({
    required String query,
    int offset = 0,
    int size = 20,
    String? category,
    String sortBy = 'relevance',
  }) async {
    final uri = Uri.parse('$_baseUrl/api/-/search').replace(queryParameters: {
      'query': query,
      'offset': offset.toString(),
      'size': size.toString(),
      'sortBy': sortBy,
      if (category != null) 'category': category,
    });

    final response = await _http
        .get(uri, headers: _headers)
        .timeout(_timeout);

    _assertOk(response, 'search');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketplaceSearchResult.fromJson(json);
  }

  /// Recherche les extensions les plus téléchargées (page d'accueil marketplace).
  Future<MarketplaceSearchResult> featured({int size = 20}) async {
    return search(query: '', sortBy: 'downloadCount', size: size);
  }

  // ── Métadonnées d'une extension ──────────────────────────────────────────

  /// Récupère les métadonnées de la dernière version d'une extension.
  Future<MarketplaceExtension> getExtension(
      String namespace, String name) async {
    final uri = Uri.parse('$_baseUrl/api/$namespace/$name');
    final response = await _http
        .get(uri, headers: _headers)
        .timeout(_timeout);

    _assertOk(response, 'getExtension $namespace.$name');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketplaceExtension.fromSearchJson(json);
  }

  /// Récupère les métadonnées d'une version spécifique.
  Future<MarketplaceExtension> getExtensionVersion(
      String namespace, String name, String version) async {
    final uri = Uri.parse('$_baseUrl/api/$namespace/$name/linux-arm64/$version');
    http.Response response;
    try {
      response = await _http.get(uri, headers: _headers).timeout(_timeout);
    } catch (_) {
      // Fallback sans platform
      final fallback = Uri.parse('$_baseUrl/api/$namespace/$name/$version');
      response = await _http.get(fallback, headers: _headers).timeout(_timeout);
    }

    _assertOk(response, 'getExtensionVersion $namespace.$name@$version');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketplaceExtension.fromSearchJson(json);
  }

  // ── URL de téléchargement ────────────────────────────────────────────────

  /// Retourne l'URL de téléchargement du .vsix pour une extension.
  /// Préfère la version linux-arm64 si disponible, sinon universal.
  Future<String> getDownloadUrl(
      String namespace, String name, String version) async {
    // Essayer d'abord la variante arm64 (meilleure compatibilité Android)
    final arm64 = Uri.parse(
        '$_baseUrl/api/$namespace/$name/linux-arm64/$version/file/$namespace.$name-$version@linux-arm64.vsix');

    try {
      final r = await _http.head(arm64, headers: _headers).timeout(_timeout);
      if (r.statusCode == 200) return arm64.toString();
    } catch (_) {}

    // Fallback universal
    return '$_baseUrl/api/$namespace/$name/linux-x64/$version/file/$namespace.$name-$version.vsix';
  }

  /// URL simplifiée — construit directement l'URL sans requête HEAD préalable.
  static String quickDownloadUrl(
      String namespace, String name, String version) {
    return '$_baseUrl/api/$namespace/$name/$version/file/$namespace.$name-$version.vsix';
  }

  // ── README ───────────────────────────────────────────────────────────────

  /// Récupère le README.md d'une extension (texte markdown).
  Future<String?> getReadme(
      String namespace, String name, String version) async {
    final uri =
        Uri.parse('$_baseUrl/api/$namespace/$name/$version/file/README.md');
    try {
      final r = await _http.get(uri, headers: _headers).timeout(_timeout);
      if (r.statusCode == 200) return r.body;
    } catch (_) {}
    return null;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'User-Agent': 'PandaIDE/2.3 (Android; arm64)',
  };

  void _assertOk(http.Response r, String ctx) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Open VSX API error [$ctx]: HTTP ${r.statusCode}\n${r.body}');
    }
  }

  void dispose() => _http.close();
}
