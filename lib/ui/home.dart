import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:panda/bloc/repo_bloc/repo_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/broken_icons.dart';
import '../ui/panda_surface.dart';
import 'about.dart';
import 'donation_page.dart';
import 'file_manager.dart';
import 'editor_page.dart';
import 'menu_screen.dart';
import 'project_screen.dart';
import 'downloads.dart';
import 'settings.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../terminal/terminal.dart';
import '../ui/contribute.dart';
import '../ui/github_page.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/languages.dart';
import '../utils/themes.dart';
import 'widgets.dart';

// ── VSCode colour tokens ──────────────────────────────────────────────────────
const _kActivityBg     = Color(0xff333333);
const _kActivityIcon   = Color(0xff858585);
const _kActivitySel    = Color(0xffffffff);
const _kTabBarDark     = Color(0xff252526);
const _kTabBarLight    = Color(0xffececec);
const _kTabActiveDark  = Color(0xff1e1e1e);
const _kTabActiveLight = Color(0xffffffff);
const _kAccent         = Color(0xff5090c8);
const _kSidebarBgDark  = Color(0xff252526);
const _kSidebarBgLight = Color(0xfff3f3f3);
const _kSidebarWidth   = 240.0;
const _kSectionTitle   = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.2,
);

// ─────────────────────────────────────────────────────────────────────────────
class SelectType extends StatefulWidget {
  const SelectType({super.key});
  @override
  State<SelectType> createState() => _SelectTypeState();
}

class _SelectTypeState extends State<SelectType> with WidgetsBindingObserver {
  // ── State ──────────────────────────────────────────────────────────────────
  final _scaffoldKey         = GlobalKey<ScaffoldState>();
  final createFileController = TextEditingController();
  final _createFileKey       = GlobalKey<FormState>();
  final _cloneRepoKey        = GlobalKey<FormState>();
  AnimationStatus _terminalSelectionStatus = AnimationStatus.dismissed;
  bool _didShowPackageUpdateToast  = false;
  bool _didShowStorageMigrationToast = false;
  bool _checkingPendingSharedFile  = false;
  int  _pendingSharedFileRetryCount = 0;

  // Active activity-bar item (0 = none/welcome)
  int _activeRail = 0;
  // Whether the sidebar panel is expanded (shows the 240px content area)
  bool _sidebarPanelOpen = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openPendingSharedFile();
      _maybeShowStorageMigrationNotice();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_openPendingSharedFile());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    createFileController.dispose();
    super.dispose();
  }

  // ── Pending shared file ────────────────────────────────────────────────────
  Future<void> _openPendingSharedFile() async {
    if (_checkingPendingSharedFile) return;
    _checkingPendingSharedFile = true;
    try {
      final pendingFiles = await NativeChannel.consumePendingOpenFiles();
      if (!mounted) return;
      if (pendingFiles.isEmpty) {
        if (_pendingSharedFileRetryCount < 30) {
          _pendingSharedFileRetryCount++;
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) unawaited(_openPendingSharedFile());
          });
        } else {
          _pendingSharedFileRetryCount = 0;
        }
        return;
      }
      _pendingSharedFileRetryCount = 0;
      final imported = File(pendingFiles.first);
      if (!imported.existsSync()) return;
      final language = languages.firstWhere(
        (item) => item.extension.contains(
            path.extension(imported.path).replaceFirst('.', '')),
        orElse: () => languages[0],
      );
      if (!mounted) return;
      Navigator.of(context).push(PageRouteBuilder(
        pageBuilder: (_, __, ___) => EditorPage(
          languageDetails: language,
          rootDir: imported.parent.path,
          file: imported,
          isProject: false,
        ),
        transitionsBuilder: (_, a, __, child) =>
            SizeTransition(sizeFactor: a, child: child),
      ));
    } finally {
      _checkingPendingSharedFile = false;
    }
  }

  // ── Storage migration notice ───────────────────────────────────────────────
  Future<void> _maybeShowStorageMigrationNotice() async {
    if (_didShowStorageMigrationToast) return;
    _didShowStorageMigrationToast = true;
    final prefs = await SharedPreferences.getInstance();
    final shouldShow = prefs.getBool(sharedStorageMigrationNoticeKey) ?? false;
    if (!mounted || !shouldShow) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Projects, Files and Templates now live in shared storage.'),
      duration: Duration(seconds: 4),
    ));
    await prefs.setBool(sharedStorageMigrationNoticeKey, false);
  }

  // ── Recent entry normaliser ────────────────────────────────────────────────
  Map<String, dynamic>? _normalizeRecentEntry(dynamic rawEntry) {
    if (rawEntry is Map &&
        rawEntry['type'] is String &&
        rawEntry['path'] is String) {
      return {
        'type': rawEntry['type'],
        'path': rawEntry['path'],
        'rootDir': rawEntry['rootDir'] ?? rawEntry['path'],
      };
    }
    if (rawEntry is Map && rawEntry.length == 1) {
      final dynamic key = rawEntry.keys.first;
      if (key is String) {
        return {'type': 'file', 'path': key, 'rootDir': rawEntry[key]};
      }
    }
    return null;
  }

  // ── Clone ──────────────────────────────────────────────────────────────────
  Future<void> _performClone(
    String projectDir,
    String repoUrl,
    String repoName,
    BuildContext context,
    StreamController<double> progressController,
  ) async {
    final targetDir = Directory('$projectDir/$repoName');
    if (targetDir.existsSync()) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Directory "$repoName" already exists'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ));
        await Future.delayed(const Duration(milliseconds: 500));
        if (context.mounted) {
          Navigator.of(context).push(PageRouteBuilder(
            pageBuilder: (_, __, ___) => EditorPage(
              rootDir: targetDir.path,
              isCloned: true,
              isProject: true,
              languageDetails: null,
            ),
            transitionsBuilder: (_, a, __, child) =>
                SizeTransition(sizeFactor: a, child: child),
          ));
        }
      }
      return;
    }
    try {
      await cloneRepo(
        projectDir,
        repoUrl,
        (p) => progressController.add(p),
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(PageRouteBuilder(
          pageBuilder: (_, __, ___) => EditorPage(
            rootDir: targetDir.path,
            isCloned: true,
            isProject: true,
            languageDetails: null,
          ),
          transitionsBuilder: (_, a, __, child) =>
              SizeTransition(sizeFactor: a, child: child),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Clone failed'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK')),
            ],
          ),
        );
      }
    } finally {
      if (mounted) progressController.close();
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  void _doNewFile(BuildContext context, AppTheme appTheme) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(24),
          decoration: _dialogBox(appTheme.isDark),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogHeader(appTheme, Broken.document_text, 'Create a new file'),
              const SizedBox(height: 24),
              Form(
                key: _createFileKey,
                child: TextFormField(
                  style: TextStyle(color: appTheme.selectScreenCardTextColor),
                  cursorColor: _kAccent,
                  controller: createFileController,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter a filename' : null,
                  decoration: InputDecoration(
                    hintText: 'filename.dart',
                    hintStyle: const TextStyle(color: Colors.grey),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xff3c3c3c)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kAccent),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _cancelBtn(ctx),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: _primaryBtn(),
                    onPressed: () async {
                      if (!_createFileKey.currentState!.validate()) return;
                      final file = await createFile(
                          createFileController.text, filesDir, context);
                      if (file != null && context.mounted) {
                        Navigator.of(ctx).pop();
                        final lang = languages.firstWhere(
                          (l) => l.extension.contains(
                              path.extension(file.path).replaceFirst('.', '')),
                          orElse: () => languages[0],
                        );
                        Navigator.of(context).push(PageRouteBuilder(
                          pageBuilder: (_, __, ___) => EditorPage(
                            rootDir: file.parent.path,
                            file: file,
                            isProject: false,
                            languageDetails: lang,
                          ),
                          transitionsBuilder: (_, a, __, child) =>
                              SizeTransition(sizeFactor: a, child: child),
                        ));
                      }
                    },
                    child: const Text('Create',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _doOpenFile(BuildContext context) async {
    if (!context.mounted) return;
    final file = await pickFile();
    if (file == null || !context.mounted) return;
    final lang = languages.firstWhere(
      (l) => l.extension.contains(
          path.extension(file.path).replaceFirst('.', '')),
      orElse: () => languages[0],
    );
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => EditorPage(
        languageDetails: lang,
        rootDir: file.parent.path,
        file: file,
        isProject: false,
      ),
      transitionsBuilder: (_, a, __, child) =>
          SizeTransition(sizeFactor: a, child: child),
    ));
  }

  Future<void> _doOpenFolder(BuildContext context, AppTheme appTheme) async {
    final dir = await pickDir();
    if (dir == null) return;
    if (!dir.existsSync()) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: appTheme.isDark
                ? const Color(0xff2b2b2b)
                : Colors.white,
            title: const Text('Cannot open folder'),
            content: const Text('The selected folder could not be opened.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK')),
            ],
          ),
        );
      }
      return;
    }
    if (context.mounted) {
      Navigator.of(context).push(PageRouteBuilder(
        pageBuilder: (_, __, ___) => EditorPage(
          rootDir: dir.path,
          isCloned: false,
          isProject: true,
          languageDetails: null,
        ),
        transitionsBuilder: (_, a, __, child) =>
            SizeTransition(sizeFactor: a, child: child),
      ));
    }
  }

  void _doCloneRepo(BuildContext context, AppTheme appTheme) {
    showDialog(
      context: context,
      builder: (_) {
        final cloneCtrl = TextEditingController();
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(24),
            decoration: _dialogBox(appTheme.isDark),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogHeader(
                    appTheme, Broken.programming_arrows, 'Clone Repository'),
                const SizedBox(height: 8),
                Text('Enter the repository URL to clone',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                const SizedBox(height: 24),
                Form(
                  key: _cloneRepoKey,
                  child: TextFormField(
                    controller: cloneCtrl,
                    style:
                        TextStyle(color: appTheme.selectScreenCardTextColor),
                    cursorColor: _kAccent,
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter a URL' : null,
                    decoration: InputDecoration(
                      hintText: 'https://github.com/user/repo.git',
                      hintStyle: const TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: Color(0xff3c3c3c)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _kAccent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _cancelBtn(context),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: _primaryBtn(),
                      onPressed: () async {
                        if (!_cloneRepoKey.currentState!.validate()) return;
                        final url  = cloneCtrl.text.trim();
                        final name = url.split('/').last.replaceAll('.git', '');
                        final progressCtrl =
                            StreamController<double>.broadcast();
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => Dialog(
                            backgroundColor: Colors.transparent,
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: _dialogBox(appTheme.isDark),
                              child: StreamBuilder<double>(
                                stream: progressCtrl.stream,
                                initialData: 0.0,
                                builder: (_, snap) {
                                  final p = snap.data ?? 0.0;
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Broken.programming_arrows,
                                          color: _kAccent, size: 32),
                                      const SizedBox(height: 16),
                                      Text('Cloning repository…',
                                          style: TextStyle(
                                              color: appTheme
                                                  .selectScreenCardTextColor,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 24),
                                      LinearPercentIndicator(
                                        percent: p,
                                        progressColor: _kAccent,
                                        barRadius:
                                            const Radius.circular(20),
                                        lineHeight: 8,
                                        trailing: Padding(
                                          padding: const EdgeInsets.only(
                                              left: 10),
                                          child: Text(
                                              '${(p * 100).toStringAsFixed(1)}%',
                                              style: TextStyle(
                                                  color: appTheme
                                                      .selectScreenCardTextColor)),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                        progressCtrl.add(0.0);
                        await _performClone(
                            projectDir, url, name, context, progressCtrl);
                      },
                      child: const Text('Clone',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Dialog helpers ─────────────────────────────────────────────────────────
  BoxDecoration _dialogBox(bool isDark) => BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
              : [const Color(0xfffafafa), const Color(0xfff0f0f0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10)),
        ],
      );

  Widget _dialogHeader(AppTheme appTheme, IconData icon, String title) =>
      Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kAccent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _kAccent, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(title,
              style: TextStyle(
                  color: appTheme.selectScreenCardTextColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
        ),
      ]);

  Widget _cancelBtn(BuildContext ctx) => TextButton(
        onPressed: () => Navigator.of(ctx).pop(),
        style: TextButton.styleFrom(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        child: Text('Cancel',
            style: TextStyle(
                color: Colors.grey[600], fontWeight: FontWeight.w500)),
      );

  ButtonStyle _primaryBtn() => ElevatedButton.styleFrom(
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        elevation: 2,
      );

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    context.read<GithubAuthCubit>().refresh();
    return BlocBuilder<AppThemeBloc, AppThemeState>(
      builder: (context, appThemestate) {
        final appTheme = appThemestate.appTheme;
        return BlocListener<PackageCatalogCubit, PackageCatalogState>(
          listenWhen: (prev, cur) =>
              !_didShowPackageUpdateToast &&
              !prev.hasUpdates &&
              cur.hasUpdates,
          listener: (context, state) {
            _didShowPackageUpdateToast = true;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  '${state.totalUpdateCount} package update(s) available in Downloads.'),
            ));
          },
          child: Scaffold(
            key: _scaffoldKey,
            resizeToAvoidBottomInset: false,
            backgroundColor: appTheme.scaffoldBg,

            // ── Drawer (unchanged behaviour) ──────────────────────────────
            drawer: Drawer(
              backgroundColor: appTheme.selectScreenDrawerBg,
              child: ListView(children: [
                drawerTile(
                  () => _push(context, const Settings()),
                  'Settings',
                  Icon(Broken.settings,
                      color: Colors.blueGrey, size: 26),
                ),
                drawerTile(
                  () => _push(context, const ContributePage()),
                  'Contribute / Source code',
                  Icon(Broken.programming_arrows,
                      color: appTheme.isDark
                          ? Colors.grey
                          : const Color(0xff242424),
                      size: 24),
                ),
                drawerTile(
                  () => _push(context, const AboutPage()),
                  'About',
                  Icon(Broken.info_circle,
                      color: Colors.blueGrey, size: 24),
                ),
                drawerTile(
                  () => _push(context, BuyMeCoffee()),
                  'Support the developer',
                  Icon(Broken.heart, color: Colors.redAccent, size: 24),
                ),
              ]),
            ),

            // ── Body ─────────────────────────────────────────────────────
            body: SafeArea(
              child: Row(
                children: [
                  // ── Activity bar ──────────────────────────────────────
                  _buildActivityBar(context, appTheme),

                  // ── Sliding sidebar panel ─────────────────────────────
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    width: _sidebarPanelOpen ? _kSidebarWidth : 0,
                    child: _sidebarPanelOpen
                        ? _buildSidebarPanel(context, appTheme)
                        : null,
                  ),

                  // ── Main content ──────────────────────────────────────
                  Expanded(
                    child: Column(
                      children: [
                        _buildTopBar(context, appTheme, appThemestate),
                        _buildTabBar(appTheme),
                        Expanded(
                          child: _buildWelcomePage(
                              context, appTheme, appThemestate),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) =>
          SizeTransition(sizeFactor: a, child: child),
    ));
  }

  // ── Activity bar ──────────────────────────────────────────────────────────
  Widget _buildActivityBar(BuildContext context, AppTheme appTheme) {
    // Top items — each toggles a sidebar panel
    final topItems = <_RailItem>[
      _RailItem(icon: Broken.element_3,          label: 'Explorer',        idx: 1),
      _RailItem(icon: Broken.search_normal,       label: 'Rechercher',      idx: 2),
      _RailItem(icon: Broken.programming_arrows,  label: 'Contrôle Git',    idx: 3),
      _RailItem(icon: Broken.play_circle,         label: 'Exécuter / Debug',idx: 4),
      _RailItem(icon: Broken.cloud_connection,    label: 'Tunnel',          idx: 5),
      _RailItem(icon: Broken.shop,               label: 'Marketplace',     idx: 6),
    ];

    return Container(
      width: 48,
      color: _kActivityBg,
      child: Column(
        children: [
          // ── Hamburger : ouvre/ferme le panneau latéral ──────────────
          Tooltip(
            message: _sidebarPanelOpen ? 'Fermer le panneau' : 'Ouvrir le panneau',
            child: InkWell(
              onTap: () {
                setState(() {
                  if (_sidebarPanelOpen) {
                    _sidebarPanelOpen = false;
                    _activeRail = 0;
                  } else {
                    // open to the last selected item, or Explorer by default
                    if (_activeRail == 0) _activeRail = 1;
                    _sidebarPanelOpen = true;
                  }
                });
              },
              child: Container(
                width: 48,
                height: 48,
                child: Center(
                  child: Icon(
                    _sidebarPanelOpen ? Broken.close_square : Broken.menu,
                    size: 22,
                    color: _kActivityIcon,
                  ),
                ),
              ),
            ),
          ),
          const Divider(color: Color(0xff444444), height: 1),
          const SizedBox(height: 4),

          // ── Sidebar items ─────────────────────────────────────────────
          ...topItems.map((item) => _ActivityBtn(
                item: item,
                selected: _sidebarPanelOpen && _activeRail == item.idx,
                onTap: () {
                  setState(() {
                    if (_activeRail == item.idx && _sidebarPanelOpen) {
                      // tap same icon → close panel
                      _sidebarPanelOpen = false;
                      _activeRail = 0;
                    } else {
                      _activeRail = item.idx;
                      _sidebarPanelOpen = true;
                    }
                  });
                },
              )),

          // ── Panda Agent ───────────────────────────────────────────────
          Tooltip(
            message: 'Panda Agent',
            child: InkWell(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Panda Agent — bientôt disponible 🐼'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: Container(
                width: 48,
                height: 48,
                child: Center(
                  child: ClipOval(
                    child: Image.asset(
                      'assets/icons/app-icon.png',
                      width: 26,
                      height: 26,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Text(
                        '🐼',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const Spacer(),

          // ── Bas : thème + compte GitHub + paramètres ──────────────────
          // Theme toggle
          BlocBuilder<AppThemeBloc, AppThemeState>(
            builder: (context, state) => _ActivityBtn(
              item: _RailItem(
                  icon: state.appTheme.isDark ? Broken.sun_1 : Broken.moon,
                  label: 'Basculer le thème',
                  idx: 98),
              selected: false,
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                final cur = prefs.getString('savedAppTheme');
                if (context.mounted) {
                  if (cur == 'dark') {
                    context.read<AppThemeBloc>().add(AppThemeEvent(appTheme: LightTheme()));
                    prefs.setString('savedAppTheme', 'light');
                  } else {
                    context.read<AppThemeBloc>().add(AppThemeEvent(appTheme: DarkTheme()));
                    prefs.setString('savedAppTheme', 'dark');
                  }
                }
              },
            ),
          ),

          // GitHub account avatar
          Tooltip(
            message: 'Compte GitHub',
            child: _GithubAvatar(onTap: () => _push(context, GithubPage())),
          ),

          // Settings
          _ActivityBtn(
            item: _RailItem(icon: Broken.settings, label: 'Paramètres', idx: 99),
            selected: false,
            onTap: () => _push(context, const Settings()),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Sidebar panel content ─────────────────────────────────────────────────
  Widget _buildSidebarPanel(BuildContext context, AppTheme appTheme) {
    final isDark = appTheme.isDark;
    final bg = isDark ? _kSidebarBgDark : _kSidebarBgLight;
    final titleColor = isDark ? Colors.grey[400]! : Colors.grey[700]!;
    final borderColor = isDark ? const Color(0xff3c3c3c) : const Color(0xffdddddd);

    final titles = {
      1: 'EXPLORATEUR',
      2: 'RECHERCHER',
      3: 'CONTRÔLE GIT',
      4: 'EXÉCUTER / DEBUG',
      5: 'TUNNEL / SSH',
      6: 'MARKETPLACE',
    };

    Widget panelBody;
    switch (_activeRail) {
      case 1: // Explorer
        panelBody = _sidebarExplorer(context, appTheme, isDark);
        break;
      case 2: // Search
        panelBody = _sidebarSearch(context, appTheme, isDark);
        break;
      case 3: // Git
        panelBody = _sidebarGit(context, appTheme, isDark);
        break;
      case 4: // Debug
        panelBody = _sidebarDebug(context, appTheme, isDark);
        break;
      case 5: // Tunnel
        panelBody = _sidebarTunnel(context, appTheme, isDark);
        break;
      case 6: // Marketplace
        panelBody = _sidebarMarketplace(context, appTheme, isDark);
        break;
      default:
        panelBody = const SizedBox.shrink();
    }

    return Container(
      width: _kSidebarWidth,
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel header
          Container(
            height: 35,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    titles[_activeRail] ?? '',
                    style: _kSectionTitle.copyWith(color: titleColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => setState(() {
                    _sidebarPanelOpen = false;
                    _activeRail = 0;
                  }),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Broken.close_circle,
                        size: 14, color: titleColor),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: panelBody),
        ],
      ),
    );
  }

  // ── Explorer panel ────────────────────────────────────────────────────────
  Widget _sidebarExplorer(BuildContext ctx, AppTheme t, bool dark) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _panelItem(ctx, t, Broken.document_text, 'Nouveau fichier…',
            () { Navigator.of(ctx).pop(); _doNewFile(ctx, t); }),
        _panelItem(ctx, t, Broken.document_upload, 'Ouvrir un fichier…',
            () => _doOpenFile(ctx)),
        _panelItem(ctx, t, Broken.folder_open, 'Ouvrir un dossier…',
            () => _doOpenFolder(ctx, t)),
        _panelItem(ctx, t, Broken.programming_arrows, 'Cloner un dépôt…',
            () => _doCloneRepo(ctx, t)),
        _panelItem(ctx, t, Broken.folder_2, 'Gestionnaire de fichiers',
            () => _push(ctx, const FileManagerPage())),
        const Divider(indent: 12, endIndent: 12),
        _panelItem(ctx, t, Broken.sidebar_right, 'Projets',
            () => _push(ctx, const ProjectScreen())),
        _panelItem(ctx, t, Broken.document_download, 'Téléchargements',
            () => _push(ctx, DownloadManager())),
      ],
    );
  }

  // ── Search panel ──────────────────────────────────────────────────────────
  Widget _sidebarSearch(BuildContext ctx, AppTheme t, bool dark) {
    final ctrl = TextEditingController();
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: ctrl,
            autofocus: false,
            style: TextStyle(
                color: dark ? Colors.grey[300] : Colors.grey[800],
                fontSize: 13),
            cursorColor: _kAccent,
            decoration: InputDecoration(
              hintText: 'Rechercher…',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 16, color: Colors.grey),
              isDense: true,
              filled: true,
              fillColor: dark ? const Color(0xff3c3c3c) : Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                    color: dark ? const Color(0xff555555) : const Color(0xffcccccc)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: _kAccent),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Ouvrez un fichier pour lancer la recherche dans un projet.',
            style: TextStyle(
                fontSize: 12,
                color: dark ? Colors.grey[500] : Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  // ── Git panel ─────────────────────────────────────────────────────────────
  Widget _sidebarGit(BuildContext ctx, AppTheme t, bool dark) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _panelItem(ctx, t, Broken.programming_arrows, 'Ouvrir GitHub',
            () => _push(ctx, GithubPage())),
        _panelItem(ctx, t, Broken.add_circle, 'Cloner un dépôt…',
            () => _doCloneRepo(ctx, t)),
        BlocBuilder<GithubAuthCubit, GithubAuthState>(
          builder: (_, s) => s.isSignedIn
              ? _panelItem(ctx, t, Broken.add_square, 'Créer un dépôt…',
                  () => _push(ctx, GithubPage()))
              : const SizedBox.shrink(),
        ),
        const Divider(indent: 12, endIndent: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: BlocBuilder<GithubAuthCubit, GithubAuthState>(
            builder: (_, s) => Text(
              s.isSignedIn
                  ? 'Connecté : ${s.user?.login ?? ''}'
                  : 'Non connecté — appuyez sur « Ouvrir GitHub »',
              style: TextStyle(
                  fontSize: 12,
                  color: dark ? Colors.grey[500] : Colors.grey[600]),
            ),
          ),
        ),
      ],
    );
  }

  // ── Debug panel ───────────────────────────────────────────────────────────
  Widget _sidebarDebug(BuildContext ctx, AppTheme t, bool dark) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _panelItem(ctx, t, Broken.cpu, 'Ouvrir le terminal',
            () => _push(ctx, SetupTerminal(
                  projectDir: homeDir,
                  sshId: null,
                  termuxId: null,
                ))),
        _panelItem(ctx, t, Broken.play_circle, 'Exécuter un fichier…',
            () => _doOpenFile(ctx)),
        const Divider(indent: 12, endIndent: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'Ouvrez un projet pour accéder aux configurations de lancement.',
            style: TextStyle(
                fontSize: 12,
                color: dark ? Colors.grey[500] : Colors.grey[600]),
          ),
        ),
      ],
    );
  }

  // ── Tunnel panel ──────────────────────────────────────────────────────────
  Widget _sidebarTunnel(BuildContext ctx, AppTheme t, bool dark) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _panelItem(ctx, t, Broken.cpu, 'Ouvrir terminal SSH',
            () => _push(ctx, SetupTerminal(
                  projectDir: homeDir,
                  sshId: null,
                  termuxId: null,
                ))),
        _panelItem(ctx, t, Broken.settings, 'Paramètres SSH / Termux',
            () => _push(ctx, const Settings())),
        const Divider(indent: 12, endIndent: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'Connectez-vous à un serveur distant ou configurez Termux pour exécuter du code nativement.',
            style: TextStyle(
                fontSize: 12,
                color: dark ? Colors.grey[500] : Colors.grey[600]),
          ),
        ),
      ],
    );
  }

  // ── Marketplace panel ─────────────────────────────────────────────────────
  Widget _sidebarMarketplace(BuildContext ctx, AppTheme t, bool dark) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _panelItem(ctx, t, Broken.shop, 'Parcourir les modèles',
            () => _push(ctx, const MenuScreen())),
        _panelItem(ctx, t, Broken.document_download, 'Téléchargements / Paquets',
            () => _push(ctx, DownloadManager())),
        const Divider(indent: 12, endIndent: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'Téléchargez des runtimes, extensions et modèles de projet.',
            style: TextStyle(
                fontSize: 12,
                color: dark ? Colors.grey[500] : Colors.grey[600]),
          ),
        ),
      ],
    );
  }

  // ── Panel item helper ─────────────────────────────────────────────────────
  Widget _panelItem(
      BuildContext ctx, AppTheme t, IconData icon, String label, VoidCallback onTap) {
    final dark = t.isDark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 15,
                color: dark ? Colors.grey[400] : Colors.grey[700]),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: 13,
                    color: dark ? Colors.grey[300] : Colors.grey[800]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar (workspace breadcrumb) ────────────────────────────────────────
  Widget _buildTopBar(
      BuildContext context, AppTheme appTheme, AppThemeState appThemestate) {
    final isDark = appTheme.isDark;
    return Container(
      height: 35,
      color: isDark ? const Color(0xff3c3c3c) : const Color(0xffdedede),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Workspace label
          Expanded(
            child: Row(children: [
              Icon(Broken.folder_open,
                  size: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[700]),
              const SizedBox(width: 6),
              Text('Workspace',
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Colors.grey[400] : Colors.grey[700])),
            ]),
          ),
          // Action icons
          _topBarIcon(Broken.folder_open, 'File Manager', appTheme, () {
            _push(context, const FileManagerPage());
          }),
          _topBarIcon(Broken.document_download, 'Downloads', appTheme, () {
            _push(context, DownloadManager());
          }),
          // Download badge
          BlocBuilder<PackageCatalogCubit, PackageCatalogState>(
            builder: (_, state) => state.hasUpdates
                ? Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('${state.totalUpdateCount}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  )
                : const SizedBox.shrink(),
          ),
          _topBarIcon(Broken.sidebar_right, 'Projects', appTheme, () {
            _push(context, const ProjectScreen());
          }),
          _topBarIcon(Broken.grid_9, 'Templates', appTheme, () {
            _push(context, const MenuScreen());
          }),
        ],
      ),
    );
  }

  Widget _topBarIcon(
      IconData icon, String tooltip, AppTheme appTheme, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Icon(icon,
              size: 16,
              color: appTheme.isDark
                  ? Colors.grey[400]
                  : Colors.grey[700]),
        ),
      ),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────
  Widget _buildTabBar(AppTheme appTheme) {
    final isDark = appTheme.isDark;
    final tabBg = isDark ? _kTabBarDark : _kTabBarLight;
    final activeTabBg = isDark ? _kTabActiveDark : _kTabActiveLight;

    return Container(
      height: 35,
      color: tabBg,
      child: Row(children: [
        // Active tab
        Container(
          height: 35,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: activeTabBg,
            border: Border(
              top: const BorderSide(color: _kAccent, width: 1),
            ),
          ),
          child: Row(children: [
            Icon(Broken.global_refresh,
                size: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[600]),
            const SizedBox(width: 6),
            Text('Welcome',
                style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? Colors.grey[300]
                        : Colors.grey[800])),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {},
              child: Icon(Broken.close_circle,
                  size: 12,
                  color: isDark ? Colors.grey[500] : Colors.grey[600]),
            ),
          ]),
        ),
        const Spacer(),
        // Layout controls
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(children: [
            _tabIcon(Broken.sidebar_left, 'Toggle sidebar', appTheme),
            _tabIcon(
                Broken.element_4, 'Editor layout', appTheme),
          ]),
        ),
      ]),
    );
  }

  Widget _tabIcon(IconData icon, String tooltip, AppTheme appTheme) =>
      Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(icon,
              size: 16,
              color: appTheme.isDark
                  ? Colors.grey[500]
                  : Colors.grey[700]),
        ),
      );

  // ── Welcome page ──────────────────────────────────────────────────────────
  Widget _buildWelcomePage(
      BuildContext context, AppTheme appTheme, AppThemeState appThemestate) {
    final isDark = appTheme.isDark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero ────────────────────────────────────────────────────
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kAccent.withOpacity(0.15),
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

            // ── Start section ────────────────────────────────────────────
            _sectionHeader('Démarrer', isDark),
            const SizedBox(height: 10),
            _StartItem(
              icon: Broken.document_text,
              label: 'Nouveau fichier…',
              isDark: isDark,
              onTap: () => _doNewFile(context, appTheme),
            ),
            _StartItem(
              icon: Broken.document_upload,
              label: 'Ouvrir un fichier…',
              isDark: isDark,
              onTap: () => _doOpenFile(context),
            ),
            _StartItem(
              icon: Broken.folder_open,
              label: 'Ouvrir un dossier…',
              isDark: isDark,
              onTap: () => _doOpenFolder(context, appTheme),
            ),
            _StartItem(
              icon: Broken.programming_arrows,
              label: 'Cloner un référentiel…',
              isDark: isDark,
              onTap: () => _doCloneRepo(context, appTheme),
            ),
            // GitHub
            BlocBuilder<GithubAuthCubit, GithubAuthState>(
              builder: (_, authState) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StartItem(
                    svgAsset: 'assets/icons/code-branch-solid.svg',
                    label: 'GitHub — Ouvrir un référentiel…',
                    isDark: isDark,
                    onTap: () {
                      if (authState.isSignedIn) {
                        _push(context, GithubPage());
                      } else {
                        _push(context, GithubPage());
                      }
                    },
                  ),
                  if (authState.isSignedIn)
                    _StartItem(
                      icon: Broken.add_circle,
                      label: 'Créer un dépôt GitHub…',
                      isDark: isDark,
                      onTap: () => _push(context, GithubPage()),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Recent section ───────────────────────────────────────────
            _sectionHeader('Récent', isDark),
            const SizedBox(height: 10),
            BlocBuilder<RecentBloc, RecentState>(
              builder: (context, recentState) {
                final recentData = recentState.recent
                    .map(_normalizeRecentEntry)
                    .whereType<Map<String, dynamic>>()
                    .toList();

                if (recentData.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      "Vous n'avez pas encore de fichiers récents. ",
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
                    final rootDir   = entry['rootDir'] as String;
                    final isProject = entry['type'] == 'project';
                    final exists = isProject
                        ? Directory(entryPath).existsSync()
                        : File(entryPath).existsSync();

                    Widget leading;
                    if (isProject) {
                      leading = const Icon(Broken.folder_open,
                          color: _kAccent, size: 18);
                    } else {
                      final matchingLang = languages.where((l) =>
                          l.extension.contains(path
                              .extension(entryPath)
                              .toLowerCase()
                              .replaceFirst('.', ''))).toList();
                      leading = matchingLang.isNotEmpty
                          ? matchingLang[0].icon ?? const Icon(Broken.document, size: 18)
                          : const Icon(Broken.document, color: Colors.grey, size: 18);
                    }

                    return _RecentItem(
                      leading: leading,
                      title: exists
                          ? path.basename(entryPath)
                          : '${path.basename(entryPath)} — introuvable',
                      subtitle: rootDir,
                      isDark: isDark,
                      faded: !exists,
                      onTap: () {
                        if (!exists) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '${isProject ? 'Project' : 'File'} not found'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }
                        if (isProject) {
                          Navigator.of(context).push(PageRouteBuilder(
                            pageBuilder: (_, __, ___) => EditorPage(
                              rootDir: entryPath,
                              isCloned: true,
                              isProject: true,
                              languageDetails: null,
                            ),
                            transitionsBuilder: (_, a, __, child) =>
                                SizeTransition(sizeFactor: a, child: child),
                          ));
                          return;
                        }
                        final matchingLang = languages
                            .where((l) => l.extension.contains(
                                path.extension(entryPath)
                                    .toLowerCase()
                                    .replaceFirst('.', '')))
                            .toList();
                        Navigator.of(context).push(PageRouteBuilder(
                          pageBuilder: (_, __, ___) => EditorPage(
                            file: File(entryPath),
                            rootDir: rootDir,
                            languageDetails: matchingLang.isNotEmpty
                                ? matchingLang[0]
                                : Language(
                                    name: 'Unknown',
                                    extension: ['null'],
                                    details: 'Unknown language',
                                    language: unknown,
                                    helloWorld: 'Unknown type of file',
                                    icon: null),
                            isProject: false,
                          ),
                          transitionsBuilder: (_, a, __, child) =>
                              SizeTransition(sizeFactor: a, child: child),
                        ));
                      },
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 28),

            // ── Walkthroughs ─────────────────────────────────────────────
            _sectionHeader('Procédures pas à pas', isDark),
            const SizedBox(height: 10),
            _WalkthroughCard(
              icon: Broken.flash_circle,
              title: 'Démarrer avec Panda IDE',
              subtitle:
                  'Configurez votre éditeur, téléchargez les runtimes et commencez à coder.',
              isDark: isDark,
              onTap: () => _push(context, DownloadManager()),
            ),
            const SizedBox(height: 10),
            _WalkthroughCard(
              icon: Broken.programming_arrows,
              title: 'Cloner depuis GitHub',
              subtitle:
                  'Connectez votre compte GitHub et gérez vos dépôts directement.',
              isDark: isDark,
              onTap: () => _push(context, GithubPage()),
            ),
            const SizedBox(height: 10),
            _WalkthroughCard(
              icon: Broken.cpu,
              title: 'Parcourir les modèles',
              subtitle: "Créez un projet à partir d'un modèle prêt à l'emploi.",
              isDark: isDark,
              onTap: () => _push(context, const MenuScreen()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, bool isDark) => Text(
        title.toUpperCase(),
        style: _kSectionTitle.copyWith(
          color: isDark ? Colors.grey[500] : Colors.grey[600],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _RailItem {
  final IconData icon;
  final String   label;
  final int      idx;
  const _RailItem({required this.icon, required this.label, required this.idx});
}

class _ActivityBtn extends StatelessWidget {
  final _RailItem  item;
  final bool       selected;
  final VoidCallback onTap;
  const _ActivityBtn(
      {required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item.label,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            border: selected
                ? const Border(
                    left: BorderSide(color: _kActivitySel, width: 2))
                : null,
          ),
          child: Center(
            child: Icon(
              item.icon,
              size: 22,
              color: selected ? _kActivitySel : _kActivityIcon,
            ),
          ),
        ),
      ),
    );
  }
}

class _GithubAvatar extends StatelessWidget {
  final VoidCallback onTap;
  const _GithubAvatar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GithubAuthCubit, GithubAuthState>(
      builder: (_, state) {
        return GestureDetector(
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
                            const Icon(Broken.profile_circle,
                                color: _kActivityIcon, size: 22))
                    : const Icon(Broken.profile_circle,
                        color: _kActivityIcon, size: 22),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Start item ────────────────────────────────────────────────────────────────
class _StartItem extends StatefulWidget {
  final IconData?    icon;
  final String?      svgAsset;
  final String       label;
  final bool         isDark;
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
    final accent = widget.isDark
        ? const Color(0xff76b4ea)
        : const Color(0xff146bb7);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: PandaSurface.welcomeItem(widget.isDark,
              hovered: _hovered),
          child: Row(children: [
            SizedBox(
              width: 22,
              child: widget.svgAsset != null
                  ? SvgPicture.asset(
                      widget.svgAsset!,
                      height: 18,
                      width: 18,
                      colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
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
  final Widget       leading;
  final String       title;
  final String       subtitle;
  final bool         isDark;
  final bool         faded;
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
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: PandaSurface.recentRow(widget.isDark,
              hovered: _hovered),
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
  final IconData     icon;
  final String       title;
  final String       subtitle;
  final bool         isDark;
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
    final border = widget.isDark
        ? const Color(0xff3c3c3c)
        : const Color(0xffdddddd);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
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
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]
                : [],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  Icon(widget.icon, color: _kAccent, size: 20),
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
