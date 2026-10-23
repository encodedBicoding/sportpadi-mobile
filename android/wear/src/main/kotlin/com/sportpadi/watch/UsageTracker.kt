package com.sportpadi.watch

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/**
 * Owner console → Usage, for the watch (the same first-party analytics the
 * web and phone send: packages/api/src/analytics/ingest.ts): sessions,
 * foreground time and the screens opened, per watch, tied to the account.
 *
 *  • device   — this watch's own id (not the phone's), in SharedPreferences
 *  • session  — from foreground; a new one after 30 minutes away
 *  • time     — foreground time only
 *  • screens  — "/watch", "/watch/games/<id>", reported when left
 *
 * Batches go to POST /api/t every 30 s while open and when the app goes to
 * the background, with the phone's bearer token (the User-Agent says
 * "wearos"). Offline batches are dropped, like the phone's. Never throws.
 */
object UsageTracker {
    private const val SESSION_GAP_MS = 30 * 60 * 1000L
    private lateinit var app: Context
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var ticker: Job? = null

    private var sessionId = UUID.randomUUID().toString()
    private var sessionStart = System.currentTimeMillis()
    private var backgroundSince: Long? = null
    private var foregroundSince: Long? = null
    private var activeMs = 0L
    private data class Page(val path: String, var at: Long, var ms: Long)
    private var page: Page? = null
    private val queue = ArrayList<JSONObject>()

    private val deviceId: String by lazy {
        val p = app.getSharedPreferences("sp.usage", Context.MODE_PRIVATE)
        p.getString("deviceId", null) ?: ("w" + UUID.randomUUID().toString().replace("-", "")).also { p.edit().putString("deviceId", it).apply() }
    }

    fun init(context: Context) { app = context.applicationContext }

    fun screen(path: String) {
        if (page?.path == path) return
        accrue()
        closePage()
        page = Page(path, System.currentTimeMillis(), 0)
    }

    fun foreground() {
        val away = backgroundSince
        backgroundSince = null
        foregroundSince = System.currentTimeMillis()
        if (away != null && System.currentTimeMillis() - away > SESSION_GAP_MS) {
            sessionId = UUID.randomUUID().toString()
            sessionStart = System.currentTimeMillis()
            page?.let { it.at = System.currentTimeMillis(); it.ms = 0 }
        }
        if (ticker?.isActive != true) ticker = scope.launch { while (isActive) { delay(30_000); flush() } }
    }

    fun background() {
        if (backgroundSince != null) return
        accrue()
        foregroundSince = null
        backgroundSince = System.currentTimeMillis()
        val current = page?.path
        closePage()
        if (current != null) page = Page(current, System.currentTimeMillis(), 0)
        ticker?.cancel(); ticker = null
        scope.launch { flush() }
    }

    private fun accrue() {
        val since = foregroundSince ?: return
        val now = System.currentTimeMillis()
        val ms = (now - since).coerceIn(0, 15 * 60 * 1000L)
        foregroundSince = now
        activeMs += ms
        page?.let { it.ms += ms }
    }

    private fun closePage() {
        val p = page ?: return
        queue.add(JSONObject().put("kind", "page").put("path", p.path).put("at", p.at).put("ms", p.ms))
        while (queue.size > 60) queue.removeAt(0)
        page = null
    }

    private suspend fun flush() {
        accrue()
        if (queue.isEmpty() && activeMs < 1000) return
        val c = ContextStore.ctx.value
        val base = c.apiBaseUrl ?: return
        val token = c.token ?: return
        val events = JSONArray().also { a -> queue.forEach { a.put(it) } }
        queue.clear()
        val active = activeMs
        activeMs = 0
        val body = JSONObject()
            .put("deviceId", deviceId)
            .put("sessionId", sessionId)
            .put("startedAt", sessionStart)
            .put("activeMs", active)
            .put("current", page?.path ?: JSONObject.NULL)
            .put("tz", TimeZone.getDefault().id)
            .put("lang", Locale.getDefault().toLanguageTag())
            .put("events", events)
        withContext(Dispatchers.IO) {
            try {
                val req = Request.Builder().url(base.trimEnd('/') + "/api/t")
                    .header("Authorization", "Bearer $token")
                    .header("User-Agent", ApiClient.userAgent)
                    .post(body.toString().toRequestBody("application/json".toMediaType()))
                    .build()
                ApiClient.http.newCall(req).execute().close()
            } catch (_: Exception) {
                // offline: dropped
            }
        }
    }
}
