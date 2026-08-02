package com.roxum

import android.content.Context
import com.google.android.play.core.splitcompat.SplitCompat
import com.google.android.play.core.splitinstall.SplitInstallManager
import com.google.android.play.core.splitinstall.SplitInstallManagerFactory
import com.google.android.play.core.splitinstall.SplitInstallRequest
import com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
import com.google.android.play.core.splitinstall.model.SplitInstallSessionStatus

class SplitInstallService(context: Context) {
    private val appContext = context.applicationContext
    private val splitInstallManager: SplitInstallManager =
        SplitInstallManagerFactory.create(appContext)

    private val listenersBySessionId = mutableMapOf<Int, SplitInstallStateUpdatedListener>()

    fun isModuleInstalled(moduleName: String): Boolean {
        return splitInstallManager.installedModules.contains(moduleName)
    }

    fun uninstallModule(moduleName: String) {
        splitInstallManager.deferredUninstall(listOf(moduleName))
    }

    fun refreshSplitCompat() {
        SplitCompat.install(appContext)
    }

    fun installModule(
        moduleName: String,
        onState: (Map<String, Any?>) -> Unit,
    ) {
        if (isModuleInstalled(moduleName)) {
            onState(
                mapOf(
                    "moduleName" to moduleName,
                    "status" to "installed",
                    "progress" to 100,
                    "bytesDownloaded" to 0L,
                    "totalBytesToDownload" to 0L,
                )
            )
            return
        }

        val request = SplitInstallRequest.newBuilder()
            .addModule(moduleName)
            .build()

        splitInstallManager.startInstall(request)
            .addOnSuccessListener { sessionId ->
                onState(
                    mapOf(
                        "moduleName" to moduleName,
                        "sessionId" to sessionId,
                        "status" to "pending",
                        "progress" to 0,
                        "bytesDownloaded" to 0L,
                        "totalBytesToDownload" to 0L,
                    )
                )

                val stateListener = SplitInstallStateUpdatedListener { state ->
                    if (state.sessionId() != sessionId) {
                        return@SplitInstallStateUpdatedListener
                    }

                    val statusCode = state.status()
                    val status = mapStatus(statusCode)
                    val progress = calculateProgress(
                        bytesDownloaded = state.bytesDownloaded(),
                        totalBytesToDownload = state.totalBytesToDownload(),
                        statusCode = statusCode,
                    )

                    onState(
                        mapOf(
                            "moduleName" to moduleName,
                            "sessionId" to sessionId,
                            "status" to status,
                            "progress" to progress,
                            "bytesDownloaded" to state.bytesDownloaded(),
                            "totalBytesToDownload" to state.totalBytesToDownload(),
                            "errorCode" to state.errorCode(),
                        )
                    )

                    if (statusCode == SplitInstallSessionStatus.INSTALLED) {
                        SplitCompat.install(appContext)
                    }

                    if (isTerminalStatus(statusCode)) {
                        unregisterSessionListener(sessionId)
                    }
                }

                listenersBySessionId[sessionId] = stateListener
                splitInstallManager.registerListener(stateListener)
            }
            .addOnFailureListener { exception ->
                onState(
                    mapOf(
                        "moduleName" to moduleName,
                        "status" to "failed",
                        "progress" to 0,
                        "errorMessage" to (exception.message ?: "Unknown install error"),
                    )
                )
            }
    }

    fun unregisterListener() {
        listenersBySessionId.values.forEach { listener ->
            splitInstallManager.unregisterListener(listener)
        }
        listenersBySessionId.clear()
    }

    private fun unregisterSessionListener(sessionId: Int) {
        val listener = listenersBySessionId.remove(sessionId) ?: return
        splitInstallManager.unregisterListener(listener)
    }

    private fun mapStatus(statusCode: Int): String {
        return when (statusCode) {
            SplitInstallSessionStatus.PENDING -> "pending"
            SplitInstallSessionStatus.DOWNLOADING -> "downloading"
            SplitInstallSessionStatus.DOWNLOADED -> "downloaded"
            SplitInstallSessionStatus.INSTALLING -> "installing"
            SplitInstallSessionStatus.INSTALLED -> "installed"
            SplitInstallSessionStatus.CANCELING -> "canceling"
            SplitInstallSessionStatus.CANCELED -> "canceled"
            SplitInstallSessionStatus.REQUIRES_USER_CONFIRMATION -> "requires_user_confirmation"
            SplitInstallSessionStatus.FAILED -> "failed"
            else -> "unknown"
        }
    }

    private fun isTerminalStatus(statusCode: Int): Boolean {
        return statusCode == SplitInstallSessionStatus.INSTALLED ||
            statusCode == SplitInstallSessionStatus.FAILED ||
            statusCode == SplitInstallSessionStatus.CANCELED
    }

    private fun calculateProgress(
        bytesDownloaded: Long,
        totalBytesToDownload: Long,
        statusCode: Int,
    ): Int {
        if (statusCode == SplitInstallSessionStatus.INSTALLED) {
            return 100
        }
        if (totalBytesToDownload <= 0L) {
            return 0
        }
        return ((bytesDownloaded * 100) / totalBytesToDownload).toInt().coerceIn(0, 100)
    }
}