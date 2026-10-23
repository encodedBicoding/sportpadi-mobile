package com.sportpadi.sportpadi_mobile

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Smartwatch pairing — Android half (docs/design/watch-officiant.md "Pairing").
 *
 * The phone hands a paired Wear OS watch everything it needs to call the API
 * as this user. The Data Layer item at [CONTEXT_PATH] is a "latest value
 * wins" store the watch app reads whenever it wakes (the Data Layer is
 * encrypted between the paired devices and readable only by the app with
 * the same package name and signing key). Dart
 * (lib/core/watch/watch_bridge.dart) sends the whole context on every change
 * over the `sportpadi/watch` method channel; this class writes it, and
 * relays the watch's few messages back:
 *
 *   watch → phone  /sportpadi/needsContext            → Dart re-sends
 *                  /sportpadi/openGame  (body: gameId) → Dart opens it
 *
 * No Play Services, no paired watch: every call is a quiet no-op.
 */
class WatchBridge(private val context: Context, messenger: BinaryMessenger) : MessageClient.OnMessageReceivedListener {
    private val channel = MethodChannel(messenger, "sportpadi/watch")
    private val main = Handler(Looper.getMainLooper())
    private val available: Boolean =
        GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateContext" -> {
                    @Suppress("UNCHECKED_CAST")
                    val ctx = call.arguments as? Map<String, Any?>
                    if (ctx == null) result.error("bad_args", "context must be a map", null)
                    else {
                        send(ctx)
                        result.success(null)
                    }
                }
                "isPaired" -> isPaired { result.success(it) }
                else -> result.notImplemented()
            }
        }
        if (available) {
            try {
                Wearable.getMessageClient(context).addListener(this)
            } catch (e: Exception) {
                Log.w(TAG, "message listener: ${e.message}")
            }
        }
    }

    /** Write the context item. Null values are dropped; everything else is stringified JSON-safe. */
    private fun send(ctx: Map<String, Any?>) {
        if (!available) return
        try {
            val req = PutDataMapRequest.create(CONTEXT_PATH)
            val map = req.dataMap
            // One JSON blob keeps the shape identical to iOS's application context.
            val json = JSONObject()
            for ((k, v) in ctx) if (v != null) json.put(k, v)
            map.putString("json", json.toString())
            map.putLong("sentAtMs", System.currentTimeMillis()) // forces a change even when the content repeats
            Wearable.getDataClient(context).putDataItem(req.setUrgent().asPutDataRequest())
                .addOnFailureListener { Log.w(TAG, "putDataItem: ${it.message}") }
        } catch (e: Exception) {
            Log.w(TAG, "send: ${e.message}")
        }
    }

    private fun isPaired(cb: (Boolean) -> Unit) {
        if (!available) return cb(false)
        try {
            Wearable.getCapabilityClient(context)
                .getCapability(WATCH_CAPABILITY, CapabilityClient.FILTER_REACHABLE)
                .addOnSuccessListener { cb(it.nodes.isNotEmpty()) }
                .addOnFailureListener { cb(false) }
        } catch (e: Exception) {
            cb(false)
        }
    }

    override fun onMessageReceived(event: MessageEvent) {
        when (event.path) {
            NEEDS_CONTEXT_PATH -> main.post { channel.invokeMethod("needsContext", null) }
            OPEN_GAME_PATH -> {
                val gameId = String(event.data, Charsets.UTF_8)
                main.post { channel.invokeMethod("openGame", mapOf("gameId" to gameId)) }
            }
        }
    }

    fun dispose() {
        if (!available) return
        try {
            Wearable.getMessageClient(context).removeListener(this)
        } catch (_: Exception) {
        }
    }

    companion object {
        private const val TAG = "WatchBridge"
        const val CONTEXT_PATH = "/sportpadi/context"
        const val NEEDS_CONTEXT_PATH = "/sportpadi/needsContext"
        const val OPEN_GAME_PATH = "/sportpadi/openGame"
        /** Declared by the Wear app in its wear.xml capabilities. */
        const val WATCH_CAPABILITY = "sportpadi_watch"
    }
}
