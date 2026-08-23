/// WirelessPairingService — pont Dart ↔ Kotlin pour l'appairage wireless
/// debugging automatique, façon Shizuku.
///
/// Flux :
///   1. Vérifier que le NotificationListenerService est actif
///   2. Ouvrir les Options développeur → Débogage sans fil
///   3. L'utilisateur appuie sur "Associer avec un code"
///   4. Le listener Kotlin détecte la notification → stocke port + code
///   5. Dart poll ou callback récupère les données → adb pair automatique
///
/// Permissions nécessaires (gérées par le panneau) :
///   - POST_NOTIFICATIONS (Android 13+) — pour la notification de guide
///   - Notification Listener — pour lire les notifications système
///   - Ignorer optimisation batterie — pour que le service survive
library;

import 'dart:async';

import 'package:flutter/services.dart';

class WirelessPairingService {
  WirelessPairingService._();
  static final WirelessPairingService instance = WirelessPairingService._();

  static const _channel = MethodChannel('panda.ide/pairing');

  PairingData? _latest;
  PairingData? get latest => _latest;

  Stream<PairingData> get onDetected => _detectedController.stream;
  final _detectedController = StreamController<PairingData>.broadcast();

  Timer? _pollTimer;

  /// Vérifie si le NotificationListenerService est activé dans les settings.
  Future<bool> isNotificationListenerEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isNotificationListenerEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Ouvre la page des settings du NotificationListener.
  Future<void> openNotificationListenerSettings() async {
    try {
      await _channel.invokeMethod('openNotificationListenerSettings');
    } catch (_) {}
  }

  /// Ouvre les Options développeur (débogage USB / sans fil).
  Future<void> openDeveloperSettings() async {
    try {
      await _channel.invokeMethod('openDeveloperSettings');
    } catch (_) {}
  }

  /// Tente d'ouvrir directement la page Débogage sans fil (Android 11+).
  Future<void> openWirelessDebugging() async {
    try {
      await _channel.invokeMethod('openWirelessDebugging');
    } catch (_) {
      // Fallback : options développeur
      await openDeveloperSettings();
    }
  }

  /// Demande l'exemption d'optimisation batterie pour Panda IDE.
  Future<bool> requestIgnoreBatteryOptimization() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimization');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Vérifie si l'optimisation batterie est déjà désactivée.
  Future<bool> isIgnoringBatteryOptimization() async {
    try {
      final result = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimization');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Récupère les dernières données de pairing capturées par le listener Kotlin.
  Future<PairingData?> getLatestPairingData() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('getLatestPairingData');
      if (result == null) return null;
      final data = PairingData(
        ip: result['ip'] as String? ?? '127.0.0.1',
        port: result['port'] as String? ?? '',
        code: result['code'] as String? ?? '',
        timestamp: result['timestamp'] as int? ?? 0,
      );
      _latest = data;
      _detectedController.add(data);
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Démarre le polling pour détecter automatiquement le pairing.
  /// Appelle [onDetected] quand le listener Kotlin capture de nouvelles données.
  void startPolling({Duration interval = const Duration(milliseconds: 800)}) {
    stopPolling();
    _pollTimer = Timer.periodic(interval, (_) async {
      final data = await getLatestPairingData();
      if (data != null && _isNewer(data)) {
        _latest = data;
        _detectedController.add(data);
      }
    });
  }

  /// Arrête le polling.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  bool _isNewer(PairingData data) {
    final prev = _latest;
    if (prev == null) return true;
    return data.timestamp > prev.timestamp;
  }

  void dispose() {
    stopPolling();
    _detectedController.close();
  }
}

class PairingData {
  final String ip;
  final String port;
  final String code;
  final int timestamp;

  const PairingData({
    required this.ip,
    required this.port,
    required this.code,
    required this.timestamp,
  });

  bool get isComplete => port.isNotEmpty && code.length == 6;
}
