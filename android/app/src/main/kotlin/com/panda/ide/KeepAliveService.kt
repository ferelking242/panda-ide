package com.panda.ide

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.net.wifi.WifiManager
import androidx.core.app.NotificationCompat

/**
 * Foreground owner for long-running terminal, build and agent work.
 *
 * The Dart UI reports one task id per live runtime. The service keeps the
 * process important while at least one task is active and releases the CPU
 * wakelock as soon as the last task ends.
 */
class KeepAliveService : Service() {

    companion object {
        const val CHANNEL_ID = "panda_keepalive"
        const val NOTIFICATION_ID = 4712
        private const val ACTION_START = "com.panda.ide.keepalive.START"
        private const val ACTION_STOP = "com.panda.ide.keepalive.STOP"
        private const val ACTION_STOP_ALL = "com.panda.ide.keepalive.STOP_ALL"
        private const val ACTION_UPDATE = "com.panda.ide.keepalive.UPDATE"
        private const val EXTRA_TASK_ID = "task_id"
        private const val EXTRA_TASK_LABEL = "task_label"
        private const val PREFS = "panda_keepalive"
        private const val TASKS_KEY = "active_tasks"
        private const val LABELS_KEY = "task_labels"

        fun start(context: Context, taskId: String = "terminal", label: String = "Terminal") {
            val intent = Intent(context, KeepAliveService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TASK_ID, taskId)
                putExtra(EXTRA_TASK_LABEL, label)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (error: Exception) {
                android.util.Log.e(
                    "KeepAliveService",
                    "Unable to start foreground service",
                    error,
                )
            }
        }

        fun stop(context: Context, taskId: String = "terminal") {
            val intent = Intent(context, KeepAliveService::class.java).apply {
                action = ACTION_STOP
                putExtra(EXTRA_TASK_ID, taskId)
            }
            try {
                context.startService(intent)
            } catch (error: IllegalStateException) {
                // If Android already reclaimed the service, there is nothing
                // left to decrement; ensure the notification is removed.
                context.stopService(intent)
                android.util.Log.w("KeepAliveService", "Stop after service reclaim", error)
            }
        }

        fun update(context: Context, taskId: String, label: String) {
            context.startService(
                Intent(context, KeepAliveService::class.java).apply {
                    action = ACTION_UPDATE
                    putExtra(EXTRA_TASK_ID, taskId)
                    putExtra(EXTRA_TASK_LABEL, label)
                }
            )
        }
    }

    private val activeTasks = linkedSetOf<String>()
    private val taskLabels = linkedMapOf<String, String>()
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        restoreTasks()
        // A foreground-service start must be promoted quickly. The
        // notification is refreshed with the real task label in onStartCommand.
        promoteToForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val id = intent.getStringExtra(EXTRA_TASK_ID)
                    .orEmpty().ifBlank { "terminal" }
                val label = intent.getStringExtra(EXTRA_TASK_LABEL)
                    .orEmpty().ifBlank { "Terminal" }
                activeTasks.add(id)
                taskLabels[id] = label
                persistTasks()
                acquireWakeLock()
                acquireWifiLock()
                promoteToForeground()
            }
            ACTION_UPDATE -> {
                val id = intent.getStringExtra(EXTRA_TASK_ID)
                    .orEmpty().ifBlank { "terminal" }
                taskLabels[id] = intent.getStringExtra(EXTRA_TASK_LABEL)
                    .orEmpty().ifBlank { taskLabels[id] ?: "Terminal" }
                persistTasks()
                promoteToForeground()
            }
            ACTION_STOP -> {
                intent.getStringExtra(EXTRA_TASK_ID)?.let {
                    activeTasks.remove(it)
                    taskLabels.remove(it)
                }
                persistTasks()
                if (activeTasks.isEmpty()) {
                    releaseWakeLock()
                    releaseWifiLock()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelfResult(startId)
                } else {
                    promoteToForeground()
                }
            }
            ACTION_STOP_ALL -> {
                activeTasks.clear()
                taskLabels.clear()
                persistTasks()
                releaseWakeLock()
                releaseWifiLock()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelfResult(startId)
            }
            else -> {
                if (activeTasks.isNotEmpty()) {
                    acquireWakeLock()
                    acquireWifiLock()
                    promoteToForeground()
                } else {
                    releaseWakeLock()
                    releaseWifiLock()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelfResult(startId)
                }
            }
        }
        return if (activeTasks.isEmpty()) START_NOT_STICKY else START_STICKY
    }

    private fun createNotificationChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Panda IDE",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Garde les sessions terminal et builds actifs"
                    setShowBadge(false)
                },
            )
        }
    }

    private fun restoreTasks() {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        activeTasks.addAll(prefs.getStringSet(TASKS_KEY, emptySet()).orEmpty())
        prefs.getStringSet(LABELS_KEY, emptySet()).orEmpty().forEach { entry ->
            val separator = entry.indexOf('\u0000')
            if (separator > 0) {
                taskLabels[entry.substring(0, separator)] = entry.substring(separator + 1)
            }
        }
    }

    private fun persistTasks() {
        val labels = taskLabels.map { (id, label) -> "$id\u0000$label" }.toSet()
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putStringSet(TASKS_KEY, activeTasks.toSet())
            .putStringSet(LABELS_KEY, labels)
            .apply()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "PandaIDE:terminal-build",
        ).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    /**
     * A partial CPU wakelock does not prevent Wi-Fi from being suspended by
     * Doze. Keep the network transport awake while a terminal/build/agent
     * task is explicitly active.
     */
    private fun acquireWifiLock() {
        if (wifiLock?.isHeld == true) return
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        wifiLock = wifi.createWifiLock(
            WifiManager.WIFI_MODE_FULL_HIGH_PERF,
            "PandaIDE:network",
        ).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWifiLock() {
        wifiLock?.let {
            if (it.isHeld) it.release()
        }
        wifiLock = null
    }

    private fun promoteToForeground() {
        val currentLabel = activeTasks
            .asSequence()
            .mapNotNull { taskLabels[it] }
            .firstOrNull()
            ?: "Terminal"
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                4713,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag(),
            )
        }
        val stopIntent = PendingIntent.getService(
            this,
            4714,
            Intent(this, KeepAliveService::class.java).apply {
                action = ACTION_STOP_ALL
            },
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag(),
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync_noanim)
            .setContentTitle("Panda IDE — tâche en cours")
            .setContentText("$currentLabel continue en arrière-plan")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_media_pause,
                    "Arrêter",
                    stopIntent,
                ).build(),
            )
            .apply {
                if (contentIntent != null) setContentIntent(contentIntent)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    setForegroundServiceBehavior(
                        NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE,
                    )
                }
            }
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun pendingIntentImmutableFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        releaseWakeLock()
        releaseWifiLock()
        super.onDestroy()
    }
}