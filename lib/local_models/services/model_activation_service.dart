/// ModelActivationService — enregistre un modèle GGUF installé comme provider IA.
///
/// Remplace le `GgufModel.registerGgufModelWithAI` existant (qui hardcode
/// threads=4, ctx=4096, gpuLayers=0) par une version qui utilise
/// InferenceConfigService pour des valeurs optimales.
///
/// Après l'activation, le modèle apparaît dans l'agent Panda et peut être
/// sélectionné comme modèle actif de chat / complétion.
library;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_model_entry.dart';
import '../models/device_profile.dart';
import '../services/model_download_manager.dart';
import 'inference_config_service.dart';



// ── Résultat de l'activation ──────────────────────────────────────────────────

class ActivationResult {
  final String modelId;           // clé dans aiConfig
  final bool   alreadyExisted;
  final InferenceConfig config;   // paramètres calculés
  final bool   setAsDefault;      // si le modèle a été mis comme défaut chat

  const ActivationResult({
    required this.modelId,
    required this.alreadyExisted,
    required this.config,
    required this.setAsDefault,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class ModelActivationService {

  /// Enregistre un modèle installé dans la config IA de Panda.
  ///
  /// [modelEntry]  — fiche du modèle (depuis le catalogue)
  /// [quantLevel]  — quantization sélectionnée
  /// [profile]     — profil matériel pour le calcul des paramètres
  /// [setAsDefault] — si true, sélectionne ce modèle comme défaut chat
  static Future<ActivationResult> activate({
    required AiModelEntry  modelEntry,
    required String        quantLevel,
    required DeviceProfile profile,
    bool setAsDefault = false,
  }) async {
    // Récupère le chemin du fichier installé
    final installed = ModelDownloadManager.instance
        .getInstalled(modelEntry.id)
        .firstWhere(
          (m) => m.quantLevel == quantLevel,
          orElse: () => throw StateError(
              'Modèle ${modelEntry.id} $quantLevel non installé'),
        );

    // Trouve la fiche de la quantization pour calculer la config
    final quant = modelEntry.quantizations.firstWhere(
        (q) => q.level == quantLevel,
        orElse: () => throw StateError('Quantization $quantLevel non trouvée'));

    final config = InferenceConfigService.compute(
      model:   modelEntry,
      quant:   quant,
      profile: profile,
    );

    final prefs = await SharedPreferences.getInstance();
    final aiConfigStr = prefs.getString('aiConfig') ?? '{}';
    final Map<String, dynamic> aiConfig =
        Map<String, dynamic>.from(jsonDecode(aiConfigStr) as Map);

    // Vérifie si ce chemin existe déjà
    final existingEntry = aiConfig.entries.firstWhere(
      (e) =>
          e.value is Map &&
          (e.value as Map)['provider'] == 'LocalLlama' &&
          (e.value as Map)['modelPath'] == installed.filePath,
      orElse: () => const MapEntry('', null),
    );

    final bool alreadyExisted = existingEntry.key.isNotEmpty;
    final String modelId = alreadyExisted
        ? existingEntry.key
        : 'LocalLlama-${modelEntry.id}-${quantLevel.replaceAll("_", "").toLowerCase()}';

    // Construit / met à jour l'entrée
    aiConfig[modelId] = {
      'provider':    'LocalLlama',
      'apiProvider': 'LocalLlama',
      'modelName':   '${modelEntry.name} $quantLevel',
      'model':       '${modelEntry.name} $quantLevel',
      'modelPath':   installed.filePath,
      ...config.toConfigMap(),
      // Métadonnées supplémentaires (non utilisées par LocalLlamaBloc mais
      // utiles pour l'UI agent_settings)
      'pandaModelId':     modelEntry.id,
      'pandaModelAuthor': modelEntry.author,
      'pandaQuantLevel':  quantLevel,
    };

    await prefs.setString('aiConfig', jsonEncode(aiConfig));

    // Mise à jour de la date de dernier usage
    installed.lastUsedAt = DateTime.now();

    // Sélection comme modèle par défaut (si demandé ou si c'est le premier)
    final modelSelectedStr = prefs.getString('modelSelected') ?? '{}';
    final Map<String, dynamic> modelSelected =
        Map<String, dynamic>.from(jsonDecode(modelSelectedStr) as Map);

    bool setDefault = false;
    if (setAsDefault || (modelSelected['chat'] as String? ?? '').isEmpty) {
      modelSelected['chat'] = modelId;
      await prefs.setString('modelSelected', jsonEncode(modelSelected));
      setDefault = true;
    }

    return ActivationResult(
      modelId:       modelId,
      alreadyExisted: alreadyExisted,
      config:        config,
      setAsDefault:  setDefault,
    );
  }

  /// Vérifie si un modèle installé est déjà enregistré dans la config IA.
  static Future<bool> isActivated({
    required String modelId,
    required String quantLevel,
  }) async {
    final installed = ModelDownloadManager.instance
        .getInstalled(modelId)
        .where((m) => m.quantLevel == quantLevel)
        .toList();
    if (installed.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final aiConfigStr = prefs.getString('aiConfig') ?? '{}';
    final Map<String, dynamic> aiConfig =
        Map<String, dynamic>.from(jsonDecode(aiConfigStr) as Map);

    return aiConfig.values.any(
      (v) =>
          v is Map &&
          v['provider'] == 'LocalLlama' &&
          v['modelPath'] == installed.first.filePath,
    );
  }

  /// Désactive (supprime) un modèle de la config IA.
  static Future<void> deactivate({
    required String modelId,
    required String quantLevel,
  }) async {
    final installed = ModelDownloadManager.instance
        .getInstalled(modelId)
        .where((m) => m.quantLevel == quantLevel)
        .toList();
    if (installed.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final aiConfigStr = prefs.getString('aiConfig') ?? '{}';
    final Map<String, dynamic> aiConfig =
        Map<String, dynamic>.from(jsonDecode(aiConfigStr) as Map);

    aiConfig.removeWhere(
      (k, v) =>
          v is Map &&
          v['provider'] == 'LocalLlama' &&
          v['modelPath'] == installed.first.filePath,
    );

    await prefs.setString('aiConfig', jsonEncode(aiConfig));
  }
}
