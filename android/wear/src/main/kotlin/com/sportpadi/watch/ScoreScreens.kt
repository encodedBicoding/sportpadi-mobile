package com.sportpadi.watch

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay
import java.time.Instant

// Scorer mode on the wrist (docs/design/watch-officiant.md "Scoring").
//
// The server's `scoring` block says what this match's category offers — big
// per-team scoring buttons, two shortcuts, the rest under More (substitutions
// included) — plus each side's players and the latest events, so nothing here
// is sport-specific: a side's tile shows the server's `value` when the sport
// has its own number (a set's points, penalties scored), a "team" stat has no
// player (a shootout penalty), and a side of one (singles) skips the player
// pick. A stat is: what, which team, which player, and (when the stat takes
// one) an assist. It goes through ActionQueue like a clock action
// (ordered, retried, idempotent), stamped with the moment of the FIRST tap,
// so a slow pick or a dropped link never moves its minute.

private val Surface = Color(0xFF262626)
private val Muted = Color(0xFFA1A1AA)
private val Orange = Color(0xFFFFA000)
private val Green = Color(0xFF6EDC9E)

/** Text colour that reads on a team colour. */
private fun onColor(c: Color) = if (c.luminance() > 0.45f) Color.Black else Color.White

private fun tabLabel(t: String) = when (t) { "clock" -> "Clock"; "score" -> "Score"; else -> "Events" }

/** Clock · Score · Events — the tabs this officiant's role gets, to tap between. */
@Composable
fun TabRow(tabs: List<String>, current: String, onPick: (String) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally)) {
        for (t in tabs) {
            val on = t == current
            Box(
                Modifier.clip(RoundedCornerShape(50)).background(if (on) Color.White else Surface)
                    .clickable { onPick(t) }.padding(horizontal = 9.dp, vertical = 8.dp),
            ) { Text(tabLabel(t), fontSize = 11.sp, fontWeight = FontWeight.Bold, color = if (on) Color.Black else Color.White) }
        }
    }
}

/** A stat in the making: opened by a tap on the Score tab. */
data class StatDraft(
    /** null = opened from More (pick the stat first). */
    val stat: Stat?,
    /** null = pick the team (shortcuts and More). */
    val teamId: String?,
    /** The first tap — what the minute is stamped from. */
    val tappedAt: Long,
)

/** A stat that was just queued, for the "Saved" screen and Undo. */
data class RecordedStat(
    val actionId: String, val stat: Stat, val teamId: String, val teamName: String,
    /** The player it's credited to — for a substitution, who came ON; null for a team tally. */
    val player: Player?,
    /** The assist — for a substitution, who went OFF. */
    val related: Player?,
    /** "67'" (empty when the clock isn't running in minutes). */
    val minute: String,
)

private sealed class Step {
    object Stats : Step()
    data class TeamPick(val stat: Stat) : Step()
    data class PlayerPick(val stat: Stat, val teamId: String) : Step()
    data class Assist(val stat: Stat, val teamId: String, val scorer: Player) : Step()
    data class SubOn(val stat: Stat, val teamId: String, val off: Player) : Step()
}

/** The score after a stat (`sign` −1 takes it back) — shown at once; the server's view follows. */
private fun scored(g: Game, teamId: String, s: Stat, sign: Int): Game {
    val sc = s.score ?: return g
    val target = when {
        sc.team == "own" -> teamId
        g.teams.size == 2 -> g.teams.firstOrNull { it.teamId != teamId }?.teamId
        else -> null
    } ?: return g
    val delta = sc.points * sign
    // The tile shows the sport's own number (a set's points): move that.
    val scoring = g.scoring
    val shown = scoring?.side(target)?.value?.toIntOrNull()
    if (scoring != null && shown != null) {
        return g.copy(scoring = scoring.copy(teams = scoring.teams.map { if (it.teamId == target) it.copy(value = (shown + delta).coerceAtLeast(0).toString()) else it }))
    }
    return g.copy(teams = g.teams.map { if (it.teamId == target) it.copy(score = (it.score + delta).coerceAtLeast(0)) else it })
}

/** The score for "Saved": the tiles' own numbers when the sport has them, else the match score. */
private fun shownScoreline(g: Game): String {
    val values = g.teams.map { t -> g.scoring?.side(t.teamId)?.value }
    return if (values.any { it != null }) values.joinToString(" – ") { it ?: "–" } else g.scoreline
}

private fun teamColor(g: Game, sc: Scoring, teamId: String?): Color =
    hexColor(sc.side(teamId)?.color ?: g.teams.firstOrNull { it.teamId == teamId }?.color)

private fun teamName(g: Game, teamId: String?) = g.teams.firstOrNull { it.teamId == teamId }?.name ?: ""

// ── Score tab ────────────────────────────────────────────────────────────────

/**
 * The clock in one line (the scorer still needs it), the teams with their
 * scoring buttons, the two shortcuts and More.
 */
@Composable
fun ScorePage(
    gameId: String, g: Game, sc: Scoring, skew: Long, now: Long,
    tabs: List<String>, onTab: (String) -> Unit, refusal: String?, onGame: (Game) -> Unit,
) {
    val context = LocalContext.current
    var draft by remember { mutableStateOf<StatDraft?>(null) }
    val d = draft
    if (d != null) {
        StatFlow(gameId, g, sc, skew, d, onGame) { draft = null }
        return
    }
    fun start(stat: Stat?, teamId: String?) {
        Haptics.click(context)
        draft = StatDraft(stat, teamId, System.currentTimeMillis())
    }
    val clock = BoardClock.of(g, skew, now)
    ScalingLazyColumn(modifier = Modifier.fillMaxSize()) {
        item { TabRow(tabs, "score", onTab) }
        item {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(6.dp).clip(CircleShape).background(if (clock.paused) Orange else if (g.status == "live") Green else Color.Gray))
                    Spacer(Modifier.width(5.dp))
                    Text(clock.text, fontSize = 14.sp, fontWeight = FontWeight.Black, color = if (clock.paused) Orange else Color.White)
                    Spacer(Modifier.width(5.dp))
                    Text(clock.sub, fontSize = 11.sp, color = Muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (!g.canTime && sc.clockBy != null) Text("${sc.clockBy} runs the clock", fontSize = 10.sp, color = Muted, maxLines = 1)
            }
        }
        if (refusal != null) item {
            Chip(onClick = { ActionQueue.refusal.value = null }, label = { Text("Not applied: $refusal", fontSize = 11.sp, maxLines = 3) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth())
        }
        if (!sc.open) {
            item { Text(sc.hint ?: "Stats open when the match starts", fontSize = 12.sp, color = Muted, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp)) }
        } else {
            if (sc.title != null) item { Text(sc.title, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Muted, maxLines = 1) }
            for (pair in g.teams.chunked(2)) item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (t in pair) TeamTile(t, sc.side(t.teamId), teamColor(g, sc, t.teamId), sc.primary, Modifier.weight(1f)) { s -> start(s, t.teamId) }
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (s in sc.shortcuts) SmallButton(s.icon ?: "•", s.short, Modifier.weight(1f)) { start(s, s.teamId) }
                    if (sc.more.isNotEmpty()) SmallButton("⋯", "More", Modifier.weight(1f)) { start(null, null) }
                }
            }
        }
    }
}

/**
 * One team: name, score and a button per scoring action ("+ Goal", or
 * "+2" "+3" "+1"). With a single action the whole tile is the button.
 */
@Composable
private fun TeamTile(t: Team, side: Side?, color: Color, primary: List<Stat>, modifier: Modifier, onStat: (Stat) -> Unit) {
    val single = primary.singleOrNull()
    Column(
        modifier.clip(RoundedCornerShape(14.dp)).background(Surface)
            .let { m -> if (single != null) m.clickable { onStat(single) } else m }
            .padding(6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(width = 4.dp, height = 11.dp).clip(RoundedCornerShape(2.dp)).background(color))
            Spacer(Modifier.width(4.dp))
            Text(t.name, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        // The sport's own number when it has one (a set's points), else the score.
        Text(side?.value ?: t.score.toString(), fontSize = 28.sp, fontWeight = FontWeight.Black)
        val caption = side?.caption
        if (caption != null) Text(caption, fontSize = 10.sp, color = Muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        for (s in primary) {
            Box(
                Modifier.padding(top = 3.dp).fillMaxWidth().height(32.dp).clip(RoundedCornerShape(50)).background(color).clickable { onStat(s) },
                contentAlignment = Alignment.Center,
            ) {
                Text(if (primary.size > 1) s.short else "+ ${s.short}", fontSize = 13.sp, fontWeight = FontWeight.Black, color = onColor(color), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun SmallButton(icon: String, label: String, modifier: Modifier, onClick: () -> Unit) {
    Column(
        modifier.height(46.dp).clip(RoundedCornerShape(13.dp)).background(Surface).clickable(onClick = onClick),
        verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(icon, fontSize = 16.sp)
        Text(label, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

// ── Recording flow ───────────────────────────────────────────────────────────

/**
 * The steps after a tap on the Score tab: (what) → (which team) → who →
 * (assist | who's coming on) → saved, with Undo. The back button steps back.
 */
@Composable
private fun StatFlow(gameId: String, g: Game, sc: Scoring, skew: Long, draft: StatDraft, onGame: (Game) -> Unit, onClose: () -> Unit) {
    val context = LocalContext.current
    var stack by remember {
        val s = draft.stat
        val t = draft.teamId
        val first: Step = if (s == null) Step.Stats else if (t != null) Step.PlayerPick(s, t) else Step.TeamPick(s)
        mutableStateOf(listOf(first))
    }
    var saved by remember { mutableStateOf<RecordedStat?>(null) }
    fun push(s: Step) { stack = stack + s }
    fun back() { if (stack.size > 1) stack = stack.dropLast(1) else onClose() }

    /** Queue it (stamped with the first tap), move the score, show "Saved". */
    fun record(s: Stat, teamId: String, player: Player, related: Player?) {
        val extra = mutableMapOf("teamId" to teamId, "at" to Instant.ofEpochMilli(draft.tappedAt + skew).toString())
        val action: String
        if (s.isSub) {
            action = "sub"
            extra["playerOnId"] = player.id
            extra["playerOffId"] = related?.id ?: ""
        } else {
            action = "stat"
            extra["type"] = s.type
            extra["playerId"] = player.id
            if (related != null) extra["relatedPlayerId"] = related.id
        }
        // "67:12" → "67'" ("45+2:30" → "45+2'"); nothing when the clock isn't in minutes.
        val text = if (g.status == "live") BoardClock.of(g, skew, draft.tappedAt).text else ""
        val minute = if (text.contains(":")) text.substringBefore(":") + "'" else ""
        val id = ActionQueue.enqueue(gameId, action, extra = extra)
        onGame(scored(g, teamId, s, 1))
        Haptics.strong(context)
        saved = RecordedStat(id, s, teamId, teamName(g, teamId), player, related, if (g.clockDirection == "down") text else minute)
    }

    /** A team tally (a shootout penalty): no player, no minute. */
    fun recordTeam(s: Stat, teamId: String) {
        val id = ActionQueue.enqueue(gameId, "teamStat", extra = mapOf("type" to s.type, "teamId" to teamId))
        Haptics.strong(context)
        saved = RecordedStat(id, s, teamId, teamName(g, teamId), null, null, "")
    }

    /** A side of one (singles) is its only player. */
    fun onlyPlayer(s: Stat, teamId: String): Player? =
        if (s.isSub) null else sc.side(teamId)?.players?.singleOrNull()

    /** The assist question only when there's a team-mate to credit. */
    fun playerPicked(s: Stat, teamId: String, p: Player) {
        if (s.assist && (sc.side(teamId)?.players?.size ?: 0) > 1) push(Step.Assist(s, teamId, p)) else record(s, teamId, p, null)
    }

    fun teamPicked(s: Stat, teamId: String) {
        val only = onlyPlayer(s, teamId)
        when {
            s.isTeam -> recordTeam(s, teamId)
            only != null -> playerPicked(s, teamId, only)
            else -> push(Step.PlayerPick(s, teamId))
        }
    }

    // Nothing to ask? Then don't: a team tally for a known team is recorded
    // straight away, and a side of one is picked for you.
    LaunchedEffect(draft) {
        val s = draft.stat
        val t = draft.teamId
        if (s != null && t != null && saved == null && stack.size == 1) {
            val only = onlyPlayer(s, t)
            if (s.isTeam) recordTeam(s, t) else if (only != null) playerPicked(s, t, only)
        }
    }

    val rec = saved
    if (rec != null) {
        BackHandler { onClose() }
        SavedScreen(rec, shownScoreline(g), onUndo = {
            // Still in the queue → just take it out. Already sent (or on its
            // way) → the server takes it back, in order: a player's stat by
            // its own id, a team tally by its opposite.
            if (!ActionQueue.cancel(rec.actionId)) {
                if (rec.stat.isTeam) {
                    rec.stat.undo?.let { opposite -> ActionQueue.enqueue(gameId, "teamStat", extra = mapOf("type" to opposite, "teamId" to rec.teamId)) }
                } else {
                    ActionQueue.enqueue(gameId, "undoStat", extra = mapOf("ref" to rec.actionId))
                }
            }
            onGame(scored(g, rec.teamId, rec.stat, -1))
            Haptics.click(context)
            onClose()
        }, onDone = onClose)
        return
    }

    BackHandler { back() }
    when (val step = stack.last()) {
        is Step.Stats -> ScalingLazyColumn(modifier = Modifier.fillMaxSize()) {
            item { Header("What happened?", g.categoryName) }
            items(sc.more) { s ->
                Chip(
                    onClick = { val preset = s.teamId; if (preset != null) teamPicked(s, preset) else push(Step.TeamPick(s)) },
                    label = { Text(s.label, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                    icon = { Text(s.icon ?: "•", fontSize = 16.sp) },
                    colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth(),
                )
            }
            item { CancelChip(onClose) }
        }
        is Step.TeamPick -> ScalingLazyColumn(modifier = Modifier.fillMaxSize()) {
            item { Header("Which team?", step.stat.label) }
            items(g.teams) { t ->
                val c = teamColor(g, sc, t.teamId)
                Box(
                    Modifier.fillMaxWidth().height(52.dp).clip(RoundedCornerShape(16.dp)).background(c).clickable { teamPicked(step.stat, t.teamId) },
                    contentAlignment = Alignment.Center,
                ) { Text(t.name, fontSize = 16.sp, fontWeight = FontWeight.Black, color = onColor(c), maxLines = 2, textAlign = TextAlign.Center) }
            }
            item { CancelChip({ back() }) }
        }
        is Step.PlayerPick -> {
            val s = step.stat
            val all = sc.side(step.teamId)?.players ?: emptyList()
            val team = teamName(g, step.teamId)
            if (s.isTeam) {
                // Recorded as it opens: nothing to pick.
                Box(Modifier.fillMaxSize())
            } else if (s.isSub) {
                PlayerList("Coming off?", "${s.label} · $team", all.filter { it.on }, teamColor(g, sc, step.teamId), "Nobody from $team is on the pitch.", null, { back() }) { off ->
                    push(Step.SubOn(s, step.teamId, off))
                }
            } else {
                PlayerList(if (s.score != null) "Who scored?" else "Which player?", "${s.label} · $team", all, teamColor(g, sc, step.teamId), "No players on $team's team sheet — add them on the phone.", null, { back() }) { p ->
                    playerPicked(s, step.teamId, p)
                }
            }
        }
        is Step.Assist -> {
            val mates = (sc.side(step.teamId)?.players ?: emptyList()).filter { it.id != step.scorer.id }
            PlayerList("Assist?", "${step.stat.label} · ${step.scorer.line}", mates, teamColor(g, sc, step.teamId), null, { record(step.stat, step.teamId, step.scorer, null) }, { back() }) { m ->
                record(step.stat, step.teamId, step.scorer, m)
            }
        }
        is Step.SubOn -> {
            val team = teamName(g, step.teamId)
            PlayerList("Coming on?", "for ${step.off.line}", sc.side(step.teamId)?.bench ?: emptyList(), teamColor(g, sc, step.teamId), "No one on $team's bench.", null, { back() }) { on ->
                record(step.stat, step.teamId, on, step.off)
            }
        }
    }
}

@Composable
private fun Header(title: String, caption: String?) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        if (!caption.isNullOrEmpty()) Text(caption, fontSize = 11.sp, color = Muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(title, fontSize = 15.sp, fontWeight = FontWeight.Black, textAlign = TextAlign.Center)
    }
}

@Composable
private fun CancelChip(onClick: () -> Unit) {
    Chip(onClick = onClick, label = { Text("Back") }, colors = ChipDefaults.childChipColors(), modifier = Modifier.fillMaxWidth())
}

/**
 * A team's players (the server's order: on the pitch first, by shirt number).
 * [onNone], when set, adds a "No assist" row on top.
 */
@Composable
private fun PlayerList(
    title: String, caption: String, players: List<Player>, color: Color, empty: String?,
    onNone: (() -> Unit)?, onBack: () -> Unit, onPick: (Player) -> Unit,
) {
    ScalingLazyColumn(modifier = Modifier.fillMaxSize()) {
        item { Header(title, caption) }
        if (onNone != null) item {
            Chip(onClick = onNone, label = { Text("No assist", fontWeight = FontWeight.Bold) }, colors = ChipDefaults.primaryChipColors(backgroundColor = Color(0xFF424242)), modifier = Modifier.fillMaxWidth())
        }
        if (players.isEmpty() && empty != null) item { Text(empty, fontSize = 12.sp, color = Orange, textAlign = TextAlign.Center) }
        items(players) { p ->
            Chip(
                onClick = { onPick(p) },
                label = { Text(if (p.sentOff) "${p.name} · sent off" else if (!p.on) "${p.name} · bench" else p.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                icon = {
                    Box(Modifier.size(width = 28.dp, height = 24.dp).clip(RoundedCornerShape(8.dp)).background(color), contentAlignment = Alignment.Center) {
                        Text(p.number?.toString() ?: "–", fontSize = 13.sp, fontWeight = FontWeight.Black, color = onColor(color))
                    }
                },
                colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth(),
            )
        }
        item { CancelChip(onBack) }
    }
}

/**
 * "Saved": what was recorded, the score, and Undo for five seconds — then
 * back to the Score tab by itself.
 */
@Composable
private fun SavedScreen(rec: RecordedStat, scoreline: String, onUndo: () -> Unit, onDone: () -> Unit) {
    var progress by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(rec.actionId) {
        val steps = 50
        for (i in 1..steps) { delay(100); progress = i / steps.toFloat() }
        onDone()
    }
    Column(Modifier.fillMaxSize().padding(horizontal = 14.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Text("✓", fontSize = 22.sp, fontWeight = FontWeight.Black, color = Green)
        Text(listOf(rec.stat.label, rec.minute).filter { it.isNotEmpty() }.joinToString(" · "), fontSize = 14.sp, fontWeight = FontWeight.Black, textAlign = TextAlign.Center, maxLines = 2)
        if (rec.stat.score != null) Text(scoreline, fontSize = 22.sp, fontWeight = FontWeight.Black)
        Text(rec.player?.line ?: rec.teamName, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        val r = rec.related
        if (r != null) Text(if (rec.stat.isSub) "for ${r.line}" else "assist ${r.line}", fontSize = 11.sp, color = Muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(4.dp))
        // (An undo of its own has nothing to take back.)
        if (!rec.stat.isTeam || rec.stat.undo != null) Box(
            Modifier.fillMaxWidth(0.8f).height(36.dp).clip(RoundedCornerShape(50)).background(Surface).clickable(onClick = onUndo),
            contentAlignment = Alignment.Center,
        ) { Text("Undo", fontSize = 14.sp, fontWeight = FontWeight.Bold) }
        Spacer(Modifier.height(5.dp))
        Box(Modifier.fillMaxWidth(0.6f).height(3.dp).clip(RoundedCornerShape(2.dp)).background(Surface)) {
            Box(Modifier.fillMaxWidth(progress).height(3.dp).background(Muted))
        }
    }
}

// ── Events tab ───────────────────────────────────────────────────────────────

/**
 * What's been recorded, newest first. Tap one, then HOLD to remove it (a
 * stray tap can't delete a goal). A scorer who doesn't run the clock leaves a
 * live match from here ([onExit]).
 */
@Composable
fun EventsPage(
    gameId: String, g: Game, sc: Scoring, tabs: List<String>, onTab: (String) -> Unit,
    waiting: Int, sending: Boolean, onGame: (Game) -> Unit, onExit: (() -> Unit)?,
) {
    var removing by remember { mutableStateOf<MatchEvent?>(null) }
    val r = removing
    if (r != null) {
        BackHandler { removing = null }
        ScalingLazyColumn(modifier = Modifier.fillMaxSize()) {
            item { Header(r.title, listOfNotNull(r.detail, r.whenText.ifEmpty { null }).joinToString(" · ")) }
            item {
                HoldButton(label = "Remove", color = Color(0xFFC62828)) {
                    ActionQueue.enqueue(gameId, "removeStat", extra = mapOf("activityId" to r.id))
                    onGame(g.copy(scoring = sc.copy(events = sc.events.filter { it.id != r.id })))
                    removing = null
                }
            }
            item { Text("Hold to remove", fontSize = 10.sp, color = Muted) }
            item { CancelChip { removing = null } }
        }
        return
    }
    ScalingLazyColumn(modifier = Modifier.fillMaxSize()) {
        item { TabRow(tabs, "events", onTab) }
        if (waiting > 0) item {
            Text(if (sending) "Sending $waiting…" else "$waiting not sent yet — no connection", fontSize = 10.sp, color = Orange, textAlign = TextAlign.Center)
        }
        if (sc.events.isEmpty()) item { Text("Nothing recorded yet", fontSize = 12.sp, color = Muted) }
        else item { Text("Tap one to remove", fontSize = 10.sp, color = Muted) }
        items(sc.events) { e ->
            Row(
                Modifier.fillMaxWidth().height(40.dp).clip(RoundedCornerShape(12.dp)).background(Surface).clickable { removing = e }.padding(horizontal = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(width = 3.dp, height = 26.dp).clip(RoundedCornerShape(2.dp)).background(teamColor(g, sc, e.teamId)))
                Spacer(Modifier.width(6.dp))
                Text(e.whenText, fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Muted, maxLines = 1, modifier = Modifier.width(30.dp))
                Text(e.icon ?: "•", fontSize = 13.sp)
                Spacer(Modifier.width(6.dp))
                Column(Modifier.weight(1f)) {
                    Text(e.title, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (!e.detail.isNullOrEmpty()) Text(e.detail, fontSize = 10.sp, color = Muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        if (onExit != null) item { HoldButton(label = "Exit", color = Color(0xFF424242), seconds = 2.0, onConfirm = onExit) }
    }
}
