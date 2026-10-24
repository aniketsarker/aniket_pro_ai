package com.example.aniket_pro_ai

import android.app.AlertDialog
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.max

class BubbleService : Service() {

    private var wm: WindowManager? = null
    private var bubbleRoot: LinearLayout? = null
    private var logoView: ImageView? = null
    private var bubbleView: TextView? = null
    private var errorView: TextView? = null
    private var menuDialog: AlertDialog? = null
    private val handler = Handler(Looper.getMainLooper())

    companion object {
        var instance: BubbleService? = null
            private set
        var onAction: ((String, String?) -> Unit)? = null
        var bText = "\uD83D\uDCF8 0"
        var bHtf = 0
        var bEntry = 0
        var bCorr = 0
        var bActive = "none"
        var bCapture = true

        fun show(ctx: Context) {
            try {
                ctx.startForegroundService(Intent(ctx, BubbleService::class.java))
            } catch (e: Exception) {
            }
        }

        fun hide(ctx: Context) {
            try {
                ctx.stopService(Intent(ctx, BubbleService::class.java))
            } catch (e: Exception) {
            }
        }

        fun showError(ctx: Context, msg: String) {
            val inst = instance ?: return
            inst.handler.post { inst.showErrorView(msg) }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        startFore()
        handler.post { buildBubble() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (bubbleRoot == null) handler.post { buildBubble() }
        return START_STICKY
    }

    private fun startFore() {
        try {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel("bubble_ch", "Bubble", NotificationManager.IMPORTANCE_LOW)
            nm.createNotificationChannel(ch)
            val iconRes = if (applicationInfo.icon != 0) applicationInfo.icon else android.R.drawable.ic_menu_camera
            val n = Notification.Builder(this, "bubble_ch")
                .setContentTitle("ANIKET PRO AI")
                .setContentText("Bubble active")
                .setSmallIcon(iconRes)
                .build()
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(9001, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(9001, n)
            }
        } catch (e: Exception) {
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        try {
            getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .edit().putBoolean("flutter.bubble", false).apply()
        } catch (e: Exception) {
        }
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        instance = null
        removeBubble()
        super.onDestroy()
    }

    private fun buildLogoBubbleBitmap(sizePx: Int, active: Boolean): Bitmap {
        val out = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val cx = sizePx / 2f
        val cy = sizePx / 2f
        val radius = sizePx / 2f - 4f

        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#F010121E")
            style = Paint.Style.FILL
        }
        canvas.drawCircle(cx, cy, radius, bgPaint)

        var rawLogo: Bitmap? = null
        try {
            assets.open("flutter_assets/assets/logo.png").use { stream ->
                rawLogo = BitmapFactory.decodeStream(stream)
            }
        } catch (_: Exception) {
        }

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
            } catch (_: Exception) {
            }
        }

        rawLogo?.let { src ->
            val innerSize = (sizePx - 12).coerceAtLeast(32)
            val scaled = Bitmap.createScaledBitmap(src, innerSize, innerSize, true)
            val shaderBmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
            val sc = Canvas(shaderBmp)
            sc.drawBitmap(scaled, 6f, 6f, null)
            val shaderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = BitmapShader(shaderBmp, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            }
            canvas.drawCircle(cx, cy, radius - 4f, shaderPaint)
        }

        val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (active) Color.parseColor("#C6A962") else Color.parseColor("#777777")
            style = Paint.Style.STROKE
            strokeWidth = 5.5f
        }
        canvas.drawCircle(cx, cy, radius - 2f, ringPaint)

        val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (active) Color.parseColor("#00E676") else Color.parseColor("#888888")
            style = Paint.Style.FILL
        }
        canvas.drawCircle(sizePx - 14f, sizePx - 14f, 8f, dotPaint)

        return out
    }

    fun refresh() {
        handler.post {
            val density = resources.displayMetrics.density
            val logoSizePx = (52 * density).toInt().coerceAtLeast(100)
            logoView?.setImageBitmap(buildLogoBubbleBitmap(logoSizePx, bCapture))
            bubbleView?.let { v ->
                v.text = bText
            }
            bubbleRoot?.alpha = if (bCapture) 1.0f else 0.55f
        }
    }

    private fun showErrorView(msg: String) {
        errorView?.let { v ->
            try {
                wm?.removeView(v)
            } catch (e: Exception) {
            }
        }
        val v = TextView(this)
        v.text = msg
        v.setTextColor(Color.WHITE)
        v.textSize = 14f
        v.setBackgroundColor(Color.parseColor("#CC000000"))
        v.setPadding(40, 16, 40, 16)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        params.y = 120
        errorView = v
        try {
            wm?.addView(v, params)
            handler.postDelayed({
                try {
                    wm?.removeView(v)
                } catch (e: Exception) {
                }
                if (errorView == v) errorView = null
            }, 2000)
        } catch (e: Exception) {
        }
    }

    private fun removeBubble() {
        bubbleRoot?.let { v ->
            try {
                wm?.removeView(v)
            } catch (e: Exception) {
            }
        }
        bubbleRoot = null
        logoView = null
        bubbleView = null
        errorView?.let { v ->
            try {
                wm?.removeView(v)
            } catch (e: Exception) {
            }
        }
        errorView = null
        menuDialog?.dismiss()
        menuDialog = null
    }

    private fun buildBubble() {
        if (bubbleRoot != null) return
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        wm = getSystemService(WINDOW_SERVICE) as WindowManager

        val density = resources.displayMetrics.density
        val logoSizePx = (52 * density).toInt().coerceAtLeast(100)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            alpha = if (bCapture) 1.0f else 0.55f
        }

        val iv = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setImageBitmap(buildLogoBubbleBitmap(logoSizePx, bCapture))
        }

        val view = TextView(this).apply {
            text = bText
            setTextColor(Color.parseColor("#F5E6C8"))
            textSize = 11f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#E6141626"))
                cornerRadius = 22f
                setStroke(2, Color.parseColor("#C6A962"))
            }
            setPadding(16, 4, 16, 4)
        }

        root.addView(iv, LinearLayout.LayoutParams(logoSizePx, logoSizePx))
        root.addView(
            view,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 4 }
        )

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

        val dragListener = DragListener(params, root)
        root.setOnTouchListener(dragListener)
        iv.setOnTouchListener(dragListener)
        view.setOnTouchListener(dragListener)

        bubbleRoot = root
        logoView = iv
        bubbleView = view
        try {
            wm?.addView(root, params)
        } catch (e: Exception) {
            bubbleRoot = null
            logoView = null
            bubbleView = null
            stopSelf()
        }
    }

    private fun openMenu() {
        val ctx = this
        val container = LinearLayout(ctx)
        container.orientation = LinearLayout.VERTICAL
        container.setBackgroundColor(Color.parseColor("#F2121212"))
        container.setPadding(48, 36, 48, 28)

        val title = TextView(ctx)
        val actName = if (bActive.isEmpty() || bActive == "none") "NO BOX" else bActive.uppercase()
        title.text = "Deliver  •  $actName active"
        title.setTextColor(Color.parseColor("#F5E6C8"))
        title.textSize = 18f
        title.setTypeface(title.typeface, Typeface.BOLD)
        title.setPadding(8, 8, 8, 24)
        container.addView(title)

        val act = if (bActive.isEmpty()) "none" else bActive
        // FIX: HTF max 6 → 4 (site er sathe mil)
        val labels = arrayOf(
            "HTF  (" + (if (bHtf >= 4) "FULL" else "$bHtf/4") + ")" + (if (act == "htf") "  ✔" else ""),
            "ENTRY  (" + (if (bEntry >= 4) "FULL" else "$bEntry/4") + ")" + (if (act == "entry") "  ✔" else ""),
            "NO BOX (OFF)" + (if (act == "none") "  ✔" else ""),
            "OKAY ✔",
            "Close"
        )
        for (i in labels.indices) {
            val tv = TextView(ctx)
            tv.text = labels[i]
            tv.setTextColor(
                when (i) {
                    2 -> Color.parseColor("#8D8D8D")
                    3 -> Color.parseColor("#7CFC9B")
                    4 -> Color.parseColor("#8D8D8D")
                    else -> Color.parseColor("#F5E6C8")
                }
            )
            tv.textSize = 16f
            tv.setPadding(16, 26, 16, 26)
            tv.setOnClickListener {
                menuDialog?.dismiss()
                when (i) {
                    0 -> onAction?.invoke("onBubbleSelect", "htf")
                    1 -> onAction?.invoke("onBubbleSelect", "entry")
                    2 -> onAction?.invoke("onBubbleSelect", "none")
                    3 -> {
                        try {
                            val li = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
                            li?.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_NEW_TASK)
                            li?.let { ctx.startActivity(it) }
                        } catch (e: Exception) {
                        }
                        onAction?.invoke("onBubbleOk", null)
                    }
                }
            }
            container.addView(tv)
        }

        val dialog = AlertDialog.Builder(ctx, android.R.style.Theme_Translucent_NoTitleBar).create()
        dialog.setView(container)
        dialog.window?.setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY)
        try {
            dialog.show()
            dialog.window?.setLayout(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT)
            menuDialog = dialog
        } catch (e: Exception) {
        }
    }

    private inner class DragListener(
        private val params: WindowManager.LayoutParams,
        private val targetView: View
    ) : View.OnTouchListener {
        private val h = Handler(Looper.getMainLooper())
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
                    h.postDelayed(longRun, 700)
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (e.rawX - touchX).toInt()
                    val dy = (e.rawY - touchY).toInt()
                    if (!moved && (Math.abs(dx) > 10 || Math.abs(dy) > 10)) {
                        moved = true
                        h.removeCallbacks(longRun)
                    }
                    if (moved) {
                        params.x = initialX - dx
                        params.y = initialY + dy
                        try {
                            wm?.updateViewLayout(targetView, params)
                        } catch (ex: Exception) {
                        }
                    }
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    h.removeCallbacks(longRun)
                    if (!moved && !longFired) {
                        onAction?.invoke("onBubbleTap", null)
                    }
                    return true
                }
                MotionEvent.ACTION_CANCEL -> {
                    h.removeCallbacks(longRun)
                    return true
                }
            }
            return false
        }
    }
}
