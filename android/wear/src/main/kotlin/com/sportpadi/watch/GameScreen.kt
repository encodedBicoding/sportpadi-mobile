package com.sportpadi.watch

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * One match — full officiant mode. Teams, score, period and a clock that
 * runs from the server's timestamps; the buttons the server says are allowed
 * right now (`actions[]`): pause/resume, add time, hold-to-confirm for
 * kick-off / end of period / full time, start next, extra time / penalties /
 * overtime when drawn, and hold-to-exit. Taps go through ActionQueue
 * (ordered, retried, idempotent). Every realtime ping refetches; "Paused by
 * Ade" when another device did it. Ambient (wrist down): the clock only.
 */
@Composable
fun GameScreen(gameId: String, activity: MainActivity, onExit: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val ctx by ContextStore.ctx.collectAsState()
    var game by remember { mutableStateOf<Game?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var skew by remember { mutableLongStateOf(0L) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val live = remember { LiveStream(scope) }
    val ping by live.ping.collectAsState()
    val connected by live.connected.collectAsState()
    val pending by ActionQueue.pending.collectAsState()
    val sending by ActionQueue.sending.collectAsState()
    val refusal by ActionQueue.refusal.collectAsState()
    val lastResult by ActionQueue.lastResult.collectAsState()
    var remindedPhase by remember { mutableStateOf<String?>(null) }
    var remindedOver by remember { mutableStateOf<String?>(null) }

    fun adopt(g: Game) {
        parseIso(g.serverNow)?.let { skew = it.toEpochMilli() - g.receivedAt }
        game = g
    }
    suspend fun load(p: Ping? = null) {
        try {
            adopt(ApiClient.game(gameId)); error = null
            // Taps for the moments that matter when ANOTHER device did them.
            val by = p?.by
            if (by != null && by.userId != ctx.userId) when {
                p.type == "status" && p.status == "live" -> Haptics.strong(context)
                p.type == "phase" -> Haptics.strong(context)
                p.type == "timer" && p.action == "pause" -> Haptics.click(context)
                p.type == "status" && p.status == "completed" -> Haptics.notify(context)
            }
        } catch (e: Exception) { if (game == null) error = e.message }
    }

    LaunchedEffect(gameId) { UsageTracker.screen("/watch/games/$gameId"); load(); live.start(gameId); ContextStore.tellPhoneOpen(gameId) }
    androidx.compose.runtime.DisposableEffect(gameId) { onDispose { UsageTracker.screen("/watch") } }
    LifecycleResumeEffect(gameId) {
        scope.launch { load() }; live.start(gameId)
        onPauseOrDispose { live.stop() }
    }
    LaunchedEffect(ping) { ping?.let { load(it.second) } }
    LaunchedEffect(lastResult?.serverNow) { lastResult?.let { if (it.id == gameId) adopt(it) } }
    // Half-second tick (one second in ambient).
    LaunchedEffect(activity.ambient) { while (isActive) { now = System.currentTimeMillis(); delay(if (activity.ambient) 1000 else 500) } }
    // Keep the clock on the watch face while live; off at full time / exit.
    val status = game?.status
    LaunchedEffect(status) {
        val g = game ?: return@LaunchedEffect
        if (status == "live" && g.canTime) OngoingMatch.start(context, g) else OngoingMatch.stop(context)
    }

    val g = game
    if (g == null) {
        if (error != null) Pitch(error ?: "", "Tap to try again") { scope.launch { load() } }
        else Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }
    val clock = BoardClock.of(g, skew, now)
    // Period-end taps: once at nominal, once when added time runs out.
    val ph = g.phase
    val mins = BoardClock.phaseMinutes(g, skew, now)
    if (ph != null && mins != null && ph.nominalMinutes != null && g.status == "live") {
        if (mins >= ph.nominalMinutes && remindedPhase != ph.key) { remindedPhase = ph.key; Haptics.notify(context) }
        if (ph.stoppageMin > 0 && mins >= ph.nominalMinutes + ph.stoppageMin && remindedOver != ph.key) { remindedOver = ph.key; Haptics.notify(context) }
    }

    if (activity.ambient) {
        // Wrist down: the clock, nothing else.
        Column(Modifier.fillMaxSize().background(Color.Black), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Text(g.scoreline, fontSize = 18.sp, color = Color.Gray)
            Text(clock.text, fontSize = 44.sp, fontWeight = FontWeight.Bold, color = if (clock.paused) Color(0xFFFFA000) else Color.White)
            Text(clock.sub, fontSize = 12.sp, color = Color.Gray)
        }
        return
    }

    val queued = pending.count { it.gameId == gameId }
    ScalingLazyColumn(modifier = Modifier.fillMaxSize()) {
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                TeamCol(g.teams.getOrNull(0), Modifier.weight(1f))
                Text(if (g.status == "scheduled") "v" else g.scoreline, fontSize = if (g.status == "scheduled") 14.sp else 24.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(horizontal = 4.dp))
                TeamCol(g.teams.getOrNull(1), Modifier.weight(1f))
            }
        }
        item {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(clock.text, fontSize = 38.sp, fontWeight = FontWeight.Black, color = if (clock.paused) Color(0xFFFFA000) else Color.White)
                Text(clock.sub, fontSize = 12.sp, color = if (g.status == "live") Color(0xFF6EDC9E) else Color.Gray)
                val by = g.lastBy
                if (by?.action != null && g.status == "live" && by.userId != ctx.userId) Text("${verb(by.action)} by ${by.name}", fontSize = 10.sp, color = Color.Gray)
                if (g.unsupported != null) Text(g.unsupported, fontSize = 10.sp, color = Color(0xFFFFA000), textAlign = TextAlign.Center)
                else if (g.role != null && !g.canTime && g.status != "completed") Text("Scorer only — the timekeeper runs the clock", fontSize = 10.sp, color = Color(0xFFFFA000), textAlign = TextAlign.Center)
            }
        }
        // Buttons, in the server's order.
        for (a in g.actions) item {
            val busy = queued > 0
            when {
                a.minutes != null -> Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                    Text(a.label, fontSize = 10.sp, color = Color.Gray)
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        for (m in a.minutes) Button(onClick = { ActionQueue.enqueue(gameId, a.action, m) }, colors = ButtonDefaults.secondaryButtonColors(), modifier = Modifier.size(36.dp)) { Text("+$m", fontSize = 12.sp) }
                    }
                }
                a.hold -> HoldButton(
                    label = a.label, enabled = !busy,
                    color = when (a.action) { "fullTime" -> Color(0xFFC62828); "kickoff" -> Color(0xFF1B7A4F); else -> Color(0xFFE08A1C) },
                ) { ActionQueue.enqueue(gameId, a.action); game = optimistic(g, a.action, skew) }
                else -> Chip(
                    onClick = { ActionQueue.enqueue(gameId, a.action); game = optimistic(g, a.action, skew) },
                    enabled = !busy || a.action == "pause",
                    label = { Text(a.label) },
                    colors = ChipDefaults.primaryChipColors(backgroundColor = when (a.action) { "pause" -> Color(0xFFE08A1C); "resume" -> Color(0xFF1B7A4F); else -> Color(0xFF1565C0) }),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        if (g.status == "live") item {
            HoldButton(label = "Exit", color = Color(0xFF424242), seconds = 2.0) {
                ActionQueue.clear(gameId); OngoingMatch.stop(context); onExit()
            }
        }
        item {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
                Box(Modifier.size(6.dp).clip(CircleShape).background(if (connected) Color(0xFF6EDC9E) else Color.Gray))
                Spacer(Modifier.width(4.dp))
                Text(
                    when { queued > 0 && sending -> "sending…"; queued > 0 -> "$queued queued — no connection"; connected -> "live"; else -> "reconnecting…" },
                    fontSize = 10.sp, color = if (queued > 0 && !sending) Color(0xFFFFA000) else Color.Gray,
                )
            }
        }
        if (refusal != null) item {
            Chip(onClick = { ActionQueue.refusal.value = null }, label = { Text("Not applied: $refusal", fontSize = 11.sp, maxLines = 3) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun TeamCol(t: Team?, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(12.dp).clip(CircleShape).background(hexColor(t?.color)))
        Text(t?.name ?: "TBD", fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 2, textAlign = TextAlign.Center)
    }
}

private fun hexColor(hex: String?): Color {
    val h = hex?.trim()?.removePrefix("#") ?: return Color.Gray
    if (h.length < 6) return Color.Gray
    val v = h.take(6).toLongOrNull(16) ?: return Color.Gray
    return Color(((0xFF shl 24) or v.toInt()))
}

private fun verb(a: String) = when (a) {
    "kickoff" -> "Kicked off"; "pause" -> "Paused"; "resume" -> "Resumed"; "stoppage" -> "Time added"
    "endPhase" -> "Period ended"; "startNext" -> "Period started"; "fullTime" -> "Full time"; else -> a.replaceFirstChar { it.uppercase() }
}

/** Flip pause/resume locally so the tap shows at once; the server's view replaces it. */
private fun optimistic(g: Game, action: String, skewMs: Long): Game {
    val nowIso = Instant.ofEpochMilli(System.currentTimeMillis() + skewMs).toString()
    return when (action) {
        "pause" -> g.copy(paused = true, phase = g.phase?.copy(pausedAt = nowIso), timer = if (g.phase == null) g.timer?.copy(pausedAt = nowIso) else g.timer)
        "resume" -> {
            val ph = g.phase
            val t = g.timer
            val since = parseIso(ph?.pausedAt ?: t?.pausedAt)?.toEpochMilli()
            val extra = if (since != null) (System.currentTimeMillis() + skewMs - since).toDouble() else 0.0
            g.copy(
                paused = false,
                phase = ph?.copy(pausedAt = null, pausedMs = ph.pausedMs + extra),
                timer = if (ph == null) t?.copy(pausedAt = null, pausedMs = t.pausedMs + extra) else t,
            )
        }
        else -> g
    }
}

/** Press and hold to confirm — a filling bar, haptics; letting go early cancels. */
@Composable
fun HoldButton(label: String, color: Color, enabled: Boolean = true, seconds: Double = 1.5, onConfirm: () -> Unit) {
    val context = LocalContext.current
    var progress by remember { mutableStateOf(0f) }
    var holding by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    Box(
        Modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(14.dp)).background(color.copy(alpha = if (enabled) 0.85f else 0.3f))
            .pointerInput(enabled, seconds) {
                if (!enabled) return@pointerInput
                detectTapGestures(onPress = {
                    holding = true; progress = 0f; Haptics.click(context)
                    val job = scope.launch {
                        val steps = (seconds * 20).toInt()
                        for (i in 1..steps) { delay(50); progress = i / steps.toFloat() }
                        Haptics.strong(context); holding = false; progress = 0f; onConfirm()
                    }
                    val released = tryAwaitRelease()
                    if (job.isActive) { job.cancel(); if (released) Haptics.click(context) }
                    holding = false; progress = 0f
                })
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(progress).background(Color.White.copy(alpha = 0.28f)).align(Alignment.CenterStart))
        Text(if (holding) "Hold…" else label, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White)
    }
}
