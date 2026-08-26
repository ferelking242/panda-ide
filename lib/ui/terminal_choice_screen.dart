import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:panda/utils/rootfs_manager.dart';

/// Distro brand colors and metadata.
class _DistroBrand {
  final Color primary;
  final Color border;
  final Color bg;
  final IconData icon;
  final String assetLogo;

  const _DistroBrand({
    required this.primary,
    required this.border,
    required this.bg,
    required this.icon,
    required this.assetLogo,
  });
}

const Map<TerminalType, _DistroBrand> _brands = {
  TerminalType.ubuntu: _DistroBrand(
    primary: Color(0xFFE95420), // Ubuntu orange
    border: Color(0xFFE95420),
    bg: Color(0xFF2D1A0E),
    icon: Icons.memory,
    assetLogo: 'ubuntu',
  ),
  TerminalType.debian: _DistroBrand(
    primary: Color(0xFFA80030), // Debian red
    border: Color(0xFFA80030),
    bg: Color(0xFF2D0A14),
    icon: Icons.terminal,
    assetLogo: 'debian',
  ),
  TerminalType.alpine: _DistroBrand(
    primary: Color(0xFF0D597F), // Alpine blue
    border: Color(0xFF0D597F),
    bg: Color(0xFF0A1E2D),
    icon: Icons.terrain,
    assetLogo: 'alpine',
  ),
  TerminalType.bionic: _DistroBrand(
    primary: Color(0xFF3DDC84), // Android green
    border: Color(0xFF3DDC84),
    bg: Color(0xFF0D2818),
    icon: Icons.phone_android,
    assetLogo: 'bionic',
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

  const _DistroDetail({
    required this.title,
    required this.version,
    required this.size,
    required this.libc,
    required this.pros,
    required this.cons,
    required this.bestFor,
  });
}

const Map<TerminalType, _DistroDetail> _details = {
  TerminalType.ubuntu: _DistroDetail(
    title: 'Ubuntu 24.04 LTS',
    version: 'Noble Numbat',
    size: '~28 MB',
    libc: 'glibc 2.39',
    bestFor: 'Best overall compatibility',
    pros: [
      'glibc native — 95%+ Linux packages work',
      'apt package manager (widest ecosystem)',
      'LTS support until 2029',
      'patchright, playwright, Chromium work',
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
    pros: [
      'Rock-solid stability (3 year support)',
      'glibc — full package compatibility',
      'apt package manager',
      'Smaller than full Ubuntu',
      'Server-grade reliability',
    ],
    cons: [
      'Older package versions',
      'Slower security patches than Ubuntu',
    ],
  ),
  TerminalType.alpine: _DistroDetail(
    title: 'Alpine Linux',
    version: 'Alpine 3.22',
    size: '~4 MB',
    libc: 'musl libc',
    bestFor: 'Minimal footprint',
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _DistroDetailPage(
        type: type,
        brand: brand,
        detail: detail,
        isInstalled: _installed[type] ?? false,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
                'Select the Linux environment for your terminal.\nRootfs is downloaded on first use.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
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
                    color: _brands[_installingType]?.primary ?? cs.primary,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(_installStatus,
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
              ],

              // Error with chevron
              if (_installStatus.isNotEmpty && !_isInstalling && _installError.isNotEmpty) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => setState(() => _showErrorDetail = !_showErrorDetail),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D1520),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFCF6679).withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.error_outline, color: Color(0xFFCF6679), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _installStatus,
                                style: const TextStyle(
                                    color: Color(0xFFCF6679),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            Icon(
                              _showErrorDetail
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: Colors.white54,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: _installError));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Error log copied'),
                                    backgroundColor: Color(0xFF1A3A55),
                                  ),
                                );
                              },
                              child: const Icon(Icons.copy, color: Colors.white38, size: 16),
                            ),
                          ],
                        ),
                        if (_showErrorDetail) ...[
                          const SizedBox(height: 10),
                          Text(
                            _installError,
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
                ),
              ],

              const SizedBox(height: 14),

              // Action button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed:
                      _isInstalling ? null : () => _selectAndInstall(_selectedType),
                  style: FilledButton.styleFrom(
                    backgroundColor: _brands[_selectedType]?.primary ?? cs.primary,
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
                              ? (widget.isFromSettings ? 'Switch Terminal' : 'Continue')
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

/// Distro selection card with colored border and brand styling.
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
        child: Column(
          children: [
            Row(
              children: [
                // Distro icon circle
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: brand.primary.withOpacity(0.15),
                    border: Border.all(
                      color: brand.primary.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: _DistroLogo(type: type, size: 24),
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
                                color: brand.primary.withOpacity(0.15),
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
                                color: Colors.green.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Installed',
                                  style: TextStyle(
                                      fontSize: 9, color: Colors.green)),
                            ),
                          ],
                          if (isInstallingThis) ...[
                            const SizedBox(width: 6),
                            SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: brand.primary)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            '${detail.size} · ${detail.libc}',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 11),
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
                                      color: brand.primary.withOpacity(0.7),
                                      fontSize: 11),
                                ),
                                Icon(Icons.chevron_right,
                                    size: 16,
                                    color: brand.primary.withOpacity(0.7)),
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
                    color: Colors.red.withOpacity(0.6),
                    onPressed: onDelete,
                    tooltip: 'Remove',
                  )
                else
                  Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: isSelected ? brand.primary : const Color(0xFF3A3A3A),
                    size: 22,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// SVG-free distro logo using styled text + icons.
class _DistroLogo extends StatelessWidget {
  final TerminalType type;
  final double size;

  const _DistroLogo({required this.type, required this.size});

  @override
  Widget build(BuildContext context) {
    final brand = _brands[type]!;
    switch (type) {
      case TerminalType.ubuntu:
        return Text(
          'U',
          style: TextStyle(
            color: brand.primary,
            fontSize: size,
            fontWeight: FontWeight.w900,
          ),
        );
      case TerminalType.debian:
        return Icon(Icons.terminal, color: brand.primary, size: size * 0.8);
      case TerminalType.alpine:
        return Icon(Icons.terrain, color: brand.primary, size: size * 0.8);
      case TerminalType.bionic:
        return Icon(Icons.phone_android, color: brand.primary, size: size * 0.8);
    }
  }
}

/// Detail page for a distro.
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
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(detail.title,
            style: TextStyle(
                color: brand.primary,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero header
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: brand.primary.withOpacity(0.15),
                  border: Border.all(
                      color: brand.primary.withOpacity(0.4), width: 2),
                ),
                child: Center(
                  child: _DistroLogo(type: type, size: 40),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                detail.title,
                style: TextStyle(
                  color: brand.primary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Center(
              child: Text(
                detail.version,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 14),
              ),
            ),
            const SizedBox(height: 24),

            // Info chips
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _InfoChip(label: 'Size', value: detail.size, brand: brand),
                const SizedBox(width: 12),
                _InfoChip(label: 'Libc', value: detail.libc, brand: brand),
                const SizedBox(width: 12),
                _InfoChip(
                    label: 'Status',
                    value: isInstalled ? 'Installed' : 'Not installed',
                    brand: brand),
              ],
            ),
            const SizedBox(height: 28),

            // Best for
            Text(
              'BEST FOR',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1),
            ),
            const SizedBox(height: 6),
            Text(
              detail.bestFor,
              style: TextStyle(
                color: brand.primary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),

            // Advantages
            Text(
              'ADVANTAGES',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            ...detail.pros.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle,
                          color: Colors.green.withOpacity(0.7), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(p,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                                height: 1.3)),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 20),

            // Limitations
            Text(
              'LIMITATIONS',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            ...detail.cons.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber,
                          color: Colors.orange.withOpacity(0.7), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(c,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                                height: 1.3)),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 32),
          ],
        ),
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
        border: Border.all(color: brand.border.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
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
