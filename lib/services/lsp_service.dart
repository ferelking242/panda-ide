/// LspService — manages Language Server Protocol servers inside PRoot.
///
/// Detects which LSP servers are installed, maps file extensions to servers,
/// and provides WebSocket URLs for CodeForge's LspSocketConfig.
///
/// LSP servers run as PTY processes inside PRoot. CodeForge connects via
/// WebSocket through a lightweight stdio↔WS bridge.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../utils/panda_log.dart';

/// Supported language → server mapping.
class LspServerInfo {
  final String languageId;
  final String displayName;
  final List<String> installCmd;
  final List<String> fileExtensions;
  final String serverCommand;
  final List<String> serverArgs;
  final String? checkCmd; // command to check if installed

  const LspServerInfo({
    required this.languageId,
    required this.displayName,
    required this.installCmd,
    required this.fileExtensions,
    required this.serverCommand,
    this.serverArgs = const ['--stdio'],
    this.checkCmd,
  });

  String get _check => checkCmd ?? 'which $serverCommand 2>/dev/null';
}

/// Registry of supported LSP servers.
const Map<String, LspServerInfo> kLspServers = {
  'typescript': LspServerInfo(
    languageId: 'typescript',
    displayName: 'TypeScript',
    installCmd: ['npm install -g typescript-language-server typescript'],
    fileExtensions: ['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.mts', '.cts'],
    serverCommand: 'typescript-language-server',
    serverArgs: ['--stdio'],
  ),
  'json': LspServerInfo(
    languageId: 'json',
    displayName: 'JSON',
    installCmd: ['npm install -g vscode-langservers-extracted'],
    fileExtensions: ['.json', '.jsonc'],
    serverCommand: 'vscode-json-language-server',
    serverArgs: ['--stdio'],
  ),
  'html': LspServerInfo(
    languageId: 'html',
    displayName: 'HTML',
    installCmd: ['npm install -g vscode-langservers-extracted'],
    fileExtensions: ['.html', '.htm', '.vue', '.svelte'],
    serverCommand: 'vscode-html-language-server',
    serverArgs: ['--stdio'],
  ),
  'css': LspServerInfo(
    languageId: 'css',
    displayName: 'CSS',
    installCmd: ['npm install -g vscode-langservers-extracted'],
    fileExtensions: ['.css', '.scss', '.less', '.sass'],
    serverCommand: 'vscode-css-language-server',
    serverArgs: ['--stdio'],
  ),
  'python': LspServerInfo(
    languageId: 'python',
    displayName: 'Python',
    installCmd: ['pip3 install python-lsp-server'],
    fileExtensions: ['.py', '.pyw', '.pyi'],
    serverCommand: 'pylsp',
    serverArgs: [],
  ),
  'rust': LspServerInfo(
    languageId: 'rust',
    displayName: 'Rust',
    installCmd: ['cargo install rust-analyzer'],
    fileExtensions: ['.rs'],
    serverCommand: 'rust-analyzer',
    serverArgs: [],
  ),
  'go': LspServerInfo(
    languageId: 'go',
    displayName: 'Go',
    installCmd: ['go install golang.org/x/tools/gopls@latest'],
    fileExtensions: ['.go'],
    serverCommand: 'gopls',
    serverArgs: [],
  ),
  'lua': LspServerInfo(
    languageId: 'lua',
    displayName: 'Lua',
    installCmd: ['luarocks install lua-language-server'],
    fileExtensions: ['.lua'],
    serverCommand: 'lua-language-server',
    serverArgs: ['--stdio'],
  ),
  'c_cpp': LspServerInfo(
    languageId: 'c_cpp',
    displayName: 'C/C++',
    installCmd: ['apt-get install -y clangd'],
    fileExtensions: ['.c', '.cpp', '.cc', '.cxx', '.h', '.hpp', '.hxx'],
    serverCommand: 'clangd',
    serverArgs: ['--background-index', '--clang-tidy=false'],
    checkCmd: 'which clangd 2>/dev/null',
  ),
  'dart': LspServerInfo(
    languageId: 'dart',
    displayName: 'Dart',
    installCmd: [], // bundled with Flutter SDK
    fileExtensions: ['.dart'],
    serverCommand: 'dart',
    serverArgs: ['language-server'],
    checkCmd: 'which dart 2>/dev/null',
  ),
  'yaml': LspServerInfo(
    languageId: 'yaml',
    displayName: 'YAML',
    installCmd: ['npm install -g yaml-language-server'],
    fileExtensions: ['.yaml', '.yml'],
    serverCommand: 'yaml-language-server',
    serverArgs: ['--stdio'],
  ),
  'markdown': LspServerInfo(
    languageId: 'markdown',
    displayName: 'Markdown',
    installCmd: ['npm install -g markdown-language-server'],
    fileExtensions: ['.md', '.mdx'],
    serverCommand: 'markdown-language-server',
    serverArgs: ['--stdio'],
  ),
  'bash': LspServerInfo(
    languageId: 'bash',
    displayName: 'Bash',
    installCmd: ['npm install -g bash-language-server'],
    fileExtensions: ['.sh', '.bash', '.zsh', '.fish'],
    serverCommand: 'bash-language-server',
    serverArgs: ['start'],
  ),
  'dockerfile': LspServerInfo(
    languageId: 'dockerfile',
    displayName: 'Dockerfile',
    installCmd: ['npm install -g dockerfile-language-server-nodejs'],
    fileExtensions: ['Dockerfile', '.dockerfile'],
    serverCommand: 'docker-langserver',
    serverArgs: ['--stdio'],
  ),
};

/// Manages LSP server detection and lifecycle.
class LspService {
  LspService._();
  static final LspService instance = LspService._();

  final Map<String, bool> _installedCache = {};
  bool _initialized = false;

  /// Initialize — detect installed servers (cached).
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    // Run detection in background
    _detectInstalled();
    PandaLog.i('LspService', 'LSP service initialized');
  }

  /// Detect which servers are installed (runs async, populates cache).
  Future<void> _detectInstalled() async {
    for (final entry in kLspServers.entries) {
      try {
        final result = await Process.run(
          '/system/bin/sh',
          ['-c', entry.value._check],
          environment: {'PATH': '/usr/local/bin:/usr/bin:/bin'},
        );
        final installed = result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty;
        _installedCache[entry.key] = installed;
      } catch (_) {
        _installedCache[entry.key] = false;
      }
    }
    PandaLog.i('LspService', 'LSP detection complete: ${_installedCache.entries.where((e) => e.value).map((e) => e.key).join(', ')}');
  }

  /// Get the language ID for a file extension.
  String? languageIdForFile(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    final basename = p.basename(filePath);

    for (final entry in kLspServers.entries) {
      if (entry.value.fileExtensions.any((e) =>
          e.toLowerCase() == ext || e == basename)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Check if a language server is installed for a file.
  bool isInstalled(String languageId) {
    return _installedCache[languageId] ?? false;
  }

  /// Get server info for a language.
  LspServerInfo? getServerInfo(String languageId) {
    return kLspServers[languageId];
  }

  /// Check installation status (refresh cache).
  Future<bool> checkInstalled(String languageId) async {
    final info = kLspServers[languageId];
    if (info == null) return false;

    try {
      final result = await Process.run(
        '/system/bin/sh',
        ['-c', info._check],
        environment: {'PATH': '/usr/local/bin:/usr/bin:/bin'},
      );
      final installed = result.exitCode == 0;
      _installedCache[languageId] = installed;
      return installed;
    } catch (_) {
      _installedCache[languageId] = false;
      return false;
    }
  }

  /// Get a summary of all server statuses.
  Map<String, bool> getAllStatus() {
    final status = <String, bool>{};
    for (final key in kLspServers.keys) {
      status[key] = _installedCache[key] ?? false;
    }
    return status;
  }

  /// Force re-detect all servers.
  Future<void> refreshDetection() async {
    _initialized = false;
    _installedCache.clear();
    await initialize();
  }
}
