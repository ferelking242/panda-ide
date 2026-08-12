import 'package:flutter/material.dart';

class SlashCommandItem {
  final String command;
  final String description;
  final String prompt;

  const SlashCommandItem({
    required this.command,
    required this.description,
    required this.prompt,
  });
}

class MentionItem {
  final String key;
  final String label;
  final IconData icon;

  const MentionItem({
    required this.key,
    required this.label,
    required this.icon,
  });
}

const List<SlashCommandItem> kPandaSlashCommands = [
  SlashCommandItem(
    command: '/fix',
    description: 'Corriger les erreurs LSP dans le fichier actif',
    prompt: 'Corrige toutes les erreurs et avertissements dans le fichier actif.',
  ),
  SlashCommandItem(
    command: '/explain',
    description: 'Expliquer le code du fichier actif',
    prompt: 'Explique en détail le rôle et le fonctionnement du fichier actif.',
  ),
  SlashCommandItem(
    command: '/tests',
    description: 'Générer des tests unitaires',
    prompt: 'Génère des tests unitaires complets pour le fichier actif.',
  ),
  SlashCommandItem(
    command: '/commit',
    description: 'Générer un message de commit git',
    prompt: 'Analyse le diff git actuel et génère un message de commit clair.',
  ),
  SlashCommandItem(
    command: '/review',
    description: 'Effectuer une revue de code',
    prompt: 'Fais une revue de code approfondie sur les modifications courantes.',
  ),
];

const List<MentionItem> kPandaMentions = [
  MentionItem(key: '@file', label: 'Insérer le contenu d\'un fichier', icon: Icons.insert_drive_file),
  MentionItem(key: '@folder', label: 'Insérer l\'arborescence d\'un dossier', icon: Icons.folder),
  MentionItem(key: '@problems', label: 'Insérer les diagnostics de compilation / LSP', icon: Icons.bug_report),
  MentionItem(key: '@git', label: 'Insérer le statut/diff git courant', icon: Icons.merge_type),
  MentionItem(key: '@terminal', label: 'Insérer la sortie récente du terminal', icon: Icons.terminal),
];

class AgentSlashMentionsOverlay extends StatelessWidget {
  final String query;
  final Function(String selected) onSelected;

  const AgentSlashMentionsOverlay({
    super.key,
    required this.query,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isSlash = query.startsWith('/');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xff222230) : Colors.white;

    if (isSlash) {
      final matches = kPandaSlashCommands
          .where((cmd) => cmd.command.toLowerCase().contains(query.toLowerCase()))
          .toList();

      if (matches.isEmpty) return const SizedBox.shrink();

      return Card(
        elevation: 6,
        color: bg,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 180),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final cmd = matches[index];
              return ListTile(
                dense: true,
                title: Text(cmd.command, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueAccent)),
                subtitle: Text(cmd.description, style: const TextStyle(fontSize: 11)),
                onTap: () => onSelected(cmd.prompt),
              );
            },
          ),
        ),
      );
    } else if (query.startsWith('@')) {
      final matches = kPandaMentions
          .where((m) => m.key.toLowerCase().contains(query.toLowerCase()))
          .toList();

      if (matches.isEmpty) return const SizedBox.shrink();

      return Card(
        elevation: 6,
        color: bg,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 180),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final item = matches[index];
              return ListTile(
                dense: true,
                leading: Icon(item.icon, size: 16, color: Colors.orangeAccent),
                title: Text(item.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(item.label, style: const TextStyle(fontSize: 11)),
                onTap: () => onSelected('${item.key} '),
              );
            },
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
