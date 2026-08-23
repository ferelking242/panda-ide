import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:panda/utils/alpine_setup.dart';
import 'package:panda/utils/constants.dart';
import 'package:panda/utils/panda_log.dart';

/// Result of one `apk` invocation inside the Alpine rootfs (via PRoot).
class ApkResult {
  final int exitCode;
  final List<String> lines;
  const ApkResult(this.exitCode, this.lines);

  bool get ok => exitCode == 0;
  String get text => lines.join('\n');
}

/// One package entry parsed from `apk search -v` / `apk info`.
class ApkPackage {
  final String name;
  final String version;
  final String description;
  final bool installed;
  const ApkPackage({
    required this.name,
    required this.version,
    this.description = '',
    this.installed = false,
  });

  /// Bare entry for an installed package name (metadata filled later).
  factory ApkPackage.bare(String name) => ApkPackage(
        name: name,
        version: '',
        description: '',
        installed: true,
      );

  ApkPackage copyWith({String? version, String? description, bool? installed}) =>
      ApkPackage(
        name: name,
        version: version ?? this.version,
        description: description ?? this.description,
        installed: installed ?? this.installed,
      );
}

/// Real `apk` backend executed through PRoot inside the Alpine rootfs —
/// exactly what a user would type in the terminal, surfaced to the UI.
class ApkService {
  static bool _running = false;
  static bool get isBusy => _running;

  /// Spawn `apk <args>` through PRoot, streaming stdout/stderr lines.
  static Future<ApkResult> run(
    List<String> args, {
    void Function(String line)? onLine,
  }) async {
    if (!AlpineSetup.isRootfsComplete()) {
      return const ApkResult(-1, ['Alpine Linux n\'est pas encore configuré']);
    }
    final prootBin = await AlpineSetup.locateProotBinary(AlpineSetup.alpineDir);
    if (prootBin == null) {
      return const ApkResult(-1, ['PRoot introuvable']);
    }

    final rootfsDir = AlpineSetup.alpineDir;
    final prootArgs = <String>[
      '-0',
      '--link2symlink',
      '--kill-on-exit',
      '--rootfs=$rootfsDir',
      '-b', '/dev',
      '-b', '/proc',
      '-b', '/sys',
      '-w', '/root',
      '/sbin/apk',
      ...args,
    ];

    final env = await AlpineSetup.prootSessionEnvironment();
    // No LD_PRELOAD-style leakage into guest: profile unsets it, but apk runs
    // non-login here so drop it explicitly for cleanliness.
    // ⚠️ NE PAS retirer : libproot.so a besoin de cette var AU LINK
        // pour trouver libtalloc.so (sinon CANNOT LINK EXECUTABLE).;

    final lines = <String>[];
    try {
      _running = true;
      final process = await Process.start(
        prootBin,
        prootArgs,
        workingDirectory: appDir,
        environment: env,
      );
      final outSub = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((l) {
            lines.add(l);
            onLine?.call(l);
          });
      final errSub = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((l) {
            lines.add(l);
            onLine?.call(l);
          });
      final code = await process.exitCode;
      await outSub.asFuture<void>().catchError((_) {});
      await errSub.asFuture<void>().catchError((_) {});
      return ApkResult(code, lines);
    } catch (e) {
      PandaLog.e('ApkService', 'apk ${args.join(" ")} failed: $e');
      return ApkResult(-1, [e.toString()]);
    } finally {
      _running = false;
    }
  }

  /// Parse `pkg-1.2.3-r0: some description here` (apk search -v output).
  static ApkPackage? parseSearchLine(String line) {
    final idx = line.indexOf(':');
    if (idx <= 0) return null;
    final head = line.substring(0, idx).trim();
    final desc = line.substring(idx + 1).trim();
    final dash = head.lastIndexOf('-');
    if (dash <= 0) return null;
    final name = head.substring(0, dash);
    final version = head.substring(dash + 1);
    if (name.isEmpty || name.contains(' ')) return null;
    return ApkPackage(name: name, version: version, description: desc);
  }

  /// Available packages matching [query] (empty query = popular subset via
  /// `apk search -v` on a common prefix is not possible, so we require >=1 char
  /// or list installed instead).
  static Future<List<ApkPackage>> search(
    String query, {
    void Function(String line)? onLine,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final res = await run(['search', '-v', q], onLine: onLine);
    final pkgs = <ApkPackage>[];
    for (final line in res.lines) {
      final p = parseSearchLine(line);
      if (p != null) pkgs.add(p);
    }
    return pkgs;
  }

  /// Names of installed packages (`apk info -v`), sorted.
  static Future<List<String>> listInstalled() async {
    final res = await run(['info', '-v']);
    final names = res.lines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList()
      ..sort();
    return names;
  }

  /// Everything installed, with metadata from `apk info` (verbose blocks).
  static Future<List<ApkPackage>> installedPackages() async {
    final names = await listInstalled();
    return names.map(ApkPackage.bare).toList(growable: false);
  }

  /// Detailed metadata for one package: `apk info <pkg>` (installed detail)
  /// falls back to search line for available-but-not-installed packages.
  static Future<ApkPackage?> detail(ApkPackage base) async {
    final res = await run(['info', base.name]);
    if (!res.ok || res.lines.isEmpty) {
      return base.copyWith(installed: false);
    }
    var desc = '';
    var version = base.version;
    var size = '';
    for (final l in res.lines) {
      if (l.startsWith('description:')) {
        desc = l.substring('description:'.length).trim();
      } else if (l.startsWith('version:')) {
        version = l.substring('version:'.length).trim();
      } else if (l.startsWith('size:')) {
        size = l.substring('size:'.length).trim();
      }
    }
    final full = size.isEmpty ? desc : '$desc • $size';
    return base.copyWith(version: version, description: full, installed: true);
  }

  static Future<ApkResult> install(String pkg, {void Function(String)? onLine}) =>
      run(['add', pkg], onLine: onLine);

  static Future<ApkResult> uninstall(String pkg, {void Function(String)? onLine}) =>
      run(['del', pkg], onLine: onLine);

  static Future<ApkResult> updateRepos({void Function(String)? onLine}) =>
      run(['update'], onLine: onLine);

  static Future<ApkResult> upgrade({void Function(String)? onLine}) =>
      run(['upgrade'], onLine: onLine);
}
