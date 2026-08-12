import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:code_forge/code_forge.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_svg/svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:re_highlight/styles/vs2015.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/xterm.dart';
import '../utils/constants.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../utils/functions.dart';
import '../utils/languages.dart';
import '../utils/themes.dart';
import 'browser/settings/browser_settings_page.dart';
import 'downloads.dart';
import 'adb_setup_page.dart';
import 'widgets.dart';
import '../extensions/ui/marketplace_page.dart';


enum _SettingsSection {
  general,
  editor,
  terminal,
  performance,
  aiAndApi,
  about,
}

class _SettingsPillNav extends StatelessWidget {
  final _SettingsSection current;
  final ValueChanged<_SettingsSection> onTap;

  const _SettingsPillNav({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final items = [
      (section: _SettingsSection.general, icon: Icons.palette_outlined, activeIcon: Icons.palette_rounded, label: 'Général & Apparence'),
      (section: _SettingsSection.editor, icon: Icons.code_outlined, activeIcon: Icons.code_rounded, label: 'Éditeur & Code'),
      (section: _SettingsSection.terminal, icon: Icons.terminal_outlined, activeIcon: Icons.terminal_rounded, label: 'Terminal & Shell'),
      (section: _SettingsSection.performance, icon: Icons.speed_outlined, activeIcon: Icons.speed_rounded, label: 'Performance & RAM'),
      (section: _SettingsSection.aiAndApi, icon: Icons.security_outlined, activeIcon: Icons.security_rounded, label: 'IA & Clés API'),
      (section: _SettingsSection.about, icon: Icons.info_outline_rounded, activeIcon: Icons.info_rounded, label: 'À propos & Système'),
    ];

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff18181b) : const Color(0xfff4f4f5),
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.25))),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          final sel = item.section == current;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => onTap(item.section),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? cs.primary.withValues(alpha: 0.16) : (isDark ? const Color(0xff27272a) : Colors.white),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: sel ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4),
                      width: sel ? 1.4 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        sel ? item.activeIcon : item.icon,
                        size: 16,
                        color: sel ? cs.primary : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel ? cs.primary : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class Settings extends StatefulWidget {
  /// When [embedded] is true, the widget skips its own Scaffold/AppBar
  /// so it can be displayed inside an editor tab without a nested navigation bar.
  final bool embedded;
  const Settings({super.key, this.embedded = false});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {

  _SettingsSection _selectedSection = _SettingsSection.general;
  String _currentLanguage = 'Français 🇫🇷';
  double _uiScale = 1.0;
  double _ramLimitGb = 4.0;
  bool _gpuAccelerated = true;

  late final Terminal terminal;
  SshKeygen? _sshKeygen;
  final apiController = TextEditingController();
  final modelNameController = TextEditingController(), modelIdController = TextEditingController();
  final scrollController = ScrollController(), terminalThemeScroll = ScrollController();
  final sshUrlController = TextEditingController(), sshServerNameController = TextEditingController();
  final sshPasswordController = TextEditingController();
  final themeScroll = ScrollController(), fontScroll = ScrollController();
  final _formKey = GlobalKey<FormState>(), _sshFormKey = GlobalKey<FormState>(), _sshUpdationKey = GlobalKey<FormState>();
  final _ggufKey = GlobalKey<FormState>(), _themeKey = GlobalKey<FormState>();
  bool? _isGeneratedKey;
  int sshStackIndex = 0;
  static const String _defaultEditorThemeName = 'vs2015';
  final List<Map<String, dynamic>> _ggufModels = [
    {
      'name': 'Qwen2.5-Coder-3B',
      'url': 'https://huggingface.co/bartowski/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-3B-Instruct-Q6_K.gguf',
      'filename': 'Qwen2.5-Coder-3B-Instruct-Q6_K.gguf',
      'param-size': 3,
      'quant': 'Q6_K',
      'image-url': 'https://cdn-avatars.huggingface.co/v1/production/uploads/620760a26e3b7210c2ff1943/-s1gyJfvbE1RgO5iBeNOi.png'
    },
    {
      'name': 'Phi-3.5-mini',
      'url': 'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q6_K.gguf',
      'filename': 'Phi-3.5-mini-instruct-Q6_K.gguf',
      'param-size': 3.8,
      'quant': 'Q6_K',
      'image-url': 'https://cdn-avatars.huggingface.co/v1/production/uploads/1583646260758-5e64858c87403103f9f1055d.png'
    },
    {
      'name': 'Phi-3-mini-4k',
      'url': 'https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q6_K.gguf',
      'filename': 'Phi-3-mini-4k-instruct-Q6_K.gguf',
      'param-size': 3.8,
      'quant': 'Q6_K',
      'image-url': 'https://cdn-avatars.huggingface.co/v1/production/uploads/1583646260758-5e64858c87403103f9f1055d.png'
    },
    {
      'name': 'Qwen2.5.1-Coder-1.5B',
      'url': 'https://huggingface.co/bartowski/Qwen2.5.1-Coder-1.5B-Instruct-GGUF/resolve/main/Qwen2.5.1-Coder-1.5B-Instruct-Q6_K.gguf',
      'filename': 'Qwen2.5.1-Coder-1.5B-Instruct-Q6_K.gguf',
      'param-size': 1.5,
      'quant': 'Q6_K',
      'image-url': 'https://cdn-avatars.huggingface.co/v1/production/uploads/620760a26e3b7210c2ff1943/-s1gyJfvbE1RgO5iBeNOi.png'
    },
    { 
      'name': 'deepseek-coder-1.3B',
      'url': 'https://huggingface.co/bartowski/deepseek-coder-1.3B-kexer-GGUF/resolve/main/deepseek-coder-1.3B-kexer-Q6_K.gguf',
      'filename': 'deepseek-coder-1.3B-kexer-Q6_K.gguf',
      'param-size': 1.3,
      'quant': 'Q6_K',
      'image-url': 'https://cdn-avatars.huggingface.co/v1/production/uploads/6538815d1bdb3c40db94fbfa/xMBly9PUMphrFVMxLX4kq.png'
    },
    {
      'name': 'Granite-Code-3B',
      'url': 'https://huggingface.co/unsloth/granite-4.1-3b-GGUF/resolve/main/granite-4.1-3b-Q6_K.gguf',
      'filename': 'granite-code-3b-instruct-Q6_K.gguf',
      'param-size': 3,
      'quant': 'Q6_K',
      'image-url': 'https://cdn-avatars.huggingface.co/v1/production/uploads/6602b217c774ff142b1493ef/Tvie7jwa9ggFjrQ5ty_Br.webp'
    },
    {
      'name': 'Gemma-2-2B',
      'url': 'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q6_K.gguf',
      'filename': 'gemma-2-2b-it-Q6_K.gguf',
      'param-size': 2,
      'quant': 'Q6_K',
      'image-url': 'https://cdn-avatars.huggingface.co/v1/production/uploads/5dd96eb166059660ed1ee413/WtA3YYitedOr9n02eHfJe.png'
    },
    {
      'name': 'CodeLlama-7B',
      'url': 'https://huggingface.co/TheBloke/CodeLlama-7B-Instruct-GGUF/resolve/main/codellama-7b-instruct.Q4_K_M.gguf',
      'filename': 'CodeLlama-7B-Instruct-Q4_K_M.gguf',
      'param-size': 7,
      'quant': 'Q4_K_M',
      'image-url': 'https://cdn-avatars.huggingface.co/v1/production/uploads/646cf8084eefb026fb8fd8bc/oCTqufkdTkjyGodsx1vo1.png'
    }
  ];
  final String demoCode =
'''
#include <stdio.h>

int main() {
    int n = 10, t1 = 0, t2 = 1, nextTerm;
    printf("Fibonacci Series: ");
    for (int i = 1; i <= n; ++i) {
        printf("%d ", t1);
        nextTerm = t1 + t2;
        t1 = t2;
        t2 = nextTerm;
    }
    return 0;
}''';
  final List<String> models = [
    "Gemini",
    "Claude",
    "OpenAI",
    "Grok",
    "DeepSeek",
    "Gorq",
    "TogetherAI",
    "Perplexity",
    "OpenRouter",
    "FireWorks",
    "Custom",
    "LocalLlama"
    ];

  @override
  void initState() {
    super.initState();

    if (!kIsWeb) {
      _sshKeygen = SshKeygen(comment: "user@panda-IDE");
      if (SshKeygen.publicKeyFilelocation.existsSync() &&
          SshKeygen.privateKeyFilelocation.existsSync()) {
        _isGeneratedKey = true;
      }
      _initializeCopilotForSettingsWhenDisabled();
    }
    terminal = Terminal(platform: TerminalTargetPlatform.android);
    _seedTerminalPreview();
  }

  void _seedTerminalPreview() {
    terminal.write(
      '\x1b[1;32mpanda\x1b[0m@\x1b[1;34mdevice\x1b[0m:\x1b[36m~/workspace\x1b[0m\$ '
      'git status\r\n',
    );
    terminal.write('On branch playstore-version\r\n');
    terminal.write('nothing to commit, working tree clean\r\n\r\n');
    terminal.write('status: \x1b[32mOK\x1b[0m  ');
    terminal.write('warn: \x1b[33m2\x1b[0m  ');
    terminal.write('errors: \x1b[31m0\x1b[0m\r\n');
  }

  Future<void> _initializeCopilotForSettingsWhenDisabled() async {
    final isCopilotEnabled = await isCopilotEnabledPref();
    if (isCopilotEnabled || !mounted) {
      return;
    }

    if (!Directory('$extensionDir/copilot-language-server').existsSync()) {
      return;
    }

    final copilotBloc = context.read<CopilotBloc>();
    if (copilotBloc.state.isInitialized || copilotBloc.state.status == CopilotStatus.initializing) {
      return;
    }

    copilotBloc.add(CopilotInitialize(configPath: filesDir));
  }

  Widget _buildCopilotButton(BuildContext context, CopilotState copilotState, AppThemeState appThemeState) {
    final status = copilotState.status;
    String buttonText;
    Color buttonColor;
    VoidCallback? onPressed;
    bool showLoading = false;

    switch (status) {
      case CopilotStatus.notInitialized:
      case CopilotStatus.notSignedIn:
        buttonText = "Login to GitHub Copilot";
        buttonColor = Color(0xff007acc);
        onPressed = () => _startCopilotSignIn(context, appThemeState);
        break;
      case CopilotStatus.initializing:
      case CopilotStatus.signingIn:
        buttonText = "Connecting...";
        buttonColor = Colors.grey;
        showLoading = true;
        onPressed = null;
        break;
      case CopilotStatus.signedIn:
        buttonText = copilotState.user != null
            ? "Signed in as ${copilotState.user}"
            : "GitHub Copilot Connected";
        buttonColor = Colors.green;
        onPressed = () => _showCopilotSettings(context, copilotState, appThemeState);
        break;
      case CopilotStatus.notAuthorized:
        buttonText = "Copilot Not Authorized";
        buttonColor = Colors.orange;
        onPressed = () => _showNotAuthorizedDialog(context, appThemeState);
        break;
      case CopilotStatus.error:
        buttonText = "Connection Error";
        buttonColor = Colors.red;
        onPressed = () => _startCopilotSignIn(context, appThemeState);
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 15),
      child: SizedBox(
        width: 280,
        height: 45,
        child: ElevatedButton(
          onPressed: () => onPressed?.call(),
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            backgroundColor: WidgetStatePropertyAll(buttonColor),
          ),
          child: showLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                spacing: 7.5,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/icons/github-copilot-icon.svg',
                    height: 20,
                    width: 20,
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  ),
                  Flexible(
                    child: Text(
                      buttonText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }

  List<String> _missingCopilotPrerequisites() {
    final missing = <String>[];
    if (!Directory('$extensionDir/copilot-language-server').existsSync()) {
      missing.add('GitHub Copilot extension');
    }
    if (!File('$binDir/node').existsSync()) {
      missing.add('Node runtime');
    }
    return missing;
  }

  void _showCopilotPrerequisiteDialog(
    BuildContext context,
    AppThemeState appThemeState,
    List<String> missing,
  ) {
    final textColor = appThemeState.appTheme.selectScreenCardTextColor;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: appThemeState.appTheme.isDark
            ? const Color(0xff2b2b2b)
            : const Color.fromARGB(255, 240, 240, 240),
          title: Text('Copilot Setup Required', style: TextStyle(color: textColor)),
          content: Text(
            'Before signing in, please install: ${missing.join(' and ')}.\n\nOpen Downloads to install them.',
            style: TextStyle(color: textColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const MarketplacePage(),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      return SizeTransition(sizeFactor: animation, child: child);
                    },
                  ),
                );
              },
              child: const Text('Open Downloads'),
            ),
          ],
        );
      },
    );
  }

  void _showNodeRuntimeRequiredDialog(
    BuildContext context,
    AppThemeState appThemeState,
  ) {
    final textColor = appThemeState.appTheme.selectScreenCardTextColor;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: appThemeState.appTheme.isDark
            ? const Color(0xff2b2b2b)
            : const Color.fromARGB(255, 240, 240, 240),
          title: Text('Node Runtime Required', style: TextStyle(color: textColor)),
          content: Text(
            'GitHub Copilot sign-in requires the Node.js runtime.\n\nPlease install Node.js from the Marketplace (Runtimes tab) before continuing.',
            style: TextStyle(color: textColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const MarketplacePage(),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      return SizeTransition(sizeFactor: animation, child: child);
                    },
                  ),
                );
              },
              child: const Text('Open Downloads'),
            ),
          ],
        );
      },
    );
  }

  void _startCopilotSignIn(BuildContext context, AppThemeState appThemeState) async {
    final missing = _missingCopilotPrerequisites();
    if (missing.isNotEmpty) {
      if (missing.length == 1 && missing.first == 'Node runtime') {
        _showNodeRuntimeRequiredDialog(context, appThemeState);
      } else {
        _showCopilotPrerequisiteDialog(context, appThemeState, missing);
      }
      return;
    }

    final copilotBloc = context.read<CopilotBloc>();

    if (copilotBloc.state.status == CopilotStatus.notInitialized) {
      copilotBloc.add(CopilotInitialize(configPath: filesDir));

      await Future.delayed(const Duration(seconds: 2));
    }

    copilotBloc.add(CopilotSignInInitiate());

    if (context.mounted) {
      _showSignInDialog(context, appThemeState);
    }
  }

  void _showSignInDialog(BuildContext context, AppThemeState appThemeState) {
    final isDark = appThemeState.appTheme.isDark;
    final textColor = appThemeState.appTheme.selectScreenCardTextColor;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return BlocBuilder<CopilotBloc, CopilotState>(
          builder: (context, state) {
            if (state.status == CopilotStatus.signedIn) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.white),
                          const SizedBox(width: 12),
                          Text('Signed in as ${state.user ?? "user"}'),
                        ],
                      ),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              });
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: 340,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                        : [const Color(0xfffafafa), const Color(0xfff0f0f0)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xff0078d4).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SvgPicture.asset(
                            'assets/icons/github-copilot-icon.svg',
                            height: 28,
                            width: 28,
                            colorFilter: ColorFilter.mode(
                              isDark ? Colors.white : const Color(0xff0078d4),
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'GitHub Copilot',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Sign in to continue',
                                style: TextStyle(
                                  color: textColor.withValues(alpha: 0.6),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: Icon(
                            Icons.close,
                            color: textColor.withValues(alpha: 0.5),
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSignInDialogContent(state, context, appThemeState),
                    const SizedBox(height: 24),
                    if (state.signInPayload != null && state.status != CopilotStatus.signedIn)
                      _buildSignInButton(context, state, isDark),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSignInButton(BuildContext context, CopilotState state, bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: () async {
          final code = state.signInPayload!.userCode;
          if (code != null) {
            await Clipboard.setData(ClipboardData(text: code));
          }

          const url = 'https://github.com/login/device';
          final uri = Uri.parse(url);
          try {
            await launchUrl(uri, mode: LaunchMode.inAppWebView);
          } catch (e) {
            debugPrint('Failed to launch URL: $e');
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xff238636),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.open_in_browser, size: 20),
            SizedBox(width: 8),
            Text(
              'Sign in with GitHub',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignInDialogContent(CopilotState state, BuildContext context, AppThemeState appThemeState) {
    final isDark = appThemeState.appTheme.isDark;
    final textColor = appThemeState.appTheme.selectScreenCardTextColor;

    if (state.status == CopilotStatus.signingIn && state.signInPayload == null) {
      return SizedBox(
        height: 120,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDark ? Colors.white : const Color(0xff0078d4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Connecting to GitHub...',
              style: TextStyle(
                color: textColor.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (state.signInPayload != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Your code',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  state.signInPayload!.userCode ?? '',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                    fontFamily: 'monospace',
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              final code = state.signInPayload!.userCode;
              if (code != null) {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('Code copied!'),
                      ],
                    ),
                    backgroundColor: const Color(0xff238636),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: Icon(
              Icons.copy_rounded,
              size: 18,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            label: Text(
              'Copy code',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff0078d4).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: isDark ? Colors.lightBlueAccent : const Color(0xff0078d4),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Click the button below to open GitHub.\nPaste the code when prompted.',
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (state.status == CopilotStatus.error) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              state.error ?? 'An error occurred',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                context.read<CopilotBloc>().add(CopilotSignInInitiate());
              },
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  void _showCopilotSettings(BuildContext context, CopilotState state, AppThemeState appThemeState) {
    final isDark = appThemeState.appTheme.isDark;
    final textColor = appThemeState.appTheme.selectScreenCardTextColor;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [const Color(0xfffafafa), const Color(0xfff0f0f0)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SvgPicture.asset(
                        'assets/icons/github-copilot-icon.svg',
                        height: 28,
                        width: 28,
                        colorFilter: ColorFilter.mode(
                          Colors.green,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GitHub Copilot',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Connected',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(
                        Icons.close,
                        color: textColor.withValues(alpha: 0.5),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // User info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xff238636).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person,
                          color: Color(0xff238636),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.user ?? 'User',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'GitHub Account',
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                BlocBuilder<CopilotBloc, CopilotState>(
                  builder: (context, copilotState) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                copilotState.isEnabled
                                    ? Icons.auto_awesome
                                    : Icons.auto_awesome_outlined,
                                color: copilotState.isEnabled
                                    ? const Color(0xff238636)
                                    : textColor.withValues(alpha: 0.5),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Enable Copilot',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Switch(
                            value: copilotState.isEnabled,
                            activeThumbColor: const Color(0xff238636),
                            onChanged: (value) {
                              context.read<CopilotBloc>().add(CopilotSetEnabled(value));
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context.read<CopilotBloc>().add(CopilotSignOut());
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Row(
                            children: [
                              Icon(Icons.logout, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text('Signed out from Copilot'),
                            ],
                          ),
                          backgroundColor: Colors.grey[700],
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      );
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign Out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showNotAuthorizedDialog(BuildContext context, AppThemeState appThemeState) {
    final isDark = appThemeState.appTheme.isDark;
    final textColor = appThemeState.appTheme.selectScreenCardTextColor;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [const Color(0xfffafafa), const Color(0xfff0f0f0)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  'Not Authorized',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  'Your GitHub account does not have access to GitHub Copilot. Please ensure you have an active Copilot subscription.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.7),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Returns a brand color for the given provider name.
  Color _providerColor(String? provider) {
    switch (provider) {
      case 'Gemini':    return const Color(0xFF4285F4);
      case 'Claude':    return const Color(0xFFD4875C);
      case 'OpenAI':    return const Color(0xFF10A37F);
      case 'Grok':      return const Color(0xFF1D9BF0);
      case 'Gorq':      return const Color(0xFFF55036);
      case 'DeepSeek':  return const Color(0xFF4A6CF7);
      case 'TogetherAI':return const Color(0xFF7C3AED);
      case 'Perplexity':return const Color(0xFF20B2AA);
      case 'OpenRouter':return const Color(0xFFFF6B35);
      case 'FireWorks': return const Color(0xFFFF4500);
      case 'Custom':    return const Color(0xFF6B7280);
      case 'LocalLlama':return const Color(0xFF059669);
      default:          return Colors.lightBlue;
    }
  }

  /// Returns an icon for the given provider name.
  IconData _providerIcon(String? provider) {
    switch (provider) {
      case 'Gemini':    return Icons.auto_awesome;
      case 'Claude':    return Icons.psychology;
      case 'OpenAI':    return Icons.bubble_chart;
      case 'Grok':      return Icons.flash_on;
      case 'Gorq':      return Icons.speed;
      case 'DeepSeek':  return Icons.search;
      case 'TogetherAI':return Icons.group;
      case 'Perplexity':return Icons.travel_explore;
      case 'OpenRouter':return Icons.route;
      case 'FireWorks': return Icons.local_fire_department;
      case 'Custom':    return Icons.tune;
      case 'LocalLlama':return Icons.computer;
      default:          return Icons.smart_toy_outlined;
    }
  }

  void _clearModelDialogControllers() {
    apiController.clear();
    modelNameController.clear();
    modelIdController.clear();
  }

  /// Returns a per-provider placeholder hint for the model name text field.
  String _modelNameHintForProvider(String? provider) {
    switch (provider) {
      case 'Gemini':
        return 'e.g. gemini-2.0-flash';
      case 'Claude':
        return 'e.g. claude-opus-4-5';
      case 'OpenAI':
        return 'e.g. gpt-4o';
      case 'Grok':
        return 'e.g. grok-3';
      case 'DeepSeek':
        return 'e.g. deepseek-chat';
      case 'Gorq':
        return 'e.g. llama-3.3-70b-versatile';
      case 'TogetherAI':
        return 'e.g. meta-llama/Llama-3-70b-chat-hf';
      case 'Perplexity':
        return 'e.g. llama-3.1-sonar-large-128k-online';
      case 'OpenRouter':
        return 'e.g. anthropic/claude-3.5-sonnet';
      case 'FireWorks':
        return 'e.g. accounts/fireworks/models/llama-v3p1-70b-instruct';
      default:
        return "model name as per the provider's api";
    }
  }

  /// Guesses the provider from the API key format.
  String? _detectProviderFromKey(String key) {
    if (key.isEmpty) return null;
    if (key.startsWith('AIza') || key.startsWith('AQ.')) return 'Gemini';
    if (key.startsWith('sk-ant-')) return 'Claude';
    if (key.startsWith('xai-')) return 'Grok';
    if (key.startsWith('pplx-')) return 'Perplexity';
    if (key.startsWith('gsk_')) return 'Gorq';
    if (key.startsWith('together_')) return 'TogetherAI';
    if (key.startsWith('fw_')) return 'FireWorks';
    if (key.startsWith('sk-or-')) return 'OpenRouter';
    if (key.startsWith('sk-')) return 'OpenAI';
    return null;
  }

  /// Fetches the list of available model IDs from the provider's API.
  Future<List<String>> _fetchModelsForProvider(
      String provider, String apiKey) async {
    try {
      http.Response response;
      switch (provider) {
        case 'Gemini':
          response = await http.get(
            Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey&pageSize=100'),
          ).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final list = (data['models'] as List? ?? []);
            return list
                .map((m) => (m['name'] as String).replaceFirst('models/', ''))
                .where((n) => !n.contains('embedding') && !n.contains('aqa'))
                .toList()
              ..sort();
          }
          break;
        case 'Claude':
          response = await http.get(
            Uri.parse('https://api.anthropic.com/v1/models?limit=100'),
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
            },
          ).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final list = (data['data'] as List? ?? []);
            return list.map((m) => m['id'] as String).toList()..sort();
          }
          break;
        case 'OpenAI':
          response = await http.get(
            Uri.parse('https://api.openai.com/v1/models'),
            headers: {'Authorization': 'Bearer $apiKey'},
          ).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final list = (data['data'] as List? ?? []);
            final ids = list.map((m) => m['id'] as String).toList()..sort();
            // Prefer gpt/o- models first
            return ids
                .where((id) =>
                    id.startsWith('gpt-') ||
                    id.startsWith('o1') ||
                    id.startsWith('o3') ||
                    id.startsWith('o4'))
                .toList()
              ..addAll(ids
                  .where((id) =>
                      !id.startsWith('gpt-') &&
                      !id.startsWith('o1') &&
                      !id.startsWith('o3') &&
                      !id.startsWith('o4'))
                  .toList());
          }
          break;
        case 'Grok':
          response = await http.get(
            Uri.parse('https://api.x.ai/v1/models'),
            headers: {'Authorization': 'Bearer $apiKey'},
          ).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final list = (data['data'] as List? ?? []);
            return list.map((m) => m['id'] as String).toList()..sort();
          }
          break;
        case 'DeepSeek':
          response = await http.get(
            Uri.parse('https://api.deepseek.com/models'),
            headers: {'Authorization': 'Bearer $apiKey'},
          ).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final list = (data['data'] as List? ?? []);
            return list.map((m) => m['id'] as String).toList()..sort();
          }
          break;
        case 'Gorq':
          response = await http.get(
            Uri.parse('https://api.groq.com/openai/v1/models'),
            headers: {'Authorization': 'Bearer $apiKey'},
          ).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final list = (data['data'] as List? ?? []);
            return list.map((m) => m['id'] as String).toList()..sort();
          }
          break;
        case 'TogetherAI':
          response = await http.get(
            Uri.parse('https://api.together.xyz/v1/models'),
            headers: {'Authorization': 'Bearer $apiKey'},
          ).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            final list = jsonDecode(response.body) as List? ?? [];
            return list.map((m) => m['id'] as String).toList()..sort();
          }
          break;
        case 'Perplexity':
          // Perplexity doesn't have a public /models endpoint; return known models
          return [
            'llama-3.1-sonar-small-128k-online',
            'llama-3.1-sonar-large-128k-online',
            'llama-3.1-sonar-huge-128k-online',
            'llama-3.1-sonar-small-128k-chat',
            'llama-3.1-sonar-large-128k-chat',
          ];
        case 'OpenRouter':
          response = await http.get(
            Uri.parse('https://openrouter.ai/api/v1/models'),
            headers: {'Authorization': 'Bearer $apiKey'},
          ).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final list = (data['data'] as List? ?? []);
            return list.map((m) => m['id'] as String).toList()..sort();
          }
          break;
        case 'FireWorks':
          response = await http.get(
            Uri.parse('https://api.fireworks.ai/inference/v1/models'),
            headers: {'Authorization': 'Bearer $apiKey'},
          ).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final list = (data['data'] as List? ?? []);
            return list.map((m) => m['id'] as String).toList()..sort();
          }
          break;
        default:
          break;
      }
    } catch (_) {
      // network or parse error — caller shows message
    }
    return [];
  }

  Future<void> _showModelDialog({
    required BuildContext context,
    required AIState aiState,
    required AppThemeState appThemeState,
    String? editingModelId,
    Map<String, dynamic>? existingConfig,
  }) async {
    final isEditing = editingModelId != null && existingConfig != null;
    String? provider = isEditing
        ? (existingConfig['provider']?.toString() ?? existingConfig['apiProvider']?.toString())
        : null;
    String customHttpMethod = isEditing
        ? (existingConfig['httpMethod']?.toString() ?? 'POST')
        : 'POST';
    String customToolCallingMethod = isEditing
        ? (existingConfig['toolCallingMethod']?.toString() ?? 'openAiCompatible')
        : 'openAiCompatible';

    modelNameController.text = isEditing
        ? (existingConfig['modelName']?.toString() ?? existingConfig['model']?.toString() ?? '')
        : '';
    apiController.text = isEditing ? (existingConfig['apiKey']?.toString() ?? '') : '';
    modelIdController.text = isEditing ? editingModelId : '';

    final customUrlController = TextEditingController(
      text: isEditing ? (existingConfig['url']?.toString() ?? '') : '',
    );

    // Fetched model list — declared here so StatefulBuilder can call setDialogState on them.
    List<String> fetchedModels = isEditing
        ? [existingConfig?['modelName']?.toString() ?? existingConfig?['model']?.toString() ?? ''].where((s) => s.isNotEmpty).toList()
        : [];
    bool isFetchingModels = false;
    String? fetchError;

    try {
      await showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final isCustomProvider = provider == 'Custom';
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                backgroundColor: appThemeState.appTheme.isDark
                    ? const Color(0xff181A26)
                    : Colors.white,
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: appThemeState.appTheme.isDark
                          ? [const Color(0xff181A26), const Color(0xff1e1f2b)]
                          : [Colors.white, Colors.grey[100]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Animated header ────────────────────────────────────
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: [
                              _providerColor(provider).withAlpha(40),
                              _providerColor(provider).withAlpha(10),
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          border: Border.all(
                            color: _providerColor(provider).withAlpha(60),
                            width: 1,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: Icon(
                                _providerIcon(provider),
                                key: ValueKey(provider),
                                color: _providerColor(provider),
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isEditing ? 'Edit AI model' : 'Add AI model',
                                  style: TextStyle(
                                    color: appThemeState.appTheme.selectScreenCardTextColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (provider != null)
                                  Text(
                                    provider!,
                                    style: TextStyle(
                                      color: _providerColor(provider),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.disabled,
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              value: provider,
                              dropdownColor: appThemeState.appTheme.isDark
                                  ? const Color(0xff181A26)
                                  : Colors.white,
                              hint: Text(
                                'Select a Provider',
                                style: TextStyle(
                                  color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                ),
                              ),
                              decoration: InputDecoration(
                                prefixIcon: provider != null
                                    ? Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Icon(
                                          _providerIcon(provider),
                                          color: _providerColor(provider),
                                          size: 22,
                                        ),
                                      )
                                    : Icon(Icons.smart_toy_outlined, color: Colors.lightBlue),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide(
                                    color: _providerColor(provider),
                                    width: 2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide(
                                    color: provider != null
                                        ? _providerColor(provider).withAlpha(100)
                                        : Colors.grey.withAlpha(80),
                                  ),
                                ),
                              ),
                              items: List.generate(
                                models.length,
                                (index) => DropdownMenuItem(
                                  value: models[index],
                                  child: Row(
                                    children: [
                                      Icon(
                                        _providerIcon(models[index]),
                                        color: _providerColor(models[index]),
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        models[index],
                                        style: TextStyle(
                                          color: appThemeState.appTheme.selectScreenCardTextColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              onChanged: (val) {
                                setDialogState(() {
                                  provider = val;
                                  fetchedModels = [];
                                  fetchError = null;
                                  modelNameController.clear();
                                });
                              },
                              validator: (value) =>
                                  value == null ? 'Select a valid provider' : null,
                            ),
                            const SizedBox(height: 15),
                            // API Key field with auto-detect + load-models button
                            TextFormField(
                              style: TextStyle(
                                color: appThemeState.appTheme.selectScreenCardTextColor,
                              ),
                              controller: apiController,
                              cursorColor: Colors.lightBlue,
                              obscureText: true,
                              onChanged: (val) {
                                final detected = _detectProviderFromKey(val.trim());
                                if (detected != null && provider != detected) {
                                  setDialogState(() {
                                    provider = detected;
                                    fetchedModels = [];
                                    fetchError = null;
                                    modelNameController.clear();
                                  });
                                }
                              },
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.key, color: Colors.lightBlue),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide(
                                    color: Colors.lightBlue,
                                    width: 2,
                                  ),
                                ),
                                labelText: 'API Key',
                                hintText: isCustomProvider
                                    ? 'Optional: Bearer token for the custom endpoint'
                                    : 'API key for the corresponding provider',
                                hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                                labelStyle: TextStyle(
                                  color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                  fontSize: 15,
                                ),
                              ),
                              validator: (value) {
                                if (isCustomProvider) {
                                  return null;
                                }
                                return value == null || value.isEmpty
                                    ? 'Enter a valid API key'
                                    : null;
                              },
                            ),
                            // Load Models button (hidden for Custom/LocalLlama)
                            if (provider != null &&
                                provider != 'Custom' &&
                                provider != 'LocalLlama') ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: isFetchingModels
                                          ? null
                                          : () async {
                                              final key = apiController.text.trim();
                                              if (key.isEmpty) {
                                                setDialogState(() {
                                                  fetchError = 'Enter your API key first.';
                                                });
                                                return;
                                              }
                                              setDialogState(() {
                                                isFetchingModels = true;
                                                fetchError = null;
                                              });
                                              final result =
                                                  await _fetchModelsForProvider(
                                                      provider!, key);
                                              setDialogState(() {
                                                isFetchingModels = false;
                                                if (result.isNotEmpty) {
                                                  fetchedModels = result;
                                                  fetchError = null;
                                                  if (!result.contains(
                                                      modelNameController.text)) {
                                                    modelNameController.text =
                                                        result.first;
                                                  }
                                                } else {
                                                  fetchError =
                                                      'Could not load models. Check your key.';
                                                }
                                              });
                                            },
                                      icon: isFetchingModels
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.lightBlue,
                                              ),
                                            )
                                          : const Icon(Icons.cloud_download_outlined,
                                              color: Colors.lightBlue, size: 18),
                                      label: Text(
                                        isFetchingModels
                                            ? 'Loading models…'
                                            : 'Load models from API',
                                        style: const TextStyle(
                                            color: Colors.lightBlue, fontSize: 13),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                            color: Colors.lightBlue),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8, horizontal: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (fetchError != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    fetchError!,
                                    style: const TextStyle(
                                        color: Colors.redAccent, fontSize: 12),
                                  ),
                                ),
                            ],
                            const SizedBox(height: 15),
                            // Model Name: dropdown when models fetched, text field otherwise
                            if (fetchedModels.isNotEmpty)
                              DropdownButtonFormField<String>(
                                value: fetchedModels
                                        .contains(modelNameController.text)
                                    ? modelNameController.text
                                    : fetchedModels.first,
                                dropdownColor: appThemeState.appTheme.isDark
                                    ? const Color(0xff181A26)
                                    : Colors.white,
                                decoration: InputDecoration(
                                  prefixIcon: Icon(Icons.smart_toy_outlined,
                                      color: Colors.lightBlue),
                                  labelText: 'Select Model',
                                  labelStyle: TextStyle(
                                    color: appThemeState.appTheme
                                        .selectScreenCardTextColor
                                        .withAlpha(150),
                                    fontSize: 15,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                        color: Colors.lightBlue, width: 2),
                                  ),
                                ),
                                isExpanded: true,
                                items: fetchedModels
                                    .map(
                                      (m) => DropdownMenuItem(
                                        value: m,
                                        child: Text(
                                          m,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: appThemeState.appTheme
                                                .selectScreenCardTextColor,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() {
                                      modelNameController.text = val;
                                    });
                                  }
                                },
                                validator: (v) =>
                                    v == null ? 'Select a model' : null,
                              )
                            else
                              TextFormField(
                                style: TextStyle(
                                  color: appThemeState.appTheme
                                      .selectScreenCardTextColor,
                                ),
                                controller: modelNameController,
                                cursorColor: Colors.lightBlue,
                                decoration: InputDecoration(
                                  prefixIcon: Icon(Icons.label,
                                      color: Colors.lightBlue),
                                  hintText: _modelNameHintForProvider(provider),
                                  hintStyle: TextStyle(
                                      color: Colors.grey, fontSize: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: const BorderSide(
                                        color: Colors.lightBlue, width: 2),
                                  ),
                                  labelText: 'Model Name',
                                  helperText: provider != null &&
                                          provider != 'Custom' &&
                                          provider != 'LocalLlama'
                                      ? 'Tap "Load models from API" to pick from a list'
                                      : null,
                                  helperStyle: const TextStyle(
                                      color: Colors.grey, fontSize: 11),
                                  labelStyle: TextStyle(
                                    color: appThemeState.appTheme
                                        .selectScreenCardTextColor
                                        .withAlpha(150),
                                    fontSize: 15,
                                  ),
                                ),
                                validator: (value) =>
                                    value == null || value.isEmpty
                                        ? 'Enter a valid model name'
                                        : null,
                              ),
                            if (isCustomProvider) ...[
                              const SizedBox(height: 15),
                              TextFormField(
                                style: TextStyle(
                                  color: appThemeState.appTheme.selectScreenCardTextColor,
                                ),
                                controller: customUrlController,
                                cursorColor: Colors.lightBlue,
                                decoration: InputDecoration(
                                  prefixIcon: Icon(Icons.link, color: Colors.lightBlue),
                                  labelText: 'Custom Endpoint URL',
                                  hintText: 'https://api.example.com/v1/chat/completions',
                                  hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: BorderSide(
                                      color: Colors.lightBlue,
                                      width: 2,
                                    ),
                                  ),
                                  labelStyle: TextStyle(
                                    color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                    fontSize: 15,
                                  ),
                                ),
                                validator: (value) {
                                  if (!isCustomProvider) return null;
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Enter a valid endpoint URL';
                                  }
                                  final uri = Uri.tryParse(value.trim());
                                  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                                    return 'Enter a valid absolute URL';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 15),
                              DropdownButtonFormField<String>(
                                initialValue: customHttpMethod,
                                dropdownColor: appThemeState.appTheme.isDark
                                    ? const Color(0xff181A26)
                                    : Colors.white,
                                decoration: InputDecoration(
                                  prefixIcon: Icon(Icons.http, color: Colors.lightBlue),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: BorderSide(
                                      color: Colors.lightBlue,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'POST',
                                    child: Text('POST', style: TextStyle(color: appThemeState.appTheme.selectScreenCardTextColor)),
                                  ),
                                  DropdownMenuItem(
                                    value: 'GET',
                                    child: Text('GET', style: TextStyle(color: appThemeState.appTheme.selectScreenCardTextColor)),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    customHttpMethod = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 15),
                              DropdownButtonFormField<String>(
                                initialValue: customToolCallingMethod,
                                dropdownColor: appThemeState.appTheme.isDark
                                    ? const Color(0xff181A26)
                                    : Colors.white,
                                decoration: InputDecoration(
                                  prefixIcon: Icon(Icons.hub_outlined, color: Colors.lightBlue),
                                  labelText: 'Agentic Tool Protocol',
                                  labelStyle: TextStyle(
                                    color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                    fontSize: 15,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: BorderSide(
                                      color: Colors.lightBlue,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'openAiCompatible',
                                    child: Text('OpenAI-compatible', style: TextStyle(color: appThemeState.appTheme.selectScreenCardTextColor)),
                                  ),
                                  DropdownMenuItem(
                                    value: 'anthropicMessages',
                                    child: Text('Anthropic Messages', style: TextStyle(color: appThemeState.appTheme.selectScreenCardTextColor)),
                                  ),
                                  DropdownMenuItem(
                                    value: 'geminiFunctionCalling',
                                    child: Text('Gemini Function Calling', style: TextStyle(color: appThemeState.appTheme.selectScreenCardTextColor)),
                                  ),
                                  DropdownMenuItem(
                                    value: 'none',
                                    child: Text('None (disable agentic tools)', style: TextStyle(color: appThemeState.appTheme.selectScreenCardTextColor)),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    customToolCallingMethod = value;
                                  });
                                },
                              ),
                            ],
                            const SizedBox(height: 15),
                            Divider(color: Colors.lightBlue.withAlpha(100)),
                            const SizedBox(height: 15),
                            TextField(
                              style: TextStyle(
                                color: appThemeState.appTheme.selectScreenCardTextColor,
                              ),
                              controller: modelIdController,
                              cursorColor: Colors.lightBlue,
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.tag, color: Colors.lightBlue),
                                hintText: isEditing
                                    ? 'Nick name used to identify this model'
                                    : 'A unique nick name, leave it empty to generate one',
                                hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide(
                                    color: Colors.lightBlue,
                                    width: 2,
                                  ),
                                ),
                                labelText: 'Nick Name (Optional)',
                                labelStyle: TextStyle(
                                  color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () async {
                              final formState = _formKey.currentState;
                              if (formState == null || !formState.validate()) {
                                return;
                              }

                              final selectedProvider = provider;
                              if (selectedProvider == null) {
                                return;
                              }

                              final modelName = modelNameController.text.trim();
                              final apiKey = apiController.text.trim();
                              final enteredModelId = modelIdController.text.trim();
                              final targetModelId =
                                enteredModelId.isNotEmpty
                                  ? enteredModelId
                                  : (isEditing ? editingModelId : '$modelName-${DateTime.now().millisecondsSinceEpoch}');

                              final newModelConfig = <String, dynamic>{
                                'provider': selectedProvider,
                                'apiProvider': selectedProvider,
                                'modelName': modelName,
                                'model': modelName,
                                'apiKey': apiKey,
                                if (selectedProvider == 'Custom') ...{
                                  'url': customUrlController.text.trim(),
                                  'httpMethod': customHttpMethod,
                                  'toolCallingMethod': customToolCallingMethod,
                                },
                              };

                              final updatedConfig = Map<String, dynamic>.from(aiState.config);
                              if (isEditing) {
                                updatedConfig.remove(editingModelId);
                              }
                              if (updatedConfig.containsKey(targetModelId)) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Model ID "$targetModelId" already exists')),
                                  );
                                }
                                return;
                              }
                              updatedConfig[targetModelId] = newModelConfig;

                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString('aiConfig', jsonEncode(updatedConfig));

                              final updatedModelSelected = Map<String, dynamic>.from(aiState.modelSelected);
                              var modelSelectionChanged = false;
                              if (isEditing && editingModelId != targetModelId) {
                                if (updatedModelSelected['code'] == editingModelId) {
                                  updatedModelSelected['code'] = targetModelId;
                                  modelSelectionChanged = true;
                                }
                                if (updatedModelSelected['chat'] == editingModelId) {
                                  updatedModelSelected['chat'] = targetModelId;
                                  modelSelectionChanged = true;
                                }
                              }

                              if (modelSelectionChanged) {
                                await prefs.setString('modelSelected', jsonEncode(updatedModelSelected));
                              }

                              if (context.mounted) {
                                context.read<AIBloc>().add(AIConfigEvent(updatedConfig));
                                if (modelSelectionChanged) {
                                  context.read<AIBloc>().add(ModelSelectEvent(updatedModelSelected));
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isEditing
                                          ? 'Successfully updated model $targetModelId'
                                          : 'Successfully created model $targetModelId',
                                    ),
                                  ),
                                );
                                Navigator.of(context).pop();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.lightBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              isEditing ? 'Update' : 'Create',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      customUrlController.dispose();
      _clearModelDialogControllers();
    }
  }

  void _showSSHDialog(
    AppTheme appTheme,
    (int, bool) updateInfo
  ){
    showDialog(
      context: context,
      builder: (ctx){
        return StatefulBuilder(
          builder: (context, setDstate) {
            return Dialog(
              backgroundColor: appTheme.isDark ? const Color(0xff181A26) : Colors.white,
              constraints: BoxConstraints(maxHeight: 600),
              child: Container(
                padding: EdgeInsets.all(20),
                width: double.infinity,
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: appTheme.selectScreenCardTextColor
                  ),
                  child: Form(
                    key: _sshUpdationKey,
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: .end,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 12, bottom: 12),
                              child: Row(
                                spacing: 18,
                                children: [
                                  FaIcon(
                                    FontAwesomeIcons.server,
                                    color: Colors.lightBlue
                                  ),
                                  Text(
                                    "Edit remote host",
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: .w500
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Column(
                                spacing: 20,
                                children: [
                                  settingsTextField(
                                    sshServerNameController,
                                    Icons.abc,
                                    "Server name",
                                    appTheme.selectScreenCardTextColor,
                                    "Eg: My server",
                                    (val) =>  val == null || val.isEmpty ? "Please give a name to the server": null,
                                  ),

                                  settingsTextField(
                                    sshUrlController,
                                    Icons.link,
                                    "Host url",
                                    appTheme.selectScreenCardTextColor,
                                    "Eg: ssh://jhon@192.168.1.100",
                                    (val) {
                                      if(val == null || val.isEmpty){
                                        return "Please enter a valid host/ip address";
                                      }

                                      final valUri = Uri.parse(val);
                                      if(valUri.scheme != "ssh") {
                                        return "Invalid ssh url";
                                      } else if(valUri.host.isEmpty){
                                        return "Invalid Or empty host name";
                                      } else if(valUri.userInfo.isEmpty) {
                                        return "Invalid or empty username";
                                      } else {
                                        return null;
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                            if(updateInfo.$2) Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Column(
                                spacing: 20,
                                children: [
                                  settingsTextField(
                                    sshPasswordController,
                                    Icons.password,
                                    "Password",
                                    appTheme.selectScreenCardTextColor,
                                    null,
                                    (val) {
                                      return val == null || val.isEmpty ? "Password field cannot be empty": null;
                                    },
                                    true
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              spacing: 18,
                              children: [
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    minimumSize: Size.zero
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                  child: Text(
                                    "Cancel",
                                    style: TextStyle(
                                      color: Colors.red
                                    )
                                  )
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    minimumSize: Size.zero
                                  ),
                                  onPressed: () async{
                                    if (_sshUpdationKey.currentState!.validate()) {
                                      await context.read<SSHServersCubit>().updateServer(
                                        updateInfo.$2
                                        ? SSHLogin(
                                            name: sshServerNameController.text,
                                            id: updateInfo.$1,
                                            url: sshUrlController.text,
                                            password: sshPasswordController.text
                                          )
                                        : SSHPrivateKey(
                                          name: sshServerNameController.text,
                                          id: updateInfo.$1,
                                          url: sshUrlController.text,
                                        )
                                      );
                                      sshServerNameController.text = "";
                                      sshUrlController.text = "";
                                      sshPasswordController.text = "";
                                      if(context.mounted) Navigator.pop(context);
                                      if(context.mounted) Navigator.pop(context);
                                    }
                                  },
                                  child: Text(
                                    "Save",
                                    style: TextStyle(
                                      color: Colors.lightBlue
                                    ),
                                  ),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    minimumSize: Size.zero
                                  ),
                                  onPressed: () async{
                                    if(_sshUpdationKey.currentState!.validate()){
                                      final server = updateInfo.$2
                                        ? SSHLogin(
                                          name: sshServerNameController.text,
                                          id: updateInfo.$1,
                                          url: sshUrlController.text,
                                          password: sshPasswordController.text
                                        )

                                        : SSHPrivateKey(
                                            name: sshServerNameController.text,
                                            id: updateInfo.$1,
                                            url: sshUrlController.text,
                                          );
                                      final result = await server.connect();
                                      if(context.mounted){
                                        if(server.isConnected) context.read<SSHServersCubit>().updateServer(server);
                                        if(result.$1) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              backgroundColor: Colors.green,
                                              content: Text(
                                                result.$2,
                                                style: TextStyle(
                                                  color: Colors.white
                                                )
                                              )
                                            )
                                          );
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              backgroundColor: Colors.red[600],
                                              content: Text(
                                                result.$2,
                                                style: TextStyle(
                                                  color: Colors.white
                                                )
                                              )
                                            )
                                          );
                                        }
                                      }
                                      if(context.mounted) Navigator.pop(context);
                                      if(context.mounted) Navigator.pop(context);
                                    }
                                  },
                                  child: Text(
                                    "Save & Connect",
                                    style: TextStyle(
                                      color: Colors.greenAccent
                                    ),
                                  )
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        );
      }
    );
  }

  Future<void> _loadLocalGgufModel(BuildContext context, AppThemeState appThemeState) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gguf'],
    );
    if (result == null) return;
    final path = result.files.single.path!;
    final fileName = result.files.single.name;

    final nameController = TextEditingController(text: fileName.replaceAll('.gguf', ''));
    
    if(!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: appThemeState.appTheme.isDark ? const Color(0xff2b2b2b) : Colors.white,
        title: const Text('Configure Local LLM'),
        content: Form(
          key: _ggufKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Display name')),
              settingsTextField(
                nameController,
                Icons.abc,
                "Display name",
                appThemeState.appTheme.selectScreenCardTextColor,
                null,
                (val) => val == null || val.isEmpty ? "Display name cannot be empty" : null
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () {
            if(_ggufKey.currentState!.validate()){
              Navigator.pop(ctx, false);
            }
          }, child: const Text('Add')),
        ],
      ),
    );

    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    final aiConfigStr = await getAiConfig();
    Map<String, dynamic> aiConfig = jsonDecode(aiConfigStr);
    final modelId = 'LocalLlama-${DateTime.now().millisecondsSinceEpoch}';
    aiConfig[modelId] = {
      'provider': 'LocalLlama',
      'apiProvider': 'LocalLlama',
      'modelName': nameController.text,
      'model': nameController.text,
      'modelPath': path,
      'threads': 4,
      'contextSize': 4096,
      'gpuLayers': 0,
    };
    await prefs.setString('aiConfig', jsonEncode(aiConfig));
    if (context.mounted) {
      context.read<AIBloc>().add(AIConfigEvent(aiConfig));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model "${nameController.text}" added to AI models')),
      );

      final modelSelectedStr = await getModelSelected();
      Map<String, dynamic> modelSelected = jsonDecode(modelSelectedStr);
      if ((modelSelected['chat'] as String? ?? '').isEmpty) {
        modelSelected['chat'] = modelId;
        await prefs.setString('modelSelected', jsonEncode(modelSelected));
        if(context.mounted) context.read<AIBloc>().add(ModelSelectEvent(modelSelected));
      }
    }
  }

  Future<void> _saveCodeForgeConfig(Map<String, dynamic> currentState) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('codeForgeConfig', jsonEncode(currentState));
    if (mounted) {
      context.read<ConfigBloc>().add(ChangeConfigEvent(currentState));
    }
  }

  Future<String?> _showCustomEditorThemeDialog(
    BuildContext context,
    AppThemeState appThemeState,
    ConfigState configState, {
    String? existingThemeName,
  }) async {
    final customThemes = getCustomEditorThemes(configState.codeForgeConfig);
    final initialTheme = existingThemeName != null ? customThemes[existingThemeName] : null;
    final tokenKeys = vs2015Theme.keys.skip(1).toList();
    final themeNameController = TextEditingController(text: existingThemeName ?? '');
    final initialRootStyle = initialTheme?.toMap()['root'] ?? const TextStyle(
      backgroundColor: Color(0xff000000),
      color: Color(0xffffffff),
    );
    final themeStyles = Map<String, TextStyle>.from(initialTheme?.toMap() ?? {});
    TextStyle rootStyle = initialRootStyle;
    bool hasChanges = initialTheme != null;

    TextStyle styleFor(String key) {
      return themeStyles[key] ?? const TextStyle(color: Colors.white);
    }

    TextStyle updateStyle(String key, {
      Color? color,
      FontStyle? fontStyle,
      FontWeight? fontWeight,
    }) {
      final currentStyle = themeStyles[key] ?? const TextStyle(color: Colors.white);
      final updatedStyle = currentStyle.copyWith(
        color: color ?? currentStyle.color,
        fontStyle: fontStyle ?? currentStyle.fontStyle,
        fontWeight: fontWeight ?? currentStyle.fontWeight,
      );
      themeStyles[key] = updatedStyle;
      hasChanges = true;
      return updatedStyle;
    }

    Future<void> pickColor({
      required Color color,
      required ValueChanged<Color> onChanged,
    }) async {
      await showDialog(
        context: context,
        builder: (pickerContext) {
          Color selectedColor = color;
          return StatefulBuilder(
            builder: (context, setPickerState) {
              return AlertDialog(
                backgroundColor: appThemeState.appTheme.editorPageDrawerBg,
                titleTextStyle: TextStyle(
                  color: appThemeState.appTheme.selectScreenCardTextColor,
                  fontSize: 25,
                ),
                title: const Text('Pick a color!'),
                content: SingleChildScrollView(
                  child: Theme(
                    data: ThemeData(
                      textTheme: Theme.of(context).textTheme.copyWith(
                        bodyMedium: TextStyle(color: appThemeState.appTheme.selectScreenCardTextColor),
                        bodyLarge: TextStyle(color: appThemeState.appTheme.selectScreenCardTextColor),
                        labelMedium: TextStyle(color: appThemeState.appTheme.selectScreenCardTextColor),
                        displayMedium: TextStyle(color: appThemeState.appTheme.selectScreenCardTextColor),
                        titleMedium: TextStyle(color: appThemeState.appTheme.selectScreenCardTextColor),
                      ),
                    ),
                    child: ColorPicker(
                      pickerColor: selectedColor,
                      labelTypes: const [.hex, .rgb, .hsv, .hsl],
                      onColorChanged: (nextColor) {
                        setPickerState(() => selectedColor = nextColor);
                      },
                    ),
                  ),
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: .circular(5)),
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.of(pickerContext).pop(),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: .circular(5)),
                      foregroundColor: Colors.black,
                      backgroundColor: Colors.white,
                    ),
                    child: const Text('Ok'),
                    onPressed: () {
                      onChanged(selectedColor);
                      Navigator.of(pickerContext).pop();
                    },
                  ),
                ],
              );
            },
          );
        },
      );
    }

    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final rootColor = rootStyle.backgroundColor ?? Colors.black;
              final foregroundColor = rootStyle.color ?? Colors.white;

              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                backgroundColor: appThemeState.appTheme.scaffoldBg,
                title: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: appThemeState.appTheme.isDark
                        ? [Colors.blue.shade800, Colors.blue.shade300]
                        : [Colors.blue.shade200, Colors.blue.shade100],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      FaIcon(
                        FontAwesomeIcons.palette,
                        color: appThemeState.appTheme.isDark ? Colors.white : Colors.purple.shade700,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              existingThemeName == null ? 'Create an editor theme' : 'Edit editor theme',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: appThemeState.appTheme.isDark ? Colors.white : Colors.purple.shade900,
                              ),
                            ),
                            Text(
                              '${tokenKeys.length + 1} theme fields available',
                              style: TextStyle(
                                fontSize: 12,
                                color: appThemeState.appTheme.isDark ? Colors.white70 : Colors.purple.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 620,
                  child: DefaultTextStyle(
                    style: TextStyle(color: appThemeState.appTheme.selectScreenCardTextColor),
                    child: RawScrollbar(
                      thumbVisibility: true,
                      thumbColor: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                      mainAxisMargin: 25,
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Form(
                              key: _themeKey,
                              child: settingsTextField(
                                themeNameController,
                                Icons.color_lens,
                                'Theme name',
                                appThemeState.appTheme.selectScreenCardTextColor,
                                'eg: Catppuccin',
                                (val) => val == null || val.trim().isEmpty ? 'Provide a valid theme name' : null,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 20),
                            child: Row(
                              children: [
                                const Text('Background color'),
                                IconButton(
                                  onPressed: () async {
                                    await pickColor(
                                      color: rootColor,
                                      onChanged: (color) {
                                        setDialogState(() {
                                          rootStyle = rootStyle.copyWith(backgroundColor: color);
                                          themeStyles['root'] = rootStyle;
                                          hasChanges = true;
                                        });
                                      },
                                    );
                                  },
                                  icon: Icon(Icons.square, color: rootColor),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 20),
                            child: Row(
                              children: [
                                const Text('Foreground color'),
                                IconButton(
                                  onPressed: () async {
                                    await pickColor(
                                      color: foregroundColor,
                                      onChanged: (color) {
                                        setDialogState(() {
                                          rootStyle = rootStyle.copyWith(color: color);
                                          themeStyles['root'] = rootStyle;
                                          hasChanges = true;
                                        });
                                      },
                                    );
                                  },
                                  icon: Icon(Icons.square, color: foregroundColor),
                                ),
                              ],
                            ),
                          ),
                          ...tokenKeys.map((key) {
                            final tokenStyle = styleFor(key);
                            final tokenColor = tokenStyle.color ?? Colors.white;
                            return Padding(
                              padding: const EdgeInsets.only(left: 20),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    Text(key),
                                    IconButton(
                                      onPressed: () async {
                                        await pickColor(
                                          color: tokenColor,
                                          onChanged: (color) {
                                            setDialogState(() {
                                              updateStyle(key, color: color);
                                            });
                                          },
                                        );
                                      },
                                      icon: Icon(Icons.square, color: tokenColor),
                                    ),
                                    DropdownButton<FontStyle>(
                                      dropdownColor: appThemeState.appTheme.selectScreenDrawerBg,
                                      value: tokenStyle.fontStyle ?? FontStyle.normal,
                                      style: TextStyle(color: appThemeState.appTheme.selectScreenCardTextColor),
                                      onChanged: (value) {
                                        if (value == null) {
                                          return;
                                        }
                                        setDialogState(() {
                                          updateStyle(key, fontStyle: value);
                                        });
                                      },
                                      items: const [
                                        DropdownMenuItem(value: FontStyle.italic, child: Text('Italic')),
                                        DropdownMenuItem(value: FontStyle.normal, child: Text('Normal')),
                                      ],
                                    ),
                                    const SizedBox(width: 3),
                                    DropdownButton<FontWeight>(
                                      value: tokenStyle.fontWeight ?? FontWeight.normal,
                                      style: TextStyle(color: appThemeState.appTheme.selectScreenCardTextColor),
                                      dropdownColor: appThemeState.appTheme.selectScreenDrawerBg,
                                      onChanged: (value) {
                                        if (value == null) {
                                          return;
                                        }
                                        setDialogState(() {
                                          updateStyle(key, fontWeight: value);
                                        });
                                      },
                                      items: const [
                                        DropdownMenuItem(value: FontWeight.bold, child: Text('Bold')),
                                        DropdownMenuItem(value: FontWeight.normal, child: Text('Normal')),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: appThemeState.appTheme.isDark ? Colors.white70 : Colors.grey.shade700,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: .circular(5)),
                      backgroundColor: const Color(0xff007acc),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final themeName = themeNameController.text.trim();
                      if (themeName.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Name field cannot be empty', style: TextStyle(color: Colors.white)),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      final mergedThemes = getMergedHighlightThemes(configState.codeForgeConfig);
                      if (mergedThemes.containsKey(themeName) && themeName != existingThemeName) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('A theme named "$themeName" already exists', style: const TextStyle(color: Colors.white)),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      final originalName = existingThemeName?.trim();
                      final isRename = originalName != null && originalName != themeName;
                      if (!hasChanges && !isRename) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please change at least one field', style: TextStyle(color: Colors.white)),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      final updatedCustomThemes = Map<String, dynamic>.from(
                        configState.codeForgeConfig['customEditorThemes'] as Map? ?? {},
                      );
                      if (originalName != null && isRename) {
                        updatedCustomThemes.remove(originalName);
                      }
                      updatedCustomThemes[themeName] = CustomEditorTheme.fromMap(themeStyles).toJson();

                      final currentState = Map<String, dynamic>.from(configState.codeForgeConfig)
                        ..['customEditorThemes'] = updatedCustomThemes
                        ..['theme'] = themeName;
                      await _saveCodeForgeConfig(currentState);
                      if (context.mounted) {
                        Navigator.of(dialogContext).pop(themeName);
                      }
                    },
                    child: Text(existingThemeName == null ? 'Create & Set theme' : 'Save & Set theme'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("An error occurred: ${e.toString()}")
      ));
    }
    return null;
  }

  @override void dispose() {
    apiController.dispose();
    modelNameController.dispose();
    modelIdController.dispose();
    scrollController.dispose();
    terminalThemeScroll.dispose();
    themeScroll.dispose();
    fontScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConfigBloc, ConfigState>(
      builder: (context, configState) {
        return BlocBuilder<AppThemeBloc, AppThemeState>(
          builder: (context, appThemeState) {
            final isDark = appThemeState.appTheme.isDark;
            final cs = Theme.of(context).colorScheme;

            final settingsBody = Column(
              children: [
                _SettingsPillNav(
                  current: _selectedSection,
                  onTap: (sec) => setState(() => _selectedSection = sec),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    child: _buildSectionContent(context, _selectedSection, configState, appThemeState, cs, isDark),
                  ),
                ),
              ],
            );

            if (widget.embedded) return settingsBody;

            return Scaffold(
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: Text(
                  'Paramètres Panda',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ),
              body: settingsBody,
            );
          },
        );
      },
    );
  }

  Widget _buildSectionContent(
    BuildContext context,
    _SettingsSection section,
    ConfigState configState,
    AppThemeState appThemeState,
    ColorScheme cs,
    bool isDark,
  ) {
    switch (section) {
      case _SettingsSection.general:
        return _buildGeneralSection(context, configState, appThemeState, cs, isDark);
      case _SettingsSection.editor:
        return _buildEditorSection(context, configState, appThemeState, cs, isDark);
      case _SettingsSection.terminal:
        return _buildTerminalSection(context, configState, appThemeState, cs, isDark);
      case _SettingsSection.performance:
        return _buildPerformanceSection(context, configState, appThemeState, cs, isDark);
      case _SettingsSection.aiAndApi:
        return _buildAiAndApiSection(context, configState, appThemeState, cs, isDark);
      case _SettingsSection.about:
        return _buildAboutSection(context, configState, appThemeState, cs, isDark);
    }
  }

  Widget _buildCardGroup({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
    required bool isDark,
    required ColorScheme cs,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff1e1e24) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
          ...children,
        ],
      ),
    );
  }

  Widget _buildGeneralSection(
    BuildContext context,
    ConfigState configState,
    AppThemeState appThemeState,
    ColorScheme cs,
    bool isDark,
  ) {
    final languages = ['Français 🇫🇷', 'English 🇺🇸', 'Español 🇪🇸', 'Deutsch 🇩🇪', '日本語 🇯🇵', '中文 🇨🇳'];

    return Column(
      children: [
        _buildCardGroup(
          title: "Langue de l'application",
          subtitle: "Sélectionnez la langue d'affichage de Panda IDE",
          icon: Icons.language_rounded,
          isDark: isDark,
          cs: cs,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Langue active', style: TextStyle(color: cs.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: languages.contains(_currentLanguage) ? _currentLanguage : 'Français 🇫🇷',
                        dropdownColor: isDark ? const Color(0xff252528) : Colors.white,
                        style: TextStyle(color: cs.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
                        onChanged: (val) async {
                          if (val != null) {
                            setState(() => _currentLanguage = val);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('app_language', val);
                          }
                        },
                        items: languages.map((lang) {
                          return DropdownMenuItem(value: lang, child: Text(lang));
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        _buildCardGroup(
          title: 'Thème & Apparence',
          subtitle: "Mode sombre, clair et échelle de l'interface",
          icon: Icons.dark_mode_outlined,
          isDark: isDark,
          cs: cs,
          children: [
            ListTile(
              title: const Text('Mode Sombre (Dark Theme)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('Basculer entre le thème clair et sombre', style: TextStyle(fontSize: 11)),
              trailing: Switch(
                value: isDark,
                onChanged: (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  if (val) {
                    if (context.mounted) context.read<AppThemeBloc>().add(AppThemeEvent(appTheme: DarkTheme()));
                    await prefs.setString('savedAppTheme', 'dark');
                  } else {
                    if (context.mounted) context.read<AppThemeBloc>().add(AppThemeEvent(appTheme: LightTheme()));
                    await prefs.setString('savedAppTheme', 'light');
                  }
                },
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Échelle de l'interface (Zoom UI)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('${(_uiScale * 100).toInt()}%', style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  Slider(
                    value: _uiScale,
                    min: 0.8,
                    max: 1.4,
                    divisions: 6,
                    label: '${(_uiScale * 100).toInt()}%',
                    onChanged: (val) async {
                      setState(() => _uiScale = val);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setDouble('ui_scale', val);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditorSection(
    BuildContext context,
    ConfigState configState,
    AppThemeState appThemeState,
    ColorScheme cs,
    bool isDark,
  ) {
    final themeName = configState.codeForgeConfig['theme'] ?? 'vs2015';
    final lineWrap = configState.codeForgeConfig['lineWrap'] ?? true;
    final enableFolding = configState.codeForgeConfig['enableFolding'] ?? true;
    final indentStatus = configState.codeForgeConfig['indentLineStatus'] ?? true;

    return Column(
      children: [
        _buildCardGroup(
          title: 'Sauvegarde & Thème',
          subtitle: 'Auto-save et thème de coloration syntaxique',
          icon: Icons.code_rounded,
          isDark: isDark,
          cs: cs,
          children: [
            BlocBuilder<GeneralBloc, GeneralState>(
              builder: (context, generalState) {
                final autoSave = generalState.generalSettings['autoSave'] ?? true;
                return ListTile(
                  title: const Text('Enregistrement automatique (Auto Save)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Enregistrer automatiquement les modifications', style: TextStyle(fontSize: 11)),
                  trailing: Switch(
                    value: autoSave,
                    onChanged: (val) async {
                      final prefs = await SharedPreferences.getInstance();
                      final currentState = Map<String, dynamic>.from(configState.codeForgeConfig);
                      currentState['autoSave'] = val;
                      await prefs.setString('codeForgeConfig', jsonEncode(currentState));
                      if (context.mounted) {
                        final curr = Map<String, dynamic>.from(context.read<GeneralBloc>().state.generalSettings);
                        curr['autoSave'] = val;
                        context.read<GeneralBloc>().add(GeneralEvent(generalSettings: curr));
                      }
                    },
                  ),
                );
              },
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            ListTile(
              title: const Text('Thème de coloration syntaxique', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('Thème actuel : $themeName', style: const TextStyle(fontSize: 11)),
              trailing: OutlinedButton.icon(
                icon: const Icon(Icons.palette_outlined, size: 14),
                label: const Text('Changer'),
                onPressed: () => _openEditorThemePicker(context, configState, isDark),
              ),
            ),
          ],
        ),

        _buildCardGroup(
          title: "Options d'affichage de l'éditeur",
          subtitle: "Pliage, guides d'indentation, ligne de retour",
          icon: Icons.tune_rounded,
          isDark: isDark,
          cs: cs,
          children: [
            ListTile(
              title: const Text('Retour à la ligne automatique (Line Wrap)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              trailing: Switch(
                value: lineWrap,
                onChanged: (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  final currentState = Map<String, dynamic>.from(configState.codeForgeConfig);
                  currentState['lineWrap'] = val;
                  await prefs.setString('codeForgeConfig', jsonEncode(currentState));
                  if (context.mounted) {
                    context.read<ConfigBloc>().add(ConfigEvent(codeForgeConfig: currentState));
                  }
                },
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            ListTile(
              title: const Text("Guides d'indentation", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              trailing: Switch(
                value: indentStatus,
                onChanged: (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  final currentState = Map<String, dynamic>.from(configState.codeForgeConfig);
                  currentState['indentLineStatus'] = val;
                  await prefs.setString('codeForgeConfig', jsonEncode(currentState));
                  if (context.mounted) {
                    context.read<ConfigBloc>().add(ConfigEvent(codeForgeConfig: currentState));
                  }
                },
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            ListTile(
              title: const Text('Pliage de code (Code Folding)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              trailing: Switch(
                value: enableFolding,
                onChanged: (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  final currentState = Map<String, dynamic>.from(configState.codeForgeConfig);
                  currentState['enableFolding'] = val;
                  await prefs.setString('codeForgeConfig', jsonEncode(currentState));
                  if (context.mounted) {
                    context.read<ConfigBloc>().add(ConfigEvent(codeForgeConfig: currentState));
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTerminalSection(
    BuildContext context,
    ConfigState configState,
    AppThemeState appThemeState,
    ColorScheme cs,
    bool isDark,
  ) {
    return Column(
      children: [
        _buildCardGroup(
          title: 'Configuration Terminal',
          subtitle: 'Aperçu interactif, police et thème',
          icon: Icons.terminal_rounded,
          isDark: isDark,
          cs: cs,
          children: [
            Container(
              height: 130,
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xff0d0d0f) : const Color(0xff1e1e24),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: TerminalView(terminal),
              ),
            ),
            ListTile(
              title: const Text('Réseau & ADB WiFi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('Appairage sans fil ADB et connexions distantes', style: TextStyle(fontSize: 11)),
              trailing: ElevatedButton.icon(
                icon: const Icon(Icons.wifi, size: 14),
                label: const Text('Ouvrir ADB'),
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AdbSetupPage(),
                  ));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPerformanceSection(
    BuildContext context,
    ConfigState configState,
    AppThemeState appThemeState,
    ColorScheme cs,
    bool isDark,
  ) {
    return Column(
      children: [
        _buildCardGroup(
          title: 'Allocation Mémoire & GPU',
          subtitle: 'Limites de RAM pour serveurs LSP et IA locale',
          icon: Icons.speed_rounded,
          isDark: isDark,
          cs: cs,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Limite RAM allouée aux LSPs & Modèles', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('${_ramLimitGb.toStringAsFixed(1)} GB', style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  Slider(
                    value: _ramLimitGb,
                    min: 1.0,
                    max: 8.0,
                    divisions: 14,
                    label: '${_ramLimitGb.toStringAsFixed(1)} GB',
                    onChanged: (val) async {
                      setState(() => _ramLimitGb = val);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setDouble('ram_limit_gb', val);
                    },
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            ListTile(
              title: const Text('Accélération Matérielle GPU / Vulkan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text("Utiliser le GPU pour l'affichage et le calcul IA", style: TextStyle(fontSize: 11)),
              trailing: Switch(
                value: _gpuAccelerated,
                onChanged: (val) async {
                  setState(() => _gpuAccelerated = val);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('gpu_accelerated', val);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAiAndApiSection(
    BuildContext context,
    ConfigState configState,
    AppThemeState appThemeState,
    ColorScheme cs,
    bool isDark,
  ) {
    return Column(
      children: [
        _buildCardGroup(
          title: 'Google Gemini & Copilot',
          subtitle: 'Clés API et services de génération de code',
          icon: Icons.security_rounded,
          isDark: isDark,
          cs: cs,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Clé API Google Gemini', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: apiController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Saisir votre clé GEMINI_API_KEY',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: const Icon(Icons.key, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            ListTile(
              title: const Text('GitHub Copilot', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text("Paramètres et état d'authentification Copilot", style: TextStyle(fontSize: 11)),
              trailing: ElevatedButton.icon(
                icon: const Icon(Icons.account_circle, size: 14),
                label: const Text('Gérer'),
                onPressed: () {
                  final copilotState = context.read<CopilotBloc>().state;
                  _showCopilotSettings(context, copilotState, appThemeState);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAboutSection(
    BuildContext context,
    ConfigState configState,
    AppThemeState appThemeState,
    ColorScheme cs,
    bool isDark,
  ) {
    return Column(
      children: [
        _buildCardGroup(
          title: 'Panda IDE',
          subtitle: 'Version v2.5.0 (PlayStore Edition)',
          icon: Icons.info_rounded,
          isDark: isDark,
          cs: cs,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Image.asset('assets/icons/app-icon.png', width: 36, height: 36, errorBuilder: (_, __, ___) => const Icon(Icons.pets, size: 30)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Panda IDE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
                        const Text('Build v2.5.0-release · Android arm64-v8a', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text('Environnement IDE complet sans serveur externe', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            ListTile(
              title: const Text('Vérifier les mises à jour', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              trailing: OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Mettre à jour'),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Panda IDE est déjà à jour (v2.5.0)')),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openEditorThemePicker(BuildContext context, ConfigState configState, bool isDark) {
    final mergedThemes = getMergedHighlightThemes(configState.codeForgeConfig);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Thème de coloration syntaxique'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: mergedThemes.length,
              itemBuilder: (ctx, i) {
                final key = mergedThemes.keys.elementAt(i);
                return ListTile(
                  title: Text(key),
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final curr = Map<String, dynamic>.from(configState.codeForgeConfig);
                    curr['theme'] = key;
                    await prefs.setString('codeForgeConfig', jsonEncode(curr));
                    if (context.mounted) {
                      context.read<ConfigBloc>().add(ConfigEvent(codeForgeConfig: curr));
                      Navigator.pop(dialogCtx);
                    }
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showCopilotSettings(BuildContext context, CopilotState state, AppThemeState appThemeState) {
    final isDark = appThemeState.appTheme.isDark;
    final textColor = appThemeState.appTheme.selectScreenCardTextColor;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [const Color(0xfffafafa), const Color(0xfff0f0f0)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SvgPicture.asset(
                        'assets/icons/github-copilot-icon.svg',
                        height: 28,
                        width: 28,
                        colorFilter: const ColorFilter.mode(
                          Colors.green,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GitHub Copilot',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Connected',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(
                        Icons.close,
                        color: textColor.withValues(alpha: 0.5),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xff238636).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person,
                          color: Color(0xff238636),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.user ?? 'User',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'GitHub Account',
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                BlocBuilder<CopilotBloc, CopilotState>(
                  builder: (context, copilotState) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                copilotState.isEnabled
                                    ? Icons.auto_awesome
                                    : Icons.auto_awesome_outlined,
                                color: copilotState.isEnabled
                                    ? const Color(0xff238636)
                                    : textColor.withValues(alpha: 0.5),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Enable Copilot',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Switch(
                            value: copilotState.isEnabled,
                            activeThumbColor: const Color(0xff238636),
                            onChanged: (value) {
                              context.read<CopilotBloc>().add(CopilotSetEnabled(value));
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context.read<CopilotBloc>().add(CopilotSignOut());
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Row(
                            children: [
                              Icon(Icons.logout, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text('Signed out from Copilot'),
                            ],
                          ),
                          backgroundColor: Colors.grey[700],
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      );
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign Out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


class _BrowserSettingsRoute extends StatelessWidget {
  const _BrowserSettingsRoute();

  @override
  Widget build(BuildContext context) => const BrowserSettingsPage();
}
