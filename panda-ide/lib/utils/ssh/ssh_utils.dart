import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';

// SSH utilities: login, key management, keygen
// Extracted from functions.dart

abstract class SSHInfo {
  final String url, name;
  final int id;

  SSHInfo({
    required this.id,
    required this.url,
    required this.name
  });

  SSHClient? get client;
  bool get isConnected;

  Uri get uri => Uri.parse(url);
  String get username => uri.userInfo.split(':').first;
  String get host => uri.host;
  int get port => uri.port == 0 ? 22 : uri.port;

  factory SSHInfo.fromJsonMap(Map<String, dynamic> jsonMap){
    switch (jsonMap["login"]) {
      case true: return SSHLogin.fromJsonMap(jsonMap);
      case false: return SSHPrivateKey.fromJsonMap(jsonMap);
      default: throw Exception('Invalid SSH type');
    }
  }

  Map<String, dynamic> toJsonMap();

  Future<(bool, String)> connect();
  void disconnect();

  static Future<List<SSHInfo>> getSavedSSHServers() async{
    final prefs = await SharedPreferences.getInstance();
    final serverList = (jsonDecode(prefs.getString('sshServerList') ?? '[]') as List).cast<Map<String, dynamic>>();
    return serverList.map(SSHInfo.fromJsonMap).toList();
  }

  @override
  bool operator ==(Object other) {
    return other is SSHInfo && other.id == id;
  }
  
  @override int get hashCode => id;
}

class SSHLogin extends SSHInfo{
  final String password;

  SSHLogin({
    required super.name,
    required super.id,
    required super.url,
    required this.password,
  });
  
  @override
  Map<String, dynamic> toJsonMap() => {
    "name": name,
    "id": id,
    "url": url,
    "username": username,
    "password": password,
    "login": true
  };

  @override
  String toString() => toJsonMap().toString();
  
  
  static SSHLogin fromJsonMap(Map<String, dynamic> jsonMap) => SSHLogin(
    name: jsonMap["name"],
    id: jsonMap["id"],
    url: jsonMap["url"],
    password: jsonMap["password"],
  );
  
  SSHClient? _client;
  bool _isConnected = false;

  @override
  SSHClient? get client => _client;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<(bool, String)> connect() async{
    try {
      _client = SSHClient(
        await SSHSocket.connect(host, port),
        username: username,
        onPasswordRequest: () => password,
      );
      await _client!.authenticated;
      _isConnected = true;
      return (true, "Successfully connected to $host as $username");
    } on SocketException catch(e) {
      return (false, "Server unreachable: $e");
    } on TimeoutException catch(e) {
      return (false, "Connection timed out: $e");
    } catch (e) {
      return (false, "An error occurred: $e");
    }
  }

  @override
  void disconnect() {
    _isConnected = false;
    _client?.close();
  }
}

class SSHPrivateKey extends SSHInfo{
  final File? termuxKeyLoc;

  SSHPrivateKey({
    required super.name,
    required super.id,
    required super.url,
    this.termuxKeyLoc
  });
  
  @override
  Map<String, dynamic> toJsonMap() => {
    "name": name,
    "id": id,
    "url": url,
    "login": false,
    "termuxKeyLoc": termuxKeyLoc?.path
  };

  static SSHPrivateKey fromJsonMap(Map<String, dynamic> jsonMap) => SSHPrivateKey(
    name: jsonMap["name"],
    id: jsonMap["id"],
    url: jsonMap["url"],
    termuxKeyLoc: File("$appDir/.termux/.ssh/id_ed25519"),
  );

  SSHClient? _client;
  bool _isConnected = false;

  @override
  String toString() => toJsonMap().toString();

  @override
  SSHClient? get client => _client;

  @override
  bool get isConnected => _isConnected;
  
  @override
  Future<(bool, String)> connect() async{
    try {
      _client = SSHClient(
        await SSHSocket.connect(host, port),
        username: username,
        identities: [
          ...SSHKeyPair.fromPem(await (termuxKeyLoc ?? SshKeygen.privateKeyFilelocation).readAsString())
        ]
      );
      await _client!.authenticated;
      _isConnected = true;
      return (true, "Successfully connected to $host as $username");
    } on SocketException catch(e) {
      return (false, "Server unreachable: $e");
    } on TimeoutException catch(e) {
      return (false, "Connection timed out: $e");
    } catch (e) {
      return (false, "An error occurred: $e");
    }
  }

  @override
  void disconnect() {
    _isConnected = false;
    _client?.close();
  }
}

class SshKeygen {
  final String? comment;
  final File? termPubKey;
  final File? termPrivKey;

  static final publicKeyFilelocation = File("$appDir/.ssh/id_ed25519.pub");
  static final privateKeyFilelocation = File("$appDir/.ssh/id_ed25519");

  SshKeygen({
    this.comment,
    this.termPubKey,
    this.termPrivKey,
  });

  Future<void> generate() async{
    final algo = Ed25519();
    final keyPair = await algo.newKeyPair();
    final pubKey = await keyPair.extractPublicKey();
    final privSeed = await keyPair.extractPrivateKeyBytes();
    final pubBytes = Uint8List.fromList(pubKey.bytes);
    final seedBytes = Uint8List.fromList(privSeed);
    final publicKeyFile = buildPublicKeyFile(pubBytes, comment: comment ?? 'user@host');
    final privateKeyFile = buildPrivateKeyFile(pubBytes, seedBytes, comment: comment ?? 'user@host');
    if(!(await (termPrivKey ?? privateKeyFilelocation).exists())){
      await (termPrivKey ?? privateKeyFilelocation).create(recursive: true);
    }

    if(!(await (termPubKey ?? publicKeyFilelocation).exists())){
      await (termPubKey ?? publicKeyFilelocation).create(recursive: true);
    }
    
    await (termPrivKey ?? privateKeyFilelocation).writeAsString(privateKeyFile);
    await (termPubKey ?? publicKeyFilelocation).writeAsString(publicKeyFile);
  }

  String buildPublicKeyFile(Uint8List pubBytes, {String comment = ''}) {
    final buf = BytesBuilder();
    _writeString(buf, 'ssh-ed25519');
    _writeBytes(buf, pubBytes);
    final b64 = base64.encode(buf.toBytes());
    return 'ssh-ed25519 $b64 $comment'.trim();
  }

  String buildPrivateKeyFile(Uint8List pubBytes, Uint8List seedBytes, {String comment = ''}) {
    final privBytes = Uint8List(64)
      ..setRange(0, 32, seedBytes)
      ..setRange(32, 64, pubBytes);

    final pubBlob = _buildPubBlob(pubBytes);
    final privBlob = _buildPrivBlob(pubBytes, privBytes, comment);

    final outer = BytesBuilder();
    outer.add(utf8.encode('openssh-key-v1\x00'));
    _writeString(outer, 'none');
    _writeString(outer, 'none');
    _writeString(outer, '');
    _writeUint32(outer, 1);
    _writeBytes(outer, pubBlob);
    _writeBytes(outer, privBlob);

    final b64 = base64.encode(outer.toBytes());
    final lines = RegExp('.{1,70}').allMatches(b64).map((m) => m.group(0)!).join('\n');
    return '-----BEGIN OPENSSH PRIVATE KEY-----\n$lines\n-----END OPENSSH PRIVATE KEY-----\n';
  }

  Uint8List _buildPubBlob(Uint8List pubBytes) {
    final b = BytesBuilder();
    _writeString(b, 'ssh-ed25519');
    _writeBytes(b, pubBytes);
    return b.toBytes();
  }

  Uint8List _buildPrivBlob(Uint8List pubBytes, Uint8List privBytes, String comment) {
    final checkInt = Random.secure().nextInt(0xFFFFFFFF);
    final b = BytesBuilder();
    _writeUint32(b, checkInt);
    _writeUint32(b, checkInt);
    _writeString(b, 'ssh-ed25519');
    _writeBytes(b, pubBytes);
    _writeBytes(b, privBytes);
    _writeString(b, comment); 
    int pad = 1;
    while (b.length % 8 != 0) {
      b.addByte(pad++);
    }
    return b.toBytes();
  }

  void _writeUint32(BytesBuilder b, int value) {
    b.addByte((value >> 24) & 0xFF);
    b.addByte((value >> 16) & 0xFF);
    b.addByte((value >> 8) & 0xFF);
    b.addByte(value & 0xFF);
  }

  void _writeString(BytesBuilder b, String s) {
    final bytes = utf8.encode(s);
    _writeUint32(b, bytes.length);
    b.add(bytes);
  }

  void _writeBytes(BytesBuilder b, Uint8List bytes) {
    _writeUint32(b, bytes.length);
    b.add(bytes);
  }
}

enum GgufDownloadStatus { downloading, completed, failed }

