/// PackageDownloader — background-safe, IDM-style resume download service.
///
/// Extracted from _DownloadManagerState so downloads survive widget disposal.
/// Features:
///   • HTTP Range-header resume: picks up where it left off on failure.
///   • Global active-index registry: no duplicate concurrent downloads.
///   • HTTP archives are extracted into the terminal-managed directories.
///   • Snackbar feedback is best-effort (silently skipped if context gone).
library;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import '../bloc/ui_bloc/ui_bloc.dart';
import '../utils/debian_setup.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/languages.dart';



// ─── Global state (survives widget disposal) ─────────────────────────────────

/// Set of indexes currently being downloaded (globally).
final Set<int> _globalActiveIndexes = {};

// ─── PackageDownloader ───────────────────────────────────────────────────────

class PackageDownloader {
  /// Entry point. Call from any widget that has the required BLoC providers.
  static Future<void> startDownload({
    required BuildContext context,
    required int index,
    required String url,
    required String archiveName,
    required String targetDir,
    required bool isExtension,
    String? packageParentName,
    Extension? extensionMetadata,
  }) async {
    // Prevent duplicate concurrent downloads on same index
    if (_globalActiveIndexes.contains(index)) {
      _showSnack(context, 'Already downloading, please wait…');
      return;
    }

    final normalizedParent = packageParentName?.toLowerCase();

    // Clang prerequisite for Rust/Go
    if (!isExtension &&
        (normalizedParent == 'rust' || normalizedParent == 'go') &&
        !_isClangInstalled()) {
      _showSnack(context, 'Clang runtime is required before downloading Rust or Go.');
      return;
    }

    final downloadBloc  = context.read<DownloadManagerBloc>();
    final catalogCubit  = context.read<PackageCatalogCubit>();

    _globalActiveIndexes.add(index);

    try {
      // Runtime and extension packages use the terminal/HTTP source only.
      if (url.isEmpty) {
        downloadBloc.clearProgress(index);
        _showSnack(context, 'No download source is available for this package.');
        return;
      }
      await _httpDownload(
        context: context,
        downloadBloc: downloadBloc,
        catalogCubit: catalogCubit,
        index: index,
        url: url,
        archivePath: '$tempDir/$archiveName',
        archiveName: archiveName,
        extractDir: isExtension ? extensionDir : runtimesDir,
        runtimeParentName: packageParentName,
        extensionMetadata: extensionMetadata,
        isExtension: isExtension,
      );
    } finally {
      _globalActiveIndexes.remove(index);
    }
  }

  // ── HTTP download with resume (IDM/ADM style) ──────────────────────────────

  static Future<void> _httpDownload({
    required BuildContext context,
    required int index,
    required DownloadManagerBloc downloadBloc,
    required PackageCatalogCubit catalogCubit,
    required String url,
    required String archivePath,
    required String archiveName,
    required String extractDir,
    required String? runtimeParentName,
    required Extension? extensionMetadata,
    required bool isExtension,
  }) async {
    final tempDirectory = Directory(tempDir);
    if (!tempDirectory.existsSync()) await tempDirectory.create(recursive: true);

    final file = File(archivePath);
    int resumeFrom = 0;

    // Resume: check if partial file already exists
    if (await file.exists()) {
      resumeFrom = await file.length();
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      if (resumeFrom > 0) {
        request.headers['Range'] = 'bytes=$resumeFrom-';
      }

      final response = await client.send(request);

      // Accept 200 (full) or 206 (partial / resumed)
      if (response.statusCode != 200 && response.statusCode != 206) {
        _showSnack(context, 'Download failed: HTTP ${response.statusCode}');
        downloadBloc.clearProgress(index);
        return;
      }

      // If server doesn't support range, restart from 0
      if (resumeFrom > 0 && response.statusCode == 200) {
        resumeFrom = 0;
        await file.writeAsBytes([]);           // truncate
      }

      final contentLength = response.contentLength ?? 0;
      final totalBytes    = resumeFrom + (contentLength > 0 ? contentLength : 0);
      int receivedBytes   = resumeFrom;

      final sink = file.openWrite(mode: resumeFrom > 0 ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            final progress = (receivedBytes / totalBytes * 80.0).clamp(0.0, 80.0);
            downloadBloc.updateProgress(index, progress);
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (isExtension && !_requiresExtraction(archiveName)) {
        final normalizedParent = runtimeParentName?.toLowerCase();
        if (normalizedParent != null && extensionMetadata != null) {
          downloadBloc.updateProgress(index, 100.0);
          downloadBloc.markFullyCompleted(index);
          await catalogCubit.refreshInstalledStatusOnly();
          return;
        }
      }

      await _extractArchive(
        downloadBloc: downloadBloc,
        catalogCubit: catalogCubit,
        index: index,
        archivePath: archivePath,
        extractDir: extractDir,
        archiveName: archiveName,
        runtimeParentName: runtimeParentName,
      );
    } catch (e) {
      _showSnack(context, 'Download error: $e');
      downloadBloc.clearProgress(index);
    } finally {
      client.close();
    }
  }

  // ── Archive extraction ─────────────────────────────────────────────────────

  static Future<void> _extractArchive({
    required DownloadManagerBloc downloadBloc,
    required PackageCatalogCubit catalogCubit,
    required int index,
    required String archivePath,
    required String extractDir,
    required String archiveName,
    String? runtimeParentName,
  }) async {
    downloadBloc.startExtracting(index);

    try {
      await Extractor.extractZipBackground(
        archivePath,
        extractDir,
        archiveName: archiveName,
        onProgress: (p) => downloadBloc.updateExtractionProgress(index, p),
      );

      final archiveFile = File(archivePath);
      if (await archiveFile.exists()) await archiveFile.delete();

      final n = runtimeParentName?.toLowerCase();
      if (n == 'python'      || archiveName == 'python.zip')           await _createPythonSymlinks();
      if (n == 'java'        || n == 'java-21-openjdk' || archiveName == 'java-21-openjdk.zip') await _copyJavaLibraries();
      if (n == 'clang'       || archiveName == 'clang.zip')             await _createClangSymlinks();
      if (n == 'dart'        || archiveName == 'dart.zip')              await _createDartSymlinks();
      if (n == 'rust'        || archiveName == 'rust.zip')              await _createRustSymlinks();
      if (n == 'go'          || archiveName == 'go.zip')                await _createGoSymlinks();
      if (n == 'ruby'        || archiveName == 'ruby.zip')              await _createRubySymlinks();
      if (n == 'lua'         || archiveName == 'lua.zip')               await _createLuaSymlinks();
      // if (n == 'alpine-linux'|| archiveName == 'alpine-proot.tar.gz')  await _setupAlpineProot();

      downloadBloc.markFullyCompleted(index);
    } catch (e) {
      debugPrint('Extraction error: $e');
      downloadBloc.markFullyCompleted(index);
    } finally {
      await catalogCubit.refreshInstalledStatusOnly();
    }
  }

  // ── Symlink / library helpers ──────────────────────────────────────────────

  static final List<String> _pythonDynload = [
    'array.cpython-313-aarch64-linux-android.so','_asyncio.cpython-313-aarch64-linux-android.so','binascii.cpython-313-aarch64-linux-android.so','_bisect.cpython-313-aarch64-linux-android.so','_blake2.cpython-313-aarch64-linux-android.so','_bz2.cpython-313-aarch64-linux-android.so','cmath.cpython-313-aarch64-linux-android.so','_codecs_cn.cpython-313-aarch64-linux-android.so','_codecs_hk.cpython-313-aarch64-linux-android.so','_codecs_iso2022.cpython-313-aarch64-linux-android.so','_codecs_jp.cpython-313-aarch64-linux-android.so','_codecs_kr.cpython-313-aarch64-linux-android.so','_codecs_tw.cpython-313-aarch64-linux-android.so','_contextvars.cpython-313-aarch64-linux-android.so','_csv.cpython-313-aarch64-linux-android.so','_ctypes.cpython-313-aarch64-linux-android.so','_ctypes_test.cpython-313-aarch64-linux-android.so','_datetime.cpython-313-aarch64-linux-android.so','_decimal.cpython-313-aarch64-linux-android.so','_elementtree.cpython-313-aarch64-linux-android.so','fcntl.cpython-313-aarch64-linux-android.so','_hashlib.cpython-313-aarch64-linux-android.so','_heapq.cpython-313-aarch64-linux-android.so','_interpchannels.cpython-313-aarch64-linux-android.so','_interpqueues.cpython-313-aarch64-linux-android.so','_interpreters.cpython-313-aarch64-linux-android.so','_json.cpython-313-aarch64-linux-android.so','_lsprof.cpython-313-aarch64-linux-android.so','_lzma.cpython-313-aarch64-linux-android.so','math.cpython-313-aarch64-linux-android.so','_md5.cpython-313-aarch64-linux-android.so','mmap.cpython-313-aarch64-linux-android.so','_multibytecodec.cpython-313-aarch64-linux-android.so','_opcode.cpython-313-aarch64-linux-android.so','_pickle.cpython-313-aarch64-linux-android.so','_posixsubprocess.cpython-313-aarch64-linux-android.so','pyexpat.cpython-313-aarch64-linux-android.so','_queue.cpython-313-aarch64-linux-android.so','_random.cpython-313-aarch64-linux-android.so','resource.cpython-313-aarch64-linux-android.so','select.cpython-313-aarch64-linux-android.so','_sha1.cpython-313-aarch64-linux-android.so','_sha2.cpython-313-aarch64-linux-android.so','_sha3.cpython-313-aarch64-linux-android.so','_socket.cpython-313-aarch64-linux-android.so','_sqlite3.cpython-313-aarch64-linux-android.so','_ssl.cpython-313-aarch64-linux-android.so','_statistics.cpython-313-aarch64-linux-android.so','_struct.cpython-313-aarch64-linux-android.so','syslog.cpython-313-aarch64-linux-android.so','termios.cpython-313-aarch64-linux-android.so','_testbuffer.cpython-313-aarch64-linux-android.so','_testcapi.cpython-313-aarch64-linux-android.so','_testclinic.cpython-313-aarch64-linux-android.so','_testclinic_limited.cpython-313-aarch64-linux-android.so','_testexternalinspection.cpython-313-aarch64-linux-android.so','_testimportmultiple.cpython-313-aarch64-linux-android.so','_testinternalcapi.cpython-313-aarch64-linux-android.so','_testlimitedcapi.cpython-313-aarch64-linux-android.so','_testmultiphase.cpython-313-aarch64-linux-android.so','_testsinglephase.cpython-313-aarch64-linux-android.so','unicodedata.cpython-313-aarch64-linux-android.so','xxlimited_35.cpython-313-aarch64-linux-android.so','xxlimited.cpython-313-aarch64-linux-android.so','xxsubtype.cpython-313-aarch64-linux-android.so','_xxtestfuzz.cpython-313-aarch64-linux-android.so','zlib.cpython-313-aarch64-linux-android.so','_zoneinfo.cpython-313-aarch64-linux-android.so',
  ];

  static const Map<String, String> _pythonLibSymlinks = {
    'libcrypto.so': 'libcrypto_python.so',
    'libsqlite3.so': 'libsqlite3_python.so',
    'libssl.so': 'libssl_python.so',
  };

  static const List<String> _pythonEngines = ['afalg.so','capi.so','loader_attic.so','padlock.so'];
  static const List<String> _pythonOssl    = ['legacy.so'];

  static final List<String> _javaLibPaths = [
    'lib/libandroid-shmem.so','lib/libandroid-spawn.so','lib/libattach.so','lib/libawt_headless.so','lib/libawt.so','lib/libawt_xawt.so','lib/libdt_socket.so','lib/libextnet.so','lib/libfontmanager.so','lib/libinstrument.so','lib/libj2gss.so','lib/libj2pcsc.so','lib/libj2pkcs11.so','lib/libjaas.so','lib/libjavajpeg.so','lib/libjava.so','lib/libjawt.so','lib/libjdwp.so','lib/libjimage.so','lib/libjli.so','lib/libjsig.so','lib/libjsound.so','lib/liblcms.so','lib/lible.so','lib/libmanagement_agent.so','lib/libmanagement_ext.so','lib/libmanagement.so','lib/libmlib_image.so','lib/libnet.so','lib/libnio.so','lib/libprefs.so','lib/librmi.so','lib/libsctp.so','lib/libsplashscreen.so','lib/libsyslookup.so','lib/libverify.so','lib/libzip.so','lib/server/libjsig.so','lib/server/libjvm.so',
  ];

  static const List<String> _clangLibPaths = [
    'libclang-cpp.so','libffi.so','libLLVM.so',
    'lib/clang/21/lib/linux/libclang_rt.asan-aarch64-android.so',
    'lib/clang/21/lib/linux/libclang_rt.hwasan-aarch64-android.so',
    'lib/clang/21/lib/linux/libclang_rt.tsan-aarch64-android.so',
    'lib/clang/21/lib/linux/libclang_rt.ubsan_minimal-aarch64-android.so',
    'lib/clang/21/lib/linux/libclang_rt.ubsan_standalone-aarch64-android.so',
  ];

  static const List<String> _goTools = ['asm','cgo','compile','cover','fix','link','preprofile','vet'];

  static const List<String> _rustOtherLibs = [
    'libandroid-execinfo.so','libdarling_macro-403b3f47737f0e10.so','libderive_setters-61a4b05c47bf1772.so','libderive_where-558b72763d14629c.so','libdisplaydoc-88ec4bfd0c13b0f9.so','libffi.so','libLLVM.so','libproc_macro_hack-b9a0cb31558b686e.so','libref_cast_impl-a8bcededf9b7ab39.so','librustc_driver-cd257725849a655d.so','librustc_fluent_macro-cc29f51bb1aff38e.so','librustc_index_macros-5b5db17373d6eb5f.so','librustc_macros-cd1aad3275f4d011.so','librustc_type_ir_macros-94b75363d95b2ff4.so','libschemars_derive-590652653e5b083d.so','libserde_derive-5c6bc018f5fc6183.so','libstd-6ea53b9eff82e224.so','libthiserror_impl-a3575ba7b15740eb.so','libtracing_attributes-ab9b431608591db8.so','libunic_langid_macros_impl-cb32e7867e91c5f5.so','libyoke_derive-9a29fbe7d205c401.so','libzerofrom_derive-6b82ce44af5b9e5d.so','libzerovec_derive-851096cd7124147b.so',
  ];

  static Future<void> _createPythonSymlinks() async {
    final shared = await NativeChannel.getLibraryPath();
    final libDir2  = '$runtimesDir/python/lib';
    final dynload = '$libDir2/python3.13/lib-dynload';
    final engines = '$libDir2/engines-3';
    final ossl    = '$libDir2/ossl-modules';
    if (!Directory(libDir2).existsSync()) return;
    for (final d in [dynload, engines, ossl]) {
      if (!Directory(d).existsSync()) await Directory(d).create(recursive: true);
    }
    for (final m in _pythonDynload) {
      await _symlink('$dynload/$m', '$shared/$m');
    }
    for (final e in _pythonLibSymlinks.entries) {
      await _symlink('$libDir2/${e.key}', '$shared/${e.value}');
    }
    for (final m in _pythonEngines) {
      await _symlink('$engines/$m', '$shared/$m');
    }
    for (final m in _pythonOssl) {
      await _symlink('$ossl/$m', '$shared/$m');
    }
  }

  static Future<void> _copyJavaLibraries() async {
    final shared   = await NativeChannel.getLibraryPath();
    final javaHome = '$runtimesDir/java-21-openjdk';
    if (!Directory(javaHome).existsSync()) return;
    for (final rel in _javaLibPaths) {
      final src = '$shared/${rel.split('/').last}';
      if (!File(src).existsSync()) continue;
      await _fileCopy(src: src, dst: '$javaHome/$rel');
    }
  }

  static Future<void> _createClangSymlinks() async {
    final shared   = await NativeChannel.getLibraryPath();
    final clangDir = '$runtimesDir/clang';
    if (!Directory(clangDir).existsSync()) return;
    for (final rel in _clangLibPaths) {
      await _symlink('$clangDir/$rel', '$shared/${rel.split('/').last}');
    }
  }

  static Future<void> _createDartSymlinks() async {
    final shared   = await NativeChannel.getLibraryPath();
    final dartBin  = '$runtimesDir/dart/bin';
    if (!Directory(dartBin).existsSync()) return;
    if (!Directory(binDir).existsSync()) await Directory(binDir).create(recursive: true);
    await _symlink('$dartBin/dart',         '$shared/libdart.so');
    await _symlink('$dartBin/dartvm',       '$shared/libdartvm.so');
    await _symlink('$dartBin/libdart.so',   '$shared/libdartaotruntime.so');
    await _symlink('$dartBin/dartaotruntime', '$dartBin/libdart.so');
    await _symlink('$binDir/dart',          '$shared/libloader.so');
  }

  static Future<void> _createRustSymlinks() async {
    final shared = await NativeChannel.getLibraryPath();
    for (final d in [binDir, libDir]) {
      if (!Directory(d).existsSync()) await Directory(d).create(recursive: true);
    }
    await _symlink('$binDir/rustc',      '$shared/librustc.so');
    await _symlink('$binDir/rustloader', '$shared/librstloader.so');
    await _symlink('$binDir/cargo',      '$shared/libcargo.so');
    await _symlink('$libDir/libicudata.so.78', '$shared/libicudata.so');
    final rustlibDir = '$runtimesDir/rust/lib/rustlib/aarch64-linux-android/lib';
    if (!Directory(rustlibDir).existsSync()) await Directory(rustlibDir).create(recursive: true);
    for (final lib in _rustOtherLibs) {
      await _symlink('$rustlibDir/$lib', '$shared/$lib');
    }
  }

  static Future<void> _createGoSymlinks() async {
    final shared       = await NativeChannel.getLibraryPath();
    final goBin        = '$runtimesDir/go/bin';
    final goTool       = '$runtimesDir/go/pkg/tool/android_arm64';
    for (final d in [goBin, goTool, binDir]) {
      if (!Directory(d).existsSync()) await Directory(d).create(recursive: true);
    }
    await _symlink('$goBin/go',     '$shared/libgo.so');
    await _symlink('$goBin/gofmt',  '$shared/libgofmt.so');
    await _symlink('$binDir/go',    '$shared/libgo.so');
    await _symlink('$binDir/gofmt', '$shared/libgofmt.so');
    for (final t in _goTools) {
      await _symlink('$goTool/$t', '$shared/lib$t.so');
    }
  }

  static Future<void> _createRubySymlinks() async {
    final shared       = await NativeChannel.getLibraryPath();
    final rubyRoot     = '$runtimesDir/ruby/lib/ruby';
    if (!Directory(rubyRoot).existsSync() || !Directory(shared).existsSync()) return;
    if (!Directory(libDir).existsSync()) await Directory(libDir).create(recursive: true);
    await for (final e in Directory(shared).list(followLinks: false)) {
      if (e is! File) continue;
      final name = e.path.split('/').last;
      if (!name.startsWith('ruby_') || !name.endsWith('.so')) continue;
      final rel = name.substring('ruby_'.length).replaceAll('__', '/');
      await _symlink('$rubyRoot/$rel', '$shared/$name');
    }
    await _symlink('$libDir/libruby.so.3.4', '$shared/libruby.so');
  }

  static Future<void> _createLuaSymlinks() async {
    final shared  = await NativeChannel.getLibraryPath();
    final luaBin  = '$runtimesDir/lua/bin';
    if (!Directory(luaBin).existsSync()) await Directory(luaBin).create(recursive: true);
    await _symlink('$luaBin/lua',  '$shared/liblua.so');
    await _symlink('$luaBin/luac', '$shared/libluac.so');
  }

  // ── Alpine Linux + proot setup ────────────────────────────────────────────
  //
  // PRoot et ses dependances natives (libtalloc.so, libandroid-shmem.so,
  // libproot-loader.so) sont embarques dans l'APK et extraits par Android
  // dans applicationInfo.nativeLibraryDir. On ne copie JAMAIS libproot.so
  // vers /data/data : l'execution y est interdite depuis Android 10 (W^X),
  // et l'ancienne copie supprimait le binaire natif de l'APK.
  //
  static Future<void> _setupAlpineProot() async {
    try {
      await DebianSetup.ensureDebianRootfs();
      await DebianSetup.ensureDebianRuntimeFiles();

      final prootBin = await DebianSetup.locateProotBinary(DebianSetup.debianDir);
      debugPrint(
        'Debian proot setup complete — rootfs at ${DebianSetup.debianDir}, '
        'proot at ${prootBin ?? "introuvable"}',
      );
    } catch (e) {
      debugPrint('Debian proot setup error: $e');
    }
  }

  static Future<void> _symlinkExec({required String execName, required String libName}) async {
    final shared = await NativeChannel.getLibraryPath();
    final lib    = '$shared/$libName';
    if (!File(lib).existsSync()) throw Exception('$libName not found at $lib');
    if (!Directory(binDir).existsSync()) await Directory(binDir).create(recursive: true);
    await _symlink('$binDir/$execName', lib);
  }

  static Future<void> _symlink(String link, String target) async {
    try {
      final t = await FileSystemEntity.type(link, followLinks: false);
      if (t == FileSystemEntityType.file) {
        await File(link).delete();
      } else if (t == FileSystemEntityType.link)   await Link(link).delete();
      else if (t == FileSystemEntityType.directory) await Directory(link).delete(recursive: true);
      await Link(link).create(target, recursive: true);
    } catch (e) {
      debugPrint('symlink $link -> $target: $e');
    }
  }

  static Future<void> _fileCopy({required String src, required String dst}) async {
    try {
      final srcFile = File(src);
      if (!srcFile.existsSync()) return;
      final srcStat = await srcFile.stat();
      final dstType = await FileSystemEntity.type(dst, followLinks: false);
      if (dstType == FileSystemEntityType.file) {
        final dstStat = await File(dst).stat();
        if (dstStat.size == srcStat.size) return;
        await File(dst).delete();
      } else if (dstType == FileSystemEntityType.link) {
        await Link(dst).delete();
      } else if (dstType == FileSystemEntityType.directory) {
        await Directory(dst).delete(recursive: true);
      }
      await File(dst).parent.create(recursive: true);
      await srcFile.copy(dst);
    } catch (e) {
      debugPrint('filecopy $src -> $dst: $e');
    }
  }

  static Future<void> _writeExtensionMetadata(Extension ext) async {
    final installDir = Directory('$extensionDir/${ext.parentName}');
    if (!installDir.existsSync()) await installDir.create(recursive: true);
    await File('${installDir.path}/rsx-package.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(ext.toJson()),
      flush: true,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static bool _isClangInstalled() => Directory('$runtimesDir/clang').existsSync();

  static bool _requiresExtraction(String archiveName) =>
      archiveName.endsWith('.zip') || archiveName.endsWith('.tar.gz');

  static double mergeProgress(double base, double stage2) =>
      base + (stage2.clamp(0.0, 100.0) * ((100.0 - base) / 100.0));

  static void _showSnack(BuildContext context, String msg, {bool isError = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Resolve catalog alias (same as _resolveCatalogAlias in downloads.dart).
  static String resolveAlias(String key) {
    const aliases = {
      'java': 'java-21-openjdk',
      'nodejs': 'node',
      'node.js': 'node',
      'javascript': 'node',
      'typescript': 'node',
      'flutter': 'dart',
      'android-sdk': 'java-21-openjdk',
    };
    return aliases[key] ?? key;
  }

  /// Whether an index is currently being actively downloaded.
  static bool isActive(int index) => _globalActiveIndexes.contains(index);
}
