import 'package:flutter/material.dart';
import '../models/browser_tab.dart';
import '../models/browser_profile.dart';
import 'profile_badge.dart';
import 'profile_picker.dart';
import '../state/browser_controller.dart';

/// Un onglet individuel dans la barre d'onglets.
class BrowserTabItem extends StatelessWidget {
  final BrowserTab tab;
  final BrowserProfile profile;
  final bool selected;
  final BrowserController controller;

  const BrowserTabItem({
    super.key,
    required this.tab,
    required this.profile,
    required this.selected,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = selected
        ? (isDark ? const Color(0xff1e1e1e) : Colors.white)
        : (isDark ? const Color(0xff2d2d2d) : const Color(0xffe8e8e8));
    final fg      = isDark ? Colors.grey[300]! : Colors.grey[800]!;
    final sub     = isDark ? Colors.grey[500]! : Colors.grey[500]!;

    return GestureDetector(
      onTap: () => controller.setActiveTab(
        controller.tabs.indexWhere((t) => t.id == tab.id),
      ),
      child: Container(
        constraints: const BoxConstraints(minWidth: 100, maxWidth: 200),
        height: 34,
        decoration: BoxDecoration(
          color: bg,
          border: selected
              ? Border(
                  top: BorderSide(color: profile.color, width: 2),
                  left: BorderSide(color: profile.color.withAlpha(60), width: 0.5),
                  right: BorderSide(color: profile.color.withAlpha(60), width: 0.5),
                )
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Indicateur de chargement ou favicon placeholder
            if (tab.isLoading)
              SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: profile.color,
                ),
              )
            else
              Icon(Icons.public, size: 12, color: sub),

            const SizedBox(width: 5),

            // Titre (tronqué)
            Flexible(
              child: Text(
                tab.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: fg,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),

            const SizedBox(width: 4),

            // Badge profil (tap → changer profil)
            ProfileBadge(
              profile: profile,
              size: 16,
              onTap: () async {
                final picked = await showProfilePicker(
                  context,
                  currentProfileId: tab.profileId,
                );
                if (picked != null && picked.id != tab.profileId) {
                  controller.changeTabProfile(tab.id, picked.id);
                }
              },
            ),

            const SizedBox(width: 3),

            // Croix fermeture
            GestureDetector(
              onTap: () => controller.closeTab(tab.id),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: 13, color: sub),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
