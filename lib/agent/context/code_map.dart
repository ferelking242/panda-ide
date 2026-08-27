import 'dart:io';
import 'package:path/path.dart' as p;

/// Lightweight code map that provides project structure awareness.
///
/// First implementation uses Dart file scanning (no Rust FFI yet).
/// Can be extended with tree-sitter parsing later if needed.
class CodeMap {
  /// Analyze a project and return its code structure.
  static Future<CodeStructure> analyze(String rootPath) async {
    final classes = <CodeClass>[];
    final functions = <CodeFunction>[];
    final imports = <String>[];

    await for (final entity in Directory(rootPath).list(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;

      final rel = p.relative(entity.path, from: rootPath);
      if (_shouldSkip(rel)) continue;

      try {
        final content = await entity.readAsString();
        _analyzeFile(rel, content, classes, functions, imports);
      } catch (_) {}
    }

    return CodeStructure(
      classes: classes,
      functions: functions,
      imports: imports.toSet().toList(),
    );
  }

  static void _analyzeFile(
    String path,
    String content,
    List<CodeClass> classes,
    List<CodeFunction> functions,
    List<String> imports,
  ) {
    final lines = content.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // Extract imports
      if (line.startsWith('import ')) {
        imports.add(line);
      }

      // Extract classes
      if (line.startsWith('class ') || line.startsWith('abstract class ')) {
        final name = line
            .replaceAll('abstract ', '')
            .replaceAll(RegExp(r'\s*extends\s+.*'), '')
            .replaceAll(RegExp(r'\s*implements\s+.*'), '')
            .replaceAll(RegExp(r'\s*with\s+.*'), '')
            .replaceFirst('class ', '')
            .split('{')
            .first
            .trim();
        classes.add(CodeClass(name: name, file: path, line: i + 1));
      }

      // Extract top-level functions
      if (line.startsWith('Future<') ||
          line.startsWith('void ') ||
          line.startsWith('String ') ||
          line.startsWith('int ') ||
          line.startsWith('bool ') ||
          line.startsWith('List<')) {
        final match = RegExp(r'(?:Future<[^>]+>|void|String|int|bool|List<[^>]+>)\s+(\w+)\(').firstMatch(line);
        if (match != null) {
          functions.add(CodeFunction(
            name: match.group(1)!,
            file: path,
            line: i + 1,
          ));
        }
      }
    }
  }

  static bool _shouldSkip(String path) {
    return path.contains('/build/') ||
        path.contains('/.dart_tool/') ||
        path.contains('/node_modules/') ||
        path.startsWith('.');
  }
}
}

class CodeStructure {
  final List<CodeClass> classes;
  final List<CodeFunction> functions;
  final List<String> imports;

  const CodeStructure({
    required this.classes,
    required this.functions,
    required this.imports,
  });

  /// Convert to compact string for LLM context.
  String toContextString() {
    final buffer = StringBuffer();
    buffer.writeln('## Code Structure');
    buffer.writeln('Classes: ${classes.length}');
    for (final c in classes.take(30)) {
      buffer.writeln('  - ${c.name} (${c.file}:${c.line})');
    }
    buffer.writeln('Functions: ${functions.length}');
    for (final f in functions.take(30)) {
      buffer.writeln('  - ${f.name} (${f.file}:${f.line})');
    }
    return buffer.toString();
  }
}

class CodeClass {
  final String name;
  final String file;
  final int line;

  const CodeClass({required this.name, required this.file, required this.line});
}

class CodeFunction {
  final String name;
  final String file;
  final int line;

  const CodeFunction({required this.name, required this.file, required this.line});
}
