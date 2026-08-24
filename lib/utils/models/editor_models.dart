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

// Core models: ActiveEditor, CodeForgeDemoKey, AIConversation, etc.
// Extracted from functions.dart

class ActiveEditor {
  final File file;
  final CodeForgeController controller;
  final Language languageDetails;
  final UndoRedoController undoRedoController;
  final ScrollController hscroll, vscroll;
  bool isActive;
  FindController? findController;
  String? customTitle;

  ActiveEditor({
    required this.file,
    required this.controller,
    required this.languageDetails,
    required this.undoRedoController,
    required this.hscroll,
    required this.vscroll,
    required this.isActive,
    this.findController,
    this.customTitle,
  });

  Map<String, dynamic> toJsonMap() {
    final json = {
      "file": file.path,
      "text": controller.text,
      "extentOffset": controller.selection.extentOffset,
      "baseOffset": controller.selection.baseOffset,
      "customTitle": customTitle,
      "isActive": isActive,
      "lang": languageDetails.name,
    };

    return json;
  }

  @override
  String toString() => toJsonMap().toString();

  Future<void> dispose() async {
    try {
      final lspConfig = controller.lspConfig;
      if (lspConfig != null) {
        await lspConfig.closeDocument(file.path);
      }
    } catch (e) {
      debugPrint('Error closing LSP document: $e');
    }
  }
}

class CodeForgeDemoKey {
  final bool indentLineStatus, lineWrap, enableFolding, isDark;
  final String theme, fontFamily;

  CodeForgeDemoKey({
    required this.indentLineStatus,
    required this.lineWrap,
    required this.enableFolding,
    required this.theme,
    required this.fontFamily,
    required this.isDark,
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
      other is CodeForgeDemoKey &&
        runtimeType == other.runtimeType &&
        indentLineStatus == other.indentLineStatus &&
        lineWrap == other.lineWrap &&
        enableFolding == other.enableFolding &&
        theme == other.theme &&
        fontFamily == other.fontFamily &&
        isDark == other.isDark;
  }

  @override
  int get hashCode => Object.hash(
    indentLineStatus,
    lineWrap,
    enableFolding,
    theme,
    fontFamily,
    isDark,
  );
}

class AIConversation {
  final String userRequest;
  String? modelResponse;

  AIConversation(this.userRequest, this.modelResponse);

  AIConversation copyWith({String? modelResponse}) =>
      AIConversation(userRequest, modelResponse);

  Map<String, dynamic> toJson() => {
    'userRequest': userRequest,
    'modelResponse': modelResponse,
  };

  factory AIConversation.fromJson(Map<String, dynamic> json) => AIConversation(
    json['userRequest'] as String,
    json['modelResponse'] as String?,
  );
}

class ChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final List<AIConversation> conversations;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.conversations,
  });

  ChatSession copyWith({String? title, List<AIConversation>? conversations}) =>
      ChatSession(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        conversations: conversations ?? this.conversations,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'conversations': conversations.map((c) => c.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'] as String,
    title: json['title'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    conversations: (json['conversations'] as List)
        .map((c) => AIConversation.fromJson(c as Map<String, dynamic>))
        .toList(),
  );
}

class CommitNode {
  final String hash;
  final List<String> parents;
  final String author;
  final String message;
  final String date;
  int lane;
  int? childLane;
  bool isMerge;
  bool isBranchStart;
  bool isHead;
  bool isRemoteHead;

  CommitNode({
    required this.hash,
    required this.parents,
    required this.author,
    required this.message,
    this.date = '',
    this.lane = -1,
    this.childLane,
    this.isMerge = false,
    this.isBranchStart = false,
    this.isHead = false,
    this.isRemoteHead = false,
  });
}

class GraphLine {
  final int fromLane;
  final int toLane;
  final int colorIndex;
  final bool isPassThrough;

  GraphLine({
    required this.fromLane,
    required this.toLane,
    required this.colorIndex,
    this.isPassThrough = false,
  });
}

class CommitRowInfo {
  final CommitNode commit;
  final List<GraphLine> lines;
  final int commitLane;
  final int colorIndex;

  CommitRowInfo({
    required this.commit,
    required this.lines,
    required this.commitLane,
    required this.colorIndex,
  });
}

List<CommitRowInfo> assignVSCodeLanes(List<CommitNode> commits) {
  if (commits.isEmpty) return [];

  final List<CommitRowInfo> rowInfos = [];

  final Map<String, int> hashToIndex = {};
  for (int i = 0; i < commits.length; i++) {
    hashToIndex[commits[i].hash] = i;
  }

  final Map<int, (String, int)> activeLanes = {};
  final Map<String, int> hashToLane = {};
  final Map<String, int> hashToColor = {};
  int nextColorIndex = 0;

  int findAvailableLane(int preferredLane) {
    if (!activeLanes.containsKey(preferredLane)) {
      return preferredLane;
    }
    int lane = 0;
    while (activeLanes.containsKey(lane)) {
      lane++;
    }
    return lane;
  }

  for (int i = 0; i < commits.length; i++) {
    final commit = commits[i];
    commit.isMerge = commit.parents.length > 1;

    final List<GraphLine> lines = [];
    int commitLane;
    int colorIndex;

    int? expectedLane;
    int? expectedColor;
    for (final entry in activeLanes.entries) {
      if (entry.value.$1 == commit.hash) {
        expectedLane = entry.key;
        expectedColor = entry.value.$2;
        break;
      }
    }

    if (expectedLane != null) {
      commitLane = expectedLane;
      colorIndex = expectedColor!;
      activeLanes.remove(expectedLane);
    } else {
      commitLane = findAvailableLane(0);
      colorIndex = nextColorIndex++;
      commit.isBranchStart = i > 0;
    }

    commit.lane = commitLane;
    hashToLane[commit.hash] = commitLane;
    hashToColor[commit.hash] = colorIndex;

    for (final entry in activeLanes.entries) {
      lines.add(
        GraphLine(
          fromLane: entry.key,
          toLane: entry.key,
          colorIndex: entry.value.$2,
          isPassThrough: true,
        ),
      );
    }

    for (int p = 0; p < commit.parents.length; p++) {
      final parentHash = commit.parents[p];
      int? existingParentLane;
      int? existingParentColor;
      for (final entry in activeLanes.entries) {
        if (entry.value.$1 == parentHash) {
          existingParentLane = entry.key;
          existingParentColor = entry.value.$2;
          break;
        }
      }

      int parentLane;
      int parentColor;

      if (existingParentLane != null) {
        parentLane = existingParentLane;
        parentColor = existingParentColor!;
        final hasDiagonal = parentLane != commitLane;
        final edgeColor = hasDiagonal
            ? (commit.isMerge && p > 0 ? parentColor : colorIndex)
            : parentColor;
        lines.add(
          GraphLine(
            fromLane: commitLane,
            toLane: parentLane,
            colorIndex: edgeColor,
          ),
        );
      } else {
        if (p == 0) {
          parentLane = commitLane;
          parentColor = colorIndex;
        } else {
          parentLane = findAvailableLane(commitLane + 1);
          parentColor = nextColorIndex++;
        }

        activeLanes[parentLane] = (parentHash, parentColor);
        hashToColor[parentHash] = parentColor;

        lines.add(
          GraphLine(
            fromLane: commitLane,
            toLane: parentLane,
            colorIndex: parentColor,
          ),
        );
      }
    }

    rowInfos.add(
      CommitRowInfo(
        commit: commit,
        lines: lines,
        commitLane: commitLane,
        colorIndex: colorIndex,
      ),
    );
  }

  return rowInfos;
}

Map<String, (String, Color)> gitFileStatus = {
  "M": ('M', Color(0xffaf9672)),
  "D": ('D', Colors.red[300]!),
  "UU": ('C', Colors.red[300]!),
  "??": ('U', Colors.green[700]!),
  "A": ('U', Colors.green[700]!),
};

