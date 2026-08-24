import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:code_forge/code_forge.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:path_provider/path_provider.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:panda/utils/themes.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../terminal/terminal.dart';
import '../utils/constants.dart';
import '../utils/languages.dart';

// Extractor and native channel utilities
// Extracted from functions.dart

class Extractor {
  static Future<void> extractZip(
    BuildContext context,
    String inputPath,
    String outputDir, {
    String? archiveName,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final progressNotifier = ValueNotifier<double>(0.0);

    final snackbar = SnackBar(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(days: 1),
      content: ValueListenableBuilder<double>(
        valueListenable: progressNotifier,
        builder: (context, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Extracting${archiveName == null ? "" : " "}${archiveName ?? "..."}',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 6),
            LinearPercentIndicator(
              percent: value.clamp(0.0, 1.0),
              progressColor: Colors.greenAccent,
              backgroundColor: Colors.white24,
              barRadius: const Radius.circular(20),
              lineHeight: 8,
              trailing: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  "${(value * 100).toStringAsFixed(1)}%",
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );

    messenger.showSnackBar(snackbar);

    try {
      await ZipFile.extractToDirectory(
        zipFile: File(inputPath),
        destinationDir: Directory(outputDir),
        onExtracting: (entry, rawProgress) {
          progressNotifier.value = rawProgress / 100.0;
          return ZipFileOperation.includeItem;
        },
      );

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('🎉 Extraction complete!')),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('❌ Extraction failed')),
      );
      debugPrint('Extraction error: $e');
    }
  }

  static Future<void> extractZipBackground(
    String inputPath,
    String outputDir, {
    String? archiveName,
    Function(double)? onProgress,
  }) async {
    try {
      await ZipFile.extractToDirectory(
        zipFile: File(inputPath),
        destinationDir: Directory(outputDir),
        onExtracting: (entry, rawProgress) {
          onProgress?.call(rawProgress);
          return ZipFileOperation.includeItem;
        },
      );
    } catch (e) {
      debugPrint('Extraction error for $archiveName: $e');
    }
  }
}

class NativeChannel {
  // Keep these names aligned with the active MainActivity in
  // android/app/src/main/kotlin/com/panda/ide/MainActivity.kt.
  static const MethodChannel _channel = MethodChannel('com.panda.ide');
  static const MethodChannel _pfdMethodChannel = MethodChannel('panda/pfd');
  static const EventChannel _pfdEventChannel = EventChannel('panda/pfd_events');

  static Future<String> getLibraryPath() async {
    try {
      final String result = await _channel.invokeMethod('getLibraryPath');
      return result;
    } on PlatformException catch (e) {
      return "Failed to load library: ${e.message}";
    }
  }

  static Future<String> getExternalMediaDir() async {
    try {
      final String result = await _channel.invokeMethod('getExtMediaPath');
      return result;
    } catch (e) {
      return "Error $e";
    }
  }

  static Future<List<String>> consumePendingOpenFiles() async {
    try {
      final List<dynamic>? raw = await _channel.invokeMethod<List<dynamic>>(
        'consumePendingOpenFiles',
      );
      if (raw == null) return const [];
      return raw.map((item) => item.toString()).toList();
    } on PlatformException catch (e) {
      debugPrint('Failed to read pending open files: ${e.message}');
      return const [];
    }
  }

  static Future<bool> isModuleInstalled(String moduleName) async {
    try {
      final bool? installed = await _pfdMethodChannel.invokeMethod<bool>(
        'isModuleInstalled',
        {'moduleName': moduleName},
      );
      return installed ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to check module install state: ${e.message}');
      return false;
    }
  }

  static Future<void> installModule(String moduleName) async {
    await _pfdMethodChannel.invokeMethod(
      'installModule',
      {'moduleName': moduleName},
    );
  }

  static Future<void> uninstallModule(String moduleName) async {
    await _pfdMethodChannel.invokeMethod(
      'uninstallModule',
      {'moduleName': moduleName},
    );
  }

  static Future<void> copyModuleAssetToPath({
    required String moduleName,
    required String assetName,
    required String targetPath,
  }) async {
    await _pfdMethodChannel.invokeMethod(
      'copyModuleAssetToPath',
      {
        'moduleName': moduleName,
        'assetName': assetName,
        'targetPath': targetPath,
      },
    );
  }

  static Future<bool> syncImportedItem({
    required String sourceUri,
    required String localPath,
    required bool isDirectory,
  }) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'syncImportedItem',
        {
          'sourceUri': sourceUri,
          'localPath': localPath,
          'isDirectory': isDirectory,
        },
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to sync imported item: ${e.message}');
      return false;
    }
  }

  static Stream<Map<String, dynamic>> moduleInstallEvents() {
    return _pfdEventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return Map<String, dynamic>.from(event);
      }
      return <String, dynamic>{};
    }).where((event) => event.isNotEmpty);
  }
}

