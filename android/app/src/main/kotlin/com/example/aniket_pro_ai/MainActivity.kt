package com.example.aniket_pro_ai

import android.app.Activity
import android.app.AlertDialog
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.database.Cursor
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.TextView
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

    private var wm: WindowManager? = null
    private var bubbleView: TextView? = null
    private var bPending = 0
    private var bHtf = 0
    private var bEntry = 0
    private var bCorr = 0
    private var bCapture = true

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
                    "canOverlay" -> result.success(Settings.canDrawOverlays(this))
                    "openOverlaySettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                            result.success(1)
                        } catch (e: Exception) {
                            result.success(0)
                        }
                    }
                    "showBubble" -> {
                        showBubble()
                        result.success(1)
                    }
                    "hideBubble" -> {
                        hideBubble()
                        result.success(1)
                    }
                    "updateBubble" -> {
                        bPending = call.argument<Int>("pending") ?: bPending
                        bHtf = call.argument<Int>("htf") ?: bHtf
                        bEntry = call.argument<Int>("entry") ?: bEntry
                        bCorr = call.argument<Int>("corr") ?: bCorr
                        bCapture = (call.argument<Int>("capture") ?: 1) == 1
                        refreshBubble()
                        result.success(1)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun bubbleText(): String = "\uD83D\uDCF8 $bPending"

    private fun refreshBubble() {
        bubbleView?.let { v ->
            v.text = bubbleText()
            v.alpha = if (bCapture) 1.0f else 0.45f
        }
    }

    private fun showBubble() {
        if (bubbleView != null) return
        if (!Settings.canDrawOverlays(this)) return
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val view = TextView(this)
        view.text = bubbleText()
        view.setTextColor(Color.parseColor("#F5E6C8"))
        view.textSize = 18f
        view.gravity = Gravity.CENTER
        val gd = GradientDrawable()
        gd.setColor(Color.parseColor("#EE121212"))
        gd.cornerRadius = 60f
        gd.setStroke(3, Color.parseColor("#F5E6C8"))
        view.background = gd
        view.setPadding(44, 26, 44, 26)
        view.alpha = if (bCapture) 1.0f else 0.45f
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.END
        params.x = 24
        params.y = 140
        view.setOnTouchListener(DragListener(params, view))
        bubbleView = view
        try {
            wm?.addView(view, params)
        } catch (e: Exception) {
            bubbleView = null
        }
    }

    private fun hideBubble() {
        bubbleView?.let { v ->
            try {
                wm?.removeView(v)
            } catch (e: Exception) {
            }
        }
        bubbleView = null
    }

    private fun openMenu() {
        val items = arrayOf(
            "HTF  ($bHtf/6)",
            "ENTRY  ($bEntry/4)",
            "CORRELATION  ($bCorr/1)",
            "Close"
        )
        val builder = AlertDialog.Builder(this)
        builder.setTitle("Joma din  •  Pending: $bPending")
        builder.setItems(items) { d, which ->
            when (which) {
                0 -> screenshotChannel?.invokeMethod("onBubbleAction", "htf")
                1 -> screenshotChannel?.invokeMethod("onBubbleAction", "entry")
                2 -> screenshotChannel?.invokeMethod("onBubbleAction", "corr")
            }
            d.dismiss()
        }
        val dialog = builder.create()
        dialog.window?.setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY)
        try {
            dialog.show()
        } catch (e: Exception) {
        }
    }

    private inner class DragListener(
        private val params: WindowManager.LayoutParams,
        private val view: View
    ) : View.OnTouchListener {
        private val handler = Handler(Looper.getMainLooper())
        private var initialX = 0
        private var initialY = 0
        private var touchX = 0f
        private var touchY = 0f
        private var moved = false
        private var longFired = false
        private val longRun = Runnable {
            longFired = true
            openMenu()
        }

        override fun onTouch(v: View, e: MotionEvent): Boolean {
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    touchX = e.rawX
                    touchY = e.rawY
                    moved = false
                    longFired = false
                    handler.postDelayed(longRun, 700)
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (e.rawX - touchX).toInt()
                    val dy = (e.rawY - touchY).toInt()
                    if (!moved && (Math.abs(dx) > 10 || Math.abs(dy) > 10)) {
                        moved = true
                        handler.removeCallbacks(longRun)
                    }
                    if (moved) {
                        params.x = initialX - dx
                        params.y = initialY + dy
                        try {
                            wm?.updateViewLayout(view, params)
                        } catch (ex: Exception) {
                        }
                    }
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(longRun)
                    if (!moved && !longFired) {
                        screenshotChannel?.invokeMethod("onBubbleTap", null)
                    }
                    return true
                }
                MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longRun)
                    return true
                }
            }
            return false
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
