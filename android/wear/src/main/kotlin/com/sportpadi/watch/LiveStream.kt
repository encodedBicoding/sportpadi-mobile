package com.sportpadi.watch

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * The match's realtime pings (SSE at /api/mobile/games/:id/stream). Any ping
 * means "refetch"; `by` says who did it. Reconnects with back-off while
 * started; stopped when the screen leaves.
 */
class LiveStream(private val scope: CoroutineScope) {
    private val _ping = MutableStateFlow<Pair<Long, Ping>?>(null)   // (seq, ping) so equal pings still emit
    val ping: StateFlow<Pair<Long, Ping>?> = _ping
    private val _connected = MutableStateFlow(false)
    val connected: StateFlow<Boolean> = _connected
    private var job: Job? = null
    private var seq = 0L
    private val client = OkHttpClient.Builder().readTimeout(0, TimeUnit.MILLISECONDS).connectTimeout(10, TimeUnit.SECONDS).build()

    fun start(gameId: String) {
        stop()
        job = scope.launch(Dispatchers.IO) {
            var retry = 2000L
            while (isActive) {
                try {
                    val req = ApiClient.streamRequest(gameId)
                    client.newCall(req).execute().use { res ->
                        if (res.code != 200) throw IllegalStateException("stream ${res.code}")
                        _connected.value = true
                        retry = 2000L
                        val src = res.body?.source() ?: return@use
                        while (isActive) {
                            val line = src.readUtf8Line() ?: break
                            if (line.startsWith("data:")) {
                                val json = line.removePrefix("data:").trim()
                                try { _ping.value = (++seq) to Ping.of(JSONObject(json)) } catch (_: Exception) {}
                            }
                        }
                    }
                } catch (_: Exception) {
                    // fall through to reconnect
                }
                _connected.value = false
                if (!isActive) break
                delay(retry)
                retry = (retry * 2).coerceAtMost(30_000L)
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        _connected.value = false
    }
}
