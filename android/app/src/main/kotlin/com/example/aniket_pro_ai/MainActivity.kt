package com.example.aniket_pro_ai

import android.Manifest
import android.accounts.AccountManager
import android.app.Activity
import android.app.AlertDialog
import android.content.ContentObserver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.Settings
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class ShotWatcher(
    private val context: Context,
    private val handler: Handler,
    private val onShot: (Long, String) -> Unit
) : ContentObserver(handler) {

    private val seen = mutableMapOf<Long, Long>()

    private fun emitIfValid(uri: Uri, id: Long, allowPending: Boolean) {
        val projection = arrayOf(
            MediaStore.Images.Media.DATA,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.IS_PENDING
        )
        val cursor: Cursor? = try {
            context.contentResolver.query(uri, projection, null, null, null)
        } catch (e: Exception) {
            null
        }
        var path: String? = null
        var dateAdded: Long = 0
        var pendingFlag = 0
        if (cursor != null) {
            if (cursor.moveToFirst()) {
                val di = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
                val ti = cursor.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
                val pi = cursor.getColumnIndex(MediaStore.Images.Media.IS_PENDING)
                if (di >= 0) path = cursor.getString(di)
                if (ti >= 0) dateAdded = cursor.getLong(ti)
                if (pi >= 0) pendingFlag = cursor.getInt(pi)
            }
            cursor.close()
        }
        if (path == null) return
        if (path.contains(".pending", true)) return
        val low = path.lowercase()
        if (!low.contains("screenshot")) return
        val nowSec = System.currentTimeMillis() / 1000
        if ((nowSec - dateAdded) !in 0..120) return
        if (pendingFlag == 1 && !allowPending) {
            handler.postDelayed({ emitIfValid(uri, id, true) }, 2500)
            return
        }
        val now = SystemClock.uptimeMillis()
        val last = seen[id] ?: 0L
        if (now - last < 5000) return
        seen[id] = now
        if (seen.size > 60) seen.clear()
        handler.post { onShot(id, path) }
    }

    override fun onChange(selfChange: Boolean, uri: Uri?) {
        super.onChange(selfChange, uri)
        if (uri == null) return
        val id = uri.lastPathSegment?.toLongOrNull() ?: return
        emitIfValid(uri, id, false)
    }
}

class MainActivity : FlutterActivity() {

    private val GALLERY_CHANNEL = "aniket_pro_ai/gallery"
    private val SCREENSHOT_CHANNEL = "aniket_pro_ai/screenshot"
    private val PICK_REQ = 9002
    private val ACCOUNT_REQ = 7001
    private var screenshotChannel: MethodChannel? = null
    private var watcher: ShotWatcher? = null
    private var pendingPick: MethodChannel.Result? = null
    private var pendingAccount: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        screenshotChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
        BubbleService.onAction = { method, arg ->
            runOnUiThread { screenshotChannel?.invokeMethod(method, arg) }
        }
        setupGalleryChannel(flutterEngine)
        startWatcher()
    }

    private fun compressBytes(src: ByteArray, maxKB: Int): ByteArray {
        return try {
            var bmp = BitmapFactory.decodeByteArray(src, 0, src.size) ?: return src
            val maxDim = 2000
            if (bmp.width > maxDim || bmp.height > maxDim) {
                val scale = maxDim.toFloat() / Math.max(bmp.width, bmp.height)
                val w = (bmp.width * scale).toInt()
                val h = (bmp.height * scale).toInt()
                val scaled = Bitmap.createScaledBitmap(bmp, w, h, true)
                if (scaled != bmp) bmp.recycle()
                bmp = scaled
            }
            fun enc(q: Int): ByteArray {
                val bos = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.JPEG, q, bos)
                return bos.toByteArray()
            }
            var out = enc(90)
            if (out.size > maxKB * 1024) out = enc(80)
            if (out.size > maxKB * 1024) out = enc(70)
            if (out.size > maxKB * 1024) {
                val scale = 1600f / Math.max(bmp.width, bmp.height)
                if (scale < 1f) {
                    val s2 = Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true)
                    val bos = ByteArrayOutputStream()
                    s2.compress(Bitmap.CompressFormat.JPEG, 70, bos)
                    out = bos.toByteArray()
                    s2.recycle()
                }
            }
            bmp.recycle()
            out
        } catch (e: Exception) {
            src
        }
    }

    private fun setupGalleryChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GALLERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceId" -> {
                        val id = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: "unknown"
                        result.success("ANK-" + id.take(4).uppercase() + "-" + id.substring(4, 8).uppercase())
                    }
                    "compress" -> {
                        val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                        val maxKB = call.argument<Int>("maxKB") ?: 1024
                        result.success(compressBytes(bytes, maxKB))
                    }
                    "deleteFiles" -> {
                        val ids = (call.argument<List<Any>>("ids") ?: emptyList()).mapNotNull { (it as? Number)?.toLong() }
                        val paths = call.argument<List<String>>("paths") ?: emptyList()
                        handleDelete(ids, paths, result)
                    }
                    "pickFiles" -> {
                        pendingPick = result
                        val max = call.argument<Int>("max") ?: 6
                        launchPicker(max)
                    }
                    "pickGoogleAccount" -> {
                        pickGoogleAccount(result)
                    }
                    "toast" -> {
                        val m = call.arguments as? String ?: ""
                        Toast.makeText(applicationContext, m, Toast.LENGTH_SHORT).show()
                        result.success(1)
                    }
                    "errorPop" -> {
                        val m = call.arguments as? String ?: ""
                        BubbleService.showError(this, m)
                        result.success(1)
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
                        BubbleService.show(this)
                        result.success(1)
                    }
                    "hideBubble" -> {
                        BubbleService.hide(this)
                        result.success(1)
                    }
                    "bubbleAlive" -> result.success(BubbleService.instance != null)
                    "updateBubble" -> {
                        BubbleService.bText = call.argument<String>("text") ?: BubbleService.bText
                        BubbleService.bHtf = call.argument<Int>("htf") ?: BubbleService.bHtf
                        BubbleService.bEntry = call.argument<Int>("entry") ?: BubbleService.bEntry
                        BubbleService.bCorr = call.argument<Int>("corr") ?: BubbleService.bCorr
                        BubbleService.bActive = call.argument<String>("active") ?: "none"
                        BubbleService.bCapture = (call.argument<Int>("capture") ?: 1) == 1
                        BubbleService.instance?.refresh()
                        result.success(1)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickGoogleAccount(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.GET_ACCOUNTS) != PackageManager.PERMISSION_GRANTED) {
            pendingAccount = result
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.GET_ACCOUNTS), ACCOUNT_REQ)
            return
        }
        showAccountPicker(result)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == ACCOUNT_REQ) {
            val res = pendingAccount
            pendingAccount = null
            if (res != null) showAccountPicker(res)
        }
    }

    private fun showAccountPicker(result: MethodChannel.Result) {
        try {
            val am = AccountManager.get(this)
            val accounts = am.getAccountsByType("com.google")
            if (accounts.isEmpty()) {
                result.success(null)
                return
            }
            val names = accounts.map { it.name }.toTypedArray()
            val builder = AlertDialog.Builder(this)
            builder.setTitle("Choose Gmail")
            builder.setItems(names) { d, which ->
                d.dismiss()
                result.success(names[which])
            }
            builder.setOnCancelListener { result.success(null) }
            builder.show()
        } catch (e: Exception) {
            result.success(null)
        }
    }

    private fun launchPicker(max: Int = 6) {
        val intent = if (Build.VERSION.SDK_INT >= 33) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
                putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, max)
            }
        } else {
            Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "image/*"
                addCategory(Intent.CATEGORY_OPENABLE)
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, max > 1)
            }
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

    private fun handleDelete(ids: List<Long>, paths: List<String>, result: MethodChannel.Result) {
        val uris = mutableListOf<Uri>()
        for (id in ids) {
            val u = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
            try {
                contentResolver.query(u, arrayOf(MediaStore.Images.Media._ID), null, null, null)?.use { c ->
                    if (c.moveToFirst()) uris.add(u)
                }
            } catch (e: Exception) {
            }
        }
        if (uris.isEmpty()) {
            for (p in paths) {
                uriForPath(p)?.let { uris.add(it) }
            }
        }
        if (uris.isEmpty()) {
            result.success(0)
            return
        }
        try {
            val pendingIntent = MediaStore.createDeleteRequest(contentResolver, uris)
            Toast.makeText(applicationContext, "Tap Allow in system dialog — SS will be deleted", Toast.LENGTH_LONG).show()
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

    private fun startWatcher() {
        watcher = ShotWatcher(applicationContext, Handler(Looper.getMainLooper())) { id, path ->
            screenshotChannel?.invokeMethod("onScreenshot", hashMapOf<String, Any>("id" to id, "path" to path))
        }
        contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            watcher!!
        )
    }

    override fun onDestroy() {
        watcher?.let { contentResolver.unregisterContentObserver(it) }
        super.onDestroy()
    }
}
