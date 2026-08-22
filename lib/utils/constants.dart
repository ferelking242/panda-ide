// App private directories (resolved at startup via path_provider)
import 'dart:io' if (dart.library.js_interop) '../web/io_stub.dart';
Starts with default, overwritten by resolveAppDir() in configureStorageRoots().
String appDir = "/data/data/com.panda.ide";
String binDir = "$appDir/bin";
String libDir = "$appDir/lib";
String certDir = "$appDir/certs";
String runtimesDir = "$appDir/runtimes";
String tempDir = "$appDir/temps";
String extensionDir = "$appDir/extensions";
String homeDir = "$appDir/Home";

/// Resolve all app paths from the actual accessible base directory.
/// Called by configureStorageRoots() at startup.
void resolveAppDir(String basePath) {
  appDir = basePath;
  binDir = "$appDir/bin";
  libDir = "$appDir/lib";
  certDir = "$appDir/certs";
  runtimesDir = "$appDir/runtimes";
  tempDir = "$appDir/temps";
  extensionDir = "$appDir/extensions";
  homeDir = "$appDir/Home";
}

// ── Panda IDE storage roots ──────────────────────────────────────────────────
const publicPandaRootDir = "/storage/emulated/0/Panda IDE";
const publicProjectDir = "$publicPandaRootDir/Projects";
const publicTemplateDir = "$publicPandaRootDir/Templates";
const publicFilesDir = "$publicPandaRootDir/Files";
const publicPandaLogsDir = "$publicPandaRootDir/Logs";

String pandaRootDir = "$appDir/UserFiles";
String projectDir = "$pandaRootDir/Projects";
String templateDir = "$pandaRootDir/Templates";
String filesDir = "$pandaRootDir/Files";
String pandaLogsDir = "$pandaRootDir/Logs";

void usePrivateStorageRoots() {
  pandaRootDir = "$appDir/UserFiles";
  projectDir = "$pandaRootDir/Projects";
  templateDir = "$pandaRootDir/Templates";
  filesDir = "$pandaRootDir/Files";
  pandaLogsDir = "$pandaRootDir/Logs";
}

// Legacy download cache (app-private, no permission needed)
String downloadsDir = "$appDir/downloads";

// ── Additional storage paths ────────────────────────────────────────────────
String modelsDir = "$appDir/models";
String downloadsCacheDir = "$appDir/downloads";
String pandaTempCacheDir = "$appDir/.cache";

/// Create all storage directories at startup.
Future<void> createAllStorageDirs() async {
  for (final dir in [
    Directory(appDir),
    Directory(binDir),
    Directory(libDir),
    Directory(certDir),
    Directory(runtimesDir),
    Directory(tempDir),
    Directory(extensionDir),
    Directory(homeDir),
    Directory(pandaRootDir),
    Directory(projectDir),
    Directory(templateDir),
    Directory(filesDir),
    Directory(pandaLogsDir),
    Directory(modelsDir),
    Directory(downloadsCacheDir),
    Directory(pandaTempCacheDir),
  ]) {
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
  }
}
