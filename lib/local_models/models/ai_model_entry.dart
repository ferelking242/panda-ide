/// Modèles de données du catalogue Local AI.
///
/// AiModelEntry   — une fiche complète (toutes quantizations incluses)
/// ModelQuant     — une quantization spécifique (taille, hash, lien HF)
/// ModelCapabilities — ce que le modèle sait faire
/// InstalledModel  — un modèle téléchargé sur l'appareil
library;

// ── Quantization ──────────────────────────────────────────────────────────────

class ModelQuant {
  final String level;         // "Q4_K_M", "Q8_0", "Q2_K"…
  final double sizeGb;        // taille du fichier en GB
  final String hfFilename;    // nom du fichier sur HuggingFace
  final String sha256;        // hash SHA256 (peut être vide si non connu)
  final int    minRamGb;      // RAM minimale recommandée pour ce niveau

  const ModelQuant({
    required this.level,
    required this.sizeGb,
    required this.hfFilename,
    required this.sha256,
    required this.minRamGb,
  });

  factory ModelQuant.fromJson(Map<String, dynamic> j) => ModelQuant(
    level:       j['level'] as String,
    sizeGb:      (j['size_gb'] as num).toDouble(),
    hfFilename:  j['hf_filename'] as String,
    sha256:      j['sha256'] as String? ?? '',
    minRamGb:    j['min_ram_gb'] as int? ?? 4,
  );

  /// Label court pour l'UI
  String get sizeLabel {
    if (sizeGb >= 1) return '${sizeGb.toStringAsFixed(1)} GB';
    return '${(sizeGb * 1024).round()} MB';
  }
}

// ── Capacités ─────────────────────────────────────────────────────────────────

class ModelCapabilities {
  final bool toolCalling;
  final bool vision;
  final bool reasoning;
  final int  contextLength;    // tokens
  final int  codingScore;      // 0-5
  final int  minRamGb;

  const ModelCapabilities({
    required this.toolCalling,
    required this.vision,
    required this.reasoning,
    required this.contextLength,
    required this.codingScore,
    required this.minRamGb,
  });

  factory ModelCapabilities.fromJson(Map<String, dynamic> j) => ModelCapabilities(
    toolCalling:   j['tool_calling'] as bool? ?? false,
    vision:        j['vision'] as bool? ?? false,
    reasoning:     j['reasoning'] as bool? ?? false,
    contextLength: j['context_length'] as int? ?? 4096,
    codingScore:   j['coding_score'] as int? ?? 3,
    minRamGb:      j['min_ram_gb'] as int? ?? 4,
  );

  String get contextLabel {
    if (contextLength >= 131072) return '128K';
    if (contextLength >= 65536)  return '64K';
    if (contextLength >= 32768)  return '32K';
    if (contextLength >= 16384)  return '16K';
    return '${(contextLength / 1024).round()}K';
  }

  String get codingStars => '⭐' * codingScore + '☆' * (5 - codingScore);
}

// ── Fiche modèle principale ───────────────────────────────────────────────────

class AiModelEntry {
  final String id;
  final String name;
  final String author;
  final String hfRepo;         // ex: "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF"
  final String description;
  final List<String> categories; // "coding", "general", "reasoning", "vision", "tool_calling"
  final List<String> tags;
  final ModelCapabilities capabilities;
  final List<ModelQuant> quantizations;
  final DateTime? releasedAt;

  const AiModelEntry({
    required this.id,
    required this.name,
    required this.author,
    required this.hfRepo,
    required this.description,
    required this.categories,
    required this.tags,
    required this.capabilities,
    required this.quantizations,
    this.releasedAt,
  });

  factory AiModelEntry.fromJson(Map<String, dynamic> j) => AiModelEntry(
    id:          j['id'] as String,
    name:        j['name'] as String,
    author:      j['author'] as String,
    hfRepo:      j['hf_repo'] as String,
    description: j['description'] as String? ?? '',
    categories:  List<String>.from(j['categories'] as List? ?? []),
    tags:        List<String>.from(j['tags'] as List? ?? []),
    capabilities: ModelCapabilities.fromJson(
        j['capabilities'] as Map<String, dynamic>? ?? {}),
    quantizations: (j['quantizations'] as List? ?? [])
        .map((q) => ModelQuant.fromJson(q as Map<String, dynamic>))
        .toList(),
    releasedAt: j['released_at'] != null
        ? DateTime.tryParse(j['released_at'] as String)
        : null,
  );

  /// Quantization recommandée selon la RAM dispo
  ModelQuant? recommendedQuant(int ramGb) {
    // Essaie Q4_K_M d'abord, puis Q4_K_S, puis la plus légère compatible
    final ordered = [...quantizations]
      ..sort((a, b) => b.sizeGb.compareTo(a.sizeGb));
    for (final q in ordered) {
      if (q.minRamGb <= ramGb) return q;
    }
    return quantizations.isNotEmpty ? quantizations.last : null;
  }

  /// Score de compatibilité 0-100 avec le profil
  int compatibilityScore(int ramGb) {
    if (capabilities.minRamGb > ramGb) return 0;
    final headroom = ramGb - capabilities.minRamGb;
    final base = (headroom / ramGb * 100).clamp(0, 100).toInt();
    return base;
  }

  bool get isNew {
    if (releasedAt == null) return false;
    return DateTime.now().difference(releasedAt!).inDays <= 30;
  }

  bool hasCategory(String cat) => categories.contains(cat);

  String get hfUrl => 'https://huggingface.co/$hfRepo';
}

// ── Catalogue ─────────────────────────────────────────────────────────────────

class ModelCatalog {
  final String version;
  final DateTime fetchedAt;
  final List<AiModelEntry> models;

  const ModelCatalog({
    required this.version,
    required this.fetchedAt,
    required this.models,
  });

  factory ModelCatalog.fromJson(Map<String, dynamic> j) => ModelCatalog(
    version:   j['version'] as String? ?? '0',
    fetchedAt: DateTime.now(),
    models:    (j['models'] as List? ?? [])
        .map((m) => AiModelEntry.fromJson(m as Map<String, dynamic>))
        .toList(),
  );

  List<AiModelEntry> forCategory(String cat) =>
      models.where((m) => m.hasCategory(cat)).toList();

  List<AiModelEntry> recommended(int ramGb) => models
      .where((m) => m.capabilities.minRamGb <= ramGb)
      .toList()
    ..sort((a, b) => b.compatibilityScore(ramGb)
        .compareTo(a.compatibilityScore(ramGb)));

  List<AiModelEntry> get newModels =>
      models.where((m) => m.isNew).toList();
}

// ── Modèle installé ───────────────────────────────────────────────────────────

class InstalledModel {
  final String modelId;
  final String quantLevel;
  final String filePath;
  final double sizeGb;
  final String storage;     // "internal" | "sdcard"
  final DateTime installedAt;
  DateTime lastUsedAt;

  InstalledModel({
    required this.modelId,
    required this.quantLevel,
    required this.filePath,
    required this.sizeGb,
    required this.storage,
    required this.installedAt,
    required this.lastUsedAt,
  });

  factory InstalledModel.fromJson(Map<String, dynamic> j) => InstalledModel(
    modelId:     j['model_id'] as String,
    quantLevel:  j['quant_level'] as String,
    filePath:    j['file_path'] as String,
    sizeGb:      (j['size_gb'] as num).toDouble(),
    storage:     j['storage'] as String? ?? 'internal',
    installedAt: DateTime.parse(j['installed_at'] as String),
    lastUsedAt:  DateTime.parse(j['last_used_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'model_id':     modelId,
    'quant_level':  quantLevel,
    'file_path':    filePath,
    'size_gb':      sizeGb,
    'storage':      storage,
    'installed_at': installedAt.toIso8601String(),
    'last_used_at': lastUsedAt.toIso8601String(),
  };
}
