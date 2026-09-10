import 'package:flutter/foundation.dart';

/// Moteur réellement utilisé par la plateforme courante.
enum BrowserEngineKind { cef, nativeWebView, unavailable }

enum BrowserRuntimeStatus {
  checking,
  notInstalled,
  ready,
  corrupted,
  unsupported,
  error,
}

@immutable
class BrowserRuntimeSnapshot {
  final BrowserEngineKind engine;
  final BrowserRuntimeStatus status;
  final String? version;
  final String? installPath;
  final String? message;

  const BrowserRuntimeSnapshot({
    required this.engine,
    required this.status,
    this.version,
    this.installPath,
    this.message,
  });

  bool get isReady =>
      status == BrowserRuntimeStatus.ready ||
      engine == BrowserEngineKind.nativeWebView;

  String get engineLabel {
    switch (engine) {
      case BrowserEngineKind.cef:
        return 'CEF / Chromium';
      case BrowserEngineKind.nativeWebView:
        return 'WebView natif';
      case BrowserEngineKind.unavailable:
        return 'Aucun moteur';
    }
  }

  String get statusLabel {
    switch (status) {
      case BrowserRuntimeStatus.checking:
        return 'Vérification…';
      case BrowserRuntimeStatus.notInstalled:
        return 'Non installé';
      case BrowserRuntimeStatus.ready:
        return 'Prêt';
      case BrowserRuntimeStatus.corrupted:
        return 'Installation à réparer';
      case BrowserRuntimeStatus.unsupported:
        return 'Plateforme non supportée';
      case BrowserRuntimeStatus.error:
        return 'Erreur';
    }
  }
}
