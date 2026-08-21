import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

/// Real provider logos served from developersdigest.tech/icons.
///
/// The SVGs use `fill="currentColor"`; we fetch the raw SVG once, replace
/// `currentColor` with the provider's brand color, and render via
/// SvgPicture.string (no dependency on flutter_svg's ColorMapper API).
class AiProviderLogos {
  AiProviderLogos._();

  static const base = 'https://www.developersdigest.tech/icons';

  /// provider id → icon slug on developersdigest.tech
  static const _slugs = <String, String>{
    'openai': 'openai',
    'claude': 'anthropic',
    'gemini': 'gemini',
    'deepseek': 'deepseek',
    'grok': 'xai',
    'mistral': 'mistral',
    'togetherai': 'together',
    'perplexity': 'perplexity',
    'groq': 'groq',
    'cohere': 'cohere',
    'copilot': 'copilot',
    'ollama': 'ollama',
    'lmstudio': 'github',
  };

  /// Cache of providerId → tinted SVG string (null while loading / failed).
  static final Map<String, String?> _cache = {};

  /// Notifié quand un logo vient d'être téléchargé (l'UI se redessine).
  static final ChangeNotifier notifier = ChangeNotifier();

  static String? urlFor(String providerId) {
    final slug = _slugs[providerId.toLowerCase().trim()];
    if (slug == null) return null;
    return '$base/$slug.svg';
  }

  /// Returns the cached tinted SVG, or triggers the fetch and returns null.
  static String? tintedSvgSync(String providerId) {
    final key = providerId.toLowerCase().trim();
    if (_cache.containsKey(key)) return _cache[key];
    final url = urlFor(key);
    if (url == null) {
      _cache[key] = null;
      return null;
    }
    _fetchAndTint(key, url);
    return null;
  }

  static Future<void> _fetchAndTint(String key, String url) async {
    try {
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        _cache[key] = null;
        return;
      }
      var svg = const Utf8Decoder().convert(resp.bodyBytes);
      svg = svg.replaceAll('currentColor', '#000000');
      // Le glyphe est noir sur fond blanc : propre et lisible pour toutes
      // les marques (logos monochromes de developers.digest).
      _cache[key] = svg;
      notifier.notifyListeners();
    } catch (_) {
      _cache[key] = null;
    }
  }

  static const brandColors = <String, Color>{
    'openai': Color(0xff10a37f),
    'claude': Color(0xffd97757),
    'gemini': Color(0xff4285f4),
    'deepseek': Color(0xff4b6ef5),
    'grok': Color(0xff1da1f2),
    'openrouter': Color(0xff8b5cf6),
    'mistral': Color(0xffff7000),
    'togetherai': Color(0xff00c9b1),
    'perplexity': Color(0xff20b2aa),
    'pandagateway': Color(0xff5090c8),
    'copilot': Color(0xff8b5cf6),
    'groq': Color(0xfff97316),
    'fireworks': Color(0xffef4444),
    'cohere': Color(0xff39d353),
    'cerebras': Color(0xffa855f7),
    'novita': Color(0xff06b6d4),
    'hyperbolic': Color(0xffe11d48),
    'custom': Color(0xff888888),
  };

  static Color colorFor(String providerId,
      [Color fallback = const Color(0xff6366f1)]) =>
      brandColors[providerId.toLowerCase().trim()] ?? fallback;
}

/// Small rounded square with the provider's real logo (network SVG), falling
/// back to a colored letter avatar while loading or when unavailable.
class ProviderLogoBadge extends StatelessWidget {
  final String providerId;
  final double size;

  const ProviderLogoBadge({super.key, required this.providerId, this.size = 26});

  Widget _fallback(Color brand) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: brand.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(color: brand.withValues(alpha: 0.25), width: 0.7),
        ),
        alignment: Alignment.center,
        child: Text(
          providerId.isNotEmpty ? providerId[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: size * 0.52,
            fontWeight: FontWeight.w800,
            color: brand,
            height: 1,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AiProviderLogos.notifier,
      builder: (context, _) => _buildInner(context),
    );
  }

  Widget _buildInner(BuildContext context) {
    final brand = AiProviderLogos.colorFor(providerId);
    final svg = AiProviderLogos.tintedSvgSync(providerId);
    if (svg == null) return _fallback(brand);

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.14),
        decoration: BoxDecoration(
          color: Colors.white,
          border:
              Border.all(color: brand.withValues(alpha: 0.25), width: 0.7),
        ),
        child: SvgPicture.string(
          svg,
          width: size * 0.72,
          height: size * 0.72,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
