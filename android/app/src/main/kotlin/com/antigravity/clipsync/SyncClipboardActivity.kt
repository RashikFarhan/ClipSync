package com.antigravity.clipsync

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.widget.Toast
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * SyncClipboardActivity — transparent Activity launched by the "Sync Now"
 * notification action button.
 *
 * Key fix: clipboard access on Android 10+ is only granted when the Activity
 * *actually* has window focus. Reading in onCreate() is too early — the window
 * may not have focus yet, so the OS returns an empty clipboard. We override
 * onWindowFocusChanged() and only read the clipboard once hasFocus=true.
 */
class SyncClipboardActivity : Activity() {

    companion object {
        private const val CLIPBOARD_CHANNEL = "com.antigravity.clipsync/clipboard"
    }

    private var synced = false // guard against onWindowFocusChanged firing twice

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // No layout — window still exists and will receive focus events.
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || synced) return
        synced = true
        readAndSync()
        finish()
    }

    private fun readAndSync() {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = cm.primaryClip
            ?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)?.text?.toString()
            ?.takeIf { it.isNotBlank() }

        if (text == null) {
            Toast.makeText(this, "Clipboard is empty", Toast.LENGTH_SHORT).show()
            return
        }

        // Dedup: skip if already the last thing we synced
        val a11y = ClipboardAccessibilityService.instance
        if (a11y?.lastSentText == text) {
            Toast.makeText(this, "Already synced", Toast.LENGTH_SHORT).show()
            return
        }

        // Stamp anti-echo guards
        a11y?.suppressNextClipText = text
        a11y?.lastSentText = text

        // Push to Flutter engine
        val engine = FlutterEngineCache.getInstance().get("clipsync_engine")
        if (engine != null) {
            MethodChannel(engine.dartExecutor.binaryMessenger, CLIPBOARD_CHANNEL)
                .invokeMethod("onClipboardCopied", text)
            val preview = if (text.length > 30) "${text.substring(0, 30)}…" else text
            Toast.makeText(this, "✓ Synced: $preview", Toast.LENGTH_SHORT).show()
        } else {
            // Engine not up — will be caught by MainActivity.onResume auto-sync
            Toast.makeText(this, "ClipSync not running — will sync on next open", Toast.LENGTH_SHORT).show()
        }
    }
}
