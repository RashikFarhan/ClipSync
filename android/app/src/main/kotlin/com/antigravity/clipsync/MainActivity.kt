package com.antigravity.clipsync

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Start the persistent foreground service as early as possible
        startSyncService()
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        // Return the globally cached engine (which FlutterEngineManager creates if needed)
        return FlutterEngineManager.getOrCreateEngine(context)
    }

    private fun startSyncService() {
        val intent = Intent(this, SyncForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
