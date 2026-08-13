import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:panda/utils/panda_log.dart';

class PandaBridge {
  static ServerSocket? _server;
  static const int port = 20300;

  static Future<void> start() async {
    if (_server != null) return;
    try {
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
            socket.writeln('Notification logged.');
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
