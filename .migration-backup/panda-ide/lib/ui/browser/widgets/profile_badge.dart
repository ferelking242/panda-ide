import 'package:flutter/material.dart';
import '../models/browser_profile.dart';

/// Badge circulaire coloré affichant l'initiale du profil.
class ProfileBadge extends StatelessWidget {
  final BrowserProfile profile;
  final double size;
  final VoidCallback? onTap;
  final bool showBorder;

  const ProfileBadge({
    super.key,
    required this.profile,
    this.size = 22,
    this.onTap,
    this.showBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final badge = CircleAvatar(
      radius: size / 2,
      backgroundColor: profile.color,
      child: Text(
        profile.initials,
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );

    final widget = showBorder
        ? Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: profile.color.withAlpha(180), width: 2),
            ),
            child: badge,
          )
        : badge;

    if (onTap == null) return widget;
    return GestureDetector(onTap: onTap, child: widget);
  }
}
