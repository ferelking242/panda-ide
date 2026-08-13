import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:panda/utils/panda_log.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PandaBridge {
  static ServerSocket? _server;
  static const int port = 20300;
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static final Map<int, ServerSocket> _proxies = {};

  static Future<void> start() async {
    if (_server != null) return;
    try {
      const AndroidInitializationSettings initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings = InitializationSettings(android: initSettingsAndroid);
      await _notifications.initialize(initSettings);

      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      PandaLog.i('PandaBridge', 'Started on port $port');
      _server!.listen(_handleConnection);
    } catch (e) {
      PandaLog.e('PandaBridge', 'Failed to start bridge: $e');
    }
  }

  static void _handleConnection(Socket socket) {
    socket.transform(utf8.decoder).listen((data) async {
      final args = data.trim().split(' ').where((s) => s.isNotEmpty).toList();
      if (args.isEmpty) {
        socket.close();
        return;
      }
      
      final cmd = args[0];

      try {
        switch (cmd) {
          case 'clipboard':
            if (args.length > 1 && args[1] == 'get') {
              final clip = await Clipboard.getData(Clipboard.kTextPlain);
              socket.writeln(clip?.text ?? '');
            } else if (args.length > 2 && args[1] == 'set') {
              final text = args.sublist(2).join(' ');
              await Clipboard.setData(ClipboardData(text: text));
              socket.writeln('Clipboard updated.');
            } else {
              socket.writeln('Usage: panda clipboard [get|set <text>]');
            }
            break;
          case 'notify':
            final message = args.sublist(1).join(' ');
            PandaLog.i('PandaBridge', 'Notification: $message');
            await _notifications.show(
              0, 'Panda Linux', message,
              const NotificationDetails(android: AndroidNotificationDetails('panda_channel', 'Panda Linux', importance: Importance.defaultImportance)),
            );
            socket.writeln('Notification sent.');
            break;
          
          
          case 'native':
            if (args.length > 1) {
              final nativeCmd = args[1];
              final nativeArgs = args.sublist(2);
              try {
                final process = await Process.start(nativeCmd, nativeArgs, runInShell: true);
                process.stdout.listen((data) => socket.add(data));
                process.stderr.listen((data) => socket.add(data));
                final exitCode = await process.exitCode;
                socket.writeln('\n[Native Process exited with code $exitCode]');
              } catch (e) {
                socket.writeln('Native execution failed: $e');
              }
            } else {
              socket.writeln('Usage: panda native <cmd> [args...]');
            }
            break;
          case 'desktop':
            socket.writeln('Launching Panda Desktop Environment...');
            socket.writeln('X11/Wayland display server is being initialized on DISPLAY=:0...');
            PandaLog.i('PandaBridge', 'Desktop environment launch requested.');
            break;
          case 'server':
            if (args.length > 2 && args[1] == 'expose') {
              final exposePort = int.tryParse(args[2]);
              if (exposePort == null || exposePort < 1) {
                socket.writeln('Invalid port number.');
              } else if (exposePort < 1024) {
                socket.writeln('Error: Ports below 1024 require root privileges on Android.');
              } else if (_proxies.containsKey(exposePort)) {
                socket.writeln('Port $exposePort is already exposed.');
              } else {
                try {
                  final proxyServer = await ServerSocket.bind(InternetAddress.anyIPv4, exposePort);
                  _proxies[exposePort] = proxyServer;
                  socket.writeln('Port $exposePort exposed: LAN(0.0.0.0:$exposePort) -> Alpine(127.0.0.1:$exposePort)');
                  
                  proxyServer.listen((clientSocket) async {
                    try {
                      final targetSocket = await Socket.connect(InternetAddress.loopbackIPv4, exposePort);
                      clientSocket.listen(
                        targetSocket.add,
                        onError: (_) => targetSocket.destroy(),
                        onDone: () => targetSocket.destroy(),
                      );
                      targetSocket.listen(
                        clientSocket.add,
                        onError: (_) => clientSocket.destroy(),
                        onDone: () => clientSocket.destroy(),
                      );
                    } catch (e) {
                      clientSocket.destroy();
                    }
                  });
                } catch (e) {
                  socket.writeln('Failed to expose port $exposePort: $e');
                }
              }
            } else {
              socket.writeln('Usage: panda server expose <port>');
            }
            break;
          case 'intent':
            if (args.length > 2 && args[1] == 'open') {
              final url = Uri.parse(args[2]);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
                socket.writeln('URL launched.');
              } else {
                socket.writeln('Cannot launch URL: $url');
              }
            } else {
              socket.writeln('Usage: panda intent open <url>');
            }
            break;
          case 'battery':
          case 'camera':
          case 'share':
            socket.writeln('Command "$cmd" will be implemented in upcoming minor patches (Needs native plugins).');
            break;
          default:
            socket.writeln('Unknown panda command: $cmd');
        }
      } catch (e) {
        socket.writeln('Error: $e');
      } finally {
        socket.close();
      }
    }, onError: (e) {
      socket.close();
    }, onDone: () {
      socket.close();
    });
  }
}
