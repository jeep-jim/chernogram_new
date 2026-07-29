package com.example.chernogram

import android.content.Context
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "chernogram/sound"
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
