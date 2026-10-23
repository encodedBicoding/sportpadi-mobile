package com.sportpadi.watch

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.NodeClient
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.tasks.await
import org.json.JSONObject

/**
 * The pairing context the phone writes to the Data Layer at /sportpadi/context
 * (docs/design/watch-officiant.md "Pairing"): API base URL, bearer token, who
 * the user is, the match open in officiant mode on the phone. Kept in
 * SharedPreferences so the watch works from cold without the phone nearby.
 * The watch never signs in itself. No token → "Open SportPadi on your phone".
 */
object ContextStore {
    data class Ctx(
        val version: Int = 0,
        val apiBaseUrl: String? = null,
        val token: String? = null,
        val userId: String? = null,
        val userName: String? = null,
        val deviceId: String? = null,
        val currentGameId: String? = null,
    ) {
        val signedIn get() = token != null && apiBaseUrl != null
        val needsPhoneUpdate get() = version > SUPPORTED_VERSION
    }

    const val SUPPORTED_VERSION = 1
    private const val PREFS = "sp.context"
    private lateinit var app: Context
    private val _ctx = MutableStateFlow(Ctx())
    val ctx: StateFlow<Ctx> = _ctx

    fun init(context: Context) {
        app = context.applicationContext
        val p = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        p.getString("json", null)?.let { applyJson(it, persist = false) }
    }

    /** A Data Layer item (from DataLayerService, or our own initial read). */
    fun apply(item: DataItem) {
        if (item.uri.path != CONTEXT_PATH) return
        val json = DataMapItem.fromDataItem(item).dataMap.getString("json") ?: return
        applyJson(json, persist = true)
    }

    private fun applyJson(json: String, persist: Boolean) {
        try {
            val j = JSONObject(json)
            val signedIn = j.optBoolean("signedIn", true)
            _ctx.value = Ctx(
                version = j.optInt("version"),
                apiBaseUrl = j.optString("apiBaseUrl").ifEmpty { null },
                token = if (signedIn) j.optString("token").ifEmpty { null } else null,
                userId = j.optString("userId").ifEmpty { null },
                userName = j.optString("userName").ifEmpty { null },
                deviceId = j.optString("deviceId").ifEmpty { null },
                currentGameId = if (j.isNull("currentGameId")) null else j.optString("currentGameId").ifEmpty { null },
            )
            if (persist) app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("json", json).apply()
        } catch (e: Exception) {
            Log.w(TAG, "bad context: ${e.message}")
        }
    }

    /** Read whatever the phone last wrote (cold start), then ask it for a fresh one. */
    suspend fun refreshFromPhone() {
        try {
            val items = Wearable.getDataClient(app).getDataItems(uriFor(CONTEXT_PATH)).await()
            items.forEach { apply(it) }
            items.release()
        } catch (e: Exception) {
            Log.w(TAG, "getDataItems: ${e.message}")
        }
        sendToPhone(NEEDS_CONTEXT_PATH, ByteArray(0))
    }

    /** The server said 401: forget the token and ask the phone again. */
    suspend fun tokenRejected() {
        _ctx.value = _ctx.value.copy(token = null)
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove("json").apply()
        sendToPhone(NEEDS_CONTEXT_PATH, ByteArray(0))
    }

    /** A match tapped here opens on the phone too. */
    suspend fun tellPhoneOpen(gameId: String) = sendToPhone(OPEN_GAME_PATH, gameId.toByteArray())

    private suspend fun sendToPhone(path: String, data: ByteArray) {
        try {
            val nodes = Wearable.getNodeClient(app).connectedNodes.await()
            val phone = nodes.firstOrNull { it.isNearby } ?: nodes.firstOrNull() ?: return
            Wearable.getMessageClient(app).sendMessage(phone.id, path, data).await()
        } catch (e: Exception) {
            Log.w(TAG, "sendMessage $path: ${e.message}")
        }
    }

    private fun uriFor(path: String) = android.net.Uri.Builder().scheme("wear").path(path).build()

    private const val TAG = "ContextStore"
    const val CONTEXT_PATH = "/sportpadi/context"
    const val NEEDS_CONTEXT_PATH = "/sportpadi/needsContext"
    const val OPEN_GAME_PATH = "/sportpadi/openGame"
}
