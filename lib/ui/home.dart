import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:file_picker/file_picker.dart';
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
import '../utils/ai.dart';
import '../ui/contribute.dart';
import '../ui/github_page.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/languages.dart';
import '../utils/themes.dart';
import '../extensions/ui/marketplace_page.dart';
import '../extensions/ui/extensions_panel.dart';
import '../extensions/ui/extension_webview.dart';
import 'agent_runner.dart';
import 'widgets.dart';

// ── VSCode colour tokens ──────────────────────────────────────────────────────
// activity-bar colours (dark / light)
const _kActivityBgDark    = Color(0xff333333);
const _kActivityBgLight   = Color(0xffe8e8e8);
const _kActivityIconDark  = Color(0xff858585);
const _kActivityIconLight = Color(0xff616161);
const _kActivitySelDark   = Color(0xffffffff);
const _kActivitySelLight  = Color(0xff1a1a1a);
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
  bool _rightPanelOpen   = false;
  bool _bottomPanelOpen  = false;

  // ── Dynamic tab system ──────────────────────────────────────────
  int  _activeTabIdx = 0;
  final List<_TabDef> _openTabs = [
    const _TabDef(id: 'welcome', title: 'Welcome', icon: Broken.global_refresh),
  ];

  // ── Split editor ─────────────────────────────────────────────
  bool _splitEditor = false;
  int  _splitTabIdx = 0;
  final List<_TabDef> _splitTabs = [
    const _TabDef(id: 'welcome', title: 'Welcome', icon: Broken.global_refresh),
  ];

  // ── Panda Agent chat ─────────────────────────────────────────────
  final _agentInputCtrl  = TextEditingController();
  final _agentScrollCtrl = ScrollController();
  final List<Map<String,dynamic>> _agentMessages = [];

  // ── Agent AI state ────────────────────────────────────────────────
  AgentPhase _agentPhase        = AgentPhase.idle;
  bool       _agentGenerating   = false;
  String     _agentThinkingBuf  = '';
  String     _agentStreamBuf    = '';
  final      _agentRunner       = AgentRunner();

  // ── Agent UI state ───────────────────────────────────────────────
  /// 'ask' | 'agent' | 'normal'
  String _agentChatMode      = 'ask';
  String? _agentSelectedModelId;
  final List<Map<String,String>> _agentAttachments = [];

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Rebuild send button colour when text changes
    _agentInputCtrl.addListener(() => setState(() {}));
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
    _agentInputCtrl.dispose();
    _agentScrollCtrl.dispose();
    super.dispose();
  }

  // ── Pending shared file ────────────────────────────────────────────────────
  Future<void> _openPendingSharedFile() async {
    if (kIsWeb) return; // NativeChannel not available on web
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
              child: Column(
                children: [
                  // ── Top bar spans full width ──────────────────────────
                  _buildTopBar(context, appTheme, appThemestate),

                  // ── Below top bar: activity bar + sidebar + editor ────
                  Expanded(
                    child: Row(
                      children: [
                        // ── Activity bar ────────────────────────────────
                        _buildActivityBar(context, appTheme),

                        // ── Sliding sidebar (rounded right corners) ──────
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          width: _sidebarPanelOpen ? _kSidebarWidth : 0,
                          child: _sidebarPanelOpen
                              ? ClipRRect(
                                  borderRadius: const BorderRadius.only(
                                    topRight:    Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                  child: _buildSidebarPanel(context, appTheme),
                                )
                              : null,
                        ),

                        // ── Editor area (supports split view) ────────────
                        Expanded(
                          child: Row(
                            children: [
                              // Primary editor pane
                              Expanded(
                                child: Column(
                                  children: [
                                    _buildTabBar(appTheme, isPrimary: true),
                                    Expanded(
                                      child: _buildActiveTab(
                                          context, appTheme, appThemestate),
                                    ),
                                  ],
                                ),
                              ),
                              // Secondary (split) editor pane
                              if (_splitEditor) ...[
                                VerticalDivider(
                                  width: 1,
                                  color: appTheme.isDark
                                      ? const Color(0xff444444)
                                      : const Color(0xffcccccc),
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      _buildTabBar(appTheme, isPrimary: false),
                                      Expanded(
                                        child: _buildSplitActiveTab(
                                            context, appTheme, appThemestate),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              // Panda Agent panel
                              if (_rightPanelOpen)
                                _buildPandaAgentPanel(context, appTheme),
                            ],
                          ),
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
      final isDark    = appTheme.isDark;
      final railBg    = isDark ? _kActivityBgDark    : _kActivityBgLight;
      final iconColor = isDark ? _kActivityIconDark  : _kActivityIconLight;
      final selColor  = isDark ? _kActivitySelDark   : _kActivitySelLight;

      final topItems = <_RailItem>[
        _RailItem(icon: Broken.element_3,          label: 'Explorateur',      idx: 1),
        _RailItem(icon: Broken.search_normal,       label: 'Rechercher',       idx: 2),
        _RailItem(icon: Broken.programming_arrows,  label: 'Contrôle Git',     idx: 3),
        _RailItem(icon: Broken.play_circle,         label: 'Exécuter / Debug', idx: 4),
        _RailItem(icon: Broken.cloud_connection,    label: 'Tunnel',           idx: 5),
        _RailItem(icon: Broken.shop,                label: 'Marketplace',      idx: 6),
      ];

      return Container(
        width: 48,
        color: railBg,
        child: Column(
          children: [
                Divider(
              color: isDark ? const Color(0xff444444) : const Color(0xffcccccc),
              height: 1,
            ),
            const SizedBox(height: 4),

            // ── Sidebar items ─────────────────────────────────────────────
            ...topItems.map((item) => _ActivityBtnEx(
                  item:      item,
                  selected:  _sidebarPanelOpen && _activeRail == item.idx,
                  iconColor: iconColor,
                  selColor:  selColor,
                  onTap: () {
                    setState(() {
                      if (_activeRail == item.idx && _sidebarPanelOpen) {
                        _sidebarPanelOpen = false;
                        _activeRail = 0;
                      } else {
                        _activeRail = item.idx;
                        _sidebarPanelOpen = true;
                      }
                    });
                  },
                )),

            // ── Panda Agent (opens right panel) ───────────────────────────
            Tooltip(
              message: 'Panda Agent',
              child: InkWell(
                onTap: () => setState(() => _rightPanelOpen = !_rightPanelOpen),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    border: _rightPanelOpen
                        ? Border(left: BorderSide(color: selColor, width: 2))
                        : null,
                  ),
                  child: Center(
                    child: ClipOval(
                      child: Image.asset(
                        'assets/icons/app-icon.png',
                        width: 26,
                        height: 26,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Text(
                          '\u{1F43C}',
                          style: TextStyle(fontSize: 18, color: iconColor),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const Spacer(),

            // ── Theme toggle ───────────────────────────────────────────────
            BlocBuilder<AppThemeBloc, AppThemeState>(
              builder: (context, state) => _ActivityBtnEx(
                item: _RailItem(
                    icon:  state.appTheme.isDark ? Broken.sun_1 : Broken.moon,
                    label: 'Basculer le theme',
                    idx:   98),
                selected:  false,
                iconColor: iconColor,
                selColor:  selColor,
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

            Tooltip(
              message: 'Compte GitHub',
              child: _GithubAvatarEx(
                iconColor: iconColor,
                onTap: () => _push(context, GithubPage()),
              ),
            ),

            _ActivityBtnEx(
              item:      _RailItem(icon: Broken.settings, label: 'Parametres', idx: 99),
              selected:  false,
              iconColor: iconColor,
              selColor:  selColor,
              onTap: () => _push(context, const Settings()),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    }

    // ── Sidebar panel content ─────────────────────────────────────────────────
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
    final bool nodeAvailable = kIsWeb
        ? true
        : () {
            try {
              // Vérifie si node est accessible via Termux ou le chemin standard
              final paths = [
                '/data/data/com.termux.app/files/usr/bin/node',
                '/usr/bin/node',
                '/usr/local/bin/node',
              ];
              return paths.any((p) {
                try { return File(p).existsSync(); } catch (_) { return false; }
              });
            } catch (_) {
              return false;
            }
          }();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // ── Bannière Node.js si absent ────────────────────────────────
        if (!nodeAvailable) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(dark ? 0.15 : 0.10),
              border: Border.all(
                  color: Colors.orange.withOpacity(0.5), width: 1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              const Icon(Broken.warning_2, size: 14, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Runtime Node.js absent. Installez-le pour activer les extensions.',
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          dark ? Colors.orange[300] : Colors.orange[800]),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _push(ctx, DownloadManager()),
                child: Text('Installer',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.orange[400],
                        decoration: TextDecoration.underline)),
              ),
            ]),
          ),
          const SizedBox(height: 4),
        ],

        // ── Section Extensions VSCode ─────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text('EXTENSIONS VSCODE',
              style: _kSectionTitle.copyWith(
                  color: dark ? Colors.grey[500] : Colors.grey[500])),
        ),
        _panelItem(ctx, t, Broken.shop, 'Parcourir les extensions',
            () => _push(ctx, const MarketplacePage())),
        _panelItem(ctx, t, Broken.element_3, 'Extensions installées',
            () => _push(ctx, const ExtensionsPanel())),
        const Divider(indent: 12, endIndent: 12),

        // ── Section Modèles & runtimes ────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Text('MODÈLES & RUNTIMES',
              style: _kSectionTitle.copyWith(
                  color: dark ? Colors.grey[500] : Colors.grey[500])),
        ),
        _panelItem(ctx, t, Broken.cpu, 'Parcourir les modèles IA',
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
      final fg = isDark ? Colors.grey[400]! : Colors.grey[700]!;

      return Container(
        height: 35,
        color: isDark ? const Color(0xff3c3c3c) : const Color(0xffdedede),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            // ── Left: nav arrows only ─────────────────────────────────────
            _hdrBtn(Broken.arrow_left_2,  'Reculer',  fg, () {}),
            _hdrBtn(Broken.arrow_right_3, 'Avancer',  fg, () {}),

            // ── Center: workspace pill (truly centered) ───────────────────
            Expanded(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xff2a2a2a)
                        : const Color(0xffc8c8c8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Broken.folder_open, size: 13, color: fg),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Espace de travail',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: fg),
                      ),
                    ),
                  ]),
                ),
              ),
            ),

            // ── Right: exactly 4 layout buttons ──────────────────────────
            _hdrBtn(
              Broken.sidebar_left,
              'Panneau lateral',
              _sidebarPanelOpen ? _kAccent : fg,
              () => setState(() {
                _sidebarPanelOpen = !_sidebarPanelOpen;
                if (_sidebarPanelOpen && _activeRail == 0) _activeRail = 1;
              }),
            ),
            Builder(
              builder: (ctx) => _hdrBtn(
                Broken.element_4,
                'Personnaliser la disposition',
                fg,
                () => _showLayoutMenu(ctx, isDark),
              ),
            ),
            _hdrBtn(
              Broken.minus_square,
              'Panneau inferieur',
              _bottomPanelOpen ? _kAccent : fg,
              () => setState(() => _bottomPanelOpen = !_bottomPanelOpen),
            ),
            _hdrBtn(
              Broken.maximize_3,
              'Plein ecran',
              fg,
              () {},
            ),
          ],
        ),
      );
    }

    Widget _hdrBtn(
            IconData icon, String tooltip, Color color, VoidCallback onTap) =>
        Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: Icon(icon, size: 16, color: color),
            ),
          ),
        );

    void _showLayoutMenu(BuildContext ctx, bool isDark) {
      final fg = isDark ? Colors.grey[300]! : Colors.grey[800]!;
      final bg = isDark ? const Color(0xff252526) : const Color(0xfff3f3f3);
      showMenu<String>(
        context: ctx,
        position: const RelativeRect.fromLTRB(0, 35, 0, 0),
        color: bg,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        items: [
          _layoutMenuItem('sidebar_left', Broken.sidebar_left,
              'Panneau lateral gauche', fg, bg,
              checked: _sidebarPanelOpen),
          _layoutMenuItem('sidebar_right', Broken.sidebar_right,
              'Panneau lateral droit', fg, bg,
              checked: _rightPanelOpen),
          _layoutMenuItem('panel_bottom', Broken.minus_square,
              'Panneau inferieur', fg, bg,
              checked: _bottomPanelOpen),
          PopupMenuItem<String>(
            height: 1,
            enabled: false,
            child: Divider(
                color: isDark
                    ? const Color(0xff444444)
                    : const Color(0xffcccccc),
                height: 1),
          ),
          _layoutMenuItem(
              'full_screen', Broken.maximize_3, 'Plein ecran', fg, bg),
        ],
      ).then((value) {
        if (value == null) return;
        setState(() {
          if (value == 'sidebar_left') {
            _sidebarPanelOpen = !_sidebarPanelOpen;
            if (_sidebarPanelOpen && _activeRail == 0) _activeRail = 1;
          }
          if (value == 'sidebar_right') _rightPanelOpen = !_rightPanelOpen;
          if (value == 'panel_bottom') _bottomPanelOpen = !_bottomPanelOpen;
        });
      });
    }

    PopupMenuItem<String> _layoutMenuItem(
        String value, IconData icon, String label, Color fg, Color bg,
        {bool checked = false}) {
      return PopupMenuItem<String>(
        value: value,
        child: Row(children: [
          Icon(checked ? Broken.tick_square : icon,
              size: 16, color: checked ? _kAccent : fg),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: fg)),
        ]),
      );
    }

    // ── Tab bar ───────────────────────────────────────────────────────────────

  Widget _buildTabBar(AppTheme appTheme, {bool isPrimary = true}) {
    final isDark      = appTheme.isDark;
    final tabBg       = isDark ? _kTabBarDark    : _kTabBarLight;
    final activeTabBg = isDark ? _kTabActiveDark : _kTabActiveLight;
    final inactiveFg  = isDark ? Colors.grey[500]! : Colors.grey[600]!;
    final activeFg    = isDark ? Colors.grey[300]! : Colors.grey[800]!;

    final tabs      = isPrimary ? _openTabs     : _splitTabs;
    final activeIdx = isPrimary ? _activeTabIdx : _splitTabIdx;

    return Container(
      height: 35,
      color: tabBg,
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(tabs.length, (i) {
                final tab      = tabs[i];
                final isActive = i == activeIdx;
                return GestureDetector(
                  onTap: () => setState(() {
                    if (isPrimary) _activeTabIdx = i;
                    else _splitTabIdx = i;
                  }),
                  child: Container(
                    height: 35,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isActive ? activeTabBg : Colors.transparent,
                      border: isActive
                          ? const Border(
                              top: BorderSide(color: _kAccent, width: 1))
                          : null,
                    ),
                    child: Row(children: [
                      Icon(tab.icon, size: 13,
                          color: isActive ? activeFg : inactiveFg),
                      const SizedBox(width: 6),
                      Text(tab.title,
                          style: TextStyle(
                              fontSize: 12,
                              color: isActive ? activeFg : inactiveFg)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => isPrimary ? _closeTab(i) : _closeSplitTab(i),
                        child: Icon(Broken.close_circle,
                            size: 12,
                            color: isActive ? inactiveFg : Colors.transparent),
                      ),
                    ]),
                  ),
                );
              }),
            ),
          ),
        ),
        // ── Right-side buttons ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Builder(builder: (ctx) => Row(children: [
            // Split button — primary editor only, when not yet split
            if (isPrimary && !_splitEditor)
              Tooltip(
                message: "Diviser l'éditeur",
                child: InkWell(
                  onTap: () => setState(() => _splitEditor = true),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Broken.element_2, size: 15, color: inactiveFg),
                  ),
                ),
              ),
            // 3-dot menu
            Tooltip(
              message: "Plus d'actions",
              child: InkWell(
                onTap: () => _showEditorMenu(ctx, isDark, isPrimary),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Broken.more_circle, size: 15, color: inactiveFg),
                ),
              ),
            ),
            // Close-split button — secondary editor only
            if (!isPrimary)
              Tooltip(
                message: 'Fermer la division',
                child: InkWell(
                  onTap: () => setState(() => _splitEditor = false),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Broken.close_circle, size: 15, color: inactiveFg),
                  ),
                ),
              ),
            // Panda Agent button — primary editor only
            if (isPrimary)
              Tooltip(
                message: 'Panda Agent',
                child: InkWell(
                  onTap: () {
                    final isMobile = MediaQuery.of(ctx).size.width < 600;
                    if (isMobile) {
                      setState(() {
                        if (!_openTabs.any((t) => t.id == 'agent')) {
                          _openTabs.add(const _TabDef(
                              id:    'agent',
                              title: 'Panda Agent',
                              icon:  Broken.message_programming));
                          _activeTabIdx = _openTabs.length - 1;
                        } else {
                          _activeTabIdx =
                              _openTabs.indexWhere((t) => t.id == 'agent');
                        }
                      });
                    } else {
                      setState(() => _rightPanelOpen = !_rightPanelOpen);
                    }
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Broken.message_programming, size: 15,
                        color: _rightPanelOpen ? _kAccent : inactiveFg),
                  ),
                ),
              ),
          ])),
        ),
      ]),
    );
  }

  void _closeSplitTab(int i) {
    setState(() {
      _splitTabs.removeAt(i);
      if (_splitTabs.isEmpty) {
        _splitTabs.add(const _TabDef(
            id: 'welcome', title: 'Welcome', icon: Broken.global_refresh));
        _splitTabIdx = 0;
      } else {
        _splitTabIdx = (_splitTabIdx >= _splitTabs.length
                ? _splitTabs.length - 1
                : _splitTabIdx)
            .clamp(0, _splitTabs.length - 1);
      }
    });
  }

  void _showEditorMenu(BuildContext ctx, bool isDark, bool isPrimary) {
    final fg = isDark ? Colors.grey[300]! : Colors.grey[800]!;
    final bg = isDark ? const Color(0xff252526) : const Color(0xfff3f3f3);
    showMenu<String>(
      context: ctx,
      position: const RelativeRect.fromLTRB(0, 35, 0, 0),
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      items: [
        PopupMenuItem<String>(
          value: 'close_all',
          child: Text('Tout fermer',
              style: TextStyle(fontSize: 13, color: fg))),
        PopupMenuItem<String>(
          value: 'reopen',
          child: Text("Réouvrir l'éditeur",
              style: TextStyle(fontSize: 13, color: fg))),
      ],
    ).then((value) {
      if (value == null) return;
      if (value == 'close_all') {
        setState(() {
          if (isPrimary) {
            _openTabs.clear();
            _openTabs.add(const _TabDef(
                id: 'welcome', title: 'Welcome', icon: Broken.global_refresh));
            _activeTabIdx = 0;
          } else {
            _splitTabs.clear();
            _splitTabs.add(const _TabDef(
                id: 'welcome', title: 'Welcome', icon: Broken.global_refresh));
            _splitTabIdx = 0;
          }
        });
      }
    });
  }

  Widget _buildSplitActiveTab(
      BuildContext context, AppTheme appTheme, AppThemeState appThemestate) {
    final tab = _splitTabs.isNotEmpty ? _splitTabs[_splitTabIdx] : null;
    if (tab == null || tab.id == 'welcome') {
      return _buildWelcomePage(context, appTheme, appThemestate);
    }
    if (tab.id == 'agent') {
      return _buildPandaAgentPanel(context, appTheme, asPage: true);
    }
    return _buildWelcomePage(context, appTheme, appThemestate);
  }

  void _closeTab(int i) {
    setState(() {
      _openTabs.removeAt(i);
      if (_openTabs.isEmpty) {
        _openTabs.add(const _TabDef(
            id: 'welcome', title: 'Welcome', icon: Broken.global_refresh));
        _activeTabIdx = 0;
      } else {
        _activeTabIdx = (_activeTabIdx >= _openTabs.length
                ? _openTabs.length - 1
                : _activeTabIdx)
            .clamp(0, _openTabs.length - 1);
      }
    });
  }

  Widget _buildActiveTab(
      BuildContext context, AppTheme appTheme, AppThemeState appThemestate) {
    final tab = _openTabs.isNotEmpty ? _openTabs[_activeTabIdx] : null;
    if (tab == null || tab.id == 'welcome') {
      return _buildWelcomePage(context, appTheme, appThemestate);
    }
    if (tab.id == 'agent') {
      return _buildPandaAgentPanel(context, appTheme, asPage: true);
    }
    return _buildWelcomePage(context, appTheme, appThemestate);
  }

  // ── Panda Agent panel ─────────────────────────────────────────────────────
  Widget _buildPandaAgentPanel(BuildContext context, AppTheme appTheme,
      {bool asPage = false}) {
    final isDark  = appTheme.isDark;
    final panelBg = isDark ? const Color(0xff1e1e1e) : const Color(0xfffafafa);
    final hdrBg   = isDark ? const Color(0xff252526) : const Color(0xffececec);
    final borderC = isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd);
    final fg      = isDark ? Colors.grey[300]! : Colors.grey[800]!;
    final muted   = isDark ? Colors.grey[500]! : Colors.grey[500]!;
    final inputBg = isDark ? const Color(0xff252526) : const Color(0xfff0f0f0);
    final inputBorder = isDark ? const Color(0xff404040) : const Color(0xffdddddd);

    // Resolve display name for selected model
    final aiState = context.watch<AIBloc>().state;
    final allModelIds = aiState.config.keys.toList();
    final effectiveModelId = _agentSelectedModelId != null &&
            aiState.config.containsKey(_agentSelectedModelId)
        ? _agentSelectedModelId!
        : (aiState.modelSelected['chat'] as String? ?? '');
    final modelDisplayName = effectiveModelId.isNotEmpty &&
            aiState.config.containsKey(effectiveModelId)
        ? (aiState.config[effectiveModelId]?['modelName'] as String? ??
            effectiveModelId)
        : 'Choisir modèle';

    return Container(
      width: asPage ? double.infinity : 300,
      decoration: BoxDecoration(
        color: panelBg,
        border: Border(left: BorderSide(color: borderC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: hdrBg,
            child: Row(children: [
              Text('PANDA AGENT',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: muted)),
              const Spacer(),
              _agentHdrBtn(Broken.add_square, 'Nouvelle conversation', muted,
                  () => setState(() {
                    _agentMessages.clear();
                    _agentAttachments.clear();
                  })),
              _agentHdrBtn(Broken.setting_2, 'Paramètres IA', muted,
                  () => _push(context, const Settings())),
              _agentHdrBtn(
                Broken.maximize_4,
                'Ouvrir dans un onglet',
                muted,
                () {
                  if (!_openTabs.any((t) => t.id == 'agent')) {
                    setState(() {
                      _openTabs.add(const _TabDef(
                          id:    'agent',
                          title: 'Panda Agent',
                          icon:  Broken.message_programming));
                      _activeTabIdx = _openTabs.length - 1;
                    });
                  } else {
                    setState(() => _activeTabIdx =
                        _openTabs.indexWhere((t) => t.id == 'agent'));
                  }
                },
              ),
              if (!asPage)
                _agentHdrBtn(Broken.close_square, 'Fermer', muted,
                    () => setState(() => _rightPanelOpen = false)),
            ]),
          ),

          // ── Mode selector ───────────────────────────────────────────────
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: hdrBg,
              border: Border(bottom: BorderSide(color: borderC)),
            ),
            child: Row(
              children: [
                for (final mode in [
                  ('ask',    'Ask'),
                  ('agent',  'Agent'),
                  ('normal', 'Normal'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: GestureDetector(
                      onTap: () => setState(() => _agentChatMode = mode.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _agentChatMode == mode.$1
                              ? _kAccent.withOpacity(isDark ? 0.25 : 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _agentChatMode == mode.$1
                                ? _kAccent.withOpacity(0.6)
                                : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          mode.$2,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _agentChatMode == mode.$1
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: _agentChatMode == mode.$1
                                ? _kAccent
                                : muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Chat area ──────────────────────────────────────────────────
          Expanded(
            child: _agentMessages.isEmpty
                ? _buildAgentEmptyState(isDark, muted, fg)
                : _buildAgentMessages(isDark, fg, muted),
          ),

          // ── Attachments strip ──────────────────────────────────────────
          if (_agentAttachments.isNotEmpty)
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: inputBg,
                border: Border(top: BorderSide(color: borderC)),
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _agentAttachments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final att = _agentAttachments[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xff3a3a3a)
                          : const Color(0xffe0e0e0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Broken.document, size: 12, color: muted),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 80),
                        child: Text(
                          att['name'] ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: fg),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setState(
                            () => _agentAttachments.removeAt(i)),
                        child: Icon(Broken.close_square,
                            size: 11, color: muted),
                      ),
                    ]),
                  );
                },
              ),
            ),

          // ── Input box ──────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: inputBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Text field
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: TextField(
                    controller: _agentInputCtrl,
                    maxLines: 5,
                    minLines: 1,
                    style: TextStyle(fontSize: 13, color: fg),
                    decoration: InputDecoration(
                      hintText: _agentChatMode == 'agent'
                          ? 'Décrivez la tâche à réaliser…'
                          : _agentChatMode == 'ask'
                              ? 'Posez votre question…'
                              : 'Écrivez un message…',
                      hintStyle: TextStyle(fontSize: 13, color: muted),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _agentSend(),
                  ),
                ),

                // Bottom toolbar
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                  child: Row(children: [
                    // ── Attachment button ──────────────────────────────
                    Tooltip(
                      message: 'Joindre un fichier',
                      child: InkWell(
                        onTap: () async {
                          final res = await FilePicker.platform.pickFiles(
                            allowMultiple: true,
                            type: FileType.any,
                          );
                          if (res != null && res.files.isNotEmpty) {
                            setState(() {
                              for (final f in res.files) {
                                _agentAttachments.add({
                                  'name': f.name,
                                  'path': f.path ?? '',
                                });
                              }
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Broken.paperclip, size: 16, color: muted),
                        ),
                      ),
                    ),

                    // ── Voice button ───────────────────────────────────
                    Tooltip(
                      message: 'Dicter (micro)',
                      child: InkWell(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Dictée vocale — bientôt disponible.',
                                style: TextStyle(fontSize: 13),
                              ),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Broken.microphone, size: 16, color: muted),
                        ),
                      ),
                    ),

                    const SizedBox(width: 4),

                    // ── Model selector pill ────────────────────────────
                    GestureDetector(
                      onTap: () => _showAgentModelSheet(
                          context, appTheme, allModelIds, aiState),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xff3a3a3a)
                              : const Color(0xffe0e0e0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Broken.cpu, size: 11, color: muted),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 90),
                            child: Text(
                              modelDisplayName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Broken.arrow_down_2, size: 10, color: muted),
                        ]),
                      ),
                    ),

                    const Spacer(),

                    // ── Send / Stop ────────────────────────────────────
                    if (_agentGenerating)
                      GestureDetector(
                        onTap: _agentStop,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Broken.stop_circle,
                              size: 18, color: Colors.red[400]),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: _agentSend,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _agentInputCtrl.text.trim().isEmpty
                                ? Colors.transparent
                                : _kAccent.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Broken.send_2,
                            size: 18,
                            color: _agentInputCtrl.text.trim().isEmpty
                                ? muted
                                : Colors.white,
                          ),
                        ),
                      ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom sheet — choose AI model for this conversation.
  void _showAgentModelSheet(
    BuildContext context,
    AppTheme appTheme,
    List<String> modelIds,
    AIState aiState,
  ) {
    final isDark  = appTheme.isDark;
    final bg      = isDark ? const Color(0xff252526) : const Color(0xfffafafa);
    final fg      = isDark ? Colors.grey[300]! : Colors.grey[800]!;
    final muted   = isDark ? Colors.grey[500]! : Colors.grey[500]!;
    final borderC = isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd);

    showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: muted.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Choisir un modèle',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: fg)),
            ),
            const Divider(height: 1),
            if (modelIds.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Broken.cpu, size: 28, color: muted),
                    const SizedBox(height: 10),
                    Text(
                      'Aucun modèle configuré.\nOuvrez Paramètres → IA pour en ajouter un.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _push(context, const Settings());
                      },
                      icon: Icon(Broken.setting_2, size: 15, color: _kAccent),
                      label: const Text('Ouvrir Paramètres',
                          style: TextStyle(color: _kAccent)),
                    ),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: modelIds.length,
                  itemBuilder: (_, i) {
                    final id = modelIds[i];
                    final cfg = aiState.config[id] as Map<String, dynamic>?;
                    final name = cfg?['modelName'] as String? ?? id;
                    final provider = cfg?['provider'] as String? ?? '';
                    final isSelected = (_agentSelectedModelId == id) ||
                        (_agentSelectedModelId == null &&
                            aiState.modelSelected['chat'] == id);
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        _providerIcon(provider),
                        size: 18,
                        color: isSelected ? _kAccent : muted,
                      ),
                      title: Text(name,
                          style: TextStyle(
                              fontSize: 13,
                              color: fg,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal)),
                      subtitle: provider.isNotEmpty
                          ? Text(provider,
                              style:
                                  TextStyle(fontSize: 11, color: muted))
                          : null,
                      trailing: isSelected
                          ? Icon(Broken.tick_circle,
                              size: 16, color: _kAccent)
                          : null,
                      onTap: () {
                        setState(() => _agentSelectedModelId = id);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            // Add model shortcut
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _push(context, const Settings());
                },
                icon: Icon(Broken.add_circle, size: 14, color: _kAccent),
                label: const Text('Ajouter un modèle',
                    style: TextStyle(color: _kAccent, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: borderC),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns a representative icon for a given provider string.
  IconData _providerIcon(String provider) {
    final p = provider.toLowerCase();
    if (p.contains('openai') || p.contains('gpt')) return Broken.global;
    if (p.contains('claude') || p.contains('anthropic')) return Broken.cpu;
    if (p.contains('gemini') || p.contains('google')) return Broken.global_search;
    if (p.contains('grok')) return Broken.code_circle;
    if (p.contains('deepseek')) return Broken.search_normal;
    if (p.contains('mistral')) return Broken.wind;
    if (p.contains('local') || p.contains('llama')) return Broken.cpu_setting;
    return Broken.cpu;
  }

  Widget _buildAgentEmptyState(bool isDark, Color muted, Color fg) {
    const suggestions = [
      'Explique ce code',
      'Crée un fichier Flutter',
      'Optimise cette fonction',
      'Écris des tests unitaires',
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      children: [
        // Logo + title
        Center(
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/icons/app-icon.png',
                  width: 52, height: 52, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: _kAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Broken.message_programming,
                        color: _kAccent, size: 28),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Panda Agent',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: fg)),
              const SizedBox(height: 6),
              Text(
                'Comment puis-je vous aider ?',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Mode description
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kAccent.withOpacity(isDark ? 0.08 : 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kAccent.withOpacity(0.2)),
          ),
          child: Row(children: [
            Icon(
              _agentChatMode == 'agent'
                  ? Broken.cpu_setting
                  : _agentChatMode == 'ask'
                      ? Broken.message_question
                      : Broken.message_text,
              size: 16, color: _kAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _agentChatMode == 'agent'
                    ? 'Mode Agent — exécute des tâches de code autonomes.'
                    : _agentChatMode == 'ask'
                        ? 'Mode Ask — répond à vos questions sur le code.'
                        : 'Mode Normal — conversation libre avec le modèle.',
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[300]! : Colors.grey[700]!),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        // Suggestion chips
        Text('SUGGESTIONS',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: suggestions.map((s) => GestureDetector(
            onTap: () {
              _agentInputCtrl.text = s;
              _agentSend();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xff2d2d2d)
                    : const Color(0xffe8e8e8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: isDark
                        ? const Color(0xff3a3a3a)
                        : const Color(0xffdddddd)),
              ),
              child: Text(s,
                  style: TextStyle(fontSize: 12, color: fg)),
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildAgentMessages(bool isDark, Color fg, Color muted) {
    return ListView.builder(
      controller: _agentScrollCtrl,
      padding: const EdgeInsets.all(12),
      itemCount: _agentMessages.length,
      itemBuilder: (_, i) {
        final msg    = _agentMessages[i];
        final isMe   = msg['role'] == 'user';
        final phase  = msg['phase'] as String? ?? 'done';
        final text   = msg['text'] as String? ?? '';
        final think  = msg['thinking'] as String? ?? '';
        final isStreaming = phase == 'streaming';
        final isError     = phase == 'error';

        if (isMe) {
          return Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              constraints: const BoxConstraints(maxWidth: 260),
              decoration: BoxDecoration(
                color: _kAccent.withOpacity(0.85),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(text,
                  style:
                      const TextStyle(fontSize: 13, color: Colors.white)),
            ),
          );
        }

        // ── Message agent ─────────────────────────────────────────────
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Phase chip (thinking / streaming)
                if (isStreaming && think.isNotEmpty)
                  _AgentPhaseChip(
                      phase: AgentPhase.thinking, isDark: isDark),
                if (isStreaming && think.isEmpty)
                  _AgentPhaseChip(
                      phase: AgentPhase.streaming, isDark: isDark),

                // Thinking block (collapsible)
                if (think.isNotEmpty)
                  _ThinkingBlock(
                      thinking: think, isDark: isDark, fg: fg, muted: muted),

                // Bulle réponse
                if (text.isNotEmpty || isStreaming)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isError
                          ? Colors.red.withOpacity(isDark ? 0.2 : 0.1)
                          : (isDark
                              ? const Color(0xff2d2d2d)
                              : const Color(0xffe8e8e8)),
                      borderRadius: BorderRadius.circular(8),
                      border: isError
                          ? Border.all(
                              color: Colors.red.withOpacity(0.4), width: 1)
                          : null,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            text.isEmpty && isStreaming ? ' ' : text,
                            style: TextStyle(
                                fontSize: 13,
                                color: isError ? Colors.red[400] : fg),
                          ),
                        ),
                        if (isStreaming) ...[
                          const SizedBox(width: 2),
                          _BlinkingCursor(color: fg),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _agentHdrBtn(
          IconData icon, String tooltip, Color color, VoidCallback onTap) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(icon, size: 15, color: color),
          ),
        ),
      );

  void _agentScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_agentScrollCtrl.hasClients) {
        _agentScrollCtrl.animateTo(
          _agentScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Builds a [Models] instance from a raw AI config map (mirrors ui_state.dart logic).
  Models? _modelFromAiConfig(Map<String, dynamic> cfg) {
    final provider  = (cfg['provider'] ?? cfg['apiProvider'] ?? '').toString();
    final apiKey    = (cfg['apiKey'] ?? '').toString();
    final modelName = (cfg['modelName'] ?? cfg['model'] ?? '').toString();

    switch (provider) {
      case 'Gemini':    return Gemini(apiKey: apiKey, model: modelName);
      case 'Claude':    return Claude(apiKey: apiKey, model: modelName);
      case 'OpenAI':    return OpenAI(apiKey: apiKey, model: modelName);
      case 'Grok':      return Grok(apiKey: apiKey, model: modelName);
      case 'DeepSeek':  return DeepSeek(apiKey: apiKey, model: modelName);
      case 'TogetherAI':return TogetherAi(apiKey: apiKey, model: modelName);
      case 'Perplexity':return Perplexity(apiKey: apiKey, model: modelName);
      case 'OpenRouter':return OpenRouter(apiKey: apiKey, model: modelName);
      case 'FireWorks': return FireWorks(apiKey: apiKey, model: modelName);
      case 'LocalLlama':
        final mp = (cfg['modelPath'] ?? '').toString().trim();
        if (mp.isEmpty) return null;
        return LocalLlama(
          modelPath: mp,
          displayName: modelName.isNotEmpty ? modelName : mp.split('/').last,
          threads: (cfg['threads'] as num?)?.toInt() ?? 4,
          contextSize: (cfg['contextSize'] as num?)?.toInt() ?? 4096,
          gpuLayers: (cfg['gpuLayers'] as num?)?.toInt() ?? 0,
        );
      case 'Custom':
        final url = (cfg['url'] ?? '').toString().trim();
        if (url.isEmpty) return null;
        final parsedHeaders = <String, String>{};
        final hdrs = cfg['headers'];
        if (hdrs is Map) {
          hdrs.forEach((k, v) {
            if (k != null && v != null) parsedHeaders[k.toString()] = v.toString();
          });
        }
        if (apiKey.isNotEmpty && !parsedHeaders.containsKey('Authorization')) {
          parsedHeaders['Authorization'] = 'Bearer $apiKey';
        }
        return CustomModel(
          url: url,
          httpMethod: (cfg['httpMethod'] ?? 'POST').toString(),
          toolCallingMethod: ToolCallingMethod.openAiCompatible,
          customHeaders: parsedHeaders,
          requestBuilder: (code, instruction) => {
            if (modelName.isNotEmpty) 'model': modelName,
            'messages': [
              {'role': 'system', 'content': instruction},
              {'role': 'user', 'content': code},
            ],
          },
          customParser: (resp) => resp?.toString() ?? '',
        );
    }
    return null;
  }

  void _agentStop() {
    _agentRunner.cancel();
    if (!mounted) return;
    setState(() {
      _agentGenerating = false;
      _agentPhase = AgentPhase.idle;
      if (_agentMessages.isNotEmpty &&
          _agentMessages.last['role'] == 'agent' &&
          _agentMessages.last['phase'] == 'streaming') {
        _agentMessages.last['phase'] = 'done';
      }
    });
  }

  void _agentSend() {
    final text = _agentInputCtrl.text.trim();
    if (text.isEmpty || _agentGenerating) return;

    // Récupère le modèle sélectionné dans le panel (ou le chatModel par défaut)
    final aiState = context.read<AIBloc>().state;

    // Priorité : modèle choisi dans le panel > chatModel de l'AIBloc
    Models? model;
    if (_agentSelectedModelId != null &&
        aiState.config.containsKey(_agentSelectedModelId)) {
      final cfg = aiState.config[_agentSelectedModelId!];
      if (cfg is Map<String, dynamic>) {
        model = _modelFromAiConfig(cfg);
      }
    }
    model ??= aiState.chatModel;

    if (model == null) {
      setState(() {
        _agentMessages.add({'role': 'user', 'text': text});
        _agentMessages.add({
          'role': 'agent',
          'text':
              'Aucun modèle IA configuré. Ouvrez Paramètres (⚙) pour en ajouter un.',
          'thinking': '',
          'phase': 'error',
        });
        _agentInputCtrl.clear();
      });
      _agentScrollToBottom();
      return;
    }

    // Construit l'historique au format OpenAI
    final history = _agentMessages
        .where((m) =>
            (m['role'] == 'user' || m['role'] == 'agent') &&
            (m['text'] as String).isNotEmpty)
        .map((m) => {
              'role': m['role'] == 'user' ? 'user' : 'assistant',
              'content': m['text'] as String,
            })
        .toList();
    final messages = [...history, {'role': 'user', 'content': text}];

    setState(() {
      _agentMessages.add({'role': 'user', 'text': text});
      _agentMessages.add({
        'role': 'agent',
        'text': '',
        'thinking': '',
        'phase': 'streaming',
      });
      _agentInputCtrl.clear();
      _agentGenerating  = true;
      _agentPhase       = AgentPhase.streaming;
      _agentThinkingBuf = '';
      _agentStreamBuf   = '';
    });

    final agentIdx = _agentMessages.length - 1;

    _agentRunner
        .run(model: model, messages: messages)
        .listen(
          (chunk) {
            if (!mounted) return;
            setState(() {
              switch (chunk.phase) {
                case AgentPhase.thinking:
                  _agentPhase = AgentPhase.thinking;
                  _agentThinkingBuf += chunk.text;
                  _agentMessages[agentIdx]['thinking'] = _agentThinkingBuf;
                case AgentPhase.streaming:
                  _agentPhase = AgentPhase.streaming;
                  _agentStreamBuf += chunk.text;
                  _agentMessages[agentIdx]['text'] = _agentStreamBuf;
                case AgentPhase.done:
                  _agentPhase = AgentPhase.done;
                  _agentGenerating = false;
                  _agentMessages[agentIdx]['phase'] = 'done';
                case AgentPhase.error:
                  _agentPhase = AgentPhase.error;
                  _agentGenerating = false;
                  _agentMessages[agentIdx]['text'] =
                      _agentStreamBuf.isNotEmpty
                          ? _agentStreamBuf
                          : 'Erreur : ${chunk.text}';
                  _agentMessages[agentIdx]['phase'] = 'error';
                case AgentPhase.idle:
                  break;
              }
            });
            _agentScrollToBottom();
          },
          onError: (e) {
            if (!mounted) return;
            setState(() {
              _agentGenerating = false;
              _agentPhase      = AgentPhase.error;
              _agentMessages[agentIdx]['text'] = 'Erreur : $e';
              _agentMessages[agentIdx]['phase'] = 'error';
            });
          },
        );
  }

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

// ── _TabDef ───────────────────────────────────────────────────────────────────
    class _TabDef {
    final String   id;
    final String   title;
    final IconData icon;
    const _TabDef({required this.id, required this.title, required this.icon});
    }

    // ── _ActivityBtnEx (theme-aware) ──────────────────────────────────────────────
    class _ActivityBtnEx extends StatelessWidget {
    final _RailItem    item;
    final bool         selected;
    final Color        iconColor;
    final Color        selColor;
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
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              border: selected
                  ? Border(left: BorderSide(color: selColor, width: 2))
                  : null,
            ),
            child: Center(
              child: Icon(item.icon, size: 22,
                  color: selected ? selColor : iconColor),
            ),
          ),
        ),
      );
    }
    }

    // ── _ActivityBtn (legacy alias) ───────────────────────────────────────────────
    class _ActivityBtn extends StatelessWidget {
    final _RailItem    item;
    final bool         selected;
    final VoidCallback onTap;
    const _ActivityBtn(
        {required this.item, required this.selected, required this.onTap});

    @override
    Widget build(BuildContext context) {
      return _ActivityBtnEx(
        item:      item,
        selected:  selected,
        iconColor: _kActivityIconDark,
        selColor:  _kActivitySelDark,
        onTap:     onTap,
      );
    }
    }

    // ── _GithubAvatarEx (theme-aware) ─────────────────────────────────────────────
    class _GithubAvatarEx extends StatelessWidget {
    final Color        iconColor;
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

    // ── _GithubAvatar (legacy alias) ──────────────────────────────────────────────
    class _GithubAvatar extends StatelessWidget {
    final VoidCallback onTap;
    const _GithubAvatar({required this.onTap});

    @override
    Widget build(BuildContext context) {
      return _GithubAvatarEx(iconColor: _kActivityIconDark, onTap: onTap);
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

// ─────────────────────────────────────────────────────────────────────────────
// Panda Agent — helper widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Bloc de pensée collapsible (extended thinking / reasoning).
class _ThinkingBlock extends StatefulWidget {
  final String  thinking;
  final bool    isDark;
  final Color   fg;
  final Color   muted;
  const _ThinkingBlock({
    required this.thinking,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark
        ? const Color(0xff2a2a3a)
        : const Color(0xfff0f0ff);
    final border = widget.isDark
        ? const Color(0xff4a4a6a)
        : const Color(0xffbbbbdd);

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border, width: 1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Broken.message_tick,
                  size: 12, color: widget.muted),
              const SizedBox(width: 6),
              Text('Réflexion interne',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: widget.muted)),
              const Spacer(),
              Icon(
                _expanded ? Broken.arrow_up_2 : Broken.arrow_down_2,
                size: 12,
                color: widget.muted,
              ),
            ]),
            if (_expanded) ...[
              const SizedBox(height: 6),
              Text(widget.thinking,
                  style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: widget.fg.withOpacity(0.7))),
            ],
          ],
        ),
      ),
    );
  }
}

/// Indicateur de phase (thinking / streaming) affiché au-dessus de la bulle.
class _AgentPhaseChip extends StatelessWidget {
  final AgentPhase phase;
  final bool       isDark;
  const _AgentPhaseChip({required this.phase, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final (String label, IconData icon, Color color) = switch (phase) {
      AgentPhase.thinking  => ('Réflexion\u2026',  Broken.cpu,        Colors.purple),
      AgentPhase.streaming => ('Génération\u2026', Broken.edit_2,     _kAccent),
      AgentPhase.error     => ('Erreur',            Broken.danger,     Colors.red),
      _                    => ('',                  Broken.tick_circle, Colors.green),
    };
    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color)),
      ]),
    );
  }
}

/// Curseur clignotant animé pendant le streaming.
class _BlinkingCursor extends StatefulWidget {
  final Color color;
  const _BlinkingCursor({required this.color});

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>    _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0, end: 1).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 2,
        height: 13,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
