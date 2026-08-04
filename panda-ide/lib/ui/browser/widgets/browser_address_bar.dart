import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/browser_controller.dart';
import 'profile_badge.dart';
import 'profile_picker.dart';

/// Barre d'adresse complète : ◀ ▶ ↺ ⌂ [URL] [profil].
class BrowserAddressBar extends StatelessWidget {
  const BrowserAddressBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl   = context.watch<BrowserController>();
    final tab    = ctrl.activeTab;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg     = isDark ? const Color(0xff2d2d2d) : const Color(0xfff3f3f3);
    final inputBg= isDark ? const Color(0xff1e1e1e) : Colors.white;
    final fg     = isDark ? Colors.grey[200]! : Colors.grey[850]!;
    final sub    = isDark ? Colors.grey[500]! : Colors.grey[500]!;
    final border = isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd);
    final accent = const Color(0xff5090c8);

    if (tab == null) return const SizedBox(height: 42);

    final profile   = ctrl.profileForId(tab.profileId);
    final urlCtrl   = ctrl.urlControllers[tab.id] ?? TextEditingController();
    final webCtrl   = ctrl.webControllers[tab.id];

    return Container(
      height: 42,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Row(
        children: [
          // ◀ Précédent
          _NavBtn(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: 'Précédent',
            color: sub,
            onTap: () => webCtrl?.goBack(),
          ),
          const SizedBox(width: 2),

          // ▶ Suivant
          _NavBtn(
            icon: Icons.arrow_forward_ios_rounded,
            tooltip: 'Suivant',
            color: sub,
            onTap: () => webCtrl?.goForward(),
          ),
          const SizedBox(width: 2),

          // ↺ Recharger / ✕ Annuler
          _NavBtn(
            icon: tab.isLoading ? Icons.close : Icons.refresh_rounded,
            tooltip: tab.isLoading ? 'Annuler' : 'Recharger',
            color: sub,
            onTap: tab.isLoading
                ? () => webCtrl?.stopLoading()
                : () => webCtrl?.reload(),
          ),
          const SizedBox(width: 2),

          // ⌂ Accueil
          _NavBtn(
            icon: Icons.home_outlined,
            tooltip: 'Accueil',
            color: sub,
            onTap: () => ctrl.navigateTo(tab.id, ctrl.homeUrl),
          ),
          const SizedBox(width: 6),

          // ─── Barre URL ──────────────────────────────────────────────
          Expanded(
            child: GestureDetector(
              onTap: () {
                urlCtrl.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: urlCtrl.text.length,
                );
              },
              child: Container(
                height: 30,
                decoration: BoxDecoration(
                  color: inputBg,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: border, width: 0.8),
                ),
                child: TextField(
                  controller: urlCtrl,
                  style: TextStyle(fontSize: 12.5, color: fg),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    border:      InputBorder.none,
                    isDense:     true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    hintText:    'Rechercher ou saisir une URL',
                    hintStyle:   TextStyle(fontSize: 12.5, color: sub),
                    // Indicateur HTTPS
                    prefixIcon: tab.url.startsWith('https')
                        ? Icon(Icons.lock_outline, size: 13, color: Colors.green[400])
                        : (tab.url.startsWith('http://')
                            ? Icon(Icons.lock_open_outlined, size: 13, color: Colors.orange[400])
                            : null),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 26, minHeight: 0),
                  ),
                  onSubmitted: (value) => ctrl.navigateTo(tab.id, value),
                  textInputAction: TextInputAction.go,
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Badge profil actif → tap = changer profil
          ProfileBadge(
            profile: profile,
            size: 26,
            showBorder: true,
            onTap: () async {
              final picked = await showProfilePicker(
                context,
                currentProfileId: tab.profileId,
              );
              if (picked != null && picked.id != tab.profileId) {
                ctrl.changeTabProfile(tab.id, picked.id);
              }
            },
          ),

          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _NavBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}
