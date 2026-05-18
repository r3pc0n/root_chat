package com.rootchat.rootchat

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val bgChannel  = "com.rootchat/background"
    private val msgChannel = "com.rootchat/messages"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // EventChannel: Kotlin service → Dart (messages + state events)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, msgChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    RelayForegroundService.isAppInBackground = false
                    RelayForegroundService.eventSink = events
                    // Send current connection state immediately (resume flag suppresses
                    // the "connected to X" system message for already-open sessions)
                    events.success(
                        """{"_state":"${RelayForegroundService.currentState}","resume":true}"""
                    )
                    // Replay messages that arrived while Dart was dead
                    RelayForegroundService.instance?.flushBuffer(events)
                }

                override fun onCancel(arguments: Any?) {
                    RelayForegroundService.eventSink = null
                }
            })

        // MethodChannel: Dart → Kotlin
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bgChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        requestNotificationPermission()
                        startRelayService()
                        result.success(null)
                    }
                    "stopService" -> {
                        stopService(Intent(this, RelayForegroundService::class.java))
                        result.success(null)
                    }
                    "connectRelay" -> {
                        val url      = call.argument<String>("url")      ?: ""
                        val room     = call.argument<String>("room")     ?: ""
                        val username = call.argument<String>("username") ?: ""
                        val relayKey = call.argument<String>("relayKey") ?: ""
                        val msgKey   = call.argument<String>("messageKey") ?: ""
                        // Persist messageKey so the service can read it after restart
                        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                            .edit().putString("flutter.messageKey", msgKey).apply()
                        requestNotificationPermission()
                        startRelayService()
                        RelayForegroundService.instance?.connect(url, room, username, relayKey)
                        result.success(null)
                    }
                    "disconnectRelay" -> {
                        RelayForegroundService.instance?.disconnect()
                        result.success(null)
                    }
                    "sendMessage" -> {
                        val json = call.argument<String>("json") ?: ""
                        RelayForegroundService.instance?.sendMessage(json)
                        result.success(null)
                    }
                    "setBackground" -> {
                        val inBg = call.argument<Boolean>("value") ?: false
                        RelayForegroundService.isAppInBackground = inBg
                        if (!inBg) {
                            // App returned to foreground — flush messages buffered while away
                            val sink = RelayForegroundService.eventSink
                            if (sink != null) {
                                RelayForegroundService.instance?.flushBuffer(sink)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startRelayService() {
        val intent = Intent(this, RelayForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001
                )
            }
        }
    }
}
