package com.sportpadi.watch

import android.content.Context
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

sealed class ApiError(message: String) : Exception(message) {
    class NotPaired : ApiError("Open SportPadi on your phone")
    class Unauthorized : ApiError("Signed out — open SportPadi on your phone")
    class Server(message: String) : ApiError(message)
    class Network : ApiError("No connection")
}

/** The same REST facade the phone uses, with the phone's bearer token. */
object ApiClient {
    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    /** "SportPadiWatch/1.0.0 (wearos 14)" — the server reads the platform off it. Set by [init]. */
    var userAgent = "SportPadiWatch/0 (wearos ${Build.VERSION.RELEASE})"
        private set

    fun init(context: Context) {
        val v = try { context.packageManager.getPackageInfo(context.packageName, 0).versionName } catch (_: Exception) { null } ?: "0"
        userAgent = "SportPadiWatch/$v (wearos ${Build.VERSION.RELEASE})"
    }

    private fun request(path: String, body: JSONObject? = null): Request {
        val c = ContextStore.ctx.value
        val base = c.apiBaseUrl ?: throw ApiError.NotPaired()
        val token = c.token ?: throw ApiError.NotPaired()
        val b = Request.Builder().url(base.trimEnd('/') + path)
            .header("Authorization", "Bearer $token")
            .header("Accept", "application/json")
            .header("User-Agent", userAgent)
        c.deviceId?.let { b.header("x-sp-device", it) }
        if (body != null) b.post(body.toString().toRequestBody("application/json".toMediaType()))
        return b.build()
    }

    private suspend fun send(req: Request): JSONObject = withContext(Dispatchers.IO) {
        val res = try { http.newCall(req).execute() } catch (e: IOException) { throw ApiError.Network() }
        res.use {
            val text = it.body?.string() ?: ""
            if (it.code == 401) { ContextStore.tokenRejected(); throw ApiError.Unauthorized() }
            if (it.code >= 400) {
                val m = try { JSONObject(text).optString("message") } catch (_: Exception) { "" }
                throw ApiError.Server(m.ifEmpty { "Something went wrong" })
            }
            try { JSONObject(text) } catch (_: Exception) { throw ApiError.Server("Unexpected reply") }
        }
    }

    suspend fun home(): Home = Home.of(send(request("/api/mobile/watch")))
    suspend fun game(id: String): Game = Game.of(send(request("/api/mobile/watch/$id")))

    suspend fun respond(gameId: String, accept: Boolean) {
        send(request("/api/mobile/watch/$gameId", JSONObject().put("action", if (accept) "accept" else "decline")))
    }

    /** A clock action; the id makes a retry a no-op. Returns the fresh view. */
    suspend fun act(gameId: String, action: String, minutes: Int?, actionId: String): Game {
        val body = JSONObject().put("action", action).put("actionId", actionId)
        if (minutes != null) body.put("minutes", minutes)
        return Game.of(send(request("/api/mobile/watch/$gameId", body)))
    }

    /** The SSE stream request for LiveStream. */
    fun streamRequest(gameId: String): Request =
        request("/api/mobile/games/$gameId/stream").newBuilder().header("Accept", "text/event-stream").build()
}
