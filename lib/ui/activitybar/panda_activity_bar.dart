import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../core/broken_icons.dart';
import '../../services/android_update_service.dart';
import '../../ui/home_models.dart';
import '../../utils/themes.dart';
import '../../bloc/repo_bloc/repo_bloc.dart';
import '../widgets/panda_theme_switch.dart';

/// VS Code-style activity bar: sidebar icons on left, bottom section
/// with theme toggle, GitHub avatar, and settings.
class PandaActivityBar extends StatelessWidget {
  final AppTheme appTheme;
  final int sidebarState;
  final int activeRail;
  final void Function(int idx) onTapItem;
  final void Function() onOpenAgentTab;
  final void Function() onOpenGithubTab;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenMarketplace;
  final VoidCallback onOpenGateway;
  final VoidCallback onOpenBrowser;
  final VoidCallback onOpenCopilot;

  const PandaActivityBar({
    super.key,
    required this.appTheme,
    required this.sidebarState,
    required this.activeRail,
    required this.onTapItem,
    required this.onOpenAgentTab,
    required this.onOpenGithubTab,
    required this.onOpenSettings,
    required this.onOpenMarketplace,
    required this.onOpenGateway,
    required this.onOpenBrowser,
    required this.onOpenCopilot,
  });

  static const Color _kAccent = Color(0xff76b4ea);
  static const Color _kActivityBgDark = Color(0xff252526);
  static const Color _kActivityBgLight = Color(0xff2c2c2c);
  static const Color _kActivityIconDark = Color(0xff858585);
  static const Color _kActivityIconLight = Color(0xff6e6e6e);
  static const Color _kActivitySelDark = Color(0xffcacaca);
  static const Color _kActivitySelLight = Color(0xff424242);

  @override
  Widget build(BuildContext context) {
    final isDark = appTheme.isDark;
    final railBg = isDark ? _kActivityBgDark : _kActivityBgLight;
    final iconColor = isDark ? _kActivityIconDark : _kActivityIconLight;
    final selColor = isDark ? _kActivitySelDark : _kActivitySelLight;

    final topItems = <RailItem>[
      RailItem(icon: Broken.element_3, label: 'Explorateur', idx: 1),
      RailItem(icon: Broken.search_normal, label: 'Rechercher', idx: 2),
      RailItem(
          icon: Broken.programming_arrows, label: 'Contrôle Git', idx: 3),
      RailItem(
          icon: Broken.play_circle, label: 'Exécuter / Debug', idx: 4),
      RailItem(icon: Icons.device_hub, label: 'Tunnel', idx: 5),
      RailItem(icon: Broken.shop, label: 'Marketplace', idx: 6),
      RailItem(icon: Icons.psychology, label: 'Panda Agent', idx: 10),
      RailItem(icon: Broken.cpu, label: 'Gateway AI', idx: 7),
      RailItem(icon: Broken.global, label: 'Navigateur', idx: 8),
      RailItem(
          icon: Broken.message_programming,
          label: 'GitHub Copilot',
          idx: 9),
    ];

    return Container(
      width: 48,
      color: railBg,
      child: Column(
        children: [
          const SizedBox(height: 6),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: topItems
                    .map((item) => _ActivityBtnEx(
                          item: item,
                          selected:
                              sidebarState == 2 && activeRail == item.idx,
                          iconColor: iconColor,
                          selColor: selColor,
                          onTap: () {
                            if (item.idx == 6) {
                              onOpenMarketplace();
                              return;
                            }
                            if (item.idx == 7) {
                              onOpenGateway();
                              return;
                            }
                            if (item.idx == 8) {
                              onOpenBrowser();
                              return;
                            }
                            if (item.idx == 9) {
                              onOpenCopilot();
                              return;
                            }
                            if (item.idx == 10) {
                              onOpenAgentTab();
                              return;
                            }
                            onTapItem(item.idx);
                          },
                        ))
                    .toList(),
              ),
            ),
          ),
          const Spacer(),
          const SizedBox(height: 6),

          // ── Bottom: Theme toggle ─────────────────────────────────
          BlocBuilder<AppThemeBloc, AppThemeState>(
            builder: (context, state) => Builder(
              builder: (btnCtx) => _ActivityBtnEx(
                item: RailItem(
                    icon: state.appTheme.isDark
                        ? Broken.sun_1
                        : Broken.moon,
                    label: state.appTheme.isDark
                        ? 'Thème clair'
                        : 'Thème sombre',
                    idx: 98),
                selected: false,
                iconColor: iconColor,
                selColor: selColor,
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  final cur = prefs.getString('savedAppTheme');
                  if (!btnCtx.mounted) return;
                  final bool toLight = cur == 'dark';
                  await ThemeSwitchScope.propagateFrom(
                    context: btnCtx,
                    apply: () {
                      btnCtx.read<AppThemeBloc>().add(AppThemeEvent(
                          appTheme:
                              toLight ? LightTheme() : DarkTheme()));
                    },
                  );
                  await prefs.setString(
                      'savedAppTheme', toLight ? 'light' : 'dark');
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Bottom: GitHub avatar ────────────────────────────────
          Tooltip(
            message: 'Compte GitHub',
            child: _GithubAvatarEx(
              iconColor: iconColor,
              onTap: onOpenGithubTab,
            ),
          ),
          const SizedBox(height: 12),

          // ── Bottom: Settings ─────────────────────────────────────
          _ActivityBtnEx(
            item: RailItem(
                icon: Broken.setting_3, label: 'Parametres', idx: 99),
            selected: false,
            iconColor: iconColor,
            selColor: selColor,
            onTap: onOpenSettings,
          ),
          const SizedBox(height: 12),

          // ── Bottom: Auto-update widget ───────────────────────────
          _buildUpdateProgress(iconColor),
        ],
      ),
    );
  }

  Widget _buildUpdateProgress(Color iconColor) {
    return ValueListenableBuilder<AndroidUpdateState>(
      valueListenable: AndroidUpdateService.stateNotifier,
      builder: (context, updateState, _) {
        if (updateState.status == 'idle') return const SizedBox.shrink();

        final isDownloading = updateState.status == 'downloading';
        final isAvailable = updateState.status == 'available';
        final isInstalling = updateState.status == 'installing';
        final isError = updateState.status == 'error';
        final percent = (updateState.progress * 100).toInt();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Tooltip(
            message: isDownloading
                ? 'Téléchargement maj ($percent%)\n${updateState.bytesText ?? ''}'
                : isAvailable
                    ? 'Mise à jour v${updateState.updateInfo?.version} disponible !'
                    : isInstalling
                        ? 'Installation de la mise à jour...'
                        : 'Mise à jour (Erreur)',
            child: InkWell(
              onTap: () async {
                if (isAvailable && updateState.updateInfo != null) {
                  try {
                    await AndroidUpdateService.install(
                        updateState.updateInfo!);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('Mise à jour échouée : $e')),
                      );
                    }
                  }
                } else if (isError) {
                  AndroidUpdateService.checkForUpdate();
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 38,
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                decoration: BoxDecoration(
                  color: isDownloading
                      ? Colors.blue.withOpacity(0.2)
                      : isAvailable
                          ? Colors.green.withOpacity(0.2)
                          : isError
                              ? Colors.red.withOpacity(0.2)
                              : Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDownloading
                        ? Colors.blue
                        : isAvailable
                            ? Colors.green
                            : isError
                                ? Colors.red
                                : Colors.grey,
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDownloading)
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              value: updateState.progress > 0
                                  ? updateState.progress
                                  : null,
                              strokeWidth: 2,
                              color: Colors.blue[400],
                            ),
                          ),
                          Text(
                            '$percent%',
                            style: const TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue),
                          ),
                        ],
                      )
                    else if (isInstalling)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.amber),
                      )
                    else
                      Icon(
                        isAvailable
                            ? Broken.document_download
                            : Broken.refresh,
                        size: 16,
                        color: isAvailable
                            ? Colors.green[400]
                            : Colors.red[400],
                      ),
                    const SizedBox(height: 2),
                    Text(
                      isDownloading
                          ? '$percent%'
                          : isAvailable
                              ? 'v${updateState.updateInfo?.version ?? 'NEW'}'
                              : isInstalling
                                  ? 'INST'
                                  : 'ERR',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: isDownloading
                            ? Colors.blue
                            : isAvailable
                                ? Colors.green[400]
                                : isError
                                    ? Colors.red[400]
                                    : iconColor,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Activity button widget ────────────────────────────────────────────────────
class _ActivityBtnEx extends StatelessWidget {
  final RailItem item;
  final bool selected;
  final Color iconColor;
  final Color selColor;
  final VoidCallback onTap;
  const _ActivityBtnEx({
    required this.item,
    required this.selected,
    required this.iconColor,
    required this.selColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item.label,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        hoverColor: selColor.withValues(alpha: 0.06),
        splashColor: selColor.withValues(alpha: 0.10),
        child: SizedBox(
          width: 48,
          height: 44,
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: 0,
                top: selected ? 8 : 22,
                bottom: selected ? 8 : 22,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: selected ? 1 : 0,
                  child: Container(
                    width: 2.5,
                    decoration: BoxDecoration(
                      color: selColor,
                      borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(2)),
                    ),
                  ),
                ),
              ),
              Center(
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 160),
                  scale: selected ? 1.06 : 1.0,
                  child: Icon(item.icon,
                      size: 21,
                      color: selected ? selColor : iconColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── GitHub avatar widget ──────────────────────────────────────────────────────
class _GithubAvatarEx extends StatelessWidget {
  final Color iconColor;
  final VoidCallback onTap;
  const _GithubAvatarEx({required this.iconColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GithubAuthCubit, GithubAuthState>(
      builder: (_, state) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: ClipOval(
              child: state.isSignedIn && state.user != null
                  ? Image.network(state.user!.avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Icon(Broken.profile_circle,
                              color: iconColor, size: 22))
                  : Icon(Broken.profile_circle,
                      color: iconColor, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}
