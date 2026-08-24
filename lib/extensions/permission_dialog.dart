/// Dialog de rationale des permissions d'extensions.
///
/// Pattern Google Play : expliquer POURQUOI avant la vraie permission
/// système, avec le nom de l'extension et ce qu'elle veut faire.
library;
import 'package:flutter/material.dart';
import 'extension_permissions.dart';




/// Affiche le dialog de rationale et retourne true si l'utilisateur accepte.
///
/// Usage typique dans l'app :
/// ```dart
/// final result = await ExtensionPermissionManager.instance.request(
///   'dev.panda.device', PandaPermission.clipboard,
///   showRationale: (perm) => showPermissionRationale(context,
///       extensionName: 'Panda Device', permission: perm),
/// );
/// ```
Future<bool> showPermissionRationale(
  BuildContext context, {
  required String extensionName,
  required PandaPermission permission,
}) async {
  final isPhone = permission.scope == PermissionScope.phone;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Icon(
          isPhone ? Icons.phone_android : Icons.extension,
          color: Theme.of(context).colorScheme.primary,
          size: 22,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            isPhone
                ? '$extensionName veut accéder\n${permission.label}'
                : 'Autoriser $extensionName ?',
            style: const TextStyle(fontSize: 17),
          ),
        ),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(permission.rationale),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.shield_outlined, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Permission : ${permission.name}\n'
                  '${isPhone ? "Une boîte de dialogue système Android s\'ouvrira ensuite." : "Portée limitée à l\'environnement Panda."}',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ]),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Refuser'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(isPhone ? 'Continuer' : 'Autoriser'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Helper tout-en-un : demande une permission avec le dialog standard.
Future<PermissionResult> requestPermissionWithDialog(
  BuildContext context, {
  required String extensionId,
  required String extensionName,
  required PandaPermission permission,
}) =>
    ExtensionPermissionManager.instance.request(
      extensionId,
      permission,
      showRationale: (perm) => showPermissionRationale(context,
          extensionName: extensionName, permission: perm),
    );
