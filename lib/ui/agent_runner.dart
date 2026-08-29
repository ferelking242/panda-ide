import 'package:shared_preferences/shared_preferences.dart';
import 'package:panda/utils/pandarules_service.dart';
/// AgentRunner — streaming AI runner pour Panda Agent.
///
/// Supporte tous les providers existants (Gemini, OpenAI, Claude, OpenAI-compat,
/// LocalLlama) ainsi que les états "thinking" (Claude extended thinking,
/// o1/o3 reasoning_content, Gemini thinking models).
///
/// Supporte également le tool calling : quand un BuildContext et un workspacePath
/// sont fournis, l'agent peut exécuter des commandes shell, lire/écrire des fichiers, etc.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../utils/ai.dart';
import '../agent/events/agent_event.dart';
import '../agent/events/agent_event_bus.dart';
import '../utils/agentic_tools.dart';
import '../utils/panda_log.dart';
import '../terminal/terminal_bridge.dart';
import '../utils/pandarules_service.dart';
import '../utils/agent_history_service.dart';
import '../utils/agent_settings_service.dart';
import '../utils/agent_thinking_parser.dart';
import '../agent/tools/tool_registry.dart';
import '../agent/tools/tool_executor.dart';
import '../agent/tools/native_tool_bridge.dart';
import '../agent/context/context_manager.dart';
import '../agent/sessions/session_manager.dart';
import '../agent/runtime/retry_manager.dart';
import '../agent/runtime/error_classifier.dart';
import '../agent/agents/agent_registry.dart';
import '../agent/modes/mode_registry.dart';
import '../agent/events/event_activity_bridge.dart';
import '../agent/modes/plan_viewer.dart';
import '../agent/agents/agent_status_widget.dart';
import '../agent/agents/subagent_viewer.dart';
import '../agent/subagents/subagent_manager.dart';
import '../agent/context/history_compactor.dart';
import '../agent/context/code_map.dart';
import '../agent/verification/verification_pipeline.dart';
import '../agent/verification/verification_viewer.dart';
import '../agent/mcp/mcp_tool_bridge.dart';


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
  /// Identifiant du bloc chronologique (réflexion / texte / outils).
  /// Permet à l'UI d'afficher les étapes dans le vrai ordre au lieu de tout
  /// empiler la réflexion en haut et les outils au milieu.
  final int? blockId;
  const AgentChunk({
    required this.phase,
    this.text = '',
    this.toolName,
    this.toolArgs,
    this.toolResult,
    this.blockId,
  });
}

/// Séquenceur de blocs chronologiques partagé par les deux runners.
/// Un nouveau bloc est ouvert dès que le type d'événement change
/// (thinking → texte → outils → texte…), ce qui restitue le déroulé réel.
class _BlockSequencer {
  int _seq = -1;
  String _lastKind = '';

  int next(String kind) {
    if (kind != _lastKind) {
      _seq += 1;
      _lastKind = kind;
    }
    return _seq;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AgentRunner
// ─────────────────────────────────────────────────────────────────────────────

class AgentRunner {
  http.Client? _client;

  /// V3 agent components
  final ToolRegistry toolRegistry = ToolRegistry();
  late final ToolExecutor toolExecutor;
  final ContextManager contextManager = ContextManager();
  final SessionManager sessionManager = SessionManager();
  final RetryManager retryManager = RetryManager();
  final ErrorClassifier errorClassifier = ErrorClassifier();
  final AgentRegistry agentRegistry = AgentRegistry();
  final ModeRegistry modeRegistry = ModeRegistry();
  SubagentManager? subagentManager;
  McpToolBridge? mcpToolBridge;
  EventActivityBridge? activityBridge;

  final AgentEventBus _eventBus = AgentEventBus();

  AgentRunner() {
    toolExecutor = ToolExecutor(
      registry: toolRegistry,
      eventBus: _eventBus,
    );
  }

  void cancel() {
    try {
      _client?.close();
      _client = null;
    } catch (_) {}
  }

  Stream<AgentChunk> run({
    required Models model,
    required List<Map<String, dynamic>> messages,
    BuildContext? context,
    String workspacePath = '',
    String agentMode = 'agent',
    String? systemPromptOverride,
    AgentConfirmCallback? onConfirmRequired,
    String approvalMode = 'default',
    AgentEventBus? eventBus,
  }) {
    final ctrl = StreamController<AgentChunk>();
    _run(
      model: model,
      messages: messages,
      systemPromptOverride: systemPromptOverride,
      ctrl: ctrl,
      context: context,
      workspacePath: workspacePath,
      agentMode: agentMode,
      onConfirmRequired: onConfirmRequired,
      approvalMode: approvalMode,
      eventBus: eventBus,
    );
    return ctrl.stream;
  }

  /// Génère dynamiquement le system prompt à partir du contexte réel du projet.
  /// Appelé dans [_run] après que les toolSchemas sont connus.
  static Future<String> _buildSystemPrompt(
    String workspacePath,
    List<Map<String, dynamic>> toolSchemas, {
    String agentMode = "agent",
  }) async {
    final StringBuffer projectSection = StringBuffer();
    final StringBuffer repoSection   = StringBuffer();

    if (workspacePath.isNotEmpty) {
      final dir = Directory(workspacePath);
      if (dir.existsSync()) {
        final projectName = path.basename(workspacePath);
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

        // V3 CodeMap: analyze code structure
        try {
          final codeStructure = await CodeMap.analyze(workspacePath);
          if (codeStructure.classes.isNotEmpty || codeStructure.functions.isNotEmpty) {
            projectSection
              ..writeln()
              ..writeln(codeStructure.toContextString());
          }
        } catch (_) {}

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

    String customPrompt = '';
    String customRules  = '';
    Map<String, String> secretsMap = {};
    List<String> activeSkills      = [];
    String? projectRules;
    String memoryContent = '';
    try {
      customPrompt = await AgentSettingsService.getCustomPrompt();
      customRules  = await AgentSettingsService.getCustomRules();
      secretsMap   = await AgentSettingsService.getSecrets();
      activeSkills = await AgentSettingsService.getSkills();
      projectRules = await PandaRulesService.loadRules(workspacePath);
      final memFile = File('$workspacePath/.panda/memory.md');
      if (await memFile.exists()) {
        memoryContent = await memFile.readAsString();
      }
    } catch (_) {}

    final String modeInstructions;
    if (agentMode == 'ask') {
      modeInstructions = '''====
## MODE ASK ACTIF (QUESTIONS & RÉPONSES)
- Tu es actuellement en MODE ASK (Discussion et explications).
- En Mode Ask, tu n'exécutes AUCUN outil ni AUCUNE commande shell.
- Tu dois répondre directement à l'utilisateur de manière pédagogique, claire et concise en français.
- Fournis des explications conceptuelles et des exemples de code parfaitement formatés en Markdown.
- Si l'utilisateur demande d'effectuer des modifications de code, des installations ou des commandes shell (ex: clone, git push, build), indique la démarche à suivre et invite-le à basculer en MODE AGENT.''';
    } else if (agentMode == 'plan') {
      modeInstructions = '''====
## MODE PLAN ACTIF (PLANIFICATION ÉTAPE PAR ÉTAPE)
- Tu es actuellement en MODE PLAN.
- Ton rôle est de discuter avec l'utilisateur pour comprendre ses besoins, d'analyser le projet avec tes outils en lecture seule, et de proposer un plan de réalisation détaillé.
- Tu ne peux PAS créer, modifier ou supprimer des fichiers directement, ni exécuter de commandes shell en Mode Plan.
- Quand le plan est prêt et complet, rédiges-le de façon claire et structurée au format Markdown avec des sous-titres et des étapes à cocher `- [ ] Tâche`.
- Inclus la balise spéciale `<plan>...</plan>` autour du plan final. Exemple :
<plan>
# 📋 Plan de réalisation : [Nom de la fonctionnalité / du projet]

## 🎯 Objectif
[Description concise de l'objectif]

## 📐 Choix techniques & Architecture
- ...

## 📝 Liste des tâches
- [ ] **Tâche 1** : ...
- [ ] **Tâche 2** : ...
- [ ] **Tâche 3** : ...
</plan>
L'interface affichera automatiquement une carte interactive avec des boutons pour approuver le plan et passer directement en Mode Agent pour commencer à coder !''';
    } else {
      modeInstructions = '''====
## MODE AGENT ACTIF (AUTONOMIE ET ÉDITION DU CODE)
- Tu es en MODE AGENT (Autonomie totale).
- Tu as les pleins pouvoirs pour créer, modifier, supprimer des fichiers, exécuter des commandes shell, gérer les dépendances et effectuer des commits Git.
- Si un plan a été préalablement validé (dans `.panda/plan.md` ou dans le chat), exécute-le méthodiquement étape par étape en cochant au fur et à mesure les tâches accomplies.''';
    }

    final String customSection = customPrompt.trim().isNotEmpty
        ? '\n====\n## INSTRUCTIONS PERSONNALISÉES UTILISATEUR\n${customPrompt.trim()}\n'
        : '';

    final String userRulesSection = customRules.trim().isNotEmpty
        ? '\n====\n## RÈGLES PERSONNALISÉES UTILISATEUR\n${customRules.trim()}\n'
        : '';

    final String rulesSection = (projectRules != null && projectRules.trim().isNotEmpty)
        ? '\n====\n## RÈGLES DU PROJET (.pandarules)\n${projectRules.trim()}\n'
        : '';

    final String memorySection = memoryContent.trim().isNotEmpty
        ? '\n====\n## MÉMOIRE DU PROJET (.panda/memory.md)\n${memoryContent.trim()}\n'
        : '';

    final String secretsSection = secretsMap.isNotEmpty
        ? '\n====\n## SECRETS D\'ENVIRONNEMENT DISPONIBLES\nSecrets configurés : ${secretsMap.keys.join(', ')}\n'
        : '';

    final String skillsSection = activeSkills.isNotEmpty
        ? '\n====\n## COMPÉTENCES ACTIVÉES\n${activeSkills.map((s) => '• $s').join('\n')}\n'
        : '';

    return '''Tu es **Panda Agent**, un ingénieur logiciel senior d'élite intégré à Panda IDE.
Tu possèdes une expertise approfondie en de nombreux langages, frameworks, patterns de conception et outils d'ingénierie.
Tu fonctionnes dans un environnement IDE complet (web / mobile) avec un terminal PTY, un gestionnaire de fichiers et des outils de développement.

$modeInstructions
$customSection
$userRulesSection
$rulesSection
$memorySection
$secretsSection
$skillsSection

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
1. **Agis, ne décris pas.** Si un outil peut accomplir quelque chose, appelle-le immédiatement. INTERDIT d'écrire "Je vais lire…" — exécute directement.
2. **readFile obligatoire avant editFile.** Sans aucune exception. Ne modifie jamais un fichier sans en avoir lu le contenu complet au préalable.
3. **N'invente jamais le contenu d'un fichier.** Contenu inconnu → readFile.
4. **Enchaîne automatiquement.** Continue d'appeler des outils SANS demander la permission jusqu'à ce que la tâche soit 100 % achevée.
5. **Résilience aux erreurs.** Si un outil retourne une erreur → analyse le message → réessaie différemment.
6. **Après runShellCommand** → lis la sortie complète. Si elle contient des erreurs, corrige-les IMMÉDIATEMENT.
7. **Auto-install des dépendances manquantes.** Si une commande échoue parce qu'un package, une librairie ou un outil n'est pas installé (ex: `command not found`, `ModuleNotFoundError`, `No such file`, `package not found`), **INSTALLE-LE IMMÉDIATEMENT** sans demander. Exemples :
   - `command not found: python3` → exécute `pkg install python` ou `apt install python3` (selon l'environnement)
   - `ModuleNotFoundError: No module named 'xxx'` → exécute `pip install xxx`
   - `npm ERR! peer dep` ou `Cannot find module` → exécute `npm install` ou `npm install xxx`
   - `flutter: command not found` → installe Flutter SDK
   - `dart: command not found` → installe Dart SDK
   - Erreur de compilation liée à un package manquant → installe-le puis relance la compilation.
   **Ne JAMAIS renvoyer une erreur de dépendance manquante à l'utilisateur. Résous-la toi-même.**
8. **Opérations git & secrets** → tu peux utiliser getSecret pour récupérer des jetons (ex: GITHUB_TOKEN, PAT) et utiliser runShellCommand pour exécuter git clone, git push, git commit.
9. **En Mode Ask** → NE TENTE PAS d'exécuter de commande shell ni de modifier de fichier. Indique la démarche et propose le passage en Mode Agent.

====
## PROCESSUS DE RÉFLEXION INTERNE (OBLIGATOIRE - COMME CLINE)
1. Avant chaque outil ou réponse, tu DOIS obligatoirement mener une réflexion approfondie et structurée sur la tâche.
2. Si le modèle supporte un "thinking mode" natif (Gemini thinking, o1/o3, Claude extended thinking), utilise-le.
3. Sinon (ou en plus), tu DOIS encapsuler TOUTE ta réflexion de manière explicite dans des balises `<think>...</think>` au tout début de ton message ou de ton tour.
4. Ne mets JAMAIS de réflexion brute en dehors de ces balises ou du format natif. Cette réflexion est cruciale pour planifier et réussir les étapes complexes de développement.

====
## FORMAT ET STYLE DE RÉPONSE
- **Langue :** réponds dans la langue de l'utilisateur (français si français).
- **Ton :** direct, professionnel, sans fioritures.
- **Code :** toujours dans des blocs ```langage.
- **Actions :** annonce en 1 phrase courte ce que tu fais, puis fais-le immédiatement.''';
  }


  Future<void> _run({
    required Models model,
    required List<Map<String, dynamic>> messages,
    String? systemPromptOverride,
    required StreamController<AgentChunk> ctrl,
    BuildContext? context,
    String workspacePath = '',
    String agentMode = 'agent',
    AgentConfirmCallback? onConfirmRequired,
    String approvalMode = 'default',
    AgentEventBus? eventBus,
  }) async {
    _client = http.Client();
    bool terminalError = false;
    eventBus?.emit(AgentStarted(taskId: DateTime.now().millisecondsSinceEpoch.toString(), mode: agentMode));
    try {
      // Ask = aucun outil du tout. Plan = outils en lecture seule.
      // Agent = tous les outils.
      final shouldUseTools =
          context != null && (agentMode == 'agent' || agentMode == 'plan');
      final agenticTools = shouldUseTools
          ? AgenticTools(
              workspacePath: workspacePath,
              context: context,
              onConfirmRequired: onConfirmRequired,
              approvalMode: approvalMode,
            )
          : null;

      // Register native tools in V3 ToolRegistry
      if (context != null && toolRegistry.count == 0) {
        NativeToolBridge.registerAll(
          registry: toolRegistry,
          context: context,
          workspacePath: workspacePath,
          onConfirmRequired: onConfirmRequired,
          approvalMode: approvalMode,
        );
      }

      // Initialize SubagentManager
      subagentManager ??= SubagentManager(
        registry: agentRegistry,
        eventBus: _eventBus,
      );

      // Initialize McpToolBridge and sync MCP tools
      mcpToolBridge ??= McpToolBridge(registry: toolRegistry);
      try {
        await mcpToolBridge!.syncAll();
      } catch (_) {}

      // Initialize EventActivityBridge if eventBus available
      if (eventBus != null && activityBridge == null) {
        // ActivityBridge needs ActivityController from UI - skip for now
      }

      final toolSchemas = toolRegistry.count > 0
          ? toolRegistry.getSchemas(mode: agentMode)
          : (agenticTools?.getTools(
                readAccessOnly: agentMode != 'agent',
              ) ??
              const <Map<String, dynamic>>[]);

      // ── Génération dynamique du system prompt (V3 ContextManager) ──────
      final basePrompt = await _buildSystemPrompt(workspacePath, toolSchemas, agentMode: agentMode);
      
      // Enrich context with V3 ContextManager
      String enrichedContext = '';
      if (workspacePath.isNotEmpty) {
        try {
          final agentContext = await contextManager.build(
            workspacePath: workspacePath,
            userRequest: messages.isNotEmpty ? (messages.last['content']?.toString() ?? '') : '',
            conversationHistory: messages,
          );
          if (agentContext.usagePercent > 0.1) {
            enrichedContext = '\n\n## CONTEXTE PROJET (auto-généré)\n${agentContext.buildString()}';
          }
        } catch (_) {}
      }
      
      final systemPrompt = (systemPromptOverride == null ||
              systemPromptOverride.trim().isEmpty)
          ? '$basePrompt$enrichedContext'
          : '$basePrompt$enrichedContext\n\n## CONTEXTE PERSONNALISÉ\n$systemPromptOverride';

      // Save session start
      final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
      await sessionManager.save(AgentSessionData(
        id: sessionId,
        title: messages.isNotEmpty ? (messages.last['content']?.toString() ?? 'Session').substring(0, 50) : 'Session',
        mode: agentMode,
        model: model.runtimeType.toString(),
        messages: messages,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      PandaLog.i(
        'AgentRunner',
        'Starting run — provider=${model.runtimeType} '
        'mode=$agentMode tools=${agenticTools != null} '
        'toolCount=${toolSchemas.length} workspace=$workspacePath '
        'sessionId=$sessionId',
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
          agentMode: agentMode,
          blocks: _BlockSequencer(),
          eventBus: eventBus,
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
          agentMode: agentMode,
          blocks: _BlockSequencer(),
          eventBus: eventBus,
        );
      }
    } catch (e) {
      terminalError = true;
      final classified = ErrorClassifier.classify(e);
      PandaLog.e('AgentRunner', 'Uncaught error in _run [category=${classified.category}]', error: e);
      eventBus?.emit(AgentError(taskId: '', error: e.toString()));
      if (!ctrl.isClosed) {
        final errorMsg = classified.suggestion.isNotEmpty
            ? '${e.toString()}\nSuggestion: ${classified.suggestion}'
            : e.toString();
        ctrl.add(AgentChunk(phase: AgentPhase.error, text: errorMsg));
      }
    } finally {
      _client?.close();
      _client = null;
      PandaLog.i('AgentRunner', 'Run complete');
      eventBus?.emit(AgentFinished(taskId: '', result: ''));
      if (!terminalError && !ctrl.isClosed) {
        ctrl.add(const AgentChunk(phase: AgentPhase.done, text: ''));
      }
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
    {required bool allowWrites, String agentMode = 'agent', _BlockSequencer? blocks, AgentEventBus? eventBus}
  ) async {
    final seq = blocks ?? _BlockSequencer();
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
          eventBus?.emit(AgentStreamingChunk(text: text.toString()));
        }
        return;
      }

      // Collect text/thinking parts and function calls
      String assistantText = '';
      final List<Map<String, dynamic>> functionCalls = [];

      for (final part in parts) {
        if (part['thought'] == true) {
          final t = part['text']?.toString() ?? '';
          if (t.isNotEmpty) {
            ctrl.add(AgentChunk(phase: AgentPhase.thinking, text: t, blockId: seq.next('thinking')));
            eventBus?.emit(AgentThinkingChunk(text: t));
          }
        } else if (part['functionCall'] != null) {
          functionCalls.add(Map<String, dynamic>.from(part['functionCall'] as Map));
        } else {
          final t = part['text']?.toString() ?? '';
          if (t.isNotEmpty) {
            assistantText += t;
            ctrl.add(AgentChunk(phase: AgentPhase.streaming, text: t, blockId: seq.next('text')));
            eventBus?.emit(AgentStreamingChunk(text: t));
          }
        }
      }

      // No tool calls → done
      if (functionCalls.isEmpty || tools == null) return;

      // Compact history if too long (in-place)
      if (conversationMessages.length > 50) {
        final compacted = await HistoryCompactor.compact(
          conversationMessages,
          maxTokens: 8000,
          summarize: (text) async => text.substring(0, text.length ~/ 2),
        );
        conversationMessages
          ..clear()
          ..addAll(compacted);
      }

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

      // Execute each tool call
      final toolResults = <Map<String, dynamic>>[];
      for (final fc in functionCalls) {
        final name = fc['name']?.toString() ?? '';
        final args = (fc['args'] is Map)
            ? Map<String, dynamic>.from(fc['args'] as Map)
            : <String, dynamic>{};

        ctrl.add(AgentChunk(phase: AgentPhase.toolRunning, toolName: name, toolArgs: args, blockId: seq.next('tool')));
        eventBus?.emit(AgentToolStarted(toolId: name, toolName: name, args: args));
        _eventBus.emit(AgentToolStarted(toolId: name, toolName: name, args: args));
        PandaLog.toolCall('Gemini', name, args);

        // Use V3 ToolExecutor when available, fallback to old dispatch
        String result;
        if (toolRegistry.has(name)) {
          result = await toolExecutor.execute(name, args);
        } else {
          result = await _dispatchTool(
            tools,
            name,
            args,
            allowWrites: allowWrites,
            agentMode: agentMode,
          );
        }
        // Wrap with timeout
        final timedResult = await Future<String>.delayed(
          Duration.zero,
          () => Future.value(result),
        ).timeout(const Duration(seconds: 150), onTimeout: () {
          PandaLog.w('Gemini', 'Tool $name timed out after 150 s');
          return 'Error: tool $name exceeded 150 s timeout';
        });
        result = timedResult;
        PandaLog.toolResult('Gemini', name, result);
        ctrl.add(AgentChunk(phase: AgentPhase.toolDone, toolName: name, toolResult: result));
        eventBus?.emit(AgentToolFinished(toolId: name, toolName: name, result: result));

        // V3 Verification: run checks after mutating tool calls
        if (allowWrites && ['writeFile', 'editFile', 'deleteFile'].contains(name)) {
          final changedFile = args['filePath']?.toString() ?? '';
          if (changedFile.isNotEmpty && workspacePath.isNotEmpty) {
            try {
              final vResult = await VerificationPipeline.run(
                changedFiles: [changedFile],
                workspacePath: workspacePath,
                level: VerificationLevel.basic,
              );
              if (!vResult.passed) {
                eventBus?.emit(AgentVerificationFailed(
                  errors: vResult.errors,
                ));
              }
            } catch (_) {}
          }
        }
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
    {required bool allowWrites, String agentMode = 'agent', _BlockSequencer? blocks, AgentEventBus? eventBus}
  ) async {
    final seq = blocks ?? _BlockSequencer();
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
          blockId: seq.next('thinking'),
        ));
        eventBus?.emit(AgentThinkingChunk(text: reasoningText));
        PandaLog.d(
          'AgentRunner',
          'Non-stream reasoning received (${reasoningText.length} chars)',
        );
      }
      final assistantText = model.parseChatMessage(decoded);
      final toolCalls = model.parseToolCalls(decoded);
      PandaLog.d('SSE', 'Parsed response — text=${assistantText.length} chars toolCalls=${toolCalls.length}');

      if (assistantText.isNotEmpty) {
        ctrl.add(AgentChunk(
          phase: AgentPhase.streaming,
          text: assistantText,
          blockId: seq.next('text'),
        ));
        eventBus?.emit(AgentStreamingChunk(text: assistantText));
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

        ctrl.add(AgentChunk(
          phase: AgentPhase.toolRunning,
          toolName: functionName,
          toolArgs: args,
          blockId: seq.next('tool'),
        ));
        eventBus?.emit(AgentToolStarted(toolId: functionName, toolName: functionName, args: args));
        PandaLog.toolCall('SSE', functionName, args);
        final result = await _dispatchTool(
          tools,
          functionName,
          args,
          allowWrites: allowWrites,
          agentMode: agentMode,
        )
            .timeout(const Duration(seconds: 150), onTimeout: () {
          PandaLog.w('SSE', 'Tool $functionName timed out after 150 s');
          return 'Error: tool $functionName exceeded 150 s timeout';
        });
        PandaLog.toolResult('SSE', functionName, result);
        ctrl.add(AgentChunk(phase: AgentPhase.toolDone, toolName: functionName, toolResult: result));
        eventBus?.emit(AgentToolFinished(toolId: functionName, toolName: functionName, result: result));

        // V3 Verification: run checks after mutating tool calls
        if (allowWrites && ['writeFile', 'editFile', 'deleteFile'].contains(functionName)) {
          final changedFile = args['filePath']?.toString() ?? '';
          if (changedFile.isNotEmpty && workspacePath.isNotEmpty) {
            try {
              final vResult = await VerificationPipeline.run(
                changedFiles: [changedFile],
                workspacePath: workspacePath,
                level: VerificationLevel.basic,
              );
              if (!vResult.passed) {
                eventBus?.emit(AgentVerificationFailed(
                  errors: vResult.errors,
                ));
              }
            } catch (_) {}
          }
        }
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
    {required bool allowWrites, String agentMode = 'agent'}
  ) async {
    // Use V3 ToolExecutor when available
    if (toolRegistry.has(functionName)) {
      return await toolExecutor.execute(functionName, args);
    }
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
        return "Blocage : L'outil \"$functionName\" modifie l'espace de travail et est indisponible en mode $agentMode. Veuillez passer en Mode Agent pour autoriser l'exécution.";
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
        case 'getTerminalOutput':
          final lines = args['lines'] is int ? args['lines'] as int : 100;
          return TerminalBridge.instance.getRecentOutput(lines);
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
                case 'getSecret':
          final secretName = (args['name'] ?? args['secretName'] ?? '').toString();
          final res = await tools.getSecret(secretName);
          return res.success ? (res.data ?? '') : (res.error ?? 'Error getting secret');
        case 'listSecrets':
          final res = await tools.listSecrets();
          return res.success ? jsonEncode(res.data) : (res.error ?? 'Error listing secrets');
        case 'getAgentSkills':
          final res = await tools.getAgentSkills();
          return res.success ? jsonEncode(res.data) : (res.error ?? 'Error getting skills');
        case 'useAgentSkill':
          final sName = (args['skillName'] ?? args['name'] ?? '').toString();
          final res = await tools.useAgentSkill(sName);
          return res.success ? (res.data ?? '') : (res.error ?? 'Error using skill');
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
        return 'Clé API invalide ou expirée (401).\n\n'
            '• Vérifiez votre clé dans les Paramètres Agent (onglet Providers).\n'
            '• Pour Gemini : la clé doit être activée sur aistudio.google.com.\n'
            '• Pour DeepSeek/OpenAI : recopiez-la depuis le tableau de bord du provider.';
      case 402:
        final detail = extracted ?? 'Insufficient Balance';
        return 'Solde insuffisant (402) — $detail\n\n'
            'Votre compte n\'a plus de crédits. Rechargez votre solde sur '
            'la plateforme du provider (ex : platform.deepseek.com, aistudio.google.com…).';
      case 403:
        return 'Accès refusé (403). ${extracted ?? 'Votre clé n\'a pas les permissions nécessaires.'}';
      case 404:
        // 404 peut venir d'une URL d'endpoint incorrecte OU d'un nom de modèle inexistant.
        final hint404 = extracted != null && extracted.isNotEmpty
            ? extracted
            : 'Le modèle sélectionné n\'existe peut-être plus chez ce provider.';
        return 'Ressource introuvable (404) — $hint404\n\n'
            'Reconfigurez votre provider dans les Paramètres Agent pour choisir un modèle valide.';
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

  static (String, String) _extractThinkingTags(String text) {
    final matches = RegExp(r'<think>([\s\S]*?)</think>').allMatches(text);
    if (matches.isEmpty) {
      return ('', text);
    }

    final thinkingParts = <String>[];
    String cleaned = text;
    for (final match in matches.toList().reversed) {
      final value = match.group(1)?.trim() ?? '';
      if (value.isNotEmpty) {
        thinkingParts.add(value);
      }
      cleaned = cleaned.replaceRange(match.start, match.end, '');
    }

    return (thinkingParts.join('\n').trim(), cleaned.trim());
  }

  static List<AgentChunk> parseSsePayload(Map<String, dynamic> payload) {
    final chunks = <AgentChunk>[];

    void addTextChunk(String text) {
      if (text.trim().isEmpty) return;
      final (thinking, cleaned) = _extractThinkingTags(text);
      if (thinking.isNotEmpty) {
        chunks.add(AgentChunk(phase: AgentPhase.thinking, text: thinking));
      }
      if (cleaned.isNotEmpty) {
        chunks.add(AgentChunk(phase: AgentPhase.streaming, text: cleaned));
      }
    }

    final choices = payload['choices'];
    if (choices is List && choices.isNotEmpty) {
      for (final entry in choices) {
        if (entry is! Map) continue;
        final delta = entry['delta'];
        if (delta is Map) {
          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            addTextChunk(content);
          } else if (content is List) {
            for (final item in content) {
              if (item is String && item.isNotEmpty) {
                addTextChunk(item);
              } else if (item is Map) {
                final text = item['text']?.toString();
                if (text != null && text.isNotEmpty) {
                  addTextChunk(text);
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
            addTextChunk(content);
          } else if (content is List) {
            for (final item in content) {
              if (item is String && item.isNotEmpty) {
                addTextChunk(item);
              } else if (item is Map) {
                final text = item['text']?.toString();
                if (text != null && text.isNotEmpty) {
                  addTextChunk(text);
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
                addTextChunk(text);
              }
            }
          }
        }
      }
      if (chunks.isNotEmpty) return chunks;
    }

    final content = payload['content'];
    if (content is String && content.isNotEmpty) {
      addTextChunk(content);
      return chunks;
    }
    if (content is List) {
      for (final item in content) {
        if (item is Map) {
          final text = item['text']?.toString();
          if (text != null && text.isNotEmpty) {
            addTextChunk(text);
          }
        } else if (item is String && item.isNotEmpty) {
          addTextChunk(item);
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
          if (t.isNotEmpty) addTextChunk(t);
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
