package com.panda.ide

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * PairingNotificationListener — écoute les notifications système pour
 * capturer automatiquement le code et le port d'appairage wireless debugging.
 *
 * Quand l'utilisateur appuie sur "Associer l'appareil avec un code d'association"
 * dans les Options développeurs → Débogage sans fil, Android affiche un popup
 * avec IP:PORT et un code à 6 chiffres. Android publie aussi une notification
 * contenant ces informations. Ce service la lit et les stocke dans
 * [PairingDataHolder] pour que Dart puisse les récupérer via MethodChannel.
 *
 * Modèle inspiré de Shizuku.
 */
class PairingNotificationListener : NotificationListenerService() {

    companion object {
        /** Dernière donnée d'appairage capturée. */
        var latestPairing: PairingData? = null
            private set

        /** Callback invoqué quand de nouvelles données sont détectées. */
        var onPairingDetected: ((PairingData) -> Unit)? = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // Filtrer : uniquement les notifications du système/settings
        val pkg = sbn.packageName
        val isSystemNotif = pkg == "com.android.settings" ||
                pkg == "com.android.systemui" ||
                pkg.contains("settings", ignoreCase = true) ||
                pkg.contains("systemui", ignoreCase = true)

        if (!isSystemNotif) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        // Extraire titre et texte
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""

        val combined = "$title $text $bigText $subText"

        // Chercher un code à 6 chiffres (appairage wireless debugging)
        val codeRegex = Regex("""\b(\d{6})\b""")
        val codeMatch = codeRegex.find(combined) ?: return

        // Chercher un port (4-5 chiffres, souvent après un : ou un espace)
        val portRegex = Regex("""[:\s](\d{4,5})\b""")
        val portMatch = portRegex.find(combined.replace(codeMatch.value, ""))

        // Chercher une IP
        val ipRegex = Regex("""(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})""")
        val ipMatch = ipRegex.find(combined)

        val code = codeMatch.groupValues[1]
        val port = portMatch?.groupValues?.getOrNull(1) ?: ""
        val ip = ipMatch?.groupValues?.getOrNull(1) ?: "127.0.0.1"

        val data = PairingData(
            ip = ip,
            port = port,
            code = code,
            timestamp = System.currentTimeMillis()
        )

        latestPairing = data
        onPairingDetected?.invoke(data)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // Ne rien faire — on garde les dernières données
    }
}

/**
 * Données d'appairage extraites de la notification système.
 */
data class PairingData(
    val ip: String,
    val port: String,
    val code: String,
    val timestamp: Long,
)
