import 'package:flutter/material.dart';
import '../../core/broken_icons.dart';
import '../../services/android_update_service.dart';
import '../../utils/themes.dart';

/// Full-page update view (check, download, install).
class UpdatePage extends StatelessWidget {
  final AppTheme appTheme;
  const UpdatePage({super.key, required this.appTheme});

  static const Color _kAccent = Color(0xff76b4ea);

  @override
  Widget build(BuildContext context) {
    final isDark = appTheme.isDark;
    final fg     = isDark ? Colors.grey[300]! : Colors.grey[800]!;
    final muted  = isDark ? Colors.grey[600]! : Colors.grey[500]!;
    final bg     = isDark ? const Color(0xff1e1e1e) : Colors.white;
    final cardBg = isDark ? const Color(0xff252526) : const Color(0xfff5f5f5);
    final border = isDark ? const Color(0xff444444) : const Color(0xffcccccc);

    return Container(
      color: bg,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Icon(Broken.document_download, size: 24, color: _kAccent),
              const SizedBox(width: 12),
              Text('Mise à jour',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: fg)),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Version installée',
                    style: TextStyle(
                        fontSize: 12,
                        color: muted,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Panda IDE v$appVersion (build $appBuildNumber)',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: fg)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<AndroidUpdateState>(
            valueListenable: AndroidUpdateService.stateNotifier,
            builder: (context, state, _) {
              if (state.status == 'idle') {
                return _actionButton(
                  icon: Broken.refresh,
                  label: 'Vérifier les mises à jour',
                  color: _kAccent,
                  onTap: () => AndroidUpdateService.checkForUpdate(),
                  isDark: isDark,
                );
              }
              if (state.status == 'available' && state.updateInfo != null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.green.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.check_circle,
                                size: 18, color: Colors.green[400]),
                            const SizedBox(width: 8),
                            Text('Nouvelle version disponible',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green[400])),
                          ]),
                          const SizedBox(height: 8),
                          Text(
                              'v${state.updateInfo!.version} (build ${state.updateInfo!.buildNumber})',
                              style: TextStyle(fontSize: 13, color: fg)),
                          if (state.updateInfo!.notes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(state.updateInfo!.notes,
                                style: TextStyle(fontSize: 12, color: muted)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _actionButton(
                      icon: Broken.document_download,
                      label: 'Installer v${state.updateInfo!.version}',
                      color: Colors.green,
                      onTap: () async {
                        try {
                          await AndroidUpdateService.install(
                              state.updateInfo!);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Erreur: $e')),
                            );
                          }
                        }
                      },
                      isDark: isDark,
                    ),
                  ],
                );
              }
              if (state.status == 'downloading') {
                return Column(
                  children: [
                    Row(children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          value: state.progress > 0 ? state.progress : null,
                          strokeWidth: 3,
                          color: _kAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Téléchargement...',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: fg)),
                          Text(
                              '${(state.progress * 100).toInt()}% ${state.bytesText ?? ''}',
                              style: TextStyle(fontSize: 11, color: muted)),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: state.progress,
                      backgroundColor: border,
                      color: _kAccent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                );
              }
              if (state.status == 'error') {
                return Column(
                  children: [
                    Text('Erreur: ${state.errorMessage ?? "Inconnue"}',
                        style:
                            TextStyle(color: Colors.red[400], fontSize: 13)),
                    const SizedBox(height: 8),
                    _actionButton(
                      icon: Broken.refresh,
                      label: 'Réessayer',
                      color: _kAccent,
                      onTap: () => AndroidUpdateService.checkForUpdate(),
                      isDark: isDark,
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  static Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
