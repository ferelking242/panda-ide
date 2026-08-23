package com.panda.ide

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * KeepAliveService — notification persistante « Panda IDE working ».
 *
 * Empêche Android (surtout Samsung/OneUI) de tuer le processus pendant :
 *   - une session terminal / proot active
 *   - un build flutter / apk install en cours
 *   - le serveur adb partagé
 *
 * Sans ça, quitter l'app 1 seconde coupe apk install au milieu.
 */
class KeepAliveService : Service() {

    companion object {
        const val CHANNEL_ID = "panda_keepalive"
        const val NOTIFICATION_ID = 4712

        @Volatile private var running = false

        fun start(context: Context) {
            if (running) return
            val intent = Intent(context, KeepAliveService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Exception) {
                // POST_NOTIFICATIONS refusée ou contexte non prêt — pas fatal
            }
        }

        fun stop(context: Context) {
            running = false
            context.stopService(Intent(context, KeepAliveService::class.java))
        }
    }

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Panda IDE",
                    NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Garde les sessions terminal et builds actifs"
                    setShowBadge(false)
                })
        }
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val builder: Notification
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder = androidx.core.app.NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_notify_sync_noanim)
                .setContentTitle("🐼 Panda IDE")
                .setContentText("Working — terminal et tâches protégés")
                .setOngoing(true)
                .setForegroundServiceBehavior(
                    androidx.core.app.NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .build()
        } else {
            @Suppress("DEPRECATION")
            builder = Notification.Builder(this)
                .setSmallIcon(android.R.drawable.stat_notify_sync_noanim)
                .setContentTitle("🐼 Panda IDE")
                .setContentText("Working — terminal et tâches protégés")
                .setOngoing(true)
                .build()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, builder,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, builder)
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }
}
