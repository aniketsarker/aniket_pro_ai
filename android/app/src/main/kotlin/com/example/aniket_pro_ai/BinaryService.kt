package com.example.aniket_pro_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Base64
import android.view.Gravity
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

// ═══════════════════════════════════════════════════════════════════
//  BINARY SIGNAL SERVICE — AUTO MODE (forex এর ShotWatcher reuse)
//  capture ON থাকলে: screenshot হলেই সাথে সাথে analysis
// ═══════════════════════════════════════════════════════════════════
class BinaryService : Service() {

    companion object {
        var instance: BinaryService? = null
        var keys: List<String> = emptyList()
        var pair: String = "EUR/USD"
        var time: String = "1m"
        var captureOn: Boolean = false
        var lastId: Long = 0
        var onResult: ((Map<String, Any>) -> Unit)? = null
    }

    private val main = Handler(Looper.getMainLooper())
    private var wm: WindowManager? = null
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
            .setContentText("Binary capture ON — screenshot nilei analysis")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true)
        var started = false
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(9002, nb.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(9002, nb.build())
            }
            started = true
        } catch (e: Exception) {
            try { startForeground(9002, nb.build()); started = true } catch (_: Exception) {}
        }
        if (!started) { stopSelf(); return START_NOT_STICKY }

        captureOn = true
        showFloat()
        main.post {
            Toast.makeText(this,
                "🎯 Binary capture ON — ekhon screenshot nilei auto analysis hobe",
                Toast.LENGTH_LONG).show()
        }
        return START_STICKY
    }

    // ── floating 🎯 (tap = capture ON/OFF) ──
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
        v.setOnClickListener { toggleCapture() }
        try {
            wm?.addView(v, p)
            floatView = v
        } catch (_: Exception) {}
    }

    private fun toggleCapture() {
        captureOn = !captureOn
        main.post {
            Toast.makeText(this,
                if (captureOn) "🎯 Capture ON — ss nilei analysis"
                else "🎯 Capture OFF — ss analysis hobe na",
                Toast.LENGTH_SHORT).show()
        }
        try {
            onResult?.invoke(mapOf<String, Any>(
                "dir" to "STATE", "conf" to (if (captureOn) 1 else 0),
                "reason" to "", "pair" to pair, "time" to time))
        } catch (_: Exception) { }
    }

    // ── ShotWatcher থেকে ss এলেই সাথে সাথে analysis (forex এর same path) ──
    fun onScreenshotReceived(id: Long, path: String) {
        if (!captureOn) return
        if (id <= lastId) return
        lastId = id
        analyze(path)
    }

    private fun analyze(path: String) {
        if (busy) return
        busy = true
        Thread {
            try {
                val f = File(path)
                if (!f.exists()) {
                    main.post { Toast.makeText(this, "SS file missing", Toast.LENGTH_SHORT).show() }
                    busy = false
                    return@Thread
                }
                main.post { showCount("🧠") }
                val b64 = bytesToB64(f.readBytes())
                val res = callGemini(b64)
                val dir = res.optString("dir", "WAIT")
                val conf = res.optInt("conf", 0)
                val reason = res.optString("reason", "")
                main.post { hideCount() }
                main.post { showResult(dir, conf, reason) }
                try {
                    onResult?.invoke(mapOf<String, Any>(
                        "dir" to dir, "conf" to conf, "reason" to reason,
                        "pair" to pair, "time" to time))
                } catch (_: Exception) { }
                appendHistory(dir, conf)
            } catch (e: Exception) {
                main.post { Toast.makeText(this, "Analysis fail: ${e.message}", Toast.LENGTH_LONG).show() }
            }
            busy = false
        }.start()
    }

    private fun showCount(t: String) {
        main.post {
            try {
                if (countView == null) {
                    val tv = TextView(this)
                    tv.textSize = 54f
                    tv.setTextColor(0xFFF5E6C8.toInt())
                    tv.gravity = Gravity.CENTER
                    val p = WindowManager.LayoutParams(
                        WindowManager.LayoutParams.WRAP_CONTENT,
                        WindowManager.LayoutParams.WRAP_CONTENT,
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                        PixelFormat.TRANSLUCENT)
                    p.gravity = Gravity.CENTER
                    wm?.addView(tv, p)
                    countView = tv
                }
                countView?.text = t
            } catch (_: Exception) {}
        }
    }

    private fun hideCount() {
        main.post {
            try { countView?.let { wm?.removeView(it) } } catch (_: Exception) {}
            countView = null
        }
    }

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
                }, 12000)
            } catch (_: Exception) {}
        }
    }

    private fun bytesToB64(src: ByteArray): String {
        return try {
            var bmp = BitmapFactory.decodeByteArray(src, 0, src.size) ?: return Base64.encodeToString(src, Base64.NO_WRAP)
            val maxDim = 1280
            if (bmp.width > maxDim || bmp.height > maxDim) {
                val s = maxDim.toFloat() / Math.max(bmp.width, bmp.height)
                val nb = android.graphics.Bitmap.createScaledBitmap(bmp, (bmp.width * s).toInt(), (bmp.height * s).toInt(), true)
                if (nb != bmp) bmp.recycle()
                bmp = nb
            }
            val bos = ByteArrayOutputStream()
            bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 80, bos)
            bmp.recycle()
            Base64.encodeToString(bos.toByteArray(), Base64.NO_WRAP)
        } catch (e: Exception) {
            Base64.encodeToString(src, Base64.NO_WRAP)
        }
    }

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
            } catch (_: Exception) {
            }
        }
        return JSONObject().put("dir", "WAIT").put("conf", 0).put("reason", "sob key fail — net/key check koro")
    }

    private fun appendHistory(dir: String, conf: Int) {
        try {
            val f = File(filesDir, "binary_history.txt")
            val now = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date())
            val line = "$dir $conf% $pair $time $now"
            val old = if (f.exists()) f.readLines() else emptyList()
            val all = (listOf(line) + old).take(5)
            f.writeText(all.joinToString("\n"))
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        captureOn = false
        try { floatView?.let { wm?.removeView(it) } } catch (_: Exception) {}
        try { resultView?.let { wm?.removeView(it) } } catch (_: Exception) {}
        try { countView?.let { wm?.removeView(it) } } catch (_: Exception) {}
        floatView = null; resultView = null; countView = null
        instance = null
        super.onDestroy()
    }
}

// ===== END OF FILE BinaryService.kt =====
