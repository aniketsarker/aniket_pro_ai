package com.example.aniket_pro_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Base64
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

// ═══════════════════════════════════════════════════════════════════
//  BINARY SIGNAL SERVICE (নতুন file — পুরানো code এ হাত দেওয়া হয়নি)
//  Floating button + screen capture + Gemini vision + result overlay
// ═══════════════════════════════════════════════════════════════════
class BinaryService : Service() {

    companion object {
        var instance: BinaryService? = null
        var projectionCode: Int = 0
        var projectionData: Intent? = null
        var keys: List<String> = emptyList()
        var pair: String = "EUR/USD"
        var time: String = "1m"
        var onResult: ((Map<String, Any>) -> Unit)? = null
    }

    private val main = Handler(Looper.getMainLooper())
    private var wm: WindowManager? = null
    private var projection: MediaProjection? = null
    private var floatView: TextView? = null
    private var resultView: LinearLayout? = null
    private var countView: TextView? = null
    private var busy = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel("bin_chan", "Binary Signal", NotificationManager.IMPORTANCE_LOW))
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: "FLOAT"
        if (action == "STOP") {
            stopSelf()
            return START_NOT_STICKY
        }
        intent?.getStringArrayListExtra("keys")?.let { keys = it }
        intent?.getStringExtra("pair")?.let { pair = it }
        intent?.getStringExtra("time")?.let { time = it }

        val nb = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "bin_chan")
        else @Suppress("DEPRECATION") Notification.Builder(this)
        nb.setContentTitle("ANIKET PRO AI")
            .setContentText("Binary signal active")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true)
        var started = false
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(9002, nb.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            } else {
                startForeground(9002, nb.build())
            }
            started = true
        } catch (e: Exception) {
            try { startForeground(9002, nb.build()); started = true } catch (_: Exception) {}
        }
        if (!started) { stopSelf(); return START_NOT_STICKY }

        if (projection == null) initProjection()
        showFloat()

        if (action == "ANALYZE_ONCE") {
            val delay = intent?.getIntExtra("delay", 6) ?: 6
            main.postDelayed({ analyze(delay) }, 800)
        }
        return START_STICKY
    }

    private fun initProjection() {
        try {
            if (projectionData == null) return
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            projection = mpm.getMediaProjection(projectionCode, projectionData!!)
        } catch (e: Exception) {
            projection = null
        }
    }

    // ── floating button ──
    private fun showFloat() {
        if (floatView != null) return
        if (!android.provider.Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "Overlay permission din", Toast.LENGTH_LONG).show()
            return
        }
        val v = TextView(this)
        v.text = "🎯"
        v.textSize = 20f
        v.gravity = Gravity.CENTER
        val bg = GradientDrawable()
        bg.setColor(0xE6F5E6C8.toInt())
        bg.cornerRadius = 60f
        v.background = bg
        v.setPadding(26, 26, 26, 26)
        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT)
        p.gravity = Gravity.END or Gravity.CENTER_VERTICAL
        v.setOnClickListener { analyze(0) }
        try {
            wm?.addView(v, p)
            floatView = v
        } catch (_: Exception) {}
    }

    // ── countdown overlay ──
    private fun showCount(n: Int) {
        main.post {
            try {
                if (countView == null) {
                    val t = TextView(this)
                    t.textSize = 60f
                    t.setTextColor(0xFFF5E6C8.toInt())
                    t.gravity = Gravity.CENTER
                    val p = WindowManager.LayoutParams(
                        WindowManager.LayoutParams.WRAP_CONTENT,
                        WindowManager.LayoutParams.WRAP_CONTENT,
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                        PixelFormat.TRANSLUCENT)
                    p.gravity = Gravity.CENTER
                    wm?.addView(t, p)
                    countView = t
                }
                countView?.text = if (n > 0) "$n" else "📸"
            } catch (_: Exception) {}
        }
    }

    private fun hideCount() {
        main.post {
            try { countView?.let { wm?.removeView(it) } } catch (_: Exception) {}
            countView = null
        }
    }

    // ── result overlay ──
    private fun showResult(dir: String, conf: Int, reason: String) {
        main.post {
            try {
                resultView?.let { wm?.removeView(it) }
                val box = LinearLayout(this)
                box.orientation = LinearLayout.VERTICAL
                box.gravity = Gravity.CENTER
                val bg = GradientDrawable()
                bg.setColor(0xF0121212.toInt())
                bg.cornerRadius = 40f
                bg.setStroke(3, if (dir == "UP") 0xFF0F9D58.toInt() else if (dir == "DOWN") 0xFFD93025.toInt() else 0xFF888888.toInt())
                box.background = bg
                box.setPadding(50, 34, 50, 34)

                val t1 = TextView(this)
                t1.text = "${if (dir == "UP") "⬆️" else if (dir == "DOWN") "⬇️" else "⏸️"} $dir  |  $conf%"
                t1.textSize = 30f
                t1.setTextColor(if (dir == "UP") 0xFF0F9D58.toInt() else if (dir == "DOWN") 0xFFD93025.toInt() else 0xFFCCCCCC.toInt())
                val t2 = TextView(this)
                t2.text = "$pair  •  $time"
                t2.textSize = 14f
                t2.setTextColor(0xFFF5E6C8.toInt())
                val t3 = TextView(this)
                t3.text = reason
                t3.textSize = 11f
                t3.setTextColor(0xFFAAAAAA.toInt())
                box.addView(t1); box.addView(t2); box.addView(t3)
                box.setOnClickListener {
                    try { wm?.removeView(box) } catch (_: Exception) {}
                    resultView = null
                }
                val p = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                    PixelFormat.TRANSLUCENT)
                p.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                p.y = 140
                wm?.addView(box, p)
                resultView = box
                main.postDelayed({
                    try { wm?.removeView(box) } catch (_: Exception) {}
                    if (resultView == box) resultView = null
                }, 9000)
            } catch (_: Exception) {}
        }
    }

    // ── analyze flow ──
    fun analyze(delaySec: Int) {
        if (busy) return
        busy = true
        Thread {
            try {
                var d = delaySec
                while (d > 0) {
                    showCount(d)
                    Thread.sleep(1000)
                    d--
                }
                showCount(0)
                Thread.sleep(400)
                hideCount()
                val bmp = capture()
                if (bmp == null) {
                    main.post { Toast.makeText(this, "Capture fail — projection restart koro", Toast.LENGTH_LONG).show() }
                    busy = false
                    return@Thread
                }
                val b64 = bmpToB64(bmp)
                val res = callGemini(b64)
                val dir = res.optString("dir", "WAIT")
                val conf = res.optInt("conf", 0)
                val reason = res.optString("reason", "")
                showResult(dir, conf, reason)
                val map = mapOf<String, Any>(
                    "dir" to dir, "conf" to conf, "reason" to reason,
                    "pair" to pair, "time" to time)
                main.post { onResult?.invoke(map) }
                appendHistory(dir, conf)
            } catch (e: Exception) {
                main.post { Toast.makeText(this, "Analysis fail: ${e.message}", Toast.LENGTH_LONG).show() }
            }
            busy = false
        }.start()
    }

    // ── screen capture ──
    private fun capture(): Bitmap? {
        val proj = projection ?: return null
        return try {
            val m = DisplayMetrics()
            @Suppress("DEPRECATION")
            wm?.defaultDisplay?.getRealMetrics(m)
            val w = m.widthPixels
            val h = m.heightPixels
            val dpi = m.densityDpi
            val reader = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
            val vd: VirtualDisplay = proj.createVirtualDisplay(
                "bin_cap", w, h, dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface, null, null)
            var bmp: Bitmap? = null
            val deadline = System.currentTimeMillis() + 2500
            while (System.currentTimeMillis() < deadline && bmp == null) {
                val img = reader.acquireLatestImage()
                if (img != null) {
                    val planes = img.planes
                    val buf = planes[0].buffer
                    val rowStride = planes[0].rowStride
                    val pixelStride = planes[0].pixelStride
                    val bw = buf.remaining()
                    val bytes = ByteArray(bw)
                    buf.get(bytes)
                    val full = Bitmap.createBitmap(rowStride / pixelStride, h, Bitmap.Config.ARGB_8888)
                    // RGBA → ARGB conversion row by row
                    val ints = IntArray(w * h)
                    var y = 0
                    while (y < h) {
                        var x = 0
                        while (x < w) {
                            val i = y * rowStride + x * pixelStride
                            if (i + 3 < bytes.size) {
                                val r = bytes[i].toInt() and 0xFF
                                val g = bytes[i + 1].toInt() and 0xFF
                                val b = bytes[i + 2].toInt() and 0xFF
                                ints[y * w + x] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
                            }
                            x++
                        }
                        y++
                    }
                    full.setPixels(ints, 0, w, 0, 0, w, h)
                    full.recycle()
                    bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                    bmp.setPixels(ints, 0, w, 0, 0, w, h)
                    img.close()
                } else {
                    Thread.sleep(120)
                }
            }
            vd.release()
            reader.close()
            bmp
        } catch (e: Exception) {
            null
        }
    }

    private fun bmpToB64(bmp: Bitmap): String {
        var b = bmp
        val maxDim = 1280
        if (b.width > maxDim || b.height > maxDim) {
            val s = maxDim.toFloat() / Math.max(b.width, b.height)
            b = Bitmap.createScaledBitmap(b, (b.width * s).toInt(), (b.height * s).toInt(), true)
        }
        val bos = ByteArrayOutputStream()
        b.compress(Bitmap.CompressFormat.JPEG, 80, bos)
        return Base64.encodeToString(bos.toByteArray(), Base64.NO_WRAP)
    }

    // ── Gemini vision + 12 key rotation ──
    private fun callGemini(b64: String): JSONObject {
        val prompt = "You are a professional binary options trader. Look at this trading " +
            "chart screenshot carefully (candles, trend, support/resistance). " +
            "Predict the NEXT candle direction for $pair on $time timeframe. " +
            "Reply ONLY with JSON like: {\"dir\":\"UP\",\"conf\":72,\"reason\":\"short Banglish reason\"} " +
            "dir must be UP or DOWN or WAIT. If chart is unclear or not a trading chart, use WAIT."
        for (key in keys) {
            try {
                val url = URL("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$key")
                val c = url.openConnection() as HttpURLConnection
                c.requestMethod = "POST"
                c.connectTimeout = 15000
                c.readTimeout = 30000
                c.doOutput = true
                c.setRequestProperty("Content-Type", "application/json")
                val body = JSONObject()
                val parts = org.json.JSONArray()
                parts.put(JSONObject().put("text", prompt))
                parts.put(JSONObject().put("inline_data",
                    JSONObject().put("mime_type", "image/jpeg").put("data", b64)))
                body.put("contents", org.json.JSONArray().put(
                    JSONObject().put("parts", parts)))
                c.outputStream.use { it.write(body.toString().toByteArray()) }
                val code = c.responseCode
                if (code == 200) {
                    val txt = c.inputStream.bufferedReader().use { it.readText() }
                    c.disconnect()
                    val j = JSONObject(txt)
                    val parts2 = j.optJSONArray("candidates")?.optJSONObject(0)
                        ?.optJSONObject("content")?.optJSONArray("parts")
                    var text = ""
                    if (parts2 != null) {
                        for (i in 0 until parts2.length()) text += parts2.optJSONObject(i)?.optString("text", "") ?: ""
                    }
                    val a = text.indexOf('{')
                    val z = text.lastIndexOf('}')
                    if (a >= 0 && z > a) return JSONObject(text.substring(a, z + 1))
                    return JSONObject().put("dir", "WAIT").put("conf", 0).put("reason", "parse fail")
                }
                c.disconnect()
                // 429/403/400 → next key
            } catch (_: Exception) {
                // next key
            }
        }
        return JSONObject().put("dir", "WAIT").put("conf", 0).put("reason", "sob key fail — net/key check koro")
    }

    private fun appendHistory(dir: String, conf: Int) {
        try {
            val f = java.io.File(filesDir, "binary_history.txt")
            val now = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date())
            val line = "$dir $conf% $pair $time $now"
            val old = if (f.exists()) f.readLines() else emptyList()
            val all = (listOf(line) + old).take(5)
            f.writeText(all.joinToString("\n"))
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try { floatView?.let { wm?.removeView(it) } } catch (_: Exception) {}
        try { resultView?.let { wm?.removeView(it) } } catch (_: Exception) {}
        try { countView?.let { wm?.removeView(it) } } catch (_: Exception) {}
        floatView = null; resultView = null; countView = null
        try { projection?.stop() } catch (_: Exception) {}
        projection = null
        instance = null
        super.onDestroy()
    }
}

// ===== END OF FILE BinaryService.kt =====
