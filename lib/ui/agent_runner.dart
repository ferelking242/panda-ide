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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../utils/ai.dart';
import '../utils/agentic_tools.dart';
import '../utils/panda_log.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AgentPhase — machine à états de l'agent
// ─────────────────────────────────────────────────────────────────────────────

enum AgentPhase {
  idle,        // en attente d'un message
  thinking,    // le modèle "réfléchit" (extended thinking / reasoning)
  toolRunning, // un outil est en cours d'exécution
  toolDone,    // un outil vient de terminer (résultat disponible)
  streaming,   // texte en cours de génération
  done,        // réponse complète
  error,       // erreur réseau ou parsing
}

// ─────────────────────────────────────────────────────────────────────────────
// AgentChunk — unité émise par le stream
// ─────────────────────────────────────────────────────────────────────────────

class AgentChunk {
  final AgentPhase phase;
  final String text;
  /// Nom de l'outil (toolRunning / toolDone)
  final String? toolName;
  /// Arguments passés à l'outil (toolRunning)
  final Map<String, dynamic>? toolArgs;
  /// Résultat retourné par l'outil (toolDone)
  final String? toolResult;
  const AgentChunk({
    required this.phase,
    this.text = '',
    this.toolName,
    this.toolArgs,
    this.toolResult,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// AgentRunner
// ─────────────────────────────────────────────────────────────────────────────

class AgentRunner {
  http.Client? _client;

  /// Génère dynamiquement le system prompt à partir du contexte réel du projet.
  /// Appelé dans [_run] après que les toolSchemas sont connus.
  static String _buildSystemPrompt(
    String workspacePath,
    List<Map<String, dynamic>> toolSchemas,
  ) {
    // ── Détection du projet ────────────────────────────────────────────────
    final StringBuffer projectSection = StringBuffer();
    final StringBuffer repoSection   = StringBuffer();

    if (workspacePath.isNotEmpty) {
      final dir = Directory(workspacePath);
      if (dir.existsSync()) {
        final projectName = path.basename(workspacePath);

        // Détecter le type de projet
        String projectType = 'Inconnu';
        String extraCtx = '';
        if (File('$workspacePath/pubspec.yaml').existsSync()) {
          projectType = 'Flutter / Dart';
          extraCtx = 'Pour compiler : `flutter build apk`. Pour les tests : `flutter test`.';
        } else if (File('$workspacePath/package.json').existsSync()) {
          projectType = 'Node.js / TypeScript';
          extraCtx = 'Pour installer : `npm install`. Pour démarrer : `npm run dev`.';
        } else if (File('$workspacePath/Cargo.toml').existsSync()) {
          projectType = 'Rust';
          extraCtx = 'Pour compiler : `cargo build`. Pour les tests : `cargo test`.';
        } else if (File('$workspacePath/go.mod').existsSync()) {
          projectType = 'Go';
          extraCtx = 'Pour compiler : `go build ./...`. Pour les tests : `go test ./...`.';
        } else if (File('$workspacePath/pom.xml').existsSync() ||
                   File('$workspacePath/build.gradle').existsSync()) {
          projectType = 'Java / Android';
          extraCtx = 'Pour compiler : `./gradlew build`.';
        } else if (File('$workspacePath/requirements.txt').existsSync() ||
                   File('$workspacePath/pyproject.toml').existsSync()) {
          projectType = 'Python';
          extraCtx = 'Pour installer : `pip install -r requirements.txt`. Pour lancer : `python main.py`.';
        }

        projectSection
          ..writeln('## PROJET OUVERT')
          ..writeln('Nom : $projectName')
          ..writeln('Type : $projectType')
          ..writeln('Chemin : $workspacePath')
          ..writeln(extraCtx);

        // Carte du dépôt (top-level + 1 niveau)
        try {
          final entries = dir
              .listSync(followLinks: false)
              .where((e) {
                final n = path.basename(e.path);
                return !n.startsWith('.') &&
                    n != 'build' &&
                    n != '.dart_tool' &&
                    n != 'node_modules' &&
                    n != '__pycache__' &&
                    n != 'target';
              })
              .toList()
            ..sort((a, b) {
              // Dossiers d'abord, puis fichiers, puis tri alphabétique
              final aIsDir = a is Directory;
              final bIsDir = b is Directory;
              if (aIsDir && !bIsDir) return -1;
              if (!aIsDir && bIsDir) return 1;
              return path.basename(a.path).compareTo(path.basename(b.path));
            });

          repoSection.writeln('## STRUCTURE DU PROJET');
          repoSection.writeln('```');
          for (final entry in entries.take(25)) {
            final name = path.basename(entry.path);
            if (entry is Directory) {
              repoSection.writeln('📁 $name/');
              try {
                final subEntries = Directory(entry.path)
                    .listSync(followLinks: false)
                    .where((e) => !path.basename(e.path).startsWith('.'))
                    .toList()
                  ..sort((a, b) =>
                      path.basename(a.path).compareTo(path.basename(b.path)));
                for (final sub in subEntries.take(12)) {
                  final subName = path.basename(sub.path);
                  final icon = sub is Directory ? '📁' : '📄';
                  repoSection.writeln('   $icon $subName');
                }
                if (subEntries.length > 12) {
                  repoSection.writeln('   … (${subEntries.length - 12} autres)');
                }
              } catch (_) {}
            } else {
              repoSection.writeln('📄 $name');
            }
          }
          if (entries.length > 25) {
            repoSection.writeln('… (${entries.length - 25} autres entrées)');
          }
          repoSection.writeln('```');
        } catch (_) {}
      }
    }

    // ── Liste des outils avec descriptions ────────────────────────────────
    final toolLines = toolSchemas
        .map((t) {
          final fn = t['function'];
          if (fn is! Map) return null;
          final name = fn['name']?.toString() ?? '';
          final desc = fn['description']?.toString() ?? '';
          final params = fn['parameters'];
          final required = (params is Map)
              ? ((params['required'] as List?)?.join(', ') ?? '')
              : '';
          final suffix = required.isNotEmpty ? ' [requis: $required]' : '';
          return '  • **$name**$suffix — $desc';
        })
        .whereType<String>()
        .join('\n');

    // ── Assemblage final ───────────────────────────────────────────────────
    return '''
Tu es **Panda Agent**, un ingénieur logiciel senior d'élite intégré à Panda IDE.
Tu possèdes une expertise approfondie en nombreux langages de programmation, frameworks, patterns de conception et meilleures pratiques.
Tu es entièrement autonome : tu accèdes au système de fichiers, modifies du code, exécutes des commandes shell, gères des dépôts git — sans attendre la permission de l'utilisateur à chaque étape.

${projectSection.isNotEmpty ? projectSection.toString() : ''}
${repoSection.isNotEmpty ? repoSection.toString() : ''}
====

## UTILISATION DES OUTILS

Tu disposes d'un ensemble d'outils que tu dois utiliser pour accomplir les tâches.
Chaque appel d'outil est exécuté immédiatement et tu reçois son résultat avant de continuer.
Utilise **un outil à la fois**, de façon itérative — chaque appel étant informé par le résultat du précédent.

### Outils disponibles (${toolSchemas.length})
$toolLines

====

## RÈGLES ABSOLUES

1. **Agis, ne décris pas.** Si un outil peut accomplir quelque chose, appelle-le immédiatement. Interdiction d'écrire "Je vais lire…" ou "Je vais exécuter…" — exécute directement.

2. **readFile obligatoire avant editFile.** Sans aucune exception. Ne modifie jamais un fichier sans en avoir lu le contenu complet au préalable.

3. **N'invente jamais le contenu d'un fichier.** Contenu inconnu → readFile. Fichier introuvable → grepInFiles ou globSearchFiles d'abord.

4. **Enchaîne automatiquement.** Continue d'appeler des outils SANS demander la permission jusqu'à ce que la tâche soit 100 % achevée. Tu as jusqu'à 12 tours de tools par réponse — utilise-les tous si nécessaire.

5. **Résilience aux erreurs.** Si un outil retourne une erreur → analyse le message → réessaie différemment. N'abandonne jamais après un seul échec.

6. **Après runShellCommand** → lis la sortie complète. Si elle contient des erreurs ou des warnings critiques, corrige-les IMMÉDIATEMENT et relance la commande pour confirmer.

7. **Boucle de correction de compilation.** Erreur de build → identifie les fichiers → readFile → corrige → runShellCommand(build). Répète jusqu'à zéro erreur.

8. **Qualité du code.** Tes modifications doivent respecter les conventions existantes du projet (style, nommage, architecture). Ne laisse jamais de TODO non résolus ni de code commenté inutile.

9. **runShellCommand est TOUJOURS disponible en mode Agent.** Utilise-le pour : git clone/pull/push/commit, flutter build/test, npm/yarn/pnpm install, cargo build, bash scripts, et toute commande shell. Ne dis JAMAIS que tu "ne peux pas" exécuter une commande shell.

10. **git operations** → utilise runShellCommand directement. Ex : `git clone <url> <dest>`, `git commit -am "message"`, `git push origin main`. Ne demande JAMAIS à l'utilisateur de faire ça lui-même.

11. **Mémoire projet.** Après un bug important résolu ou une décision technique majeure → appelle updateProjectMemory avec un résumé Markdown structuré.

12. **Editeur ciblé vs réécriture.** Préfère editFile (remplacement ciblé) à writeFile (réécriture totale) pour les modifications partielles. Utilise writeFile uniquement pour créer un nouveau fichier ou réécrire un fichier court en totalité.

====

## PROCESSUS DE RÉFLEXION

Avant chaque appel d'outil, réfléchis brièvement (sans le montrer à l'utilisateur) :
- Quelle est l'information dont j'ai besoin ?
- Quel outil est le plus adapté ?
- Ai-je déjà cette information ou dois-je la récupérer ?

====

## WORKFLOWS TYPE

**Corriger un bug / une erreur de build :**
```
runShellCommand(build) → lire les erreurs → grepInFiles(symbole) → readFile → editFile → runShellCommand(build)
```

**Implémenter une fonctionnalité :**
```
listFiles → grepInFiles(code similaire) → readFile(fichiers concernés) → writeFile/editFile → runShellCommand(test)
```

**Explorer et comprendre une base de code :**
```
globSearchFiles(pattern) → readFilesBatch([fichiers]) → grepInFiles(symbole) → réponse synthétique
```

**Modifier sans régressions :**
```
readFile(complet) → editFile(old_text EXACT, new_text) → getLspDiagnostics → si erreurs → corriger
```

**Opérations git :**
```
runShellCommand(git status) → runShellCommand(git add -A) → runShellCommand(git commit -m "...") → runShellCommand(git push)
```

====

## FORMAT ET STYLE DE RÉPONSE

- **Langue :** réponds dans la langue de l'utilisateur (français si l'utilisateur parle français, anglais si anglais, etc.).
- **Ton :** direct, professionnel, sans fioritures. INTERDIT de commencer par "Super !", "Bien sûr !", "Absolument !", "D'accord !" ou tout autre formule de politesse creuse.
- **Code :** toujours dans des blocs ` ```langage `.
- **Actions :** annonce en 1 phrase courte ce que tu fais, puis fais-le immédiatement.
- **Fin de tâche :** résumé factuel en 1-2 phrases de ce qui a été accompli. Ne termine JAMAIS par une question ou une offre d'aide supplémentaire — la réponse est complète et définitive.
- **Pas de sur-explication.** Ne décris pas le code que tu vas écrire avant de l'écrire. Agis, puis explique brièvement si nécessaire.
''';
  }

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
    String agentMode = 'agent',
  }) {
    final ctrl = StreamController<AgentChunk>();
    // JSON literals containing only strings can arrive here at runtime as
    // List<Map<String, String>> even though the public API is dynamic-valued.
    // Rebuild every entry so Iterable.first/lastWhere and tool payloads use
    // one concrete map type throughout the Agent lifecycle.
    final normalizedMessages = messages
        .map<Map<String, dynamic>>(
          (message) => Map<String, dynamic>.from(message),
        )
        .toList();
    unawaited(_run(
      model: model,
      messages: normalizedMessages,
      systemPromptOverride: systemPromptOverride,
      ctrl: ctrl,
      context: context,
      workspacePath: workspacePath,
      agentMode: agentMode,
    ));
    return ctrl.stream;
  }

  Future<void> _run({
    required Models model,
    required List<Map<String, dynamic>> messages,
    String? systemPromptOverride,
    required StreamController<AgentChunk> ctrl,
    BuildContext? context,
    String workspacePath = '',
    String agentMode = 'agent',
  }) async {
    _client = http.Client();
    try {
      // Tools are always available in agent and ask modes.
      // Only 'normal' (free conversation) mode disables them entirely.
      final shouldUseTools = context != null && agentMode != 'normal';
      final agenticTools = shouldUseTools
          ? AgenticTools(workspacePath: workspacePath, context: context)
          : null;
      final toolSchemas = agenticTools?.getTools(
            readAccessOnly: agentMode != 'agent',
          ) ??
          const <Map<String, dynamic>>[];

      // ── Génération dynamique du system prompt ───────────────────────────
      final basePrompt = _buildSystemPrompt(workspacePath, toolSchemas);
      final systemPrompt = (systemPromptOverride == null ||
              systemPromptOverride.trim().isEmpty)
          ? basePrompt
          : '$basePrompt\n\n## CONTEXTE PERSONNALISÉ\n$systemPromptOverride';

      PandaLog.i(
        'AgentRunner',
        'Starting run — provider=${model.runtimeType} '
        'mode=$agentMode tools=${agenticTools != null} '
        'toolCount=${toolSchemas.length} workspace=$workspacePath',
      );
      if (model is Gemini) {
        await _runGemini(
          model,
          messages,
          systemPrompt,
          ctrl,
          agenticTools,
          toolSchemas,
          allowWrites: agentMode == 'agent',
        );
      } else if (model is LocalLlama) {
        // LocalLlama expose une API OpenAI-compatible → on passe par _runSse
        await _runSse(
          model,
          messages,
          systemPrompt,
          ctrl,
          agenticTools,
          toolSchemas,
          allowWrites: agentMode == 'agent',
        );
      } else {
        await _runSse(
          model,
          messages,
          systemPrompt,
          ctrl,
          agenticTools,
          toolSchemas,
          allowWrites: agentMode == 'agent',
        );
      }
    } catch (e) {
      PandaLog.e('AgentRunner', 'Uncaught error in _run', error: e);
      if (!ctrl.isClosed) {
        ctrl.add(AgentChunk(phase: AgentPhase.error, text: e.toString()));
      }
    } finally {
      _client?.close();
      _client = null;
      PandaLog.i('AgentRunner', 'Run complete');
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
    List<Map<String, dynamic>> toolSchemas,
    {required bool allowWrites}
  ) async {
    final conversationMessages = <Map<String, dynamic>>[
      <String, dynamic>{'role': 'system', 'content': systemPrompt},
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
          text: _friendlyHttpError(resp.statusCode, resp.body),
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

        ctrl.add(AgentChunk(phase: AgentPhase.toolRunning, toolName: name, toolArgs: args));
        PandaLog.toolCall('Gemini', name, args);

        final result = await _dispatchTool(
          tools,
          name,
          args,
          allowWrites: allowWrites,
        )
            .timeout(const Duration(seconds: 45), onTimeout: () {
          PandaLog.w('Gemini', 'Tool $name timed out after 45 s');
          return 'Error: tool $name exceeded 45 s timeout';
        });
        PandaLog.toolResult('Gemini', name, result);
        ctrl.add(AgentChunk(phase: AgentPhase.toolDone, toolName: name, toolResult: result));
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
    List<Map<String, dynamic>> toolSchemas,
    {required bool allowWrites}
  ) async {
    final conversationMessages = <Map<String, dynamic>>[
      <String, dynamic>{'role': 'system', 'content': systemPrompt},
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
          const message =
              'Le modèle a fermé le flux sans envoyer de contenu '
              '(réponse vide ou session refusée).';
          PandaLog.e('SSE', 'Stream ended with ZERO chunks in ${elapsed}ms');
          if (!ctrl.isClosed) {
            ctrl.add(const AgentChunk(
              phase: AgentPhase.error,
              text: message,
            ));
          }
        } else {
          PandaLog.i('SSE', 'Stream done — $chunkCount chunks in ${elapsed}ms');
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
          text: _friendlyHttpError(resp.statusCode, resp.body),
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

        ctrl.add(AgentChunk(phase: AgentPhase.toolRunning, toolName: functionName, toolArgs: args));
        PandaLog.toolCall('SSE', functionName, args);
        final result = await _dispatchTool(
          tools,
          functionName,
          args,
          allowWrites: allowWrites,
        )
            .timeout(const Duration(seconds: 45), onTimeout: () {
          PandaLog.w('SSE', 'Tool $functionName timed out after 45 s');
          return 'Error: tool $functionName exceeded 45 s timeout';
        });
        PandaLog.toolResult('SSE', functionName, result);
        ctrl.add(AgentChunk(phase: AgentPhase.toolDone, toolName: functionName, toolResult: result));
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
    {required bool allowWrites}
  ) async {
    try {
      const mutatingTools = {
        'writeFile',
        'deleteFile',
        'renamePath',
        'rename',
        'insertAtLine',
        'replaceAllInFile',
        'editFile',
        'runShellCommand',
        'updateProjectMemory',
      };
      if (!allowWrites && mutatingTools.contains(functionName)) {
        return 'Blocked: this tool changes the workspace and is unavailable in Ask mode.';
      }
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
        case 'updateProjectMemory':
          final res = await tools.updateProjectMemory(args['content']?.toString() ?? '');
          return res.success
              ? 'Project memory updated at .panda/memory.md'
              : (res.error ?? 'Error updating project memory');
        default:
          return 'Unknown tool: $functionName';
      }
    } catch (e) {
      return 'Error executing $functionName: $e';
    }
  }

  /// Converts an HTTP error code + body into a user-friendly error message.
  static String _friendlyHttpError(int statusCode, String body) {
    // Try to extract message from JSON body
    String? extracted;
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      extracted = json['error']?['message']?.toString()
          ?? json['message']?.toString()
          ?? json['error']?.toString();
    } catch (_) {}

    switch (statusCode) {
      case 400:
        return 'Requête invalide (400). ${extracted ?? body}';
      case 401:
        return 'Clé API invalide ou expirée (401). Vérifiez votre clé dans Paramètres Agent.';
      case 402:
        final detail = extracted ?? 'Insufficient Balance';
        return 'Solde insuffisant (402) — $detail\n\n'
            'Votre compte n\'a plus de crédits. Rechargez votre solde sur '
            'la plateforme du provider (ex : platform.deepseek.com, platform.openai.com…).';
      case 403:
        return 'Accès refusé (403). ${extracted ?? 'Votre clé n\'a pas les permissions nécessaires.'}';
      case 404:
        return 'Endpoint introuvable (404). Vérifiez l\'URL du provider.';
      case 429:
        return 'Limite de débit atteinte (429). ${extracted ?? 'Attendez quelques secondes et réessayez.'}';
      case 500:
      case 502:
      case 503:
        return 'Erreur serveur ($statusCode). ${extracted ?? 'Le provider est temporairement indisponible.'}';
      default:
        return 'HTTP $statusCode: ${extracted ?? body}';
    }
  }

  bool _shouldUseTools(List<Map<String, dynamic>> messages) {
    Map<String, dynamic>? latestUser;
    for (final message in messages.reversed) {
      if (message['role']?.toString() == 'user') {
        latestUser = message;
        break;
      }
    }
    final text = latestUser?['content']?.toString() ?? '';
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
