import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import '../../bloc/repo_bloc/repo_bloc.dart';
import '../../core/broken_icons.dart';
import '../../core/workspace/panda_workspace.dart';
import '../../utils/themes.dart';
import '../../utils/languages.dart';
import '../panda_surface.dart';
import '../menu_screen.dart';
import '../github_page.dart';
import '../package_manager_page.dart';
import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../bloc/repo_bloc/repo_bloc.dart';

/// VS Code-style welcome page: Hero, Start section, Recent projects, Walkthroughs.
class PandaWelcomePage extends StatelessWidget {
  final AppTheme appTheme;
  final AppThemeState appThemeState;
  final void Function(File file, String rootDir) onOpenFile;
  final void Function(String rootDir) onOpenProject;
  final void Function(BuildContext ctx) onNewFile;
  final void Function(BuildContext ctx) onOpenFileAction;
  final void Function(BuildContext ctx) onOpenFolder;
  final void Function(BuildContext ctx) onCloneRepo;
  final VoidCallback onOpenGithubTab;

  const PandaWelcomePage({
    super.key,
    required this.appTheme,
    required this.appThemeState,
    required this.onOpenFile,
    required this.onOpenProject,
    required this.onNewFile,
    required this.onOpenFileAction,
    required this.onOpenFolder,
    required this.onCloneRepo,
    required this.onOpenGithubTab,
  });

  static const Color _kAccent = Color(0xff76b4ea);

  @override
  Widget build(BuildContext context) {
    final isDark = appTheme.isDark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final hPad = isNarrow ? 16.0 : 40.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 32, hPad, 48),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Hero ──────────────────────────────────────────
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Broken.code_circle,
                          color: _kAccent, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Text('Panda IDE',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w300,
                            color: appTheme.selectScreenCardTextColor)),
                  ]),
                  const SizedBox(height: 32),

                  // ── Start section ─────────────────────────────────
                  _sectionHeader('Démarrer', isDark),
                  const SizedBox(height: 10),
                  _StartItem(
                    icon: Broken.document_text,
                    label: 'Nouveau fichier…',
                    isDark: isDark,
                    onTap: () => onNewFile(context),
                  ),
                  _StartItem(
                    icon: Broken.document_upload,
                    label: 'Ouvrir un fichier…',
                    isDark: isDark,
                    onTap: () => onOpenFileAction(context),
                  ),
                  _StartItem(
                    icon: Broken.folder_open,
                    label: 'Ouvrir un dossier…',
                    isDark: isDark,
                    onTap: () => onOpenFolder(context),
                  ),
                  _StartItem(
                    icon: Broken.programming_arrows,
                    label: 'Cloner un référentiel…',
                    isDark: isDark,
                    onTap: () => onCloneRepo(context),
                  ),
                  BlocBuilder<GithubAuthCubit, GithubAuthState>(
                    builder: (_, authState) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StartItem(
                          svgAsset:
                              'assets/icons/code-branch-solid.svg',
                          label: 'GitHub — Ouvrir un référentiel…',
                          isDark: isDark,
                          onTap: onOpenGithubTab,
                        ),
                        if (authState.isSignedIn)
                          _StartItem(
                            icon: Broken.add_circle,
                            label: 'Créer un dépôt GitHub…',
                            isDark: isDark,
                            onTap: onOpenGithubTab,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Recent section ────────────────────────────────
                  _sectionHeader('Récent', isDark),
                  const SizedBox(height: 10),
                  BlocBuilder<RecentBloc, RecentState>(
                    builder: (context, recentState) {
                      final recentData = recentState.recent
                          .whereType<Map<String, dynamic>>()
                          .toList();

                      if (recentData.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            "Vous n'avez pas encore de fichiers récents.",
                            style: TextStyle(
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[600],
                                fontSize: 13),
                          ),
                        );
                      }

                      return Column(
                        children: recentData.take(10).map((entry) {
                          final entryPath = entry['path'] as String;
                          final rootDir =
                              entry['rootDir'] as String;
                          final isProject =
                              entry['type'] == 'project';
                          final exists = isProject
                              ? Directory(entryPath).existsSync()
                              : File(entryPath).existsSync();

                          Widget leading;
                          if (isProject) {
                            leading = const Icon(Broken.folder_open,
                                color: _kAccent, size: 18);
                          } else {
                            final matchingLang = languages.where((l) =>
                                l.extension.contains(p
                                    .extension(entryPath)
                                    .toLowerCase()
                                    .replaceFirst('.', ''))).toList();
                            leading = matchingLang.isNotEmpty
                                ? matchingLang[0].icon ??
                                    const Icon(Broken.document, size: 18)
                                : const Icon(Broken.document,
                                    color: Colors.grey, size: 18);
                          }

                          return _RecentItem(
                            leading: leading,
                            title: exists
                                ? p.basename(entryPath)
                                : '${p.basename(entryPath)} — introuvable',
                            subtitle: rootDir,
                            isDark: isDark,
                            faded: !exists,
                            onTap: () {
                              if (!exists) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(
                                      '${isProject ? 'Project' : 'File'} not found'),
                                  backgroundColor: Colors.orange,
                                ));
                                return;
                              }
                              if (isProject) {
                                onOpenProject(entryPath);
                                return;
                              }
                              final matchingLang = languages
                                  .where((l) => l.extension.contains(
                                      p
                                          .extension(entryPath)
                                          .toLowerCase()
                                          .replaceFirst('.', '')))
                                  .toList();
                              onOpenFile(
                                File(entryPath),
                                rootDir,
                              );
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 28),

                  // ── Walkthroughs ──────────────────────────────────
                  _sectionHeader('Procédures pas à pas', isDark),
                  const SizedBox(height: 10),
                  _WalkthroughCard(
                    icon: Broken.flash_circle,
                    title: 'Démarrer avec Panda IDE',
                    subtitle:
                        'Configurez votre éditeur, téléchargez les runtimes et commencez à coder.',
                    isDark: isDark,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                MarketplacePage())),
                  ),
                  const SizedBox(height: 10),
                  _WalkthroughCard(
                    icon: Broken.programming_arrows,
                    title: 'Cloner depuis GitHub',
                    subtitle:
                        'Connectez votre compte GitHub et gérez vos dépôts directement.',
                    isDark: isDark,
                    onTap: onOpenGithubTab,
                  ),
                  const SizedBox(height: 10),
                  _WalkthroughCard(
                    icon: Broken.cpu,
                    title: 'Parcourir les modèles',
                    subtitle:
                        "Créez un projet à partir d'un modèle prêt à l'emploi.",
                    isDark: isDark,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const MenuScreen())),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _sectionHeader(String title, bool isDark) => Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: isDark ? Colors.grey[500] : Colors.grey[600],
        ),
      );
}

// ── Start item ────────────────────────────────────────────────────────────────
class _StartItem extends StatefulWidget {
  final IconData? icon;
  final String? svgAsset;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _StartItem({
    this.icon,
    this.svgAsset,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_StartItem> createState() => _StartItemState();
}

class _StartItemState extends State<_StartItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.isDark ? const Color(0xff76b4ea) : const Color(0xff146bb7);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration:
              PandaSurface.welcomeItem(widget.isDark, hovered: _hovered),
          child: Row(children: [
            SizedBox(
              width: 22,
              child: widget.svgAsset != null
                  ? SvgPicture.asset(
                      widget.svgAsset!,
                      height: 18,
                      width: 18,
                      colorFilter:
                          ColorFilter.mode(accent, BlendMode.srcIn),
                    )
                  : Icon(widget.icon!, color: accent, size: 18),
            ),
            const SizedBox(width: 10),
            Text(widget.label,
                style: TextStyle(
                    color: accent,
                    fontSize: 14,
                    fontWeight: widget.isDark
                        ? FontWeight.w300
                        : FontWeight.w400)),
          ]),
        ),
      ),
    );
  }
}

// ── Recent item ───────────────────────────────────────────────────────────────
class _RecentItem extends StatefulWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final bool isDark;
  final bool faded;
  final VoidCallback onTap;

  const _RecentItem({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.faded,
    required this.onTap,
  });

  @override
  State<_RecentItem> createState() => _RecentItemState();
}

class _RecentItemState extends State<_RecentItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration:
              PandaSurface.recentRow(widget.isDark, hovered: _hovered),
          child: Row(children: [
            widget.leading,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: TextStyle(
                          fontSize: 13,
                          color: widget.faded
                              ? Colors.grey
                              : (widget.isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[800]))),
                  Text(widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: widget.isDark
                              ? Colors.grey[600]
                              : Colors.grey[500])),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Walkthrough card ──────────────────────────────────────────────────────────
class _WalkthroughCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  const _WalkthroughCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_WalkthroughCard> createState() => _WalkthroughCardState();
}

class _WalkthroughCardState extends State<_WalkthroughCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark
        ? (_hovered ? const Color(0xff2a2d2e) : const Color(0xff252526))
        : (_hovered ? const Color(0xffe8eaed) : const Color(0xfff3f3f3));
    final border =
        widget.isDark ? const Color(0xff3c3c3c) : const Color(0xffdddddd);
    const Color _kAccent = Color(0xff76b4ea);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]
                : [],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(widget.icon, color: _kAccent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: widget.isDark
                              ? Colors.grey[200]
                              : Colors.grey[800])),
                  const SizedBox(height: 3),
                  Text(widget.subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: widget.isDark
                              ? Colors.grey[500]
                              : Colors.grey[600])),
                ],
              ),
            ),
            Icon(Broken.arrow_right_2,
                size: 16,
                color: widget.isDark
                    ? Colors.grey[600]
                    : Colors.grey[400]),
          ]),
        ),
      ),
    );
  }
}
