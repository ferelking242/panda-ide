import 'dart:async';
import 'dart:convert';
import '../fs/panda_file_system_provider.dart';

class WorkspaceFolder {
  final String name;
  final PandaUri uri;

  WorkspaceFolder({
    required this.name,
    required this.uri,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'uri': uri.toUriString(),
  };

  factory WorkspaceFolder.fromJson(Map<String, dynamic> json) => WorkspaceFolder(
    name: json['name'] as String? ?? 'Folder',
    uri: PandaUri.parse(json['uri'] as String? ?? 'file:///workspace'),
  );
}

class PandaWorkspaceConfig {
  final String id;
  final String name;
  final List<WorkspaceFolder> folders;
  final Map<String, dynamic> settings;
  final List<String> openTabPaths;
  final int activeTabIndex;

  PandaWorkspaceConfig({
    required this.id,
    required this.name,
    required this.folders,
    required this.settings,
    required this.openTabPaths,
    required this.activeTabIndex,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'folders': folders.map((f) => f.toJson()).toList(),
    'settings': settings,
    'openTabPaths': openTabPaths,
    'activeTabIndex': activeTabIndex,
  };

  factory PandaWorkspaceConfig.fromJson(Map<String, dynamic> json) => PandaWorkspaceConfig(
    id: json['id'] as String? ?? 'default',
    name: json['name'] as String? ?? 'Untitled Workspace',
    folders: (json['folders'] as List<dynamic>?)
        ?.map((e) => WorkspaceFolder.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
    settings: json['settings'] as Map<String, dynamic>? ?? {},
    openTabPaths: (json['openTabPaths'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    activeTabIndex: json['activeTabIndex'] as int? ?? 0,
  );
}

class PandaWorkspaceManager {
  static final PandaWorkspaceManager _instance = PandaWorkspaceManager._internal();
  factory PandaWorkspaceManager() => _instance;
  PandaWorkspaceManager._internal();

  PandaWorkspaceConfig? _currentWorkspace;
  final _fs = PandaFileSystemProvider();
  final StreamController<PandaWorkspaceConfig> _workspaceController = StreamController.broadcast();

  PandaWorkspaceConfig? get currentWorkspace => _currentWorkspace;
  Stream<PandaWorkspaceConfig> get onWorkspaceChanged => _workspaceController.stream;

  Future<void> initializeWorkspace(String primaryPath) async {
    final folder = WorkspaceFolder(
      name: primaryPath.split('/').where((s) => s.isNotEmpty).last,
      uri: PandaUri(scheme: PandaScheme.file, path: primaryPath),
    );
    _currentWorkspace = PandaWorkspaceConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: folder.name,
      folders: [folder],
      settings: {'editor.fontSize': 14, 'editor.wordWrap': 'on'},
      openTabPaths: [],
      activeTabIndex: 0,
    );
    _workspaceController.add(_currentWorkspace!);
  }

  Future<void> addFolderToWorkspace(String folderPath) async {
    if (_currentWorkspace == null) {
      await initializeWorkspace(folderPath);
      return;
    }
    final name = folderPath.split('/').where((s) => s.isNotEmpty).last;
    final folder = WorkspaceFolder(
      name: name,
      uri: PandaUri(scheme: PandaScheme.file, path: folderPath),
    );
    final updatedFolders = List<WorkspaceFolder>.from(_currentWorkspace!.folders)..add(folder);
    _currentWorkspace = PandaWorkspaceConfig(
      id: _currentWorkspace!.id,
      name: _currentWorkspace!.name,
      folders: updatedFolders,
      settings: _currentWorkspace!.settings,
      openTabPaths: _currentWorkspace!.openTabPaths,
      activeTabIndex: _currentWorkspace!.activeTabIndex,
    );
    _workspaceController.add(_currentWorkspace!);
  }

  Future<void> saveWorkspaceConfig(String configFilePath) async {
    if (_currentWorkspace == null) return;
    final jsonStr = jsonEncode(_currentWorkspace!.toJson());
    await _fs.writeAsString(
      PandaUri(scheme: PandaScheme.file, path: configFilePath),
      jsonStr,
    );
  }

  Future<void> loadWorkspaceConfig(String configFilePath) async {
    final jsonStr = await _fs.readAsString(
      PandaUri(scheme: PandaScheme.file, path: configFilePath),
    );
    if (jsonStr.isNotEmpty) {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      _currentWorkspace = PandaWorkspaceConfig.fromJson(json);
      _workspaceController.add(_currentWorkspace!);
    }
  }
}
