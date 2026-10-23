package com.sportpadi.watch

import android.content.Context
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import kotlin.math.min
import kotlin.math.pow

/**
 * Clock actions from the wrist, in order, whatever the link is doing. Each
 * tap gets a client id, is saved to disk at once, and is sent one at a time
 * in tap order; a network failure backs off (2…30 s) and retries the SAME id
 * (a no-op server-side if it landed), so a full time is never lost and never
 * applied twice. A server "no" (400/403) drops that one and says why.
 */
object ActionQueue {
    data class Pending(val id: String, val gameId: String, val action: String, val minutes: Int?, val createdAt: Long, var attempts: Int = 0)

    private const val PREFS = "sp.queue"
    private lateinit var app: Context
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var drainJob: Job? = null

    private val _pending = MutableStateFlow<List<Pending>>(emptyList())
    val pending: StateFlow<List<Pending>> = _pending
    private val _sending = MutableStateFlow(false)
    val sending: StateFlow<Boolean> = _sending
    /** The last thing the server refused (consumed by the screen). */
    val refusal = MutableStateFlow<String?>(null)
    /** The fresh match view after a successful send. */
    val lastResult = MutableStateFlow<Game?>(null)

    fun init(context: Context) {
        app = context.applicationContext
        val raw = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("items", null)
        if (raw != null) {
            val a = JSONArray(raw)
            _pending.value = (0 until a.length()).map { i ->
                val j = a.getJSONObject(i)
                Pending(j.getString("id"), j.getString("gameId"), j.getString("action"), if (j.isNull("minutes")) null else j.getInt("minutes"), j.getLong("createdAt"), j.optInt("attempts"))
            }
        }
        if (_pending.value.isNotEmpty()) kick()
    }

    fun count(gameId: String) = _pending.value.count { it.gameId == gameId }

    fun enqueue(gameId: String, action: String, minutes: Int? = null): String {
        val p = Pending(UUID.randomUUID().toString(), gameId, action, minutes, System.currentTimeMillis())
        _pending.value = _pending.value + p
        persist()
        kick()
        return p.id
    }

    fun clear(gameId: String) {
        _pending.value = _pending.value.filter { it.gameId != gameId }
        persist()
    }

    private fun persist() {
        val a = JSONArray()
        for (p in _pending.value) a.put(JSONObject().put("id", p.id).put("gameId", p.gameId).put("action", p.action).put("minutes", p.minutes ?: JSONObject.NULL).put("createdAt", p.createdAt).put("attempts", p.attempts))
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("items", a.toString()).apply()
    }

    private fun kick() {
        if (drainJob?.isActive == true) return
        drainJob = scope.launch { drain() }
    }

    private suspend fun drain() {
        while (true) {
            val next = _pending.value.firstOrNull() ?: break
            _sending.value = true
            try {
                val g = ApiClient.act(next.gameId, next.action, next.minutes, next.id)
                _pending.value = _pending.value.drop(1)
                persist()
                lastResult.value = g
                Haptics.click(app)
            } catch (e: ApiError.Server) {
                _pending.value = _pending.value.drop(1)
                persist()
                refusal.value = e.message
                Haptics.fail(app)
            } catch (e: ApiError.Unauthorized) {
                _sending.value = false; delay(5000); continue
            } catch (e: ApiError.NotPaired) {
                _sending.value = false; delay(5000); continue
            } catch (e: Exception) {
                val p = _pending.value.first()
                p.attempts++
                persist()
                _sending.value = false
                delay(min(30_000.0, 2.0.pow(min(p.attempts, 5)) * 1000).toLong())
                continue
            }
        }
        _sending.value = false
    }
}

object Haptics {
    private fun v(c: Context): Vibrator? =
        (c.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
    fun click(c: Context) = v(c)?.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK))
    fun fail(c: Context) = v(c)?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 60, 60, 60), -1))
    fun strong(c: Context) = v(c)?.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_HEAVY_CLICK))
    fun notify(c: Context) = v(c)?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 200, 100, 200), -1))
}
