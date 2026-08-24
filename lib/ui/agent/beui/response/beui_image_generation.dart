import 'package:flutter/material.dart';
import '../beui_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// BeUIImageGeneration — carte de génération d'image avec transitions.
///
///   • queued    : shimmer placeholder rectangulaire
///   • generating: blur progressif + barre indéterminée
///   • done      : image fade-in avec layout stable
/// ═══════════════════════════════════════════════════════════════════════════

enum BeUIImageStatus { queued, generating, done }

class BeUIImageGeneration extends StatelessWidget {
  final BeUIImageStatus status;
  final String? imageUrl;
  final String? label;
  final double width;
  final double height;
  final bool isDark;
  final VoidCallback? onSave;

  const BeUIImageGeneration({
    super.key,
    required this.status,
    this.imageUrl,
    this.label,
    this.width = 260,
    this.height = 260,
    this.isDark = true,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height + (label != null ? 28 : 0),
      decoration: BoxDecoration(
        color: BeUIColors.deepSurfaceOf(isDark),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BeUIColors.borderOf(isDark), width: 0.5),
      ),
      child: Column(
        children: [
          // ── Image area (stable size) ────────────────────────
          SizedBox(
            width: width,
            height: height,
            child: _buildContent(),
          ),

          // ── Label / Save ────────────────────────────────────
          if (label != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: BeUIColors.accentOf(isDark).withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  if (status == BeUIImageStatus.done && onSave != null)
                    GestureDetector(
                      onTap: onSave,
                      child: Icon(Icons.download, size: 14, color: BeUIColors.accentOf(isDark)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (status) {
      case BeUIImageStatus.queued:
        return _ShimmerPlaceholder(isDark: isDark);
      case BeUIImageStatus.generating:
        return _GeneratingOverlay(isDark: isDark);
      case BeUIImageStatus.done:
        return _DoneImage(imageUrl: imageUrl, isDark: isDark);
    }
  }
}

// ── Queued: shimmer placeholder ───────────────────────────────────────────

class _ShimmerPlaceholder extends StatelessWidget {
  final bool isDark;
  const _ShimmerPlaceholder({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return BeUIShimmer(
      baseColor: BeUIColors.deepSurfaceOf(isDark),
      highlightColor: BeUIColors.borderOf(isDark),
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: BeUIColors.deepSurfaceOf(isDark),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

// ── Generating: blur pulse + progress ──────────────────────────────────────

class _GeneratingOverlay extends StatefulWidget {
  final bool isDark;
  const _GeneratingOverlay({required this.isDark});

  @override
  State<_GeneratingOverlay> createState() => _GeneratingOverlayState();
}

class _GeneratingOverlayState extends State<_GeneratingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blurCtrl;

  @override
  void initState() {
    super.initState();
    _blurCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blurCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Blurred gradient background
        AnimatedBuilder(
          animation: _blurCtrl,
          builder: (context, _) {
            final t = _blurCtrl.value;
            return Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: RadialGradient(
                  center: Alignment(0.2 + t * 0.3, 0.3 - t * 0.2),
                  colors: [
                    BeUIColors.accentOf(widget.isDark).withValues(alpha: 0.25),
                    BeUIColors.deepSurfaceOf(widget.isDark),
                  ],
                ),
              ),
            );
          },
        ),
        // Progress indicator
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: BeUIColors.accentOf(widget.isDark),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Génération…',
              style: TextStyle(
                fontSize: 11,
                color: BeUIColors.accentOf(widget.isDark).withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Done: fade-in image ───────────────────────────────────────────────────

class _DoneImage extends StatelessWidget {
  final String? imageUrl;
  final bool isDark;
  const _DoneImage({this.imageUrl, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: BeUIColors.deepSurfaceOf(isDark),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(
            Icons.image_outlined,
            size: 40,
            color: BeUIColors.accentOf(isDark).withValues(alpha: 0.3),
          ),
        ),
      );
    }

    return FadeInImage(
      placeholder: const AssetImage('assets/icons/app-icon.png'),
      image: NetworkImage(imageUrl!),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: BeUIDurations.medium,
      fadeOutDuration: BeUIDurations.fast,
      imageErrorBuilder: (_, __, ___) => Container(
        decoration: BoxDecoration(
          color: BeUIColors.deepSurfaceOf(isDark),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(Icons.broken_image, size: 40, color: BeUIColors.error),
        ),
      ),
    );
  }
}
