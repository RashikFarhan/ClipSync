package com.antigravity.clipsync

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.GridLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.LinearLayout
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.database.sqlite.SQLiteDatabase
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * A translucent overlay Activity that appears when the user taps the
 * Quick Settings tile. It shows the last 50 clips from the Dart side
 * and injects the selected text into the system clipboard, then finishes.
 *
 * If the Flutter engine is not available (app was swiped away), falls back
 * to reading clips directly from the SQLite database.
 */
class QuickPasteActivity : Activity() {

    private val CHANNEL = "com.antigravity.clipsync/quickpaste"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Full translucent window
        window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window.setDimAmount(0.6f)

        // Try the Flutter engine first
        val engine = FlutterEngineCache.getInstance().get("clipsync_engine")
        if (engine != null) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            channel.invokeMethod("getRecentClips", null, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    @Suppress("UNCHECKED_CAST")
                    val clips = result as? List<Map<String, Any>> ?: emptyList()
                    runOnUiThread { buildClipGrid(clips) }
                }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    runOnUiThread { loadFromSQLite() }
                }
                override fun notImplemented() {
                    runOnUiThread { loadFromSQLite() }
                }
            })
        } else {
            // Engine dead — read directly from SQLite
            loadFromSQLite()
        }
    }

    private fun loadFromSQLite() {
        try {
            // sqflite stores DBs in app_flutter/ subdirectory (getApplicationDocumentsDirectory)
            val dbPath = "${filesDir.parent}/app_flutter/clipsync.db"
            val dbFile = java.io.File(dbPath)
            if (!dbFile.exists()) {
                showFallbackUI()
                return
            }
            val db = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READONLY)
            val clips = mutableListOf<Map<String, Any>>()
            val cursor = db.rawQuery(
                "SELECT id, content, type, sourceDeviceName, is_pinned, timestamp FROM clips ORDER BY timestamp DESC LIMIT 50",
                null
            )
            while (cursor.moveToNext()) {
                clips.add(mapOf(
                    "id" to (cursor.getString(0) ?: ""),
                    "content" to (cursor.getString(1) ?: ""),
                    "type" to (cursor.getString(2) ?: "text"),
                    "deviceName" to (cursor.getString(3) ?: ""),
                    "isPinned" to (cursor.getInt(4) == 1),
                    "timestamp" to cursor.getLong(5)
                ))
            }
            cursor.close()
            db.close()
            buildClipGrid(clips)
        } catch (e: Exception) {
            showFallbackUI()
        }
    }

    private fun buildClipGrid(clips: List<Map<String, Any>>) {
        val scrollView = ScrollView(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
        }

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(24), dp(16), dp(24))
        }

        // Title bar
        val titleRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dp(16))
        }
        val title = TextView(this).apply {
            text = "Quick Paste"
            setTextColor(Color.WHITE)
            textSize = 20f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        val closeBtn = TextView(this).apply {
            text = "✕"
            setTextColor(Color.parseColor("#808080"))
            textSize = 22f
            setPadding(dp(16), 0, 0, 0)
            setOnClickListener { finish() }
        }
        titleRow.addView(title, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        titleRow.addView(closeBtn)
        container.addView(titleRow)

        if (clips.isEmpty()) {
            val emptyText = TextView(this).apply {
                text = "Vault is empty.\nCopy something first!"
                setTextColor(Color.parseColor("#808080"))
                textSize = 15f
                gravity = Gravity.CENTER
                setPadding(0, dp(48), 0, 0)
            }
            container.addView(emptyText)
        } else {
            val grid = GridLayout(this).apply {
                columnCount = 2
                setPadding(0, 0, 0, dp(16))
            }

            val maxClips = clips.take(50)
            for (clip in maxClips) {
                val content = clip["content"] as? String ?: ""
                val device = clip["deviceName"] as? String ?: ""
                val isPinned = clip["isPinned"] as? Boolean ?: false

                val tile = createClipTile(content, device, isPinned)
                val params = GridLayout.LayoutParams().apply {
                    width = 0
                    height = GridLayout.LayoutParams.WRAP_CONTENT
                    columnSpec = GridLayout.spec(GridLayout.UNDEFINED, 1, 1f)
                    setMargins(dp(4), dp(4), dp(4), dp(4))
                }
                grid.addView(tile, params)
            }
            container.addView(grid)
        }

        scrollView.addView(container)
        setContentView(scrollView)
    }

    private fun createClipTile(content: String, device: String, isPinned: Boolean): View {
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(12), dp(12), dp(12))
            val bg = GradientDrawable().apply {
                setColor(Color.parseColor("#1A1A1A"))
                cornerRadius = dp(14).toFloat()
                setStroke(1, if (isPinned) Color.parseColor("#00E5FF") else Color.parseColor("#333333"))
            }
            background = bg
            isClickable = true
            isFocusable = true
        }

        val deviceLabel = TextView(this).apply {
            text = if (isPinned) "📌 $device" else device
            setTextColor(Color.parseColor("#00E5FF"))
            textSize = 10f
        }
        card.addView(deviceLabel)

        val contentText = TextView(this).apply {
            text = if (content.length > 80) content.substring(0, 80) + "…" else content
            setTextColor(Color.WHITE)
            textSize = 13f
            maxLines = 4
            setPadding(0, dp(4), 0, 0)
        }
        card.addView(contentText)

        card.setOnClickListener {
            pasteText(content)
        }
        return card
    }

    private fun pasteText(text: String) {
        // 1. Set anti-echo guard BEFORE setting clipboard so the copy doesn't re-sync
        val a11y = ClipboardAccessibilityService.instance
        a11y?.let {
            it.suppressNextClipText = text
            it.lastSentText = text
        }

        // 2. Put the text in the system clipboard
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("ClipSync", text))

        // 3. Close the overlay FIRST so the previous app regains focus
        finish()

        // 4. Give the window manager 350ms to restore focus, then attempt paste
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            if (a11y != null) {
                a11y.pasteClipboardContent(text)
            }
            // If paste didn't work, text is still on clipboard — user can paste from Gboard
        }, 350)
    }

    private fun showFallbackUI() {
        val text = TextView(this).apply {
            this.text = "ClipSync engine not running.\nPlease open the app first."
            setTextColor(Color.WHITE)
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(dp(32), dp(64), dp(32), dp(64))
            setOnClickListener { finish() }
        }
        setContentView(text)
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()
}
