import 'dart:convert';
import 'dart:io';

List<int> readPubManifestBytes(String projectPath) {
  final bytes = <int>[];
  for (final name in const ['pubspec.yaml', 'pubspec.lock']) {
    try {
      final file = File('$projectPath/$name');
      if (file.existsSync()) {
        bytes
          ..addAll(utf8.encode(name))
          ..add(0)
          ..addAll(file.readAsBytesSync())
          ..add(0);
      }
    } catch (_) {
      // A project can be temporarily unavailable while its mount is created.
    }
  }
  return bytes;
}