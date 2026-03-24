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
        const val CHANNEL_ID = "clipsync_sync_channel"
        const val NOTIF_ID   = 1
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // onStartCommand is called with a null intent when the system restarts
        // the service after it was killed (START_STICKY). We always want to
        // start foreground and ensure the Flutter engine is alive.
        val notification = buildNotification()
        startForeground(NOTIF_ID, notification)
        FlutterEngineManager.getOrCreateEngine(this)

        // START_STICKY: system will restart the service after killing it,
        // passing a null intent (which we handle gracefully above).
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ClipSync")
            .setContentText("Clipboard sync is active")
            .setSmallIcon(R.drawable.ic_logo)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "ClipSync Background Sync",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps clipboard sync running in the background"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    // NOTE: We intentionally do NOT override onTaskRemoved to reschedule via
    // AlarmManager. That pattern causes the service to survive APK uninstall.
    // START_STICKY gives us the OS-level restart we need without that side-effect.

    override fun onBind(intent: Intent?): IBinder? = null
}
