import 'package:flutter/material.dart';

/// Palette prédéfinie pour les couleurs de profil.
const kProfileColors = [
  Color(0xFFE53935), // Rouge
  Color(0xFF1E88E5), // Bleu
  Color(0xFF43A047), // Vert
  Color(0xFFFF8F00), // Ambre
  Color(0xFF8E24AA), // Violet
  Color(0xFF00ACC1), // Cyan
  Color(0xFFFF5722), // Orange foncé
  Color(0xFF3949AB), // Indigo
  Color(0xFF00897B), // Teal
  Color(0xFF6D4C41), // Marron
];

/// Moteurs de recherche prédéfinis (label → url template avec %s).
const kSearchEngines = {
  'Google': 'https://www.google.com/search?q=%s',
  'Bing': 'https://www.bing.com/search?q=%s',
  'DuckDuckGo': 'https://duckduckgo.com/?q=%s',
  'Brave': 'https://search.brave.com/search?q=%s',
  'Qwant': 'https://www.qwant.com/?q=%s',
};

class BrowserProfile {
  final String id;
  final String name;
  final Color color;

  /// null = UA par défaut de flutter_inappwebview.
  final String? userAgent;

  /// URL template avec %s pour la requête (ex. Google).
  final String searchEngine;

  const BrowserProfile({
    required this.id,
    required this.name,
    required this.color,
    this.userAgent,
    this.searchEngine = 'https://www.google.com/search?q=%s',
  });

  /// Identifiant unique pour l'isolation native des données WebView.
  /// Utilisé via [InAppWebViewSettings.dataDirectoryIdentifier].
  String get dataDirectoryIdentifier => 'panda_browser_$id';

  /// Initiale du profil (pour le badge).
  String get initials =>
      name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

  // ── Serialization ──────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        // ignore: deprecated_member_use
        'color': color.value,
        'userAgent': userAgent,
        'searchEngine': searchEngine,
      };

  factory BrowserProfile.fromJson(Map<String, dynamic> json) => BrowserProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        color: Color(json['color'] as int),
        userAgent: json['userAgent'] as String?,
        searchEngine: (json['searchEngine'] as String?) ??
            'https://www.google.com/search?q=%s',
      );

  BrowserProfile copyWith({
    String? name,
    Color? color,
    Object? userAgent = _sentinel,
    String? searchEngine,
  }) =>
      BrowserProfile(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        userAgent: userAgent == _sentinel ? this.userAgent : userAgent as String?,
        searchEngine: searchEngine ?? this.searchEngine,
      );
}

const _sentinel = Object();
