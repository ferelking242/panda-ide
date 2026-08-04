// Web stub — llama_flutter_android (dart:ffi) is not available on web.
// Provides empty/no-op implementations of every class the codebase uses.

class RustLib {
  static Future<void> init() async {}
}

class GpuInfo {
  final int recommendedGpuLayers;
  const GpuInfo({this.recommendedGpuLayers = 0});
}

class LlamaController {
  Future<GpuInfo> detectGpu() async => const GpuInfo();

  Future<void> loadModel({
    required String modelPath,
    int threads = 4,
    int contextSize = 2048,
    int gpuLayers = 0,
  }) async {}

  Stream<String> generate({
    required String prompt,
    int maxTokens = 256,
    double temperature = 0.7,
    double topP = 0.9,
    int topK = 40,
    double repeatPenalty = 1.1,
    double frequencyPenalty = 0.0,
    double presencePenalty = 0.0,
    int repeatLastN = 64,
    int seed = -1,
    int mirostat = 0,
    double mirostatTau = 5.0,
    double mirostatEta = 0.1,
  }) async* {}

  Future<void> stop() async {}
  Future<void> dispose() async {}
}
