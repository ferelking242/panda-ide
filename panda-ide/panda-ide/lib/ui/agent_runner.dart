/// AgentRunner — streaming AI runner pour Panda Agent.
///
/// Supporte tous les providers existants (Gemini, OpenAI, Claude, OpenAI-compat,
/// LocalLlama) ainsi que les états "thinking" (Claude extended thinking,
/// o1/o3 reasoning_content, Gemini thinking models).
///
/// Supporte également le tool calling : quand un BuildContext et un workspacePath
/// sont fournis, l'agent peut exécuter des commandes shell, lire/écrire des fichiers, etc.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../utils/ai.dart';
import '../utils/agentic_tools.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AgentPhase — machine à états de l'agent
// ─────────────────────────────────────────────────────────────────────────────

enum AgentPhase {
  idle,       // en attente d'un message
  thinking,   // le modèle "réfléchit" (extended thinking / reasoning)
  streaming,  // texte en cours de génération
  done,       // réponse complète
  error,      // erreur réseau ou parsing
}

// ─────────────────────────────────────────────────────────────────────────────
// AgentChunk — unité émise par le stream
// ─────────────────────────────────────────────────────────────────────────────

class AgentChunk {
  final AgentPhase phase;
  final String text;
  const AgentChunk({required this.phase, this.text = ''});
}

// ─────────────────────────────────────────────────────────────────────────────
// AgentRunner
// ─────────────────────────────────────────────────────────────────────────────

class AgentRunner {
  http.Client? _client;

  static const String _systemPrompt =
      'You are Panda Agent, an expert coding assistant embedded in a mobile IDE. '
      'You have access to tools that let you read files, write files, run shell commands, '
      'search code, clone repositories, and more. '
      'When asked to perform tasks (clone a repo, create files, run commands), USE the tools — '
      'do not just describe what to do. '
      'Answer concisely, in the same language as the user. '
      'For code blocks use markdown fences. '
      'Do not repeat the question.';

  /// Annule la requête en cours (si elle existe).
  void cancel() {
    _client?.close();
    _client = null;
  }

  /// Lance une conversation avec [model] et renvoie un stream de [AgentChunk].
  ///
  /// [messages] doit être au format OpenAI : `[{'role':'user'|'assistant', 'content':'...'}]`.
  /// [context] et [workspacePath] sont optionnels mais requis pour le tool calling.
  Stream<AgentChunk> run({
    required Models model,
    required List<Map<String, dynamic>> messages,
    String? systemPromptOverride,
    BuildContext? context,
    String workspacePath = '',
  }) {
    final ctrl = StreamController<AgentChunk>();
    _run(
      model: model,
      messages: messages,
      systemPrompt: systemPromptOverride ?? _systemPrompt,
      ctrl: ctrl,
      context: context,
      workspacePath: workspacePath,
    );
    return ctrl.stream;
  }

  Future<void> _run({
    required Models model,
    required List<Map<String, dynamic>> messages,
    required String systemPrompt,
    required StreamController<AgentChunk> ctrl,
    BuildContext? context,
    String workspacePath = '',
  }) async {
    _client = http.Client();
    final agenticTools = (context != null)
        ? AgenticTools(workspacePath: workspacePath, context: context)
        : null;
    try {
      if (model is Gemini) {
        await _runGemini(model, messages, systemPrompt, ctrl, agenticTools);
      } else if (model is LocalLlama) {
        ctrl.add(const AgentChunk(
          phase: AgentPhase.error,
          text: 'LocalLlama n\'est pas supporté en mode agent pour l\'instant.',
        ));
      } else {
        await _runSse(model, messages, systemPrompt, ctrl, agenticTools);
      }
      ctrl.add(const AgentChunk(phase: AgentPhase.done));
    } catch (e) {
      if (!ctrl.isClosed) {
        ctrl.add(AgentChunk(phase: AgentPhase.error, text: e.toString()));
      }
    } finally {
      _client?.close();
      _client = null;
      await ctrl.close();
    }
  }

  // ── Gemini (réponse JSON directe + tool calling loop) ─────────────────────
  Future<void> _runGemini(
    Gemini model,
    List<Map<String, dynamic>> messages,
    String systemPrompt,
    StreamController<AgentChunk> ctrl,
    AgenticTools? tools,
  ) async {
    final toolSchemas = tools?.getTools() ?? [];
    final conversationMessages = [
      {'role': 'system', 'content': systemPrompt},
      ...messages,
    ];

    for (var turn = 0; turn < 12; turn++) {
      if (ctrl.isClosed) return;

      final body = model.buildToolCallingRequest(
        messages: conversationMessages,
        tools: toolSchemas,
        stream: false,
      );

      final resp = await _client!.post(
        Uri.parse(model.url),
        headers: model.headers,
        body: jsonEncode(body),
      );

      if (resp.statusCode >= 400) {
        ctrl.add(AgentChunk(
          phase: AgentPhase.error,
          text: 'HTTP ${resp.statusCode}: ${resp.body}',
        ));
        return;
      }

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final parts = decoded['candidates']?[0]?['content']?['parts'];

      if (parts is! List) {
        final text = decoded['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
        if (text.toString().isNotEmpty) {
          ctrl.add(AgentChunk(phase: AgentPhase.streaming, text: text.toString()));
        }
        return;
      }

      // Collect text/thinking parts and function calls
      String assistantText = '';
      final List<Map<String, dynamic>> functionCalls = [];

      for (final part in parts) {
        if (part['thought'] == true) {
          final t = part['text']?.toString() ?? '';
          if (t.isNotEmpty) ctrl.add(AgentChunk(phase: AgentPhase.thinking, text: t));
        } else if (part['functionCall'] != null) {
          functionCalls.add(Map<String, dynamic>.from(part['functionCall'] as Map));
        } else {
          final t = part['text']?.toString() ?? '';
          if (t.isNotEmpty) {
            assistantText += t;
            ctrl.add(AgentChunk(phase: AgentPhase.streaming, text: t));
          }
        }
      }

      // No tool calls → done
      if (functionCalls.isEmpty || tools == null) return;

      // Add assistant turn to conversation
      conversationMessages.add({
        'role': 'model',
        'content': assistantText,
        'tool_calls': functionCalls.map((fc) => {
          'id': fc['name'] ?? 'call_${turn}_${functionCalls.indexOf(fc)}',
          'type': 'function',
          'function': {
            'name': fc['name'],
            'arguments': jsonEncode(fc['args'] ?? {}),
          },
        }).toList(),
      });

      // Notify user that tools are being executed
      ctrl.add(AgentChunk(
        phase: AgentPhase.thinking,
        text: '\n🔧 Executing ${functionCalls.length} tool(s)...\n',
      ));

      // Execute each tool call
      final toolResults = <Map<String, dynamic>>[];
      for (final fc in functionCalls) {
        final name = fc['name']?.toString() ?? '';
        final args = (fc['args'] is Map)
            ? Map<String, dynamic>.from(fc['args'] as Map)
            : <String, dynamic>{};

        ctrl.add(AgentChunk(phase: AgentPhase.thinking, text: '→ $name\n'));

        final result = await _dispatchTool(tools, name, args);
        toolResults.add({
          'tool_call_id': name,
          'role': 'tool',
          'name': name,
          'content': result,
        });
      }

      // Add tool results to conversation
      conversationMessages.addAll(toolResults);
    }

    // Exceeded max turns
    ctrl.add(const AgentChunk(
      phase: AgentPhase.streaming,
      text: '\n⚠️ Reached maximum tool calling iterations.',
    ));
  }

  // ── SSE streaming (OpenAI-compat + Anthropic) + tool calling ─────────────
  Future<void> _runSse(
    Models model,
    List<Map<String, dynamic>> messages,
    String systemPrompt,
    StreamController<AgentChunk> ctrl,
    AgenticTools? tools,
  ) async {
    final toolSchemas = tools?.getTools() ?? [];
    final conversationMessages = [
      {'role': 'system', 'content': systemPrompt},
      ...messages,
    ];

    for (var turn = 0; turn < 12; turn++) {
      if (ctrl.isClosed) return;

      final body = model.buildToolCallingRequest(
        messages: conversationMessages,
        tools: toolSchemas,
        // For tool calling we need non-streaming to parse tool calls cleanly
        stream: toolSchemas.isEmpty,
      );

      // If streaming with no tools, use the old SSE path
      if (toolSchemas.isEmpty) {
        final req = http.Request('POST', Uri.parse(model.url))
          ..headers.addAll(model.headers)
          ..body = jsonEncode(body);
        final streamed = await _client!.send(req);
        final lines = streamed.stream
            .transform(const Utf8Decoder())
            .transform(const LineSplitter());
        await for (final line in lines) {
          if (ctrl.isClosed) break;
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trim();
          if (data == '[DONE]') break;
          if (data.isEmpty) continue;
          Map<String, dynamic> obj;
          try {
            obj = jsonDecode(data) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
          _parseChunk(obj, ctrl);
        }
        return;
      }

      // Non-streaming for tool calling
      final resp = await _client!.post(
        Uri.parse(model.url),
        headers: model.headers,
        body: jsonEncode(body),
      );

      if (resp.statusCode >= 400) {
        ctrl.add(AgentChunk(
          phase: AgentPhase.error,
          text: 'HTTP ${resp.statusCode}: ${resp.body}',
        ));
        return;
      }

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final assistantText = model.parseChatMessage(decoded);
      final toolCalls = model.parseToolCalls(decoded);

      if (assistantText.isNotEmpty) {
        ctrl.add(AgentChunk(phase: AgentPhase.streaming, text: assistantText));
      }

      if (toolCalls.isEmpty || tools == null) return;

      conversationMessages.add({
        'role': 'assistant',
        'content': assistantText,
        if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
      });

      ctrl.add(AgentChunk(
        phase: AgentPhase.thinking,
        text: '\n🔧 Executing ${toolCalls.length} tool(s)...\n',
      ));

      final toolResults = <String>[];
      for (final call in toolCalls) {
        final callFunction = call['function'];
        if (callFunction is! Map) {
          toolResults.add('Malformed tool call');
          continue;
        }
        final functionName = callFunction['name']?.toString() ?? '';
        final rawArgs = callFunction['arguments'];
        Map<String, dynamic> args = {};
        if (rawArgs is String && rawArgs.trim().isNotEmpty) {
          try {
            final parsed = jsonDecode(rawArgs);
            if (parsed is Map) args = Map<String, dynamic>.from(parsed);
          } catch (_) {}
        } else if (rawArgs is Map) {
          args = Map<String, dynamic>.from(rawArgs);
        }

        ctrl.add(AgentChunk(phase: AgentPhase.thinking, text: '→ $functionName\n'));
        final result = await _dispatchTool(tools, functionName, args);
        toolResults.add(result);
      }

      conversationMessages.addAll(
        model.buildToolResultMessages(toolCalls, toolResults),
      );
    }

    ctrl.add(const AgentChunk(
      phase: AgentPhase.streaming,
      text: '\n⚠️ Reached maximum tool calling iterations.',
    ));
  }

  // ── Tool dispatch ─────────────────────────────────────────────────────────
  Future<String> _dispatchTool(
    AgenticTools tools,
    String functionName,
    Map<String, dynamic> args,
  ) async {
    try {
      switch (functionName) {
        case 'activeEditorFile':
          final res = await tools.activeEditorFile();
          return res.success ? (res.data ?? 'No active file') : (res.error ?? 'Error');
        case 'currentlySelectedText':
          final res = await tools.currentlySelectedText();
          return res.success
              ? 'Start: ${res.data?['startLine']}, End: ${res.data?['endLine']}, Text: ${res.data?['selectedText'] ?? ''}'
              : (res.error ?? 'Error');
        case 'getLspDiagnostics':
          final res = await tools.getLspDiagnostics(args['filePath']);
          return res.success ? jsonEncode(res.data) : (res.error ?? 'Error');
        case 'readFile':
          final res = await tools.readFile(args['filePath'], args['startLine'], args['endLine']);
          return res.success ? (res.data ?? '') : (res.error ?? 'Error reading file');
        case 'writeFile':
          final res = await tools.writeFile(args['filePath'], args['content']);
          return res.success ? 'File written successfully' : (res.error ?? 'Error writing file');
        case 'deleteFile':
          final res = await tools.deleteFile(args['filePath']);
          return res.success ? 'File deleted successfully' : (res.error ?? 'Error deleting file');
        case 'renamePath':
          final res = await tools.renamePath(args['oldPath'], args['newPath']);
          return res.success ? 'Renamed successfully' : (res.error ?? 'Error renaming');
        case 'rename':
          final res = await tools.rename(args['oldPath'], args['newPath']);
          return res.success ? 'Renamed successfully' : (res.error ?? 'Error renaming');
        case 'insertAtLine':
          final res = await tools.insertAtLine(
            args['filePath'], args['line'], args['text'],
            position: args['position'] ?? 'before',
          );
          return res.success ? 'Text inserted successfully' : (res.error ?? 'Error inserting');
        case 'replaceAllInFile':
          final res = await tools.replaceAllInFile(
            args['filePath'], args['oldText'], args['newText'],
            useRegex: args['useRegex'] ?? false,
            maxReplacements: args['maxReplacements'],
            caseSensitive: args['caseSensitive'] ?? true,
          );
          return res.success ? jsonEncode(res.data) : (res.error ?? 'Error replacing');
        case 'listFiles':
          final res = await tools.listFiles(
            args['directoryPath'],
            pattern: args['pattern'],
            recursive: args['recursive'] ?? false,
          );
          return res.success ? (res.data?.join('\n') ?? 'No files') : (res.error ?? 'Error listing');
        case 'readFilesBatch':
          final res = await tools.readFilesBatch((args['files'] as List?) ?? []);
          return res.success ? jsonEncode(res.data) : (res.error ?? 'Error');
        case 'globSearchFiles':
          final res = await tools.globSearchFiles(
            args['pattern'],
            directoryPath: args['directoryPath'] ?? '.',
            excludePatterns: (args['excludePatterns'] as List?)?.map((e) => e.toString()).toList(),
            recursive: args['recursive'] ?? true,
            maxResults: args['maxResults'],
          );
          return res.success ? (res.data?.join('\n') ?? 'No matches') : (res.error ?? 'Error');
        case 'searchInFiles':
          final res = await tools.searchInFiles(
            args['query'],
            filePattern: args['filePattern'],
            caseSensitive: args['caseSensitive'] ?? false,
            matchWholeWord: args['matchWholeWord'] ?? false,
            useRegex: args['useRegex'] ?? false,
          );
          return res.success
              ? (res.data?.map((s) => '${s.filePath}:${s.lineNumber}: ${s.lineContent}').join('\n') ?? 'No results')
              : (res.error ?? 'Error');
        case 'grepInFiles':
          final res = await tools.grepInFiles(
            args['query'],
            filePattern: args['filePattern'],
            caseSensitive: args['caseSensitive'] ?? false,
            matchWholeWord: args['matchWholeWord'] ?? false,
            useRegex: args['useRegex'] ?? false,
            before: args['before'] ?? 2,
            after: args['after'] ?? 2,
            maxResults: args['maxResults'],
          );
          return res.success
              ? (res.data?.map((r) => r.toString()).join('\n') ?? 'No results')
              : (res.error ?? 'Error');
        case 'editFile':
          final res = await tools.editFile(args['filePath'], args['oldText'], args['newText']);
          return res.success ? 'File edited successfully' : (res.error ?? 'Error editing file');
        case 'getPendingEditsForFile':
          final res = await tools.getPendingEditsForFile(args['filePath']);
          return res.success
              ? (res.data == null ? 'No pending edits' : jsonEncode(res.data!.toJson()))
              : (res.error ?? 'Error');
        case 'getFileInfo':
          final res = await tools.getFileInfo(args['filePath']);
          return res.success
              ? 'Path: ${res.data?.path}, Size: ${res.data?.size}, Modified: ${res.data?.modified}, IsDir: ${res.data?.isDirectory}'
              : (res.error ?? 'Error');
        case 'openLinks':
          final res = await tools.openLinks(args['url']);
          return res.success ? (res.data?.toString() ?? '') : (res.error ?? 'Error');
        case 'searchInWeb':
          final res = await tools.searchInWeb(args['searchQuery']);
          return res.success
              ? (res.data?.map((w) => '${w.title}\n${w.url}\n${w.snippet}').join('\n---\n') ?? 'No results')
              : (res.error ?? 'Error');
        case 'runShellCommand':
          final parsedArgs = (args['args'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
          final parsedEnvs = (args['envs'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? <String, String>{};
          final timeout = (args['timeoutSeconds'] as num?)?.toInt() ?? 120;
          final res = await tools.runShellCommand(args['command'], parsedArgs, parsedEnvs, timeout);
          return res.success ? jsonEncode(res.data) : (res.error ?? 'Error running command');
        case 'fastSearch':
          final res = await tools.fastSearch(
            args['query']?.toString() ?? '',
            directoryPath: args['directoryPath']?.toString(),
            filePattern: args['filePattern']?.toString(),
            caseSensitive: args['caseSensitive'] ?? false,
            useRegex: args['useRegex'] ?? false,
            matchWholeWord: args['matchWholeWord'] ?? false,
            maxResults: (args['maxResults'] as num?)?.toInt() ?? 300,
          );
          return res.success
              ? (res.data?.map((s) => '${s.filePath}:${s.lineNumber}: ${s.lineContent}').join('\n') ?? 'No results')
              : (res.error ?? 'Error');
        case 'getProjectTree':
          final res = await tools.getProjectTree(
            directoryPath: args['directoryPath']?.toString(),
            maxDepth: (args['maxDepth'] as num?)?.toInt() ?? 4,
            maxEntries: (args['maxEntries'] as num?)?.toInt() ?? 500,
          );
          return res.success ? (res.data ?? '') : (res.error ?? 'Error');
        case 'getProjectStats':
          final res = await tools.getProjectStats(
            directoryPath: args['directoryPath']?.toString(),
          );
          return res.success ? jsonEncode(res.data) : (res.error ?? 'Error');
        case 'findSymbols':
          final res = await tools.findSymbols(
            args['symbolName']?.toString() ?? '',
            directoryPath: args['directoryPath']?.toString(),
            fileExtension: args['fileExtension']?.toString(),
            caseSensitive: args['caseSensitive'] ?? false,
            maxResults: (args['maxResults'] as num?)?.toInt() ?? 100,
          );
          return res.success
              ? jsonEncode(res.data)
              : (res.error ?? 'Error');
        case 'getFileOutline':
          final res = await tools.getFileOutline(args['filePath']?.toString() ?? '');
          return res.success ? jsonEncode(res.data) : (res.error ?? 'Error');
        case 'httpRequest':
          final hdrs = (args['headers'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString()));
          final res = await tools.httpRequest(
            args['url']?.toString() ?? '',
            method: args['method']?.toString() ?? 'GET',
            headers: hdrs,
            body: args['body']?.toString(),
          );
          return res.success ? jsonEncode(res.data) : (res.error ?? 'Error');
        case 'createDirectory':
          final res = await tools.createDirectory(args['dirPath']?.toString() ?? '');
          return res.success ? 'Directory created' : (res.error ?? 'Error');
        case 'copyFile':
          final res = await tools.copyFile(
            args['sourcePath']?.toString() ?? '',
            args['destPath']?.toString() ?? '',
          );
          return res.success ? 'File copied' : (res.error ?? 'Error');
        case 'keepAllPendingEdits':
          final res = await tools.keepAllPendingEditsForAgent(args['filePath']?.toString() ?? '');
          return res.success ? 'Pending edits accepted' : (res.error ?? 'Error');
        case 'rejectAllPendingEdits':
          final res = await tools.rejectAllPendingEditsForAgent(args['filePath']?.toString() ?? '');
          return res.success ? 'Pending edits rejected' : (res.error ?? 'Error');
        case 'gitStatus':
          final res = await tools.gitStatus();
          return res.success ? jsonEncode(res.data?.toJson()) : (res.error ?? 'Error');
        case 'gitDiff':
          final res = await tools.gitDiff(
            filePath: args['filePath'],
            staged: args['staged'] ?? false,
            contextLines: args['contextLines'] ?? 3,
          );
          return res.success ? (res.data ?? '') : (res.error ?? 'Error');
        case 'gitLog':
          final res = await tools.gitLog(limit: args['limit'] ?? 20, filePath: args['filePath']);
          return res.success
              ? jsonEncode(res.data?.map((c) => c.toJson()).toList() ?? [])
              : (res.error ?? 'Error');
        default:
          return 'Unknown tool: $functionName';
      }
    } catch (e) {
      return 'Error executing $functionName: $e';
    }
  }

  void _parseChunk(Map<String, dynamic> obj, StreamController<AgentChunk> ctrl) {
    // ── OpenAI-compatible ────────────────────────────────────────────────────
    final choices = obj['choices'];
    if (choices is List && choices.isNotEmpty) {
      final delta = choices[0]['delta'];
      if (delta is Map) {
        final content = delta['content'];
        if (content is String && content.isNotEmpty) {
          ctrl.add(AgentChunk(phase: AgentPhase.streaming, text: content));
        }
        final reasoning = delta['reasoning_content'] ?? delta['reasoning'] ?? delta['thinking'];
        if (reasoning is String && reasoning.isNotEmpty) {
          ctrl.add(AgentChunk(phase: AgentPhase.thinking, text: reasoning));
        }
      }
      return;
    }

    // ── Anthropic SSE ────────────────────────────────────────────────────────
    final type = obj['type']?.toString() ?? '';
    if (type == 'content_block_delta') {
      final dt = obj['delta'];
      if (dt is Map) {
        final dtType = dt['type']?.toString() ?? '';
        if (dtType == 'text_delta') {
          final t = dt['text']?.toString() ?? '';
          if (t.isNotEmpty) ctrl.add(AgentChunk(phase: AgentPhase.streaming, text: t));
        } else if (dtType == 'thinking_delta') {
          final t = dt['thinking']?.toString() ?? '';
          if (t.isNotEmpty) ctrl.add(AgentChunk(phase: AgentPhase.thinking, text: t));
        }
      }
    }
  }
}
