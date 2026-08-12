import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenVSXItem {
  final String namespace;
  final String name;
  final String version;
  final String displayName;
  final String description;
  final String downloadUrl;

  OpenVSXItem({
    required this.namespace,
    required this.name,
    required this.version,
    required this.displayName,
    required this.description,
    required this.downloadUrl,
  });

  factory OpenVSXItem.fromJson(Map<String, dynamic> json) {
    final files = json['files'] as Map<String, dynamic>? ?? {};
    return OpenVSXItem(
      namespace: json['namespace'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      displayName: json['displayName'] as String? ?? json['name'] as String? ?? 'Extension',
      description: json['description'] as String? ?? '',
      downloadUrl: files['download'] as String? ?? '',
    );
  }
}

class OpenVSXMarketplace {
  static const String baseUrl = 'https://open-vsx.org/api';

  static Future<List<OpenVSXItem>> searchExtensions(String query) async {
    try {
      final url = Uri.parse('$baseUrl/-/search?q=${Uri.encodeComponent(query)}&size=20');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final extensions = data['extensions'] as List<dynamic>? ?? [];
        return extensions.map((e) => OpenVSXItem.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<OpenVSXItem?> getExtensionDetails(String namespace, String name) async {
    try {
      final url = Uri.parse('$baseUrl/$namespace/$name');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return OpenVSXItem.fromJson(data);
      }
    } catch (_) {}
    return null;
  }
}
