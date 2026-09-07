import 'flutter_pub_manifest_stub.dart'
    if (dart.library.io) 'flutter_pub_manifest_io.dart' as implementation;

/// Reads the dependency manifests when the app has native filesystem access.
///
/// The conditional import keeps the shared cache-key code compilable for web.
List<int> readPubManifestBytes(String projectPath) =>
    implementation.readPubManifestBytes(projectPath);