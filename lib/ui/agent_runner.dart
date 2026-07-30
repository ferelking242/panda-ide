/// AgentRunner — streaming AI runner pour Panda Agent.
///
/// Supporte tous les providers existants (Gemini, OpenAI, Claude, OpenAI-compat,
/// LocalLlama) ainsi que les états "thinking" (Claude extended thinking,
/// o1/o3 reasoning_content, Gemini thinking models).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/ai.dart';

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
  Stream<AgentChunk> run({
    required Models model,
    required List<Map<String, dynamic>> messages,
    String? systemPromptOverride,
  }) {
    final ctrl = StreamController<AgentChunk>();
    _run(
      model: model,
      messages: messages,
      systemPrompt: systemPromptOverride ?? _systemPrompt,
      ctrl: ctrl,
    );
    return ctrl.stream;
  }

  Future<void> _run({
    required Models model,
    required List<Map<String, dynamic>> messages,
    required String systemPrompt,
    required StreamController<AgentChunk> ctrl,
  }) async {
    _client = http.Client();
    try {
      if (model is Gemini) {
        await _runGemini(model, messages, systemPrompt, ctrl);
      } else if (model is LocalLlama) {
        ctrl.add(const AgentChunk(
          phase: AgentPhase.error,
          text: 'LocalLlama n\'est pas supporté en mode agent pour l\'instant.',
        ));
      } else {
        await _runSse(model, messages, systemPrompt, ctrl);
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

  // ── Gemini (pas de SSE, réponse JSON directe) ─────────────────────────────
  Future<void> _runGemini(
    Gemini model,
    List<Map<String, dynamic>> messages,
    String systemPrompt,
    StreamController<AgentChunk> ctrl,
  ) async {
    final allMessages = [
      {'role': 'system', 'content': systemPrompt},
      ...messages,
    ];
    final body = model.buildToolCallingRequest(
      messages: allMessages,
      tools: [],
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
    // Cherche d'abord les blocs "thought" (Gemini thinking models)
    final parts = decoded['candidates']?[0]?['content']?['parts'];
    if (parts is List) {
      for (final part in parts) {
        final thought = part['thought'];
        if (thought == true) {
          final t = part['text']?.toString() ?? '';
          if (t.isNotEmpty) ctrl.add(AgentChunk(phase: AgentPhase.thinking, text: t));
        } else {
          final t = part['text']?.toString() ?? '';
          if (t.isNotEmpty) ctrl.add(AgentChunk(phase: AgentPhase.streaming, text: t));
        }
      }
    } else {
      final text = decoded['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
      if (text.toString().isNotEmpty) {
        ctrl.add(AgentChunk(phase: AgentPhase.streaming, text: text.toString()));
      }
    }
  }

  // ── SSE streaming (OpenAI-compat + Anthropic) ─────────────────────────────
  Future<void> _runSse(
    Models model,
    List<Map<String, dynamic>> messages,
    String systemPrompt,
    StreamController<AgentChunk> ctrl,
  ) async {
    final allMessages = [
      {'role': 'system', 'content': systemPrompt},
      ...messages,
    ];

    final body = model.buildToolCallingRequest(
      messages: allMessages,
      tools: [],
      stream: true,
    );

    // Pour Claude extended thinking, ajouter le champ thinking si le modèle
    // supporte claude-3-7 / claude-opus-4 etc.
    Map<String, dynamic> finalBody = Map.from(body);
    Map<String, String> finalHeaders = Map.from(model.headers);
    if (model is Claude) {
      final modelId = model.model.toLowerCase();
      if (modelId.contains('claude-3-7') ||
          modelId.contains('claude-opus-4') ||
          modelId.contains('claude-sonnet-4')) {
        finalBody['thinking'] = {'type': 'enabled', 'budget_tokens': 8000};
        finalHeaders['anthropic-beta'] = 'interleaved-thinking-2025-05-14';
      }
    }

    final req = http.Request('POST', Uri.parse(model.chatUrl));
    req.headers.addAll(finalHeaders);
    req.body = jsonEncode(finalBody);

    final streamed = await _client!.send(req);

    if (streamed.statusCode >= 400) {
      final body2 = await streamed.stream.bytesToString();
      ctrl.add(AgentChunk(
        phase: AgentPhase.error,
        text: 'HTTP ${streamed.statusCode}: $body2',
      ));
      return;
    }

    final lineBuffer = StringBuffer();

    await for (final bytes in streamed.stream) {
      if (ctrl.isClosed) break;
      final raw = utf8.decode(bytes, allowMalformed: true);
      lineBuffer.write(raw);

      final full = lineBuffer.toString();
      final lines = full.split('\n');
      lineBuffer.clear();
      // Garde la dernière ligne incomplète dans le buffer
      if (!full.endsWith('\n')) {
        lineBuffer.write(lines.removeLast());
      } else {
        lines.removeLast(); // ligne vide finale
      }

      for (final line in lines) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final data = trimmed.substring(5).trim();
        if (data == '[DONE]' || data.isEmpty) continue;

        Map<String, dynamic> obj;
        try {
          obj = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }

        _parseChunk(obj, ctrl);
      }
    }
  }

  void _parseChunk(Map<String, dynamic> obj, StreamController<AgentChunk> ctrl) {
    // ── OpenAI-compatible ────────────────────────────────────────────────────
    final choices = obj['choices'];
    if (choices is List && choices.isNotEmpty) {
      final delta = choices[0]['delta'];
      if (delta is Map) {
        // Texte standard
        final content = delta['content'];
        if (content is String && content.isNotEmpty) {
          ctrl.add(AgentChunk(phase: AgentPhase.streaming, text: content));
        }
        // Reasoning (o1 / o3 / DeepSeek-R1)
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
