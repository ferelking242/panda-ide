import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, SystemUiOverlayStyle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:panda/bloc/repo_bloc/repo_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/broken_icons.dart';
import '../ui/panda_surface.dart';
import 'about.dart';
import 'donation_page.dart';
import 'file_manager.dart';
import 'editor_page.dart';
import 'menu_screen.dart';
// downloads.dart kept for GgufDownloadManager + backward compat; navigation redirected to MarketplacePage
import 'downloads.dart';
import 'settings.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../terminal/terminal.dart';
import '../utils/ai.dart';
import '../utils/copilot_chat.dart';
import '../ui/contribute.dart';
import '../ui/github_page.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/languages.dart';
import '../utils/panda_log.dart';
import '../utils/themes.dart';
import '../services/android_update_service.dart';
import '../extensions/ui/marketplace_page.dart';
import '../extensions/ui/extensions_panel.dart';
import '../extensions/ui/extension_webview.dart';
import '../ui/gateway_panel.dart';
import '../ui/browser/browser_panel.dart';
import 'agent_runner.dart';
import 'agent_settings.dart';
import '../local_models/ui/local_models_page.dart'
    if (dart.library.html) '../local_models/ui/local_models_page_web.dart';
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

class _SelectTypeState extends State<SelectType>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  final _scaffoldKey         = GlobalKey<ScaffoldState>();
  final createFileController = TextEditingController();
  final _createFileKey       = GlobalKey<FormState>();
  AnimationStatus _terminalSelectionStatus = AnimationStatus.dismissed;
  bool _didShowPackageUpdateToast  = false;
  bool _didShowStorageMigrationToast = false;
  bool _didCheckAndroidUpdate = false;
  bool _checkingPendingSharedFile  = false;
  int  _pendingSharedFileRetryCount = 0;

  // Active activity-bar item (0 = none/welcome)
  int _activeRail = 0;
  // Sidebar state: 0=closed 1=icons-only(default) 2=extended panel
  int  _sidebarState     = 1;
  bool _rightPanelOpen   = false;
  bool _bottomPanelOpen  = false;
  int  _bottomPanelTab   = 0; // 0=Terminal 1=Problems 2=Output 3=Debug

  // Problems panel state
  final _problemsSearchCtrl = TextEditingController();
  String _problemsSearch    = '';
  int    _problemsFilter    = 0; // 0=all 1=errors 2=warnings

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

  // ── Editor tabs data (file/folder/project content for tabs) ──
  final Map<String, _EditorTabConfig> _editorTabs = {};
  late final MultiSplitViewController _splitViewController;

  // ── Panda Agent chat ─────────────────────────────────────────────
  final _agentInputCtrl  = TextEditingController();
  final _agentScrollCtrl = ScrollController();
  final List<Map<String,dynamic>> _agentMessages = [];

  // ── Agent AI state ────────────────────────────────────────────────
  AgentPhase _agentPhase        = AgentPhase.idle;
  bool       _agentGenerating   = false;
  String     _agentThinkingBuf  = '';
  String     _agentStreamBuf    = '';
  String     _agentCurrentTool  = '';
  final      _agentRunner       = AgentRunner();
  int        _agentRequestSerial = 0;

  // ── Agent UI state ───────────────────────────────────────────────
  /// 'ask' | 'agent' | 'plan'
  String _agentChatMode      = 'ask';
  final List<Map<String,String>> _agentAttachments = [];

  // ── Floating agent overlay ────────────────────────────────────────
  bool   _agentFloating      = false;
  Offset _agentFloatOffset   = const Offset(20, 100);
  bool   _agentFloatStickLeft = false;

  // ── Send button animation ─────────────────────────────────────────
  late AnimationController _sendAnimCtrl;
  late Animation<double>   _sendAnim;

  // ── Theme fade animation ──────────────────────────────────────────
  late AnimationController _themeAnimCtrl;
  late Animation<double>   _themeAnim;

  // ── Conversation history ──────────────────────────────────────────
  bool _showHistoryPanel = false;

  // ── Conversation title (editable) ────────────────────────────────
  String _agentConversationTitle = 'Nouvelle conversation';

  // ── Last resolved AI model (used for title generation) ───────────
  Models? _lastUsedModel;

  // ── Panel tabs (0=Chat, 1=Tool, 2=Task, 3=UserSettings, 4=Providers) ─
  int _agentPanelTab     = 0;
  int _agentPanelPrevTab = 0;

  // ── Background tasks ──────────────────────────────────────────────
  final List<Map<String, dynamic>> _agentTasks = [];
  bool   _agentTasksShowNew = true;

  // ── Tools search ──────────────────────────────────────────────────
  String _agentToolsSearch = '';
  final _agentToolsSearchCtrl = TextEditingController();

  // ── Approval mode ─────────────────────────────────────────────────
  String _agentApprovalMode    = 'default'; // 'default'|'bypass'|'autopilot'
  bool   _agentSandboxTerminal = true;

  // ── User Settings ─────────────────────────────────────────────────
  bool   _usAudioNotif          = true;
  bool   _usPushNotif           = true;
  bool   _usAutoPreview         = true;
  String _usForwardPorts        = 'all ports except localhost';
  String _usFontSize            = 'normal';
  bool   _usAgentExpanded       = true;
  bool   _usPreviewExpanded     = true;
  bool   _usAppearanceExpanded  = true;
  bool   _usCodeEditExpanded    = false;
  bool   _usAdvancedExpanded    = false;

  // ── Sidebar search ────────────────────────────────────────────────
  final _sidebarSearchCtrl = TextEditingController();
  List<File> _sidebarSearchResults = [];
  bool _sidebarSearching = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _splitViewController = MultiSplitViewController(areas: [Area(), Area()]);
    // Send button pulse animation
    _sendAnimCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat();
    _sendAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _sendAnimCtrl, curve: Curves.easeInOut));
    _sendAnimCtrl.stop();
    // Theme fade animation
    _themeAnimCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 250))
      ..value = 1.0;
    _themeAnim = CurvedAnimation(parent: _themeAnimCtrl, curve: Curves.easeInOut);
    // Rebuild send button colour when text changes
    _agentInputCtrl.addListener(() => setState(() {}));
    // Load chat sessions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openPendingSharedFile();
      _maybeShowStorageMigrationNotice();
      _checkForAndroidUpdate();
      context.read<ChatSessionBloc>().add(LoadChatSessions());
    });
  }

  Future<void> _checkForAndroidUpdate() async {
    if (_didCheckAndroidUpdate) return;
    _didCheckAndroidUpdate = true;
    try {
      final update = await AndroidUpdateService.checkForUpdate();
      if (!mounted || update == null) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Mise à jour disponible'),
          content: Text(
            'Panda IDE ${update.version} (build ${update.buildNumber}) est disponible.\n\n'
            'Version installée : $appVersion (build $appBuildNumber)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Plus tard'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                try {
                  await AndroidUpdateService.install(update);
                } catch (error) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Mise à jour impossible : $error')),
                  );
                }
              },
              child: const Text('Installer'),
            ),
          ],
        ),
      );
    } catch (error) {
      PandaLog.w('PandaAgent', 'Android update check failed: $error');
    }
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
    _sidebarSearchCtrl.dispose();
    _splitViewController.dispose();
    _sendAnimCtrl.dispose();
    _themeAnimCtrl.dispose();
    _problemsSearchCtrl.dispose();
    super.dispose();
  }

  // ── Pending shared file ────────────────────────────────────────────────────
  Future<void> _openPendingSharedFile() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return; // NativeChannel is currently Android-only.
    }
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
      _openEditorTab(
        file:            imported,
        rootDir:         imported.parent.path,
        languageDetails: language,
        isProject:       false,
      );
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
    {
    String? branch,
    int? depth,
    bool recursive = false,
    }
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
          _openEditorTab(
            rootDir:   targetDir.path,
            isProject: true,
            isCloned:  true,
          );
        }
      }
      return;
    }
    try {
      await cloneRepo(
        projectDir,
        repoUrl,
        (p) => progressController.add(p),
        branch: branch,
        depth: depth,
        recursive: recursive,
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        _openEditorTab(
          rootDir:   targetDir.path,
          isProject: true,
          isCloned:  true,
        );
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
                      // On web, use the platform-compatible dir from setupFilesDir()
                      // instead of the Android-specific filesDir constant.
                      final String targetDir;
                      if (kIsWeb) {
                        final d = await setupFilesDir();
                        targetDir = d.path;
                      } else {
                        targetDir = filesDir;
                      }
                      final file = await createFile(
                          createFileController.text, targetDir, context);
                      if (file != null && context.mounted) {
                        Navigator.of(ctx).pop();
                        final lang = languages.firstWhere(
                          (l) => l.extension.contains(
                              path.extension(file.path).replaceFirst('.', '')),
                          orElse: () => languages[0],
                        );
                        _openEditorTab(
                          file:            file,
                          rootDir:         file.parent.path,
                          languageDetails: lang,
                          isProject:       false,
                        );
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
    _openEditorTab(
      file:            file,
      rootDir:         file.parent.path,
      languageDetails: lang,
      isProject:       false,
    );
  }

  Future<void> _doOpenFolder(BuildContext context, AppTheme appTheme) async {
    // Folder picking via Android SAF is not available on web.
    if (kIsWeb) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: appTheme.isDark
                ? const Color(0xff2b2b2b)
                : Colors.white,
            title: const Text('Non disponible sur le web'),
            content: const Text(
                'L\'ouverture de dossiers n\'est pas supportée sur la version web. '
                'Utilisez l\'application Android pour gérer des projets complets.'),
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
      _openEditorTab(
        rootDir:   dir.path,
        isProject: true,
        isCloned:  false,
      );
    }
  }

  void _doCloneRepo(BuildContext context, AppTheme appTheme) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final cloneCtrl = TextEditingController();
        final branchCtrl = TextEditingController();
        final depthCtrl = TextEditingController(text: '1');
        final nameCtrl = TextEditingController();
        var source = 'github';
        var advanced = false;
        var shallow = true;
        var recursive = false;

        String repoNameFromUrl(String value) {
          final cleaned = value.trim().replaceFirst(RegExp(r'/$'), '');
          if (cleaned.isEmpty) return '';
          final lastPart = cleaned.split('/').last;
          return lastPart.replaceFirst(RegExp(r'\.git$'), '');
        }

        String normalizedUrl() {
          final value = cloneCtrl.text.trim();
          if (value.isEmpty) return '';
          if (source == 'github' &&
              !value.startsWith('http') &&
              !value.startsWith('git@')) {
            return 'https://github.com/${value.replaceFirst(RegExp(r'^/+'), '')}.git';
          }
          if (source == 'gitlab' &&
              !value.startsWith('http') &&
              !value.startsWith('git@')) {
            return 'https://gitlab.com/${value.replaceFirst(RegExp(r'^/+'), '')}.git';
          }
          return value;
        }

        String sourceHint() {
          switch (source) {
            case 'gitlab':
              return 'group/projet ou https://gitlab.com/groupe/projet.git';
            case 'url':
              return 'https://example.com/organisation/projet.git';
            default:
              return 'organisation/projet ou https://github.com/organisation/projet.git';
          }
        }

        Future<void> startClone() async {
          final url = normalizedUrl();
          if (url.isEmpty) return;
          final name = nameCtrl.text.trim().isEmpty
              ? repoNameFromUrl(url)
              : nameCtrl.text.trim();
          if (name.isEmpty) return;

          final parsedDepth = int.tryParse(depthCtrl.text.trim());
          if (shallow && (parsedDepth == null || parsedDepth < 1)) return;

          final progressCtrl = StreamController<double>.broadcast();
          if (!dialogContext.mounted) return;
          Navigator.of(dialogContext).pop();
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
                    final p = (snap.data ?? 0.0).clamp(0.0, 1.0).toDouble();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Broken.programming_arrows,
                            color: _kAccent, size: 32),
                        const SizedBox(height: 16),
                        Text(
                          'Clonage de $name…',
                          style: TextStyle(
                            color: appTheme.selectScreenCardTextColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        LinearPercentIndicator(
                          percent: p,
                          progressColor: _kAccent,
                          barRadius: const Radius.circular(20),
                          lineHeight: 8,
                          trailing: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Text(
                              '${(p * 100).toStringAsFixed(1)}%',
                              style: TextStyle(
                                  color: appTheme.selectScreenCardTextColor),
                            ),
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
            projectDir,
            url,
            name,
            context,
            progressCtrl,
            branch: advanced && branchCtrl.text.trim().isNotEmpty
                ? branchCtrl.text.trim()
                : null,
            depth: advanced && shallow ? parsedDepth : null,
            recursive: advanced && recursive,
          );
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 520,
            padding: const EdgeInsets.all(24),
            decoration: _dialogBox(appTheme.isDark),
            child: StatefulBuilder(
              builder: (context, setDialogState) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _dialogHeader(
                      appTheme, Broken.programming_arrows, 'Cloner un dépôt'),
                  const SizedBox(height: 18),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'github', label: Text('GitHub')),
                      ButtonSegment(value: 'gitlab', label: Text('GitLab')),
                      ButtonSegment(value: 'url', label: Text('URL')),
                    ],
                    selected: {source},
                    onSelectionChanged: (value) =>
                        setDialogState(() => source = value.first),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: cloneCtrl,
                    autofocus: true,
                    style: TextStyle(
                        color: appTheme.selectScreenCardTextColor),
                    cursorColor: _kAccent,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: source == 'url'
                          ? 'URL du dépôt'
                          : 'Chemin du dépôt',
                      hintText: sourceHint(),
                      prefixIcon: Icon(
                        source == 'github'
                            ? Icons.code
                            : source == 'gitlab'
                                ? Icons.source
                                : Icons.link,
                        size: 18,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    style: TextStyle(
                        color: appTheme.selectScreenCardTextColor),
                    decoration: const InputDecoration(
                      labelText: 'Nom du dossier (optionnel)',
                      hintText: 'Déduit automatiquement du dépôt',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setDialogState(() => advanced = !advanced),
                      icon: Icon(advanced
                          ? Icons.expand_less
                          : Icons.expand_more),
                      label: const Text('Options avancées'),
                    ),
                  ),
                  if (advanced) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: branchCtrl,
                            style: TextStyle(
                                color:
                                    appTheme.selectScreenCardTextColor),
                            decoration: const InputDecoration(
                              labelText: 'Branche',
                              hintText: 'main',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Clone superficiel'),
                            subtitle: const Text('Historique limité'),
                            value: shallow,
                            onChanged: (value) =>
                                setDialogState(() => shallow = value),
                          ),
                        ),
                      ],
                    ),
                    if (shallow)
                      TextField(
                        controller: depthCtrl,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                            color: appTheme.selectScreenCardTextColor),
                        decoration: const InputDecoration(
                          labelText: 'Profondeur de l’historique',
                          hintText: '1',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Inclure les sous-modules Git'),
                      value: recursive,
                      onChanged: (value) =>
                          setDialogState(() => recursive = value ?? false),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _cancelBtn(dialogContext),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: _primaryBtn(),
                        onPressed: cloneCtrl.text.trim().isEmpty
                            ? null
                            : startClone,
                        child: const Text('Cloner',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
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
    return BlocConsumer<AppThemeBloc, AppThemeState>(
      listenWhen: (prev, cur) => prev.appTheme != cur.appTheme,
      listener: (context, state) => _themeAnimCtrl.forward(from: 0.0),
      builder: (context, appThemestate) {
        final appTheme = appThemestate.appTheme;
        return FadeTransition(
          opacity: _themeAnim,
          child: BlocListener<PackageCatalogCubit, PackageCatalogState>(
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
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  appTheme.isDark ? Brightness.light : Brightness.dark,
            ),
            child: Scaffold(
            key: _scaffoldKey,
            resizeToAvoidBottomInset: false,
            backgroundColor: appTheme.isDark ? const Color(0xff3c3c3c) : const Color(0xffdedede),

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
              child: Stack(
                children: [
              Column(
                children: [
                  // ── Top bar spans full width ──────────────────────────
                  _buildTopBar(context, appTheme, appThemestate),

                  // ── Below top bar: activity bar (full-height) | editor + panel ─
                  Expanded(
                    child: Row(
                      children: [
                        // Activity bar — full height, spans editor AND terminal
                        if (_sidebarState >= 1)
                          _buildActivityBar(context, appTheme),

                        // ── Right side: editor stacked above bottom panel ──
                        Expanded(
                          child: Stack(
                            children: [
                              Column(
                                children: [
                                  // ── Editor area ──────────────────────────────
                                  Expanded(
                                    child: ClipSmoothRect(
                                      radius: _sidebarState >= 1
                                          ? SmoothBorderRadius.only(
                                              topLeft: SmoothRadius(
                                                  cornerRadius: 22,
                                                  cornerSmoothing: 0.6),
                                              bottomLeft: _bottomPanelOpen
                                                  ? const SmoothRadius(
                                                      cornerRadius: 0,
                                                      cornerSmoothing: 0)
                                                  : SmoothRadius(
                                                      cornerRadius: 22,
                                                      cornerSmoothing: 0.6))
                                          : SmoothBorderRadius.zero,
                                      child: Container(
                                      color: appTheme.scaffoldBg,
                                      child: Row(
                                      children: [
                                        Expanded(
                                          child: _splitEditor
                                              ? MultiSplitView(
                                                  controller: _splitViewController,
                                                  builder: (context, area) {
                                                    if (area.index == 0) {
                                                      return Column(
                                                        children: [
                                                          _buildTabBar(appTheme,
                                                              isPrimary: true),
                                                          Expanded(
                                                            child: _buildActiveTab(
                                                                context,
                                                                appTheme,
                                                                appThemestate),
                                                          ),
                                                        ],
                                                      );
                                                    }
                                                    return Column(
                                                      children: [
                                                        _buildTabBar(appTheme,
                                                            isPrimary: false),
                                                        Expanded(
                                                          child: _buildSplitActiveTab(
                                                              context,
                                                              appTheme,
                                                              appThemestate),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                )
                                              : Column(
                                                  children: [
                                                    _buildTabBar(appTheme,
                                                        isPrimary: true),
                                                    Expanded(
                                                      child: AnimatedSwitcher(
                                                        duration: const Duration(milliseconds: 150),
                                                        child: KeyedSubtree(
                                                          key: ValueKey(_activeTabIdx),
                                                          child: _buildActiveTab(context,
                                                              appTheme, appThemestate),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                        ),
                                        // Panda Agent panel
                                        if (_rightPanelOpen)
                                          BlocProvider(
                                            create: (_) => AIChatUIBloc(),
                                            child: Builder(
                                              builder: (panelContext) =>
                                                  _buildPandaAgentPanel(
                                                    panelContext, appTheme),
                                            ),
                                          ),
                                      ],
                                    ),
                                    ),
                                    ),
                                  ),
                                  // ── Bottom panel — stays right of activity bar ──
                                  if (_bottomPanelOpen)
                                    _buildBottomPanel(),
                                ],
                              ),

                              // ── Sidebar overlay (no layout push) ────────────────
                              if (_sidebarState == 2)
                                Positioned(
                                  left: 0,
                                  top: 36,   // starts below the dongle tab bar (35px + 1px divider)
                                  bottom: 0,
                                  child: Material(
                                    elevation: 6,
                                    shadowColor: Colors.black45,
                                    child: SizedBox(
                                      width: _kSidebarWidth,
                                      child: _buildSidebarPanel(context, appTheme),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
// ── Status bar ────────────────────────────────────────
                  _buildStatusBar(context, appTheme,
                      sidebarActive: _sidebarState >= 1),
                ],
              ),
              // ── Floating agent overlay ──────────────────────────────
              if (_agentFloating)
                _buildFloatingAgentOverlay(appTheme),
                ],
              ),
            ),
          ),
            ),
          ),
        );
      },
    );
  }


  // ── VSCode-style status bar ────────────────────────────────────────────────
  Widget _buildStatusBar(
    BuildContext context,
    AppTheme appTheme, {
    bool sidebarActive = false,
  }) {
    final isDark  = appTheme.isDark;
    final actBg   = isDark ? _kActivityBgDark : _kActivityBgLight;
    final editorBg = isDark ? appTheme.scaffoldBg : appTheme.scaffoldBg;
    final fg      = isDark ? _kActivitySelDark : _kActivitySelLight;

    return BlocBuilder<RepoStatusBloc, RepoStatusState>(
      builder: (ctx, repoState) {
        final hasProject = repoState is RepoStatusLoaded &&
            (repoState.currentBranch?.isNotEmpty ?? false);
        final branch = hasProject ? repoState.currentBranch! : null;

        // Errors / warnings are 0 for now (will be wired to language diagnostics)
        const int errors   = 0;
        const int warnings = 0;

        // ── Editor portion of the bar (right of activity bar) ─────────
        final editorBar = ClipRRect(
          borderRadius: sidebarActive
              ? const BorderRadius.only(topLeft: Radius.circular(20))
              : BorderRadius.zero,
          child: Container(
            height: 22,
            color: actBg,
            padding: EdgeInsets.only(left: sidebarActive ? 14 : 6, right: 6),
            child: Row(children: [
              // ── Left: remote / branch ───────────────────────────────
              if (branch != null)
                _StatusBarItem(
                  icon: Icons.call_split_rounded,
                  label: branch,
                  fg: fg,
                  onTap: () {},
                )
              else
                // VSCode-style "><" remote / open button
                Builder(builder: (bCtx) => InkWell(
                  onTap: () => _showWorkspaceMenu(bCtx, isDark, appTheme),
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.chevron_right, size: 13, color: fg),
                      Icon(Icons.chevron_left, size: 13, color: fg),
                    ]),
                  ),
                )),

              const SizedBox(width: 6),

              // ── Left: problems ──────────────────────────────────────
              _StatusBarItem(
                icon: Icons.cancel_outlined,
                label: '$errors',
                fg: errors > 0 ? Colors.red[300]! : fg,
                onTap: () => setState(() {
                  _bottomPanelOpen = true;
                  _bottomPanelTab  = 1;
                }),
              ),
              const SizedBox(width: 2),

              // ── Left: warnings ──────────────────────────────────────
              _StatusBarItem(
                icon: Icons.warning_amber_outlined,
                label: '$warnings',
                fg: warnings > 0 ? Colors.orange[300]! : fg,
                onTap: () => setState(() {
                  _bottomPanelOpen = true;
                  _bottomPanelTab  = 1;
                }),
              ),

              const Spacer(),

              // ── Right: Panda AI icon ────────────────────────────────
              _StatusBarItem(
                icon: Broken.magic_star,
                label: '',
                fg: _rightPanelOpen ? _kAccent : fg,
                onTap: () => setState(() => _rightPanelOpen = !_rightPanelOpen),
              ),
              const SizedBox(width: 2),

              // ── Right: terminal ─────────────────────────────────────
              _StatusBarItem(
                icon: Icons.terminal,
                label: '',
                fg: _bottomPanelOpen ? _kAccent : fg,
                onTap: () => setState(() {
                  _bottomPanelOpen = true;
                  _bottomPanelTab  = 0;
                }),
              ),
              const SizedBox(width: 2),

              // ── Right: notifications ────────────────────────────────
              _StatusBarItem(
                icon: Icons.notifications_none,
                label: '',
                fg: fg,
                onTap: () {},
              ),
            ]),
          ),
        );

        if (!sidebarActive) return SizedBox(height: 22, child: editorBar);

        // Two-tone: activity-bar block | rounded editor bar
        return SizedBox(
          height: 22,
          child: Row(children: [
            // Activity bar segment (flat, same bg, no radius)
            Container(width: 48, height: 22, color: actBg),
            // Editor bar with rounded top-left corner
            Expanded(child: editorBar),
          ]),
        );
      },
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeIn), child: child),
    ));
  }

  void _openAgentSettingsTab() {
    setState(() {
      if (!_openTabs.any((t) => t.id == 'agent-settings')) {
        _openTabs.add(const _TabDef(
          id:    'agent-settings',
          title: 'Paramètres Agent',
          icon:  Broken.cpu_setting,
        ));
      }
      _activeTabIdx = _openTabs.indexWhere((t) => t.id == 'agent-settings');
    });
  }

  void _openAgentTab() {
    setState(() {
      final existing = _openTabs.indexWhere((tab) => tab.id == 'agent');
      if (existing == -1) {
        _openTabs.add(const _TabDef(
          id: 'agent',
          title: 'Panda Agent',
          icon: Broken.magic_star,
        ));
        _activeTabIdx = _openTabs.length - 1;
      } else {
        _activeTabIdx = existing;
      }
      _sidebarState = 1;
      _activeRail = 0;
    });
  }

  // ── Open a file / folder / project as a tab in the new Panda IDE UI ──────
  // ── Active editor helpers ─────────────────────────────────────────────────
  _EditorTabConfig? _activeEditorConfig() {
    if (_openTabs.isEmpty) return null;
    final tab = _openTabs[_activeTabIdx];
    return _editorTabs[tab.id];
  }

  String? _activeProjectDir() {
    final cfg = _activeEditorConfig();
    return (cfg != null && cfg.isProject) ? cfg.rootDir : null;
  }

  void _openGithubTab() {
    setState(() {
      if (!_openTabs.any((t) => t.id == 'github')) {
        _openTabs.add(const _TabDef(
            id: 'github', title: 'GitHub', icon: Broken.programming_arrows));
        _activeTabIdx = _openTabs.length - 1;
      } else {
        _activeTabIdx = _openTabs.indexWhere((t) => t.id == 'github');
      }
    });
  }

  // This replaces all Navigator.push(EditorPage(...)) calls so that files and
  // projects open inside the tab system instead of the old full-screen Panda UI.
  void _openEditorTab({
    File?     file,
    required String    rootDir,
    Language? languageDetails,
    bool      isProject = false,
    bool      isCloned  = false,
  }) {
    final tabId = isProject
        ? 'editor:dir:$rootDir'
        : 'editor:file:${file?.path ?? rootDir}';
    final tabTitle = isProject
        ? path.basename(rootDir)
        : (file != null ? path.basename(file.path) : path.basename(rootDir));
    const tabIcon = Broken.document_text;

    setState(() {
      if (!_openTabs.any((t) => t.id == tabId)) {
        _openTabs.add(_TabDef(id: tabId, title: tabTitle, icon: tabIcon));
        _editorTabs[tabId] = _EditorTabConfig(
          file:            file,
          rootDir:         rootDir,
          languageDetails: languageDetails,
          isProject:       isProject,
          isCloned:        isCloned,
        );
      }
      _activeTabIdx = _openTabs.indexWhere((t) => t.id == tabId);
      // Make sure the sidebar collapses so the editor gets full width.
      if (_sidebarState == 2) _sidebarState = 1;
      _activeRail = 0;
    });
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
        _RailItem(icon: Broken.cpu,                 label: 'Gateway AI',       idx: 7),
        _RailItem(icon: Broken.global,              label: 'Navigateur',        idx: 8),
        _RailItem(icon: Broken.message_programming, label: 'GitHub Copilot',    idx: 9),
        _RailItem(icon: Broken.magic_star,          label: 'Panda Agent',       idx: 10),
        _RailItem(icon: Broken.cpu_setting,         label: 'Local Models',      idx: 11),
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
                  selected:  _sidebarState == 2 && _activeRail == item.idx,
                  iconColor: iconColor,
                  selColor:  selColor,
                  onTap: () {
                    // Marketplace (idx:6) opens as an editor tab, not sidebar
                    if (item.idx == 6) {
                      setState(() {
                        if (!_openTabs.any((t) => t.id == 'marketplace')) {
                          _openTabs.add(const _TabDef(
                              id:    'marketplace',
                              title: 'Extensions',
                              icon:  Broken.shop));
                          _activeTabIdx = _openTabs.length - 1;
                        } else {
                          _activeTabIdx =
                              _openTabs.indexWhere((t) => t.id == 'marketplace');
                        }
                        _sidebarState = 1;
                        _activeRail = 0;
                      });
                      return;
                    }
                    // Gateway AI (idx:7) opens as an editor tab, not sidebar
                    if (item.idx == 7) {
                      setState(() {
                        if (!_openTabs.any((t) => t.id == 'gateway')) {
                          _openTabs.add(const _TabDef(
                              id:    'gateway',
                              title: 'Gateway AI',
                              icon:  Broken.cpu));
                          _activeTabIdx = _openTabs.length - 1;
                        } else {
                          _activeTabIdx =
                              _openTabs.indexWhere((t) => t.id == 'gateway');
                        }
                        _sidebarState = 1;
                        _activeRail = 0;
                      });
                      return;
                    }
                    // Navigateur (idx:8) opens as an editor tab, not sidebar
                    if (item.idx == 8) {
                      setState(() {
                        if (!_openTabs.any((t) => t.id == 'browser')) {
                          _openTabs.add(const _TabDef(
                              id:    'browser',
                              title: 'Navigateur',
                              icon:  Broken.global));
                          _activeTabIdx = _openTabs.length - 1;
                        } else {
                          _activeTabIdx =
                              _openTabs.indexWhere((t) => t.id == 'browser');
                        }
                        _sidebarState = 1;
                        _activeRail = 0;
                      });
                      return;
                    }
                    // Copilot is a real sidebar panel: its controls must stay
                    // reachable after the extension has been installed.
                    if (item.idx == 9) {
                      setState(() {
                        _activeRail = 9;
                        _sidebarState = 2;
                      });
                      _ensureCopilotInitialized();
                      return;
                    }
                    // Panda Agent always opens directly in the editor.
                    if (item.idx == 10) {
                      _openAgentTab();
                      return;
                    }
                    // Local Models opens as an editor tab.
                    if (item.idx == 11) {
                      setState(() {
                        if (!_openTabs.any((t) => t.id == 'local_models')) {
                          _openTabs.add(const _TabDef(
                              id:    'local_models',
                              title: 'Local Models',
                              icon:  Broken.cpu_setting));
                          _activeTabIdx = _openTabs.length - 1;
                        } else {
                          _activeTabIdx =
                              _openTabs.indexWhere((t) => t.id == 'local_models');
                        }
                        _sidebarState = 1;
                        _activeRail   = 0;
                      });
                      return;
                    }
                    setState(() {
                      if (_activeRail == item.idx && _sidebarState == 2) {
                        _sidebarState = 1;
                        _activeRail = 0;
                      } else {
                        _activeRail = item.idx;
                        _sidebarState = 2;
                      }
                    });
                  },
                )),

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
                onTap: () {
                  setState(() {
                    if (!_openTabs.any((t) => t.id == 'github')) {
                      _openTabs.add(const _TabDef(
                          id:    'github',
                          title: 'GitHub',
                          icon:  Broken.programming_arrows));
                      _activeTabIdx = _openTabs.length - 1;
                    } else {
                      _activeTabIdx =
                          _openTabs.indexWhere((t) => t.id == 'github');
                    }
                  });
                },
              ),
            ),

            _ActivityBtnEx(
              item:      _RailItem(icon: Broken.settings, label: 'Parametres', idx: 99),
              selected:  false,
              iconColor: iconColor,
              selColor:  selColor,
              onTap: () {
                setState(() {
                  if (!_openTabs.any((t) => t.id == 'settings')) {
                    _openTabs.add(const _TabDef(
                        id:    'settings',
                        title: 'Paramètres',
                        icon:  Broken.settings));
                    _activeTabIdx = _openTabs.length - 1;
                  } else {
                    _activeTabIdx =
                        _openTabs.indexWhere((t) => t.id == 'settings');
                  }
                });
              },
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
      9: 'GITHUB COPILOT',
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
      case 9: // GitHub Copilot
        panelBody = _sidebarCopilot(context, appTheme, isDark);
        break;
      default:
        panelBody = const SizedBox.shrink();
    }

    return PhysicalShape(
      color: bg,
      elevation: 6,
      shadowColor: Colors.black38,
      clipper: _SidebarClipper(),
      child: SizedBox(
        width: _kSidebarWidth,
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
                      _sidebarState = 1;
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
      ),
    );
  }

  // ── Explorer panel ────────────────────────────────────────────────────────
  Widget _sidebarExplorer(BuildContext ctx, AppTheme t, bool dark) {
    final activeProjPath = _activeProjectDir();

    if (activeProjPath != null) {
      // Active project → show full file tree
      return DirectoryTreeViewerCustom(
        rootPath: activeProjPath,
        appTheme: t,
        isUnfoldedFirst: true,
        enableCreateFileOption: true,
        enableCreateFolderOption: true,
        enableDeleteFileOption: true,
        enableDeleteFolderOption: true,
        enableRenameFileOption: true,
        enableRenameFolderOption: true,
        enableGitFeatures: true,
        fileIconBuilder: (extension) =>
            _buildExplorerFileIcon(extension, t),
        onFileTap: (file) {
          final lang = languages.firstWhere(
            (l) => l.extension.contains(
                path.extension(file.path).replaceFirst('.', '')),
            orElse: () => languages[0],
          );
          _openEditorTab(
            file:            file,
            rootDir:         activeProjPath,
            languageDetails: lang,
            isProject:       false,
          );
        },
      );
    }

    // No active project → show open/clone actions + recent projects
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _panelItem(ctx, t, Broken.document_text, 'Nouveau fichier…',
            () => _doNewFile(ctx, t)),
        _panelItem(ctx, t, Broken.document_upload, 'Ouvrir un fichier…',
            () => _doOpenFile(ctx)),
        _panelItem(ctx, t, Broken.folder_open, 'Ouvrir un dossier…',
            () => _doOpenFolder(ctx, t)),
        _panelItem(ctx, t, Broken.programming_arrows, 'Cloner un dépôt…',
            () => _doCloneRepo(ctx, t)),
        _panelItem(ctx, t, Broken.folder_2, 'Gestionnaire de fichiers',
            () => _push(ctx, const FileManagerPage())),
        const Divider(indent: 12, endIndent: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text('PROJETS RÉCENTS',
              style: _kSectionTitle.copyWith(
                  color: dark ? Colors.grey[500] : Colors.grey[600])),
        ),
        FutureBuilder<List<Directory>>(
          future: Future(() async {
            final d = Directory(projectDir); // global constant from constants.dart
            if (!d.existsSync()) return [];
            final entities = await d.list().toList();
            final dirs = entities.whereType<Directory>().toList()
              ..sort((a, b) =>
                  b.statSync().modified.compareTo(a.statSync().modified));
            return dirs.take(8).toList();
          }),
          builder: (_, snap) {
            if (!snap.hasData || snap.data!.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text('Aucun projet récent.',
                    style: TextStyle(
                        fontSize: 12,
                        color: dark ? Colors.grey[600] : Colors.grey[500])),
              );
            }
            return Column(
              children: snap.data!
                  .map((dir) => _panelItem(
                        ctx, t, Broken.folder_open,
                        path.basename(dir.path),
                        () => _openEditorTab(
                          rootDir:   dir.path,
                          isProject: true,
                          isCloned:  false,
                        ),
                      ))
                  .toList(),
            );
          },
        ),
        const Divider(indent: 12, endIndent: 12),
        _panelItem(ctx, t, Broken.document_download, 'Téléchargements',
            () => _push(ctx, const MarketplacePage())),
      ],
    );
  }

  Widget _buildExplorerFileIcon(String extension, AppTheme theme) {
    final normalizedExtension =
        extension.toLowerCase().replaceFirst('.', '');
    Language? language;
    for (final candidate in languages) {
      if (candidate.extension.any(
          (item) => item.toLowerCase() == normalizedExtension)) {
        language = candidate;
        break;
      }
    }
    final icon = language?.icon;
    if (icon is Widget) {
      return SizedBox(
        width: 16,
        height: 16,
        child: FittedBox(fit: BoxFit.contain, child: icon),
      );
    }
    if (icon is IconData) {
      return Icon(icon, size: 16, color: theme.selectScreenCardTextColor);
    }
    return Icon(Icons.insert_drive_file_outlined,
        size: 16, color: theme.selectScreenCardTextColor.withOpacity(0.65));
  }

  // ── Search panel ──────────────────────────────────────────────────────────
  Widget _sidebarSearch(BuildContext ctx, AppTheme t, bool dark) {
    final activeDir = _activeProjectDir();

    Future<void> runSearch(String query) async {
      if (query.trim().isEmpty || activeDir == null) {
        if (mounted) setState(() { _sidebarSearchResults = []; _sidebarSearching = false; });
        return;
      }
      if (mounted) setState(() => _sidebarSearching = true);
      final results = <File>[];
      try {
        await for (final entity in Directory(activeDir)
            .list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final name = path.basename(entity.path).toLowerCase();
            if (name.contains(query.toLowerCase())) {
              results.add(entity);
              if (results.length >= 50) break;
            }
          }
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _sidebarSearchResults = results;
          _sidebarSearching = false;
        });
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            controller: _sidebarSearchCtrl,
            autofocus: false,
            style: TextStyle(
                color: dark ? Colors.grey[300] : Colors.grey[800],
                fontSize: 13),
            cursorColor: _kAccent,
            onChanged: runSearch,
            decoration: InputDecoration(
              hintText: activeDir != null
                  ? 'Rechercher des fichiers…'
                  : 'Ouvrez un projet d\'abord',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
              prefixIcon:
                  const Icon(Icons.search, size: 16, color: Colors.grey),
              isDense: true,
              filled: true,
              fillColor: dark ? const Color(0xff3c3c3c) : Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                    color: dark
                        ? const Color(0xff555555)
                        : const Color(0xffcccccc)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: _kAccent),
              ),
            ),
          ),
        ),
        if (_sidebarSearching)
          const LinearProgressIndicator(
              color: _kAccent, backgroundColor: Colors.transparent),
        Expanded(
          child: _sidebarSearchResults.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Text(
                    activeDir != null
                        ? (_sidebarSearchCtrl.text.isEmpty
                            ? 'Saisissez un nom de fichier pour rechercher.'
                            : 'Aucun résultat.')
                        : 'Ouvrez un dossier ou un projet pour lancer la recherche.',
                    style: TextStyle(
                        fontSize: 12,
                        color:
                            dark ? Colors.grey[500] : Colors.grey[600]),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: _sidebarSearchResults.length,
                  itemBuilder: (_, i) {
                    final file = _sidebarSearchResults[i];
                    return _panelItem(
                      ctx, t,
                      Broken.document_text,
                      path.basename(file.path),
                      () {
                        final lang = languages.firstWhere(
                          (l) => l.extension.contains(path
                              .extension(file.path)
                              .replaceFirst('.', '')),
                          orElse: () => languages[0],
                        );
                        _openEditorTab(
                          file:            file,
                          rootDir:         activeDir!,
                          languageDetails: lang,
                          isProject:       false,
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Git panel ─────────────────────────────────────────────────────────────
  Widget _sidebarGit(BuildContext ctx, AppTheme t, bool dark) {
    final activeDir = _activeProjectDir();
    if (activeDir == null) {
      // No project open → keep the source-control entry points available.
      return _gitEntryPoints(ctx, t, dark);
    }

    // Keep the complete source-control experience in the Panda sidebar:
    // staging, commit actions, sync, and the commit graph all live here.
    final isGitRepo = Directory('$activeDir/.git').existsSync();
    return Column(
      children: [
        Expanded(
          child: SourceControl(
            appTheme: t,
            workSpace: activeDir,
            isRepoThere: isGitRepo,
          ),
        ),
        const Divider(height: 1, indent: 12, endIndent: 12),
        _panelItem(ctx, t, Broken.add_circle, 'Cloner un dépôt…',
            () => _doCloneRepo(ctx, t)),
      ],
    );
  }

  Widget _gitEntryPoints(BuildContext ctx, AppTheme t, bool dark) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _panelItem(ctx, t, Broken.programming_arrows, 'Ouvrir GitHub',
            _openGithubTab),
        _panelItem(ctx, t, Broken.add_circle, 'Cloner un dépôt…',
            () => _doCloneRepo(ctx, t)),
        BlocBuilder<GithubAuthCubit, GithubAuthState>(
          builder: (_, s) => s.isSignedIn
              ? _panelItem(ctx, t, Broken.add_square, 'Créer un dépôt…',
                  _openGithubTab)
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
                onTap: () => _push(ctx, const MarketplacePage()),
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
        _panelItem(ctx, t, Broken.shop, 'Parcourir les extensions', () {
          setState(() {
            if (!_openTabs.any((tab) => tab.id == 'marketplace')) {
              _openTabs.add(const _TabDef(
                  id: 'marketplace',
                  title: 'Extensions',
                  icon: Broken.shop));
              _activeTabIdx = _openTabs.length - 1;
            } else {
              _activeTabIdx =
                  _openTabs.indexWhere((tab) => tab.id == 'marketplace');
            }
            _sidebarState = 1;
            _activeRail = 0;
          });
        }),
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
            () => _push(ctx, const MarketplacePage())),
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

  void _ensureCopilotInitialized() {
    if (kIsWeb) return;
    final copilotBloc = context.read<CopilotBloc>();
    if (copilotBloc.state.isInitialized ||
        copilotBloc.state.status == CopilotStatus.initializing ||
        copilotBloc.state.status == CopilotStatus.signingIn) {
      return;
    }
    if (!Directory('$extensionDir/copilot-language-server').existsSync() ||
        !File('$binDir/node').existsSync()) {
      return;
    }
    copilotBloc.add(CopilotInitialize(
      configPath: filesDir,
      workspacePath: homeDir,
    ));
  }

  void _openCopilotChatTab() {
    setState(() {
      final existing = _openTabs.indexWhere((tab) => tab.id == 'copilot-chat');
      if (existing == -1) {
        _openTabs.add(const _TabDef(
          id: 'copilot-chat',
          title: 'Copilot Chat',
          icon: Broken.message_programming,
        ));
        _activeTabIdx = _openTabs.length - 1;
      } else {
        _activeTabIdx = existing;
      }
      _sidebarState = 1;
      _activeRail = 0;
    });
  }

  Widget _buildCopilotChatPage() {
    // AIChat already contains the Copilot model selector, conversation history,
    // streaming responses and Agent/Ask modes. These two blocs are local to
    // this standalone tab; the shared AIBloc/Copilot blocs come from main().
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => AIChatBloc()),
        BlocProvider(create: (_) => AIChatUIBloc()),
      ],
      child: AIChat(
        filePath: homeDir,
        workspacePath: homeDir,
      ),
    );
  }

  Widget _sidebarCopilot(BuildContext ctx, AppTheme t, bool dark) {
    final fg = dark ? Colors.grey[200]! : Colors.grey[850]!;
    final muted = dark ? Colors.grey[500]! : Colors.grey[600]!;
    final card = dark ? const Color(0xff2d2d2d) : Colors.white;
    final border = dark ? const Color(0xff424242) : const Color(0xffdddddd);
    final extensionInstalled =
        kIsWeb || Directory('$extensionDir/copilot-language-server').existsSync();
    final nodeInstalled = kIsWeb || File('$binDir/node').existsSync();

    return BlocBuilder<CopilotBloc, CopilotState>(
      builder: (context, state) {
        final canSignIn = extensionInstalled &&
            nodeInstalled &&
            state.isInitialized &&
            state.status != CopilotStatus.initializing &&
            state.status != CopilotStatus.signingIn;
        final statusLabel = switch (state.status) {
          CopilotStatus.signedIn => state.user == null
              ? 'Connecté à GitHub Copilot'
              : 'Connecté en tant que ${state.user}',
          CopilotStatus.signingIn => 'Connexion à GitHub…',
          CopilotStatus.initializing => 'Démarrage du serveur…',
          CopilotStatus.notAuthorized => 'Compte sans accès Copilot',
          CopilotStatus.error => 'Erreur du serveur Copilot',
          CopilotStatus.notSignedIn => 'Extension prête — connexion requise',
          CopilotStatus.notInitialized => 'Prêt à être configuré',
        };
        final statusColor = switch (state.status) {
          CopilotStatus.signedIn => Colors.green,
          CopilotStatus.error || CopilotStatus.notAuthorized => Colors.orange,
          CopilotStatus.initializing || CopilotStatus.signingIn => _kAccent,
          _ => muted,
        };

        return ListView(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  SvgPicture.asset(
                    'assets/icons/github-copilot-icon.svg',
                    width: 28,
                    height: 28,
                    colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('GitHub Copilot',
                            style: TextStyle(
                                color: fg,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(statusLabel,
                            style: TextStyle(color: statusColor, fontSize: 10),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _copilotRequirementRow(
              icon: Broken.box,
              label: 'Extension Copilot',
              ok: extensionInstalled,
              fg: fg,
            ),
            _copilotRequirementRow(
              icon: Broken.code,
              label: 'Runtime Node.js',
              ok: nodeInstalled,
              fg: fg,
            ),
            const SizedBox(height: 8),
            if (!extensionInstalled || !nodeInstalled)
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(dark ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
                ),
                child: Text(
                  !extensionInstalled && !nodeInstalled
                      ? 'Installez l’extension Copilot et Node.js depuis la Marketplace.'
                      : !extensionInstalled
                          ? 'Installez l’extension Copilot depuis la Marketplace.'
                          : 'Installez le runtime Node.js depuis la Marketplace.',
                  style: TextStyle(color: dark ? Colors.orange[300] : Colors.orange[800], fontSize: 11),
                ),
              ),
            if (!extensionInstalled || !nodeInstalled) const SizedBox(height: 8),
            if (!extensionInstalled || !nodeInstalled)
              _copilotActionButton(
                label: 'Ouvrir la Marketplace',
                icon: Broken.shop,
                onPressed: () => setState(() {
                  _activeRail = 6;
                  _sidebarState = 2;
                }),
                fg: fg,
                border: border,
              ),
            if (extensionInstalled && nodeInstalled && !state.isInitialized)
              _copilotActionButton(
                label: 'Démarrer Copilot',
                icon: Broken.refresh,
                onPressed: _ensureCopilotInitialized,
                fg: fg,
                border: border,
              ),
            if (canSignIn && !state.isSignedIn)
              _copilotActionButton(
                label: state.status == CopilotStatus.error
                    ? 'Réessayer la connexion'
                    : 'Se connecter avec GitHub',
                icon: Broken.login,
                onPressed: state.status == CopilotStatus.error
                    ? _ensureCopilotInitialized
                    : () => context
                        .read<CopilotBloc>()
                        .add(CopilotSignInInitiate()),
                fg: fg,
                border: border,
              ),
            if (state.signInPayload?.userCode != null) ...[
              const SizedBox(height: 7),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: _kAccent.withOpacity(dark ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Code GitHub',
                        style: TextStyle(color: muted, fontSize: 10)),
                    const SizedBox(height: 3),
                    SelectableText(
                      state.signInPayload!.userCode!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: fg,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ouvrez github.com/login/device, saisissez ce code, puis confirmez.',
                      style: TextStyle(color: muted, fontSize: 10),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(
                                  text: state.signInPayload!.userCode!));
                            },
                            child: const Text('Copier',
                                style: TextStyle(fontSize: 11)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final uri = Uri.parse(
                                state.signInPayload!.verificationUri ??
                                    'https://github.com/login/device',
                              );
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            child: const Text(
                              'Ouvrir GitHub',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => context.read<CopilotBloc>().add(
                                CopilotSignInConfirm(
                                    state.signInPayload!.userCode!)),
                            child: const Text('Confirmer',
                                style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (state.isSignedIn) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _copilotActionButton(
                      label: 'Ouvrir le chat',
                      icon: Broken.message_text,
                      onPressed: _openCopilotChatTab,
                      fg: fg,
                      border: border,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: state.isEnabled ? 'Désactiver' : 'Activer',
                    onPressed: () => context.read<CopilotBloc>().add(
                        CopilotSetEnabled(!state.isEnabled)),
                    icon: Icon(
                      state.isEnabled ? Icons.toggle_on : Icons.toggle_off,
                      color: state.isEnabled ? Colors.green : muted,
                    ),
                  ),
                ],
              ),
              Text(
                state.isEnabled
                    ? 'Les suggestions inline sont activées dans l’éditeur.'
                    : 'Les suggestions inline sont désactivées.',
                style: TextStyle(color: muted, fontSize: 10),
              ),
              const SizedBox(height: 5),
              TextButton(
                onPressed: () =>
                    context.read<CopilotBloc>().add(CopilotSignOut()),
                child: const Text('Se déconnecter',
                    style: TextStyle(fontSize: 11)),
              ),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 7),
              Text(state.error!,
                  style: const TextStyle(color: Colors.red, fontSize: 10),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
            const Divider(height: 22),
            Text(
              'Ce que fait cette intégration',
              style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              '• Complétions de code inline dans l’éditeur\n'
              '• Chat Copilot avec les modèles disponibles\n'
              '• Modes Ask et Agent dans le panneau de chat\n'
              '• Node.js requis pour le language server\n\n'
              'Ce n’est pas Codespaces : Panda ne fournit pas un environnement cloud GitHub complet. '
              'Copilot fournit l’assistance de code, tandis que Node.js exécute son serveur local.',
              style: TextStyle(color: muted, fontSize: 10, height: 1.35),
            ),
          ],
        );
      },
    );
  }

  Widget _copilotRequirementRow({
    required IconData icon,
    required String label,
    required bool ok,
    required Color fg,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: ok ? Colors.green : Colors.orange),
          const SizedBox(width: 7),
          Expanded(child: Text(label, style: TextStyle(color: fg, fontSize: 11))),
          Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded,
              size: 14, color: ok ? Colors.green : Colors.orange),
        ],
      ),
    );
  }

  Widget _copilotActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required Color fg,
    required Color border,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          alignment: Alignment.centerLeft,
        ),
      ),
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

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar(
        BuildContext context, AppTheme appTheme, AppThemeState appThemestate) {
      final isDark = appTheme.isDark;
      final fg     = isDark ? Colors.grey[400]! : Colors.grey[700]!;
      final bg     = isDark ? const Color(0xff3c3c3c) : const Color(0xffdedede);
      final boxBg  = isDark ? const Color(0xff3a3a3a) : const Color(0xfff5f5f5);
      final boxBdr = isDark ? const Color(0xff666666) : const Color(0xffbbbbbb);
      final nameFg = isDark ? Colors.grey[200]! : Colors.grey[800]!;

      return Container(
        height: 35,
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            // ── LEFT: logo + "Panda" ─────────────────────────
            ClipOval(
              child: Image.asset(
                'assets/icons/app-icon.png',
                width: 18, height: 18, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Text('🐼', style: TextStyle(fontSize: 14)),
              ),
            ),
            const SizedBox(width: 5),
            Text('Panda',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: nameFg)),
            const SizedBox(width: 4),

            // ── CENTER: ← [workspace box] → ──────────────────────────────
            Expanded(
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _hdrBtn(Broken.arrow_left_2, 'Reculer', fg, () {}),
                    const SizedBox(width: 2),
                    Builder(builder: (ctx) => GestureDetector(
                      onTap: () => _showWorkspaceMenu(ctx, isDark, appTheme),
                      child: Container(
                        constraints: const BoxConstraints(
                            minWidth: 140, maxWidth: 260),
                        height: 24,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: boxBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: boxBdr, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Broken.folder_open, size: 13, color: fg),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'Espace de travail',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.grey[300]!
                                        : Colors.grey[700]!),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(Icons.keyboard_arrow_down,
                                size: 14, color: fg),
                          ],
                        ),
                      ),
                    )),
                    const SizedBox(width: 2),
                    _hdrBtn(Broken.arrow_right_3, 'Avancer', fg, () {}),
                  ],
                ),
              ),
            ),

            // ── RIGHT: 4 buttons ─────────────────────────────────────────
            // 1 — ouvrir/fermer le panneau gauche
            _hdrBtn(
              Broken.sidebar_left,
              _sidebarState == 2
                  ? 'Fermer le panneau gauche'
                  : 'Ouvrir le panneau gauche',
              _sidebarState == 2 ? _kAccent : fg,
              () => setState(() {
                if (_sidebarState == 2) {
                  _sidebarState = 1;
                  _activeRail = 0;
                } else {
                  _sidebarState = 2;
                  if (_activeRail == 0) _activeRail = 1;
                }
              }),
            ),
            // 2 — layout disposition menu
            Builder(
              builder: (ctx) => _hdrBtn(
                Broken.element_4,
                'Personnaliser la disposition',
                fg,
                () => _showLayoutMenu(ctx, isDark),
              ),
            ),
            // 3 — terminal / bottom panel
            _hdrBtn(
              Icons.terminal,
              'Terminal',
              _bottomPanelOpen ? _kAccent : fg,
              () => setState(() => _bottomPanelOpen = !_bottomPanelOpen),
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
              checked: _sidebarState == 2),
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
            if (_sidebarState == 2) {
              _sidebarState = 1; _activeRail = 0;
            } else {
              _sidebarState = 2;
              if (_activeRail == 0) _activeRail = 1;
            }
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

    // ── Hamburger cycle ──────────────────────────────────────────────────────
      void _cycleHamburger() {
        _sidebarState = (_sidebarState + 1) % 3;
        if (_sidebarState == 2 && _activeRail == 0) _activeRail = 1;
        if (_sidebarState == 0) _activeRail = 0;
      }

      // ── Workspace picker ─────────────────────────────────────────────────────
      void _showWorkspaceMenu(BuildContext ctx, bool isDark, AppTheme appTheme) {
        final fg = isDark ? Colors.grey[300]! : Colors.grey[800]!;
        final bg = isDark ? const Color(0xff252526) : const Color(0xfff3f3f3);
        final RenderBox box = ctx.findRenderObject()! as RenderBox;
        final Offset off = box.localToGlobal(Offset.zero);
        final pos = RelativeRect.fromLTRB(
            off.dx, off.dy + box.size.height, off.dx + box.size.width, 0);
        showMenu<String>(
          context: ctx,
          position: pos,
          color: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          items: [
            PopupMenuItem<String>(
              enabled: false, height: 28,
              child: Text('ESPACE DE TRAVAIL',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: isDark ? Colors.grey[500]! : Colors.grey[600]!)),
            ),
            PopupMenuItem<String>(value: 'open_folder', height: 32,
              child: Row(children: [
                Icon(Broken.folder_open, size: 15, color: fg),
                const SizedBox(width: 8),
                Text('Ouvrir un dossier…', style: TextStyle(fontSize: 13, color: fg)),
              ])),
            PopupMenuItem<String>(value: 'open_file', height: 32,
              child: Row(children: [
                Icon(Broken.document, size: 15, color: fg),
                const SizedBox(width: 8),
                Text('Ouvrir un fichier…', style: TextStyle(fontSize: 13, color: fg)),
              ])),
            PopupMenuItem<String>(value: 'new_project', height: 32,
              child: Row(children: [
                Icon(Broken.folder_add, size: 15, color: fg),
                const SizedBox(width: 8),
                Text('Nouveau projet…', style: TextStyle(fontSize: 13, color: fg)),
              ])),
          ],
        ).then((value) {
          if (value == null) return;
          if (value == 'open_folder') {
            _doOpenFolder(ctx, appTheme);
          } else if (value == 'open_file') {
            _doOpenFile(ctx);
          } else if (value == 'new_project') {
            _doOpenFolder(ctx, appTheme);
          }
        });
      }

      // ── Bottom panel (terminal / problems / output / debug) ──────────────────
      Widget _buildBottomPanel() {
        return BlocBuilder<AppThemeBloc, AppThemeState>(
          builder: (context, ts) {
            final isDark = ts.appTheme.isDark;
            final bg     = isDark ? const Color(0xff1e1e1e) : const Color(0xfffefefe);
            final tabBg  = isDark ? const Color(0xff252526) : const Color(0xffececec);
            final fg     = isDark ? Colors.grey[400]! : Colors.grey[600]!;
            final selFg  = isDark ? Colors.grey[200]! : Colors.grey[900]!;
            final border = isDark ? const Color(0xff444444) : const Color(0xffcccccc);
            const tabNames = ['TERMINAL', 'PROBLÈMES', 'SORTIE', 'CONSOLE DEBUG'];
            return Container(
              height: 220,
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: border))),
              child: Column(children: [
                // Tab strip
                Container(
                  height: 30,
                  color: tabBg,
                  child: Row(children: [
                    ...List.generate(tabNames.length, (i) {
                      final active = _bottomPanelTab == i;
                      return GestureDetector(
                        onTap: () => setState(() => _bottomPanelTab = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: active ? bg : Colors.transparent,
                            border: Border(
                              top: BorderSide(
                                  color: active ? _kAccent : Colors.transparent,
                                  width: 1),
                            ),
                          ),
                          child: Text(tabNames[i],
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: active ? selFg : fg)),
                        ),
                      );
                    }),
                    const Spacer(),
                    InkWell(
                      onTap: () => setState(() => _bottomPanelOpen = false),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Icon(Broken.close_circle, size: 14, color: fg),
                      ),
                    ),
                  ]),
                ),
                // ── Problems toolbar (search + filter + actions) ───────────
                if (_bottomPanelTab == 1)
                  Container(
                    height: 28,
                    decoration: BoxDecoration(
                      color: tabBg,
                      border: Border(bottom: BorderSide(color: border)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(children: [
                      // Search input
                      Expanded(
                        child: SizedBox(
                          height: 20,
                          child: TextField(
                            controller: _problemsSearchCtrl,
                            style: TextStyle(fontSize: 11, color: selFg),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              hintText: 'Filter (e.g. text, **/*.ts, !**/node_modules/**)',
                              hintStyle: TextStyle(fontSize: 11, color: fg),
                              prefixIcon: Icon(Icons.search, size: 12, color: fg),
                              prefixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 20),
                              filled: true,
                              fillColor: isDark ? const Color(0xff3c3c3c) : const Color(0xffe8e8e8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(2),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (v) => setState(() => _problemsSearch = v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Filter: errors only
                      _PanelToolbarBtn(
                        icon: Icons.cancel_outlined,
                        tooltip: 'Show Errors',
                        active: _problemsFilter == 1,
                        fg: fg, activeFg: Colors.red[300]!,
                        onTap: () => setState(() =>
                          _problemsFilter = _problemsFilter == 1 ? 0 : 1),
                      ),
                      // Filter: warnings only
                      _PanelToolbarBtn(
                        icon: Icons.warning_amber_outlined,
                        tooltip: 'Show Warnings',
                        active: _problemsFilter == 2,
                        fg: fg, activeFg: Colors.orange[300]!,
                        onTap: () => setState(() =>
                          _problemsFilter = _problemsFilter == 2 ? 0 : 2),
                      ),
                      // Collapse all
                      _PanelToolbarBtn(
                        icon: Icons.unfold_less,
                        tooltip: 'Collapse All',
                        active: false,
                        fg: fg, activeFg: fg,
                        onTap: () {},
                      ),
                      // Clear all
                      _PanelToolbarBtn(
                        icon: Icons.clear_all,
                        tooltip: 'Clear All',
                        active: false,
                        fg: fg, activeFg: fg,
                        onTap: () => setState(() {
                          _problemsSearch = '';
                          _problemsSearchCtrl.clear();
                          _problemsFilter = 0;
                        }),
                      ),
                      // More actions
                      _PanelToolbarBtn(
                        icon: Icons.more_horiz,
                        tooltip: 'More Actions',
                        active: false,
                        fg: fg, activeFg: fg,
                        onTap: () {},
                      ),
                    ]),
                  ),
                Expanded(
                  child: Container(
                    color: bg,
                    child: _buildBottomPanelContent(context, ts.appTheme, isDark),
                  ),
                ),
              ]),
            );
          },
        );
      }

      Widget _buildBottomPanelContent(
          BuildContext context, AppTheme appTheme, bool isDark) {
        final fg = isDark ? const Color(0xffcfcfcf) : const Color(0xff333333);
        switch (_bottomPanelTab) {
          case 0: // Terminal
            if (kIsWeb) {
              return Center(
                child: Text(
                  'Le terminal n\'est pas disponible dans la version web.',
                  style: TextStyle(fontSize: 12, color: fg),
                ),
              );
            }
            return EmbeddedTerminal(
              projectDir: '/',
              showKeyboardMenu: true,
            );
          case 1: // Problems
            return _ProblemsPanel(
              fg: fg,
              search: _problemsSearch,
              filter: _problemsFilter,
            );
          case 2: // Output
            return ListView(padding: const EdgeInsets.all(12), children: [
              Text('Pas de sortie.', style: TextStyle(fontSize: 12, color: fg)),
            ]);
          case 3: // Debug Console
            return ListView(padding: const EdgeInsets.all(12), children: [
              Text('Console de débogage vide.',
                  style: TextStyle(fontSize: 12, color: fg)),
            ]);
          default:
            return const SizedBox.shrink();
        }
      }

      // ── Tab bar ───────────────────────────────────────────────────────────────

  
  /// Returns the correct 13×13 icon widget for a dongle tab.
  /// For file-editor tabs the real language icon (SVG) is used.
  /// For all other tabs (Welcome, Agent, …) falls back to the IconData.
  Widget _buildTabIconWidget(_TabDef tab, Color color) {
    final cfg = _editorTabs[tab.id];
    if (cfg != null && cfg.languageDetails != null) {
      final langIcon = cfg.languageDetails!.icon;
      if (langIcon is Widget) {
        return SizedBox(
          width: 13,
          height: 13,
          child: FittedBox(fit: BoxFit.contain, child: langIcon),
        );
      }
    }
    return Icon(tab.icon, size: 13, color: color);
  }

  Widget _buildTabBar(AppTheme appTheme, {bool isPrimary = true}) {
    final isDark      = appTheme.isDark;
    final tabBg       = isDark ? _kTabBarDark    : _kTabBarLight;
    final activeTabBg = isDark ? _kTabActiveDark : _kTabActiveLight;
    final inactiveFg  = isDark ? Colors.grey[500]! : Colors.grey[600]!;
    final activeFg    = isDark ? Colors.grey[300]! : Colors.grey[800]!;
    final sepColor    = isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd);

    final tabs      = isPrimary ? _openTabs     : _splitTabs;
    final activeIdx = isPrimary ? _activeTabIdx : _splitTabIdx;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
      Container(
      height: 35,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: tabBg),
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
                    ),
                    child: Row(children: [
                      _buildTabIconWidget(tab, isActive ? activeFg : inactiveFg),
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
                            color: isActive
                                ? inactiveFg
                                : inactiveFg.withOpacity(0.3)),
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
          ])),
        ),
      ]),
    ),
    Divider(height: 1, thickness: 1, color: sepColor),
    ],
    );
  }

  void _closeSplitTab(int i) {
    setState(() {
      _splitTabs.removeAt(i);
      if (_splitTabs.isNotEmpty) {
        _splitTabIdx = (_splitTabIdx >= _splitTabs.length
                ? _splitTabs.length - 1
                : _splitTabIdx)
            .clamp(0, _splitTabs.length - 1);
      } else {
        _splitTabIdx = 0;
        _splitEditor = false; // ferme le split quand plus aucun onglet
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
            _editorTabs.clear(); // clean up all editor tab configs
            _openTabs.clear();
            _activeTabIdx = 0;
          } else {
            _splitTabs.clear();
            _splitTabIdx = 0;
            _splitEditor = false; // ferme le split quand tous les onglets sont fermés
          }
        });
      }
    });
  }

  Widget _buildSplitActiveTab(
      BuildContext context, AppTheme appTheme, AppThemeState appThemestate) {
    if (_splitTabs.isEmpty) {
      return _buildEmptyEditor(context, appTheme);
    }
    final tab = _splitTabs[_splitTabIdx];
    if (tab.id == 'welcome') {
      return _buildWelcomePage(context, appTheme, appThemestate);
    }
    if (tab.id == 'agent') {
      return BlocProvider(
        create: (_) => AIChatUIBloc(),
        child: Builder(
          builder: (panelContext) => _buildPandaAgentPanel(
            panelContext, appTheme, asPage: true),
        ),
      );
    }
    if (tab.id == 'copilot-chat') {
      return _buildCopilotChatPage();
    }
    if (tab.id == 'marketplace') {
      return const MarketplacePage(embedded: true);
    }
    if (tab.id == 'gateway') {
      return const GatewayPanel();
    }
    if (tab.id == 'browser') {
      return const BrowserPanel();
    }
    if (tab.id == 'github') {
      return GithubPage(embedded: true);
    }
    if (tab.id == 'settings') {
      return const Settings(embedded: true);
    }
    if (tab.id == 'agent-settings') {
      return BlocProvider(
        create: (_) => AIChatUIBloc(),
        child: const AgentSettings(embedded: true),
      );
    }
    if (tab.id == 'local_models') {
      return const LocalModelsPage(embedded: true);
    }
    // ── Editor tab: file / folder / project ──────────────────────────────────
    final editorCfg = _editorTabs[tab.id];
    if (editorCfg != null) {
      return EditorPage(
        key:             ValueKey(tab.id),
        file:            editorCfg.file,
        rootDir:         editorCfg.rootDir,
        languageDetails: editorCfg.languageDetails,
        isProject:       editorCfg.isProject,
        isCloned:        editorCfg.isCloned,
      );
    }
    return _buildWelcomePage(context, appTheme, appThemestate);
  }

  void _closeTab(int i) {
    setState(() {
      final removedId = _openTabs[i].id;
      _openTabs.removeAt(i);
      _editorTabs.remove(removedId);
      if (_openTabs.isEmpty) {
        _activeTabIdx = 0;
      } else if (i < _activeTabIdx) {
        // Tab before active closed: shift active index down
        _activeTabIdx = (_activeTabIdx - 1).clamp(0, _openTabs.length - 1);
      } else {
        // Tab at or after active: clamp to valid range
        _activeTabIdx = _activeTabIdx.clamp(0, _openTabs.length - 1);
      }
    });
  }

  Widget _buildActiveTab(
      BuildContext context, AppTheme appTheme, AppThemeState appThemestate) {
    if (_openTabs.isEmpty) {
      return _buildEmptyEditor(context, appTheme);
    }
    final tab = _openTabs[_activeTabIdx];
    if (tab.id == 'welcome') {
      return _buildWelcomePage(context, appTheme, appThemestate);
    }
    if (tab.id == 'agent') {
      return BlocProvider(
        create: (_) => AIChatUIBloc(),
        child: Builder(
          builder: (panelContext) => _buildPandaAgentPanel(
            panelContext, appTheme, asPage: true),
        ),
      );
    }
    if (tab.id == 'copilot-chat') {
      return _buildCopilotChatPage();
    }
    if (tab.id == 'marketplace') {
      return const MarketplacePage(embedded: true);
    }
    if (tab.id == 'gateway') {
      return const GatewayPanel();
    }
    if (tab.id == 'browser') {
      return const BrowserPanel();
    }
    if (tab.id == 'github') {
      return GithubPage(embedded: true);
    }
    if (tab.id == 'settings') {
      return const Settings(embedded: true);
    }
    if (tab.id == 'agent-settings') {
      return BlocProvider(
        create: (_) => AIChatUIBloc(),
        child: const AgentSettings(embedded: true),
      );
    }
    if (tab.id == 'local_models') {
      return const LocalModelsPage(embedded: true);
    }
    // ── Editor tab: file / folder / project ──────────────────────────────────
    final editorCfg = _editorTabs[tab.id];
    if (editorCfg != null) {
      return EditorPage(
        key:             ValueKey(tab.id),
        file:            editorCfg.file,
        rootDir:         editorCfg.rootDir,
        languageDetails: editorCfg.languageDetails,
        isProject:       editorCfg.isProject,
        isCloned:        editorCfg.isCloned,
      );
    }
    return _buildWelcomePage(context, appTheme, appThemestate);
  }

  // ── Panda Agent panel ─────────────────────────────────────────────────────
  Widget _buildPandaAgentPanel(BuildContext context, AppTheme appTheme,
      {bool asPage = false}) {
    final isDark  = appTheme.isDark;
    final panelBg = isDark ? const Color(0xff1e1e1e) : const Color(0xfffafafa);
    final borderC = isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd);

    // Watch AI state so chat input can access model info
    context.watch<AIBloc>();

    return Container(
      width: asPage ? double.infinity : 300,
      decoration: BoxDecoration(
        color: panelBg,
        border: Border(left: BorderSide(color: borderC, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Sliding bubble tab bar ──────────────────────────────────────
          _buildAgentTabBar(context, appTheme, asPage),

          // ── Tab content with slide transition ───────────────────────────
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 270),
              transitionBuilder: (child, anim) {
                final isForward = _agentPanelTab >= _agentPanelPrevTab;
                final begin = Offset(isForward ? 1.0 : -1.0, 0.0);
                return SlideTransition(
                  position: Tween<Offset>(begin: begin, end: Offset.zero)
                      .animate(CurvedAnimation(
                          parent: anim, curve: Curves.easeOutCubic)),
                  child: FadeTransition(opacity: anim, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_agentPanelTab),
                child: _agentPanelTab == 1
                    ? _buildToolsTabContent(context, appTheme)
                    : _agentPanelTab == 2
                        ? _buildTasksTabContent(context, appTheme)
                        : _agentPanelTab == 3
                            ? _buildUserSettingsPage(context, appTheme)
                            : _agentPanelTab == 4
                                ? _buildAgentProvidersPage(context, appTheme)
                            : _buildChatTabContent(context, appTheme, asPage),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab bar: 3 animated sliding bubbles ──────────────────────────────────
  Widget _buildAgentTabBar(
      BuildContext context, AppTheme appTheme, bool asPage) {
    final isDark    = appTheme.isDark;
    final panelBg   = isDark ? const Color(0xff1e1e1e) : const Color(0xfffafafa);
    final borderC   = isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd);
    final fg        = isDark ? Colors.grey[300]! : Colors.grey[800]!;
    final muted     = isDark ? Colors.grey[500]! : Colors.grey[500]!;
    final unselBg   = isDark ? const Color(0xff2a2a2a) : const Color(0xffe2e2e2);
    final selBg     = isDark ? const Color(0xff383838) : const Color(0xffd2d2d2);

    if (_agentPanelTab >= 3) {
      return Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: panelBg,
          border: Border(
            bottom: BorderSide(color: borderC.withOpacity(0.5), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => setState(() {
                _agentPanelPrevTab = _agentPanelTab;
                _agentPanelTab = 1;
              }),
              child: SizedBox(
                width: 32,
                height: 34,
                child: Icon(Broken.arrow_left_2, size: 15, color: muted),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              _agentPanelTab == 4 ? Broken.cpu_setting : Broken.setting,
              size: 15,
              color: _kAccent,
            ),
            const SizedBox(width: 8),
            Text(
              _agentPanelTab == 4 ? 'Providers' : 'User Settings',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      );
    }

    Widget bubble({
      required int tabIdx,
      required IconData icon,
      required String label,
      required double w,
    }) {
      final selected = _agentPanelTab == tabIdx;
      return GestureDetector(
        onTap: () {
          if (tabIdx == 0 && selected) {
            _showAgentHeaderMenu(context, appTheme, asPage);
            return;
          }
          setState(() {
            _agentPanelPrevTab = _agentPanelTab;
            _agentPanelTab     = tabIdx;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 270),
          curve: Curves.easeInOutCubic,
          height: 34,
          width: w,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: selected ? selBg : unselBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: selected ? fg : muted),
                if (selected) ...[
                  const SizedBox(width: 6),
                  if (tabIdx == 0) ...[
                    Flexible(
                      child: Text(
                        _agentConversationTitle,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12, color: fg, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Broken.arrow_down_2, size: 11, color: muted),
                  ] else ...[
                    Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            color: fg,
                            fontWeight: FontWeight.w500)),
                  ],
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: 50,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: panelBg,
        border: Border(
            bottom: BorderSide(color: borderC.withOpacity(0.5), width: 0.5)),
      ),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          // Compute widths so all 3 bubbles fill 100% of available space
          // Layout: [back28] [4] [chat] [4] [tools] [4] [tasks]
          final double bubbles = (constraints.maxWidth - 28 - 4 - 4 - 4)
              .clamp(0.0, double.infinity)
              .toDouble(); // remaining for 3 bubbles
          final double chatW  = _agentPanelTab == 0 ? bubbles * 0.62 : bubbles * 0.19;
          final double toolsW = _agentPanelTab == 1 ? bubbles * 0.62 : bubbles * 0.19;
          final double tasksW = _agentPanelTab == 2 ? bubbles * 0.62 : bubbles * 0.19;

          return Row(children: [
            // Back / close
            GestureDetector(
              onTap: () {
                if (_agentPanelTab >= 3) {
                  setState(() {
                    _agentPanelPrevTab = _agentPanelTab;
                    _agentPanelTab     = 1; // back to tools
                  });
                } else if (!asPage) {
                  setState(() => _rightPanelOpen = false);
                }
              },
              child: SizedBox(
                width: 28,
                height: 34,
                child: Icon(Broken.arrow_left_2, size: 15, color: muted),
              ),
            ),
            const SizedBox(width: 4),
            bubble(tabIdx: 0, icon: Broken.magic_star,  label: '',      w: chatW),
            const SizedBox(width: 4),
            bubble(tabIdx: 1, icon: Broken.setting_3,   label: 'Tools', w: toolsW),
            const SizedBox(width: 4),
            bubble(tabIdx: 2, icon: Broken.task_square, label: 'Tasks', w: tasksW),
          ]);
        },
      ),
    );
  }

  // ── Chat tab content (existing chat UI) ───────────────────────────────────
  Widget _buildChatTabContent(
      BuildContext context, AppTheme appTheme, bool asPage) {
    final isDark     = appTheme.isDark;
    final borderC    = isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd);
    final fg         = isDark ? Colors.grey[300]! : Colors.grey[800]!;
    final muted      = isDark ? Colors.grey[500]! : Colors.grey[500]!;
    final inputBg    = isDark ? const Color(0xff252526) : const Color(0xfff0f0f0);
    final inputBorder= isDark ? const Color(0xff404040) : const Color(0xffdddddd);

    final aiState          = context.watch<AIBloc>().state;
    final selectedProfile = _selectedAgentProfile(aiState);
    final selectedProviderId = selectedProfile?.key;
    final selectedConfig   = selectedProfile?.value;
    final providerName     = selectedConfig is Map
        ? (selectedConfig['provider'] ?? selectedConfig['apiProvider'] ?? '')
              .toString()
        : '';
    final selectedProvider = _providerNameFromConfig(selectedConfig);
    final missingKey = selectedConfig is Map &&
        _agentProviderNeedsKey(selectedProvider) &&
        (selectedConfig['apiKey'] ?? selectedConfig['api_key'] ??
                selectedConfig['key'] ?? '')
            .toString()
            .trim()
            .isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Messages / empty state ─────────────────────────────────────
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      onTap: () =>
                          setState(() => _agentAttachments.removeAt(i)),
                      child: Icon(Broken.close_square, size: 11, color: muted),
                    ),
                  ]),
                );
              },
            ),
          ),

        // ── Input box ─────────────────────────────────────────────────
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
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
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
                            : 'Décrivez ce que vous voulez planifier…',
                    hintStyle: TextStyle(fontSize: 13, color: muted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _agentSend(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                child: Row(children: [
                  // Attachment
                  Tooltip(
                    message: 'Joindre un fichier',
                    child: InkWell(
                      onTap: () async {
                        final res = await FilePicker.pickFiles(
                            allowMultiple: true, type: FileType.any);
                        if (res != null && res.files.isNotEmpty) {
                          setState(() {
                            for (final f in res.files) {
                              _agentAttachments.add(
                                  {'name': f.name, 'path': f.path ?? ''});
                            }
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child:
                            Icon(Broken.paperclip, size: 16, color: muted),
                      ),
                    ),
                  ),
                  // Voice
                  Tooltip(
                    message: 'Dicter (micro)',
                    child: InkWell(
                      onTap: () => ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(
                        content: Text('Dictée vocale — bientôt disponible.',
                            style: TextStyle(fontSize: 13)),
                        duration: Duration(seconds: 2),
                      )),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child:
                            Icon(Broken.microphone, size: 16, color: muted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Mode pill
                  GestureDetector(
                    onTap: () => _showModeSheet(context, appTheme),
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
                        Icon(Broken.category, size: 11, color: muted),
                        const SizedBox(width: 4),
                        Text(
                          _agentChatMode == 'ask'
                              ? 'Ask'
                              : _agentChatMode == 'agent'
                                  ? 'Agent'
                                  : 'Plan',
                          style: TextStyle(
                              fontSize: 11,
                              color: muted,
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 2),
                        Icon(Broken.arrow_down_2, size: 10, color: muted),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Model pill
                  GestureDetector(
                    onTap: () => _showModelPickerSheet(context, appTheme),
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
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.sizeOf(context).width * 0.2,
                          ),
                          child: Builder(builder: (_) {
                            final selCfg = selectedConfig is Map
                                ? Map<String, dynamic>.from(
                                    selectedConfig as Map)
                                : null;
                            final modelLabel = selCfg != null
                                ? (selCfg['modelName'] ??
                                        selCfg['model'] ??
                                        providerName)
                                    .toString()
                                : '';
                            return Text(
                              missingKey
                                  ? 'No key configured'
                                  : (modelLabel.isEmpty ? 'Modèle' : modelLabel),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: missingKey ? Colors.orange[400] : muted,
                                  fontWeight: FontWeight.w500),
                            );
                          }),
                        ),
                        const SizedBox(width: 2),
                        Icon(Broken.arrow_down_2, size: 10, color: muted),
                      ]),
                    ),
                  ),
                  const Spacer(),
                  // Token estimate
                  Builder(builder: (ctx) {
                    int totalChars = 0;
                    for (final msg in _agentMessages) {
                      totalChars +=
                          (msg['text'] as String? ?? '').length;
                      totalChars +=
                          (msg['thinking'] as String? ?? '').length;
                    }
                    totalChars += _agentInputCtrl.text.length;
                    final estTokens = (totalChars / 4).round();
                    if (estTokens == 0) return const SizedBox.shrink();
                    final label = estTokens < 1000
                        ? '~${estTokens}tok'
                        : '~${(estTokens / 1000).toStringAsFixed(1)}k';
                    return Tooltip(
                      message:
                          'Tokens estimés ($estTokens ≈ chars÷4). '
                          'Au-delà de 80k le modèle peut tronquer.',
                      child: Text(label,
                          style: TextStyle(
                            fontSize: 10,
                            color: estTokens > 80000
                                ? Colors.red[400]
                                : estTokens > 40000
                                    ? Colors.orange[400]
                                    : muted,
                          )),
                    );
                  }),
                  const SizedBox(width: 6),
                  // Send / Stop
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
                          color:
                              _agentInputCtrl.text.trim().isEmpty
                                  ? Colors.transparent
                                  : _kAccent.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Broken.send_2,
                            size: 18,
                            color: _agentInputCtrl.text.trim().isEmpty
                                ? muted
                                : Colors.white),
                      ),
                    ),
                ]),
              ),
            ],
          ),
        ),

        // ── Footer: Local env + Approval mode ────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Row(children: [
            // + Agent shortcut
            GestureDetector(
              onTap: () {},
              child: Row(children: [
                Icon(Broken.add_circle, size: 13, color: muted),
                const SizedBox(width: 4),
                Icon(Broken.magic_star, size: 13, color: muted),
                const SizedBox(width: 4),
                Text('Agent', style: TextStyle(fontSize: 11, color: muted)),
              ]),
            ),
            const Spacer(),
            // Local pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xff2a2a2a) : const Color(0xffe8e8e8),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Broken.monitor, size: 11, color: muted),
                const SizedBox(width: 4),
                Text('Local', style: TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w500)),
              ]),
            ),
            const SizedBox(width: 6),
            // Approval mode pill
            GestureDetector(
              onTap: () => _showApprovalModeSheet(context, appTheme),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xff2a2a2a) : const Color(0xffe8e8e8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Broken.shield_tick, size: 11,
                      color: _agentApprovalMode == 'bypass'
                          ? Colors.orange[400]
                          : _agentApprovalMode == 'autopilot'
                              ? Colors.blue[400]
                              : muted),
                  const SizedBox(width: 4),
                  Text(
                    _agentApprovalMode == 'bypass'
                        ? 'Contournement'
                        : _agentApprovalMode == 'autopilot'
                            ? 'Autopilot'
                            : 'Approbations par défaut',
                    style: TextStyle(
                        fontSize: 11,
                        color: muted,
                        fontWeight: FontWeight.w500),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  // ── Approval mode bottom sheet ────────────────────────────────────────────
  void _showApprovalModeSheet(BuildContext context, AppTheme appTheme) {
    final isDark = appTheme.isDark;
    final bg     = isDark ? const Color(0xff1e1e1e) : Colors.white;
    final fg     = isDark ? Colors.grey[200]! : Colors.grey[900]!;
    final muted  = isDark ? Colors.grey[500]! : Colors.grey[600]!;
    final selBg  = isDark ? const Color(0xff2a2a2a) : const Color(0xfff0f0f0);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: muted.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2))),

              // ── Option: Approbations par défaut ──
              _approvalOption(
                context: ctx, setS: setS, appTheme: appTheme,
                mode: 'default',
                icon: Broken.shield_tick,
                iconColor: Colors.grey[400]!,
                title: 'Approbations par défaut',
                subtitle: 'Copilot utilise vos paramètres configurés',
                selBg: selBg, fg: fg, muted: muted,
                extra: Padding(
                  padding: const EdgeInsets.fromLTRB(36, 8, 0, 0),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bac à sable pour le terminal',
                              style: TextStyle(fontSize: 13, color: fg)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _agentSandboxTerminal,
                      onChanged: (v) => setState(() {
                        _agentSandboxTerminal = v;
                        setS(() {});
                      }),
                      activeColor: _kAccent,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ]),
                ),
              ),

              // ── Option: Contournement ──
              _approvalOption(
                context: ctx, setS: setS, appTheme: appTheme,
                mode: 'bypass',
                icon: Broken.warning_2,
                iconColor: Colors.orange[400]!,
                title: 'Contournement des approbations',
                subtitle: 'Tous les appels d\'outils sont automatiquement approuvés',
                selBg: selBg, fg: fg, muted: muted,
              ),

              // ── Option: Autopilot ──
              _approvalOption(
                context: ctx, setS: setS, appTheme: appTheme,
                mode: 'autopilot',
                icon: Broken.send_2,
                iconColor: Colors.blue[400]!,
                title: 'Autopilot (Aperçu)',
                subtitle: 'Itère de manière autonome, du début à la fin',
                selBg: selBg, fg: fg, muted: muted,
              ),

              Divider(color: muted.withOpacity(0.2), height: 24),

              // En savoir plus
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('En savoir plus sur les autorisations',
                      style: TextStyle(
                          fontSize: 14,
                          color: fg,
                          fontWeight: FontWeight.w500)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _approvalOption({
    required BuildContext context,
    required StateSetter setS,
    required AppTheme appTheme,
    required String mode,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color selBg,
    required Color fg,
    required Color muted,
    Widget? extra,
  }) {
    final selected = _agentApprovalMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _agentApprovalMode = mode);
        setS(() {});
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? selBg : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 12, color: muted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ]),
            if (extra != null) extra!,
          ],
        ),
      ),
    );
  }

  // ── User Settings page ────────────────────────────────────────────────────
  Widget _buildUserSettingsPage(BuildContext context, AppTheme appTheme) {
    final isDark  = appTheme.isDark;
    final bg      = isDark ? const Color(0xff1e1e1e) : const Color(0xfffafafa);
    final fg      = isDark ? Colors.grey[200]! : Colors.grey[900]!;
    final muted   = isDark ? Colors.grey[500]! : Colors.grey[600]!;
    final border  = isDark ? const Color(0xff2e2e2e) : const Color(0xffe8e8e8);
    final cardBg  = isDark ? const Color(0xff252526) : Colors.white;
    final divC    = isDark ? const Color(0xff2e2e2e) : const Color(0xffe8e8e8);

    Widget section({
      required String title,
      required bool expanded,
      required VoidCallback onToggle,
      required List<Widget> children,
    }) =>
        Container(
          margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: divC, width: 0.5)),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: fg)),
                    const Spacer(),
                    Icon(
                      expanded ? Broken.arrow_up_2 : Broken.arrow_down_2,
                      size: 14,
                      color: muted,
                    ),
                  ]),
                ),
              ),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
            ],
          ),
        );

    Widget toggleRow(String label, String subtitle, bool value, ValueChanged<bool> onChanged) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 13, color: fg, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: muted)),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: _kAccent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ]),
        );

    Widget dividerRow() => Divider(height: 1, color: divC);

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Page header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('User Settings',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: fg)),
                const SizedBox(height: 4),
                Text(
                  'The following settings apply to your account and will be used across all your Apps.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                // ── Agent ──────────────────────────────────────────────
                section(
                  title: 'Agent',
                  expanded: _usAgentExpanded,
                  onToggle: () => setState(() => _usAgentExpanded = !_usAgentExpanded),
                  children: [
                    toggleRow(
                      'Agent Audio Notification',
                      'Play a sound when the Agent needs your response.',
                      _usAudioNotif,
                      (v) => setState(() => _usAudioNotif = v),
                    ),
                    dividerRow(),
                    toggleRow(
                      'Agent Push Notification',
                      'Send a push notification when the Agent needs your response.',
                      _usPushNotif,
                      (v) => setState(() => _usPushNotif = v),
                    ),
                  ],
                ),

                // ── App Preview ────────────────────────────────────────
                section(
                  title: 'App Preview',
                  expanded: _usPreviewExpanded,
                  onToggle: () => setState(() => _usPreviewExpanded = !_usPreviewExpanded),
                  children: [
                    toggleRow(
                      'Automatic Preview',
                      'Open a web preview automatically when a port is open',
                      _usAutoPreview,
                      (v) => setState(() => _usAutoPreview = v),
                    ),
                    dividerRow(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Forward Opened Ports Automat…',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: fg,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text('Automatically configure detected newly opened ports.',
                              style: TextStyle(fontSize: 11, color: muted)),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: cardBg,
                              border: Border.all(color: border),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButton<String>(
                              value: _usForwardPorts,
                              isExpanded: true,
                              underline: const SizedBox.shrink(),
                              dropdownColor: cardBg,
                              style: TextStyle(fontSize: 13, color: fg),
                              icon: Icon(Broken.arrow_down_2, size: 14, color: muted),
                              items: const [
                                DropdownMenuItem(value: 'all ports except localhost', child: Text('all ports except localhost')),
                                DropdownMenuItem(value: 'all ports', child: Text('all ports')),
                                DropdownMenuItem(value: 'none', child: Text('none')),
                              ],
                              onChanged: (v) => setState(() => _usForwardPorts = v!),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ── Appearance ─────────────────────────────────────────
                section(
                  title: 'Appearance',
                  expanded: _usAppearanceExpanded,
                  onToggle: () => setState(() => _usAppearanceExpanded = !_usAppearanceExpanded),
                  children: [
                    // Font Size
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Font Size',
                                  style: TextStyle(fontSize: 13, color: fg, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Text('Change the font size of the editor.',
                                  style: TextStyle(fontSize: 11, color: muted)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: cardBg,
                            border: Border.all(color: border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButton<String>(
                            value: _usFontSize,
                            underline: const SizedBox.shrink(),
                            dropdownColor: cardBg,
                            style: TextStyle(fontSize: 13, color: fg),
                            icon: Icon(Broken.arrow_down_2, size: 14, color: muted),
                            items: const [
                              DropdownMenuItem(value: 'small',  child: Text('small')),
                              DropdownMenuItem(value: 'normal', child: Text('normal')),
                              DropdownMenuItem(value: 'large',  child: Text('large')),
                            ],
                            onChanged: (v) => setState(() => _usFontSize = v!),
                          ),
                        ),
                      ]),
                    ),
                    dividerRow(),
                    // Theme
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Text('Theme', style: TextStyle(fontSize: 13, color: fg, fontWeight: FontWeight.w500)),
                        const Spacer(),
                        Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            border: Border.all(color: border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            for (final opt in [
                              (label: 'Light', icon: Broken.sun_1),
                              (label: 'Dark',  icon: Broken.moon),
                              (label: 'System', icon: Broken.monitor),
                            ]) ...[
                              GestureDetector(
                                onTap: () {
                                  final bloc = context.read<AppThemeBloc>();
                                  if (opt.label == 'Light') bloc.add(AppThemeEvent(appTheme: LightTheme()));
                                  else if (opt.label == 'Dark') bloc.add(AppThemeEvent(appTheme: DarkTheme()));
                                  else {
                                    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
                                    bloc.add(AppThemeEvent(appTheme: brightness == Brightness.dark ? DarkTheme() : LightTheme()));
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: (opt.label == 'Light' && !isDark) ||
                                           (opt.label == 'Dark'  &&  isDark)
                                        ? _kAccent.withOpacity(0.15)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(opt.icon, size: 13, color: fg),
                                    const SizedBox(width: 4),
                                    Text(opt.label,
                                        style: TextStyle(fontSize: 12, color: fg)),
                                  ]),
                                ),
                              ),
                            ],
                          ]),
                        ),
                      ]),
                    ),
                  ],
                ),

                // ── Code Editing ───────────────────────────────────────
                section(
                  title: 'Code Editing',
                  expanded: _usCodeEditExpanded,
                  onToggle: () => setState(() => _usCodeEditExpanded = !_usCodeEditExpanded),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Code editing settings coming soon.',
                          style: TextStyle(fontSize: 12, color: muted)),
                    ),
                  ],
                ),

                // ── Advanced Developer Settings ─────────────────────────
                section(
                  title: 'Advanced Developer Settings',
                  expanded: _usAdvancedExpanded,
                  onToggle: () => setState(() => _usAdvancedExpanded = !_usAdvancedExpanded),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Advanced settings coming soon.',
                          style: TextStyle(fontSize: 12, color: muted)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Reuse the provider form without rendering the legacy AgentSettings shell.
  Widget _buildAgentProvidersPage(
      BuildContext context, AppTheme appTheme) {
    return const AgentSettings(
      embedded: true,
      providersOnly: true,
    );
  }

  // ── Tools tab content ─────────────────────────────────────────────────────
  Widget _buildToolsTabContent(BuildContext context, AppTheme appTheme) {
    final isDark  = appTheme.isDark;
    final bg      = isDark ? const Color(0xff1e1e1e) : const Color(0xfffafafa);
    final fg      = isDark ? Colors.grey[200]! : Colors.grey[900]!;
    final muted   = isDark ? Colors.grey[500]! : Colors.grey[600]!;
    final border  = isDark ? const Color(0xff2e2e2e) : const Color(0xffe8e8e8);
    final inputBg = isDark ? const Color(0xff2a2a2a) : const Color(0xfff0f0f0);
    final hoverBg = isDark ? const Color(0xff252525) : const Color(0xfff2f2f2);

    final tools = [
      (icon: Broken.cpu_setting, color: _kAccent, title: 'Providers',
       desc: 'Configure API keys and AI models'),
      (icon: Broken.lock,          color: Colors.orange[400]!,  title: 'Secrets',        desc: 'Store sensitive information (like API keys) securely in your App'),
      (icon: Broken.code_1,        color: Colors.blue[400]!,    title: 'Agent Skills',   desc: 'Manage skills that extend Agent capabilities'),
      (icon: Broken.archive_book,  color: Colors.green[400]!,   title: 'App Storage',    desc: 'Host and save uploads like images, videos, and documents'),
      (icon: Broken.copy,          color: Colors.purple[400]!,  title: 'Artifacts',      desc: 'Browse generated artifacts and previews'),
      (icon: Broken.brush_1,       color: Colors.pink[400]!,    title: 'Canvas',         desc: 'Agent-controlled canvas for mockups and wireframes'),
      (icon: Broken.command_square,color: Colors.teal[400]!,    title: 'Console',        desc: 'View the terminal output after running your code'),
      (icon: Broken.data,          color: Colors.cyan[400]!,    title: 'Database',       desc: 'Stores structured data such as user profiles, game scores, and product catalogs'),
      (icon: Broken.code,          color: Colors.indigo[400]!,  title: 'Developer',      desc: 'Internal developer tools, telemetry, and diagnostics'),
      (icon: Broken.global,        color: Colors.amber[400]!,   title: 'Domains',        desc: 'Manage custom domains for your published project'),
      (icon: Broken.setting,       color: Colors.grey[500]!,    title: 'User Settings',  desc: 'Configure your account settings, appearance, and notifications'),
    ];

    final filtered = _agentToolsSearch.isEmpty
        ? tools
        : tools
            .where((t) =>
                t.title.toLowerCase().contains(_agentToolsSearch.toLowerCase()) ||
                t.desc.toLowerCase().contains(_agentToolsSearch.toLowerCase()))
            .toList();

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tool list — same bg as panel, no card elevation
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final t = filtered[i];
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (t.title == 'Providers') {
                        setState(() {
                          _agentPanelPrevTab = _agentPanelTab;
                          _agentPanelTab = 4;
                        });
                      } else if (t.title == 'Console') {
                        setState(() { _bottomPanelOpen = true; _bottomPanelTab = 0; });
                      } else if (t.title == 'User Settings') {
                        setState(() {
                          _agentPanelPrevTab = _agentPanelTab;
                          _agentPanelTab     = 3;
                        });
                      }
                    },
                    hoverColor: hoverBg,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: t.color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(child: Icon(t.icon, size: 16, color: t.color)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: fg)),
                              const SizedBox(height: 2),
                              Text(t.desc,
                                  style: TextStyle(fontSize: 11, color: muted),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        Icon(Broken.arrow_right_3, size: 13, color: muted.withOpacity(0.5)),
                      ]),
                    ),
                  ),
                );
                },
            ),
          ),

          // ── Footer: search full width ──────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(
              color: bg,
              border: Border(top: BorderSide(color: border, width: 0.5)),
            ),
            child: TextField(
              controller: _agentToolsSearchCtrl,
              onChanged: (v) => setState(() => _agentToolsSearch = v),
              style: TextStyle(fontSize: 13, color: fg),
              decoration: InputDecoration(
                hintText: 'Search tool…',
                hintStyle: TextStyle(fontSize: 13, color: muted),
                filled: true,
                fillColor: inputBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Broken.search_normal, size: 15, color: muted),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tasks tab content ─────────────────────────────────────────────────────
  Widget _buildTasksTabContent(BuildContext context, AppTheme appTheme) {
    final isDark  = appTheme.isDark;
    final bg      = isDark ? const Color(0xff1e1e1e) : const Color(0xfffafafa);
    final fg      = isDark ? Colors.grey[200]! : Colors.grey[900]!;
    final muted   = isDark ? Colors.grey[500]! : Colors.grey[600]!;
    final border  = isDark ? const Color(0xff3a3a3a) : const Color(0xffe5e5e5);
    final cardBg  = isDark ? const Color(0xff252526) : const Color(0xfff0f0f0);
    final emptyBg = isDark ? const Color(0xff252526) : const Color(0xffe8e8e8);

    final readyTasks  = _agentTasks.where((t) => t['status'] == 'ready').toList();
    final activeTasks = _agentTasks.where((t) => t['status'] == 'active').toList();
    final draftTasks  = _agentTasks.where((t) => t['status'] == 'draft').toList();

    Widget sectionLabel(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: muted,
                  letterSpacing: 0.2)),
        );

    Widget emptyBox(String text) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
              color: emptyBg, borderRadius: BorderRadius.circular(8)),
          child: Center(
              child: Text(text,
                  style: TextStyle(fontSize: 12, color: muted))),
        );

    Widget taskTile(Map<String, dynamic> task) {
      final icons = {
        'ready':  (Broken.play_circle, Colors.green[400]!),
        'active': (Broken.timer_1,     Colors.blue[400]!),
        'draft':  (Broken.edit,        muted),
      };
      final pair = icons[task['status']] ?? (Broken.task_square, muted);
      return ListTile(
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(pair.$1, size: 16, color: pair.$2),
        title: Text(task['title'] as String? ?? 'Task',
            style: TextStyle(fontSize: 13, color: fg)),
        subtitle: task['desc'] != null
            ? Text(task['desc'] as String,
                style: TextStyle(fontSize: 11, color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis)
            : null,
        trailing: GestureDetector(
          onTap: () =>
              setState(() => _agentTasks.remove(task)),
          child: Icon(Broken.close_circle, size: 15, color: muted),
        ),
      );
    }

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── "New" onboarding card (dismissible) ─────────────────────
          if (_agentTasksShowNew)
            Container(
              margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: _kAccent,
                          borderRadius: BorderRadius.circular(4)),
                      child: const Text('New',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _agentTasksShowNew = false),
                      child: Icon(Broken.close_square, size: 16, color: muted),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  // Colorful task type icons row
                  Row(children: [
                    for (final c in [
                      Colors.blue[400]!,
                      Colors.green[400]!,
                      Colors.orange[400]!,
                      Colors.purple[400]!,
                      Colors.pink[400]!,
                    ])
                      Container(
                        width: 30,
                        height: 30,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: c.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                            child: Icon(Broken.task_square,
                                size: 14, color: c)),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Background tasks allow you to get more work done at once.',
                    style: TextStyle(fontSize: 12, color: fg),
                  ),
                  const SizedBox(height: 4),
                  Text('Try creating your first one!',
                      style: TextStyle(fontSize: 12, color: fg)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () {},
                    child: Text('View documentation',
                        style: TextStyle(
                            fontSize: 12,
                            color: _kAccent,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),

          // ── Task sections ────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                sectionLabel('Ready'),
                readyTasks.isEmpty
                    ? emptyBox('No ready tasks')
                    : Column(
                        children: readyTasks.map(taskTile).toList()),
                sectionLabel('Active'),
                activeTasks.isEmpty
                    ? emptyBox('No active tasks')
                    : Column(
                        children: activeTasks.map(taskTile).toList()),
                sectionLabel('Draft'),
                draftTasks.isEmpty
                    ? emptyBox('No draft tasks')
                    : Column(
                        children: draftTasks.map(taskTile).toList()),
              ],
            ),
          ),

          // ── + New task button (full width, no Core badge) ─────────
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: border, width: 0.5)),
            ),
            child: GestureDetector(
              onTap: () => _createAgentTask(context, appTheme),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xff2a2a2a) : const Color(0xffe8e8e8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Broken.add_square, size: 15, color: muted),
                    const SizedBox(width: 6),
                    Text('New task',
                        style: TextStyle(
                            fontSize: 13,
                            color: fg,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Create task dialog ────────────────────────────────────────────────────
  void _createAgentTask(BuildContext context, AppTheme appTheme) {
    final isDark   = appTheme.isDark;
    final titleCtrl = TextEditingController();
    final descCtrl  = TextEditingController();
    String status   = 'draft';

    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor:
              isDark ? const Color(0xff252526) : Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          title: Text('Nouvelle tâche',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[200] : Colors.grey[900])),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[200] : Colors.grey[900]),
                decoration: InputDecoration(
                  hintText: 'Titre de la tâche',
                  hintStyle: TextStyle(
                      color: isDark
                          ? Colors.grey[600]
                          : Colors.grey[500]),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xff1e1e1e)
                      : const Color(0xfff5f5f5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[200] : Colors.grey[900]),
                decoration: InputDecoration(
                  hintText: 'Description (optionnel)',
                  hintStyle: TextStyle(
                      color: isDark
                          ? Colors.grey[600]
                          : Colors.grey[500]),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xff1e1e1e)
                      : const Color(0xfff5f5f5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              // Status selector
              Row(children: [
                for (final s in ['draft', 'ready', 'active'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setS(() => status = s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: status == s
                              ? _kAccent.withOpacity(0.2)
                              : (isDark
                                  ? const Color(0xff2a2a2a)
                                  : const Color(0xffe8e8e8)),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: status == s
                                  ? _kAccent
                                  : Colors.transparent),
                        ),
                        child: Text(
                          s[0].toUpperCase() + s.substring(1),
                          style: TextStyle(
                              fontSize: 12,
                              color: status == s
                                  ? _kAccent
                                  : (isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[700]),
                              fontWeight: status == s
                                  ? FontWeight.w600
                                  : FontWeight.normal),
                        ),
                      ),
                    ),
                  ),
              ]),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Annuler',
                  style: TextStyle(
                      fontSize: 13,
                      color:
                          isDark ? Colors.grey[500] : Colors.grey[600])),
            ),
            TextButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isNotEmpty) {
                  setState(() => _agentTasks.add({
                        'title': title,
                        'desc': descCtrl.text.trim().isEmpty
                            ? null
                            : descCtrl.text.trim(),
                        'status': status,
                        'createdAt': DateTime.now().toIso8601String(),
                      }));
                }
                Navigator.pop(ctx);
              },
              child: Text('Créer',
                  style: TextStyle(
                      fontSize: 13,
                      color: _kAccent,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet — choose mode (Ask / Agent / Normal).
  void _showModeSheet(BuildContext context, AppTheme appTheme) {
    final isDark  = appTheme.isDark;
    final bg      = isDark ? const Color(0xff252526) : const Color(0xfffafafa);
    final fg      = isDark ? Colors.grey[300]! : Colors.grey[800]!;
    final muted   = isDark ? Colors.grey[500]! : Colors.grey[500]!;

    showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            child: Text('Choisir le mode',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: fg)),
          ),
          const Divider(height: 1),
          for (final mode in [
            ('ask',    'Ask',    'Questions & réponses rapides',   Broken.message_question),
            ('agent',  'Agent',  'Tâches complexes étape par étape', Broken.cpu),
            ('plan',   'Plan',   'Planification avant exécution',   Broken.task_square),
          ])
            ListTile(
              dense: true,
              leading: Icon(mode.$4, size: 18,
                  color: _agentChatMode == mode.$1 ? _kAccent : muted),
              title: Text(mode.$2,
                  style: TextStyle(
                      fontSize: 13,
                      color: fg,
                      fontWeight: _agentChatMode == mode.$1
                          ? FontWeight.w600
                          : FontWeight.normal)),
              subtitle: Text(mode.$3,
                  style: TextStyle(fontSize: 11, color: muted)),
              trailing: _agentChatMode == mode.$1
                  ? Icon(Broken.tick_circle, size: 16, color: _kAccent)
                  : null,
              onTap: () {
                setState(() => _agentChatMode = mode.$1);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Bottom sheet — hierarchical model picker (Provider → Models).
  void _showModelPickerSheet(BuildContext context, AppTheme appTheme) {
    final isDark  = appTheme.isDark;
    final bg      = isDark ? const Color(0xff252526) : const Color(0xfffafafa);
    final fg      = isDark ? Colors.grey[300]! : Colors.grey[800]!;
    final muted   = isDark ? Colors.grey[500]! : Colors.grey[500]!;
    final border  = isDark ? const Color(0xff3a3a3a) : const Color(0xffe0e0e0);
    final card    = isDark ? const Color(0xff2d2d2d) : Colors.white;

    final aiState     = context.read<AIBloc>().state;
    final selectedId  = aiState.modelSelected['chat']?.toString();
    final agentEntries = aiState.config.entries
        .where((e) => e.key.startsWith('agent_'))
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scroll) {
          if (agentEntries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Broken.cpu_setting, size: 36, color: muted),
                    const SizedBox(height: 12),
                    Text('Aucun provider configuré',
                        style: TextStyle(fontSize: 14, color: fg,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('Ouvrez Paramètres Agent pour ajouter un provider.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: muted)),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _rightPanelOpen = true;
                          _agentPanelPrevTab = _agentPanelTab;
                          _agentPanelTab = 4;
                        });
                      },
                      icon: const Icon(Broken.add_circle, size: 14),
                      label: const Text('Ajouter un provider'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
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
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Choisir un modèle',
                    style: TextStyle(fontSize: 15,
                        fontWeight: FontWeight.w600, color: fg)),
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // One section per configured provider
              for (final entry in agentEntries) ...[
                Builder(builder: (_) {
                  final cfg = entry.value is Map
                      ? Map<String, dynamic>.from(entry.value as Map)
                      : <String, dynamic>{};
                  final providerRaw = (cfg['provider'] ?? cfg['apiProvider'] ?? entry.key)
                      .toString();
                  final currentModel = (cfg['modelName'] ?? cfg['model'] ?? '').toString();
                  final models = (cfg['availableModels'] as List?)
                      ?.map((m) => m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{})
                      .where((m) => m['id'] != null && m['id'].toString().isNotEmpty)
                      .toList() ?? <Map<String, dynamic>>[];

                  final isSelectedProvider = selectedId == entry.key;
                  final icon = _providerIcon(providerRaw);
                  final pColor = _providerColor(providerRaw);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Provider header ──────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: pColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(icon, size: 13, color: pColor),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            providerRaw.substring(0, 1).toUpperCase() +
                                providerRaw.substring(1),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSelectedProvider ? _kAccent : fg,
                              letterSpacing: 0.5,
                            ),
                          ),
                          if (isSelectedProvider) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _kAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('actif',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: _kAccent,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ]),
                      ),

                      // ── Models list ──────────────────────────────────
                      if (models.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 26, bottom: 8),
                          child: Text(
                            currentModel.isNotEmpty ? currentModel : 'Aucun modèle',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        )
                      else
                        ...models.map((model) {
                          final modelId = model['id'].toString();
                          final displayName = (model['displayName'] ??
                                  model['display_name'] ??
                                  model['name'] ??
                                  modelId)
                              .toString();
                          final isSelected = isSelectedProvider &&
                              currentModel == modelId;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              Navigator.pop(ctx);
                              _selectAgentModel(
                                  context, entry.key, cfg, modelId);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(
                                  left: 26, bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _kAccent.withOpacity(0.1)
                                    : card,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? _kAccent.withOpacity(0.4)
                                      : border,
                                ),
                              ),
                              child: Row(children: [
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isSelected ? _kAccent : fg,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Broken.tick_circle,
                                      size: 14, color: _kAccent),
                              ]),
                            ),
                          );
                        }),
                      Divider(color: border, height: 16),
                    ],
                  );
                }),
              ],

              // ── Add provider shortcut ──────────────────────────────
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _rightPanelOpen    = true;
                    _agentPanelPrevTab = _agentPanelTab;
                    _agentPanelTab     = 4;
                  });
                },
                icon: Icon(Broken.add_circle, size: 14, color: muted),
                label: Text('Ajouter un provider',
                    style: TextStyle(fontSize: 12, color: muted)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Selects [modelId] within provider [providerKey], updates AIBloc.
  void _selectAgentModel(
    BuildContext context,
    String providerKey,
    Map<String, dynamic> cfg,
    String modelId,
  ) {
    final aiBloc = context.read<AIBloc>();
    final newCfg = Map<String, dynamic>.from(aiBloc.state.config);
    final updatedProviderCfg = Map<String, dynamic>.from(cfg);
    updatedProviderCfg['modelName'] = modelId;
    updatedProviderCfg['model']     = modelId;
    newCfg[providerKey] = updatedProviderCfg;
    aiBloc.add(AIConfigEvent(newCfg));

    final newSelected = Map<String, dynamic>.from(aiBloc.state.modelSelected);
    newSelected['chat'] = providerKey;
    aiBloc.add(ModelSelectEvent(newSelected));

    // Persist both
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('aiConfig', jsonEncode(newCfg));
      prefs.setString('modelSelected', jsonEncode(newSelected));
    });
  }

  MapEntry<String, dynamic>? _selectedAgentProfile(AIState aiState) {
    final selectedId = aiState.modelSelected['chat']?.toString();
    if (selectedId != null &&
        selectedId.startsWith('agent_') &&
        aiState.config[selectedId] is Map) {
      return MapEntry<String, dynamic>(selectedId, aiState.config[selectedId]);
    }

    for (final entry in aiState.config.entries) {
      if (entry.key.startsWith('agent_') && entry.value is Map) {
        return MapEntry<String, dynamic>(entry.key, entry.value);
      }
    }
    return null;
  }

  String _providerNameFromConfig(dynamic config) {
    if (config is! Map) return '';
    return (config['provider'] ?? config['apiProvider'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
  }

  bool _agentProviderNeedsKey(String provider) {
    return provider.isNotEmpty &&
        provider != 'copilot' &&
        provider != 'ollama' &&
        provider != 'lmstudio' &&
        provider != 'localllama' &&
        provider != 'custom' &&
        provider != 'pandagateway';
  }

  /// Returns a branded color for a provider string.
  Color _providerColor(String provider) {
    final p = provider.toLowerCase();
    if (p.contains('openai') || p.contains('gpt')) return const Color(0xff10a37f);
    if (p.contains('claude') || p.contains('anthropic')) return const Color(0xffb87333);
    if (p.contains('gemini') || p.contains('google')) return const Color(0xff4285f4);
    if (p.contains('grok')) return const Color(0xff1da1f2);
    if (p.contains('deepseek')) return const Color(0xff4b6ef5);
    if (p.contains('mistral')) return const Color(0xffff7000);
    if (p.contains('openrouter')) return const Color(0xff8b5cf6);
    if (p.contains('copilot')) return const Color(0xff8b5cf6);
    if (p.contains('together')) return const Color(0xff00c9b1);
    if (p.contains('perplexity')) return const Color(0xff20b2aa);
    if (p.contains('panda') || p.contains('gateway')) return _kAccent;
    return const Color(0xff888888);
  }

  /// Returns a representative icon for a given provider string.
  IconData _providerIcon(String provider) {
    final p = provider.toLowerCase();
    if (p.contains('copilot')) return Broken.message_programming;
    if (p.contains('openai') || p.contains('gpt')) return Broken.global;
    if (p.contains('claude') || p.contains('anthropic')) return Broken.cpu;
    if (p.contains('gemini') || p.contains('google')) return Broken.global_search;
    if (p.contains('grok')) return Broken.code_circle;
    if (p.contains('deepseek')) return Broken.search_normal;
    if (p.contains('mistral')) return Broken.wind;
    if (p.contains('local') || p.contains('llama')) return Broken.cpu_setting;
    return Broken.cpu;
  }

  /// Resolves the selected Agent model at send time.
  ///
  /// Copilot is deliberately different from API-key providers: GitHub issues
  /// a short-lived Copilot token, so it must never be persisted in AI config.
  /// The configured model is normally `auto`; in that case we select the first
  /// chat-capable model returned by GitHub's live catalog.
  Future<Models?> _resolveAgentModel(
    Map<String, dynamic> cfg,
  ) async {
    final provider = (cfg['provider'] ?? cfg['apiProvider'] ?? '')
        .toString()
        .toLowerCase();
    if (provider != 'copilot') {
      return _modelFromAiConfig(cfg);
    }

    final auth = await CopilotChat.loadAuthContext();
    if (auth == null) return null;

    final client = context.read<CopilotChatBloc>().chatClient ??
        CopilotChat(
          authToken: auth.authToken,
          initialApiEndpoint: auth.apiEndpoint,
        );
    final configuredModel = (cfg['modelName'] ?? cfg['model'] ?? '')
        .toString()
        .trim();
    var modelName = configuredModel;
    if (modelName.isEmpty || modelName == 'auto') {
      final payload = await client.getCopilotModels();
      final models = (payload['data'] as List?)
          ?.whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => item['id'] != null)
          .where((item) => item['model_picker_enabled'] != false)
          .where((item) {
            final endpoints = item['supported_endpoints'];
            if (endpoints is! List || endpoints.isEmpty) return true;
            return endpoints.any((endpoint) {
              final value = endpoint.toString().toLowerCase();
              return value.contains('chat/completions') ||
                  value.contains('/responses');
            });
          })
          .toList() ??
          const <Map<String, dynamic>>[];
      modelName = models.isNotEmpty
          ? models.first['id'].toString()
          : '';
    }
    if (modelName.isEmpty) return null;

    return Copilot(
      authToken: auth.authToken,
      apiEndpoint: auth.apiEndpoint,
      model: modelName,
    );
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
                      : Broken.task_square,
              size: 16, color: _kAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _agentChatMode == 'agent'
                    ? 'Mode Agent — exécute des tâches de code autonomes.'
                    : _agentChatMode == 'ask'
                        ? 'Mode Ask — répond à vos questions sur le code.'
                        : 'Mode Plan — planifie et décompose avant d\'agir.',
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
          // ── User message with GitHub avatar ───────────────────────
          final githubAvatarUrl = context
              .read<RepoBloc>()
              .state
              .user
              ?.avatarUrl;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Message bubble
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 0, bottom: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _kAccent.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(text,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.white)),
                      ),
                      // Copy action row
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MsgActionBtn(
                            icon: Broken.copy,
                            label: 'Copier',
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: text));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Copié !',
                                      style: TextStyle(fontSize: 12)),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            muted: muted,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // User avatar (GitHub photo or initials fallback)
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kAccent.withOpacity(0.2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: githubAvatarUrl != null && githubAvatarUrl.isNotEmpty
                      ? Image.network(
                          githubAvatarUrl,
                          width: 28, height: 28, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.person, size: 16, color: _kAccent),
                        )
                      : const Icon(Icons.person, size: 16, color: _kAccent),
                ),
              ],
            ),
          );
        }

        // ── Message agent ─────────────────────────────────────────────
        // Provider name + icon for the agent avatar
        final providerName = _lastUsedModel != null
            ? _lastUsedModel!.runtimeType.toString().toLowerCase()
            : 'agent';
        // Find index of the user message that triggered this response
        final userMsgIdx = (i > 0 && _agentMessages[i - 1]['role'] == 'user')
            ? i - 1
            : -1;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Agent avatar
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kAccent.withOpacity(0.15),
                ),
                child: ClipOval(
                  child: Image.asset(
                    _providerIconAsset(providerName),
                    width: 28, height: 28, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                        Broken.cpu_setting, size: 16, color: _kAccent),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Message content
              Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Phase chip — only when no tool calls to avoid double indicator
                () {
                  final hasCalls = (msg['toolCalls'] as List?)?.isNotEmpty ?? false;
                  if (isStreaming && think.isNotEmpty)
                    return _AgentPhaseChip(phase: AgentPhase.thinking, isDark: isDark);
                  if (isStreaming && !hasCalls && (msg['toolName'] as String? ?? '').isNotEmpty)
                    return _AgentPhaseChip(
                        phase: AgentPhase.toolRunning,
                        isDark: isDark,
                        toolName: msg['toolName'] as String? ?? '');
                  if (isStreaming && !hasCalls && (msg['toolName'] as String? ?? '').isEmpty)
                    return _AgentPhaseChip(phase: AgentPhase.streaming, isDark: isDark);
                  return const SizedBox.shrink();
                }(),

                // Thinking block (collapsible)
                if (think.isNotEmpty)
                  _ThinkingBlock(
                      thinking: think,
                      isDark: isDark,
                      fg: fg,
                      muted: muted),

                // Tool call blocks (expandable, Replit-style)
                ...() {
                  final calls = (msg['toolCalls'] as List?)
                      ?.cast<Map<String, dynamic>>() ?? [];
                  return calls.map((call) => _ToolCallBlock(
                    toolName: call['name'] as String? ?? '',
                    args: (call['args'] as Map?)
                        ?.cast<String, dynamic>() ?? {},
                    result: call['result'] as String?,
                    status: call['status'] as String? ?? 'running',
                    isDark: isDark,
                    fg: fg,
                    muted: muted,
                  ));
                }(),

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

                // Action row (copy + retry) — shown after generation
                if (!isStreaming && (text.isNotEmpty || isError))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (text.isNotEmpty)
                          _MsgActionBtn(
                            icon: Broken.copy,
                            label: 'Copier',
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: text));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Copié !',
                                      style: TextStyle(fontSize: 12)),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            muted: muted,
                          ),
                        if (userMsgIdx >= 0)
                          _MsgActionBtn(
                            icon: Broken.refresh,
                            label: 'Réessayer',
                            onTap: () {
                              final userText =
                                  _agentMessages[userMsgIdx]['text']
                                          as String? ??
                                      '';
                              if (userText.isEmpty || _agentGenerating) {
                                return;
                              }
                              // Remove agent message + user message then resend
                              setState(() {
                                if (i < _agentMessages.length) {
                                  _agentMessages.removeAt(i);
                                }
                                if (userMsgIdx < _agentMessages.length) {
                                  _agentMessages.removeAt(userMsgIdx);
                                }
                                _agentInputCtrl.text = userText;
                              });
                              _agentSend();
                            },
                            muted: muted,
                          ),
                      ],
                    ),
                  ),
              ],
            ),            // closes Column
          ),              // closes Expanded
        ],
      ),                  // closes Row
    );                    // closes Padding
      },
    );
  }

  /// Returns the asset path of the provider's icon given a provider runtime type.
  String _providerIconAsset(String name) {
    if (name.contains('gemini'))     return 'assets/icons/ai.svg';
    if (name.contains('claude'))     return 'assets/icons/ai.svg';
    if (name.contains('openai'))     return 'assets/icons/ai.svg';
    if (name.contains('copilot'))    return 'assets/icons/github-copilot-icon.svg';
    return 'assets/icons/app-icon.png';
  }

  // ── Floating agent overlay ────────────────────────────────────────────────
  Widget _buildFloatingAgentOverlay(AppTheme appTheme) {
    final isDark  = appTheme.isDark;
    final shadowC = isDark ? Colors.black54 : Colors.black26;
    const panelW  = 320.0;
    const panelH  = 480.0;

    return Positioned(
      left: _agentFloatOffset.dx,
      top:  _agentFloatOffset.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _agentFloatOffset = Offset(
            (_agentFloatOffset.dx + d.delta.dx).clamp(0, double.infinity),
            (_agentFloatOffset.dy + d.delta.dy).clamp(0, double.infinity),
          );
        }),
        child: Material(
          elevation: 12,
          shadowColor: shadowC,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width:  panelW,
            height: panelH,
            child: Stack(
              children: [
                BlocProvider(
                  create: (_) => AIChatUIBloc(),
                  child: Builder(
                    builder: (panelContext) => _buildPandaAgentPanel(
                      panelContext, appTheme, asPage: true),
                  ),
                ),
                Positioned(
                  top: 0, right: 0,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.picture_in_picture_alt, size: 14),
                      tooltip: 'Ancrer',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                      onPressed: () => setState(() {
                        _agentFloating  = false;
                        _rightPanelOpen = true;
                      }),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      tooltip: 'Fermer',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                      onPressed: () => setState(() => _agentFloating = false),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
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
    final providerRaw = (cfg['provider'] ?? cfg['apiProvider'] ?? '').toString();
    final provider    = providerRaw.toLowerCase();
    final apiKey      = (cfg['apiKey'] ?? '').toString();
    final modelName   = (cfg['modelName'] ?? cfg['model'] ?? '').toString();

    switch (provider) {
      case 'gemini':     return Gemini(apiKey: apiKey, model: modelName);
      case 'claude':     return Claude(apiKey: apiKey, model: modelName);
      case 'openai':     return OpenAI(apiKey: apiKey, model: modelName);
      case 'grok':       return Grok(apiKey: apiKey, model: modelName);
      case 'deepseek':   return DeepSeek(apiKey: apiKey, model: modelName);
      case 'mistral':    return Mistral(apiKey: apiKey, model: modelName);
      case 'togetherai': return TogetherAi(apiKey: apiKey, model: modelName);
      case 'perplexity': return Perplexity(apiKey: apiKey, model: modelName);
      case 'openrouter': return OpenRouter(apiKey: apiKey, model: modelName);
      case 'groq':       return Groq(apiKey: apiKey, model: modelName);
      case 'fireworks':  return FireWorks(apiKey: apiKey, model: modelName);
      case 'cohere':     return Cohere(apiKey: apiKey, model: modelName);
      case 'cerebras':   return Cerebras(apiKey: apiKey, model: modelName);
      case 'novita':     return Novita(apiKey: apiKey, model: modelName);
      case 'hyperbolic': return Hyperbolic(apiKey: apiKey, model: modelName);
      case 'sambanova':  return SambaNova(apiKey: apiKey, model: modelName);
      case 'qwen':       return Qwen(apiKey: apiKey, model: modelName);
      case 'ollama':
        final ollamaPort = (cfg['port'] as num?)?.toInt() ?? 11434;
        return Ollama(model: modelName, port: ollamaPort);
      case 'lmstudio':
        final lmsPort = (cfg['port'] as num?)?.toInt() ?? 1234;
        return LmStudio(model: modelName, port: lmsPort);
      case 'pandagateway':
        final port = (cfg['port'] as num?)?.toInt() ?? 8000;
        return PandaGateway(apiKey: apiKey, model: modelName, port: port);
      case 'localllama':
        final mp = (cfg['modelPath'] ?? '').toString().trim();
        if (mp.isEmpty) return null;
        return LocalLlama(
          modelPath: mp,
          displayName: modelName.isNotEmpty ? modelName : mp.split('/').last,
          threads: (cfg['threads'] as num?)?.toInt() ?? 4,
          contextSize: (cfg['contextSize'] as num?)?.toInt() ?? 4096,
          gpuLayers: (cfg['gpuLayers'] as num?)?.toInt() ?? 0,
        );
      case 'custom':
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
    PandaLog.w('PandaAgent', 'Generation cancelled by user');
    _agentRequestSerial++;
    _agentRunner.cancel();
    _sendAnimCtrl.stop();
    if (!mounted) return;
    setState(() {
      _agentGenerating = false;
      _agentPhase = AgentPhase.idle;
      if (_agentMessages.isNotEmpty &&
          _agentMessages.last['role'] == 'agent' &&
          _agentMessages.last['phase'] == 'streaming') {
        _agentMessages.last['text'] =
            _agentStreamBuf.isEmpty ? 'Génération arrêtée.' : _agentStreamBuf;
        _agentMessages.last['phase'] = 'error';
      }
    });
  }

  // ── Nouvelle conversation ────────────────────────────────────────────────
  // ── Export conversation as Markdown ──────────────────────────────────────
  Future<void> _exportAgentMarkdown() async {
    if (_agentMessages.isEmpty) return;
    final buf = StringBuffer();
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    buf.writeln('# Panda Agent — $dateStr');
    buf.writeln();
    for (final msg in _agentMessages) {
      final role = msg['role'] as String? ?? '';
      final text = msg['text'] as String? ?? '';
      if (role == 'user') {
        buf.writeln('## 👤 Vous');
        buf.writeln();
        buf.writeln(text);
        buf.writeln();
      } else {
        buf.writeln('## 🐼 Panda Agent');
        buf.writeln();
        final think = msg['thinking'] as String? ?? '';
        if (think.isNotEmpty) {
          buf.writeln('<details><summary>Réflexion</summary>');
          buf.writeln();
          buf.writeln(think);
          buf.writeln('</details>');
          buf.writeln();
        }
        if (text.isNotEmpty) buf.writeln(text);
        buf.writeln();
      }
    }

    try {
      final ts  =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      // Export to the public Panda IDE root folder accessible to the user
      final exportDir = Directory(pandaRootDir);
      if (!exportDir.existsSync()) {
        await exportDir.create(recursive: true);
      }
      final file = File('$pandaRootDir/panda-agent-$ts.md');
      await file.writeAsString(buf.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Exporté → ${file.path}',
            style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Copier le chemin',
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: file.path)),
        ),
      ));
    } catch (_) {
      // Fallback : copier le Markdown dans le presse-papier
      await Clipboard.setData(ClipboardData(text: buf.toString()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Markdown copié dans le presse-papier',
            style: TextStyle(fontSize: 12)),
        duration: Duration(seconds: 2),
      ));
    }
  }

  // ── P2: Token estimation ─────────────────────────────────────────────────
  /// Estimates the number of tokens in [messages] (~4 chars per token).
  int _estimateTokens(List<Map<String, dynamic>> messages) {
    int chars = 0;
    for (final m in messages) {
      chars += (m['text']?.toString().length ?? 0);
      chars += (m['thinking']?.toString().length ?? 0);
    }
    return (chars / 4).round();
  }

  // ── P2: SummaryMemory — compresses old messages when context is too large ─
  /// Calls the LLM to summarise old messages when [_agentMessages] exceeds
  /// ~40 000 tokens, keeping the 4 most recent messages intact.
  Future<void> _compressOldMessages(Models model) async {
    if (_agentMessages.length < 6) return; // need at least 3 pairs
    if (_estimateTokens(_agentMessages) < 40000) return;

    final keepCount = 4;
    final toCompress = _agentMessages.sublist(0, _agentMessages.length - keepCount);
    final recent     = _agentMessages.sublist(_agentMessages.length - keepCount);

    final oldText = toCompress.map((m) {
      final role = m['role'] == 'user' ? 'Utilisateur' : 'Agent';
      return '$role: ${m['text'] ?? ''}';
    }).join('\n\n');

    try {
      final summaryMsgs = <Map<String, dynamic>>[
        {
          'role': 'user',
          'content':
              'Résume cette conversation de développement en 300 mots max. '
              'Conserve : décisions techniques, fichiers modifiés, bugs résolus, '
              'contexte clé.\n\n$oldText',
        },
      ];
      String summary = '';
      await for (final chunk in AgentRunner().run(
        model: model,
        messages: summaryMsgs,
        agentMode: 'ask',
      )) {
        if (chunk.phase == AgentPhase.streaming) summary += chunk.text;
      }
      if (summary.isNotEmpty && mounted) {
        setState(() {
          _agentMessages
            ..clear()
            ..add({
              'role': 'agent',
              'text': '[📝 Résumé de la conversation précédente]\n$summary',
              'thinking': '',
              'phase': 'done',
            })
            ..addAll(recent);
        });
        PandaLog.i('PandaAgent',
            'SummaryMemory: compressed ${toCompress.length} messages → summary');
      }
    } catch (e) {
      PandaLog.w('PandaAgent', 'SummaryMemory compression failed: $e');
    }
  }

  // ── P2: ProjectMemory — reads .panda/memory.md ───────────────────────────
  Future<String> _loadProjectMemory(String workspacePath) async {
    if (workspacePath.isEmpty) return '';
    try {
      final file = File('$workspacePath/.panda/memory.md');
      if (!file.existsSync()) return '';
      final content = await file.readAsString();
      PandaLog.i('PandaAgent', 'ProjectMemory loaded (${content.length} chars)');
      return content.trim();
    } catch (e) {
      PandaLog.w('PandaAgent', 'Could not load project memory: $e');
      return '';
    }
  }

  // ── P2: ProjectMemory — writes .panda/memory.md ──────────────────────────
  Future<void> _saveProjectMemory(String workspacePath, String content) async {
    if (workspacePath.isEmpty || content.isEmpty) return;
    try {
      final dir = Directory('$workspacePath/.panda');
      if (!dir.existsSync()) await dir.create(recursive: true);
      await File('$workspacePath/.panda/memory.md').writeAsString(content);
      PandaLog.i('PandaAgent', 'ProjectMemory saved');
    } catch (e) {
      PandaLog.w('PandaAgent', 'Could not save project memory: $e');
    }
  }

  // ── Smart title extraction ────────────────────────────────────────────────
  /// Generates a concise chat title from [text] (first message).
  String _smartTitle(String text) {
    final cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return 'Nouvelle conversation';
    // Try to grab first meaningful sentence (10–60 chars)
    final match = RegExp(r'^(.{10,60}?)[\.\!\?]').firstMatch(cleaned);
    if (match != null) return match.group(1)!.trim();
    // Fallback: first 7 words
    final words = cleaned.split(' ').take(7).join(' ');
    return words.length > 50 ? words.substring(0, 50) : words;
  }

  /// After the first exchange, fires an async LLM call to generate a
  /// proper conversation title and updates state + history.
  Future<void> _generateConversationTitle() async {
    if (_agentMessages.length != 2) return;
    final model = _lastUsedModel;
    if (model == null) return;
    final firstMsg = (_agentMessages.first['text'] as String? ?? '').trim();
    if (firstMsg.isEmpty) return;

    try {
      final runner = AgentRunner();
      String title = '';
      final stream = runner.run(
        model: model,
        messages: [
          {
            'role': 'user',
            'content':
                'Generate a concise 4–6 word title (in the same language as the user message) '
                'summarising this conversation. Output ONLY the title — no quotes, no punctuation, '
                'no explanation.\n\nUser message: "$firstMsg"',
          },
        ],
        agentMode: 'normal', // disables all tools
      );

      await for (final chunk in stream) {
        if (chunk.phase == AgentPhase.streaming) title += chunk.text;
        if (chunk.phase == AgentPhase.done || chunk.phase == AgentPhase.error) break;
      }

      title = title.trim().replaceAll(RegExp(r'^["«»\']+|["«»\']+$'), '');
      if (title.isNotEmpty && mounted) {
        final clean = title.length > 50 ? title.substring(0, 50) : title;
        setState(() => _agentConversationTitle = clean);
        _autoSaveConversation();
      }
    } catch (_) {
      // Title generation is best-effort — silently ignore failures.
    }
  }

  /// Auto-saves the current conversation to history after each AI response.
  /// Silently no-ops if there are fewer than 2 messages or if already saving.
  void _autoSaveConversation() {
    if (_agentMessages.length < 2) return;
    // Build conversation pairs (user + agent)
    final conversations = <AIConversation>[];
    for (var i = 0; i < _agentMessages.length - 1; i += 2) {
      final user  = _agentMessages[i];
      final agent = i + 1 < _agentMessages.length ? _agentMessages[i + 1] : null;
      final userText  = user['text'] as String? ?? '';
      final agentText = agent?['text'] as String? ?? '';
      if (userText.isEmpty) continue;
      conversations.add(AIConversation(userText, agentText.isEmpty ? null : agentText));
    }
    if (conversations.isEmpty) return;
    final title = (_agentMessages.first['text'] as String? ?? 'Chat').trim();
    context.read<ChatSessionBloc>().add(UpdateCurrentSession(
      conversations: conversations,
      title: title.length > 50 ? title.substring(0, 50) : title,
    ));
  }

  void _agentNewConversation() {
    // Save current conversation to ChatSessionBloc
    if (_agentMessages.isNotEmpty) {
      final conversations = <AIConversation>[];
      for (var i = 0; i < _agentMessages.length - 1; i += 2) {
        final user  = _agentMessages[i];
        final agent = i + 1 < _agentMessages.length ? _agentMessages[i + 1] : null;
        conversations.add(AIConversation(
          user['text'] as String? ?? '',
          agent?['text'] as String?,
        ));
      }
      if (conversations.isNotEmpty) {
        final title = (_agentMessages.isNotEmpty
            ? (_agentMessages.first['text'] as String? ?? 'Chat')
            : 'Chat');
        context.read<ChatSessionBloc>().add(UpdateCurrentSession(
          conversations: conversations,
          title: title.length > 40 ? title.substring(0, 40) : title,
        ));
      }
    }
    // Create new session
    context.read<ChatSessionBloc>().add(CreateNewSession());
    setState(() {
      _agentMessages.clear();
      _agentAttachments.clear();
      _showHistoryPanel = false;
      _agentConversationTitle = 'Nouvelle conversation';
    });
  }

  // ── Add Provider inline panel ─────────────────────────────────────────────
  /// Affiche un bottom sheet avec un formulaire de configuration de provider
  /// directement dans le panneau (sans ouvrir l'onglet agent-settings).
  void _showAddProviderInPanel(BuildContext context, AppTheme appTheme) {
    final isDark  = appTheme.isDark;
    final bg      = isDark ? const Color(0xff252526) : Colors.white;
    final fg      = isDark ? Colors.grey[200]! : Colors.grey[900]!;
    final muted   = isDark ? Colors.grey[500]! : Colors.grey[600]!;
    final border  = isDark ? const Color(0xff3a3a3a) : const Color(0xffe0e0e0);
    final cardBg  = isDark ? const Color(0xff1e1e1e) : const Color(0xfff5f5f5);

    // Providers list (simplified subset)
    const providers = [
      (id: 'openai',     name: 'OpenAI',     hint: 'sk-...'),
      (id: 'claude',     name: 'Claude',     hint: 'sk-ant-...'),
      (id: 'gemini',     name: 'Gemini',     hint: 'AIza...'),
      (id: 'deepseek',   name: 'DeepSeek',   hint: 'sk-...'),
      (id: 'openrouter', name: 'OpenRouter', hint: 'sk-or-...'),
      (id: 'mistral',    name: 'Mistral',    hint: '...'),
      (id: 'groq',       name: 'Groq',       hint: 'gsk_...'),
      (id: 'copilot',    name: 'Copilot',    hint: ''),
      (id: 'custom',     name: 'Custom',     hint: ''),
    ];

    String selectedId  = 'openai';
    String apiKey      = '';
    String customUrl   = '';
    bool   obscure     = true;
    bool   saving      = false;
    String? errorMsg;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final prov = providers.firstWhere((p) => p.id == selectedId,
              orElse: () => providers.first);

          Future<void> save() async {
            if (prov.hint.isNotEmpty && apiKey.trim().isEmpty && selectedId != 'copilot' && selectedId != 'custom') {
              setSt(() => errorMsg = 'Clé API requise');
              return;
            }
            if (selectedId == 'custom' && customUrl.trim().isEmpty) {
              setSt(() => errorMsg = 'URL requise pour un endpoint custom');
              return;
            }
            setSt(() { saving = true; errorMsg = null; });
            try {
              final aiBloc  = context.read<AIBloc>();
              final newCfg  = Map<String, dynamic>.from(aiBloc.state.config);
              final modelId = 'agent_$selectedId';
              newCfg[modelId] = {
                'provider':    selectedId,
                'apiProvider': selectedId,
                if (selectedId != 'copilot') 'apiKey': apiKey.trim(),
                'modelName':   '',
                'model':       '',
                if (selectedId == 'custom') 'url': customUrl.trim(),
              };
              aiBloc.add(AIConfigEvent(newCfg));
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('aiConfig', jsonEncode(newCfg));
              final selected = Map<String, dynamic>.from(aiBloc.state.modelSelected);
              selected['chat'] = modelId;
              aiBloc.add(ModelSelectEvent(selected));
              await prefs.setString('modelSelected', jsonEncode(selected));
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              setSt(() { saving = false; errorMsg = e.toString(); });
            }
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: muted.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Ajouter un provider',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg)),
                  const SizedBox(height: 16),
                  // Provider selector
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: providers.map((p) {
                      final sel = selectedId == p.id;
                      return GestureDetector(
                        onTap: () => setSt(() { selectedId = p.id; apiKey = ''; customUrl = ''; errorMsg = null; }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: sel ? _kAccent.withOpacity(0.15) : cardBg,
                            border: Border.all(color: sel ? _kAccent : border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(p.name,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                                  color: sel ? _kAccent : fg)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // API key field (not for copilot)
                  if (selectedId != 'copilot' && selectedId != 'custom') ...[
                    Text('Clé API', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
                    const SizedBox(height: 6),
                    TextField(
                      onChanged: (v) => setSt(() { apiKey = v; errorMsg = null; }),
                      obscureText: obscure,
                      style: TextStyle(fontSize: 13, color: fg),
                      decoration: InputDecoration(
                        hintText: prov.hint,
                        hintStyle: TextStyle(fontSize: 12, color: muted),
                        filled: true, fillColor: cardBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        suffixIcon: IconButton(
                          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 16, color: muted),
                          onPressed: () => setSt(() => obscure = !obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Custom URL
                  if (selectedId == 'custom') ...[
                    Text('URL endpoint', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
                    const SizedBox(height: 6),
                    TextField(
                      onChanged: (v) => setSt(() { customUrl = v; errorMsg = null; }),
                      style: TextStyle(fontSize: 13, color: fg),
                      decoration: InputDecoration(
                        hintText: 'http://localhost:11434/v1/chat/completions',
                        hintStyle: TextStyle(fontSize: 12, color: muted),
                        filled: true, fillColor: cardBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Error
                  if (errorMsg != null) ...[
                    Text(errorMsg!, style: TextStyle(fontSize: 11, color: Colors.red[400])),
                    const SizedBox(height: 8),
                  ],
                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: saving ? null : save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Connecter', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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

  // ── Rename conversation ───────────────────────────────────────────────────
  void _renameConversation(BuildContext context, AppTheme appTheme) {
    final isDark = appTheme.isDark;
    final ctrl = TextEditingController(text: _agentConversationTitle);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xff252526) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Renommer la conversation',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[200] : Colors.grey[900])),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[200] : Colors.grey[900]),
          decoration: InputDecoration(
            hintText: 'Nom de la conversation',
            hintStyle: TextStyle(
                color: isDark ? Colors.grey[600] : Colors.grey[500]),
            filled: true,
            fillColor: isDark ? const Color(0xff1e1e1e) : const Color(0xfff5f5f5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              setState(() => _agentConversationTitle = v.trim());
            }
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler',
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[500] : Colors.grey[600])),
          ),
          TextButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) {
                setState(() => _agentConversationTitle = v);
              }
              Navigator.pop(ctx);
            },
            child: Text('Renommer',
                style: TextStyle(
                    fontSize: 13,
                    color: _kAccent,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Agent header chevron menu ─────────────────────────────────────────────
  void _showAgentHeaderMenu(
      BuildContext context, AppTheme appTheme, bool asPage) {
    final isDark = appTheme.isDark;
    final bg = isDark ? const Color(0xff2d2d2d) : Colors.white;
    final fg = isDark ? Colors.grey[200]! : Colors.grey[900]!;
    final muted = isDark ? Colors.grey[500]! : Colors.grey[600]!;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              decoration: BoxDecoration(
                color: muted.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Conversation name display
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _kAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(child: Icon(Broken.magic_star, size: 13, color: _kAccent)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _agentConversationTitle,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
          const Divider(height: 1),
          // Actions
          _menuItem(
            icon: Broken.edit_2,
            label: 'Renommer',
            color: fg,
            muted: muted,
            onTap: () {
              Navigator.pop(context);
              _renameConversation(context, appTheme);
            },
          ),
          _menuItem(
            icon: Broken.add_square,
            label: 'Nouvelle conversation',
            color: fg,
            muted: muted,
            onTap: () {
              Navigator.pop(context);
              _agentNewConversation();
            },
          ),
          _menuItem(
            icon: Broken.clock,
            label: 'Historique',
            color: fg,
            muted: muted,
            onTap: () {
              Navigator.pop(context);
              setState(() => _showHistoryPanel = !_showHistoryPanel);
            },
          ),
          _menuItem(
            icon: Broken.maximize_4,
            label: 'Mode flottant',
            color: fg,
            muted: muted,
            onTap: () async {
              Navigator.pop(context);
              // On Android, check/request SYSTEM_ALERT_WINDOW before entering
              // floating mode so the overlay can show over other apps.
              if (Platform.isAndroid) {
                final overlayStatus =
                    await Permission.systemAlertWindow.status;
                if (!overlayStatus.isGranted) {
                  await Permission.systemAlertWindow.request();
                  // Re-check after the settings round-trip
                  final recheckStatus =
                      await Permission.systemAlertWindow.status;
                  if (!recheckStatus.isGranted) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                          'Autorisez la superposition dans Réglages → Panda IDE '
                          'pour afficher l\'overlay par-dessus les autres apps.',
                          style: TextStyle(fontSize: 12),
                        ),
                        duration: Duration(seconds: 5),
                      ));
                    }
                    return;
                  }
                }
              }
              if (mounted) {
                setState(() {
                  _agentFloating  = true;
                  _rightPanelOpen = false;
                });
              }
            },
          ),
          if (_agentMessages.isNotEmpty)
            _menuItem(
              icon: Broken.document_download,
              label: 'Exporter Markdown',
              color: fg,
              muted: muted,
              onTap: () {
                Navigator.pop(context);
                _exportAgentMarkdown();
              },
            ),
          _menuItem(
            icon: Broken.setting_2,
            label: 'Paramètres Agent',
            color: fg,
            muted: muted,
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _rightPanelOpen    = true;
                _agentPanelPrevTab = _agentPanelTab;
                _agentPanelTab     = 3; // User Settings
              });
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required Color color,
    required Color muted,
    required VoidCallback onTap,
  }) =>
      ListTile(
        dense: true,
        leading: Icon(icon, size: 18, color: muted),
        title: Text(label,
            style: TextStyle(fontSize: 13, color: color)),
        onTap: onTap,
      );

  // ── History panel ────────────────────────────────────────────────────────
  Widget _buildHistoryPanel(AppTheme appTheme) {
    final isDark  = appTheme.isDark;
    final bg      = isDark ? const Color(0xff252526) : const Color(0xfff5f5f5);
    final border  = isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd);
    final fg      = isDark ? Colors.grey[200]! : Colors.grey[900]!;
    final muted   = isDark ? Colors.grey[500]! : Colors.grey[600]!;

    return BlocBuilder<ChatSessionBloc, ChatSessionState>(
      builder: (ctx, sessState) {
        final sessions = sessState.sessions;
        return Container(
          width: 240,
          decoration: BoxDecoration(
            color: bg,
            border: Border(left: BorderSide(color: border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                color: isDark ? const Color(0xff252526) : const Color(0xffececec),
                child: Row(children: [
                  Text('HISTORIQUE',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: muted)),
                  const Spacer(),
                  _agentHdrBtn(Broken.close_square, 'Fermer', muted,
                      () => setState(() => _showHistoryPanel = false)),
                ]),
              ),
              if (sessState.isLoading)
                Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                        color: _kAccent, strokeWidth: 2),
                  ),
                )
              else if (sessions.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Broken.clock, size: 28, color: muted),
                        const SizedBox(height: 8),
                        Text('Aucune conversation',
                            style: TextStyle(fontSize: 12, color: muted)),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: sessions.length,
                    itemBuilder: (_, i) {
                      final s = sessions[i];
                      final isCurrent = sessState.currentSession?.id == s.id;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Broken.message_programming,
                          size: 15,
                          color: isCurrent ? _kAccent : muted,
                        ),
                        title: Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: isCurrent ? _kAccent : fg,
                              fontWeight: isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.normal),
                        ),
                        subtitle: Text(
                          _relativeTime(s.createdAt),
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                        selected: isCurrent,
                        selectedTileColor: _kAccent.withOpacity(0.07),
                        onTap: () {
                          ctx.read<ChatSessionBloc>().add(SelectSession(s.id));
                          final convs = s.conversations;
                          final msgs = <Map<String, dynamic>>[];
                          for (final c in convs) {
                            msgs.add({'role': 'user', 'text': c.userRequest});
                            msgs.add({
                              'role': 'agent',
                              'text': c.modelResponse ?? '',
                              'thinking': '',
                              'phase': 'done',
                            });
                          }
                          setState(() {
                            _agentMessages
                              ..clear()
                              ..addAll(msgs);
                            _showHistoryPanel = false;
                          });
                        },
                        trailing: IconButton(
                          icon: Icon(Broken.trash, size: 13,
                              color: muted.withOpacity(0.6)),
                          onPressed: () => ctx.read<ChatSessionBloc>()
                              .add(DeleteSession(s.id)),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    return 'Il y a ${diff.inDays}j';
  }

  Future<void> _agentSend() async {
    final text = _agentInputCtrl.text.trim();
    if (text.isEmpty || _agentGenerating) return;
    final requestId = ++_agentRequestSerial;
    _sendAnimCtrl.repeat(reverse: true);
    setState(() {
      _agentGenerating = true;
      _agentPhase = AgentPhase.thinking;
      // Auto-title from first message (smart extraction; refined by LLM after response)
      if (_agentMessages.isEmpty && _agentConversationTitle == 'Nouvelle conversation') {
        _agentConversationTitle = _smartTitle(text);
      }
    });
    PandaLog.i(
      'PandaAgent',
      'Send requested — chars=${text.length} mode=$_agentChatMode',
    );
    try {
      await _agentSendInternal(text, requestId);
    } catch (error, stack) {
      PandaLog.e(
        'PandaAgent',
        'Failure before stream started',
        error: '$error\n$stack',
      );
      _showAgentFailure(text, error.toString(), requestId);
    }
  }

  void _showAgentFailure(String prompt, String message, int requestId) {
    if (requestId != _agentRequestSerial) return;
    _sendAnimCtrl.stop();
    if (!mounted) return;
    setState(() {
      _agentGenerating = false;
      _agentPhase = AgentPhase.error;
      if (_agentMessages.isEmpty ||
          _agentMessages.last['role'] != 'agent' ||
          _agentMessages.last['phase'] != 'streaming') {
        _agentMessages.add({'role': 'user', 'text': prompt});
        _agentMessages.add({
          'role': 'agent',
          'text': 'Erreur : $message',
          'thinking': '',
          'phase': 'error',
        });
      } else {
        _agentMessages.last['text'] = 'Erreur : $message';
        _agentMessages.last['phase'] = 'error';
      }
      _agentInputCtrl.clear();
    });
    _agentScrollToBottom();
  }

  Future<void> _agentSendInternal(String text, int requestId) async {
    PandaLog.d('PandaAgent', 'Preparing model and conversation');

    final aiState = context.read<AIBloc>().state;
    PandaLog.d(
      'PandaAgent',
      'AI state loaded — configs=${aiState.config.length} '
      'selected=${aiState.modelSelected['chat']}',
    );

    Models? model;
    String? modelResolutionError;
    final selectedProfile = _selectedAgentProfile(aiState);
    final selectedId = selectedProfile?.key;
    final selectedConfig = selectedProfile?.value;
    // Panda Agent only consumes provider profiles created by the provider-first
    // settings flow. Older IDE model profiles must not silently control Agent.
    final isAgentProviderProfile =
        selectedId != null && selectedId.startsWith('agent_');
    if (isAgentProviderProfile && selectedConfig is Map) {
      try {
        final normalizedConfig = Map<String, dynamic>.from(selectedConfig);
        final provider = _providerNameFromConfig(normalizedConfig);
        final apiKey = (normalizedConfig['apiKey'] ??
                normalizedConfig['api_key'] ??
                normalizedConfig['key'] ??
                '')
            .toString()
            .trim();
        if (_agentProviderNeedsKey(provider) && apiKey.isEmpty) {
          modelResolutionError = 'No key configured for $provider. '
              'Open Tools → Providers and add your API key.';
        } else {
          PandaLog.d(
            'PandaAgent',
            'Resolving provider=${normalizedConfig['provider']} modelId=$selectedId',
          );
          model = await _resolveAgentModel(
            normalizedConfig,
          ).timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException(
              'La résolution du modèle IA a expiré.',
            ),
          );
          if (model != null) _lastUsedModel = model;
          PandaLog.d(
            'PandaAgent',
            'Provider resolved — model=${model?.runtimeType ?? '<none>'}',
          );
          if (model == null &&
              selectedConfig['provider']?.toString().toLowerCase() ==
                  'copilot') {
            modelResolutionError =
                'GitHub Copilot n’est pas disponible avec cette session ou ce compte.';
          }
        }
      } catch (error) {
        modelResolutionError = 'Impossible de charger le modèle IA : $error';
      }
    }
    if (model == null) {
      _sendAnimCtrl.stop();
      setState(() {
        _agentGenerating = false;
        _agentPhase = AgentPhase.error;
        _agentMessages.add({'role': 'user', 'text': text});
        _agentMessages.add({
          'role': 'agent',
          'text': modelResolutionError ??
          'Aucun provider validé pour Panda Agent. Ouvrez Paramètres Agent, '
          'entrez votre clé puis validez la connexion.',
          'thinking': '',
          'phase': 'error',
        });
        _agentInputCtrl.clear();
      });
      _agentScrollToBottom();
      return;
    }

    if (!mounted || requestId != _agentRequestSerial) return;

    PandaLog.d('PandaAgent', 'Loading agent preferences');
    final prefs = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException(
        'Le chargement des préférences de Panda Agent a expiré.',
      ),
    );
    if (!mounted || requestId != _agentRequestSerial) return;
    final memoryEnabled = prefs.getBool('agent_memory_enabled') ?? true;
    final memoryNotes = memoryEnabled
        ? (prefs.getString('agent_memory_notes') ?? '').trim()
        : '';
    final customSystemPrompt = (prefs.getString('agent_system_prompt') ?? '')
        .trim();
    // ── Résolution du workspacePath (avant injection mémoire) ────────────
    // The active editor is the source of truth. Recent projects are only a
    // fallback for the welcome state; relying on recents alone can give the
    // agent an empty workspace after a project was opened in a tab.
    String workspacePath = '';
    try {
      workspacePath = _activeProjectDir() ?? '';
      if (workspacePath.isEmpty) {
        final recentState = context.read<RecentBloc>().state;
        final recentProject = recentState.recent.cast<dynamic>().firstWhere(
          (e) => (e as Map?)?['type'] == 'project',
          orElse: () => null,
        );
        if (recentProject is Map) {
          workspacePath = recentProject['rootDir']?.toString() ??
              recentProject['path']?.toString() ?? '';
        }
      }
    } catch (error) {
      PandaLog.w('PandaAgent', 'Could not resolve workspace path: $error');
    }
    PandaLog.i(
      'PandaAgent',
      'Workspace resolved — ${workspacePath.isEmpty ? '<none>' : workspacePath}',
    );

    // ── P2: ProjectMemory — injecte .panda/memory.md ─────────────────────
    final projectMemory = await _loadProjectMemory(workspacePath);
    final systemPromptParts = <String>[
      if (customSystemPrompt.isNotEmpty) customSystemPrompt,
      if (memoryNotes.isNotEmpty)
        'Persistent project/user context:\n$memoryNotes',
      if (projectMemory.isNotEmpty)
        '## MÉMOIRE PROJET\n$projectMemory',
    ];

    // ── P2: SummaryMemory — compresse si le contexte dépasse 40k tokens ──
    if (_estimateTokens(_agentMessages) > 40000) {
      await _compressOldMessages(model);
    }

    // Construit l'historique au format OpenAI (après compression éventuelle)
    final history = <Map<String, dynamic>>[];
    for (final message in _agentMessages) {
      final role = message['role']?.toString();
      final content = message['text']?.toString() ?? '';
      if ((role == 'user' || role == 'agent') && content.isNotEmpty) {
        history.add(<String, dynamic>{
          'role': role == 'user' ? 'user' : 'assistant',
          'content': content,
        });
      }
    }
    final messages = <Map<String, dynamic>>[
      ...history,
      <String, dynamic>{'role': 'user', 'content': text},
    ];
    PandaLog.d(
      'PandaAgent',
      'Conversation prepared — messages=${messages.length} '
      'tokens≈${_estimateTokens(_agentMessages)} '
      'projectMemory=${projectMemory.isNotEmpty}',
    );

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

    PandaLog.i(
      'PandaAgent',
      'Starting AgentRunner — model=${model.runtimeType} mode=$_agentChatMode',
    );
    _agentRunner
        .run(
          model: model,
          messages: messages,
          context: context,
          workspacePath: workspacePath,
          agentMode: _agentChatMode,
          systemPromptOverride: systemPromptParts.isEmpty
              ? null
              : systemPromptParts.join('\n\n'),
        )
        .listen(
          (chunk) {
            if (!mounted || requestId != _agentRequestSerial) return;
            setState(() {
              switch (chunk.phase) {
                case AgentPhase.thinking:
                  _agentPhase = AgentPhase.thinking;
                  _agentThinkingBuf += chunk.text;
                  _agentMessages[agentIdx]['thinking'] = _agentThinkingBuf;
                case AgentPhase.toolRunning:
                  _agentPhase = AgentPhase.toolRunning;
                  _agentCurrentTool = chunk.toolName ?? '';
                  _agentMessages[agentIdx]['toolName'] = _agentCurrentTool;
                  // Append a running tool call entry
                  final runningCalls = List<Map<String,dynamic>>.from(
                    (_agentMessages[agentIdx]['toolCalls'] as List?)
                        ?.cast<Map<String,dynamic>>() ?? []);
                  runningCalls.add({
                    'name': chunk.toolName ?? '',
                    'args': chunk.toolArgs ?? {},
                    'result': null,
                    'status': 'running',
                  });
                  _agentMessages[agentIdx]['toolCalls'] = runningCalls;
                case AgentPhase.toolDone:
                  _agentCurrentTool = '';
                  // Find last entry with matching name and update it
                  final doneCalls = List<Map<String,dynamic>>.from(
                    (_agentMessages[agentIdx]['toolCalls'] as List?)
                        ?.cast<Map<String,dynamic>>() ?? []);
                  final idx = doneCalls.lastIndexWhere(
                    (c) => c['name'] == chunk.toolName && c['status'] == 'running',
                  );
                  if (idx >= 0) {
                    doneCalls[idx] = {
                      ...doneCalls[idx],
                      'result': chunk.toolResult ?? '',
                      'status': 'done',
                    };
                  }
                  _agentMessages[agentIdx]['toolCalls'] = doneCalls;
                case AgentPhase.streaming:
                  _agentPhase = AgentPhase.streaming;
                  _agentCurrentTool = '';
                  _agentStreamBuf += chunk.text;
                  _agentMessages[agentIdx]['text'] = _agentStreamBuf;
                case AgentPhase.done:
                  _agentPhase = AgentPhase.done;
                  _agentCurrentTool = '';
                  _agentGenerating = false;
                  _agentMessages[agentIdx]['phase'] = 'done';
                  _sendAnimCtrl.stop();
                case AgentPhase.error:
                  _agentPhase = AgentPhase.error;
                  _agentCurrentTool = '';
                  _agentGenerating = false;
                  _sendAnimCtrl.stop();
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
            PandaLog.e('PandaAgent', 'Stream error', error: e);
            _sendAnimCtrl.stop();
            if (!mounted || requestId != _agentRequestSerial) return;
            setState(() {
              _agentGenerating = false;
              _agentPhase      = AgentPhase.error;
              _agentMessages[agentIdx]['text'] = 'Erreur : $e';
              _agentMessages[agentIdx]['phase'] = 'error';
            });
          },
          onDone: () {
            PandaLog.i('PandaAgent', 'Stream closed');
            _sendAnimCtrl.stop();
            if (!mounted ||
                requestId != _agentRequestSerial ||
                !_agentGenerating) {
              return;
            }
            setState(() {
              _agentGenerating = false;
              if (_agentPhase != AgentPhase.error) {
                _agentPhase = AgentPhase.done;
                _agentMessages[agentIdx]['phase'] = 'done';
              }
              _sendAnimCtrl.stop();
            });
            // Auto-save conversation to history after each complete exchange
            _autoSaveConversation();
            // After the FIRST exchange, fire an async LLM title generation
            if (_agentMessages.length == 2) {
              _generateConversationTitle();
            }
          },
        );
  }

  // ── Empty editor (shown when all tabs are closed) ────────────────────────
  Widget _buildEmptyEditor(BuildContext context, AppTheme appTheme) {
    final isDark = appTheme.isDark;
    final muted  = isDark ? Colors.grey[700]! : Colors.grey[400]!;
    final hint   = isDark ? Colors.grey[600]! : Colors.grey[400]!;
    return Stack(
      children: [
        Center(
          child: Opacity(
            opacity: 0.06,
            child: Image.asset(
              'assets/icons/app-icon.png',
              width: 180,
              height: 180,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Text('🐼', style: TextStyle(fontSize: 120)),
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 200),
              Text('Ouvrir un fichier pour commencer',
                  style: TextStyle(fontSize: 13, color: muted)),
              const SizedBox(height: 6),
              Text(
                'Ctrl+O  Ouvrir un fichier   •   Ctrl+Shift+E  Explorateur',
                style: TextStyle(fontSize: 11, color: hint),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Welcome page ──────────────────────────────────────────────────────────
  Widget _buildWelcomePage(
      BuildContext context, AppTheme appTheme, AppThemeState appThemestate) {
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
                    onTap: _openGithubTab,
                  ),
                  if (authState.isSignedIn)
                    _StartItem(
                      icon: Broken.add_circle,
                      label: 'Créer un dépôt GitHub…',
                      isDark: isDark,
                      onTap: _openGithubTab,
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
                          _openEditorTab(
                            rootDir:   entryPath,
                            isProject: true,
                            isCloned:  true,
                          );
                          return;
                        }
                        final matchingLang = languages
                            .where((l) => l.extension.contains(
                                path.extension(entryPath)
                                    .toLowerCase()
                                    .replaceFirst('.', '')))
                            .toList();
                        _openEditorTab(
                          file:            File(entryPath),
                          rootDir:         rootDir,
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
                        );
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
              onTap: () => _push(context, const MarketplacePage()),
            ),
            const SizedBox(height: 10),
            _WalkthroughCard(
              icon: Broken.programming_arrows,
              title: 'Cloner depuis GitHub',
              subtitle:
                  'Connectez votre compte GitHub et gérez vos dépôts directement.',
              isDark: isDark,
              onTap: _openGithubTab,
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
    ),   // Align
    );   // SingleChildScrollView / return
      }, // LayoutBuilder builder
    );   // LayoutBuilder
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

// ── _EditorTabConfig ──────────────────────────────────────────────────────────
// Holds the data needed to render an EditorPage inside a tab.
class _EditorTabConfig {
  final File?     file;
  final String    rootDir;
  final Language? languageDetails;
  final bool      isProject;
  final bool      isCloned;

  _EditorTabConfig({
    this.file,
    required this.rootDir,
    this.languageDetails,
    this.isProject = false,
    this.isCloned  = false,
  });
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

// ─────────────────────────────────────────────────────────────────────────────
// _ToolCallBlock — bloc expandable pour un appel d'outil (style Replit)
// ─────────────────────────────────────────────────────────────────────────────

class _ToolCallBlock extends StatefulWidget {
  final String toolName;
  final Map<String, dynamic> args;
  final String? result;
  final String status; // 'running' | 'done' | 'error'
  final bool isDark;
  final Color fg;
  final Color muted;

  const _ToolCallBlock({
    required this.toolName,
    required this.args,
    required this.result,
    required this.status,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  State<_ToolCallBlock> createState() => _ToolCallBlockState();
}

class _ToolCallBlockState extends State<_ToolCallBlock> {
  bool _expanded = false;

  // Icône par catégorie d'outil
  static IconData _iconFor(String name) {
    if (name.contains('read') || name.contains('Read')) return Broken.document_text;
    if (name.contains('write') || name.contains('Write') ||
        name.contains('edit') || name.contains('Edit')) return Broken.edit;
    if (name.contains('delete') || name.contains('Delete')) return Broken.trash;
    if (name.contains('shell') || name.contains('Shell') ||
        name.contains('command') || name.contains('Command')) return Broken.command_square;
    if (name.contains('git') || name.contains('Git')) return Broken.code_circle;
    if (name.contains('search') || name.contains('Search') ||
        name.contains('grep') || name.contains('Grep') ||
        name.contains('glob') || name.contains('Glob')) return Broken.search_normal;
    if (name.contains('list') || name.contains('List')) return Broken.folder;
    if (name.contains('web') || name.contains('Web') ||
        name.contains('link') || name.contains('Link')) return Broken.global;
    return Broken.code_1;
  }

  // Résumé compact des args (1 ligne max)
  static String _argsSummary(Map<String, dynamic> args) {
    if (args.isEmpty) return '';
    final first = args.values.first?.toString() ?? '';
    final preview = first.length > 40 ? '${first.substring(0, 40)}\u2026' : first;
    return preview;
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = widget.isDark;
    final isRunning = widget.status == 'running';
    final isError   = widget.result?.startsWith('Error') ?? false;

    final borderC = isDark ? const Color(0xff3a3a3a) : const Color(0xffdddddd);
    final bgC     = isDark ? const Color(0xff252526) : const Color(0xfff0f0f0);
    final iconC   = isRunning
        ? Colors.orange
        : isError
            ? Colors.red[400]!
            : Colors.green[400]!;

    return GestureDetector(
      onTap: widget.result != null
          ? () => setState(() => _expanded = !_expanded)
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: bgC,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderC),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header row ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                children: [
                  // Status indicator
                  if (isRunning)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.orange,
                      ),
                    )
                  else
                    Icon(_iconFor(widget.toolName), size: 12, color: iconC),
                  const SizedBox(width: 6),
                  // Tool name
                  Text(
                    widget.toolName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: widget.fg,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Args preview
                  Expanded(
                    child: Text(
                      _argsSummary(widget.args),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: widget.muted),
                    ),
                  ),
                  // Expand chevron (only when result available)
                  if (widget.result != null)
                    Icon(
                      _expanded ? Broken.arrow_up_2 : Broken.arrow_down_2,
                      size: 12,
                      color: widget.muted,
                    ),
                ],
              ),
            ),
            // ── Expanded result ────────────────────────────────────────
            if (_expanded && widget.result != null)
              Container(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xff1e1e1e)
                        : const Color(0xfffafafa),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: borderC),
                  ),
                  child: SelectableText(
                    widget.result!.length > 2000
                        ? '${widget.result!.substring(0, 2000)}\n\u2026 (tronqué)'
                        : widget.result!,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: isError ? Colors.red[400] : widget.fg,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Animated spinning indicator for agent thinking / streaming states.
class _AgentPhaseChip extends StatefulWidget {
  final AgentPhase phase;
  final bool       isDark;
  final String     toolName;
  const _AgentPhaseChip({
    required this.phase,
    required this.isDark,
    this.toolName = '',
  });

  @override
  State<_AgentPhaseChip> createState() => _AgentPhaseChipState();
}

class _AgentPhaseChipState extends State<_AgentPhaseChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>    _spin;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat();
    _spin = Tween<double>(begin: 0, end: 1).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String rawLabel;
    final Color color;
    switch (widget.phase) {
      case AgentPhase.thinking:
        rawLabel = 'Réflexion\u2026';
        color    = Colors.purple;
      case AgentPhase.toolRunning:
        rawLabel = widget.toolName.isNotEmpty ? widget.toolName : 'Outil\u2026';
        color    = Colors.orange;
      case AgentPhase.streaming:
        rawLabel = 'Génération\u2026';
        color    = _kAccent;
      case AgentPhase.error:
        rawLabel = 'Erreur';
        color    = Colors.red;
      default:
        rawLabel = '';
        color    = Colors.green;
    }
    if (rawLabel.isEmpty) return const SizedBox.shrink();
    final label = rawLabel;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(widget.isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Spinning square — inspired by Replit Agent cube
        AnimatedBuilder(
          animation: _spin,
          builder: (_, __) => Transform.rotate(
            angle: _spin.value * 6.2832,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: color.withOpacity(0.85),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
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

// ─────────────────────────────────────────────────────────────────────────────
// _MsgActionBtn — small icon+label action button for message bubbles
// ─────────────────────────────────────────────────────────────────────────────

class _MsgActionBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  final Color    muted;

  const _MsgActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: muted),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(fontSize: 11, color: muted)),
        ]),
      ),
    );
  }
}

// ── _SidebarClipper ────────────────────────────────────────────────────────────
// Rounds the top-right and bottom-right corners of the sidebar panel,
// giving it the "floating card" look from Scolaris.
class _SidebarClipper extends CustomClipper<Path> {
  static const double _radius = 20.0;

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - _radius, 0)
      ..quadraticBezierTo(size.width, 0, size.width, _radius)
      ..lineTo(size.width, size.height - _radius)
      ..quadraticBezierTo(
          size.width, size.height, size.width - _radius, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Minimal clickable item for the VSCode-style status bar.
// ── Panel toolbar button (used in bottom panel tab headers) ─────────────────
class _PanelToolbarBtn extends StatelessWidget {
  const _PanelToolbarBtn({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.fg,
    required this.activeFg,
    required this.onTap,
  });
  final IconData icon;
  final String   tooltip;
  final bool     active;
  final Color    fg;
  final Color    activeFg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Icon(icon, size: 14, color: active ? activeFg : fg),
        ),
      ),
    );
  }
}

// ── Problems panel content ────────────────────────────────────────────────
class _ProblemsPanel extends StatelessWidget {
  const _ProblemsPanel({
    required this.fg,
    required this.search,
    required this.filter,
  });
  final Color  fg;
  final String search;
  final int    filter; // 0=all 1=errors 2=warnings

  @override
  Widget build(BuildContext context) {
    final isEmpty = true; // TODO: wire to real diagnostics
    final label = search.isNotEmpty
        ? 'No problems matching "$search"'
        : 'No problems have been detected in the workspace.';
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_outline, size: 32, color: fg.withOpacity(0.35)),
        const SizedBox(height: 8),
        Text(label,
          style: TextStyle(fontSize: 12, color: fg.withOpacity(0.6)),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

class _StatusBarItem extends StatelessWidget {
  final IconData      icon;
  final String        label;
  final Color         fg;
  final VoidCallback  onTap;

  const _StatusBarItem({
    required this.icon,
    required this.label,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: fg),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 11, color: fg, height: 1)),
          ],
        ]),
      ),
    );
  }
}
