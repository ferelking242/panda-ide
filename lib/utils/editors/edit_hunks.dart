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
import '../../terminal/terminal.dart';
import '../constants.dart';
import '../languages.dart';

// Edit hunks and pending edit file models
// Extracted from functions.dart

class EditHunk {
  final String id;
  final String type;
  final int startLine, endLine;
  final int sourceStartLine, sourceEndLine;
  final int? afterLine;
  final String oldText;
  final String newText;
  final String? addedText;
  final String? removedText;

  const EditHunk({
    required this.id,
    required this.type,
    required this.startLine,
    required this.endLine,
    required this.sourceStartLine,
    required this.sourceEndLine,
    required this.oldText,
    required this.newText,
    this.afterLine,
    this.addedText,
    this.removedText,
  });

  factory EditHunk.fromJson(Map<String, dynamic> json) {
    return EditHunk(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'modified',
      startLine: (json['startLine'] as num?)?.toInt() ?? 0,
      endLine: (json['endLine'] as num?)?.toInt() ?? 0,
      sourceStartLine:
          (json['sourceStartLine'] as num?)?.toInt() ??
          (json['startLine'] as num?)?.toInt() ??
          0,
      sourceEndLine:
          (json['sourceEndLine'] as num?)?.toInt() ??
          (json['endLine'] as num?)?.toInt() ??
          0,
      oldText: json['oldText']?.toString() ?? '',
      newText: json['newText']?.toString() ?? '',
      afterLine: (json['afterLine'] as num?)?.toInt(),
      addedText: json['addedText']?.toString(),
      removedText: json['removedText']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      "startLine": startLine,
      "endLine": endLine,
      "sourceStartLine": sourceStartLine,
      "sourceEndLine": sourceEndLine,
      "oldText": oldText,
      "newText": newText,
      "afterLine": afterLine,
      "addedText": addedText,
      "removedText": removedText,
    };
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

class PendingEditFile {
  static const String _prefsKey = 'pendingAgenticEdits';

  final String filePath;
  final String oldText;
  final List<EditHunk> editHunks;

  const PendingEditFile({
    required this.filePath,
    required this.oldText,
    required this.editHunks,
  });

  factory PendingEditFile.fromJson(Map<String, dynamic> json) {
    final hunksRaw = json['editHunks'];
    final hunks = <EditHunk>[];
    if (hunksRaw is List) {
      for (final item in hunksRaw) {
        if (item is Map<String, dynamic>) {
          hunks.add(EditHunk.fromJson(item));
        } else if (item is Map) {
          hunks.add(EditHunk.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return PendingEditFile(
      filePath: json['filePath']?.toString() ?? '',
      oldText: json['oldText']?.toString() ?? '',
      editHunks: hunks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'oldText': oldText,
      'editHunks': editHunks.map((h) => h.toJson()).toList(),
    };
  }

  PendingEditFile copyWith({
    String? filePath,
    String? oldText,
    List<EditHunk>? editHunks,
  }) {
    return PendingEditFile(
      filePath: filePath ?? this.filePath,
      oldText: oldText ?? this.oldText,
      editHunks: editHunks ?? this.editHunks,
    );
  }

  static int _safeLineAtOffset(CodeForgeController controller, int offset) {
    final text = controller.text;
    if (text.isEmpty) return 0;
    final maxOffset = text.length - 1;
    final safeOffset = offset.clamp(0, maxOffset);
    return controller.getLineAtOffset(safeOffset);
  }

  static List<EditHunk> patchesToHunks(
    List<Patch> patches,
    CodeForgeController newController,
    CodeForgeController oldController,
  ) {
    final List<EditHunk> hunks = [];
    final ts = DateTime.now().microsecondsSinceEpoch;
    var idx = 0;

    for (final patch in patches) {
      var newCursor = patch.start2;
      var oldCursor = patch.start1;
      int? changedStartOffset;
      int? changedEndOffset;
      int? changedSourceStartOffset;
      int? changedSourceEndOffset;
      final newText = StringBuffer();
      final oldText = StringBuffer();
      final addedOnlyText = StringBuffer();
      final removedOnlyText = StringBuffer();
      var hasInsert = false;
      var hasDelete = false;

      for (final diff in patch.diffs) {
        if (diff.operation == 0 || diff.operation == -1) {
          oldText.write(diff.text);
        }

        if (diff.operation == 0 || diff.operation == 1) {
          newText.write(diff.text);
        }

        if (diff.operation == -1) {
          hasDelete = true;
          removedOnlyText.write(diff.text);
          changedSourceStartOffset ??= oldCursor;
          changedSourceEndOffset = (oldCursor + diff.text.length) - 1;
        } else if (diff.operation == 1) {
          hasInsert = true;
          addedOnlyText.write(diff.text);
          changedStartOffset ??= newCursor;
          changedEndOffset = (newCursor + diff.text.length) - 1;
        }

        if (diff.operation == 0 || diff.operation == 1) {
          newCursor += diff.text.length;
        }
        if (diff.operation == 0 || diff.operation == -1) {
          oldCursor += diff.text.length;
        }
      }

      final type = hasInsert && hasDelete
          ? 'modified'
          : hasInsert
          ? 'added'
          : 'removed';
      final rangeStartOffset = changedStartOffset ?? patch.start2;
      final rangeEndOffset = changedEndOffset ?? rangeStartOffset;
      final sourceRangeStartOffset = changedSourceStartOffset ?? patch.start1;
      final sourceRangeEndOffset =
          changedSourceEndOffset ?? sourceRangeStartOffset;
      final startLine = _safeLineAtOffset(newController, rangeStartOffset);
      final endLine = _safeLineAtOffset(newController, rangeEndOffset);
      final sourceStartLine = _safeLineAtOffset(
        oldController,
        sourceRangeStartOffset,
      );
      final sourceEndLine = _safeLineAtOffset(
        oldController,
        sourceRangeEndOffset,
      );
      final afterLine = hasDelete ? (startLine > 0 ? startLine - 1 : 0) : null;

      hunks.add(
        EditHunk(
          id: 'hunk-$ts-${idx++}',
          type: type,
          startLine: startLine,
          endLine: endLine,
          sourceStartLine: sourceStartLine,
          sourceEndLine: sourceEndLine,
          oldText: oldText.toString(),
          newText: newText.toString(),
          afterLine: afterLine,
          addedText: addedOnlyText.isEmpty ? null : addedOnlyText.toString(),
          removedText: removedOnlyText.isEmpty
              ? null
              : removedOnlyText.toString(),
        ),
      );
    }

    return hunks;
  }

  ({
    List<(int startLine, int endLine)> addedRanges,
    List<(int startLine, int endLine)> modifiedRanges,
    List<({int afterLine, String content})> removedRanges,
  })
  toDecorationRanges() {
    final addedRanges = <(int, int)>[];
    final modifiedRanges = <(int, int)>[];
    final removedRanges = <({int afterLine, String content})>[];

    String extractOldLines(EditHunk hunk) {
      if (oldText.isEmpty) return '';
      final lines = oldText.split('\n');
      if (lines.isEmpty) return '';
      final safeStart = hunk.sourceStartLine.clamp(0, lines.length - 1);
      final safeEnd = hunk.sourceEndLine.clamp(safeStart, lines.length - 1);
      return lines.sublist(safeStart, safeEnd + 1).join('\n');
    }

    for (final hunk in editHunks) {
      if (hunk.type == 'added') {
        addedRanges.add((hunk.startLine, hunk.endLine));
        continue;
      }

      if (hunk.type == 'modified') {
        modifiedRanges.add((hunk.startLine, hunk.endLine));
        final removed = extractOldLines(hunk);
        if (removed.isNotEmpty) {
          removedRanges.add((
            afterLine:
                hunk.afterLine ?? (hunk.startLine > 0 ? hunk.startLine - 1 : 0),
            content: removed,
          ));
        }
        continue;
      }

      if (hunk.type == 'removed') {
        final removed = extractOldLines(hunk);
        removedRanges.add((
          afterLine:
              hunk.afterLine ?? (hunk.startLine > 0 ? hunk.startLine - 1 : 0),
          content: removed.isNotEmpty
              ? removed
              : (hunk.removedText ?? hunk.oldText),
        ));
      }
    }

    return (
      addedRanges: addedRanges,
      modifiedRanges: modifiedRanges,
      removedRanges: removedRanges,
    );
  }

  void applyDecorations(
    CodeForgeController controller, {
    Color addedColor = const Color(0xFF4CAF50),
    Color removedColor = const Color(0xFFE53935),
    Color modifiedColor = const Color(0xFF4CAF50),
  }) {
    final ranges = toDecorationRanges();
    if (editHunks.isEmpty) {
      controller.clearGitDiffDecorations();
      return;
    }
    controller.setGitDiffDecorations(
      addedRanges: ranges.addedRanges,
      modifiedRanges: ranges.modifiedRanges,
      removedRanges: ranges.removedRanges,
      addedColor: addedColor,
      removedColor: removedColor,
      modifiedColor: modifiedColor,
    );
  }

  static Map<String, dynamic> _decodePrefs(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return {};
    }
    return {};
  }

  static PendingEditFile? _parseFileEntry(dynamic rawEntry) {
    try {
      if (rawEntry is Map<String, dynamic>) {
        return PendingEditFile.fromJson(rawEntry);
      }
      if (rawEntry is Map) {
        return PendingEditFile.fromJson(Map<String, dynamic>.from(rawEntry));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedContent = _decodePrefs(prefs.getString(_prefsKey));
    final existing = _parseFileEntry(savedContent[filePath]);
    final merged = existing == null
        ? this
        : PendingEditFile(
            filePath: filePath,
            oldText: existing.oldText,
            editHunks: [...existing.editHunks, ...editHunks],
          );
    savedContent[filePath] = merged.toJson();
    await prefs.setString(_prefsKey, jsonEncode(savedContent));
  }

  static Future<void> upsert(PendingEditFile pendingEditFile) async {
    final prefs = await SharedPreferences.getInstance();
    final savedContent = _decodePrefs(prefs.getString(_prefsKey));
    savedContent[pendingEditFile.filePath] = pendingEditFile.toJson();
    await prefs.setString(_prefsKey, jsonEncode(savedContent));
  }

  static Future<PendingEditFile?> getForFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final savedContent = _decodePrefs(prefs.getString(_prefsKey));
    return _parseFileEntry(savedContent[filePath]);
  }

  static Future<Map<String, PendingEditFile>> getAllFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedContent = _decodePrefs(prefs.getString(_prefsKey));
    final result = <String, PendingEditFile>{};
    for (final entry in savedContent.entries) {
      final parsed = _parseFileEntry(entry.value);
      if (parsed != null) {
        result[entry.key] = parsed;
      }
    }
    return result;
  }

  static Future<void> removeFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final savedContent = _decodePrefs(prefs.getString(_prefsKey));
    savedContent.remove(filePath);
    await prefs.setString(_prefsKey, jsonEncode(savedContent));
  }

  static Future<void> removeHunk(String filePath, String hunkId) async {
    final pending = await getForFile(filePath);
    if (pending == null) return;

    final updated = pending.editHunks.where((h) => h.id != hunkId).toList();
    if (updated.isEmpty) {
      await removeFile(filePath);
      return;
    }

    await upsert(pending.copyWith(editHunks: updated));
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode({}));
  }

  static Future<Map<String, dynamic>> getFromPref() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodePrefs(prefs.getString(_prefsKey));
  }
}

sealed class SSHInfo {
  final String url, name;
  final int id;

  SSHInfo({
    required this.id,
    required this.url,
    required this.name
  });

  SSHClient? get client;
  bool get isConnected;

  Uri get uri => Uri.parse(url);
  String get username => uri.userInfo.split(':').first;
  String get host => uri.host;
  int get port => uri.port == 0 ? 22 : uri.port;

  factory SSHInfo.fromJsonMap(Map<String, dynamic> jsonMap){
    switch (jsonMap["login"]) {
      case true: return SSHLogin.fromJsonMap(jsonMap);
      case false: return SSHPrivateKey.fromJsonMap(jsonMap);
      default: throw Exception('Invalid SSH type');
    }
  }

  Map<String, dynamic> toJsonMap();

  Future<(bool, String)> connect();
  void disconnect();

  static Future<List<SSHInfo>> getSavedSSHServers() async{
    final prefs = await SharedPreferences.getInstance();
    final serverList = (jsonDecode(prefs.getString('sshServerList') ?? '[]') as List).cast<Map<String, dynamic>>();
    return serverList.map(SSHInfo.fromJsonMap).toList();
  }

  @override
  bool operator ==(Object other) {
    return other is SSHInfo && other.id == id;
  }
  
  @override int get hashCode => id;
}

