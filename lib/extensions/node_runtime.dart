import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../utils/constants.dart';

/// Manages the Node.js runtime binary for the extension host.
///
/// The node binary is required for running VS Code extensions (Node.js).
/// It can be:
///   1. Bundled in assets/ (for small builds)
///   2. Downloaded via Play Feature Delivery (PFD)
///   3. Downloaded via HTTP from GitHub releases
class NodeRuntimeManager {
  static final NodeRuntimeManager instance = NodeRuntimeManager._();
  NodeRuntimeManager._();

  bool _installed = false;
  bool get isInstalled => _installed;

  String? _nodePath;
  String? get nodePath => _nodePath;

  /// Version of the installed node binary.
  String? _version;
  String? get version => _version;

  // ── Initialization ──────────────────────────────────────────────────────

  /// Initialize the Node.js runtime.
  /// Checks if node is already installed, if not, tries to extract from assets.
  Future<bool> init() async {
    // 1. Check if node binary already exists at the expected path
    final expectedPath = '$binDir/node';
    if (File(expectedPath).existsSync()) {
      _nodePath = expectedPath;
      _installed = true;
      _version = await _getVersion();
      return true;
    }

    // 2. Check alternative paths
    final altPaths = [
      '$runtimesDir/node/bin/node',
      '$runtimesDir/node',
      '/data/data/com.termux.app/files/usr/bin/node',
      '$appDir/node/bin/node',
    ];

    for (final path in altPaths) {
      if (File(path).existsSync()) {
        _nodePath = path;
        _installed = true;
        _version = await _getVersion();
        // Copy to expected location for consistency
        await _copyToExpectedPath(path);
        return true;
      }
    }

    // 3. Try to extract from bundled assets
    final extracted = await _extractFromAssets();
    if (extracted) {
      _nodePath = expectedPath;
      _installed = true;
      _version = await _getVersion();
      return true;
    }

    return false;
  }

  // ── Asset extraction ──────────────────────────────────────────────────

  /// Try to extract node binary from Flutter assets.
  Future<bool> _extractFromAssets() async {
    try {
      final data = await rootBundle.load('assets/bin/node');
      if (data.lengthInBytes == 0) return false;

      final dir = Directory(binDir);
      if (!dir.existsSync()) await dir.create(recursive: true);

      final file = File('$binDir/node');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );

      // Make executable (chmod +x)
      await Process.run('chmod', ['755', file.path]);

      return file.existsSync();
    } catch (_) {
      return false;
    }
  }

  // ── HTTP download ─────────────────────────────────────────────────────

  /// Download node binary from a URL (GitHub releases, custom server, etc.).
  Future<bool> downloadFromUrl(String url, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) return false;

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      final dir = Directory(binDir);
      if (!dir.existsSync()) await dir.create(recursive: true);

      final file = File('$binDir/node');
      final sink = file.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call(receivedBytes / totalBytes);
        }
      }

      await sink.flush();
      await sink.close();

      // Make executable
      await Process.run('chmod', ['755', file.path]);

      _nodePath = file.path;
      _installed = true;
      _version = await _getVersion();

      return true;
    } catch (e) {
      return false;
    }
  }

  // ── PFD download ──────────────────────────────────────────────────────

  /// Download via Play Feature Delivery (PFD).
  /// This is the recommended method for Android — the node binary is
  /// delivered as a feature module (~80MB compressed).
  Future<bool> downloadViaPFD({
    void Function(double progress)? onProgress,
  }) async {
    try {
      // The PFD download is handled by PackageDownloader
      // This method just checks if the result landed in the right place
      final pfdPath = '$runtimesDir/node/bin/node';
      if (File(pfdPath).existsSync()) {
        await _copyToExpectedPath(pfdPath);
        _nodePath = '$binDir/node';
        _installed = true;
        _version = await _getVersion();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Installation status ───────────────────────────────────────────────

  /// Get detailed installation status.
  Future<NodeRuntimeStatus> getStatus() async {
    final installed = _installed || File('$binDir/node').existsSync();
    final version = installed ? await _getVersion() : null;
    final size = installed ? await _getBinarySize() : 0;

    return NodeRuntimeStatus(
      installed: installed,
      path: _nodePath,
      version: version,
      sizeBytes: size,
      required: true, // Required for extensions
    );
  }

  /// Get the download URL for the current platform.
  static String getDownloadUrl() {
    // Node.js official builds for Android (arm64)
    return 'https://nodejs.org/dist/v20.11.1/node-v20.11.1-android-arm64.tar.gz';
  }

  // ── Private helpers ──────────────────────────────────────────────────

  Future<String?> _getVersion() async {
    if (_nodePath == null) return null;
    try {
      final result = await Process.run(_nodePath!, ['--version']);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}
    return null;
  }

  Future<int> _getBinarySize() async {
    if (_nodePath == null) return 0;
    try {
      final file = File(_nodePath!);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  Future<void> _copyToExpectedPath(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return;

      final dir = Directory(binDir);
      if (!dir.existsSync()) await dir.create(recursive: true);

      final dest = File('$binDir/node');
      await source.copy(dest.path);
      await Process.run('chmod', ['755', dest.path]);
    } catch (_) {}
  }

  /// Dispose resources.
  void dispose() {
    _installed = false;
    _nodePath = null;
    _version = null;
  }
}

/// Status of the Node.js runtime installation.
class NodeRuntimeStatus {
  final bool installed;
  final String? path;
  final String? version;
  final int sizeBytes;
  final bool required;

  const NodeRuntimeStatus({
    required this.installed,
    this.path,
    this.version,
    this.sizeBytes = 0,
    required this.required,
  });

  String get sizeText {
    if (sizeBytes == 0) return 'Not installed';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
