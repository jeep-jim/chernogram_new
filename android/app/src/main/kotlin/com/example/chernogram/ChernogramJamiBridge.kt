package com.example.chernogram

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import net.jami.daemon.Blob
import net.jami.daemon.Callback
import net.jami.daemon.ConfigurationCallback
import net.jami.daemon.ConversationCallback
import net.jami.daemon.DataTransferCallback
import net.jami.daemon.IntVect
import net.jami.daemon.JamiService
import net.jami.daemon.NetworkServiceCallback
import net.jami.daemon.PresenceCallback
import net.jami.daemon.StringMap
import net.jami.daemon.StringVect
import net.jami.daemon.VideoCallback
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class ChernogramJamiBridge(
    private val context: Context,
    flutterEngine: FlutterEngine,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        METHOD_CHANNEL,
    )
    private val events = EventChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        EVENT_CHANNEL,
    )
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor()
    private val nativeLoaded = AtomicBoolean(false)
    private val daemonStarted = AtomicBoolean(false)

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var accountId: String = ""

    @Volatile
    private var registrationState: String = ""

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
        val id = accountId
        if (id.isNotEmpty()) emitIdentity(id)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call.argument<String>("nickname") ?: "Чернограм", result)
            "send" -> send(call, result)
            "exportArchive" -> exportArchive(call, result)
            else -> result.notImplemented()
        }
    }

    private fun initialize(nickname: String, result: MethodChannel.Result) {
        executor.execute {
            try {
                startDaemon()
                val id = ensureAccount(nickname)
                accountId = id
                JamiService.sendRegister(id, true)
                JamiService.registerAllAccounts()
                val identity = waitForIdentity(id)
                success(result, identity)
                emitIdentity(id)
            } catch (error: Throwable) {
                Log.e(TAG, "Unable to initialize the embedded Jami core", error)
                failure(result, "JAMI_INIT", error.message ?: error.javaClass.simpleName)
            }
        }
    }

    private fun send(call: MethodCall, result: MethodChannel.Result) {
        val peers = call.argument<List<Any?>>("peers")
            ?.mapNotNull { it?.toString()?.trim() }
            ?.filter { it.isNotEmpty() }
            ?.distinct()
            ?: emptyList()
        val payload = call.argument<String>("payload") ?: ""
        if (peers.isEmpty() || payload.isEmpty()) {
            result.success(emptyList<String>())
            return
        }
        executor.execute {
            try {
                startDaemon()
                val id = if (accountId.isNotEmpty()) accountId else ensureAccount("Чернограм")
                accountId = id
                val sent = ArrayList<String>(peers.size)
                for (peer in peers) {
                    try {
                        JamiService.addContact(id, peer)
                        val message = StringMap().apply {
                            setUnicode(MIME_CHERNOGRAM, payload)
                        }
                        val messageId = JamiService.sendAccountTextMessage(id, peer, message, 0)
                        sent.add(messageId.toString())
                    } catch (error: Throwable) {
                        Log.w(TAG, "Unable to send a Chernogram envelope to $peer", error)
                    }
                }
                success(result, sent)
            } catch (error: Throwable) {
                Log.e(TAG, "Unable to send through the embedded Jami core", error)
                failure(result, "JAMI_SEND", error.message ?: error.javaClass.simpleName)
            }
        }
    }

    private fun exportArchive(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")?.trim().orEmpty()
        val password = call.argument<String>("password") ?: ""
        if (path.isEmpty()) {
            result.error("JAMI_EXPORT", "Archive path is empty", null)
            return
        }
        executor.execute {
            try {
                startDaemon()
                val id = if (accountId.isNotEmpty()) accountId else ensureAccount("Чернограм")
                accountId = id
                File(path).parentFile?.mkdirs()
                val ok = JamiService.exportToFile(id, path, "", password)
                success(
                    result,
                    mapOf(
                        "ok" to ok,
                        "path" to path,
                        "accountId" to id,
                    ),
                )
            } catch (error: Throwable) {
                Log.e(TAG, "Unable to export the Jami account", error)
                failure(result, "JAMI_EXPORT", error.message ?: error.javaClass.simpleName)
            }
        }
    }

    @Synchronized
    private fun startDaemon() {
        if (daemonStarted.get()) return
        if (nativeLoaded.compareAndSet(false, true)) {
            System.loadLibrary("jami-core-jni")
        }
        JamiService.init(
            configurationCallback,
            callCallback,
            presenceCallback,
            dataTransferCallback,
            videoCallback,
            conversationCallback,
            networkCallback,
        )
        daemonStarted.set(true)
    }

    private fun ensureAccount(nickname: String): String {
        val existing = JamiService.getAccountList().firstOrNull()
        if (!existing.isNullOrEmpty()) {
            applyProfile(existing, nickname)
            return existing
        }
        val details = JamiService.getAccountTemplate("RING")
        details["Account.alias"] = nickname
        details["Account.displayName"] = nickname
        details["Account.enable"] = "true"
        details["Account.active"] = "true"
        details["Account.videoEnabled"] = "true"
        details["Account.peerDiscovery"] = "true"
        details["Account.accountDiscovery"] = "true"
        val created = JamiService.addAccount(details)
        check(created.isNotEmpty()) { "Jami core did not create an account" }
        applyProfile(created, nickname)
        return created
    }

    private fun applyProfile(id: String, nickname: String) {
        try {
            val details = JamiService.getAccountDetails(id)
            details["Account.alias"] = nickname
            details["Account.displayName"] = nickname
            details["Account.enable"] = "true"
            details["Account.active"] = "true"
            JamiService.setAccountDetails(id, details)
            JamiService.updateProfile(id, nickname, "", "", "", 0)
        } catch (error: Throwable) {
            Log.w(TAG, "Unable to update embedded Jami profile", error)
        }
    }

    private fun waitForIdentity(id: String): Map<String, Any> {
        var identity = identityMap(id)
        repeat(40) {
            if (identity["address"].toString().isNotEmpty()) return identity
            TimeUnit.MILLISECONDS.sleep(250)
            identity = identityMap(id)
        }
        return identity
    }

    private fun identityMap(id: String): Map<String, Any> {
        val details = JamiService.getAccountDetails(id)
        val volatile = try {
            JamiService.getVolatileAccountDetails(id)
        } catch (_: Throwable) {
            StringMap()
        }
        val state = volatile["Account.registrationStatus"]
            ?: volatile["Account.registrationState"]
            ?: registrationState
        if (!state.isNullOrEmpty()) registrationState = state
        return mapOf(
            "accountId" to id,
            "address" to (details["Account.username"] ?: ""),
            "deviceId" to (details["Account.deviceID"] ?: ""),
            "registrationState" to registrationState,
        )
    }

    private fun emitIdentity(id: String) {
        try {
            val event = HashMap<String, Any>(identityMap(id))
            event["type"] = "identity"
            emit(event)
        } catch (error: Throwable) {
            Log.w(TAG, "Unable to emit Jami identity", error)
        }
    }

    private fun emit(event: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(event) }
    }

    private fun success(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun failure(result: MethodChannel.Result, code: String, message: String) {
        mainHandler.post { result.error(code, message, null) }
    }

    fun detach() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        eventSink = null
    }

    private val configurationCallback = object : ConfigurationCallback() {
        override fun registrationStateChanged(
            account: String,
            state: String,
            code: Int,
            detailString: String,
        ) {
            registrationState = state
            emit(
                mapOf(
                    "type" to "registration",
                    "accountId" to account,
                    "state" to state,
                    "code" to code,
                    "detail" to detailString,
                ),
            )
            if (account == accountId || accountId.isEmpty()) emitIdentity(account)
        }

        override fun incomingAccountMessage(
            account: String,
            from: String,
            messageId: String,
            messages: StringMap,
        ) {
            val payload = messages[MIME_CHERNOGRAM] ?: return
            emit(
                mapOf(
                    "type" to "message",
                    "accountId" to account,
                    "from" to from,
                    "messageId" to messageId,
                    "payload" to payload,
                ),
            )
        }

        override fun incomingTrustRequest(
            account: String,
            conversationId: String,
            from: String,
            payload: Blob,
            received: Long,
        ) {
            executor.execute {
                try {
                    JamiService.acceptTrustRequest(account, from)
                    JamiService.addContact(account, from)
                } catch (error: Throwable) {
                    Log.w(TAG, "Unable to accept a Chernogram trust request", error)
                }
            }
        }

        override fun getHardwareAudioFormat(ret: IntVect) {
            var sampleRate = 48000
            var framesPerBuffer = 256
            try {
                val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                sampleRate = audio.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull()
                    ?: sampleRate
                framesPerBuffer = audio.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)?.toIntOrNull()
                    ?: framesPerBuffer
            } catch (_: Throwable) {
            }
            ret.add(sampleRate)
            ret.add(framesPerBuffer)
        }

        override fun getAppDataPath(name: String, ret: StringVect) {
            val path = when (name) {
                "files" -> context.filesDir
                "cache" -> context.cacheDir
                else -> context.getDir(name, Context.MODE_PRIVATE)
            }
            ret.add(path.absolutePath)
        }

        override fun getDeviceName(ret: StringVect) {
            ret.add("${Build.MANUFACTURER} ${Build.MODEL}".trim())
        }
    }

    private val callCallback = object : Callback() {}
    private val presenceCallback = object : PresenceCallback() {}
    private val dataTransferCallback = object : DataTransferCallback() {}
    private val videoCallback = object : VideoCallback() {}
    private val conversationCallback = object : ConversationCallback() {}
    private val networkCallback = object : NetworkServiceCallback() {}

    companion object {
        private const val TAG = "ChernogramJami"
        private const val METHOD_CHANNEL = "chernogram/jami"
        private const val EVENT_CHANNEL = "chernogram/jami/events"
        private const val MIME_CHERNOGRAM = "application/x-chernogram+json"
    }
}
