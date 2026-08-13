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
