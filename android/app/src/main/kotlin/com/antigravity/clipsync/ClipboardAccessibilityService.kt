package com.antigravity.clipsync

import android.accessibilityservice.AccessibilityService
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * ClipboardAccessibilityService
 *
 * Responsibilities (post-PROCESS_TEXT migration):
 *   • Track the currently focused editable text field so we can inject paste actions.
 *   • Expose pasteClipboardContent() for use by QuickPasteActivity (overlay paste).
 *
 * Clipboard *capture* is now handled exclusively by ProcessTextActivity via
 * Android's ACTION_PROCESS_TEXT intent — no background polling, no listener,
 * no Android 10+ restrictions. This service no longer touches ClipboardManager.
 */
class ClipboardAccessibilityService : AccessibilityService() {

    private val mainHandler = Handler(Looper.getMainLooper())

    // Track the last focused EditText node for paste injection
    private var lastFocusedNodeInfo: AccessibilityNodeInfo? = null

    // ── Anti-echo guards (set by ProcessTextActivity / QuickPasteActivity) ─────
    // Exposed so those activities can stamp the text before writing to clipboard,
    // preventing any residual clipboard listener from re-syncing it.
    @Volatile var suppressNextClipText: String? = null
    @Volatile var lastSentText: String? = null

    companion object {
        var instance: ClipboardAccessibilityService? = null
            private set
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
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

    /**
     * Called from QuickPasteActivity when the user selects a clip.
     * Suppresses the echo so the clipboard write doesn't re-sync.
     *
     * Strategy:
     * 1. Try the LIVE focused node from rootInActiveWindow (most reliable — gets
     *    the real focused field after the overlay has closed and focus returned).
     * 2. Fall back to the cached lastFocusedNodeInfo.
     * 3. If both fail, do nothing — text is already on the clipboard so the user
     *    can paste from Gboard. Never call performGlobalAction (closes apps).
     */
    fun pasteClipboardContent(text: String) {
        suppressNextClipText = text
        lastSentText = text

        // Strategy 1: Live focused editable node
        val liveNode = findFocusedEditableNode()
        if (liveNode != null) {
            try {
                if (liveNode.performAction(AccessibilityNodeInfo.ACTION_PASTE)) return
            } catch (_: Exception) { /* stale node, fall through */ }
        }

        // Strategy 2: Cached node
        val cached = lastFocusedNodeInfo
        if (cached != null) {
            try {
                if (cached.isEditable && cached.performAction(AccessibilityNodeInfo.ACTION_PASTE)) return
            } catch (_: Exception) { /* stale, fall through */ }
        }

        // Strategy 3: Silent fallback — text is on clipboard, user can paste via Gboard.
    }

    /**
     * Walks rootInActiveWindow depth-first to find the focused editable node.
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
        mainHandler.removeCallbacksAndMessages(null)
        lastFocusedNodeInfo?.recycle()
        lastFocusedNodeInfo = null
        super.onDestroy()
    }

    override fun onInterrupt() {}
}
