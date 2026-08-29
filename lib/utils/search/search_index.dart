import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import '../ssh/ssh_utils.dart';
import '../git/git_diff.dart';

// Search indexing: Boyer-Moore, inverted index, GGUF models
// Extracted from functions.dart

class GgufDownloadTask {
  final String taskId, modelName, url, fileName, localPath, quant, imageUrl;
  final GgufDownloadStatus status;
  final double progress, paramSize;
  final bool registered;

  GgufDownloadTask({
    required this.taskId,
    required this.modelName,
    required this.url,
    required this.fileName,
    required this.localPath,
    required this.status,
    required this.progress,
    required this.registered,
    required this.quant,
    required this.paramSize,
    required this.imageUrl
  });

  GgufDownloadTask copyWith({
    String? taskId,
    String? modelName,
    String? url,
    String? fileName,
    String? localPath,
    String? quant,
    String? imageUrl,
    GgufDownloadStatus? status,
    double? progress,
    double? paramSize,
    bool? registered,
  }) {
    return GgufDownloadTask(
      taskId: taskId ?? this.taskId,
      modelName: modelName ?? this.modelName,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      registered: registered ?? this.registered,
      quant: quant ?? this.quant,
      paramSize: paramSize ?? this.paramSize,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'modelName': modelName,
    'url': url,
    'fileName': fileName,
    'localPath': localPath,
    'status': status.index,
    'progress': progress,
    'registered': registered,
    'quant': quant,
    'paramSize': paramSize,
    'imageUrl': imageUrl
  };

  factory GgufDownloadTask.fromJson(Map<String, dynamic> json) => GgufDownloadTask(
    taskId: json['taskId'] as String? ?? '',
    modelName: json['modelName'] as String? ?? '',
    url: json['url'] as String? ?? '',
    fileName: json['fileName'] as String? ?? '',
    localPath: json['localPath'] as String? ?? '',
    status: GgufDownloadStatus.values[json['status'] as int? ?? 0],
    progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
    registered: json['registered'] as bool? ?? false,
    quant: json['quant'] as String? ?? '',
    paramSize: (json['paramSize'] as num?)?.toDouble() ?? 0.0,
    imageUrl: json['imageUrl'] ?? '',
  );
}

class GgufModel {
  final String name, url, fileName, quant, imageUrl;
  final double paramSize;

  GgufModel({
    required this.name,
    required this.url,
    required this.fileName,
    required this.quant,
    required this.paramSize,
    required this.imageUrl
  });

  static Future<({String modelId, Map<String, dynamic> aiConfig, Map<String, dynamic> modelSelected})> registerGgufModelWithAI(GgufDownloadTask task) async {
    final prefs = await SharedPreferences.getInstance();
    final aiConfigStr = await getAiConfig();
    final Map<String, dynamic> aiConfig = jsonDecode(aiConfigStr);

    final alreadyExists = aiConfig.values.any((v) =>
      v is Map<String, dynamic> &&
      v['provider'] == 'LocalLlama' &&
      v['modelPath'] == task.localPath
    );
    if (alreadyExists) {
      final existingKey = aiConfig.entries.firstWhere((e) =>
        e.value is Map<String, dynamic> &&
        (e.value as Map)['modelPath'] == task.localPath
      ).key;
      final modelSelectedStr = await getModelSelected();
      return (
        modelId: existingKey,
        aiConfig: aiConfig,
        modelSelected: jsonDecode(modelSelectedStr) as Map<String, dynamic>,
      );
    }

    final modelId = 'LocalLlama-${DateTime.now().millisecondsSinceEpoch}';
    aiConfig[modelId] = {
      'provider': 'LocalLlama',
      'apiProvider': 'LocalLlama',
      'modelName': task.modelName,
      'model': task.modelName,
      'modelPath': task.localPath,
      'threads': 4,
      'contextSize': 4096,
      'gpuLayers': 0,
    };
    await prefs.setString('aiConfig', jsonEncode(aiConfig));

    final modelSelectedStr = await getModelSelected();
    final Map<String, dynamic> modelSelected = jsonDecode(modelSelectedStr);
    if ((modelSelected['chat'] as String? ?? '').isEmpty) {
      modelSelected['chat'] = modelId;
      await prefs.setString('modelSelected', jsonEncode(modelSelected));
    }

    return (modelId: modelId, aiConfig: aiConfig, modelSelected: modelSelected);
  }
}

class BoyerMooreSearch {
  final String pattern;
  final bool caseSensitive;

  late final String _pat;
  late final List<int> _skip;

  BoyerMooreSearch(this.pattern, {this.caseSensitive = true}) {
    _pat = caseSensitive ? pattern : pattern.toLowerCase();
    _skip = List<int>.filled(256, _pat.length);
    for (int i = 0; i < _pat.length - 1; i++) {
      final c = _pat.codeUnitAt(i);
      if (c < 256) _skip[c] = _pat.length - 1 - i;
    }
  }

  bool containsIn(String text) => _firstMatch(
    caseSensitive ? text : text.toLowerCase(),
  ) != -1;

  int firstMatch(String text) => _firstMatch(caseSensitive ? text : text.toLowerCase());

  List<int> findAll(String text) {
    final src = caseSensitive ? text : text.toLowerCase();
    final m = _pat.length;
    if (m == 0) return [];
    final hits = <int>[];
    int base = 0;
    while (base <= src.length - m) {
      final idx = _firstMatch(src.substring(base));
      if (idx == -1) break;
      hits.add(base + idx);
      base += idx + m;
    }
    return hits;
  }

  bool isWholeWordMatch(String text, int offset) {
    final end = offset + _pat.length;
    final before = offset == 0 || !_isWordChar(text.codeUnitAt(offset - 1));
    final after  = end >= text.length || !_isWordChar(text.codeUnitAt(end));
    return before && after;
  }

  int _firstMatch(String src) {
    final m = _pat.length;
    final n = src.length;
    if (m == 0) return 0;
    if (m > n)  return -1;

    int i = m - 1;
    while (i < n) {
      int j = m - 1, k = i;
      while (j >= 0 && src.codeUnitAt(k) == _pat.codeUnitAt(j)) {
        k--;
        j--;
      }
      if (j < 0) return k + 1;
      final c = src.codeUnitAt(i);
      i += (c < 256) ? _skip[c] : m;
    }
    return -1;
  }

  static bool _isWordChar(int c) =>
      (c >= 65 && c <= 90)  ||
      (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57)  ||
      c == 95;
}

String? _regexLiteralPrefix(String regexPattern) {
  final sb = StringBuffer();
  for (int i = 0; i < regexPattern.length; i++) {
    final c = regexPattern[i];
    if (r'\^$.|?*+()[]{}'.contains(c)) break;
    sb.write(c);
  }
  final p = sb.toString();
  return p.length >= 2 ? p : null;
}

Future<bool> _isBinaryFile(File file, {int sampleBytes = 4096}) async {
  try {
    final raf = await file.open();
    try {
      final buf = await raf.read(sampleBytes);
      return buf.contains(0);
    } finally {
      await raf.close();
    }
  } catch (_) {
    return true;
  }
}

class SearchParams {
  final String workspacePath;
  final String query;
  final bool matchCase;
  final bool matchWholeWord;
  final bool isRegex;
  final int maxFileSizeBytes;

  const SearchParams({
    required this.workspacePath,
    required this.query,
    required this.matchCase,
    required this.matchWholeWord,
    required this.isRegex,
    this.maxFileSizeBytes = 5 * 1024 * 1024,
  });
}

class RawResult {
  final String filePath;
  final String relativePath;
  final int lineNumber;
  final String lineContent;

  const RawResult({
    required this.filePath,
    required this.relativePath,
    required this.lineNumber,
    required this.lineContent,
  });
}

const _kTextExtensions = {
  '.dart', '.js',   '.ts',   '.json', '.xml',   '.html',  '.css',
  '.md',   '.txt',  '.yaml', '.yml',  '.java',  '.kt',    '.py',
  '.c',    '.cpp',  '.h',    '.hpp',  '.sh',    '.gradle',
  '.properties',   '.swift', '.m',    '.go',    '.rs',    '.rb',
  '.php',  '.sql',  '.vue',  '.jsx',  '.tsx',   '.toml',  '.lock',
};

Future<List<RawResult>> searchIsolate(SearchParams p) async {
  final results = <RawResult>[];
  final dir = Directory(p.workspacePath);

  BoyerMooreSearch? bm;
  RegExp? regex;
  BoyerMooreSearch? prefixBm;

  if (p.isRegex) {
    try {
      regex = RegExp(p.query, caseSensitive: p.matchCase);
    } catch (_) {
      return results;
    }
    final prefix = _regexLiteralPrefix(p.query);
    if (prefix != null) {
      prefixBm = BoyerMooreSearch(prefix, caseSensitive: p.matchCase);
    }
  } else {
    bm = BoyerMooreSearch(p.query, caseSensitive: p.matchCase);
  }

  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;

    final relativePath = entity.path.replaceFirst('${p.workspacePath}/', '');

    if (relativePath.startsWith('.') ||
        relativePath.contains('/.') ||
        relativePath.contains('/build/') ||
        relativePath.contains('/.git/') ||
        relativePath.contains('/node_modules/') ||
        relativePath.contains('/.dart_tool/') ||
        relativePath.contains('/.gradle/')) {
      continue;
    }

    final ext = path.extension(entity.path).toLowerCase();
    if (ext.isNotEmpty && !_kTextExtensions.contains(ext)) continue;

    try {
      final stat = await entity.stat();
      if (stat.size == 0 || stat.size > p.maxFileSizeBytes) continue;
    } catch (_) {
      continue;
    }

    if (await _isBinaryFile(entity)) continue;

    try {
      int lineNumber = 0;

      await for (final line in entity
          .openRead()
          .transform(utf8.decoder) 
          .transform(const LineSplitter())) {
        lineNumber++;

        bool hasMatch;

        if (p.isRegex) {
          if (prefixBm != null && !prefixBm.containsIn(line)) {
            hasMatch = false;
          } else {
            hasMatch = regex!.hasMatch(line);
          }
        } else if (p.matchWholeWord) {
          final offsets = bm!.findAll(line);
          hasMatch = offsets.any((o) => bm!.isWholeWordMatch(line, o));
        } else {
          hasMatch = bm!.containsIn(line);
        }

        if (hasMatch) {
          results.add(RawResult(
            filePath:     entity.path,
            relativePath: relativePath,
            lineNumber:   lineNumber,
            lineContent:  line.trim(),
          ));
        }
      }
    } on FormatException {
      continue;
    } catch (_) {
      continue;
    }
  }

  return results;
}

class InvertedIndex {
  final Map<String, Map<String, List<int>>> _index = {};
  bool _ready = false;

  bool get isReady => _ready;

  static final _wordRe = RegExp(r'\b[A-Za-z_]\w{2,}\b');
  static const _maxFileSizeForIndex = 2 * 1024 * 1024;   // 2 MB

  Future<void> build(String workspacePath) async {
    _index.clear();
    _ready = false;
    await _scan(workspacePath);
    _ready = true;
  }

  Future<void> _scan(String workspacePath) async {
    final dir = Directory(workspacePath);

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;

      final relativePath = entity.path.replaceFirst('$workspacePath/', '');
      if (relativePath.startsWith('.') ||
          relativePath.contains('/.') ||
          relativePath.contains('/build/') ||
          relativePath.contains('/.git/') ||
          relativePath.contains('/node_modules/')) {
        continue;
      }

      final ext = path.extension(entity.path).toLowerCase();
      if (ext.isNotEmpty && !_kTextExtensions.contains(ext)) continue;

      try {
        final stat = await entity.stat();
        if (stat.size == 0 || stat.size > _maxFileSizeForIndex) continue;
      } catch (_) {
        continue;
      }

      if (await _isBinaryFile(entity)) continue;

      try {
        int lineNo = 0;
        await for (final line in entity
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          lineNo++;
          for (final m in _wordRe.allMatches(line.toLowerCase())) {
            final word = m.group(0)!;
            (_index[word] ??= {})[entity.path] ??= [];
            _index[word]![entity.path]!.add(lineNo);
          }
        }
      } catch (_) {
        continue;
      }
    }
  }

  Map<String, List<int>>? lookup(String word) {
    if (!_ready || word.length < 3) return null;
    return _index[word.toLowerCase()];
  }

  Future<void> updateFile(File file) async {
    for (final v in _index.values) {
      v.remove(file.path);
    }
    try {
      int lineNo = 0;
      await for (final line in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        lineNo++;
        for (final m in _wordRe.allMatches(line.toLowerCase())) {
          final word = m.group(0)!;
          (_index[word] ??= {})[file.path] ??= [];
          _index[word]![file.path]!.add(lineNo);
        }
      }
    } catch (_) {}
  }

  void clear() {
    _index.clear();
    _ready = false;
  }
}

