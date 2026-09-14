package com.example.aniket_pro_ai

import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val GALLERY_CHANNEL = "aniket_pro_ai/gallery"
    private val SCREENSHOT_CHANNEL = "aniket_pro_ai/screenshot"
    private var screenshotChannel: MethodChannel? = null
    private var observer: ScreenshotObserver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        screenshotChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
        setupGalleryChannel(flutterEngine)
        startScreenshotObserver()
    }

    private fun setupGalleryChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GALLERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deleteFiles" -> {
                        val paths = call.argument<List<String>>("paths") ?: emptyList()
                        handleDelete(paths, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleDelete(paths: List<String>, result: MethodChannel.Result) {
        val uris = paths.mapNotNull { uriForPath(it) }
        if (uris.isEmpty()) { result.success(0); return }
        try {
            val pi = MediaStore.createDeleteRequest(this, uris)
            startIntentSenderForResult(pi.intentSender, 9001, null, 0, 0, 0)
            result.success(1)
        } catch (e: Exception) { result.error("DELETE_FAILED", e.message, null) }
    }

    private fun uriForPath(path: String): Uri? {
        val projection = arrayOf(MediaStore.Images.Media._ID)
        val selection = "${MediaStore.Images.Media.DATA}=?"
        contentResolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, projection, selection, arrayOf(path), null)?.use { c ->
            if (c.moveToFirst()) {
                val id = c.getLong(0)
                return ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
            }
        }
        return null
    }

    private fun startScreenshotObserver() {
        observer = ScreenshotObserver(applicationContext, Handler(Looper.getMainLooper())) { path ->
            screenshotChannel?.invokeMethod("onScreenshot", path)
        }
        contentResolver.registerContentObserver(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, observer!!)
    }

    override fun onDestroy() {
        super.onDestroy()
        observer?.let { contentResolver.unregisterContentObserver(it) }
    }

    class ScreenshotObserver(
        private val context: Context,
        private val handler: Handler,
        private val onScreenshot: (String) -> Unit
    ) : ContentObserver(handler) {
        private var lastPath = ""
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            super.onChange(selfChange, uri)
            uri?.let {
                val path = getPathFromUri(it)
                if (path != null && path != lastPath && path.contains("Screenshots", ignoreCase = true)) {
                    lastPath = path
                    handler.post { onScreenshot(path) }
                }
            }
        }
        private fun getPathFromUri(uri: Uri): String? {
            var path: String? = null
            val projection = arrayOf(MediaStore.Images.Media.DATA)
            val cursor: Cursor? = try { context.contentResolver.query(uri, projection, null, null, null) } catch (e: Exception) { null }
            cursor?.use { if (it.moveToFirst()) { path = it.getString(it.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)) } }
            cursor?.close()
            return path
        }
    }
}
