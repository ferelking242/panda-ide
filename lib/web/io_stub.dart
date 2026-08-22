/// Stub for dart:io types on web platform.
/// Provides minimal Directory/FileSystemEntity stubs so code that
/// imports dart:io conditionally can compile on web.

class Directory {
  final String path;
  const Directory(this.path);
  bool existsSync() => false;
  Future<Directory> create({bool recursive = false}) async => this;
  Stream<dynamic> list({bool followLinks = true}) => const Stream.empty();
}

class File {
  final String path;
  const File(this.path);
  bool existsSync() => false;
  Future<File> create({bool recursive = false}) async => this;
  Future<String> readAsString() async => '';
  Future<List<int>> readAsBytes() async => [];
  Future<File> writeAsString(String content, {bool flush = false}) async => this;
  Future<File> writeAsBytes(List<int> bytes, {bool flush = false}) async => this;
  int lengthSync() => 0;
  Stream<List<int>> openRead([int? start, int? end]) => const Stream.empty();
  IOSink openSync({FileMode mode = FileMode.write}) => IOSink();
  File copySync(String newPath) => this;
  String get absolute => path;
  DateTime get lastModifiedSync() => DateTime.now();
}

class FileSystemEntity {
  final String path;
  const FileSystemEntity(this.path);
  String get name => path.split('/').last;
  String get parent => path.substring(0, path.lastIndexOf('/'));
  bool get isAbsolute => path.startsWith('/');
}

class FileMode {
  static const write = FileMode._();
  static const append = FileMode._();
  const FileMode._();
}

class IOSink {
  void write(Object? object) {}
  void writeln([Object? object = '']) {}
  void close() {}
  Future<void> flush() async {}
}
