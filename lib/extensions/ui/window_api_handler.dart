/// Handlers Flutter pour vscode.window.showMessage / showInputBox / showQuickPick.
import 'package:flutter/material.dart';

library;


enum WindowMessageType { information, warning, error }

class WindowApiHandler {
  // ── showInformationMessage / showWarningMessage / showErrorMessage ─────────
  //
  // params[0] = message (String)
  // params[1..n] = boutons OU { title, isCloseAffordance } OU options object
  //
  // Retourne le titre du bouton cliqué, ou null si fermé sans choix.

  static Future<String?> showMessage(
    BuildContext context,
    WindowMessageType type,
    List<dynamic> params,
  ) async {
    if (!context.mounted) return null;

    final message = params.isNotEmpty ? params[0]?.toString() ?? '' : '';

    // Extraire les boutons (strings ou maps { title, ... })
    final buttons = <String>[];
    for (int i = 1; i < params.length; i++) {
      final p = params[i];
      if (p is String) {
        buttons.add(p);
      } else if (p is Map) {
        final title = p['title'] as String?;
        if (title != null) buttons.add(title);
      }
    }

    final icon = switch (type) {
      WindowMessageType.information => Icons.info_outline,
      WindowMessageType.warning     => Icons.warning_amber_outlined,
      WindowMessageType.error       => Icons.error_outline,
    };

    final color = switch (type) {
      WindowMessageType.information => const Color(0xff5090c8),
      WindowMessageType.warning     => const Color(0xffcca700),
      WindowMessageType.error       => const Color(0xfff14c4c),
    };

    if (buttons.isEmpty) {
      // Pas de boutons → SnackBar simple
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xff2d2d2d),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
      return null;
    }

    // Avec boutons → Dialog
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff252526),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _typeLabel(type),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xffcccccc), fontSize: 13),
        ),
        actions: [
          for (final btn in buttons)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(btn),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xff5090c8),
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: Text(btn),
            ),
        ],
      ),
    );
  }

  static String _typeLabel(WindowMessageType t) => switch (t) {
        WindowMessageType.information => 'Information',
        WindowMessageType.warning     => 'Avertissement',
        WindowMessageType.error       => 'Erreur',
      };

  // ── showInputBox ──────────────────────────────────────────────────────────
  //
  // options keys: prompt, placeHolder, value, password, validateInput,
  //               title, ignoreFocusOut
  //
  // Retourne la valeur saisie, ou null si annulé.

  static Future<String?> showInputBox(
    BuildContext context,
    Map<String, dynamic> options,
  ) async {
    if (!context.mounted) return null;

    final title       = options['title']       as String? ?? options['prompt'] as String? ?? 'Entrée';
    final placeholder = options['placeHolder'] as String? ?? '';
    final initial     = options['value']       as String? ?? '';
    final isPassword  = options['password']    as bool?   ?? false;

    final controller = TextEditingController(text: initial);
    String? errorText;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xff252526),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          title: Text(
            title,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: isPassword,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle:
                      const TextStyle(color: Color(0xff858585), fontSize: 13),
                  errorText: errorText,
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xff5090c8)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xff5090c8), width: 2),
                  ),
                  errorBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xfff14c4c)),
                  ),
                ),
                onChanged: (val) {
                  // validateInput est une fonction JS — on ne peut pas l'appeler ici
                  // Phase 3 : brancher via callFlutter round-trip
                  setState(() => errorText = null);
                },
                onSubmitted: (val) => Navigator.of(ctx).pop(val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xff858585)),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xff5090c8)),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  // ── showQuickPick ─────────────────────────────────────────────────────────
  //
  // items   : List<String> ou List<{ label, description, detail, picked }>
  // options : { placeHolder, canPickMany, matchOnDescription, matchOnDetail, title }
  //
  // Retourne l'item choisi (String ou Map), ou null si annulé.
  // Si canPickMany, retourne une List.

  static Future<dynamic> showQuickPick(
    BuildContext context,
    List<dynamic> items,
    Map<String, dynamic> options,
  ) async {
    if (!context.mounted || items.isEmpty) return null;

    final title       = options['title']       as String? ?? options['placeHolder'] as String? ?? 'Sélection';
    final canPickMany = options['canPickMany'] as bool?   ?? false;

    // Normalise les items en Maps
    final normalized = items.map((item) {
      if (item is String) return {'label': item, 'description': '', 'detail': ''};
      if (item is Map<String, dynamic>) return item;
      return <String, dynamic>{'label': item.toString()};
    }).toList();

    final selected = <int>{};
    final controller = TextEditingController();

    return showDialog<dynamic>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final query = controller.text.toLowerCase();
          final filtered = normalized.asMap().entries.where((e) {
            if (query.isEmpty) return true;
            final item = e.value;
            return (item['label']?.toString().toLowerCase().contains(query) ?? false) ||
                   (item['description']?.toString().toLowerCase().contains(query) ?? false);
          }).toList();

          return Dialog(
            backgroundColor: const Color(0xff252526),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  maxWidth: 480, maxHeight: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Titre
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ),
                  // Barre de recherche
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Filtrer...',
                        hintStyle:
                            TextStyle(color: Color(0xff858585), fontSize: 13),
                        prefixIcon:
                            Icon(Icons.search, color: Color(0xff858585), size: 18),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xff5090c8))),
                        focusedBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: Color(0xff5090c8), width: 2)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Liste
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final entry = filtered[i];
                        final idx   = entry.key;
                        final item  = entry.value;
                        final label = item['label']?.toString() ?? '';
                        final desc  = item['description']?.toString() ?? '';
                        final isSelected = selected.contains(idx);

                        return InkWell(
                          onTap: () {
                            if (canPickMany) {
                              setState(() {
                                if (isSelected) {
                                  selected.remove(idx);
                                } else {
                                  selected.add(idx);
                                }
                              });
                            } else {
                              Navigator.of(ctx).pop(item);
                            }
                          },
                          child: Container(
                            color: isSelected
                                ? const Color(0xff094771)
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                if (canPickMany) ...[
                                  Icon(
                                    isSelected
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    color: const Color(0xff5090c8),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(label,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13)),
                                      if (desc.isNotEmpty)
                                        Text(desc,
                                            style: const TextStyle(
                                                color: Color(0xff858585),
                                                fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Boutons si canPickMany
                  if (canPickMany)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(null),
                            style: TextButton.styleFrom(
                                foregroundColor: const Color(0xff858585)),
                            child: const Text('Annuler'),
                          ),
                          TextButton(
                            onPressed: () {
                              final picked = selected
                                  .map((i) => normalized[i])
                                  .toList();
                              Navigator.of(ctx).pop(picked);
                            },
                            style: TextButton.styleFrom(
                                foregroundColor: const Color(0xff5090c8)),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
