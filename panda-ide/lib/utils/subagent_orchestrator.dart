import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai.dart';
import 'panda_log.dart';
import 'api_key_rotation.dart';
import '../ui/agent_runner.dart';

/// Configuration of one sub-agent (max 4) or peer agent in a room.
class SubAgentConfig {
  final String id;
  String name;
  /// Key inside AIBloc.config (e.g. "agent_gemini").
  String modelCfgKey;
  /// Optional key-profile id inside the rotation brain (null = auto).
  String? keyProfileId;
  bool autoRotate;
  bool enabled;
  /// Role / specialization shown in the conference room.
  String role;

  SubAgentConfig({
    required this.id,
    required this.name,
    required this.modelCfgKey,
    this.keyProfileId,
    this.autoRotate = true,
    this.enabled = true,
    this.role = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'modelCfgKey': modelCfgKey,
        if (keyProfileId != null) 'keyProfileId': keyProfileId,
        'autoRotate': autoRotate,
        'enabled': enabled,
        'role': role,
      };

  static SubAgentConfig fromJson(Map<String, dynamic> j) => SubAgentConfig(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'Sub-agent',
        modelCfgKey: j['modelCfgKey']?.toString() ?? '',
        keyProfileId: j['keyProfileId']?.toString(),
        autoRotate: j['autoRotate'] != false,
        enabled: j['enabled'] != false,
        role: j['role']?.toString() ?? '',
      );
}

/// One message inside a room (conference or multi-agent).
class RoomMessage {
  final String id;
  final String roomId;
  final String author;
  /// 'user' | 'agent' | sub-agent id | peer agent id
  final String authorId;
  final String text;
  final bool isError;
  final DateTime at;

  RoomMessage({
    required this.id,
    required this.roomId,
    required this.author,
    required this.authorId,
    required this.text,
    this.isError = false,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'roomId': roomId,
        'author': author,
        'authorId': authorId,
        'text': text,
        'isError': isError,
        'at': at.toIso8601String(),
      };

  static RoomMessage fromJson(Map<String, dynamic> j) => RoomMessage(
        id: j['id']?.toString() ?? '',
        roomId: j['roomId']?.toString() ?? '',
        author: j['author']?.toString() ?? '',
        authorId: j['authorId']?.toString() ?? '',
        text: j['text']?.toString() ?? '',
        isError: j['isError'] == true,
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// A room where several agents talk: the Panda Agent conference room
/// (main agent + its sub-agents) or a multi-agent room (agent + peers).
class AgentRoom {
  final String id;
  String name;
  final bool isConference;
  /// For multi-agent rooms: model cfg keys of the participants.
  final List<String> participantCfgKeys;
  final List<RoomMessage> messages;

  AgentRoom({
    required this.id,
    required this.name,
    required this.isConference,
    List<String> participantCfgKeys = const [],
    List<RoomMessage> messages = const [],
  })  : participantCfgKeys = List<String>.from(participantCfgKeys),
        messages = List<RoomMessage>.from(messages);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isConference': isConference,
        'participantCfgKeys': participantCfgKeys,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  static AgentRoom fromJson(Map<String, dynamic> j) => AgentRoom(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'Room',
        isConference: j['isConference'] == true,
        participantCfgKeys: (j['participantCfgKeys'] as List?)?.map((e) => e.toString()).toList() ?? [],
        messages: (j['messages'] as List?)
                ?.whereType<Map>()
                .map((m) => RoomMessage.fromJson(Map<String, dynamic>.from(m)))
                .toList() ??
            [],
      );
}

/// A task given by the main agent to a sub-agent (or launched manually).
class OrchestratorTask {
  final String id;
  String title;
  String description;
  String subAgentId;
  String status; // ready | running | done | failed
  final StringBuffer log = StringBuffer();
  String result = '';
  final DateTime createdAt;

  OrchestratorTask({
    required this.id,
    required this.title,
    required this.description,
    required this.subAgentId,
    this.status = 'ready',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'subAgentId': subAgentId,
        'status': status,
        'result': result,
        'log': log.toString(),
        'createdAt': createdAt.toIso8601String(),
      };

  static OrchestratorTask fromJson(Map<String, dynamic> j) {
    final t = OrchestratorTask(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      description: j['description']?.toString() ?? '',
      subAgentId: j['subAgentId']?.toString() ?? '',
      status: j['status']?.toString() ?? 'ready',
      createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
    t.result = j['result']?.toString() ?? '';
    t.log.write(j['log']?.toString() ?? '');
    return t;
  }
}

/// SubagentOrchestrator — the "room conference" brain of Panda Agent.
///
/// • Holds up to 4 sub-agent configs (model + key profile + auto rotation).
/// • Runs their tasks for real through AgentRunner.
/// • Hosts the conference room (main agent ↔ sub-agents) and multi-agent
///   rooms (agent + peer agents, each peer may have its own sub-agents).
class SubagentOrchestrator extends ChangeNotifier {
  SubagentOrchestrator._();
  static final SubagentOrchestrator instance = SubagentOrchestrator._();

  static const int maxSubAgents = 4;
  static const _prefsKey = 'panda_agent_orchestrator_v1';

  final List<SubAgentConfig> subAgents = [];
  final List<AgentRoom> rooms = [];
  final List<OrchestratorTask> tasks = [];

  /// Model configs of the app (AIBloc.config) injected by the UI so the
  /// orchestrator can resolve models without a BuildContext.
  Map<String, dynamic> aiConfig = {};

  bool _loaded = false;
  int _running = 0;

  bool get isBusy => _running > 0;

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      subAgents
        ..clear()
        ..addAll((decoded['subAgents'] as List?)
                ?.whereType<Map>()
                .map((e) => SubAgentConfig.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            []);
      rooms
        ..clear()
        ..addAll((decoded['rooms'] as List?)
                ?.whereType<Map>()
                .map((e) => AgentRoom.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            []);
      tasks
        ..clear()
        ..addAll((decoded['tasks'] as List?)
                ?.whereType<Map>()
                .map((e) => OrchestratorTask.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            []);
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode({
        'subAgents': subAgents.map((s) => s.toJson()).toList(),
        'rooms': rooms.map((r) => r.toJson()).toList(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
      }));
    } catch (_) {}
  }

  // ── Sub-agent management ──────────────────────────────────────────────────

  SubAgentConfig addSubAgent({String name = 'Sub-agent', String modelCfgKey = ''}) {
    if (subAgents.length >= maxSubAgents) {
      throw StateError('Maximum $maxSubAgents sous-agents atteint.');
    }
    final cfg = SubAgentConfig(
      id: 'sub_${DateTime.now().millisecondsSinceEpoch}',
      name: '$name ${subAgents.length + 1}',
      modelCfgKey: modelCfgKey,
    );
    subAgents.add(cfg);
    _persist();
    notifyListeners();
    return cfg;
  }

  void removeSubAgent(String id) {
    subAgents.removeWhere((s) => s.id == id);
    _persist();
    notifyListeners();
  }

  void updateSubAgent(String id, void Function(SubAgentConfig) update) {
    for (final s in subAgents) {
      if (s.id == id) {
        update(s);
        break;
      }
    }
    _persist();
    notifyListeners();
  }

  // ── Rooms ─────────────────────────────────────────────────────────────────

  AgentRoom conferenceRoom() {
    for (final r in rooms) {
      if (r.isConference) return r;
    }
    final room = AgentRoom(
      id: 'room_conf_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Salle de conférence',
      isConference: true,
    );
    rooms.add(room);
    _persist();
    return room;
  }

  AgentRoom createMultiAgentRoom(String name, List<String> participantCfgKeys) {
    final room = AgentRoom(
      id: 'room_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Room ${rooms.length + 1}' : name.trim(),
      isConference: false,
      participantCfgKeys: participantCfgKeys,
    );
    rooms.add(room);
    _persist();
    notifyListeners();
    return room;
  }

  void removeRoom(String id) {
    rooms.removeWhere((r) => r.id == id);
    _persist();
    notifyListeners();
  }

  // ── Model resolution (with key rotation) ──────────────────────────────────

  Future<Models?> _resolveModelForKey(String cfgKey, {String? keyProfileId}) async {
    final cfg = aiConfig[cfgKey];
    if (cfg is! Map) return null;
    final map = Map<String, dynamic>.from(cfg);
    final provider = (map['provider'] ?? map['apiProvider'] ?? '').toString().toLowerCase();

    // Key profile selection through the rotation brain.
    String? key;
    if (keyProfileId != null && keyProfileId.isNotEmpty) {
      final profiles = await KeyRotationBrain.instance.getProfiles(provider);
      for (final p in profiles) {
        if (p.id == keyProfileId) key = p.key;
      }
    }
    if (key == null || key.isEmpty) {
      key = await KeyRotationBrain.instance.pickKey(provider);
    }
    if (key != null && key.isNotEmpty) {
      map['apiKey'] = key;
      map['key'] = key;
    }
    return modelFromAiConfigMap(map);
  }

  /// Builds a Models instance from a raw config map (shared with the settings
  /// page so both use identical provider mapping).
  static Models? modelFromAiConfigMap(Map<String, dynamic> cfg) {
    final providerRaw = (cfg['provider'] ?? cfg['apiProvider'] ?? '').toString();
    final provider = providerRaw.toLowerCase();
    final apiKey = Models.resolveApiKey(cfg);
    final modelName = (cfg['modelName'] ?? cfg['model'] ?? '').toString();

    switch (provider) {
      case 'gemini':     return Gemini(apiKey: apiKey, model: modelName);
      case 'claude':     return Claude(apiKey: apiKey, model: modelName);
      case 'openai':     return OpenAI(apiKey: apiKey, model: modelName);
      case 'grok':       return Grok(apiKey: apiKey, model: modelName);
      case 'deepseek':   return DeepSeek(apiKey: apiKey, model: modelName);
      case 'mistral':    return Mistral(apiKey: apiKey, model: modelName);
      case 'togetherai': return TogetherAi(apiKey: apiKey, model: modelName);
      case 'perplexity': return Perplexity(apiKey: apiKey, model: modelName);
      case 'openrouter': return OpenRouter(apiKey: apiKey, model: modelName);
      case 'groq':       return Groq(apiKey: apiKey, model: modelName);
      case 'fireworks':  return FireWorks(apiKey: apiKey, model: modelName);
      case 'cohere':     return Cohere(apiKey: apiKey, model: modelName);
      case 'cerebras':   return Cerebras(apiKey: apiKey, model: modelName);
      case 'novita':     return Novita(apiKey: apiKey, model: modelName);
      case 'hyperbolic': return Hyperbolic(apiKey: apiKey, model: modelName);
      case 'sambanova':  return SambaNova(apiKey: apiKey, model: modelName);
      case 'qwen':       return Qwen(apiKey: apiKey, model: modelName);
      case 'ollama':
        return Ollama(model: modelName, port: (cfg['port'] as num?)?.toInt() ?? 11434);
      case 'lmstudio':
        return LmStudio(model: modelName, port: (cfg['port'] as num?)?.toInt() ?? 1234);
      case 'pandagateway':
        return PandaGateway(apiKey: apiKey, model: modelName, port: (cfg['port'] as num?)?.toInt() ?? 8000);
      case 'custom':
        final url = (cfg['url'] ?? '').toString().trim();
        if (url.isEmpty) return null;
        final parsedHeaders = <String, String>{};
        final hdrs = cfg['headers'];
        if (hdrs is Map) {
          hdrs.forEach((k, v) {
            if (k != null && v != null) parsedHeaders[k.toString()] = v.toString();
          });
        }
        if (apiKey.isNotEmpty && !parsedHeaders.containsKey('Authorization')) {
          parsedHeaders['Authorization'] = 'Bearer $apiKey';
        }
        return CustomModel(
          url: url,
          httpMethod: (cfg['httpMethod'] ?? 'POST').toString(),
          toolCallingMethod: ToolCallingMethod.openAiCompatible,
          customHeaders: parsedHeaders,
          requestBuilder: (code, instruction) => {
            if (modelName.isNotEmpty) 'model': modelName,
            'messages': [
              {'role': 'system', 'content': instruction},
              {'role': 'user', 'content': code},
            ],
          },
          customParser: (response) {
            try {
              final data = response is Map ? response : {};
              final choices = data['choices'] as List?;
              if (choices != null && choices.isNotEmpty) {
                final msg = choices.first['message'] ?? choices.first['delta'];
                if (msg is Map) return (msg['content'] ?? '').toString();
              }
              return (data['text'] ?? data['content'] ?? response ?? '').toString();
            } catch (_) {
              return response?.toString() ?? '';
            }
          },
        );
      default:
        return null;
    }
  }

  // ── Task execution ────────────────────────────────────────────────────────

  OrchestratorTask createTask(String title, String description, String subAgentId) {
    final task = OrchestratorTask(
      id: 'task_${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Tâche ${tasks.length + 1}' : title.trim(),
      description: description.trim(),
      subAgentId: subAgentId,
      createdAt: DateTime.now(),
    );
    tasks.add(task);
    _persist();
    notifyListeners();
    return task;
  }

  /// Runs [task] with its sub-agent through the real AgentRunner.
  /// Returns when the task completes (or fails).
  Future<void> runTask(
    OrchestratorTask task, {
    String workspacePath = '',
    String agentMode = 'agent',
  }) async {
    await load();
    final sub = subAgents.where((s) => s.id == task.subAgentId).firstOrNull;
    if (sub == null) {
      task.status = 'failed';
      task.log.writeln('Sous-agent introuvable.');
      notifyListeners();
      return;
    }
    final model = await _resolveModelForKey(sub.modelCfgKey, keyProfileId: sub.keyProfileId);
    if (model == null) {
      task.status = 'failed';
      task.log.writeln('Aucun modèle configuré pour ce sous-agent (Tools → Settings → Providers).');
      notifyListeners();
      return;
    }

    task.status = 'running';
    _running++;
    _appendConference(sub.name, '▶ Task reçue : ${task.title}\n${task.description}', sub.id);
    notifyListeners();

    final runner = _RunnerHandle();
    try {
      await for (final chunk in runner.run(
        model: model,
        messages: [
          {'role': 'user', 'content': task.description},
        ],
        workspacePath: workspacePath,
        agentMode: agentMode,
      )) {
        switch (chunk.phase) {
          case AgentPhase.thinking:
            if (chunk.text.isNotEmpty) task.log.write(chunk.text);
            break;
          case AgentPhase.streaming:
            if (chunk.text.isNotEmpty) task.log.write(chunk.text);
            break;
          case AgentPhase.toolRunning:
            task.log.writeln('\n🔧 ${chunk.toolName}…');
            break;
          case AgentPhase.toolDone:
            final r = (chunk.toolResult ?? '').toString();
            task.log.writeln('   → ${r.length > 200 ? '${r.substring(0, 200)}…' : r}');
            break;
          case AgentPhase.error:
            task.log.writeln('\n✕ ${chunk.text}');
            task.status = 'failed';
            _appendConference(sub.name, '✕ Erreur : ${chunk.text}', sub.id, isError: true);
            break;
          case AgentPhase.done:
          case AgentPhase.idle:
            break;
        }
        notifyListeners();
      }
      if (task.status != 'failed') {
        task.status = 'done';
        task.result = task.log.toString();
        _appendConference(sub.name, '✔ Terminé : ${task.title}', sub.id);
      }
    } catch (e) {
      task.status = 'failed';
      task.log.writeln('Erreur : $e');
      PandaLog.e('Orchestrator', 'Task failed', error: e);
    } finally {
      _running--;
      _persist();
      notifyListeners();
    }
  }

  // ── Conference / rooms messaging ──────────────────────────────────────────

  void _appendConference(String author, String text, String authorId, {bool isError = false}) {
    final room = conferenceRoom();
    room.messages.add(RoomMessage(
      id: 'm_${DateTime.now().microsecondsSinceEpoch}',
      roomId: room.id,
      author: author,
      authorId: authorId,
      text: text,
      isError: isError,
      at: DateTime.now(),
    ));
    if (room.messages.length > 300) room.messages.removeRange(0, room.messages.length - 300);
    _persist();
  }

  void appendUserMessage(AgentRoom room, String text) {
    room.messages.add(RoomMessage(
      id: 'm_${DateTime.now().microsecondsSinceEpoch}',
      roomId: room.id,
      author: 'Vous',
      authorId: 'user',
      text: text,
      at: DateTime.now(),
    ));
    _persist();
    notifyListeners();
  }

  /// Broadcasts [text] to every enabled participant of [room]:
  ///  • conference room → all enabled sub-agents answer in turn;
  ///  • multi-agent room → every peer agent answers in turn.
  Future<void> broadcast(AgentRoom room, String text, {String workspacePath = ''}) async {
    await load();
    appendUserMessage(room, text);

    final participants = <(String, String, String?, bool)>[]; // (name, cfgKey, keyProfileId, autoRotate)
    if (room.isConference) {
      for (final s in subAgents.where((s) => s.enabled)) {
        participants.add((s.name, s.modelCfgKey, s.keyProfileId, s.autoRotate));
      }
    } else {
      for (final key in room.participantCfgKeys) {
        final cfg = aiConfig[key];
        final name = cfg is Map ? ((cfg['modelName'] ?? cfg['model'] ?? key).toString()) : key;
        participants.add((name, key, null, true));
      }
    }

    for (final (name, cfgKey, keyProfileId, _) in participants) {
      final model = await _resolveModelForKey(cfgKey, keyProfileId: keyProfileId);
      if (model == null) {
        _appendConference(name, '⚠️ Modèle non configuré ($cfgKey).', cfgKey, isError: true);
        notifyListeners();
        continue;
      }
      final history = room.messages
          .where((m) => m.text.isNotEmpty)
          .toList()
          .fold<StringBuffer>(StringBuffer(), (b, m) {
        b.writeln('${m.author} : ${m.text}');
        return b;
      });

      _running++;
      notifyListeners();
      final buffer = StringBuffer();
      final runner = _RunnerHandle();
      try {
        await for (final chunk in runner.run(
          model: model,
          messages: [
            {'role': 'user', 'content': text},
          ],
          workspacePath: workspacePath,
          agentMode: 'ask',
          systemPromptOverride:
              'Tu participes à une salle de conférence multi-agents de Panda IDE. '
              'Voici le fil de discussion :\n$history\n'
              'Réponds de façon concise et apporte ta perspective unique.',
        )) {
          switch (chunk.phase) {
            case AgentPhase.streaming:
            case AgentPhase.thinking:
              buffer.write(chunk.text);
              break;
            case AgentPhase.error:
              _appendConference(name, '✕ ${chunk.text}', cfgKey, isError: true);
              break;
            default:
              break;
          }
          notifyListeners();
        }
        if (buffer.toString().trim().isNotEmpty) {
          _appendConference(name, buffer.toString().trim(), cfgKey);
        }
      } catch (e) {
        _appendConference(name, '✕ $e', cfgKey, isError: true);
      } finally {
        _running--;
        notifyListeners();
      }
    }
    _persist();
  }

  void clearRoom(AgentRoom room) {
    room.messages.clear();
    _persist();
    notifyListeners();
  }
}

/// Thin wrapper so the orchestrator uses the real AgentRunner (headless:
/// no BuildContext → no file tools, pure reasoning/reporting).
class _RunnerHandle {
  Stream<AgentChunk> run({
    required Models model,
    required List<Map<String, dynamic>> messages,
    String workspacePath = '',
    String agentMode = 'ask',
    String? systemPromptOverride,
  }) {
    return AgentRunner().run(
      model: model,
      messages: messages,
      workspacePath: workspacePath,
      agentMode: agentMode,
      systemPromptOverride: systemPromptOverride,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
