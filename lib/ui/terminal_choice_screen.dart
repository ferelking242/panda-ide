import 'package:flutter/material.dart';
import 'package:panda/utils/rootfs_manager.dart';

/// Terminal Selection Screen
///
/// Flow: Splash -> Permissions -> THIS -> Download -> Terminal
/// Default: Debian. None bundled. Download on first use.
/// Also accessible from Settings to switch terminals.
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
  TerminalType _selectedType = TerminalType.debian;
  final Map<TerminalType, bool> _installed = {};
  bool _isInstalling = false;
  TerminalType? _installingType;
  double _installProgress = 0;
  String _installStatus = '';
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
          _installStatus = 'Installation failed. Please try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInstalling = false;
          _installingType = null;
          _installStatus = 'Error: $e';
        });
      }
    }
  }

  Future<void> _deleteTerminal(TerminalType type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${type.displayName}?'),
        content: Text(
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                widget.isFromSettings ? 'Change Terminal' : 'Choose Your Terminal',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select the Linux environment for your terminal.\n'
                'Rootfs is downloaded on first use (~4 MB Alpine, ~90 MB Debian).',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              // Terminal cards
              Expanded(
                child: ListView(
                  children: TerminalType.values
                      .map((t) => _TerminalCard(
                            type: t,
                            isSelected: _selectedType == t,
                            isInstalled: _installed[t] ?? false,
                            isInstallingThis: _isInstalling && _installingType == t,
                            pulse: _pulse,
                            onSelect: _isInstalling ? null : () => setState(() => _selectedType = t),
                            onDelete: (_installed[t] == true && !_isInstalling)
                                ? () => _deleteTerminal(t)
                                : null,
                          ))
                      .toList(),
                ),
              ),

              // Progress
              if (_isInstalling) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _installProgress,
                  backgroundColor: cs.surfaceVariant,
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Text(_installStatus,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],

              // Error
              if (_installStatus.isNotEmpty &&
                  !_isInstalling &&
                  _installStatus.startsWith('Error'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_installStatus, style: TextStyle(color: cs.error, fontSize: 13)),
                ),

              const SizedBox(height: 16),

              // Action button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _isInstalling ? null : () => _selectAndInstall(_selectedType),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
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

/// Animated terminal selection card.
class _TerminalCard extends StatelessWidget {
  final TerminalType type;
  final bool isSelected;
  final bool isInstalled;
  final bool isInstallingThis;
  final AnimationController pulse;
  final VoidCallback? onSelect;
  final VoidCallback? onDelete;

  const _TerminalCard({
    required this.type,
    required this.isSelected,
    required this.isInstalled,
    required this.isInstallingThis,
    required this.pulse,
    this.onSelect,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = type == TerminalType.debian
        ? Icons.terminal
        : type == TerminalType.alpine
            ? Icons.terrain
            : Icons.phone_android;

    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary.withOpacity(0.08) : cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outline.withOpacity(0.15),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: pulse,
              builder: (_, __) => Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected ? cs.primary.withOpacity(0.15) : cs.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    size: 22,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(type.displayName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600)),
                    if (isInstalled) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Installed',
                            style: TextStyle(fontSize: 10, color: Colors.green)),
                      ),
                    ],
                    if (type == TerminalType.debian) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Default',
                            style: TextStyle(
                                fontSize: 10,
                                color: cs.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                    if (isInstallingThis) ...[
                      const SizedBox(width: 6),
                      const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Text(type.description,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant, height: 1.3)),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.red.withOpacity(0.7),
                onPressed: onDelete,
                tooltip: 'Remove',
              )
            else
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? cs.primary : cs.outline,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}
