/// InferenceConfigService — calcule les paramètres optimaux llama.cpp.
///
/// Remplace les valeurs codées en dur (threads=4, ctx=4096, gpuLayers=0)
/// par des valeurs adaptées au matériel détecté.
///
/// Principe :
///   • threads    → performance cores - 2 (min 1), pour laisser de la place à l'UI
///   • contextSize → basé sur la RAM disponible et la taille du modèle
///   • gpuLayers  → 0 (déclenche l'auto-détection GPU du LocalLlamaBloc)
///   • flashAttention → true si ARM SVE2 ou GPU Vulkan disponible
library;
import '../models/ai_model_entry.dart';
import '../models/device_profile.dart';



// ── Config calculée ───────────────────────────────────────────────────────────

class InferenceConfig {
  final int    threads;
  final int    contextSize;
  final int    gpuLayers;     // 0 = auto-détection via LlamaController.detectGpu()
  final bool   flashAttention;
  final int    batchSize;     // n_batch pour le prompt processing
  final String source;        // description de comment les valeurs ont été choisies

  const InferenceConfig({
    required this.threads,
    required this.contextSize,
    required this.gpuLayers,
    required this.flashAttention,
    required this.batchSize,
    required this.source,
  });

  /// Convertit en Map pour stockage dans aiConfig (SharedPreferences)
  Map<String, dynamic> toConfigMap() => {
    'threads':     threads,
    'contextSize': contextSize,
    'gpuLayers':   gpuLayers,
    'batchSize':   batchSize,
  };

  @override
  String toString() =>
      'InferenceConfig(threads=$threads, ctx=$contextSize, '
      'gpuLayers=$gpuLayers, flash=$flashAttention, batch=$batchSize)';
}

// ── Service ───────────────────────────────────────────────────────────────────

class InferenceConfigService {

  /// Calcule la config optimale pour un modèle sur l'appareil.
  static InferenceConfig compute({
    required AiModelEntry   model,
    required ModelQuant     quant,
    required DeviceProfile  profile,
  }) {
    final threads     = _calcThreads(profile);
    final contextSize = _calcContextSize(model, quant, profile);
    final flash       = _hasFlashAttention(profile);
    final batch       = _calcBatchSize(profile);

    final src = 'Auto: ${profile.cpuCores} cœurs → $threads threads, '
                '${profile.totalRamGb}GB RAM → ctx $contextSize'
                '${flash ? ", Flash Attention" : ""}';

    return InferenceConfig(
      threads:        threads,
      contextSize:    contextSize,
      gpuLayers:      0,   // 0 = auto via LlamaController.detectGpu()
      flashAttention: flash,
      batchSize:      batch,
      source:         src,
    );
  }

  // ── Threads ────────────────────────────────────────────────────────────────

  /// Alloue les cœurs CPU à llama.cpp en laissant 2 cœurs pour l'UI.
  ///
  /// Sur un SoC ARM moderne (Snapdragon, Dimensity) il y a typiquement
  /// 4 "big" cœurs performants + 4 "little" efficaces.
  /// llama.cpp bénéficie surtout des big cœurs → on prend tous sauf 2.
  static int _calcThreads(DeviceProfile profile) {
    final cores = profile.cpuCores;
    if (cores <= 2) return 1;
    if (cores <= 4) return cores - 1;   // 3 ou 4 cœurs → on garde 1 pour UI
    if (cores <= 6) return cores - 2;   // 4 threads
    return cores - 2;                    // 8 cœurs → 6 threads (bon compromis)
  }

  // ── Contexte ───────────────────────────────────────────────────────────────

  /// Calcule la taille de contexte en tenant compte de la RAM disponible.
  ///
  /// Le KV cache occupe environ : 2 * n_layers * n_kv_heads * head_dim * ctx * dtype_bytes
  /// Approximation pratique : ~0.5 MB par 1K tokens pour un modèle 7B Q4.
  /// On cible 20% de la RAM disponible au maximum pour le KV cache.
  static int _calcContextSize(
      AiModelEntry model, ModelQuant quant, DeviceProfile profile) {

    final ramGb     = profile.totalRamGb;
    final modelGb   = quant.sizeGb;
    final freeAfter = (ramGb - modelGb).clamp(0.0, double.infinity);

    // Taille max du contexte supportée par le modèle
    final modelMaxCtx = model.capabilities.contextLength;

    // Budget KV cache ≈ 20% de la RAM restante après chargement du modèle
    final kvBudgetMb = freeAfter * 1024 * 0.20;

    // ~0.5 MB / 1K tokens pour un 7B Q4 (heuristique conservative)
    final maxCtxFromRam = (kvBudgetMb / 0.5 * 1024).toInt();

    // On retourne le plus petit des deux, arrondi aux puissances de 2
    final target = maxCtxFromRam.clamp(512, modelMaxCtx);
    return _roundToPow2(target);
  }

  static int _roundToPow2(int value) {
    const options = [512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072];
    int result = 512;
    for (final o in options) {
      if (o <= value) {
        result = o;
      } else {
        break;
      }
    }
    return result;
  }

  // ── Flash Attention ───────────────────────────────────────────────────────

  /// Flash Attention est utile sur : GPU Vulkan, SVE2, i8mm.
  /// Réduit la mémoire du KV cache et accélère les longs contextes.
  static bool _hasFlashAttention(DeviceProfile profile) {
    if (profile.vulkanSupported) return true;
    final f = profile.cpuFeatures;
    return f.contains('sve2') || f.contains('sme') || f.contains('i8mm');
  }

  // ── Batch size ────────────────────────────────────────────────────────────

  /// n_batch contrôle combien de tokens sont traités en parallèle pendant
  /// le prefill (traitement du prompt). Plus grand = plus rapide mais plus RAM.
  static int _calcBatchSize(DeviceProfile profile) {
    final ramGb = profile.totalRamGb;
    if (ramGb >= 12) return 1024;
    if (ramGb >= 8)  return 512;
    if (ramGb >= 6)  return 256;
    return 128;
  }

  // ── Résumé lisible ────────────────────────────────────────────────────────

  /// Retourne un résumé des choix pour affichage dans l'UI.
  static List<String> summary(InferenceConfig cfg, DeviceProfile profile) {
    return [
      '${cfg.threads} threads CPU (${profile.cpuCores} cœurs détectés)',
      'Contexte : ${_ctxLabel(cfg.contextSize)}',
      'GPU layers : auto (LlamaController.detectGpu)',
      if (cfg.flashAttention) 'Flash Attention : activé ✅',
      'Batch size : ${cfg.batchSize}',
    ];
  }

  static String _ctxLabel(int ctx) {
    if (ctx >= 65536)  return '${ctx ~/ 1024}K tokens';
    if (ctx >= 1024)   return '${ctx ~/ 1024}K tokens';
    return '$ctx tokens';
  }
}
