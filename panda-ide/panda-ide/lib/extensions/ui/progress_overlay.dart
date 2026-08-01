/// Gestionnaire du progress overlay pour vscode.window.withProgress().
/// Supporte les 3 locations : Notification (overlay), Window (titre), SourceControl.
library;

import 'package:flutter/material.dart';

// ── Modèle ────────────────────────────────────────────────────────────────

enum ProgressLocation { sourceControl, window, notification }

class _ProgressState {
  final String title;
  final ProgressLocation location;
  String? message;
  double? increment; // 0-100
  double _total = 0;
  bool cancellable;

  _ProgressState({
    required this.title,
    required this.location,
    this.cancellable = false,
  });

  bool get isIndeterminate => increment == null;

  double get fraction => (_total / 100).clamp(0.0, 1.0);

  void applyReport(Map<String, dynamic> data) {
    if (data['message'] != null) message = data['message'] as String;
    if (data['increment'] != null) {
      final inc = (data['increment'] as num).toDouble();
      _total = (_total + inc).clamp(0.0, 100.0);
      increment = inc;
    }
  }
}

// ── Singleton manager ─────────────────────────────────────────────────────

class ProgressOverlayManager extends ChangeNotifier {
  static final ProgressOverlayManager instance = ProgressOverlayManager._();
  ProgressOverlayManager._();

  _ProgressState? _current;
  OverlayEntry? _overlayEntry;
  BuildContext? _context;

  bool get isActive => _current != null;
  _ProgressState? get current => _current;

  void start(BuildContext context, Map<String, dynamic> options) {
    _context = context;

    final locInt = (options['location'] as num?)?.toInt() ?? 15;
    final location = switch (locInt) {
      1  => ProgressLocation.sourceControl,
      10 => ProgressLocation.window,
      _  => ProgressLocation.notification,
    };

    _current = _ProgressState(
      title: options['title'] as String? ?? '',
      location: location,
      cancellable: options['cancellable'] as bool? ?? false,
    );

    if (location == ProgressLocation.notification) {
      _showOverlay(context);
    }

    notifyListeners();
  }

  void report(Map<String, dynamic> data) {
    _current?.applyReport(data);
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }
    notifyListeners();
  }

  void end() {
    _removeOverlay();
    _current = null;
    notifyListeners();
  }

  void _showOverlay(BuildContext context) {
    _removeOverlay();
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (_) => _ProgressOverlayWidget(
        manager: this,
        onDismiss: end,
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

// ── Widget Overlay ────────────────────────────────────────────────────────

class _ProgressOverlayWidget extends StatelessWidget {
  final ProgressOverlayManager manager;
  final VoidCallback onDismiss;

  const _ProgressOverlayWidget({
    required this.manager,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (ctx, _) {
        final state = manager.current;
        if (state == null) return const SizedBox.shrink();

        return Positioned(
          bottom: 48, // au-dessus de la status bar
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xff252526),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xff3c3c3c)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Titre + bouton annuler
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          state.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (state.cancellable)
                        GestureDetector(
                          onTap: onDismiss,
                          child: const Icon(
                            Icons.close,
                            color: Color(0xff858585),
                            size: 16,
                          ),
                        ),
                    ],
                  ),

                  // Message
                  if (state.message != null && state.message!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      state.message!,
                      style: const TextStyle(
                        color: Color(0xff858585),
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 10),

                  // Barre de progression
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: state.isIndeterminate
                        ? const LinearProgressIndicator(
                            backgroundColor: Color(0xff3c3c3c),
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xff5090c8)),
                            minHeight: 3,
                          )
                        : LinearProgressIndicator(
                            value: state.fraction,
                            backgroundColor: const Color(0xff3c3c3c),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xff5090c8)),
                            minHeight: 3,
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Widget inline (pour ProgressLocation.window) ──────────────────────────
//
// Usage dans la barre de titre ou status bar de l'app :
//   WindowProgressIndicator()

class WindowProgressIndicator extends StatelessWidget {
  const WindowProgressIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProgressOverlayManager.instance,
      builder: (ctx, _) {
        final state = ProgressOverlayManager.instance.current;
        if (state == null ||
            state.location != ProgressLocation.window) {
          return const SizedBox.shrink();
        }

        return SizedBox(
          width: 100,
          height: 3,
          child: state.isIndeterminate
              ? const LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xff5090c8)),
                  minHeight: 3,
                )
              : LinearProgressIndicator(
                  value: state.fraction,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xff5090c8)),
                  minHeight: 3,
                ),
        );
      },
    );
  }
}
