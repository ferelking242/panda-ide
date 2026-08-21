import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Real provider logos served from developersdigest.tech/icons.
///
/// The SVGs use `fill="currentColor"`, so they are tinted with the provider's
/// brand color through a ColorMapper. Providers without an official icon in
/// the set fall back to a letter avatar.
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

  static String? urlFor(String providerId) {
    final slug = _slugs[providerId.toLowerCase().trim()];
    if (slug == null) return null;
    return '$base/$slug.svg';
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

  static Color colorFor(String providerId, [Color fallback = const Color(0xff6366f1)]) =>
      brandColors[providerId.toLowerCase().trim()] ?? fallback;
}

class _CurrentColorMapper implements ColorMapper {
  final Color color;
  const _CurrentColorMapper(this.color);

  @override
  Color substitute(String? id, String elementName, AttributeType attributeType, String? attributeValue) {
    if ((attributeValue == 'currentColor' || attributeValue == 'black') &&
        (attributeType == AttributeType.fill || attributeType == AttributeType.stroke)) {
      return color;
    }
    return _fallbackColor(attributeValue);
  }

  static Color _fallbackColor(String? value) {
    if (value == null || value.isEmpty) return const Color(0xff000000);
    final v = value.replaceFirst('#', '');
    if (v.length == 3) {
      return Color(int.parse('ff${v[0]}${v[0]}${v[1]}${v[1]}${v[2]}${v[2]}', radix: 16));
    }
    if (v.length >= 6) {
      return Color(int.parse(v.length == 8 ? v : 'ff$v', radix: 16));
    }
    return const Color(0xff000000);
  }
}

/// Small rounded square with the provider's real logo (network SVG), falling
/// back to a colored letter avatar while loading or when unavailable.
class ProviderLogoBadge extends StatelessWidget {
  final String providerId;
  final double size;

  const ProviderLogoBadge({super.key, required this.providerId, this.size = 26});

  @override
  Widget build(BuildContext context) {
    final brand = AiProviderLogos.colorFor(providerId);
    final url = AiProviderLogos.urlFor(providerId);

    Widget fallback() => Container(
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

    if (url == null) return fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          border: Border.all(color: brand.withValues(alpha: 0.25), width: 0.7),
        ),
        child: SvgPicture.network(
          url,
          width: size * 0.72,
          height: size * 0.72,
          fit: BoxFit.contain,
          colorMapper: _CurrentColorMapper(brand),
          placeholderBuilder: (_) => Center(
            child: SizedBox(
              width: size * 0.4,
              height: size * 0.4,
              child: CircularProgressIndicator(strokeWidth: 1.4, color: brand),
            ),
          ),
        ),
      ),
    );
  }
}
