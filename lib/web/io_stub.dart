/// Stub for dart:io types on web platform.
/// Provides minimal stubs so conditional dart:io imports compile on web.

class Directory {
  final String path;
  const Directory(this.path);
  bool existsSync() => false;
  Future<Directory> create({bool recursive = false}) async => this;
  Stream<dynamic> list({bool followLinks = true}) => const Stream.empty();
  Directory get parent => Directory(path.substring(0, path.lastIndexOf('/')));
  Future<Directory> delete({bool recursive = false}) async => this;
  StatResult statSync() => StatResult();
  Future<Directory> rename(String newPath) async => this;
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
  File copySync(String newPath) => this;
  String get absolute => path;
  DateTime get lastModifiedSync => DateTime.now();
  StatResult statSync() => StatResult();
  Future<File> rename(String newPath) async => this;
  Future<File> delete() async => this;
}

class FileSystemEntity {
  final String path;
  const FileSystemEntity(this.path);
  String get name => path.split('/').last;
  String get parentPath => path.substring(0, path.lastIndexOf('/'));
  bool get isAbsolute => path.startsWith('/');
}

class StatResult {
  final DateTime modified = DateTime.now();
  final int size = 0;
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
