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
// The active workspace is always app-private. Shared storage is an explicit
// import/export location because FUSE-backed public storage does not preserve
// the POSIX semantics required by git, npm and APK tooling.
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
const downloadsDir = "/storage/emulated/0/Android/data/com.panda.ide/files/data/user/0/com.panda.ide/files";
