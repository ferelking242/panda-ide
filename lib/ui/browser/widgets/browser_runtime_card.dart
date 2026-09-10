import 'package:flutter/material.dart';

import '../models/browser_runtime.dart';
import '../state/browser_runtime_manager.dart';

class BrowserRuntimeCard extends StatefulWidget {
  const BrowserRuntimeCard({super.key});

  @override
  State<BrowserRuntimeCard> createState() => _BrowserRuntimeCardState();
}

class _BrowserRuntimeCardState extends State<BrowserRuntimeCard> {
  BrowserRuntimeManager get _manager => BrowserRuntimeManager.instance;

  @override
  void initState() {
    super.initState();
    _manager.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xff2d2d2d) : Colors.white;
    final borderColor = isDark
        ? const Color(0xff3a3a3a)
        : const Color(0xffdddddd);
    final foreground = isDark ? Colors.grey[200]! : Colors.grey[850]!;
    final secondary = isDark ? Colors.grey[500]! : Colors.grey[600]!;

    return AnimatedBuilder(
      animation: _manager,
      builder: (context, _) {
        final runtime = _manager.snapshot;
        final statusColor = _statusColor(runtime.status);
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.web_asset_outlined, size: 19, color: statusColor),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Runtime navigateur',
                      style: TextStyle(
                        color: foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _StatusPill(text: runtime.statusLabel, color: statusColor),
                ],
              ),
              const SizedBox(height: 10),
              _RuntimeRow(
                label: 'Moteur',
                value: runtime.engineLabel,
                foreground: foreground,
                secondary: secondary,
              ),
              if (runtime.version != null)
                _RuntimeRow(
                  label: 'Version',
                  value: runtime.version!,
                  foreground: foreground,
                  secondary: secondary,
                ),
              if (runtime.installPath != null)
                _RuntimeRow(
                  label: 'Emplacement',
                  value: runtime.installPath!,
                  foreground: foreground,
                  secondary: secondary,
                ),
              if (runtime.message != null) ...[
                const SizedBox(height: 8),
                Text(
                  runtime.message!,
                  style: TextStyle(color: secondary, fontSize: 11.5),
                ),
              ],
              if (runtime.engine == BrowserEngineKind.cef &&
                  runtime.status != BrowserRuntimeStatus.ready) ...[
                const SizedBox(height: 12),
                Text(
                  'Le téléchargement CEF sera activé uniquement lorsqu’un '
                  'paquet signé et vérifiable sera configuré.',
                  style: TextStyle(color: secondary, fontSize: 11.5),
                ),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: runtime.status == BrowserRuntimeStatus.checking
                      ? null
                      : _manager.refresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Vérifier'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _statusColor(BrowserRuntimeStatus status) {
    switch (status) {
      case BrowserRuntimeStatus.ready:
        return Colors.green.shade400;
      case BrowserRuntimeStatus.checking:
        return Colors.amber.shade400;
      case BrowserRuntimeStatus.notInstalled:
      case BrowserRuntimeStatus.corrupted:
        return Colors.orange.shade400;
      case BrowserRuntimeStatus.unsupported:
      case BrowserRuntimeStatus.error:
        return Colors.red.shade400;
    }
  }
}

class _RuntimeRow extends StatelessWidget {
  final String label;
  final String value;
  final Color foreground;
  final Color secondary;

  const _RuntimeRow({
    required this.label,
    required this.value,
    required this.foreground,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(color: secondary, fontSize: 11.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
