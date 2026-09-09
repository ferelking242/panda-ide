import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:panda/utils/rootfs_manager.dart';

/// Distro brand colors and metadata.
class _DistroBrand {
  final Color primary;
  final Color border;
  final Color bg;
  final Color accent;
  final String tagline;

  const _DistroBrand({
    required this.primary,
    required this.border,
    required this.bg,
    required this.accent,
    required this.tagline,
  });
}

const Map<TerminalType, _DistroBrand> _brands = {
  TerminalType.ubuntu: _DistroBrand(
    primary: Color(0xFFE95420),
    border: Color(0xFFE95420),
    bg: Color(0xFF1C0E06),
    accent: Color(0xFFFF9D00),
    tagline: 'For everyone',
  ),
  TerminalType.debian: _DistroBrand(
    primary: Color(0xFFD70A53),
    border: Color(0xFFD70A53),
    bg: Color(0xFF1C0610),
    accent: Color(0xFFFC0E33),
    tagline: 'The universal OS',
  ),
  TerminalType.alpine: _DistroBrand(
    primary: Color(0xFF0D597F),
    border: Color(0xFF0D597F),
    bg: Color(0xFF06141C),
    accent: Color(0xFF45A5C4),
    tagline: 'Simple. Secure.',
  ),
  TerminalType.bionic: _DistroBrand(
    primary: Color(0xFF3DDC84),
    border: Color(0xFF3DDC84),
    bg: Color(0xFF061C0E),
    accent: Color(0xFF7BED9F),
    tagline: 'Native Android',
  ),
};

/// Detailed info for each distro's detail page.
class _DistroDetail {
  final String title;
  final String version;
  final String size;
  final String libc;
  final List<String> pros;
  final List<String> cons;
  final String bestFor;
  final String overview;

  const _DistroDetail({
    required this.title,
    required this.version,
    required this.size,
    required this.libc,
    required this.pros,
    required this.cons,
    required this.bestFor,
    required this.overview,
  });
}

const Map<TerminalType, _DistroDetail> _details = {
  TerminalType.ubuntu: _DistroDetail(
    title: 'Ubuntu 24.04 LTS',
    version: 'Noble Numbat',
    size: '~28 MB',
    libc: 'glibc 2.39',
    bestFor: 'Best overall compatibility',
    overview:
        'Ubuntu is the most popular Linux distribution. With glibc natively supported, '
        'almost every prebuilt Linux binary works out of the box. '
        'Supports apt, patchright, playwright, and Chromium seamlessly.',
    pros: [
      'glibc native — 95%+ Linux packages work',
      'apt package manager (widest ecosystem)',
      'LTS support until 2029',
      'patchright, playwright, Chromium work out of the box',
      'Most community tutorials apply directly',
    ],
    cons: [
      'Larger rootfs than Alpine',
      'More disk space for installed packages',
    ],
  ),
  TerminalType.debian: _DistroDetail(
    title: 'Debian Bookworm',
    version: 'Debian 12',
    size: '~103 MB',
    libc: 'glibc 2.36',
    bestFor: 'Maximum stability',
    overview:
        'Debian is the foundation that Ubuntu is built on. '
        'Rock-solid stability with 3+ years of support. '
        'Perfect for server workloads and reliability-critical tasks.',
    pros: [
      'Rock-solid stability (3+ year support)',
      'glibc — full package compatibility',
      'apt package manager',
      'Server-grade reliability',
      'Smaller than full Ubuntu install',
    ],
    cons: [
      'Older package versions than Ubuntu',
      'Slower security patches than Ubuntu',
      'Larger than Alpine rootfs',
    ],
  ),
  TerminalType.alpine: _DistroDetail(
    title: 'Alpine Linux',
    version: 'Alpine 3.22',
    size: '~4 MB',
    libc: 'musl libc',
    bestFor: 'Minimal footprint',
    overview:
        'Alpine Linux is an ultra-lightweight distribution using musl instead of glibc. '
        'Incredibly small at just 4 MB, but many prebuilt Linux binaries require '
        'glibc and won\'t work directly.',
    pros: [
      'Tiny rootfs (4 MB!)',
      'Fastest to download',
      'Low memory usage',
      'Good for lightweight tools',
    ],
    cons: [
      'musl libc — many glibc packages fail',
      'patchright/playwright won\'t work',
      'Limited compatibility with prebuilt binaries',
      'Requires workarounds for some tools',
    ],
  ),
  TerminalType.bionic: _DistroDetail(
    title: 'Android Bionic',
    version: 'Native',
    size: '0 MB',
    libc: 'Bionic libc',
    bestFor: 'Native Android tools only',
    overview:
        'Bionic is Android\'s built-in C library. No download needed, '
        'but only Android-native tools are available. '
        'Most standard Linux software will not run.',
    pros: [
      'No download needed',
      'Zero setup time',
      'Native Android tools available',
    ],
    cons: [
      'Very limited Linux tools',
      'No apt/apk package manager',
      'No standard Linux environment',
      'Most Linux software won\'t run',
    ],
  ),
};

/// Terminal Selection Screen
///
/// Flow: Splash -> Permissions -> THIS -> Download -> Terminal
/// Default: Ubuntu (best glibc compatibility).
class TerminalChoiceScreen extends StatefulWidget {
  final Function(TerminalType) onTerminalSelected;
  final bool isFromSettings;

  const TerminalChoiceScreen({
    super.key,
    required this.onTerminalSelected,
    this.isFromSettings = false,
  });

  @override
  State<TerminalChoiceScreen> createState() => _TerminalChoiceScreenState();
}

class _TerminalChoiceScreenState extends State<TerminalChoiceScreen>
    with SingleTickerProviderStateMixin {
  TerminalType _selectedType = TerminalType.ubuntu;
  final Map<TerminalType, bool> _installed = {};
  bool _isInstalling = false;
  TerminalType? _installingType;
  double _installProgress = 0;
  String _installStatus = '';
  String _installError = '';
  bool _showErrorDetail = false;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _loadStatus();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final current = await RootfsManager.getActiveTerminal();
    final statuses = <TerminalType, bool>{};
    for (final t in TerminalType.values) {
      statuses[t] = await RootfsManager.isInstalled(t);
    }
    if (mounted) {
      setState(() {
        _selectedType = current;
        _installed.addAll(statuses);
      });
    }
  }

  Future<void> _selectAndInstall(TerminalType type) async {
    if (_isInstalling) return;

    setState(() {
      _isInstalling = true;
      _installingType = type;
      _installProgress = 0;
      _installStatus = 'Preparing download...';
      _installError = '';
      _showErrorDetail = false;
    });

    try {
      final success = await RootfsManager.install(
        type,
        onProgress: (progress, downloaded, total) {
          if (!mounted) return;
          setState(() {
            _installProgress = progress;
            _installStatus = 'Downloading ${type.displayName}... '
                '${(progress * 100).toStringAsFixed(0)}% '
                '(${RootfsManager.formatSize(downloaded)}/${RootfsManager.formatSize(total)})';
          });
        },
      );

      if (!mounted) return;

      if (success) {
        await RootfsManager.setActiveTerminal(type);
        setState(() {
          _installed[type] = true;
          _isInstalling = false;
          _installingType = null;
          _selectedType = type;
        });
        widget.onTerminalSelected(type);
      } else {
        setState(() {
          _isInstalling = false;
          _installingType = null;
          _installStatus = 'Installation failed';
          _installError = 'Rootfs extraction or validation failed.\n'
              'Possible causes:\n'
              '- Network error during download\n'
              '- Insufficient storage space\n'
              '- Corrupted rootfs archive\n\n'
              'Try switching to a different terminal or retrying.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInstalling = false;
          _installingType = null;
          _installStatus = 'Error: $e';
          _installError = 'Exception: $e\n\nStack trace and details:\n'
              'Terminal: ${type.displayName}\n'
              'URL: ${RootfsManager.manifest[type]?.url ?? "unknown"}\n'
              'Expected size: ${RootfsManager.formatSize(RootfsManager.manifest[type]?.sizeBytes ?? 0)}\n\n'
              'Please copy this log and share it for support.';
        });
      }
    }
  }

  Future<void> _deleteTerminal(TerminalType type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Remove ${type.displayName}?'),
        content: const Text(
            'The rootfs will be deleted. You can re-download it later from Settings.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await RootfsManager.delete(type);
      await _loadStatus();
    }
  }

  void _openDetail(TerminalType type) {
    final brand = _brands[type]!;
    final detail = _details[type]!;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DistroDetailPage(
          type: type,
          brand: brand,
          detail: detail,
          isInstalled: _installed[type] ?? false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Text(
                'Choose Your Terminal',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Select the Linux environment for your terminal.\n'
                'Rootfs is downloaded on first use.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // Terminal cards
              Expanded(
                child: ListView.builder(
                  itemCount: TerminalType.values.length,
                  itemBuilder: (context, index) {
                    final t = TerminalType.values[index];
                    final brand = _brands[t]!;
                    return _DistroCard(
                      type: t,
                      brand: brand,
                      isSelected: _selectedType == t,
                      isInstalled: _installed[t] ?? false,
                      isInstallingThis: _isInstalling && _installingType == t,
                      isDefault: t == TerminalType.ubuntu,
                      pulse: _pulse,
                      onSelect: _isInstalling
                          ? null
                          : () => setState(() => _selectedType = t),
                      onDetail: () => _openDetail(t),
                      onDelete: (_installed[t] == true && !_isInstalling)
                          ? () => _deleteTerminal(t)
                          : null,
                    );
                  },
                ),
              ),

              // Progress bar
              if (_isInstalling) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _installProgress,
                    backgroundColor: const Color(0xFF1A1A1A),
                    color: _brands[_installingType]?.primary ?? Colors.white,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(_installStatus,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
              ],

              // Error with chevron
              if (_installStatus.isNotEmpty &&
                  !_isInstalling &&
                  _installError.isNotEmpty) ...[
                const SizedBox(height: 8),
                _ErrorPanel(
                  status: _installStatus,
                  error: _installError,
                  isExpanded: _showErrorDetail,
                  onToggleExpand: () =>
                      setState(() => _showErrorDetail = !_showErrorDetail),
                  onCopy: () {
                    Clipboard.setData(ClipboardData(text: _installError));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Error log copied'),
                        backgroundColor: Color(0xFF1A3A55),
                      ),
                    );
                  },
                ),
              ],

              const SizedBox(height: 14),

              // Action button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _isInstalling
                      ? null
                      : () => _selectAndInstall(_selectedType),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        _brands[_selectedType]?.primary ?? Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isInstalling
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(
                          _installed[_selectedType] == true
                              ? (widget.isFromSettings
                                  ? 'Switch Terminal'
                                  : 'Continue')
                              : 'Download & Continue',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Error panel ────────────────────────────────────────────────────
class _ErrorPanel extends StatelessWidget {
  final String status;
  final String error;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onCopy;

  const _ErrorPanel({
    required this.status,
    required this.error,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggleExpand,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2D1520),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: const Color(0xFFCF6679).withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline,
                    color: Color(0xFFCF6679), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: const TextStyle(
                        color: Color(0xFFCF6679),
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.white54,
                  size: 20,
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onCopy,
                  child: const Icon(Icons.copy,
                      color: Colors.white38, size: 16),
                ),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: 10),
              Text(
                error,
                style: const TextStyle(
                  color: Color(0xFFCF6679),
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Distro Card ────────────────────────────────────────────────────
class _DistroCard extends StatelessWidget {
  final TerminalType type;
  final _DistroBrand brand;
  final bool isSelected;
  final bool isInstalled;
  final bool isInstallingThis;
  final bool isDefault;
  final AnimationController pulse;
  final VoidCallback? onSelect;
  final VoidCallback? onDetail;
  final VoidCallback? onDelete;

  const _DistroCard({
    required this.type,
    required this.brand,
    required this.isSelected,
    required this.isInstalled,
    required this.isInstallingThis,
    required this.isDefault,
    required this.pulse,
    this.onSelect,
    this.onDetail,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final detail = _details[type]!;

    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? brand.bg : const Color(0xFF141414),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? brand.border : const Color(0xFF2A2A2A),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Real distro logo
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: brand.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: brand.primary.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: DistroLogo(type: type, size: 28),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        detail.title,
                        style: TextStyle(
                          color: isSelected ? brand.primary : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: brand.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Recommended',
                            style: TextStyle(
                                fontSize: 9,
                                color: brand.primary,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                      if (isInstalled) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Installed',
                              style:
                                  TextStyle(fontSize: 9, color: Colors.green)),
                        ),
                      ],
                      if (isInstallingThis) ...[
                        const SizedBox(width: 6),
                        SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: brand.primary)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        '${detail.size}  ${detail.libc}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                      ),
                      const Spacer(),
                      // Detail chevron
                      GestureDetector(
                        onTap: onDetail,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Details',
                              style: TextStyle(
                                  color: brand.primary.withValues(alpha: 0.7),
                                  fontSize: 11),
                            ),
                            Icon(Icons.chevron_right,
                                size: 16,
                                color: brand.primary.withValues(alpha: 0.7)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Selection / delete
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.red.withValues(alpha: 0.6),
                onPressed: onDelete,
                tooltip: 'Remove',
              )
            else
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color:
                    isSelected ? brand.primary : const Color(0xFF3A3A3A),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Real Distro Logos (CustomPainter) ──────────────────────────────
/// Public widget so detail page can use it too.
class DistroLogo extends StatelessWidget {
  final TerminalType type;
  final double size;

  const DistroLogo({super.key, required this.type, required this.size});

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case TerminalType.ubuntu:
        return CustomPaint(size: Size(size, size), painter: const UbuntuLogoPainter());
      case TerminalType.debian:
        return CustomPaint(size: Size(size, size), painter: const DebianLogoPainter());
      case TerminalType.alpine:
        return CustomPaint(size: Size(size, size), painter: const AlpineLogoPainter());
      case TerminalType.bionic:
        return CustomPaint(size: Size(size, size), painter: const AndroidLogoPainter());
    }
  }
}

/// Ubuntu "Circle of Friends" logo (simplified vector).
class UbuntuLogoPainter extends CustomPainter {
  const UbuntuLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.42;

    // Outer circle
    final circlePaint = Paint()
      ..color = const Color(0xFFE95420)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(cx, cy), r, circlePaint);

    // Inner filled circle
    final innerPaint = Paint()
      ..color = const Color(0xFFE95420)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r * 0.18, innerPaint);

    // Three dots (the "friends")
    final dotPaint = Paint()
      ..color = const Color(0xFFE95420)
      ..style = PaintingStyle.fill;
    final dotR = r * 0.13;
    final dist = r * 0.72;

    for (int i = 0; i < 3; i++) {
      final angle = (i * 2 * math.pi / 3) - math.pi / 2;
      final dx = cx + dist * math.cos(angle);
      final dy = cy + dist * math.sin(angle);
      canvas.drawCircle(Offset(dx, dy), dotR, dotPaint);
    }

    // Gap lines in the circle (3 segments)
    final gapPaint = Paint()
      ..color = const Color(0xFF0A0A0A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 3; i++) {
      final angle = (i * 2 * math.pi / 3) - math.pi / 2;
      final x1 = cx + r * 0.45 * math.cos(angle);
      final y1 = cy + r * 0.45 * math.sin(angle);
      final x2 = cx + r * 1.15 * math.cos(angle);
      final y2 = cy + r * 1.15 * math.sin(angle);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), gapPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Debian swirl logo (simplified vector).
class DebianLogoPainter extends CustomPainter {
  const DebianLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.40;

    // Outer circle (the "swirl")
    final swirlPaint = Paint()
      ..color = const Color(0xFFD70A53)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round;

    // Draw arc
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    canvas.drawArc(rect, -math.pi * 0.3, math.pi * 1.6, false, swirlPaint);

    // Inner circle
    final innerPaint = Paint()
      ..color = const Color(0xFFD70A53)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r * 0.22, innerPaint);

    // Small swirl at top
    final headPaint = Paint()
      ..color = const Color(0xFFD70A53)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(cx + r * 0.68, cy - r * 0.68), r * 0.10, headPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Alpine triangle/mountain logo (simplified vector).
class AlpineLogoPainter extends CustomPainter {
  const AlpineLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.width * 0.40;

    final paint = Paint()
      ..color = const Color(0xFF0D597F)
      ..style = PaintingStyle.fill;

    // Mountain triangle
    final path = Path()
      ..moveTo(cx, cy - s * 0.85)
      ..lineTo(cx - s * 0.85, cy + s * 0.65)
      ..lineTo(cx + s * 0.85, cy + s * 0.65)
      ..close();
    canvas.drawPath(path, paint);

    // Snow cap (small white triangle)
    final capPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final capPath = Path()
      ..moveTo(cx, cy - s * 0.85)
      ..lineTo(cx - s * 0.22, cy - s * 0.35)
      ..lineTo(cx + s * 0.22, cy - s * 0.35)
      ..close();
    canvas.drawPath(capPath, capPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Android robot logo (simplified vector).
class AndroidLogoPainter extends CustomPainter {
  const AndroidLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.width * 0.38;

    final paint = Paint()
      ..color = const Color(0xFF3DDC84)
      ..style = PaintingStyle.fill;

    // Body (rounded rect)
    final bodyPath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, cy + s * 0.15),
            width: s * 1.3,
            height: s * 1.1),
        Radius.circular(s * 0.18),
      ));
    canvas.drawPath(bodyPath, paint);

    // Head (half circle)
    final headPaint = Paint()
      ..color = const Color(0xFF3DDC84)
      ..style = PaintingStyle.fill;
    final headRect = Rect.fromCenter(
      center: Offset(cx, cy - s * 0.45),
      width: s * 1.3,
      height: s * 0.9,
    );
    canvas.drawArc(headRect, math.pi, math.pi, false, headPaint);

    // Eyes
    final eyePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - s * 0.28, cy - s * 0.52), s * 0.09, eyePaint);
    canvas.drawCircle(Offset(cx + s * 0.28, cy - s * 0.52), s * 0.09, eyePaint);

    // Antennae
    final antPaint = Paint()
      ..color = const Color(0xFF3DDC84)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.03
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(cx - s * 0.28, cy - s * 0.88),
        Offset(cx - s * 0.40, cy - s * 1.08),
        antPaint);
    canvas.drawLine(
        Offset(cx + s * 0.28, cy - s * 0.88),
        Offset(cx + s * 0.40, cy - s * 1.08),
        antPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Detail Page ────────────────────────────────────────────────────
class _DistroDetailPage extends StatelessWidget {
  final TerminalType type;
  final _DistroBrand brand;
  final _DistroDetail detail;
  final bool isInstalled;

  const _DistroDetailPage({
    required this.type,
    required this.brand,
    required this.detail,
    required this.isInstalled,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: CustomScrollView(
        slivers: [
          // SliverAppBar with logo
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: brand.bg,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: brand.bg,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 30),
                    // Logo in gradient circle
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            brand.primary.withValues(alpha: 0.25),
                            brand.primary.withValues(alpha: 0.05),
                          ],
                        ),
                        border: Border.all(
                            color: brand.primary.withValues(alpha: 0.4), width: 2),
                      ),
                      child: Center(
                        child: DistroLogo(type: type, size: 44),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      detail.title,
                      style: TextStyle(
                        color: brand.primary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail.version,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    // Chips
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _InfoChip(
                            label: 'Size', value: detail.size, brand: brand),
                        const SizedBox(width: 10),
                        _InfoChip(
                            label: 'Libc', value: detail.libc, brand: brand),
                        const SizedBox(width: 10),
                        _InfoChip(
                            label: 'Status',
                            value: isInstalled ? 'Installed' : 'Available',
                            brand: brand),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overview
                  Text(
                    'OVERVIEW',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    detail.overview,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Best for
                  Text(
                    'BEST FOR',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: brand.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: brand.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.star, color: brand.primary, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            detail.bestFor,
                            style: TextStyle(
                              color: brand.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Advantages
                  Text(
                    'ADVANTAGES',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  ...detail.pros.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle,
                                color: Colors.green.withValues(alpha: 0.7),
                                size: 16),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(p,
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      fontSize: 13,
                                      height: 1.4)),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 24),

                  // Limitations
                  Text(
                    'LIMITATIONS',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  ...detail.cons.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber,
                                color: Colors.orange.withValues(alpha: 0.7),
                                size: 16),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(c,
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      fontSize: 13,
                                      height: 1.4)),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small info chip for detail page.
class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final _DistroBrand brand;

  const _InfoChip(
      {required this.label, required this.value, required this.brand});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: brand.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: brand.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: brand.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
