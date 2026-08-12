/// ModelNotificationService — Notifications Android pour les téléchargements de modèles.
///
/// Utilise flutter_local_notifications pour :
///   • Notification de progression persistante pendant le téléchargement.
///   • Notification de succès avec action "Charger le modèle".
///   • Notification d'erreur avec bouton "Réessayer".
///   • Canal Android dédié : panda_models (importance HIGH).
library;

import 'dart:async';
import 'dart:ui' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/model_download_manager.dart';

// ── IDs de notifications ──────────────────────────────────────────────────────

const _kProgressChannelId   = 'panda_models_progress';
const _kProgressChannelName = 'Téléchargement modèles IA';
const _kCompleteChannelId   = 'panda_models_complete';
const _kCompleteChannelName = 'Modèles IA prêts';
const _kBaseProgressId      = 5000; // IDs 5000-5099 pour les progressions
const _kBaseCompleteId      = 5100; // IDs 5100+ pour les succès/erreurs

// ── Service ───────────────────────────────────────────────────────────────────

class ModelNotificationService {
  ModelNotificationService._();
  static final ModelNotificationService instance = ModelNotificationService._();

  final _plugin      = FlutterLocalNotificationsPlugin();
  bool  _initialized = false;

  // Mapping taskId → notifId pour mise à jour / suppression
  final Map<String, int> _taskNotifIds = {};
  int _nextCompleteId = _kBaseCompleteId;

  StreamSubscription<DownloadTask>? _sub;

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    // Crée les canaux Android
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _kProgressChannelId,
          _kProgressChannelName,
          description: 'Progression du téléchargement des modèles IA locaux',
          importance: Importance.low, // LOW pour éviter le son à chaque update
          showBadge: false,
          playSound: false,
          enableVibration: false,
        ));

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _kCompleteChannelId,
          _kCompleteChannelName,
          description: 'Modèle IA téléchargé et prêt à utiliser',
          importance: Importance.high,
        ));

    // S'abonne aux mises à jour du DownloadManager
    _sub = ModelDownloadManager.instance.updates.listen(_onTaskUpdate);
  }

  void dispose() {
    _sub?.cancel();
  }

  // ── Handler principal ─────────────────────────────────────────────────────

  void _onTaskUpdate(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.verifying:
        _showProgress(task);
        break;
      case DownloadStatus.completed:
        _dismissProgress(task.taskId);
        _showSuccess(task);
        break;
      case DownloadStatus.failed:
        _dismissProgress(task.taskId);
        _showError(task);
        break;
      case DownloadStatus.cancelled:
        _dismissProgress(task.taskId);
        break;
      default:
        break;
    }
  }

  // ── Notification de progression ───────────────────────────────────────────

  Future<void> _showProgress(DownloadTask task) async {
    final notifId = _notifIdForTask(task.taskId);
    final pct     = (task.progress * 100).toInt();
    final dlTitle = task.status == DownloadStatus.verifying
        ? 'Vérification en cours…'
        : 'Téléchargement en cours';

    final speedStr = task.speedMbps > 0
        ? '${task.speedMbps.toStringAsFixed(1)} MB/s · '
        : '';
    final progressStr =
        '${(task.bytesDownloaded / (1024 * 1024 * 1024)).toStringAsFixed(2)} /'
        ' ${task.totalSizeGb.toStringAsFixed(2)} GB';

    final androidDetails = AndroidNotificationDetails(
      _kProgressChannelId,
      _kProgressChannelName,
      channelDescription: 'Progression du téléchargement des modèles IA locaux',
      importance:          Importance.low,
      priority:            Priority.low,
      ongoing:             true,
      autoCancel:          false,
      showProgress:        true,
      maxProgress:         100,
      progress:            pct,
      indeterminate:       task.status == DownloadStatus.verifying,
      subText:             '$speedStr$progressStr',
      icon:                '@mipmap/ic_launcher',
      // Bouton Annuler
      actions: [
        const AndroidNotificationAction(
          'cancel_download',
          'Annuler',
          cancelNotification: true,
          showsUserInterface: false,
        ),
      ],
    );

    await _plugin.show(
      notifId,
      dlTitle,
      _modelLabel(task),
      NotificationDetails(android: androidDetails),
      payload: 'download:${task.taskId}',
    );
  }

  // ── Notification de succès ────────────────────────────────────────────────

  Future<void> _showSuccess(DownloadTask task) async {
    final notifId = _nextCompleteId++;

    final androidDetails = AndroidNotificationDetails(
      _kCompleteChannelId,
      _kCompleteChannelName,
      channelDescription: 'Modèle IA téléchargé et prêt à utiliser',
      importance:         Importance.high,
      priority:           Priority.high,
      autoCancel:         true,
      icon:               '@mipmap/ic_launcher',
      color:              const Color(0xFF7C4DFF), // violet Panda
      actions: [
        const AndroidNotificationAction(
          'load_model',
          'Charger le modèle',
          showsUserInterface: true,
        ),
      ],
    );

    await _plugin.show(
      notifId,
      '✅ Modèle prêt',
      '${_modelLabel(task)} est téléchargé et prêt à utiliser',
      NotificationDetails(android: androidDetails),
      payload: 'ready:${task.taskId}',
    );
  }

  // ── Notification d'erreur ─────────────────────────────────────────────────

  Future<void> _showError(DownloadTask task) async {
    final notifId = _nextCompleteId++;

    final androidDetails = AndroidNotificationDetails(
      _kCompleteChannelId,
      _kCompleteChannelName,
      channelDescription: 'Modèle IA téléchargé et prêt à utiliser',
      importance:         Importance.defaultImportance,
      priority:           Priority.defaultPriority,
      autoCancel:         true,
      icon:               '@mipmap/ic_launcher',
      actions: [
        const AndroidNotificationAction(
          'retry_download',
          'Réessayer',
          showsUserInterface: true,
        ),
      ],
    );

    final errorMsg = task.errorMessage ?? 'Erreur inconnue';
    await _plugin.show(
      notifId,
      '❌ Échec du téléchargement',
      '${_modelLabel(task)} — $errorMsg',
      NotificationDetails(android: androidDetails),
      payload: 'error:${task.taskId}',
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int _notifIdForTask(String taskId) {
    if (!_taskNotifIds.containsKey(taskId)) {
      _taskNotifIds[taskId] = _kBaseProgressId + _taskNotifIds.length;
    }
    return _taskNotifIds[taskId]!;
  }

  Future<void> _dismissProgress(String taskId) async {
    final id = _taskNotifIds.remove(taskId);
    if (id != null) await _plugin.cancel(id);
  }

  String _modelLabel(DownloadTask task) =>
      '${task.modelId.replaceAll("-", " ")} ${task.quantLevel}';

  /// Annule toutes les notifications de progression actives.
  Future<void> cancelAll() async {
    for (final id in _taskNotifIds.values) {
      await _plugin.cancel(id);
    }
    _taskNotifIds.clear();
  }
}
