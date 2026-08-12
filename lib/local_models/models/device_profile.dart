/// DeviceProfile — résultat du scan matériel de l'appareil Android.
///
/// Collecté une fois au premier lancement (puis mis en cache dans SharedPreferences).
/// Utilisé par le catalogue pour filtrer et trier les modèles recommandés.
library;

class DeviceProfile {
  // ── CPU ────────────────────────────────────────────────────────────────────
  final String cpuArch;        // arm64-v8a, x86_64, armeabi-v7a
  final int    cpuCores;       // nombre total de cœurs
  final int    cpuFreqMHz;     // fréquence max détectée (MHz)
  final List<String> cpuFeatures; // neon, sve, sve2, sme, dotprod, i8mm…

  // ── RAM ───────────────────────────────────────────────────────────────────
  final int totalRamMb;        // RAM totale (MB)
  final int availableRamMb;    // RAM libre au moment du scan

  // ── Stockage ──────────────────────────────────────────────────────────────
  final int internalFreeGb;    // stockage interne libre (GB)
  final int sdCardFreeGb;      // SD card libre (0 = pas de SD)
  final bool sdCardWritable;

  // ── GPU ───────────────────────────────────────────────────────────────────
  final String gpuHint;        // "adreno", "mali", "powervr", "unknown"
  final bool vulkanSupported;  // heuristique: Android 7+ arm64

  // ── Score global (0-100) ──────────────────────────────────────────────────
  final int performanceScore;

  const DeviceProfile({
    required this.cpuArch,
    required this.cpuCores,
    required this.cpuFreqMHz,
    required this.cpuFeatures,
    required this.totalRamMb,
    required this.availableRamMb,
    required this.internalFreeGb,
    required this.sdCardFreeGb,
    required this.sdCardWritable,
    required this.gpuHint,
    required this.vulkanSupported,
    required this.performanceScore,
  });

  factory DeviceProfile.unknown() => const DeviceProfile(
    cpuArch: 'unknown',
    cpuCores: 4,
    cpuFreqMHz: 1800,
    cpuFeatures: [],
    totalRamMb: 4096,
    availableRamMb: 1500,
    internalFreeGb: 8,
    sdCardFreeGb: 0,
    sdCardWritable: false,
    gpuHint: 'unknown',
    vulkanSupported: false,
    performanceScore: 30,
  );

  /// RAM totale en GB (plafond vers taille standard) — Android rapporte ~6-10%
  /// de moins que la RAM nominale (ex: Samsung S21 8GB → ~7.3-7.5 GB dans
  /// /proc/meminfo). On arrondit au plafond pour ne pas bloquer les modèles
  /// qui tiendraient réellement en mémoire.
  int get totalRamGb {
    // Plafond au GB entier, puis snap vers la taille standard ≥
    final gbCeil = (totalRamMb / 1024).ceil();
    for (final s in const [2, 3, 4, 6, 8, 10, 12, 16, 24, 32]) {
      if (gbCeil <= s) return s;
    }
    return gbCeil;
  }

  /// Indique si le GPU offload est probablement disponible
  bool get gpuOffloadAvailable => vulkanSupported && gpuHint != 'unknown';

  /// Taille max recommandée de modèle selon la RAM totale
  int get recommendedMaxModelSizeGb {
    if (totalRamGb >= 16) return 8;
    if (totalRamGb >= 12) return 6;
    if (totalRamGb >= 8)  return 4;
    if (totalRamGb >= 6)  return 2;
    return 1;
  }

  /// Quantization recommandée par défaut
  String get recommendedQuant {
    if (totalRamGb >= 12) return 'Q4_K_M';
    if (totalRamGb >= 8)  return 'Q4_K_M';
    if (totalRamGb >= 6)  return 'Q4_K_S';
    return 'Q4_K_S';
  }

  /// Label friendly du niveau de performance
  String get performanceLabel {
    if (performanceScore >= 80) return 'Excellent ⚡';
    if (performanceScore >= 60) return 'Bon ✅';
    if (performanceScore >= 40) return 'Correct 🟡';
    return 'Limité 🔴';
  }

  Map<String, dynamic> toJson() => {
    'cpuArch': cpuArch,
    'cpuCores': cpuCores,
    'cpuFreqMHz': cpuFreqMHz,
    'cpuFeatures': cpuFeatures,
    'totalRamMb': totalRamMb,
    'availableRamMb': availableRamMb,
    'internalFreeGb': internalFreeGb,
    'sdCardFreeGb': sdCardFreeGb,
    'sdCardWritable': sdCardWritable,
    'gpuHint': gpuHint,
    'vulkanSupported': vulkanSupported,
    'performanceScore': performanceScore,
  };

  factory DeviceProfile.fromJson(Map<String, dynamic> j) => DeviceProfile(
    cpuArch:        j['cpuArch'] as String? ?? 'unknown',
    cpuCores:       j['cpuCores'] as int? ?? 4,
    cpuFreqMHz:     j['cpuFreqMHz'] as int? ?? 1800,
    cpuFeatures:    List<String>.from(j['cpuFeatures'] as List? ?? []),
    totalRamMb:     j['totalRamMb'] as int? ?? 4096,
    availableRamMb: j['availableRamMb'] as int? ?? 1500,
    internalFreeGb: j['internalFreeGb'] as int? ?? 8,
    sdCardFreeGb:   j['sdCardFreeGb'] as int? ?? 0,
    sdCardWritable: j['sdCardWritable'] as bool? ?? false,
    gpuHint:        j['gpuHint'] as String? ?? 'unknown',
    vulkanSupported:j['vulkanSupported'] as bool? ?? false,
    performanceScore: j['performanceScore'] as int? ?? 30,
  );
}
