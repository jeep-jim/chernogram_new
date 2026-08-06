package com.example.chernogram

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "svet/native"
    private val pendingSharedFiles = mutableListOf<String>()
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        consumeShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeShareIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceName" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}".trim())
                    "takeSharedFiles" -> {
                        val files = synchronized(pendingSharedFiles) {
                            pendingSharedFiles.toList().also { pendingSharedFiles.clear() }
                        }
                        result.success(files)
                    }
                    "publishToDownloads" -> {
                        val path = call.argument<String>("path")
                        val name = call.argument<String>("name")
                        if (path.isNullOrBlank() || name.isNullOrBlank()) {
                            result.error("invalid_arguments", "path and name are required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(publishToDownloads(File(path), name).toString())
                        } catch (error: Throwable) {
                            result.error("publish_failed", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        if (pendingSharedFiles.isNotEmpty()) {
            channel?.invokeMethod("sharedFilesReady", null)
        }
    }

    private fun consumeShareIntent(source: Intent?) {
        if (source == null) return
        val uris = mutableListOf<Uri>()
        when (source.action) {
            Intent.ACTION_SEND -> readSingleUri(source)?.let(uris::add)
            Intent.ACTION_SEND_MULTIPLE -> readMultipleUris(source)?.let(uris::addAll)
        }
        if (uris.isEmpty()) return
        val copied = uris.mapNotNull(::copySharedUri)
        if (copied.isEmpty()) return
        synchronized(pendingSharedFiles) { pendingSharedFiles.addAll(copied) }
        channel?.invokeMethod("sharedFilesReady", null)
        source.action = null
    }

    @Suppress("DEPRECATION")
    private fun readSingleUri(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun readMultipleUris(intent: Intent): ArrayList<Uri>? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }

    private fun copySharedUri(uri: Uri): String? {
        val displayName = queryDisplayName(uri) ?: "shared_${System.currentTimeMillis()}"
        val safeName = displayName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val folder = File(cacheDir, "svet_share").apply { mkdirs() }
        var target = File(folder, safeName)
        var index = 1
        while (target.exists()) {
            val dot = safeName.lastIndexOf('.')
            val stem = if (dot > 0) safeName.substring(0, dot) else safeName
            val extension = if (dot > 0) safeName.substring(dot) else ""
            target = File(folder, "$stem ($index)$extension")
            index++
        }
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            target.absolutePath
        } catch (_: Throwable) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                }
        } catch (_: Throwable) {
            uri.lastPathSegment
        }
    }

    private fun publishToDownloads(source: File, requestedName: String): Uri {
        require(source.exists()) { "Temporary file does not exist" }
        val safeName = requestedName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/SVET")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = requireNotNull(
                contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ) { "Cannot create download entry" }
            try {
                contentResolver.openOutputStream(uri)?.use { output ->
                    FileInputStream(source).use { input -> input.copyTo(output) }
                } ?: error("Cannot open download output")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                uri
            } catch (error: Throwable) {
                contentResolver.delete(uri, null, null)
                throw error
            }
        } else {
            @Suppress("DEPRECATION")
            val directory = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "SVET"
            ).apply { mkdirs() }
            var target = File(directory, safeName)
            var index = 1
            while (target.exists()) {
                val dot = safeName.lastIndexOf('.')
                val stem = if (dot > 0) safeName.substring(0, dot) else safeName
                val extension = if (dot > 0) safeName.substring(dot) else ""
                target = File(directory, "$stem ($index)$extension")
                index++
            }
            source.copyTo(target)
            Uri.fromFile(target)
        }
    }
}
