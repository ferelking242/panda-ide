/// Environment helpers for Flutter/Dart Pub inside the PRoot Linux session.
///
/// Pub keeps Git checkouts in a shared cache. On Android/PRoot, reusing that
/// cache across unrelated workspaces can make a failed checkout look like a
/// missing pubspec in a different repository. Every workspace therefore gets
/// a stable, private cache namespace.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'flutter_pub_manifest.dart';

class FlutterPubEnvironment {
  FlutterPubEnvironment._();

  static const String cacheRoot = '/root/.panda-pub-cache';
  // Bump this when the cache layout or invalidation rules change. This
  // invalidates caches created by older Panda builds without touching the
  // user's project or lockfile.
  static const String cacheVersion = 'v2';

  /// Returns a deterministic, path-safe cache key on both native and web.
  ///
  /// The dependency manifests are part of the key. A changed Git ref or
  /// resolved commit therefore gets a fresh Pub Git cache instead of reusing
  /// a possibly incomplete checkout from the previous lockfile.
  static String cacheKeyForProject(String projectPath) {
    final normalized = projectPath.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return 'default-$cacheVersion';

    final manifestBytes = <int>[];
    manifestBytes.addAll(readPubManifestBytes(normalized));

    final digest = sha1.convert(<int>[
      ...utf8.encode(normalized),
      0,
      ...manifestBytes,
    ]).toString();
    return '$cacheVersion-${digest.substring(0, 16)}';
  }

  static String cachePathForProject(String projectPath) =>
      '$cacheRoot/${cacheKeyForProject(projectPath)}';

  /// Variables that must be present in every Flutter-capable guest shell.
  static Map<String, String> forProject(String projectPath) {
    return <String, String>{
      'PUB_CACHE': cachePathForProject(projectPath),
      // Do not inherit a host-specific mirror from Panda's Android process.
      'PUB_HOSTED_URL': 'https://pub.dev',
      'FLUTTER_SUPPRESS_ANALYTICS': 'true',
    };
  }

  /// Shell command used by the device runner. It keeps the original Pub exit
  /// code while making the isolation and the next diagnostic step visible.
  static String flutterRunCommand({
    required String projectPath,
    required String dartTarget,
  }) {
    final cachePath = cachePathForProject(projectPath);
    return '''
cd /root/workspace 2>/dev/null || exit 1
mkdir -p "\$PUB_CACHE"
echo "[Panda] Pub cache isolé: \$PUB_CACHE"
flutter pub get
pub_status=\$?
if [ "\$pub_status" -ne 0 ]; then
  echo "[Panda] flutter pub get a échoué dans ce workspace."
  echo "[Panda] Le cache isolé peut être réparé avec: rm -rf $cachePath && flutter pub get"
  exit "\$pub_status"
fi
exec flutter run $dartTarget
''';
  }
}