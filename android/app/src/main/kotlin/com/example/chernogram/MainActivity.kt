package com.example.chernogram

import android.content.Context
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import android.os.VibrationEffect
import android.os.Vibrator
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Date

class MainActivity : AudioServiceActivity() {
    companion object {
        @Volatile
        private var crashHandlerInstalled = false
    }

    private val channelName = "chernogram/sound"
    private var incomingRingtone: Ringtone? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        if (!crashHandlerInstalled) {
            crashHandlerInstalled = true
            val previous = Thread.getDefaultUncaughtExceptionHandler()
            val appFiles = applicationContext.filesDir
            Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
                try {
                    val report = buildString {
                        appendLine("===== ${Date()} ANDROID NATIVE CRASH =====")
                        appendLine("Thread: ${thread.name}")
                        appendLine("Device: ${Build.MANUFACTURER} ${Build.MODEL}")
                        appendLine("Android: ${Build.VERSION.RELEASE} SDK ${Build.VERSION.SDK_INT}")
                        appendLine(throwable.stackTraceToString())
                        appendLine()
                    }
                    File(appFiles, "chernogram_native_crash.log").appendText(report)
                } catch (_: Throwable) {
                }
                if (previous != null) {
                    previous.uncaughtException(thread, throwable)
                } else {
                    android.os.Process.killProcess(android.os.Process.myPid())
                }
            }
        }
        super.onCreate(savedInstanceState)
    }

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
                    val customSound = call.argument<Boolean>("customSound") ?: false
                    if (!customSound) startIncomingCallSound()
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
}
