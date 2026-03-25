package com.antigravity.clipsync

import android.app.*
import android.content.Intent
import android.os.IBinder
import android.os.Build
import android.content.Context
import androidx.core.app.NotificationCompat
import com.antigravity.clipsync.R

class SyncForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "clipsync_v2"   // v2 = forces fresh channel; old HIGH-importance channel is gone
        const val NOTIF_ID   = 1
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        startForeground(NOTIF_ID, notification)
        FlutterEngineManager.getOrCreateEngine(this)
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        // Tapping the notification body opens the Quick Paste Overlay
        val openIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, QuickPasteActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // "Sync Now" action button
        val syncIntent = PendingIntent.getActivity(
            this, 1,
            Intent(this, SyncClipboardActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ClipSync")
            .setContentText("Tap to browse vault  •  Sync Now →")
            .setSmallIcon(R.drawable.ic_logo)
            .setContentIntent(openIntent)
            .addAction(
                android.R.drawable.ic_menu_upload,
                "Sync Now",
                syncIntent
            )
            // ongoing = stays pinned at top; cannot be dismissed by swipe
            .setOngoing(true)
            // PRIORITY_MIN keeps it in the "silent" section but still pinned
            // (matches how Google Play's background notification behaves)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            // Silent = no sound, no vibration, no heads-up peek
            .setSilent(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Delete the old channel that may have been cached with IMPORTANCE_HIGH
            nm.deleteNotificationChannel("clipsync_sync_channel")

            // Create the new silent channel — only if it doesn't exist yet
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "ClipSync Background Sync",
                    NotificationManager.IMPORTANCE_MIN   // truly silent; no heads-up, no sound
                ).apply {
                    description = "Keeps clipboard sync running in the background"
                    setShowBadge(false)
                    setSound(null, null)
                    enableVibration(false)
                }
                nm.createNotificationChannel(channel)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
