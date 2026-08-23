import 'dart:async';
import 'dart:convert';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'utils/llama_wrapper.dart';
import 'package:path_provider/path_provider.dart';
import 'bloc/repo_bloc/repo_bloc.dart';
import 'bloc/ui_bloc/ui_bloc.dart';
import 'extensions/extension_api_router.dart';
import 'extensions/extension_host_setup.dart';
import 'extensions/extension_registry.dart';
import 'ui/start_screen.dart';
import 'ui/widgets/panda_theme_switch.dart';
import 'utils/functions.dart';
import 'utils/settings_service.dart';
import 'utils/themes.dart';
import 'logging/logging.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // RustLib uses dart:ffi / native Rust — skip on web to avoid runtime crash.
  if (!kIsWeb) {
    await RustLib.init();
  }
  // Shared storage roots and the extension host use Android-only paths and
  // native binaries. Keep iOS focused on the Flutter UI and Agent providers.
  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  if (isAndroid) {
    await configureStorageRoots();
    // Initialize logging system (non-blocking, wrapped for safety)
    try {
      await PandaLogger.init();
    } catch (e) {
      // Logging failure must never prevent app startup
      debugPrint('[Main] Logger init failed: $e');
    }
  }

  // Chaque lecture de prefs est protégée : une exception ici ne doit JAMAIS
  // empêcher runApp() (page blanche sur web sinon). Les fallbacks reproduisent
  // exactement les défauts des fonctions correspondantes.
  final recent = await _safe(getRecent, () => '[]');
  final appTheme = await _safe(getAppTheme, () => 'dark');
  final codeForgeConfig = await _safe(
    getCodeForgeConfig,
    () => jsonEncode(const <String, dynamic>{
      'indentLineStatus': true,
      'lineWrap': false,
      'enableFolding': true,
      'theme': 'vs2015',
      'terminalTheme': 'classic-green',
      'fontFamily': 'jetBrainsMono',
      'terminalFontSize': 14.0,
      'isAIEnabled': true,
      'manualCompletion': true,
      'autoSave': true,
      'enableLSP': true,
      'LSPFeatureToggle': <String, dynamic>{},
      'customEditorThemes': <String, dynamic>{},
    }),
  );
  final aiConfig = await _safe(getAiConfig, () => '{}');
  final modelSelected = await _safe(
      getModelSelected, () => jsonEncode(const {'code': '', 'chat': ''}));
  final sshServerList =
      await _safe(SSHInfo.getSavedSSHServers, () => <SSHInfo>[]);
  final termuxInfo = await TermuxCubit.getSavedTermuxInfo();

  // Initialize settings persistence (non-blocking, wrapped for safety)
  try {
    await SettingsService.instance;
  } catch (e) {
    debugPrint('[Main] SettingsService init failed: $e');
  }

  runApp(
    MainApp(
      recent: recent,
      appTheme: appTheme,
      codeForgeConfig: codeForgeConfig,
      aiConfig: aiConfig,
      modelSelected: modelSelected,
      sshSServerList: sshServerList,
      termuxInfo: termuxInfo,
    )
  );

  // Install crash handler AFTER runApp (never before splash)
  try {
    PandaCrashHandler.install();
  } catch (_) {}

  // Never hold Android's native splash screen while copying legacy storage
  // or extracting extension assets. Those operations are non-critical for
  // the first frame and may be slow or blocked by a storage provider.
  if (isAndroid) {
    unawaited(_finishAndroidStartup());
  }
}

/// Exécute [fn] et retombe sur [fallback] en cas d'erreur — jamais de crash
/// avant le premier frame.
Future<T> _safe<T>(Future<T> Function() fn, T Function() fallback) async {
  try {
    return await fn();
  } catch (e) {
    debugPrint('[Main] init failed, using fallback: $e');
    return fallback();
  }
}

Future<void> _finishAndroidStartup() async {
  try {
    await importPublicProjectsToPrivate().timeout(const Duration(seconds: 15));
  } catch (e) {
    // The migration can be retried by the explicit storage flow later.
    // ignore: avoid_print
    print('[StorageMigration] deferred: $e');
  }

  try {
    final dir = await getApplicationDocumentsDirectory();
    ExtensionRegistry.setRoot(dir.path);
    final sharedPath = await NativeChannel.getLibraryPath();
    await ExtensionHostSetup.init(sharedPath: sharedPath)
        .timeout(const Duration(seconds: 20));
  } catch (e) {
    // Extensions are optional; the editor must remain usable without them.
    // ignore: avoid_print
    print('[ExtensionHost] deferred: $e');
  }
}

// ── Palette ────────────────────────────────────────────────────────────────────
const _kAccent = Color(0xff5090c8);

ColorScheme _darkScheme() => ColorScheme(
  brightness: Brightness.dark,
  primary:              _kAccent,
  onPrimary:            Colors.white,
  primaryContainer:     const Color(0xff1a3a55),
  onPrimaryContainer:   Colors.white,
  secondary:            const Color(0xff7aabdd),
  onSecondary:          Colors.black,
  secondaryContainer:   const Color(0xff1c3548),
  onSecondaryContainer: Colors.white,
  tertiary:             const Color(0xff9ec3e8),
  onTertiary:           Colors.black,
  tertiaryContainer:    const Color(0xff1d3045),
  onTertiaryContainer:  Colors.white,
  error:                const Color(0xffcf6679),
  onError:              Colors.white,
  errorContainer:       const Color(0xff5c1826),
  onErrorContainer:     Colors.white,
  surface:              const Color(0xff252525),
  onSurface:            const Color(0xffe0e0e0),
  surfaceContainerHighest: const Color(0xff333333),
  outline:              const Color(0xff555555),
  outlineVariant:       const Color(0xff3a3a3a),
  shadow:               Colors.black,
  scrim:                Colors.black,
  inverseSurface:       Colors.white,
  onInverseSurface:     Colors.black,
  inversePrimary:       _kAccent,
);

ColorScheme _lightScheme() => ColorScheme(
  brightness: Brightness.light,
  primary:              _kAccent,
  onPrimary:            Colors.white,
  primaryContainer:     const Color(0xffd0e6f8),
  onPrimaryContainer:   const Color(0xff0d2a45),
  secondary:            const Color(0xff4a7aaa),
  onSecondary:          Colors.white,
  secondaryContainer:   const Color(0xffcce0f5),
  onSecondaryContainer: const Color(0xff0d2a45),
  tertiary:             const Color(0xff2d6ea0),
  onTertiary:           Colors.white,
  tertiaryContainer:    const Color(0xffbbe3ff),
  onTertiaryContainer:  const Color(0xff0d2a45),
  error:                const Color(0xffba1a1a),
  onError:              Colors.white,
  errorContainer:       const Color(0xffffdad6),
  onErrorContainer:     const Color(0xff410002),
  surface:              const Color(0xfffafafa),
  onSurface:            const Color(0xff1a1a1a),
  surfaceContainerHighest: const Color(0xffe8e8e8),
  outline:              const Color(0xff9e9e9e),
  outlineVariant:       const Color(0xffcccccc),
  shadow:               Colors.black,
  scrim:                Colors.black,
  inverseSurface:       const Color(0xff2d2d2d),
  onInverseSurface:     Colors.white,
  inversePrimary:       _kAccent,
);

// ── MainApp ────────────────────────────────────────────────────────────────────

class MainApp extends StatelessWidget {
  final String recent, appTheme, codeForgeConfig, aiConfig, modelSelected;
  final List<SSHInfo> sshSServerList;
  final SSHPrivateKey? termuxInfo;
  const MainApp({
      super.key,
      required this.recent,
      required this.appTheme,
      required this.codeForgeConfig,
      required this.aiConfig,
      required this.modelSelected,
      required this.sshSServerList,
      required this.termuxInfo
    });

  @override
  Widget build(BuildContext context) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    // Wire ExtensionApiRouter une seule fois au démarrage (Android uniquement).
    if (isAndroid) {
      ExtensionApiRouter.instance.attachToManager();
    }
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ConfigBloc(codeForgeConfig: jsonDecode(codeForgeConfig))),
        BlocProvider(create: (_) => FolderBloc()),
        BlocProvider(create: (_) => GitCommitBloc()),
        BlocProvider(create: (_) => RepoStatusBloc()),
        BlocProvider(create: (_) => RecentBloc(recent: jsonDecode(recent))),
        BlocProvider(create: (_) => AppThemeBloc(appTheme: themeMap[appTheme]!)),
        BlocProvider(create: (_) => WebViewBloc()),
        BlocProvider(create: (_) => MenuSearchBloc()),
        BlocProvider(create: (_) => DownloadManagerBloc()),
        BlocProvider(create: (_) => PackageCatalogCubit()),
        BlocProvider(create: (_) => GithubAuthCubit()),
        BlocProvider(create: (_) => ChatSessionBloc()..add(LoadChatSessions())),
        BlocProvider(create: (_) => GeneralBloc({"autoSave": jsonDecode(codeForgeConfig)['autoSave'] as bool})),
        BlocProvider(create: (_) => CopilotBloc()),
        BlocProvider(create: (context) => AIBloc(
          jsonDecode(aiConfig),
          jsonDecode(codeForgeConfig)['isAIEnabled'] as bool,
          jsonDecode(modelSelected),
          jsonDecode(codeForgeConfig)['manualCompletion'] as bool,
          copilotBloc: context.read<CopilotBloc>(),
        )),
        BlocProvider(create: (_) => CopilotChatBloc()),
        BlocProvider(create: (_) => LocalLlamaBloc()),
        BlocProvider(create: (_) => GgufDownloadCubit()),
        BlocProvider(create: (_) => SSHServersCubit(sshSServerList)),
        BlocProvider(create: (_) => TermuxCubit(termuxInfo)),
        BlocProvider(create: (_) => CurrentlySelectedTerminalCubit()),
        BlocProvider(create: (_) => SelectedRuntimeEnvironmentCubit()),
      ],
      child: BlocBuilder<AppThemeBloc, AppThemeState>(
        builder: (context, appThemeState) {
          final isDark = appThemeState.appTheme.isDark;
          // Fournir le BuildContext live à l'ExtensionApiRouter (Android uniquement).
          if (isAndroid) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ExtensionApiRouter.instance.setContext(context);
            });
          }
          context.read<GgufDownloadCubit>().onTaskCompleted = (task) async {
            final result = await GgufModel.registerGgufModelWithAI(task);
            if (context.mounted) {
              context.read<AIBloc>().add(AIConfigEvent(result.aiConfig));
              context.read<AIBloc>().add(ModelSelectEvent(result.modelSelected));
              context.read<GgufDownloadCubit>().markTaskRegistered(task.taskId);
            }
          };
          return MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: isDark ? _darkScheme() : _lightScheme(),
              brightness: isDark ? Brightness.dark : Brightness.light,
              progressIndicatorTheme: progressTheme,
              popupMenuTheme: appThemeState.appTheme.popupBtnTheme,
              scaffoldBackgroundColor: appThemeState.appTheme.scaffoldBg,
              appBarTheme: appThemeState.appTheme.appBarTheme,
              listTileTheme: appThemeState.appTheme.tileTheme,
              cardTheme: appThemeState.appTheme.cardTheme.data,
              textSelectionTheme: const TextSelectionThemeData(
                selectionHandleColor: _kAccent,
              ),
            ),
            // Propagation animee du theme : englobe tout le navigateur pour
            // que les routes/dialogues soient couverts par le reveal.
            builder: (context, child) =>
                ThemeSwitchScope(child: child ?? const SizedBox.shrink()),
            home: SafeArea(
              top: false,
              child: const StartScreen()
            ),
          );
        },
      ),
    );
  }
}
