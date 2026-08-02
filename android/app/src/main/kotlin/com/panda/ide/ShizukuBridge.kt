package com.panda.ide

import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import rikka.shizuku.Shizuku.OnRequestPermissionResultListener
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/**
 * ShizukuBridge wires Shizuku's privileged binder service to Flutter
 * via two channels:
 *
 *   MethodChannel  "com.panda.ide/shizuku"  — isAvailable, hasPermission,
 *                                              requestPermission, exec
 *   EventChannel   "com.panda.ide/shizuku_events" — live availability stream
 *
 * The Shizuku permission listener uses a request-code map so multiple
 * concurrent permission requests don't collide.
 */
object ShizukuBridge {

    private const val TAG = "ShizukuBridge"
    private const val METHOD_CHANNEL  = "com.panda.ide/shizuku"
    private const val EVENT_CHANNEL   = "com.panda.ide/shizuku_events"

    private val requestCode = AtomicInteger(1000)
    // requestCode → (result: Boolean?) pending permission callbacks
    private val pendingPermResults =
        ConcurrentHashMap<Int, MethodChannel.Result>()

    private var eventSink: EventChannel.EventSink? = null

    // ── Shizuku lifecycle listeners ──────────────────────────────────────────

    private val binderReceivedListener = Shizuku.OnBinderReceivedListener {
        Log.d(TAG, "Shizuku binder received")
        eventSink?.success("connected")
    }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        Log.d(TAG, "Shizuku binder dead")
        eventSink?.success("disconnected")
    }

    private val permissionResultListener =
        OnRequestPermissionResultListener { code, grantResult ->
            val result = pendingPermResults.remove(code)
            val granted = grantResult == PackageManager.PERMISSION_GRANTED
            Log.d(TAG, "Shizuku permission result code=$code granted=$granted")
            result?.success(granted)
        }

    // ── Registration ─────────────────────────────────────────────────────────

    fun register(flutterEngine: FlutterEngine) {
        Shizuku.addBinderReceivedListenerSticky(binderReceivedListener)
        Shizuku.addBinderDeadListener(binderDeadListener)
        Shizuku.addRequestPermissionResultListener(permissionResultListener)

        // ── MethodChannel ────────────────────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable"      -> result.success(isAvailable())
                "hasPermission"    -> result.success(hasPermission())
                "requestPermission"-> requestPermission(result)
                "exec"             -> {
                    val cmd = call.argument<String>("command")
                    if (cmd.isNullOrBlank()) {
                        result.error("INVALID", "command is required", null)
                    } else {
                        exec(cmd, result)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ── EventChannel ─────────────────────────────────────────────────────
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                // Emit initial state immediately
                events?.success(if (isAvailable()) "connected" else "disconnected")
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    fun unregister() {
        Shizuku.removeBinderReceivedListener(binderReceivedListener)
        Shizuku.removeBinderDeadListener(binderDeadListener)
        Shizuku.removeRequestPermissionResultListener(permissionResultListener)
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private fun isAvailable(): Boolean {
        return try {
            Shizuku.pingBinder()
        } catch (e: Throwable) {
            false
        }
    }

    private fun hasPermission(): Boolean {
        if (!isAvailable()) return false
        return try {
            if (Shizuku.isPreV11() || Shizuku.getVersion() < 11) {
                // API < 11: check self uid
                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
            } else {
                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
            }
        } catch (e: Throwable) {
            false
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (!isAvailable()) {
            result.success(false)
            return
        }
        if (hasPermission()) {
            result.success(true)
            return
        }
        val code = requestCode.incrementAndGet()
        pendingPermResults[code] = result
        try {
            Shizuku.requestPermission(code)
        } catch (e: Throwable) {
            pendingPermResults.remove(code)
            result.error("SHIZUKU_ERROR", e.message, null)
        }
    }

    /**
     * Execute a shell command via Shizuku's remote service.
     *
     * Shizuku runs commands as uid=2000 (ADB shell level) using
     * Runtime.exec via its privileged binder — no root required.
     */
    private fun exec(command: String, result: MethodChannel.Result) {
        if (!isAvailable()) {
            result.error("UNAVAILABLE", "Shizuku is not running", null)
            return
        }
        if (!hasPermission()) {
            result.error("NO_PERMISSION", "Shizuku permission not granted", null)
            return
        }

        // Run on a background thread — never block the main thread
        Thread {
            try {
                // Shizuku's exec goes through its remote service which runs
                // at ADB privilege level. We use the Shizuku.newProcess API.
                val process = Shizuku.newProcess(
                    arrayOf("sh", "-c", command),
                    null, // inherit env
                    null  // inherit cwd
                )

                val stdout = process.inputStream.bufferedReader().readText()
                val stderr = process.errorStream.bufferedReader().readText()
                val exitCode = process.waitFor()

                result.success(mapOf(
                    "exitCode" to exitCode,
                    "stdout"   to stdout,
                    "stderr"   to stderr,
                ))
            } catch (e: Throwable) {
                Log.e(TAG, "exec failed: ${e.message}")
                result.error("EXEC_ERROR", e.message, null)
            }
        }.start()
    }
}
