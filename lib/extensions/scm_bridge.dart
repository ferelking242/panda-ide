/// Bridge vscode.scm — Phase 10.
///
/// Permet aux extensions Git/SCM (GitLens, etc.) de créer des
/// Source Controls et d'afficher leur état dans l'IDE.
///
/// Architecture :
///   Extension appelle vscode.scm.createSourceControl(id, label, rootUri)
///   → SourceControl.dart gère les resourceGroups
///   → Flutter UI reflète les groupes / resources
import 'package:flutter/foundation.dart';

library;


// ── Modèles ────────────────────────────────────────────────────────────────

class ScmResource {
  final String resourceUri;     // file path
  final int decorations;        // bitmask (modified, staged, etc.)
  final String? tooltip;
  final String? letter;         // ex: 'M', 'A', 'D'
  final int? color;             // ARGB

  const ScmResource({
    required this.resourceUri,
    this.decorations = 0,
    this.tooltip,
    this.letter,
    this.color,
  });

  factory ScmResource.fromJson(Map<String, dynamic> json) => ScmResource(
    resourceUri: json['resourceUri'] as String? ?? '',
    decorations: (json['decorations'] as num?)?.toInt() ?? 0,
    tooltip: json['tooltip'] as String?,
    letter: json['letter'] as String?,
    color: (json['color'] as num?)?.toInt(),
  );
}

class ScmResourceGroup {
  final String id;
  String label;
  bool hideWhenEmpty;
  List<ScmResource> resources;

  ScmResourceGroup({
    required this.id,
    required this.label,
    this.hideWhenEmpty = false,
    this.resources = const [],
  });
}

class SourceControl {
  final String id;
  final String label;
  final String? rootUri;
  final String extensionId;
  String inputBoxValue = '';
  String inputBoxPlaceholder = 'Message';
  bool inputBoxVisible = true;

  final Map<String, ScmResourceGroup> _groups = {};

  SourceControl({
    required this.id,
    required this.label,
    this.rootUri,
    required this.extensionId,
  });

  List<ScmResourceGroup> get groups => _groups.values.toList();

  ScmResourceGroup createResourceGroup(String groupId, String label) {
    final group = ScmResourceGroup(id: groupId, label: label);
    _groups[groupId] = group;
    return group;
  }

  void updateResourceGroup(String groupId, List<dynamic> resources) {
    final group = _groups[groupId];
    if (group == null) return;
    group.resources = resources
        .whereType<Map<String, dynamic>>()
        .map(ScmResource.fromJson)
        .toList();
  }

  void dispose() {
    _groups.clear();
  }
}

// ── Bridge singleton ──────────────────────────────────────────────────────────

class ScmBridge extends ChangeNotifier {
  static final ScmBridge instance = ScmBridge._();
  ScmBridge._();

  final Map<String, SourceControl> _controls = {};
  int _scmCounter = 0;

  List<SourceControl> get all => _controls.values.toList();

  // ── API appelée depuis ExtensionApiRouter ─────────────────────────────────

  /// vscode.scm.createSourceControl(id, label, rootUri?)
  String createSourceControl({
    required String extensionId,
    required String id,
    required String label,
    String? rootUri,
  }) {
    final scmId = '${id}_${_scmCounter++}';
    _controls[scmId] = SourceControl(
      id: scmId,
      label: label,
      rootUri: rootUri,
      extensionId: extensionId,
    );
    notifyListeners();
    return scmId;
  }

  /// sourceControl.createResourceGroup(id, label)
  String createResourceGroup({
    required String scmId,
    required String groupId,
    required String label,
  }) {
    final sc = _controls[scmId];
    if (sc == null) return groupId;
    sc.createResourceGroup(groupId, label);
    notifyListeners();
    return groupId;
  }

  /// resourceGroup.resourceStates = [...]
  void setResourceGroupStates({
    required String scmId,
    required String groupId,
    required List<dynamic> resources,
  }) {
    _controls[scmId]?.updateResourceGroup(groupId, resources);
    notifyListeners();
  }

  /// sourceControl.inputBox.value = ...
  void setInputBoxValue(String scmId, String value) {
    final sc = _controls[scmId];
    if (sc == null) return;
    sc.inputBoxValue = value;
    notifyListeners();
  }

  String getInputBoxValue(String scmId) => _controls[scmId]?.inputBoxValue ?? '';

  void setInputBoxPlaceholder(String scmId, String placeholder) {
    final sc = _controls[scmId];
    if (sc == null) return;
    sc.inputBoxPlaceholder = placeholder;
    notifyListeners();
  }

  void disposeSourceControl(String scmId) {
    _controls[scmId]?.dispose();
    _controls.remove(scmId);
    notifyListeners();
  }

  SourceControl? get(String scmId) => _controls[scmId];
}
