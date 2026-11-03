package com.hotshare.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val channelName = "com.hotshare.app/share_target"
    private var methodChannel: MethodChannel? = null
    private var pendingSharedFiles = mutableListOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialSharedFiles" -> {
                        val files = ArrayList(pendingSharedFiles)
                        pendingSharedFiles.clear()
                        result.success(files)
                    }
                    "clearShareCache" -> {
                        clearShareCache()
                        result.success(true)
                    }
                    "scanFile" -> {
                        val path = call.argument<String>("path")
                        if (path != null) {
                            android.media.MediaScannerConnection.scanFile(
                                applicationContext,
                                arrayOf(path),
                                null,
                                null
                            )
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Deliver pending files if already extracted before engine was ready
        if (pendingSharedFiles.isNotEmpty()) {
            val files = ArrayList(pendingSharedFiles)
            pendingSharedFiles.clear()
            methodChannel?.invokeMethod("onFilesShared", files)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.let { handleShareIntent(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    private fun handleShareIntent(intent: Intent) {
        val action = intent.action ?: return
        val type = intent.type ?: return

        if (action == Intent.ACTION_SEND) {
            val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (uri != null) {
                processUris(listOf(uri))
            } else {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (!text.isNullOrEmpty()) {
                    // Save shared text into a text file so transfer engine can send it
                    processSharedText(text)
                }
            }
        } else if (action == Intent.ACTION_SEND_MULTIPLE) {
            val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            if (!uris.isNullOrEmpty()) {
                processUris(uris)
            }
        }
    }

    private fun processUris(uris: List<Uri>) {
        thread {
            val copiedPaths = mutableListOf<String>()
            val cacheFolder = File(cacheDir, "share_incoming").apply { mkdirs() }

            for (uri in uris) {
                try {
                    val name = getFileName(uri) ?: "share_${System.currentTimeMillis()}"
                    val destDir = File(cacheFolder, UUID.randomUUID().toString()).apply { mkdirs() }
                    val destFile = File(destDir, name)

                    contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(destFile).use { output ->
                            input.copyTo(output)
                        }
                    }

                    if (destFile.exists() && destFile.length() > 0) {
                        copiedPaths.add(destFile.absolutePath)
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }

            if (copiedPaths.isNotEmpty()) {
                runOnUiThread {
                    if (methodChannel != null) {
                        methodChannel?.invokeMethod("onFilesShared", copiedPaths)
                    } else {
                        pendingSharedFiles.addAll(copiedPaths)
                    }
                }
            }
        }
    }

    private fun processSharedText(text: String) {
        thread {
            try {
                val cacheFolder = File(cacheDir, "share_incoming").apply { mkdirs() }
                val destDir = File(cacheFolder, UUID.randomUUID().toString()).apply { mkdirs() }
                val destFile = File(destDir, "shared_note_${System.currentTimeMillis()}.txt")
                destFile.writeText(text)

                runOnUiThread {
                    val paths = listOf(destFile.absolutePath)
                    if (methodChannel != null) {
                        methodChannel?.invokeMethod("onFilesShared", paths)
                    } else {
                        pendingSharedFiles.addAll(paths)
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun getFileName(uri: Uri): String? {
        if (uri.scheme == "content") {
            try {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index != -1) return cursor.getString(index)
                    }
                }
            } catch (_: Exception) {}
        }
        return uri.lastPathSegment
    }

    private fun clearShareCache() {
        thread {
            try {
                File(cacheDir, "share_incoming").deleteRecursively()
            } catch (_: Exception) {}
        }
    }
}
