package com.example.aniket_pro_ai

import android.app.AlertDialog
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

class BubbleService : Service() {

    private var wm: WindowManager? = null
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
        if (bubbleView == null) handler.post { buildBubble() }
        return START_STICKY
    }

    private fun startFore() {
        try {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel("bubble_ch", "Bubble", NotificationManager.IMPORTANCE_LOW)
            nm.createNotificationChannel(ch)
            val n = Notification.Builder(this, "bubble_ch")
                .setContentTitle("ANIKET PRO AI")
                .setContentText("Bubble active")
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .build()
            startForeground(9001, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
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

    fun refresh() {
        handler.post {
            bubbleView?.let { v ->
                v.text = bText
                v.alpha = if (bCapture) 1.0f else 0.45f
            }
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
        bubbleView?.let { v ->
            try {
                wm?.removeView(v)
            } catch (e: Exception) {
            }
        }
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
        if (bubbleView != null) return
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val view = TextView(this)
        view.text = bText
        view.setTextColor(Color.parseColor("#F5E6C8"))
        view.textSize = 24f
        view.gravity = Gravity.CENTER
        view.setShadowLayer(10f, 0f, 0f, Color.BLACK)
        view.setPadding(24, 12, 24, 12)
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
        val labels = arrayOf(
            "HTF  (" + (if (bHtf >= 6) "FULL" else "$bHtf/6") + ")" + (if (act == "htf") "  ✔" else ""),
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
        private val view: View
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
                            wm?.updateViewLayout(view, params)
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
