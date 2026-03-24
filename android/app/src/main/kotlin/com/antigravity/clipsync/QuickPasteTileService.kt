package com.antigravity.clipsync

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class QuickPasteTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        qsTile?.state = Tile.STATE_INACTIVE
        qsTile?.label = "ClipSync"
        qsTile?.subtitle = "Quick Paste"
        qsTile?.updateTile()
    }

    override fun onClick() {
        super.onClick()
        // 1. Collapse the shade
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ automatically collapses when startActivityAndCollapse is used
        }
        // 2. Launch our transparent overlay activity
        val intent = Intent(this, QuickPasteActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+ requires PendingIntent
            val pendingIntent = android.app.PendingIntent.getActivity(
                this, 0, intent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
