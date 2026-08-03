// ── App private directories (no special permission needed) ────────────────────
const appDir = "/data/data/com.panda.ide";
const binDir = "$appDir/bin";
const libDir = "$appDir/lib";
const certDir = "$appDir/certs";
const runtimesDir = "$appDir/runtimes";
const tempDir = "$appDir/temps";
const extensionDir = "$appDir/extensions";
const homeDir = "$appDir/Home";

// ── Panda IDE public folder — user-accessible at storage root ─────────────────
//    /storage/emulated/0/Panda IDE/
//    Requires MANAGE_EXTERNAL_STORAGE (Android 11+) to create at this level.
const pandaRootDir    = "/storage/emulated/0/Panda IDE";
const projectDir      = "$pandaRootDir/Projects";
const templateDir     = "$pandaRootDir/Templates";
const filesDir        = "$pandaRootDir/Files";
const pandaLogsDir    = "$pandaRootDir/Logs";

// Legacy download cache (app-private, no permission needed)
const downloadsDir = "/storage/emulated/0/Android/data/com.panda.ide/files/data/user/0/com.panda.ide/files";
