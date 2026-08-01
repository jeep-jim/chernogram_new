package com.example.chernogram

import android.content.Context
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.VibrationEffect
import android.os.Vibrator
import chat.simplex.common.platform.SimplexLabCore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "chernogram/sound"
    private val simplexExecutor = Executors.newSingleThreadExecutor()
    private var incomingRingtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "playMessage" -> {
                    playNotificationSound()
                    vibrate(longArrayOf(0, 35))
                    result.success(null)
                }
                "startIncomingCall" -> {
                    startIncomingCallSound()
                    vibrate(longArrayOf(0, 450, 350, 450, 350, 450))
                    result.success(null)
                }
                "stopIncomingCall" -> {
                    stopIncomingCallSound()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "chernogram/storage"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getStorageStats") {
                val stat = StatFs(Environment.getDataDirectory().path)
                result.success(
                    mapOf(
                        "freeBytes" to stat.availableBytes,
                        "totalBytes" to stat.totalBytes
                    )
                )
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "chernogram/simplex_lab"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> runSimplex(result) {
                    SimplexLabCore.initialize(applicationContext)
                }
                "sendCommand" -> {
                    val command = call.argument<String>("command")?.trim().orEmpty()
                    if (command.isEmpty()) {
                        result.error("invalid_command", "Command is empty", null)
                    } else {
                        runSimplex(result) {
                            mapOf("response" to SimplexLabCore.sendCommand(command))
                        }
                    }
                }
                "receiveEvent" -> {
                    val waitMicros = call.argument<Int>("waitMicros") ?: 500_000
                    runSimplex(result) {
                        mapOf(
                            "event" to SimplexLabCore.receiveEvent(waitMicros)
                        )
                    }
                }
                "close" -> runSimplex(result) {
                    mapOf("response" to SimplexLabCore.close())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun runSimplex(
        result: MethodChannel.Result,
        block: () -> Any?
    ) {
        simplexExecutor.execute {
            try {
                val value = block()
                runOnUiThread { result.success(value) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error(
                        "simplex_core_error",
                        error.message ?: error.javaClass.simpleName,
                        error.stackTraceToString()
                    )
                }
            }
        }
    }

    private fun playNotificationSound() {
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        RingtoneManager.getRingtone(applicationContext, uri)?.play()
    }

    private fun startIncomingCallSound() {
        stopIncomingCallSound()
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        incomingRingtone = RingtoneManager.getRingtone(applicationContext, uri)?.also { ringtone ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ringtone.isLooping = true
            }
            ringtone.play()
        }
    }

    private fun stopIncomingCallSound() {
        incomingRingtone?.stop()
        incomingRingtone = null
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        vibrator.cancel()
    }

    @Suppress("DEPRECATION")
    private fun vibrate(pattern: LongArray) {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        if (!vibrator.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            vibrator.vibrate(pattern, -1)
        }
    }

    override fun onStop() {
        super.onStop()
        if (isFinishing) stopIncomingCallSound()
    }

    override fun onDestroy() {
        simplexExecutor.shutdownNow()
        super.onDestroy()
    }
}
