/// ModelSelectorService — Sélection automatique du modèle selon la tâche IDE.
///
/// Choisit le meilleur modèle installé selon le contexte d'utilisation :
///   • code_completion  → coding_score max, tool_calling optionnel
///   • agent_chat       → tool_calling + reasoning
///   • vision_analysis  → vision: true
///   • math_reasoning   → reasoning: true, coding_score >= 3
///   • general_chat     → modèle généraliste, taille équilibrée
///
/// Fallback : si aucun modèle installé n'est parfait, retourne le meilleur disponible.
library;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_model_entry.dart';
import '../services/catalog_service.dart';
import '../services/model_download_manager.dart';



// ── Types de tâches IDE ───────────────────────────────────────────────────────

enum IdeTask {
  codeCompletion,  // complétion inline dans l'éditeur
  agentChat,       // chat avec agent autonome (tool calling)
  visionAnalysis,  // analyse d'une image / screenshot
  mathReasoning,   // raisonnement mathématique
  generalChat,     // chat général, questions/réponses
  codeReview,      // revue de code, explication
  debugAssistance, // aide au debug
}

extension IdleTaskLabel on IdeTask {
  String get label {
    switch (this) {
      case IdeTask.codeCompletion:  return 'Complétion de code';
      case IdeTask.agentChat:       return 'Agent autonome';
      case IdeTask.visionAnalysis:  return 'Analyse d\'image';
      case IdeTask.mathReasoning:   return 'Raisonnement maths';
      case IdeTask.generalChat:     return 'Chat général';
      case IdeTask.codeReview:      return 'Revue de code';
      case IdeTask.debugAssistance: return 'Aide au debug';
    }
  }

  String get emoji {
    switch (this) {
      case IdeTask.codeCompletion:  return '⌨️';
      case IdeTask.agentChat:       return '🤖';
      case IdeTask.visionAnalysis:  return '👁️';
      case IdeTask.mathReasoning:   return '🧮';
      case IdeTask.generalChat:     return '💬';
      case IdeTask.codeReview:      return '🔍';
      case IdeTask.debugAssistance: return '🐛';
    }
  }
}

// ── Résultat de la sélection ──────────────────────────────────────────────────

class ModelSelectionResult {
  final AiModelEntry? model;
  final InstalledModel? installed;
  final String          quantLevel;
  final double          score;       // Score de correspondance 0-100
  final String          reason;      // Explication lisible
  final bool            isInstalled; // false si aucun modèle installé

  const ModelSelectionResult({
    required this.model,
    required this.installed,
    required this.quantLevel,
    required this.score,
    required this.reason,
    required this.isInstalled,
  });

  /// Pas de modèle disponible.
  static const ModelSelectionResult none = ModelSelectionResult(
    model:       null,
    installed:   null,
    quantLevel:  '',
    score:       0,
    reason:      'Aucun modèle installé',
    isInstalled: false,
  );

  /// ID aiConfig du modèle sélectionné (format LocalLlama-...)
  String get aiConfigId {
    if (model == null) return '';
    return 'LocalLlama-${model!.id}-${quantLevel.replaceAll("_", "").toLowerCase()}';
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class ModelSelectorService {

  /// Sélectionne le meilleur modèle installé pour une tâche donnée.
  ///
  /// [task]       — type de tâche IDE
  /// [catalog]    — catalogue courant (optionnel, chargé automatiquement si null)
  static Future<ModelSelectionResult> selectFor({
    required IdeTask       task,
    ModelCatalog?          catalog,
  }) async {
    catalog ??= await CatalogService.load();
    await ModelDownloadManager.instance.init();

    final installed = ModelDownloadManager.instance.allInstalled;
    if (installed.isEmpty) return ModelSelectionResult.none;

    // Récupère les fiches des modèles installés
    final candidates = <_Candidate>[];
    for (final inst in installed) {
      final entry = _findEntry(catalog, inst.modelId);
      if (entry == null) continue;
      final score = _scoreForTask(entry, inst, task);
      candidates.add(_Candidate(entry: entry, installed: inst, score: score));
    }

    if (candidates.isEmpty) return ModelSelectionResult.none;

    // Trie par score décroissant
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;

    return ModelSelectionResult(
      model:       best.entry,
      installed:   best.installed,
      quantLevel:  best.installed.quantLevel,
      score:       best.score,
      reason:      _reason(best.entry, task, best.score),
      isInstalled: true,
    );
  }

  /// Enregistre le modèle sélectionné comme défaut pour une tâche dans les prefs.
  static Future<void> setDefaultForTask(
      IdeTask task, ModelSelectionResult result) async {
    if (!result.isInstalled) return;
    final prefs   = await SharedPreferences.getInstance();
    final raw     = prefs.getString('panda_task_model_defaults') ?? '{}';
    final Map<String, dynamic> map =
        Map<String, dynamic>.from(jsonDecode(raw) as Map);
    map[task.name] = result.aiConfigId;
    await prefs.setString('panda_task_model_defaults', jsonEncode(map));
  }

  /// Récupère l'override manuel pour une tâche (si l'utilisateur a forcé un modèle).
  static Future<String?> getOverrideForTask(IdeTask task) async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('panda_task_model_defaults') ?? '{}';
    final map   = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    return map[task.name] as String?;
  }

  /// Retourne le meilleur modèle pour chaque tâche IDE (résumé global).
  static Future<Map<IdeTask, ModelSelectionResult>> selectAll(
      ModelCatalog catalog) async {
    final results = <IdeTask, ModelSelectionResult>{};
    await Future.wait(IdeTask.values.map((task) async {
      results[task] = await selectFor(task: task, catalog: catalog);
    }));
    return results;
  }

  // ── Scoring ───────────────────────────────────────────────────────────────

  static double _scoreForTask(AiModelEntry entry, InstalledModel inst, IdeTask task) {
    double score = 0;
    final caps   = entry.capabilities;

    switch (task) {
      case IdeTask.codeCompletion:
        score += caps.codingScore * 15.0;          // coding ×15 (0-75)
        if (!caps.vision) score += 10;             // bonus légerté visuelle
        if (entry.quantizations.any((q) => q.level == inst.quantLevel && q.sizeGb < 3.0)) {
          score += 10;                             // bonus modèle léger = rapide
        }
        break;

      case IdeTask.agentChat:
        if (caps.toolCalling)  score += 40;
        if (caps.reasoning)    score += 20;
        score += caps.codingScore * 5.0;
        break;

      case IdeTask.visionAnalysis:
        if (caps.vision) score += 80;
        score += caps.codingScore * 4.0;
        break;

      case IdeTask.mathReasoning:
        if (caps.reasoning)   score += 50;
        score += caps.codingScore * 5.0;
        if (caps.toolCalling) score += 10;
        break;

      case IdeTask.generalChat:
        score += 30; // base pour tout modèle
        if (caps.contextLength >= 32768) score += 20;
        if (!caps.vision) score += 10;             // vision = overhead inutile
        score += caps.codingScore * 3.0;
        break;

      case IdeTask.codeReview:
        score += caps.codingScore * 16.0;          // coding ×16 (0-80)
        if (caps.contextLength >= 32768) score += 15;
        if (caps.reasoning) score += 5;
        break;

      case IdeTask.debugAssistance:
        score += caps.codingScore * 12.0;
        if (caps.reasoning)  score += 20;
        if (caps.toolCalling) score += 10;
        if (caps.vision)     score += 8;           // peut analyser screenshot
        break;
    }

    // Bonus LRU : préfère les modèles récemment utilisés (légère préférence)
    final daysSince = DateTime.now().difference(inst.lastUsedAt).inDays;
    if (daysSince < 7) score += 5;

    return score.clamp(0, 100);
  }

  static String _reason(AiModelEntry entry, IdeTask task, double score) {
    final caps = entry.capabilities;
    final parts = <String>[];
    switch (task) {
      case IdeTask.codeCompletion:
        parts.add('coding ${caps.codingScore}/5');
        break;
      case IdeTask.agentChat:
        if (caps.toolCalling) parts.add('tool calling ✓');
        if (caps.reasoning)   parts.add('reasoning ✓');
        break;
      case IdeTask.visionAnalysis:
        if (caps.vision) parts.add('vision ✓');
        break;
      case IdeTask.mathReasoning:
        if (caps.reasoning) parts.add('reasoning ✓');
        break;
      default:
        parts.add('score ${score.toInt()}/100');
    }
    return '${entry.name} — ${parts.join(", ")}';
  }

  static AiModelEntry? _findEntry(ModelCatalog catalog, String modelId) {
    try {
      return catalog.models.firstWhere((m) => m.id == modelId);
    } catch (_) {
      return null;
    }
  }
}

// ── Interne ───────────────────────────────────────────────────────────────────

class _Candidate {
  final AiModelEntry  entry;
  final InstalledModel installed;
  final double         score;
  const _Candidate({
    required this.entry,
    required this.installed,
    required this.score,
  });
}
