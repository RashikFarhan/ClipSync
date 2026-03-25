package com.antigravity.clipsync

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import com.antigravity.clipsync.R

object FlutterEngineManager {
    private const val CLIPBOARD_CHANNEL  = "com.antigravity.clipsync/clipboard"
    private const val HEALTH_CHANNEL     = "com.antigravity.clipsync/health"
    private const val QUICKPASTE_CHANNEL = "com.antigravity.clipsync/quickpaste"

    fun getOrCreateEngine(context: Context): FlutterEngine {
        var engine = FlutterEngineCache.getInstance().get("clipsync_engine")
        if (engine == null) {
            val appCtx = context.applicationContext
            engine = FlutterEngine(appCtx)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            configureChannels(engine, appCtx)
            FlutterEngineCache.getInstance().put("clipsync_engine", engine)
        }
        return engine
    }

    private fun configureChannels(flutterEngine: FlutterEngine, context: Context) {
        // NOTE: We do NOT register a handler on CLIPBOARD_CHANNEL here.
        // The Dart-side ClipboardChannel class is the sole handler for that channel.
        // Registering one here would overwrite the Dart handler and break onClipboardCopied.

        // ── Health channel ───────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HEALTH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForegroundService" -> {
                        val intent = Intent(context, SyncForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(intent)
                        } else {
                            context.startService(intent)
                        }
                        result.success(null)
                    }
                    "getHealthStatus" -> {
                        result.success(mapOf(
                            "accessibilityEnabled" to isAccessibilityEnabled(context),
                            "batteryOptimized"     to isBatteryOptimized(context),
                            "canDrawOverlays"      to Settings.canDrawOverlays(context),
                            "notificationsEnabled" to isNotificationsEnabled(context)
                        ))
                    }
                    "openNotificationSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                            }
                        } else {
                            Intent("android.settings.APP_NOTIFICATION_SETTINGS").apply {
                                putExtra("app_package", context.packageName)
                                putExtra("app_uid", context.applicationInfo.uid)
                            }
                        }
                        context.startActivity(intent.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) })
                        result.success(null)
                    }
                    "getDeviceModel" -> {
                        // Returns e.g. "Samsung Galaxy S23" or "Google Pixel 7"
                        val manufacturer = android.os.Build.MANUFACTURER
                            .replaceFirstChar { it.uppercase() }
                        val model = android.os.Build.MODEL
                        val name = if (model.startsWith(manufacturer, ignoreCase = true)) {
                            model
                        } else {
                            "$manufacturer $model"
                        }
                        result.success(name)
                    }
                    "openAccessibilitySettings" -> {
                        context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                        result.success(null)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        context.startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:${context.packageName}")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                        )
                        result.success(null)
                    }
                    "openOverlaySettings" -> {
                        context.startActivity(
                            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                                data = Uri.parse("package:${context.packageName}")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                        )
                        result.success(null)
                    }
                    "openBatterySettings" -> {
                        // Opens the per-app battery usage / background activity screen
                        context.startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:${context.packageName}")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Quick Paste channel ──────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, QUICKPASTE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getRecentClips" -> result.notImplemented()
                    "performPaste" -> {
                        val text = call.arguments as? String
                        if (text != null) {
                            ClipboardAccessibilityService.instance?.pasteClipboardContent(text)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isAccessibilityEnabled(context: Context): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.contains("${context.packageName}/${ClipboardAccessibilityService::class.java.name}")
    }

    private fun isBatteryOptimized(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return !pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun isNotificationsEnabled(context: Context): Boolean {
        return androidx.core.app.NotificationManagerCompat.from(context).areNotificationsEnabled()
    }
}
