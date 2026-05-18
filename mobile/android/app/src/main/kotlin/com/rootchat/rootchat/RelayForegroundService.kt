package com.rootchat.rootchat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.EventChannel
import okhttp3.*
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

class RelayForegroundService : Service() {

    companion object {
        const val BG_CHANNEL_ID  = "rootchat_bg"
        const val MSG_CHANNEL_ID = "rootchat_msg"
        const val BG_NOTIF_ID    = 1

        @Volatile var instance: RelayForegroundService? = null
        @Volatile var eventSink: EventChannel.EventSink? = null
        @Volatile var currentState = "disconnected"
        @Volatile var isAppInBackground = false
    }

    private val client = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .connectTimeout(10, TimeUnit.SECONDS)
        .pingInterval(25, TimeUnit.SECONDS)
        .build()

    private var webSocket: WebSocket? = null
    private val messageBuffer = mutableListOf<String>()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var intentionalStop = false
    private var reconnectAttempt = 0
    private var msgNotifId = 200

    // Tracks what we're currently connected to (to detect same-endpoint reconnects)
    private var connectedUrl = ""
    private var connectedRoom = ""
    private var connectedUsername = ""

    private lateinit var prefs: SharedPreferences

    private val serverUrl  get() = prefs.getString("flutter.serverUrl",  "") ?: ""
    private val room       get() = prefs.getString("flutter.room",       "public") ?: "public"
    private val username   get() = prefs.getString("flutter.username",   "") ?: ""
    private val relayKey   get() = prefs.getString("flutter.relayKey",   "") ?: ""
    private val hasMessageKey get() = (prefs.getString("flutter.messageKey", "") ?: "").isNotEmpty()

    // ── lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        instance = this
        prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        createChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(BG_NOTIF_ID, buildBgNotification())
        if (webSocket == null && serverUrl.isNotEmpty() && username.isNotEmpty()) {
            doConnect()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        intentionalStop = true
        mainHandler.removeCallbacksAndMessages(null)
        webSocket?.close(1000, null)
        webSocket = null
        client.dispatcher.executorService.shutdown()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── public API (called from MainActivity) ─────────────────────────────────

    fun connect(url: String, rm: String, user: String, key: String) {
        val sameEndpoint = url == connectedUrl && rm == connectedRoom && user == connectedUsername

        prefs.edit()
            .putString("flutter.serverUrl", url)
            .putString("flutter.room", rm)
            .putString("flutter.username", user)
            .putString("flutter.relayKey", key)
            .apply()

        if (sameEndpoint && currentState == "connected") {
            // Dart re-subscribed after being killed — don't reconnect, just signal state
            sendStateToFlutter("connected")
            return
        }

        intentionalStop = false
        reconnectAttempt = 0
        mainHandler.removeCallbacksAndMessages(null)
        webSocket?.close(1000, null)
        webSocket = null
        doConnect()
    }

    fun disconnect() {
        intentionalStop = true
        mainHandler.removeCallbacksAndMessages(null)
        webSocket?.close(1000, null)
        webSocket = null
        connectedUrl = ""; connectedRoom = ""; connectedUsername = ""
        sendStateToFlutter("disconnected")
    }

    fun sendMessage(json: String) {
        webSocket?.send(json)
    }

    /** Called by MainActivity when Dart subscribes to the EventChannel. */
    fun flushBuffer(sink: EventChannel.EventSink) {
        synchronized(messageBuffer) {
            messageBuffer.forEach { sink.success(it) }
            messageBuffer.clear()
        }
    }

    // ── WebSocket ─────────────────────────────────────────────────────────────

    private fun doConnect() {
        val url  = serverUrl
        val rm   = room
        val user = username
        val key  = relayKey
        if (url.isEmpty() || user.isEmpty()) return

        sendStateToFlutter("connecting")

        val wsUrl = "$url/ws?username=${enc(user)}&room=${enc(rm)}"
        val req = Request.Builder().url(wsUrl).apply {
            if (key.isNotEmpty()) header("Authorization", "Bearer $key")
        }.build()

        webSocket = client.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                reconnectAttempt = 0
                connectedUrl = url
                connectedRoom = rm
                connectedUsername = user
                sendStateToFlutter("connected")
            }

            override fun onMessage(ws: WebSocket, text: String) {
                val sink = eventSink
                if (sink != null && !isAppInBackground) {
                    // App is foregrounded and Dart is listening — deliver directly.
                    mainHandler.post { sink.success(text) }
                } else {
                    // App is backgrounded or Dart is dead — buffer and notify.
                    synchronized(messageBuffer) { messageBuffer.add(text) }
                    showNotificationFromJson(text)
                }
            }

            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                sendStateToFlutter("disconnected")
                scheduleReconnect()
            }

            override fun onClosing(ws: WebSocket, code: Int, reason: String) {
                ws.close(1000, null)
            }

            override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                if (!intentionalStop) {
                    sendStateToFlutter("disconnected")
                    scheduleReconnect()
                }
            }
        })
    }

    private fun scheduleReconnect() {
        if (intentionalStop) return
        val delay = minOf(3_000L * (reconnectAttempt + 1), 30_000L)
        reconnectAttempt++
        mainHandler.postDelayed({ doConnect() }, delay)
    }

    private fun sendStateToFlutter(state: String) {
        currentState = state
        val sink = eventSink ?: return
        mainHandler.post { sink.success("""{"_state":"$state"}""") }
    }

    // ── Notifications ─────────────────────────────────────────────────────────

    private fun showNotificationFromJson(json: String) {
        try {
            val obj  = JSONObject(json)
            val user = obj.getString("user")
            if (user == "·") return  // system message
            val rawText = obj.getString("text")
            val body = if (hasMessageKey) "encrypted message" else rawText.take(120)
            showMessageNotification(user, body)
        } catch (_: Exception) {}
    }

    fun showMessageNotification(title: String, body: String) {
        if (!NotificationManagerCompat.from(this).areNotificationsEnabled()) return

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT
        val pi = PendingIntent.getActivity(this, 0, launchIntent, piFlags)

        val notif = NotificationCompat.Builder(this, MSG_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_menu_send)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pi)
            .build()

        NotificationManagerCompat.from(this).notify(msgNotifId++, notif)
    }

    private fun buildBgNotification() = NotificationCompat.Builder(this, BG_CHANNEL_ID)
        .setContentTitle("root_chat")
        .setContentText("connected in background")
        .setSmallIcon(android.R.drawable.ic_menu_send)
        .setOngoing(true)
        .setSilent(true)
        .setPriority(NotificationCompat.PRIORITY_MIN)
        .build()

    private fun createChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(BG_CHANNEL_ID, "Background connection",
                    NotificationManager.IMPORTANCE_MIN).apply { setShowBadge(false) }
            )
            nm.createNotificationChannel(
                NotificationChannel(MSG_CHANNEL_ID, "Messages",
                    NotificationManager.IMPORTANCE_HIGH)
            )
        }
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
}
