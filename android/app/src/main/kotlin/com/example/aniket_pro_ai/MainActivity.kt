package com.example.aniket_pro_ai

import android.app.Activity
import android.content.ContentUris
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
    private val PICK_REQ = 9002
    private var screenshotChannel: MethodChannel? = null
    private var observer: ScreenshotObserver? = null
    private var pendingPick: MethodChannel.Result? = null

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
                    "pickFiles" -> {
                        pendingPick = result
                        launchPicker()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun launchPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            type = "image/*"
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        try {
            startActivityForResult(intent, PICK_REQ)
        } catch (e: Exception) {
            pendingPick?.success(emptyList<String>())
            pendingPick = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == PICK_REQ) {
            val res = pendingPick
            pendingPick = null
            if (res != null) {
                val paths = mutableListOf<String?>()
                if (resultCode == Activity.RESULT_OK && data != null) {
                    val clip = data.clipData
                    if (clip != null) {
                        for (i in 0 until clip.itemCount) {
                            paths.add(uriToPath(clip.getItemAt(i).uri))
                        }
                    } else {
                        data.data?.let { paths.add(uriToPath(it)) }
                    }
                }
                res.success(paths.filterNotNull())
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun uriToPath(uri: Uri): String? {
        val proj = arrayOf(MediaStore.Images.Media.DATA)
        contentResolver.query(uri, proj, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val idx = c.getColumnIndex(MediaStore.Images.Media.DATA)
                if (idx >= 0) {
                    val p = c.getString(idx)
                    if (!p.isNullOrEmpty()) return p
                }
            }
        }
        return try {
            val file = java.io.File(cacheDir, "pick_${System.currentTimeMillis()}.png")
            contentResolver.openInputStream(uri)?.use { input ->
                file.outputStream().use { output -> input.copyTo(output) }
            }
            file.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    private fun handleDelete(paths: List<String>, result: MethodChannel.Result) {
        val uris = paths.mapNotNull { uriForPath(it) }
        if (uris.isEmpty()) {
            result.success(0)
            return
        }
        try {
            val pendingIntent = MediaStore.createDeleteRequest(contentResolver, uris)
            startIntentSenderForResult(pendingIntent.intentSender, 9001, null, 0, 0, 0)
            result.success(1)
        } catch (e: Exception) {
            result.error("DELETE_FAILED", e.message, null)
        }
    }

    private fun uriForPath(path: String): Uri? {
        val projection = arrayOf(MediaStore.Images.Media._ID)
        val selection = MediaStore.Images.Media.DATA + "=?"
        val selectionArgs = arrayOf(path)
        val cursor: Cursor? = contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            null
        )
        var resultUri: Uri? = null
        if (cursor != null) {
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(0)
                resultUri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
            }
            cursor.close()
        }
        return resultUri
    }

    private fun startScreenshotObserver() {
        observer = ScreenshotObserver(applicationContext, Handler(Looper.getMainLooper())) { path ->
            screenshotChannel?.invokeMethod("onScreenshot", path)
        }
        contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            observer!!
        )
    }

    override fun onDestroy() {
        observer?.let { contentResolver.unregisterContentObserver(it) }
        super.onDestroy()
    }

    class ScreenshotObserver(
        private val context: Context,
        private val handler: Handler,
        private val onScreenshot: (String) -> Unit
    ) : ContentObserver(handler) {

        private var lastPath = ""

        override fun onChange(selfChange: Boolean, uri: Uri?) {
            super.onChange(selfChange, uri)
            uri?.let { u ->
                val path = getPathFromUri(u)
                if (path != null && path != lastPath && path.contains("Screenshots", ignoreCase = true)) {
                    lastPath = path
                    handler.post { onScreenshot(path) }
                }
            }
        }

        private fun getPathFromUri(uri: Uri): String? {
            var path: String? = null
            val projection = arrayOf(MediaStore.Images.Media.DATA)
            val cursor: Cursor? = try {
                context.contentResolver.query(uri, projection, null, null, null)
            } catch (e: Exception) {
                null
            }
            if (cursor != null) {
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
                    if (index >= 0) {
                        path = cursor.getString(index)
                    }
                }
                cursor.close()
            }
            return path
        }
    }
}
