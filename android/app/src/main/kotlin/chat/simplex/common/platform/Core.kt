package chat.simplex.common.platform

import android.content.Context
import java.io.File

// Имена top-level функций и имя файла Core.kt намеренно совпадают
// с официальным JNI ABI SimpleX: chat.simplex.common.platform.CoreKt.
typealias ChatCtrl = Long

external fun initHS()
external fun chatMigrateInit(
    dbPath: String,
    dbKey: String,
    confirm: String
): Array<Any>
external fun chatCloseStore(ctrl: ChatCtrl): String
external fun chatSendCmdRetry(ctrl: ChatCtrl, msg: String, retryNum: Int): String
external fun chatRecvMsgWait(ctrl: ChatCtrl, timeout: Int): String

object SimplexLabCore {
    @Volatile
    private var nativeLoaded = false

    @Volatile
    private var controller: ChatCtrl? = null

    @Synchronized
    private fun ensureNativeLoaded() {
        if (nativeLoaded) return
        System.loadLibrary("support")
        System.loadLibrary("simplex")
        System.loadLibrary("app-lib")
        initHS()
        nativeLoaded = true
    }

    @Synchronized
    fun initialize(context: Context): Map<String, Any> {
        ensureNativeLoaded()
        controller?.let { existing ->
            return mapOf(
                "state" to "ready",
                "controller" to existing.toString(),
                "reused" to true
            )
        }

        val directory = File(context.filesDir, "simplex_lab").apply { mkdirs() }
        val prefix = File(directory, "simplex_v1").absolutePath
        val migrated = chatMigrateInit(prefix, "", "yesUp")
        val migrationJson = migrated.getOrNull(0)?.toString().orEmpty()
        val ctrl = when (val raw = migrated.getOrNull(1)) {
            is Long -> raw
            is Number -> raw.toLong()
            else -> 0L
        }
        check(ctrl != 0L) {
            "SimpleX returned an empty controller: $migrationJson"
        }
        controller = ctrl
        return mapOf(
            "state" to "ready",
            "controller" to ctrl.toString(),
            "reused" to false,
            "databasePrefix" to prefix,
            "migration" to migrationJson
        )
    }

    @Synchronized
    fun sendCommand(command: String): String {
        val ctrl = controller ?: error("SimpleX core is not initialized")
        return chatSendCmdRetry(ctrl, command, 1)
    }

    @Synchronized
    fun receiveEvent(waitMicros: Int): String {
        val ctrl = controller ?: error("SimpleX core is not initialized")
        return chatRecvMsgWait(ctrl, waitMicros.coerceIn(0, 5_000_000))
    }

    @Synchronized
    fun close(): String {
        val ctrl = controller ?: return "already_closed"
        controller = null
        return chatCloseStore(ctrl)
    }
}
