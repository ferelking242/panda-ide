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
import '../utils/panda_log.dart';

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
    final shouldUseTools = context != null && _shouldUseTools(messages);
    final agenticTools = shouldUseTools
        ? AgenticTools(workspacePath: workspacePath, context: context)
        : null;
    PandaLog.i('AgentRunner', 'Starting run — provider=${model.runtimeType} tools=${agenticTools != null}');
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
      PandaLog.e('AgentRunner', 'Uncaught error in _run', error: e);
      if (!ctrl.isClosed) {
        ctrl.add(AgentChunk(phase: AgentPhase.error, text: e.toString()));
      }
    } finally {
      _client?.close();
      _client = null;
      PandaLog.d('AgentRunner', 'Run complete');
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

      PandaLog.httpRequest('Gemini', 'POST', model.url,
          body: 'turn=$turn messages=${conversationMessages.length} tools=${toolSchemas.length}');

      final resp = await _client!.post(
        Uri.parse(model.url),
        headers: model.headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 90), onTimeout: () {
        throw TimeoutException('La requête Gemini a dépassé 90 secondes.');
      });

      PandaLog.httpResponse('Gemini', resp.statusCode, model.url, body: resp.body);

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
        'role': 'assistant',
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
        PandaLog.toolCall('Gemini', name, args);

        final result = await _dispatchTool(tools, name, args)
            .timeout(const Duration(seconds: 45), onTimeout: () {
          PandaLog.w('Gemini', 'Tool $name timed out after 45 s');
          return 'Error: tool $name exceeded 45 s timeout';
        });
        PandaLog.toolResult('Gemini', name, result);
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
      // NOTE: use chatUrl (not url) — for OpenAI, url→/v1/responses,
      //       chatUrl→/v1/chat/completions (correct Chat Completions format).
      if (toolSchemas.isEmpty) {
        final chatUrl = model.chatUrl;
        PandaLog.httpRequest('SSE', 'POST', chatUrl,
            body: 'turn=$turn messages=${conversationMessages.length} stream=true');
        final req = http.Request('POST', Uri.parse(chatUrl))
          ..headers.addAll(model.headers)
          ..body = jsonEncode(body);
        final streamed = await _client!.send(req).timeout(const Duration(seconds: 90), onTimeout: () {
          throw TimeoutException('La connexion SSE a dépassé 90 secondes.');
        });

        if (streamed.statusCode != 200) {
          final body = await streamed.stream.bytesToString();
          PandaLog.e('SSE', 'HTTP ${streamed.statusCode} from $chatUrl', body: body);
          ctrl.add(AgentChunk(
            phase: AgentPhase.error,
            text: 'HTTP ${streamed.statusCode}: $body',
          ));
          return;
        }

        int chunkCount = 0;
        final lines = streamed.stream
            .transform(const Utf8Decoder())
            .transform(const LineSplitter())
            // Per-event timeout: abort if the server stops sending for 60 s
            .timeout(
              const Duration(seconds: 60),
              onTimeout: (sink) {
                PandaLog.w('SSE', 'Per-event timeout reached (60 s) — surfacing error');
                sink.addError(TimeoutException('Le modèle n’a pas répondu dans le délai imparti.'));
                sink.close();
              },
            );
        final startMs = DateTime.now().millisecondsSinceEpoch;
        await for (final line in lines) {
          if (ctrl.isClosed) break;
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trim();
          if (data == '[DONE]') break;
          if (data.isEmpty) continue;
          Map<String, dynamic> obj;
          try {
            obj = jsonDecode(data) as Map<String, dynamic>;
          } catch (parseErr) {
            PandaLog.w('SSE', 'Failed to parse chunk: $parseErr', body: data);
            continue;
          }
          chunkCount++;
          _parseChunk(obj, ctrl);
        }
        final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
        if (chunkCount == 0) {
          PandaLog.w('SSE', 'Stream ended with ZERO chunks in ${elapsed}ms — possible silent auth error or empty response');
        } else {
          PandaLog.d('SSE', 'Stream done — $chunkCount chunks in ${elapsed}ms');
        }
        return;
      }

      // Non-streaming for tool calling
      // NOTE: use chatUrl — same reason as above.
      final chatUrl = model.chatUrl;
      PandaLog.httpRequest('SSE', 'POST', chatUrl,
          body: 'turn=$turn messages=${conversationMessages.length} tools=${toolSchemas.length} stream=false');
      final resp = await _client!.post(
        Uri.parse(chatUrl),
        headers: model.headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 90), onTimeout: () {
        throw TimeoutException('La requête tool-calling a dépassé 90 secondes.');
      });

      PandaLog.httpResponse('SSE', resp.statusCode, chatUrl, body: resp.body);

      if (resp.statusCode >= 400) {
        ctrl.add(AgentChunk(
          phase: AgentPhase.error,
          text: 'HTTP ${resp.statusCode}: ${resp.body}',
        ));
        return;
      }

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final reasoningText = _extractNonStreamingReasoning(decoded);
      if (reasoningText.isNotEmpty) {
        ctrl.add(AgentChunk(
          phase: AgentPhase.thinking,
          text: reasoningText,
        ));
        PandaLog.d(
          'AgentRunner',
          'Non-stream reasoning received (${reasoningText.length} chars)',
        );
      }
      final assistantText = model.parseChatMessage(decoded);
      final toolCalls = model.parseToolCalls(decoded);
      PandaLog.d('SSE', 'Parsed response — text=${assistantText.length} chars toolCalls=${toolCalls.length}');

      if (assistantText.isNotEmpty) {
        ctrl.add(AgentChunk(phase: AgentPhase.streaming, text: assistantText));
      } else {
        final fallbackChunks = parseSsePayload(decoded);
        if (fallbackChunks.isNotEmpty) {
          for (final chunk in fallbackChunks) {
            ctrl.add(chunk);
          }
        } else if (tools == null || toolCalls.isEmpty) {
          ctrl.add(const AgentChunk(
            phase: AgentPhase.error,
            text: 'Le modèle n’a renvoyé aucun contenu exploitable.',
          ));
          return;
        }
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
        PandaLog.toolCall('SSE', functionName, args);
        final result = await _dispatchTool(tools, functionName, args)
            .timeout(const Duration(seconds: 45), onTimeout: () {
          PandaLog.w('SSE', 'Tool $functionName timed out after 45 s');
          return 'Error: tool $functionName exceeded 45 s timeout';
        });
        PandaLog.toolResult('SSE', functionName, result);
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
          final res = await tools.runShellCommand(args['command'], parsedArgs, parsedEnvs);
          return res.success ? jsonEncode(res.data) : (res.error ?? 'Error running command');
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

  bool _shouldUseTools(List<Map<String, dynamic>> messages) {
    final latestUser = messages.lastWhere(
      (message) => (message['role']?.toString() ?? '') == 'user',
      orElse: () => <String, dynamic>{},
    );
    final text = latestUser['content']?.toString() ?? '';
    if (text.trim().isEmpty || text.trim().length < 8) {
      return false;
    }

    final lowered = text.toLowerCase();
    final actionTerms = [
      'create', 'edit', 'write', 'read', 'search', 'find', 'open', 'run', 'clone', 'delete',
      'rename', 'install', 'fix', 'build', 'analyze', 'summarize', 'debug', 'test', 'update',
      'generate', 'list', 'inspect', 'compare', 'explain', 'help', 'implement',
    ];
    return actionTerms.any(lowered.contains);
  }

  static List<AgentChunk> parseSsePayload(Map<String, dynamic> payload) {
    final chunks = <AgentChunk>[];

    final choices = payload['choices'];
    if (choices is List && choices.isNotEmpty) {
      for (final entry in choices) {
        if (entry is! Map) continue;
        final delta = entry['delta'];
        if (delta is Map) {
          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            chunks.add(AgentChunk(phase: AgentPhase.streaming, text: content));
          } else if (content is List) {
            for (final item in content) {
              if (item is String && item.isNotEmpty) {
                chunks.add(AgentChunk(phase: AgentPhase.streaming, text: item));
              } else if (item is Map) {
                final text = item['text']?.toString();
                if (text != null && text.isNotEmpty) {
                  chunks.add(AgentChunk(phase: AgentPhase.streaming, text: text));
                }
              }
            }
          }

          final reasoning = delta['reasoning_content'] ?? delta['reasoning'] ?? delta['thinking'];
          if (reasoning is String && reasoning.isNotEmpty) {
            chunks.add(AgentChunk(phase: AgentPhase.thinking, text: reasoning));
          }
        }

        final message = entry['message'];
        if (message is Map) {
          final content = message['content'];
          if (content is String && content.isNotEmpty) {
            chunks.add(AgentChunk(phase: AgentPhase.streaming, text: content));
          } else if (content is List) {
            for (final item in content) {
              if (item is String && item.isNotEmpty) {
                chunks.add(AgentChunk(phase: AgentPhase.streaming, text: item));
              } else if (item is Map) {
                final text = item['text']?.toString();
                if (text != null && text.isNotEmpty) {
                  chunks.add(AgentChunk(phase: AgentPhase.streaming, text: text));
                }
              }
            }
          }
        }
      }
      return chunks;
    }

    final output = payload['output'];
    if (output is List) {
      for (final item in output) {
        if (item is! Map) continue;
        final content = item['content'];
        if (content is List) {
          for (final part in content) {
            if (part is Map) {
              final text = part['text']?.toString();
              if (text != null && text.isNotEmpty) {
                chunks.add(AgentChunk(phase: AgentPhase.streaming, text: text));
              }
            }
          }
        }
      }
      if (chunks.isNotEmpty) return chunks;
    }

    final content = payload['content'];
    if (content is String && content.isNotEmpty) {
      chunks.add(AgentChunk(phase: AgentPhase.streaming, text: content));
      return chunks;
    }
    if (content is List) {
      for (final item in content) {
        if (item is Map) {
          final text = item['text']?.toString();
          if (text != null && text.isNotEmpty) {
            chunks.add(AgentChunk(phase: AgentPhase.streaming, text: text));
          }
        } else if (item is String && item.isNotEmpty) {
          chunks.add(AgentChunk(phase: AgentPhase.streaming, text: item));
        }
      }
    }

    final type = payload['type']?.toString() ?? '';
    if (type == 'content_block_delta') {
      final dt = payload['delta'];
      if (dt is Map) {
        final dtType = dt['type']?.toString() ?? '';
        if (dtType == 'text_delta') {
          final t = dt['text']?.toString() ?? '';
          if (t.isNotEmpty) chunks.add(AgentChunk(phase: AgentPhase.streaming, text: t));
        } else if (dtType == 'thinking_delta') {
          final t = dt['thinking']?.toString() ?? '';
          if (t.isNotEmpty) chunks.add(AgentChunk(phase: AgentPhase.thinking, text: t));
        }
      }
    }

    return chunks;
  }

  void _parseChunk(Map<String, dynamic> obj, StreamController<AgentChunk> ctrl) {
    final parsed = parseSsePayload(obj);
    if (parsed.isEmpty) return;
    for (final chunk in parsed) {
      ctrl.add(chunk);
    }
  }

  /// Extract provider-specific reasoning from a non-streaming response.
  ///
  /// Tool-calling requests intentionally use `stream: false`, so reasoning
  /// does not pass through the SSE parser. Providers place it under different
  /// keys (`reasoning_content`, `reasoning`, `thinking`, or `thought`).
  String _extractNonStreamingReasoning(Map<String, dynamic> payload) {
    final parts = <String>[];

    void visit(dynamic value) {
      if (value is List) {
        for (final item in value) {
          visit(item);
        }
        return;
      }
      if (value is! Map) return;

      for (final entry in value.entries) {
        final key = entry.key.toString();
        final child = entry.value;
        final isReasoningKey = key == 'reasoning_content' ||
            key == 'reasoning' ||
            key == 'thinking' ||
            key == 'thought';

        if (isReasoningKey) {
          if (child is String && child.trim().isNotEmpty) {
            parts.add(child);
          } else if (child is Map || child is List) {
            visit(child);
          }
          continue;
        }

        // Walk response envelopes, but do not inspect ordinary text fields.
        if (child is Map || child is List) {
          visit(child);
        }
      }
    }

    visit(payload);
    return parts.join();
  }
}
