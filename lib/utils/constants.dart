import 'package:flutter/foundation.dart';

// ── App private directories (no special permission needed) ────────────────────
const appDir = "/data/data/com.panda.ide";
const binDir = "$appDir/bin";
const libDir = "$appDir/lib";
const certDir = "$appDir/certs";
const runtimesDir = "$appDir/runtimes";
const tempDir = "$appDir/temps";
const extensionDir = "$appDir/extensions";
const homeDir = "$appDir/Home";

// ── Panda IDE storage roots ──────────────────────────────────────────────────
// Public storage is used when MANAGE_EXTERNAL_STORAGE is granted. Until then
// the mutable active roots point to app-private storage, which is available
// during the very first launch.
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

void usePublicStorageRoots() {
  pandaRootDir = publicPandaRootDir;
  projectDir = publicProjectDir;
  templateDir = publicTemplateDir;
  filesDir = publicFilesDir;
  pandaLogsDir = publicPandaLogsDir;
}

// Legacy download cache (app-private, no permission needed)
const downloadsDir = "/storage/emulated/0/Android/data/com.panda.ide/files/data/user/0/com.panda.ide/files";

class EditorStatusInfo {
  final String lineCol;
  final String language;
  const EditorStatusInfo({required this.lineCol, required this.language});
}

final globalEditorStatusNotifier = ValueNotifier<EditorStatusInfo?>(null);
final globalToolbarVisibleNotifier = ValueNotifier<bool>(true);

