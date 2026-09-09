import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/browser_profile.dart';
import '../state/browser_controller.dart';
import 'profile_badge.dart';

/// Affiche un bottom sheet pour choisir ou créer un profil.
/// Retourne le [BrowserProfile] sélectionné.
Future<BrowserProfile?> showProfilePicker(
  BuildContext context, {
  required String currentProfileId,
}) {
  return showModalBottomSheet<BrowserProfile>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProfilePickerSheet(currentProfileId: currentProfileId),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _ProfilePickerSheet extends StatefulWidget {
  final String currentProfileId;
  const _ProfilePickerSheet({required this.currentProfileId});

  @override
  State<_ProfilePickerSheet> createState() => _ProfilePickerSheetState();
}

class _ProfilePickerSheetState extends State<_ProfilePickerSheet> {
  bool _creating = false;
  final _nameCtrl   = TextEditingController();
  Color _newColor   = kProfileColors[0];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl    = context.watch<BrowserController>();
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = isDark ? const Color(0xff252526) : Colors.white;
    final fg      = isDark ? Colors.white : Colors.black87;
    final sub     = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final accent  = const Color(0xff5090c8);

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: sub.withAlpha(100),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Choisir un profil',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            const SizedBox(height: 12),

            // Liste des profils
            ...ctrl.profiles.map((p) => _ProfileTile(
              profile: p,
              selected: p.id == widget.currentProfileId,
              fg: fg,
              sub: sub,
              onTap: () => Navigator.of(context).pop(p),
            )),

            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Section création
            if (_creating) ...[
              _NewProfileForm(
                nameCtrl: _nameCtrl,
                selectedColor: _newColor,
                fg: fg,
                sub: sub,
                accent: accent,
                onColorChanged: (c) => setState(() => _newColor = c),
                onCancel: () => setState(() {
                  _creating = false;
                  _nameCtrl.clear();
                }),
                onCreate: () async {
                  final name = _nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  await ctrl.createProfile(name: name, color: _newColor);
                  if (mounted) setState(() { _creating = false; _nameCtrl.clear(); });
                },
              ),
            ] else ...[
              TextButton.icon(
                onPressed: () => setState(() => _creating = true),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nouveau profil'),
                style: TextButton.styleFrom(foregroundColor: accent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ProfileTile extends StatelessWidget {
  final BrowserProfile profile;
  final bool selected;
  final Color fg, sub;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.profile,
    required this.selected,
    required this.fg,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      leading: ProfileBadge(profile: profile, size: 28),
      title: Text(
        profile.name,
        style: TextStyle(
          color: fg,
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_circle, color: profile.color, size: 18)
          : null,
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _NewProfileForm extends StatelessWidget {
  final TextEditingController nameCtrl;
  final Color selectedColor;
  final Color fg, sub, accent;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback onCancel;
  final VoidCallback onCreate;

  const _NewProfileForm({
    required this.nameCtrl,
    required this.selectedColor,
    required this.fg,
    required this.sub,
    required this.accent,
    required this.onColorChanged,
    required this.onCancel,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nouveau profil', style: TextStyle(fontSize: 13, color: sub)),
        const SizedBox(height: 8),
        TextField(
          controller: nameCtrl,
          autofocus: true,
          style: TextStyle(color: fg, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Nom du profil',
            hintStyle: TextStyle(color: sub, fontSize: 14),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: accent, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
        const SizedBox(height: 10),
        // Palette couleurs
        Wrap(
          spacing: 8,
          children: kProfileColors.map((c) {
            final selected = c == selectedColor;
            return GestureDetector(
              onTap: () => onColorChanged(c),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(color: Colors.white, width: 2.5)
                      : null,
                  boxShadow: selected
                      ? [BoxShadow(color: c.withAlpha(120), blurRadius: 6)]
                      : null,
                ),
                child: selected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(foregroundColor: sub),
              child: const Text('Annuler'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onCreate,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Créer'),
            ),
          ],
        ),
      ],
    );
  }
}
