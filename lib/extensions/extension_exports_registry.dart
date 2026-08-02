/// ExtensionExportsRegistry — vscode.extensions.* inter-extension API — Phase 6.
///
/// Stocke les exports retournés par activate() de chaque extension active.
/// Permet à une extension d'accéder aux APIs publiques d'une autre via
/// vscode.extensions.getExtension('id').exports
library;

// ── ExtensionExportsRegistry ──────────────────────────────────────────────

class ExtensionExportsRegistry {
  static final ExtensionExportsRegistry instance =
      ExtensionExportsRegistry._();
  ExtensionExportsRegistry._();

  /// exports par extensionId
  final Map<String, dynamic> _exports = {};

  /// Métadonnées légères (id, version, isActive, extensionPath)
  final Map<String, Map<String, dynamic>> _metadata = {};

  // ── Enregistrement ────────────────────────────────────────────────────────

  void register({
    required String extensionId,
    required String version,
    required String extensionPath,
    dynamic exports,
  }) {
    _exports[extensionId]  = exports;
    _metadata[extensionId] = {
      'id':            extensionId,
      'version':       version,
      'extensionPath': extensionPath,
      'isActive':      true,
      'packageJSON':   <String, dynamic>{}, // rempli par ExtensionHostManager si besoin
    };
  }

  void unregister(String extensionId) {
    _exports.remove(extensionId);
    _metadata.remove(extensionId);
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  /// Retourne l'objet Extension sérialisable (pour JSON IPC).
  Map<String, dynamic>? getExtensionJson(String extensionId) {
    final meta = _metadata[extensionId];
    if (meta == null) return null;
    return {
      ...meta,
      'exports': _exports[extensionId],
    };
  }

  /// Retourne les exports bruts d'une extension (null si non active).
  dynamic getExports(String extensionId) => _exports[extensionId];

  /// Retourne toutes les métadonnées (pour vscode.extensions.all).
  List<Map<String, dynamic>> getAll() => _metadata.values.toList();

  bool isActive(String extensionId) => _metadata.containsKey(extensionId);

  // ── Mise à jour des packageJSON ───────────────────────────────────────────

  void setPackageJson(String extensionId, Map<String, dynamic> packageJson) {
    final meta = _metadata[extensionId];
    if (meta != null) {
      meta['packageJSON'] = packageJson;
    }
  }
}
