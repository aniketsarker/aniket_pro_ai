package com.example.aniket_pro_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.MediaStore
import android.util.Base64
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Collections
import java.util.Date
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

// ═══════════════════════════════════════════════════════════════════
//  PRO TRAP-SNIPER + LIVE PRICE TRIGGER BINARY SIGNAL SERVICE
//  • Recognizes all chart candle colors (Green/Red AND Blue/Orange/Cyan)
//  • Trades AGAINST Retail Traps (Bull Trap -> DOWN, Bear Trap -> UP)
//  • Reads exact Y-axis prices (current_price, up_trigger, down_trigger)
//    so even when waiting for a level, it tells the exact price numbers!
// ═══════════════════════════════════════════════════════════════════
class BinaryService : Service() {

    companion object {
        var instance: BinaryService? = null
        var keys: List<String> = emptyList()
        var pair: String = "EUR/USD (OTC)"
        var time: String = "1m"
        var captureOn: Boolean = false
        var lastId: Long = 0
        var onResult: ((Map<String, Any>) -> Unit)? = null

        @Volatile
        private var lastWorkingKey: String = ""

        private val GEMINI_MODELS = listOf(
            "gemini-2.5-flash",
            "gemini-2.5-flash-lite",
            "gemini-2.0-flash",
            "gemini-2.0-flash-lite"
        )

        private val GROQ_MODELS = listOf(
            "qwen/qwen3.8-27b",
            "meta-models/muse-spark-open",
            "meta-llama/llama-4-scout-17b-16e-instruct",
            "meta-llama/llama-4-maverick-17b-128e-instruct"
        )

        private val OPENROUTER_MODELS = listOf(
            "openrouter/free",
            "google/gemma-3-27b-it:free",
            "qwen/qwen2.5-vl-72b-instruct:free",
            "qwen/qwen2.5-vl-32b-instruct:free",
            "mistralai/mistral-small-3.1-24b-instruct:free"
        )

        private val MISTRAL_MODELS = listOf(
            "mistral-small-latest",
            "ministral-14b-latest",
            "ministral-8b-latest",
            "mistral-medium-latest",
            "mistral-large-latest",
            "ministral-14b-2512",
            "ministral-8b-2512"
        )
    }

    private val main = Handler(Looper.getMainLooper())
    private var wm: WindowManager? = null

    private var bubbleRoot: LinearLayout? = null
    private var bubbleLogoView: ImageView? = null
    private var bubbleMiniTag: TextView? = null
    private var bubbleDetailPanel: LinearLayout? = null
    private var bubbleTitleText: TextView? = null
    private var bubbleTimeScheduleText: TextView? = null
    private var bubblePairReasonText: TextView? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var isBubbleExpanded: Boolean = false

    private var floatView: View? = null
    private var resultView: LinearLayout? = null
    private var countView: TextView? = null

    @Volatile
    private var busy = false
    private var lastAnalyzedPath: String = ""
    private var lastAnalyzedTimeMs: Long = 0L
    private var serviceStartSec: Long = 0L
    private var lastSeenMediaId: Long = 0L
    private var lastSignalShort: String = ""

    private val analyzedMediaIds = Collections.synchronizedSet(HashSet<Long>())
    private val analyzedSourceMtimes = Collections.synchronizedSet(HashSet<Long>())
    private val analyzedByteSignatures = Collections.synchronizedSet(HashSet<String>())
    private var lastSavedHistSig: String = ""

    private var mediaObserver: ContentObserver? = null
    private val collapseRunnable = Runnable {
        collapseBubbleToMini()
    }

    private val folderPollRunnable = object : Runnable {
        override fun run() {
            if (captureOn && !busy) {
                checkRecentScreenshotInBackground()
            }
            if (instance != null) {
                main.postDelayed(this, 1800L)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel("bin_chan", "Binary Signal", NotificationManager.IMPORTANCE_LOW)
            )
        }
        serviceStartSec = (System.currentTimeMillis() / 1000L) - 1L
        seedInitialMediaId()
        registerOwnScreenshotObserver()
        main.postDelayed(folderPollRunnable, 1800L)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: "FLOAT"
        if (action == "STOP") {
            stopSelf()
            return START_NOT_STICKY
        }
        intent?.getStringArrayListExtra("keys")?.let { list ->
            val cleaned = list.map { cleanKey(it) }.filter { it.isNotEmpty() }
            if (cleaned.isNotEmpty()) keys = cleaned
        }
        intent?.getStringExtra("pair")?.let {
            if (it.isNotEmpty()) pair = it
        }
        intent?.getStringExtra("time")?.let {
            if (it.isNotEmpty()) time = it
        }
        loadPrefsFallbackIfNeeded()

        val nb = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "bin_chan")
        else @Suppress("DEPRECATION") Notification.Builder(this)
        nb.setContentTitle("ANIKET PRO AI")
            .setContentText("Auto SS Bubble ON ($pair • $time) — Trap Sniper + Price Trigger")
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
            try {
                startForeground(9002, nb.build())
                started = true
            } catch (_: Exception) {}
        }
        if (!started) {
            stopSelf()
            return START_NOT_STICKY
        }

        captureOn = true
        serviceStartSec = (System.currentTimeMillis() / 1000L) - 1L
        seedInitialMediaId()
        showFloat()
        updateBubbleAppearance()

        if (action == "ANALYZE_ONCE") {
            triggerLatestScreenshotAnalysis(manualTap = true)
        } else {
            main.post {
                Toast.makeText(
                    this,
                    "🟢 Auto SS Bubble ON — Trap Sniper + Exact Price Trigger Level সহ অ্যানালাইসিস করবে!",
                    Toast.LENGTH_SHORT
                ).show()
            }
        }
        return START_STICKY
    }

    private fun cleanKey(raw: String): String {
        return raw
            .replace("Bearer ", "")
            .replace("bearer ", "")
            .replace("\"", "")
            .replace("'", "")
            .trim()
    }

    private fun computeBytesSignature(bytes: ByteArray): String {
        if (bytes.isEmpty()) return "empty"
        var h1 = bytes.size
        var h2 = 0x811C9DC5.toInt()
        val step = max(1, bytes.size / 96)
        var i = 0
        while (i < bytes.size) {
            val b = bytes[i].toInt() and 0xFF
            h1 = ((h1 * 31) + b) and 0x7FFFFFFF
            h2 = ((h2 xor b) * 0x01000193) and 0x7FFFFFFF
            i += step
        }
        return "${bytes.size}_${Integer.toHexString(h1)}_${Integer.toHexString(h2)}"
    }

    private fun seedInitialMediaId() {
        Thread {
            try {
                val proj = arrayOf(MediaStore.Images.Media._ID)
                contentResolver.query(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    proj,
                    null,
                    null,
                    "${MediaStore.Images.Media._ID} DESC"
                )?.use { c ->
                    var count = 0
                    val idIdx = c.getColumnIndex(MediaStore.Images.Media._ID)
                    while (c.moveToNext() && count < 10) {
                        count++
                        if (idIdx >= 0) {
                            val id = c.getLong(idIdx)
                            lastSeenMediaId = max(lastSeenMediaId, id)
                            analyzedMediaIds.add(id)
                        }
                    }
                }
            } catch (_: Exception) {}
        }.start()
    }

    private fun loadPrefsFallbackIfNeeded() {
        try {
            val sp = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            if (pair.isEmpty()) {
                pair = sp.getString("flutter.bin_pair", "EUR/USD (OTC)") ?: "EUR/USD (OTC)"
            }
            if (time.isEmpty()) {
                time = sp.getString("flutter.bin_time", "1m") ?: "1m"
            }
            if (keys.isEmpty()) {
                val rawKeys = sp.getString("flutter.bin_keys", null)
                if (!rawKeys.isNullOrEmpty()) {
                    val extracted = Regex("(AIza[0-9A-Za-z_\\-]{20,}|gsk_[0-9A-Za-z_\\-]{20,}|sk-or-[0-9A-Za-z_\\-]{20,}|[0-9A-Za-z]{28,48})")
                        .findAll(rawKeys)
                        .map { cleanKey(it.value) }
                        .filter { it.isNotEmpty() && !it.startsWith("vghpcyBpcy") }
                        .distinct()
                        .toList()
                    if (extracted.isNotEmpty()) {
                        keys = extracted
                    }
                }
            }
        } catch (_: Exception) {}
    }

    private fun registerOwnScreenshotObserver() {
        try {
            val obs = object : ContentObserver(main) {
                override fun onChange(selfChange: Boolean, uri: Uri?) {
                    super.onChange(selfChange, uri)
                    if (!captureOn) return
                    for (delayMs in listOf(450L, 1200L)) {
                        main.postDelayed({
                            if (captureOn && !busy) {
                                checkRecentScreenshotInBackground()
                            }
                        }, delayMs)
                    }
                }
            }
            contentResolver.registerContentObserver(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                true,
                obs
            )
            mediaObserver = obs
        } catch (_: Exception) {}
    }

    private fun checkRecentScreenshotInBackground() {
        if (busy) return
        val now = System.currentTimeMillis()
        if ((now - lastAnalyzedTimeMs) < 4000L) return

        Thread {
            try {
                if (busy) return@Thread
                val copied = fetchAndCopyNewestScreenshot(maxAgeSec = 15L, requireNewId = true)
                if (copied != null && copied.exists() && copied.length() > 3000L) {
                    analyze(copied.absolutePath, forceManual = false)
                }
            } catch (_: Exception) {}
        }.start()
    }

    private fun triggerLatestScreenshotAnalysis(manualTap: Boolean) {
        if (busy) {
            if (manualTap) {
                main.post {
                    Toast.makeText(this, "⏳ Pro Trap AI ekhon analyze korche...", Toast.LENGTH_SHORT).show()
                }
            }
            return
        }
        Thread {
            try {
                val copied = fetchAndCopyNewestScreenshot(maxAgeSec = 3600L, requireNewId = false)
                if (copied != null && copied.exists() && copied.length() > 3000L) {
                    analyze(copied.absolutePath, forceManual = manualTap)
                } else if (manualTap) {
                    main.post {
                        Toast.makeText(
                            this,
                            "📸 Kono screenshot pawa jayni — age Pocket Option-e screenshot nao!",
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                }
            } catch (e: Exception) {
                if (manualTap) {
                    main.post {
                        Toast.makeText(this, "SS load error: ${e.message}", Toast.LENGTH_SHORT).show()
                    }
                }
            }
        }.start()
    }

    private fun fetchAndCopyNewestScreenshot(maxAgeSec: Long, requireNewId: Boolean): File? {
        val nowSec = System.currentTimeMillis() / 1000L

        try {
            val proj = if (Build.VERSION.SDK_INT >= 29) {
                arrayOf(
                    MediaStore.Images.Media._ID,
                    MediaStore.Images.Media.DATE_ADDED,
                    MediaStore.Images.Media.DATE_MODIFIED,
                    MediaStore.Images.Media.IS_PENDING,
                    MediaStore.Images.Media.DATA
                )
            } else {
                arrayOf(
                    MediaStore.Images.Media._ID,
                    MediaStore.Images.Media.DATE_ADDED,
                    MediaStore.Images.Media.DATE_MODIFIED,
                    MediaStore.Images.Media.DATA
                )
            }

            contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                proj,
                null,
                null,
                "${MediaStore.Images.Media.DATE_ADDED} DESC"
            )?.use { c ->
                val idIdx = c.getColumnIndex(MediaStore.Images.Media._ID)
                val addIdx = c.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
                val modIdx = c.getColumnIndex(MediaStore.Images.Media.DATE_MODIFIED)
                val pendIdx = if (Build.VERSION.SDK_INT >= 29) c.getColumnIndex(MediaStore.Images.Media.IS_PENDING) else -1
                val dataIdx = c.getColumnIndex(MediaStore.Images.Media.DATA)

                var checked = 0
                while (c.moveToNext() && checked < 5) {
                    checked++
                    if (idIdx < 0) continue
                    val mediaId = c.getLong(idIdx)
                    val dateAdded = if (addIdx >= 0) c.getLong(addIdx) else 0L
                    val dateMod = if (modIdx >= 0) c.getLong(modIdx) else 0L
                    val tsSec = max(dateAdded, dateMod)
                    val isPending = if (pendIdx >= 0) c.getInt(pendIdx) else 0

                    if (isPending == 1) continue

                    if (requireNewId) {
                        if (analyzedMediaIds.contains(mediaId)) continue
                        if (mediaId <= lastSeenMediaId || mediaId <= lastId) continue
                        if (tsSec > 0 && (nowSec - tsSec) > maxAgeSec) continue
                        if (tsSec > 0 && tsSec < serviceStartSec) continue
                    } else {
                        if (tsSec > 0 && (nowSec - tsSec) > maxAgeSec) continue
                    }

                    val contentUri = ContentUris.withAppendedId(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        mediaId
                    )
                    val outFile = File(cacheDir, "bin_auto_$mediaId.jpg")
                    var copiedOk = false

                    try {
                        contentResolver.openInputStream(contentUri)?.use { input ->
                            outFile.outputStream().use { output ->
                                input.copyTo(output)
                            }
                        }
                        if (outFile.exists() && outFile.length() > 3000L) {
                            copiedOk = true
                        }
                    } catch (_: Exception) {}

                    if (!copiedOk && dataIdx >= 0) {
                        try {
                            val rawPath = c.getString(dataIdx) ?: ""
                            if (rawPath.isNotEmpty()) {
                                val rawFile = File(rawPath)
                                if (rawFile.exists() && rawFile.length() > 3000L) {
                                    analyzedSourceMtimes.add(rawFile.lastModified())
                                    rawFile.copyTo(outFile, overwrite = true)
                                    copiedOk = true
                                }
                            }
                        } catch (_: Exception) {}
                    }

                    if (copiedOk) {
                        analyzedMediaIds.add(mediaId)
                        lastSeenMediaId = max(lastSeenMediaId, mediaId)
                        lastId = max(lastId, mediaId)
                        return outFile
                    }
                }
            }
        } catch (_: Exception) {}

        try {
            val nowMs = System.currentTimeMillis()
            val root = Environment.getExternalStorageDirectory()
            val dirs = listOf(
                File(root, "Pictures/Screenshots"),
                File(root, "DCIM/Screenshots"),
                File(root, "Screenshots")
            )
            var bestFile: File? = null
            var bestTime = 0L
            for (d in dirs) {
                if (d.exists() && d.isDirectory) {
                    val files = d.listFiles() ?: continue
                    for (f in files) {
                        if (f.isFile && f.length() > 4000L) {
                            val mt = f.lastModified()
                            if ((nowMs - mt) <= maxAgeSec * 1000L && mt > bestTime) {
                                if (!requireNewId || (mt / 1000L >= serviceStartSec && !analyzedSourceMtimes.contains(mt))) {
                                    bestTime = mt
                                    bestFile = f
                                }
                            }
                        }
                    }
                }
            }
            if (bestFile != null) {
                val srcMtime = bestFile.lastModified()
                analyzedSourceMtimes.add(srcMtime)
                val outFile = File(cacheDir, "bin_dir_$srcMtime.jpg")
                bestFile.copyTo(outFile, overwrite = true)
                return outFile
            }
        } catch (_: Exception) {}

        return null
    }

    private fun timeframeStepSeconds(tf: String): Int {
        return when (tf.lowercase().trim()) {
            "5s" -> 5
            "15s" -> 15
            "30s" -> 30
            "1m" -> 60
            "2m" -> 120
            "3m" -> 180
            "5m" -> 300
            "15m" -> 900
            else -> 60
        }
    }

    private fun computeUpcomingCandleTimes(tf: String): List<String> {
        val stepSec = timeframeStepSeconds(tf)
        val nowMs = System.currentTimeMillis()
        val stepMs = stepSec * 1000L
        val nextBoundaryMs = ((nowMs / stepMs) + 1L) * stepMs
        val fmt = if (stepSec < 60) {
            SimpleDateFormat("HH:mm:ss", Locale.getDefault())
        } else {
            SimpleDateFormat("HH:mm", Locale.getDefault())
        }
        return listOf(
            fmt.format(Date(nextBoundaryMs)),
            fmt.format(Date(nextBoundaryMs + stepMs)),
            fmt.format(Date(nextBoundaryMs + stepMs * 2L))
        )
    }

    private fun buildLogoBubbleBitmap(sizePx: Int, active: Boolean, analyzing: Boolean, signalDir: String = ""): Bitmap {
        val out = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val cx = sizePx / 2f
        val cy = sizePx / 2f
        val radius = sizePx / 2f - 4f

        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xF010121E.toInt()
            style = Paint.Style.FILL
        }
        canvas.drawCircle(cx, cy, radius, bgPaint)

        var rawLogo: Bitmap? = null
        try {
            assets.open("flutter_assets/assets/logo.png").use { stream ->
                rawLogo = BitmapFactory.decodeStream(stream)
            }
        } catch (_: Exception) {}

        if (rawLogo == null) {
            try {
                val drawable = packageManager.getApplicationIcon(packageName)
                if (drawable is BitmapDrawable && drawable.bitmap != null) {
                    rawLogo = drawable.bitmap
                } else {
                    val bmp = Bitmap.createBitmap(
                        max(drawable.intrinsicWidth, 96),
                        max(drawable.intrinsicHeight, 96),
                        Bitmap.Config.ARGB_8888
                    )
                    val c = Canvas(bmp)
                    drawable.setBounds(0, 0, c.width, c.height)
                    drawable.draw(c)
                    rawLogo = bmp
                }
            } catch (_: Exception) {}
        }

        rawLogo?.let { src ->
            val innerSize = (sizePx - 14).coerceAtLeast(32)
            val scaled = Bitmap.createScaledBitmap(src, innerSize, innerSize, true)
            val shaderBmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
            val sc = Canvas(shaderBmp)
            sc.drawBitmap(scaled, 7f, 7f, null)
            val shaderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = BitmapShader(shaderBmp, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            }
            canvas.drawCircle(cx, cy, radius - 5f, shaderPaint)
        }

        val ringColor = when {
            analyzing -> 0xFFFFD54F.toInt()
            signalDir == "UP" -> 0xFF00E676.toInt()
            signalDir == "DOWN" -> 0xFFFF5252.toInt()
            active -> 0xFFC6A962.toInt()
            else -> 0xFF777777.toInt()
        }
        val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ringColor
            style = Paint.Style.STROKE
            strokeWidth = 6f
        }
        canvas.drawCircle(cx, cy, radius - 2f, ringPaint)

        val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (active) 0xFF00E676.toInt() else 0xFF888888.toInt()
            style = Paint.Style.FILL
        }
        canvas.drawCircle(sizePx - 15f, sizePx - 15f, 8.5f, dotPaint)

        return out
    }

    private fun showFloat() {
        if (bubbleRoot != null) {
            updateBubbleAppearance()
            return
        }
        if (!android.provider.Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "Overlay permission din", Toast.LENGTH_LONG).show()
            return
        }

        val density = resources.displayMetrics.density
        val logoSizePx = (56 * density).toInt().coerceAtLeast(110)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                setColor(0x00000000)
                cornerRadius = 80f
            }
        }

        val logoCol = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }

        val iv = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setImageBitmap(buildLogoBubbleBitmap(logoSizePx, captureOn, busy))
        }

        val miniTag = TextView(this).apply {
            text = "🟢 AUTO SS"
            textSize = 9.5f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                setColor(0xE6141626.toInt())
                cornerRadius = 20f
                setStroke(2, 0xFFC6A962.toInt())
            }
            setPadding(12, 3, 12, 3)
        }

        logoCol.addView(iv, LinearLayout.LayoutParams(logoSizePx, logoSizePx))
        logoCol.addView(
            miniTag,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 3 }
        )

        val detailPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            background = GradientDrawable().apply {
                setColor(0xF5101322.toInt())
                cornerRadius = 32f
                setStroke(3, 0xFFC6A962.toInt())
            }
            setPadding(26, 16, 28, 16)
        }

        val titleTv = TextView(this).apply {
            text = "⬆️ UP 90% • ⏱️ 1 min por Trade"
            textSize = 15.0f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(0xFF00E676.toInt())
        }

        val scheduleTv = TextView(this).apply {
            text = "📍 Price & Trigger Level"
            textSize = 11.5f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(0xFFFFD54F.toInt())
        }

        val reasonTv = TextView(this).apply {
            text = "🪤 Trap Sniper + SMC + ICT Setup"
            textSize = 11f
            setTextColor(0xFFDDDDDD.toInt())
            maxLines = 3
        }

        detailPanel.addView(titleTv)
        detailPanel.addView(scheduleTv)
        detailPanel.addView(reasonTv)

        root.addView(logoCol)
        root.addView(
            detailPanel,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { marginStart = 10 }
        )

        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= 26)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )
        p.gravity = Gravity.TOP or Gravity.START
        val screenW = resources.displayMetrics.widthPixels
        val screenH = resources.displayMetrics.heightPixels
        p.x = (screenW - logoSizePx - (14 * density).toInt()).coerceAtLeast(8)
        p.y = (screenH * 0.42f).toInt()

        val touchListener = object : View.OnTouchListener {
            private var startX = 0
            private var startY = 0
            private var touchX = 0f
            private var touchY = 0f
            private var moved = false
            private var longPressTriggered = false
            private val longPressRunnable = Runnable {
                if (!moved) {
                    longPressTriggered = true
                    toggleCapture()
                }
            }

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        startX = p.x
                        startY = p.y
                        touchX = event.rawX
                        touchY = event.rawY
                        moved = false
                        longPressTriggered = false
                        main.postDelayed(longPressRunnable, 650L)
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - touchX).toInt()
                        val dy = (event.rawY - touchY).toInt()
                        if (abs(dx) > 10 || abs(dy) > 10) {
                            moved = true
                            main.removeCallbacks(longPressRunnable)
                            p.x = (startX + dx).coerceIn(0, max(0, screenW - logoSizePx))
                            p.y = (startY + dy).coerceIn(0, max(0, screenH - logoSizePx))
                            try {
                                wm?.updateViewLayout(root, p)
                            } catch (_: Exception) {}
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        main.removeCallbacks(longPressRunnable)
                        if (!moved && !longPressTriggered && event.actionMasked == MotionEvent.ACTION_UP) {
                            if (isBubbleExpanded) {
                                if (v == detailPanel) {
                                    collapseBubbleToMini()
                                } else {
                                    triggerLatestScreenshotAnalysis(manualTap = true)
                                }
                            } else {
                                if (!captureOn) {
                                    captureOn = true
                                    updateBubbleAppearance()
                                }
                                triggerLatestScreenshotAnalysis(manualTap = true)
                            }
                        }
                        return true
                    }
                }
                return false
            }
        }

        root.setOnTouchListener(touchListener)
        logoCol.setOnTouchListener(touchListener)
        detailPanel.setOnTouchListener(touchListener)

        try {
            wm?.addView(root, p)
            bubbleRoot = root
            bubbleLogoView = iv
            bubbleMiniTag = miniTag
            bubbleDetailPanel = detailPanel
            bubbleTitleText = titleTv
            bubbleTimeScheduleText = scheduleTv
            bubblePairReasonText = reasonTv
            bubbleParams = p
            floatView = root
        } catch (_: Exception) {}
    }

    private fun updateBubbleAppearance(signalDir: String = "") {
        main.post {
            try {
                val iv = bubbleLogoView ?: return@post
                val density = resources.displayMetrics.density
                val logoSizePx = (56 * density).toInt().coerceAtLeast(110)
                iv.setImageBitmap(buildLogoBubbleBitmap(logoSizePx, captureOn, busy, signalDir))
                bubbleMiniTag?.text = when {
                    busy -> "⚡ SS AI.."
                    lastSignalShort.isNotEmpty() -> lastSignalShort
                    captureOn -> "🟢 AUTO SS"
                    else -> "⏸️ OFF"
                }
            } catch (_: Exception) {}
        }
    }

    private fun collapseBubbleToMini() {
        main.post {
            try {
                isBubbleExpanded = false
                bubbleDetailPanel?.visibility = View.GONE
                val root = bubbleRoot
                val p = bubbleParams
                if (root != null && p != null) {
                    wm?.updateViewLayout(root, p)
                }
            } catch (_: Exception) {}
        }
    }

    private fun toggleCapture() {
        captureOn = !captureOn
        if (!captureOn) lastSignalShort = ""
        updateBubbleAppearance()
        main.post {
            Toast.makeText(
                this,
                if (captureOn) "🟢 Auto SS Capture ON (Trap Sniper + Price Trigger)"
                else "⏸️ Auto SS Capture OFF (Long-press or tap bubble to turn ON)",
                Toast.LENGTH_SHORT
            ).show()
        }
        try {
            onResult?.invoke(
                mapOf<String, Any>(
                    "dir" to "STATE",
                    "conf" to (if (captureOn) 1 else 0),
                    "reason" to "",
                    "pair" to pair,
                    "time" to time
                )
            )
        } catch (_: Exception) {}
    }

    fun onScreenshotReceived(id: Long, path: String) {
        if (!captureOn) return
        if (id > 0) {
            if (analyzedMediaIds.contains(id)) return
            analyzedMediaIds.add(id)
            lastId = max(lastId, id)
            lastSeenMediaId = max(lastSeenMediaId, id)
        }
        analyze(path, forceManual = false)
    }

    private fun analyze(path: String, forceManual: Boolean = false) {
        if (busy) return
        val now = System.currentTimeMillis()
        if (!forceManual && (now - lastAnalyzedTimeMs) < 4000L) {
            return
        }

        val f = File(path)
        if (!f.exists() || f.length() < 2000L) return

        val rawBytes = try {
            f.readBytes()
        } catch (_: Exception) {
            return
        }

        val byteSig = computeBytesSignature(rawBytes)
        if (!forceManual && analyzedByteSignatures.contains(byteSig)) {
            return
        }
        analyzedByteSignatures.add(byteSig)

        busy = true
        lastAnalyzedPath = path
        lastAnalyzedTimeMs = now
        updateBubbleAppearance()

        try {
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .edit()
                .putString("flutter.bin_last_ss", path)
                .apply()
        } catch (_: Exception) {}

        main.post {
            showBubbleLoadingState("📸 SS Detected! Trap + Price Level Analyzing...")
            try {
                onResult?.invoke(
                    mapOf<String, Any>(
                        "dir" to "SCANNING",
                        "conf" to 0,
                        "path" to path,
                        "sig" to byteSig,
                        "reason" to "📸 Screenshot Auto-Imported! Trap Sniper + Candlestick Psychology + Price Trigger Level analyze korche...",
                        "pair" to pair,
                        "time" to time
                    )
                )
            } catch (_: Exception) {}
        }

        Thread {
            try {
                loadPrefsFallbackIfNeeded()
                val upcomingTimes = computeUpcomingCandleTimes(time)
                val b64 = bytesToB64(rawBytes)
                val res = callMultiProviderWithKeyFailover(b64, upcomingTimes)

                val dir = res.optString("dir", "WAIT").uppercase().let {
                    if (it == "CALL" || it == "BUY") "UP"
                    else if (it == "PUT" || it == "SELL") "DOWN"
                    else if (it == "UP" || it == "DOWN") it
                    else "WAIT"
                }
                val conf = if (dir == "WAIT") 0 else res.optInt("conf", 88).coerceIn(75, 98)
                val detectedPair = res.optString("detected_pair", "").trim()
                if (detectedPair.isNotEmpty() && detectedPair != "UNKNOWN" && detectedPair.contains("/")) {
                    pair = detectedPair
                }

                val currentPrice = res.optString("current_price", "Live").ifEmpty { "Live" }
                val upTrigger = res.optString("up_trigger", "Resistance Break / Support Bounce-e UP").ifEmpty {
                    "Resistance Break / Support Bounce-e UP"
                }
                val downTrigger = res.optString("down_trigger", "Resistance Wick Rejection / Support Break-e DOWN").ifEmpty {
                    "Resistance Wick Rejection / Support Break-e DOWN"
                }
                val trapPsychology = res.optString("trap_psychology", "")

                val waitMins = res.optInt("wait_mins", 1).coerceIn(1, 3)
                val defaultTarget = upcomingTimes[(waitMins - 1).coerceIn(0, 2)]
                val targetTime = res.optString("target_time", defaultTarget).ifEmpty { defaultTarget }
                val mtgBackupTime = upcomingTimes[min(waitMins, 2)]

                val stepSec = timeframeStepSeconds(time)
                val defaultTradeAfter = if (dir == "WAIT") {
                    "⏸️ Price $currentPrice → ⬆️ $upTrigger | ⬇️ $downTrigger"
                } else if (stepSec < 60) {
                    "${stepSec * waitMins} sec por Trade ($targetTime)"
                } else {
                    "$waitMins min por Trade ($targetTime)"
                }
                val tradeAfterText = res.optString("trade_after_text", defaultTradeAfter).ifEmpty { defaultTradeAfter }

                val candlePlan = res.optString(
                    "candle_plan",
                    if (dir == "WAIT") {
                        "📍 $currentPrice → ⬆️ $upTrigger | ⬇️ $downTrigger"
                    } else {
                        "${upcomingTimes[0]}: ${if (dir == "UP") "⬆️ UP" else "⬇️ DOWN"} | ${upcomingTimes[1]}: ${if (dir == "UP") "⬆️" else "⬇️"} | ${upcomingTimes[2]}: ${if (dir == "UP") "⬆️" else "⬇️"}"
                    }
                )
                val pattern = res.optString("pattern", "Candlestick Check")
                val structure = res.optString("structure", "Structure Check")
                val smc = res.optString("smc", "SMC Zone Check")
                val ict = res.optString("ict", "ICT Liquidity Check")
                val chartPattern = res.optString("chart_pattern", "Chart Pattern Check")
                val trap = res.optBoolean("trap", false)
                val trapType = res.optString(
                    "trap_type",
                    if (dir == "WAIT") "Watch Price Trigger ($currentPrice)"
                    else if (trap) "Counter-Trap Sniper Setup"
                    else "Clean Institutional Setup"
                )
                val providerUsed = res.optString("__provider", "AI")

                val defaultMtg = when {
                    dir == "WAIT" -> "🎯 Trigger Price স্পর্শ করলেই Direct Entry"
                    conf >= 88 -> "✅ Direct Shot (Backup 1-Step MTG: $mtgBackupTime)"
                    else -> "🔄 1-Step MTG Ready Rakho ($mtgBackupTime Backup)"
                }
                val mtgAdvice = res.optString("mtg_advice", defaultMtg).ifEmpty { defaultMtg }
                val entry = res.optString("entry", if (dir == "WAIT") "📍 $currentPrice -> Watch Trigger" else "$tradeAfterText • MTG: $mtgBackupTime")
                val risk = res.optString("risk", if (dir == "WAIT") "Wait for Level" else if (conf >= 86) "Low Risk (Sniper)" else "Medium Risk")
                val rawReason = res.optString("reason", "")
                val fullReason = if (pattern.isNotEmpty() && !rawReason.contains(pattern) && dir != "WAIT") {
                    "[$pattern • $chartPattern] $rawReason"
                } else {
                    rawReason
                }

                val shortIcon = if (dir == "UP") "⬆️" else if (dir == "DOWN") "⬇️" else "🎯"
                lastSignalShort = if (dir == "WAIT") "🎯 $currentPrice" else "$shortIcon ${waitMins}m ($targetTime)"

                main.post {
                    showSignalInsideBubble(
                        dir = dir,
                        conf = conf,
                        waitMins = waitMins,
                        targetTime = targetTime,
                        currentPrice = currentPrice,
                        upTrigger = upTrigger,
                        downTrigger = downTrigger,
                        mtgAdvice = mtgAdvice,
                        candlePlan = candlePlan,
                        trapType = trapType,
                        reason = fullReason,
                        trap = trap
                    )
                }

                main.post {
                    try {
                        onResult?.invoke(
                            mapOf<String, Any>(
                                "dir" to dir,
                                "conf" to conf,
                                "path" to path,
                                "sig" to byteSig,
                                "provider" to providerUsed,
                                "wait_mins" to waitMins,
                                "trade_after" to tradeAfterText,
                                "reason" to fullReason,
                                "pair" to pair,
                                "time" to time,
                                "target_time" to targetTime,
                                "current_price" to currentPrice,
                                "up_trigger" to upTrigger,
                                "down_trigger" to downTrigger,
                                "trap_psychology" to trapPsychology,
                                "candle_plan" to candlePlan,
                                "pattern" to pattern,
                                "structure" to structure,
                                "smc" to smc,
                                "ict" to ict,
                                "chart_pattern" to chartPattern,
                                "mtg_advice" to mtgAdvice,
                                "entry" to entry,
                                "risk" to risk,
                                "trap" to trap,
                                "trap_type" to trapType,
                                "trend_score" to res.optInt("trend_score", conf),
                                "pattern_score" to res.optInt("pattern_score", conf),
                                "snr_score" to res.optInt("snr_score", conf),
                                "momentum_score" to res.optInt("momentum_score", conf)
                            )
                        )
                    } catch (_: Exception) {}
                }

                if (conf > 0 && dir != "WAIT" && byteSig != lastSavedHistSig) {
                    lastSavedHistSig = byteSig
                    appendHistory(dir, conf, waitMins, targetTime)
                }
            } catch (e: Exception) {
                main.post {
                    Toast.makeText(this, "Analysis fail: ${e.message}", Toast.LENGTH_LONG).show()
                }
            } finally {
                busy = false
                updateBubbleAppearance()
            }
        }.start()
    }

    private fun showBubbleLoadingState(statusLabel: String = "⚡ Trap + Price Level Analyze korche...") {
        try {
            main.removeCallbacks(collapseRunnable)
            isBubbleExpanded = true
            val panel = bubbleDetailPanel ?: return
            panel.visibility = View.VISIBLE
            panel.background = GradientDrawable().apply {
                setColor(0xF2121526.toInt())
                cornerRadius = 32f
                setStroke(3, 0xFFFFD54F.toInt())
            }
            bubbleTitleText?.apply {
                text = statusLabel
                setTextColor(0xFFFFD54F.toInt())
            }
            val nextTimes = computeUpcomingCandleTimes(time)
            bubbleTimeScheduleText?.apply {
                text = "🕒 Candles: ${nextTimes[0]} (1m) • ${nextTimes[1]} (2m) • ${nextTimes[2]} (3m)"
                setTextColor(0xFFF5E6C8.toInt())
            }
            bubblePairReasonText?.apply {
                text = "$pair • $time (Trap Sniper + Price Trigger Level + SMC/ICT)"
                setTextColor(0xFFBBBBBB.toInt())
            }
            val root = bubbleRoot
            val p = bubbleParams
            if (root != null && p != null) {
                wm?.updateViewLayout(root, p)
            }
        } catch (_: Exception) {}
    }

    private fun showSignalInsideBubble(
        dir: String,
        conf: Int,
        waitMins: Int,
        targetTime: String,
        currentPrice: String,
        upTrigger: String,
        downTrigger: String,
        mtgAdvice: String,
        candlePlan: String,
        trapType: String,
        reason: String,
        trap: Boolean
    ) {
        try {
            main.removeCallbacks(collapseRunnable)
            updateBubbleAppearance(signalDir = dir)
            isBubbleExpanded = true

            val strokeColor = when (dir) {
                "UP" -> 0xFF00E676.toInt()
                "DOWN" -> 0xFFFF5252.toInt()
                else -> 0xFFFFB300.toInt()
            }
            val icon = when (dir) {
                "UP" -> "⬆️ UP / CALL"
                "DOWN" -> "⬇️ DOWN / PUT"
                else -> "🎯 PRICE TRIGGER MAP"
            }

            val panel = bubbleDetailPanel ?: return
            panel.visibility = View.VISIBLE
            panel.background = GradientDrawable().apply {
                setColor(0xF50E111F.toInt())
                cornerRadius = 32f
                setStroke(3, strokeColor)
            }

            bubbleTitleText?.apply {
                text = if (dir == "WAIT") {
                    "📍 Price: $currentPrice  •  ⏳ Wait for Level"
                } else {
                    "$icon ($conf%)  •  ⏱️ $waitMins min por ($targetTime)"
                }
                setTextColor(strokeColor)
            }

            bubbleTimeScheduleText?.apply {
                text = if (dir == "WAIT") {
                    "⬆️ $upTrigger  |  ⬇️ $downTrigger"
                } else {
                    "📍 $currentPrice  •  $mtgAdvice"
                }
                setTextColor(0xFFFFD54F.toInt())
            }

            bubblePairReasonText?.apply {
                text = if (dir == "WAIT") {
                    "🪤 $trapType — $reason"
                } else {
                    "🎯 UP: $upTrigger | DOWN: $downTrigger"
                }
                setTextColor(0xFFEEEEEE.toInt())
            }

            val root = bubbleRoot
            val p = bubbleParams
            if (root != null && p != null) {
                val screenW = resources.displayMetrics.widthPixels
                if (p.x > screenW / 2) {
                    p.x = 16
                }
                wm?.updateViewLayout(root, p)
            }

            main.postDelayed(collapseRunnable, 22000L)
        } catch (_: Exception) {}
    }

    private fun bytesToB64(src: ByteArray): String {
        return try {
            var bmp = BitmapFactory.decodeByteArray(src, 0, src.size)
                ?: return Base64.encodeToString(src, Base64.NO_WRAP)
            val maxDim = 1080
            if (bmp.width > maxDim || bmp.height > maxDim) {
                val s = maxDim.toFloat() / max(bmp.width, bmp.height)
                val nb = Bitmap.createScaledBitmap(
                    bmp,
                    (bmp.width * s).toInt(),
                    (bmp.height * s).toInt(),
                    true
                )
                if (nb != bmp) bmp.recycle()
                bmp = nb
            }
            val bos = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, 82, bos)
            bmp.recycle()
            Base64.encodeToString(bos.toByteArray(), Base64.NO_WRAP)
        } catch (e: Exception) {
            Base64.encodeToString(src, Base64.NO_WRAP)
        }
    }

    private fun providerNameForKey(key: String): String {
        val k = cleanKey(key)
        return when {
            k.startsWith("gsk_") -> "Groq"
            k.startsWith("sk-or-") -> "OpenRouter"
            k.startsWith("AIza") -> "Gemini"
            else -> "Mistral/AI"
        }
    }

    private fun callMultiProviderWithKeyFailover(
        b64: String,
        upcomingTimes: List<String>
    ): JSONObject {
        if (keys.isEmpty()) {
            loadPrefsFallbackIfNeeded()
        }

        val nowStr = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        val t1 = upcomingTimes[0]
        val t2 = upcomingTimes[1]
        val t3 = upcomingTimes[2]
        val isOtc = pair.contains("OTC", ignoreCase = true)
        val marketMode = if (isOtc) "Pocket Option OTC algorithmic chart" else "Live Interbank chart"

        val prompt = "You are an elite 15-Year Institutional Binary Options Trap-Sniper, Candlestick Psychology, Chart Pattern, SMC & ICT Master Trader.\n" +
            "Read this trading chart screenshot carefully.\n\n" +
            "CRITICAL CHART & COLOR READING RULES:\n" +
            "- Bullish (UP-moving) candles on this user's chart may be GREEN, BLUE, CYAN, or WHITE. Bearish (DOWN-moving) candles may be RED, ORANGE, or PINK. Always judge bullish vs bearish by whether the candle moves UP or DOWN on the price axis!\n" +
            "- Read the EXACT right-hand Y-axis price scale and live price badge (for example 158.300, 158.368, 5246, 1.08520, etc.). You MUST fill \"current_price\", \"up_trigger\", and \"down_trigger\" with real numbers from the chart!\n\n" +
            "MANDATORY 6-STAGE PRO TRAP & PRICE ACTION PROTOCOL:\n" +
            "1. BINARY TRAP MASTERCLASS (HIGHEST PRIORITY — TRADE AGAINST RETAIL TRAPS!):\n" +
            "   - In Binary Options, 80% of movements are Retail Traps. When you detect a Trap, DO NOT lazily output \"WAIT\" — give the high-probability COUNTER-TRAP trade (\"UP\" or \"DOWN\")!\n" +
            "   - BULL TRAP -> SIGNAL \"DOWN\": If price pokes above a Resistance / Swing High / Round Number (.000/.300/.500) with an Upper Wick rejection, OR if 2-4 bullish candles have pushed into a Bearish Order Block / Resistance and their bodies are shrinking (Buyer Exhaustion / Retail FOMO Trap), output \"dir\": \"DOWN\", \"trap\": true, \"trap_type\": \"🐂🪤 Bull Trap / BSL Sweep -> Counter-Trap DOWN!\".\n" +
            "   - BEAR TRAP -> SIGNAL \"UP\": If price pokes below a Support / Swing Low / Round Number with a Lower Wick rejection (Spring / SSL Sweep), OR if 2-4 bearish candles have dropped into a Bullish Order Block / Support followed by a strong bullish reversal candle (like a V-bottom or Engulfing), output \"dir\": \"UP\", \"trap\": true, \"trap_type\": \"🐻🪤 Bear Trap / SSL Sweep -> Counter-Trap UP!\".\n" +
            "   - DISPLACEMENT / BREAKOUT CONTINUATION: If a strong V-reversal or Liquidity Sweep has already happened at the bottom/top and strong displacement candles are pushing with momentum toward an unfilled FVG or next zone (with room left before major Resistance/Support), give the continuation trade (\"UP\" or \"DOWN\") for 1 min por ($t1), OR if a 1-candle pullback is expected first, set \"wait_mins\": 2 ($t2)!\n" +
            "2. WHEN TO GIVE \"UP\" / \"DOWN\" vs WHEN TO OUTPUT \"WAIT\":\n" +
            "   - Give a decisive \"dir\": \"UP\" or \"dir\": \"DOWN\" (with \"wait_mins\": 1, 2, or 3) on ~80% of charts where there is a clear Trap Reversal, Candlestick Rejection, Order Block/FVG reaction, Chart Pattern (W, M, H&S, Wedge, Flag), or Trend Displacement.\n" +
            "   - ONLY output \"dir\": \"WAIT\" if the chart is genuinely stuck in dead-flat tiny Doji barcode candles OR sitting strictly in the exact middle between distant Support & Resistance with zero momentum.\n" +
            "   - MANDATORY WHEN \"WAIT\" (AND ON ALL CHARTS): You MUST tell the trader the EXACT price numbers from the right-hand axis! Example: \"Price ekhon 5246-e ache -> 5267 er upore gele UP trade nibe, othoba 5232 er niche gele / 5267-e Upper Wick Rejection dile DOWN trade nibe (2-3 min por)\". Never say \"Wait\" without giving the exact price numbers!\n" +
            "3. CANDLESTICK PSYCHOLOGY (\"CANDLESTICK SOCIOLOGY\"):\n" +
            "   - Analyze body-to-wick ratio of the last 3 candles: Upper wick rejection at Resistance = Sellers absorbing Buyers (DOWN). Lower wick rejection at Support = Buyers absorbing Sellers (UP).\n" +
            "   - Identify Pinbar, Hammer, Shooting Star, Bullish/Bearish Engulfing, Morning/Evening Star, Tweezer Top/Bottom, Inside Bar Fakey, or Exhaustion Climax.\n" +
            "4. CHART PATTERNS + SMC + ICT:\n" +
            "   - Chart Pattern: Double Top (M), Double Bottom (W / V-Reversal), Head & Shoulders, Rising/Falling Wedge, Bull/Bear Flag, Triangle, or Channel.\n" +
            "   - SMC & ICT: BOS, CHoCH, Unmitigated Order Block (OB), Breaker Block, 50% FVG, BSL/SSL Liquidity Sweep, Inducement (IDM) Trap.\n" +
            "5. SMART MTG (MARTINGALE) ADVISOR:\n" +
            "   - State whether the trade is \"✅ Direct Shot (MTG Lagbe Na — Clean Trap Sweep)\" OR \"🔄 1-Step MTG Ready Rakho ($t2 Candle Backup)\" OR \"⛔ No MTG (Breakout Risk)\".\n\n" +
            "Current time: $nowStr | Selected Pair: $pair | Timeframe: $time ($marketMode).\n" +
            "Upcoming 3 candles: Candle 1 (1m por) = $t1, Candle 2 (2m por) = $t2, Candle 3 (3m por) = $t3.\n" +
            "Reply ONLY with a single raw JSON object (no markdown fences):\n" +
            "{\"dir\":\"UP\",\"conf\":90,\"detected_pair\":\"$pair\",\"wait_mins\":1,\"trade_after_text\":\"1 min por Trade ($t1 Candle)\",\"target_time\":\"$t1\",\"current_price\":\"158.295\",\"up_trigger\":\"158.300 break korle UP / 158.275 Support bounce-e UP\",\"down_trigger\":\"158.315 Resistance-e Upper Wick Rejection dile DOWN\",\"trap_psychology\":\"Retail 5ta red candle dekhe SELL korchilo (Bear Trap), kintu SSL Sweep kore Smart Money 3ta strong bullish candle diye upore tulche!\",\"candle_plan\":\"$t1 ⬆️ UP | $t2 ⬆️ UP | $t3 ⬆️ UP\",\"trap\":true,\"trap_type\":\"🐻🪤 Bear Trap SSL Sweep -> Counter-Trap UP!\",\"pattern\":\"V-Bottom Engulfing + Lower Wick Absorption\",\"structure\":\"Bullish CHoCH + Displacement\",\"smc\":\"Bullish Order Block + FVG Fill\",\"ict\":\"SSL Liquidity Sweep (Turtle Soup)\",\"chart_pattern\":\"Double Bottom (W) / V-Reversal\",\"mtg_advice\":\"✅ Direct Shot (Backup 1-Step MTG: $t2)\",\"entry\":\"1 min por ($t1 Open) • Trigger: 158.300+\",\"risk\":\"Low Risk (Counter-Trap Sniper)\",\"trend_score\":89,\"pattern_score\":92,\"snr_score\":91,\"momentum_score\":88,\"reason\":\"Detailed Banglish explanation including: (1) Exact Current Price & Trigger Price Levels (e.g. Price ekhon X-e ache, Y er upore gele UP / Z-e rejection dile DOWN), (2) Retail Trap vs Pro Action, (3) Candlestick Psychology + SMC/ICT, and (4) Timing & MTG advice.\"}"

        val orderedKeys = mutableListOf<String>()
        if (lastWorkingKey.isNotEmpty() && keys.contains(lastWorkingKey)) {
            orderedKeys.add(lastWorkingKey)
        }
        for (k in keys) {
            val trimmed = cleanKey(k)
            if (trimmed.isNotEmpty() && trimmed != lastWorkingKey) {
                orderedKeys.add(trimmed)
            }
        }

        val errorList = mutableListOf<String>()

        for ((index, key) in orderedKeys.withIndex()) {
            val pName = providerNameForKey(key)
            if (orderedKeys.size > 1) {
                main.post {
                    showBubbleLoadingState("⚡ Key ${index + 1}/${orderedKeys.size} ($pName) Analyzing...")
                }
            }

            val res: JSONObject? = when {
                key.startsWith("gsk_") -> callOpenAiWithDiscovery(
                    endpoint = "https://api.groq.com/openai/v1/chat/completions",
                    modelsEndpoint = "https://api.groq.com/openai/v1/models",
                    key = key,
                    models = GROQ_MODELS,
                    prompt = prompt,
                    b64 = b64,
                    timeoutSec = 12,
                    errorList = errorList
                )
                key.startsWith("sk-or-") -> callOpenAiWithDiscovery(
                    endpoint = "https://openrouter.ai/api/v1/chat/completions",
                    modelsEndpoint = "https://openrouter.ai/api/v1/models",
                    key = key,
                    models = OPENROUTER_MODELS,
                    prompt = prompt,
                    b64 = b64,
                    timeoutSec = 13,
                    requireFreeSuffix = true,
                    extraHeaders = mapOf(
                        "HTTP-Referer" to "https://aniketpro.ai",
                        "X-Title" to "ANIKET PRO AI"
                    ),
                    errorList = errorList
                )
                key.startsWith("AIza") -> raceGeminiModels(
                    key = key,
                    models = GEMINI_MODELS,
                    prompt = prompt,
                    b64 = b64,
                    timeoutSec = 10L
                )
                else -> {
                    callOpenAiWithDiscovery(
                        endpoint = "https://api.mistral.ai/v1/chat/completions",
                        modelsEndpoint = "https://api.mistral.ai/v1/models",
                        key = key,
                        models = MISTRAL_MODELS,
                        prompt = prompt,
                        b64 = b64,
                        timeoutSec = 12,
                        errorList = errorList
                    ) ?: callOpenAiWithDiscovery(
                        endpoint = "https://openrouter.ai/api/v1/chat/completions",
                        modelsEndpoint = "https://openrouter.ai/api/v1/models",
                        key = key,
                        models = OPENROUTER_MODELS,
                        prompt = prompt,
                        b64 = b64,
                        timeoutSec = 12,
                        requireFreeSuffix = true,
                        errorList = errorList
                    )
                }
            }

            if (res != null) {
                lastWorkingKey = key
                if (!res.has("__provider")) {
                    res.put("__provider", pName)
                }
                return res
            }
        }

        val errText = if (errorList.isNotEmpty()) errorList.take(2).joinToString(" | ") else "Server Busy / Key Check"
        return JSONObject()
            .put("__provider", "Wait (Key Busy)")
            .put("dir", "WAIT")
            .put("conf", 0)
            .put("detected_pair", pair)
            .put("wait_mins", 1)
            .put("current_price", "Check Key")
            .put("up_trigger", "SNR Support Bounce / Resistance Break-e UP")
            .put("down_trigger", "Resistance Wick Rejection / Support Break-e DOWN")
            .put("trap_psychology", "API Server ($errText) busy thakay blind trade dewa hoyni.")
            .put("trade_after_text", "⏸️ AI Key Busy — 5s por abar tap koro")
            .put("target_time", t1)
            .put("candle_plan", "$t1 ⏸️ WAIT | $t2 ⏸️ WAIT")
            .put("trap", true)
            .put("trap_type", "AI Key Busy ($errText)")
            .put("pattern", "No Blind Trade")
            .put("structure", "Wait for AI Vision")
            .put("smc", "Capital Protection")
            .put("ict", "No Fake Signal")
            .put("chart_pattern", "Wait")
            .put("mtg_advice", "⛔ NO TRADE (সার্ভার রেসপন্স ছাড়া অন্ধ ট্রেড বন্ধ)")
            .put("entry", "Wait 5s & Tap Bubble Again")
            .put("risk", "Protected")
            .put("reason", "⚠️ এই মুহূর্তে AI সার্ভার রেসপন্স দেয়নি ($errText)। ৫ সেকেন্ড পর আবার বাবলে ট্যাপ করো অথবা Key Box চেক করো।")
    }

    private fun raceGeminiModels(
        key: String,
        models: List<String>,
        prompt: String,
        b64: String,
        timeoutSec: Long
    ): JSONObject? {
        val winner = AtomicReference<JSONObject?>(null)
        val doneLatch = CountDownLatch(1)
        val finishedCount = AtomicInteger(0)
        val totalModels = models.size

        for (model in models) {
            Thread {
                val res = trySingleGeminiModel(key, model, prompt, b64, timeoutSec.toInt())
                if (res != null && winner.compareAndSet(null, res)) {
                    res.put("__provider", "Gemini ($model)")
                    doneLatch.countDown()
                } else if (finishedCount.incrementAndGet() >= totalModels) {
                    doneLatch.countDown()
                }
            }.start()
        }

        try {
            doneLatch.await(timeoutSec, TimeUnit.SECONDS)
        } catch (_: Exception) {}

        return winner.get()
    }

    private fun trySingleGeminiModel(
        key: String,
        model: String,
        prompt: String,
        b64: String,
        timeoutSec: Int = 9
    ): JSONObject? {
        var c: HttpURLConnection? = null
        try {
            val url = URL("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key")
            c = url.openConnection() as HttpURLConnection
            c.requestMethod = "POST"
            c.connectTimeout = 5000
            c.readTimeout = timeoutSec * 1000
            c.doOutput = true
            c.setRequestProperty("Content-Type", "application/json; charset=utf-8")

            val body = JSONObject()
            val parts = JSONArray()
            parts.put(JSONObject().put("text", prompt))
            parts.put(
                JSONObject().put(
                    "inline_data",
                    JSONObject().put("mime_type", "image/jpeg").put("data", b64)
                )
            )
            body.put("contents", JSONArray().put(JSONObject().put("parts", parts)))

            val genConfig = JSONObject().put("temperature", 0.2)
            if (model.contains("2.5")) {
                genConfig.put("thinkingConfig", JSONObject().put("thinkingBudget", 0))
            }
            body.put("generationConfig", genConfig)

            c.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = c.responseCode
            if (code == 200) {
                val txt = c.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
                c.disconnect()
                val j = JSONObject(txt)
                val parts2 = j.optJSONArray("candidates")
                    ?.optJSONObject(0)
                    ?.optJSONObject("content")
                    ?.optJSONArray("parts")
                val sb = StringBuilder()
                if (parts2 != null) {
                    for (i in 0 until parts2.length()) {
                        val pObj = parts2.optJSONObject(i) ?: continue
                        if (pObj.optBoolean("thought", false)) continue
                        sb.append(pObj.optString("text", ""))
                    }
                }
                return parseJsonFromRawText(sb.toString())
            } else {
                c.disconnect()
            }
        } catch (_: Exception) {
            try { c?.disconnect() } catch (_: Exception) {}
        }
        return null
    }

    private fun callOpenAiWithDiscovery(
        endpoint: String,
        modelsEndpoint: String,
        key: String,
        models: List<String>,
        prompt: String,
        b64: String,
        timeoutSec: Int,
        requireFreeSuffix: Boolean = false,
        extraHeaders: Map<String, String>? = null,
        errorList: MutableList<String>? = null
    ): JSONObject? {
        val allModels = models.toMutableList()
        val discovered = discoverProviderVisionModels(modelsEndpoint, key, requireFreeSuffix)
        for (dm in discovered.take(4)) {
            if (!allModels.contains(dm)) allModels.add(dm)
        }

        for (model in allModels) {
            val res = trySingleOpenAiVisionModel(
                endpoint = endpoint,
                key = key,
                model = model,
                prompt = prompt,
                b64 = b64,
                timeoutSec = timeoutSec,
                extraHeaders = extraHeaders,
                errorList = errorList
            )
            if (res != null) {
                res.put("__provider", model.substringAfterLast('/'))
                return res
            }
        }
        return null
    }

    private fun discoverProviderVisionModels(
        modelsEndpoint: String,
        key: String,
        requireFreeSuffix: Boolean
    ): List<String> {
        var c: HttpURLConnection? = null
        try {
            val url = URL(modelsEndpoint)
            c = url.openConnection() as HttpURLConnection
            c.requestMethod = "GET"
            c.connectTimeout = 4000
            c.readTimeout = 5000
            c.setRequestProperty("Authorization", "Bearer $key")
            if (c.responseCode == 200) {
                val txt = c.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
                c.disconnect()
                val arr = JSONObject(txt).optJSONArray("data") ?: return emptyList()
                val out = mutableListOf<String>()
                for (i in 0 until arr.length()) {
                    val item = arr.optJSONObject(i) ?: continue
                    val id = item.optString("id", "")
                    if (id.isEmpty()) continue
                    if (requireFreeSuffix && !id.endsWith(":free")) continue
                    val low = id.lowercase()
                    val arch = item.optJSONObject("architecture")?.toString()?.lowercase() ?: ""
                    if (low.contains("qwen") ||
                        low.contains("vl") ||
                        low.contains("vision") ||
                        low.contains("gemma-3") ||
                        low.contains("ministral") ||
                        low.contains("pixtral") ||
                        low.contains("llama-4") ||
                        arch.contains("image")
                    ) {
                        out.add(id)
                    }
                }
                return out
            } else {
                c.disconnect()
            }
        } catch (_: Exception) {
            try { c?.disconnect() } catch (_: Exception) {}
        }
        return emptyList()
    }

    private fun trySingleOpenAiVisionModel(
        endpoint: String,
        key: String,
        model: String,
        prompt: String,
        b64: String,
        timeoutSec: Int = 11,
        extraHeaders: Map<String, String>? = null,
        errorList: MutableList<String>? = null
    ): JSONObject? {
        var c: HttpURLConnection? = null
        try {
            val url = URL(endpoint)
            c = url.openConnection() as HttpURLConnection
            c.requestMethod = "POST"
            c.connectTimeout = 6000
            c.readTimeout = timeoutSec * 1000
            c.doOutput = true
            c.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            c.setRequestProperty("Authorization", "Bearer $key")
            extraHeaders?.forEach { (k, v) -> c.setRequestProperty(k, v) }

            val contentArr = JSONArray()
            contentArr.put(JSONObject().put("type", "text").put("text", prompt))
            contentArr.put(
                JSONObject()
                    .put("type", "image_url")
                    .put("image_url", JSONObject().put("url", "data:image/jpeg;base64,$b64"))
            )

            val msgObj = JSONObject()
                .put("role", "user")
                .put("content", contentArr)

            val body = JSONObject()
                .put("model", model)
                .put("temperature", 0.2)
                .put("max_tokens", 2048)
                .put("messages", JSONArray().put(msgObj))

            c.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = c.responseCode
            if (code == 200) {
                val txt = c.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
                c.disconnect()
                val root = JSONObject(txt)
                val content = root.optJSONArray("choices")
                    ?.optJSONObject(0)
                    ?.optJSONObject("message")
                    ?.optString("content", "") ?: ""
                return parseJsonFromRawText(content)
            } else {
                errorList?.add("${model.substringAfterLast('/')}: HTTP $code")
                c.disconnect()
            }
        } catch (_: Exception) {
            try { c?.disconnect() } catch (_: Exception) {}
        }
        return null
    }

    private fun parseJsonFromRawText(raw: String): JSONObject? {
        val noThink = raw.replace(Regex("<think>[\\s\\S]*?</think>", RegexOption.IGNORE_CASE), "")
        val text = noThink.replace("```json", "").replace("```", "").trim()
        val a = text.indexOf('{')
        val z = text.lastIndexOf('}')
        if (a >= 0 && z > a) {
            val slice = text.substring(a, z + 1)
            try {
                return JSONObject(slice)
            } catch (_: Exception) {
                try {
                    val flat = slice.replace("\r", " ").replace("\n", " ")
                    return JSONObject(flat)
                } catch (_: Exception) {}
            }
        }

        fun pickStr(key: String, def: String = ""): String {
            val m = Regex("\"$key\"\\s*:\\s*\"([^\"]+)\"", RegexOption.IGNORE_CASE).find(text)
            return m?.groupValues?.getOrNull(1)?.trim() ?: def
        }

        val dirMatch = Regex("\"dir\"\\s*:\\s*\"(UP|DOWN|WAIT|CALL|PUT|BUY|SELL)\"", RegexOption.IGNORE_CASE).find(text)
        if (dirMatch != null) {
            val dirVal = dirMatch.groupValues[1].uppercase()
            val confVal = Regex("\"conf\"\\s*:\\s*(\\d+)").find(text)?.groupValues?.getOrNull(1)?.toIntOrNull() ?: 88
            val waitVal = Regex("\"wait_mins\"\\s*:\\s*(\\d+)").find(text)?.groupValues?.getOrNull(1)?.toIntOrNull() ?: 1
            val trapVal = Regex("\"trap\"\\s*:\\s*true", RegexOption.IGNORE_CASE).containsMatchIn(text)

            return JSONObject()
                .put("dir", dirVal)
                .put("conf", confVal)
                .put("detected_pair", pickStr("detected_pair", pair))
                .put("wait_mins", waitVal)
                .put("trade_after_text", pickStr("trade_after_text"))
                .put("target_time", pickStr("target_time"))
                .put("current_price", pickStr("current_price"))
                .put("up_trigger", pickStr("up_trigger"))
                .put("down_trigger", pickStr("down_trigger"))
                .put("trap_psychology", pickStr("trap_psychology"))
                .put("candle_plan", pickStr("candle_plan"))
                .put("trap", trapVal)
                .put("trap_type", pickStr("trap_type", "Trap Analysis Complete"))
                .put("pattern", pickStr("pattern", "Pinbar / Engulfing"))
                .put("structure", pickStr("structure", "BOS + SNR Bounce"))
                .put("smc", pickStr("smc", "Order Block + FVG"))
                .put("ict", pickStr("ict", "Liquidity Sweep + Displacement"))
                .put("chart_pattern", pickStr("chart_pattern", "Price Channel Breakout"))
                .put("mtg_advice", pickStr("mtg_advice"))
                .put("entry", pickStr("entry"))
                .put("risk", pickStr("risk", "Low Risk"))
                .put("reason", pickStr("reason", "Institutional Trap + SMC + ICT + Price Action confluence confirmed."))
        }
        return null
    }

    private fun appendHistory(dir: String, conf: Int, waitMins: Int, targetTime: String) {
        try {
            val f = File(filesDir, "binary_history.txt")
            val line = "$dir $conf% $pair $time • ${waitMins}m por [🕒 $targetTime]"
            val old = if (f.exists()) f.readLines() else emptyList()
            val all = (listOf(line) + old.filter { it != line }).take(5)
            f.writeText(all.joinToString("\n"))
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        captureOn = false
        main.removeCallbacks(folderPollRunnable)
        main.removeCallbacks(collapseRunnable)
        try {
            mediaObserver?.let { contentResolver.unregisterContentObserver(it) }
        } catch (_: Exception) {}
        mediaObserver = null
        try { bubbleRoot?.let { wm?.removeView(it) } } catch (_: Exception) {}
        try { resultView?.let { wm?.removeView(it) } } catch (_: Exception) {}
        try { countView?.let { wm?.removeView(it) } } catch (_: Exception) {}
        bubbleRoot = null
        bubbleLogoView = null
        bubbleMiniTag = null
        bubbleDetailPanel = null
        floatView = null
        resultView = null
        countView = null
        instance = null
        super.onDestroy()
    }
}
