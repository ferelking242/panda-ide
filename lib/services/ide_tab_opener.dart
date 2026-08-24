/// IdeTabOpener — point d'entrée global pour ouvrir des onglets IDE
/// depuis n'importe quel widget, SANS Navigator.push fullscreen.
///
/// Utilisé par les pages marketplace/extensions/device_panel pour rester
/// DANS l'IDE au lieu de naviguer vers une page séparée.
///
/// Usage :
///   // Dans home.dart (initState) :
///   IdeTabOpener.instance.register(
///     openFlutterDevice: () { _openFlutterDeviceTab(); },
///     openTerminal: () { _openTerminalTab(); },
///   );
///
///   // Dans panda_registry_page.dart / device_panel / etc :
///   IdeTabOpener.instance.openFlutterDevice();
import 'package:flutter/material.dart';

library;


class IdeTabOpener extends ChangeNotifier {
  IdeTabOpener._();
  static final IdeTabOpener instance = IdeTabOpener._();

  VoidCallback? _openFlutterDevice;
  VoidCallback? _openTerminal;
  VoidCallback? _openMarketplace;

  /// Enregistré par home.dart au démarrage.
  void register({
    VoidCallback? openFlutterDevice,
    VoidCallback? openTerminal,
    VoidCallback? openMarketplace,
  }) {
    _openFlutterDevice = openFlutterDevice;
    _openTerminal = openTerminal;
    _openMarketplace = openMarketplace;
    notifyListeners();
  }

  void openFlutterDevice() => _openFlutterDevice?.call();
  void openTerminal() => _openTerminal?.call();
  void openMarketplace() => _openMarketplace?.call();
}
