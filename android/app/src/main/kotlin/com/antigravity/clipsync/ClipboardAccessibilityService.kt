package com.antigravity.clipsync

import android.accessibilityservice.AccessibilityService
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import kotlin.collections.ArrayDeque

class ClipboardAccessibilityService : AccessibilityService() {

    private var clipboardManager: ClipboardManager? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Track the last focused EditText node for paste injection
    private var lastFocusedNodeInfo: AccessibilityNodeInfo? = null

    // ── Anti-echo guard ────────────────────────────────────────────────────────
    // Set this before paste so we don't re-broadcast the text we just pasted.
    @Volatile var suppressNextClipText: String? = null

    // ── Dedup guard — tracks the last content sent to Flutter ─────────────────
    @Volatile var lastSentText: String? = null

    // ── Pending queue: every clipboard change is enqueued, processed serially ──
    private val pendingQueue = ArrayDeque<String>()
    private var isProcessing = false
    private val processHandler = Handler(Looper.getMainLooper())

    private val clipChangedListener = ClipboardManager.OnPrimaryClipChangedListener {
        val text = clipboardManager?.primaryClip
            ?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)?.text?.toString()
            ?.takeIf { it.isNotBlank() }
            ?: return@OnPrimaryClipChangedListener

        // Suppress our own paste operations (from overlay or remote sync)
        if (suppressNextClipText != null && suppressNextClipText == text) {
            suppressNextClipText = null
            return@OnPrimaryClipChangedListener
        }

        // Skip exact duplicate of the last item we already sent
        if (text == lastSentText) return@OnPrimaryClipChangedListener

        // Enqueue and schedule processing
        pendingQueue.addLast(text)
        scheduleProcessQueue()
    }

    companion object {
        var instance: ClipboardAccessibilityService? = null
            private set
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboardManager?.addPrimaryClipChangedListener(clipChangedListener)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // Track focused text fields for paste injection
        if (event.eventType == AccessibilityEvent.TYPE_VIEW_FOCUSED ||
            event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED) {
            val source = event.source
            if (source != null && source.isEditable) {
                lastFocusedNodeInfo?.recycle()
                lastFocusedNodeInfo = source
            }
        }
    }

    // ── Queue processor: 150ms delay after last enqueue, then drain sequentially
    private fun scheduleProcessQueue() {
        if (isProcessing) return
        processHandler.removeCallbacksAndMessages(null)
        processHandler.postDelayed({
            drainQueue()
        }, 150)
    }

    private fun drainQueue() {
        if (pendingQueue.isEmpty()) {
            isProcessing = false
            return
        }
        isProcessing = true

        val text = pendingQueue.removeFirst()
        if (text != lastSentText) {
            lastSentText = text
            sendToFlutter(text)
        }
        processHandler.postDelayed({ drainQueue() }, 50)
    }

    private fun sendToFlutter(text: String) {
        mainHandler.post {
            val engine = FlutterEngineCache.getInstance().get("clipsync_engine") ?: return@post
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.antigravity.clipsync/clipboard")
            channel.invokeMethod("onClipboardCopied", text)
        }
    }

    /**
     * Called from QuickPasteActivity when the user selects a clip.
     * Suppresses the echo so the clipboard write doesn't re-sync.
     *
     * Strategy:
     * 1. Set anti-echo guard (prevents re-syncing the text we're about to paste).
     * 2. Try to find the CURRENTLY focused editable node via rootInActiveWindow.
     *    This is more reliable than the cached lastFocusedNodeInfo because the
     *    overlay activity may have caused focus to shift.
     * 3. If ACTION_PASTE succeeds on that node, we're done.
     * 4. If that fails, try the cached lastFocusedNodeInfo.
     * 5. If all else fails, just leave the text on the clipboard (user can
     *    long-press paste from Gboard). Do NOT perform global actions that
     *    could close the user's app.
     */
    fun pasteClipboardContent(text: String) {
        suppressNextClipText = text
        lastSentText = text // also suppress the queue

        // Strategy 1: Find the live focused editable node
        val liveNode = findFocusedEditableNode()
        if (liveNode != null) {
            try {
                val success = liveNode.performAction(AccessibilityNodeInfo.ACTION_PASTE)
                if (success) return
            } catch (_: Exception) {
                // Node might be stale, continue to next strategy
            }
        }

        // Strategy 2: Try the cached last focused node
        val cachedNode = lastFocusedNodeInfo
        if (cachedNode != null) {
            try {
                if (cachedNode.isEditable) {
                    val success = cachedNode.performAction(AccessibilityNodeInfo.ACTION_PASTE)
                    if (success) return
                }
            } catch (_: Exception) {
                // Stale node, fall through
            }
        }

        // Strategy 3: Graceful fallback — text is already on the clipboard.
        // User can paste manually from Gboard. Do NOT call performGlobalAction
        // as it can cause unpredictable behavior (closing apps, etc).
    }

    /**
     * Walks rootInActiveWindow to find the currently focused editable node.
     * This is more reliable than tracking events because it always returns
     * the live state after the overlay has closed and focus has returned.
     */
    private fun findFocusedEditableNode(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return findFocusedEditable(root)
    }

    private fun findFocusedEditable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isFocused && node.isEditable) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findFocusedEditable(child)
            if (result != null) return result
        }
        return null
    }

    override fun onDestroy() {
        instance = null
        clipboardManager?.removePrimaryClipChangedListener(clipChangedListener)
        processHandler.removeCallbacksAndMessages(null)
        mainHandler.removeCallbacksAndMessages(null)
        lastFocusedNodeInfo?.recycle()
        lastFocusedNodeInfo = null
        super.onDestroy()
    }

    override fun onInterrupt() {}
}
