package com.sportpadi.watch

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.OffsetDateTime

// The watch API's shapes — docs/design/watch-officiant.md. Parsed leniently
// (org.json, every field optional) so a server change never crashes the watch.

private fun JSONObject.str(k: String): String? = if (has(k) && !isNull(k)) optString(k) else null
private fun JSONObject.int(k: String): Int? = if (has(k) && !isNull(k)) optInt(k) else null
private fun JSONObject.obj(k: String): JSONObject? = optJSONObject(k)
private fun JSONObject.arr(k: String): JSONArray = optJSONArray(k) ?: JSONArray()

fun parseIso(s: String?): Instant? = try { s?.let { OffsetDateTime.parse(it).toInstant() } } catch (_: Exception) { null }

data class Invite(
    val gameId: String, val eventId: String?, val title: String, val groupName: String?,
    val date: String?, val startTime: String?, val locationName: String?, val teams: List<String>,
) {
    companion object {
        fun of(j: JSONObject) = Invite(
            j.str("gameId") ?: "", j.str("eventId"), j.str("title") ?: "Match", j.str("groupName"),
            j.str("date"), j.str("startTime"), j.str("locationName"),
            (0 until j.arr("teams").length()).map { j.arr("teams").optString(it) },
        )
    }
}

data class Team(val teamId: String, val name: String, val color: String?, val score: Int) {
    companion object { fun of(j: JSONObject) = Team(j.str("teamId") ?: "", j.str("name") ?: "TBD", j.str("color"), j.optInt("score")) }
}

data class EventInfo(val id: String, val title: String, val date: String?, val startTime: String?, val locationName: String?, val groupName: String?) {
    companion object { fun of(j: JSONObject) = EventInfo(j.str("id") ?: "", j.str("title") ?: "Match", j.str("date"), j.str("startTime"), j.str("locationName"), j.str("groupName")) }
}

data class Phase(
    val key: String, val label: String, val kind: String, val status: String,
    val nominalMinutes: Int?, val nominalOffset: Int, val startedAt: String?, val endedAt: String?,
    val pausedAt: String?, val pausedMs: Double, val stoppageMin: Int, val index: Int, val of: Int,
) {
    companion object {
        fun of(j: JSONObject) = Phase(
            j.str("key") ?: "", j.str("label") ?: "", j.str("kind") ?: "", j.str("status") ?: "",
            j.int("nominalMinutes"), j.optInt("nominalOffset"), j.str("startedAt"), j.str("endedAt"),
            j.str("pausedAt"), j.optDouble("pausedMs", 0.0), j.optInt("stoppageMin"), j.optInt("index"), j.optInt("of"),
        )
    }
}

data class LegacyTimer(val pausedAt: String?, val pausedMs: Double, val stoppageMin: Int) {
    companion object { fun of(j: JSONObject) = LegacyTimer(j.str("pausedAt"), j.optDouble("pausedMs", 0.0), j.optInt("stoppageMin")) }
}

data class By(val userId: String?, val name: String, val action: String?) {
    companion object { fun of(j: JSONObject) = By(j.str("userId"), j.str("name") ?: "someone", j.str("action")) }
}

data class Action(
    val action: String, val label: String, val hold: Boolean, val minutes: List<Int>?,
    /** Sent back with the action (a timeout's team). */
    val arg: String? = null,
) {
    companion object {
        fun of(j: JSONObject) = Action(
            j.str("action") ?: "", j.str("label") ?: "", j.optBoolean("hold", false),
            j.optJSONArray("minutes")?.let { a -> (0 until a.length()).map { a.optInt(it) } },
            j.str("arg"),
        )
    }
}

// ── Scorer mode (docs/design/watch-officiant.md "Scoring") ──────────────────
// All optional: a server from before scorer mode doesn't send `scoring`, and
// the watch stays a clock.

private fun <T> JSONObject.list(k: String, f: (JSONObject) -> T): List<T> {
    val a = arr(k)
    return (0 until a.length()).mapNotNull { a.optJSONObject(it)?.let(f) }
}

/** What a stat does to the score, for instant feedback on the wrist. */
data class StatScore(val team: String, val points: Int)

/** One thing a scorer can record ("goal", "yellow_card", a substitution…). */
data class Stat(
    val type: String, val label: String, val short: String, val icon: String?,
    val assist: Boolean, val kind: String, val score: StatScore?,
    /** The team it can only be for right now (skips "Which team?"). */
    val teamId: String? = null,
    /** "team" stats: the type that takes it back (Undo). */
    val undo: String? = null,
) {
    val isSub get() = kind == "sub"
    /** A team tally with no player (a shootout penalty …). */
    val isTeam get() = kind == "team"

    companion object {
        fun of(j: JSONObject) = Stat(
            j.str("type") ?: "", j.str("label") ?: "", j.str("short") ?: j.str("label") ?: "", j.str("icon"),
            j.optBoolean("assist", false), j.str("kind") ?: "stat",
            j.obj("score")?.let { StatScore(it.str("team") ?: "own", it.optInt("points")) },
            j.str("teamId"), j.str("undo"),
        )
    }
}

data class Player(val id: String, val name: String, val number: Int?, val on: Boolean, val sentOff: Boolean) {
    /** "9 Ade" */
    val line get() = if (number != null) "$number $name" else name

    companion object {
        fun of(j: JSONObject) = Player(j.str("id") ?: "", j.str("name") ?: "Player", j.int("number"), j.optBoolean("on", true), j.optBoolean("sentOff", false))
    }
}

/** One team's people: in the match (on the pitch first) and able to come on. */
data class Side(
    val teamId: String, val color: String?, val players: List<Player>, val bench: List<Player>,
    /** What the tile shows big when it isn't the match score (the current set's points, penalties scored). */
    val value: String? = null,
    /** A line under it ("Sets 1", "Fouls 4"). */
    val caption: String? = null,
) {
    companion object {
        fun of(j: JSONObject) = Side(j.str("teamId") ?: "", j.str("color"), j.list("players", Player::of), j.list("bench", Player::of), j.str("value"), j.str("caption"))
    }
}

/** A recorded event, already worded by the server. */
data class MatchEvent(val id: String, val icon: String?, val teamId: String?, val whenText: String, val title: String, val detail: String?) {
    companion object {
        fun of(j: JSONObject) = MatchEvent(j.str("id") ?: "", j.str("icon"), j.str("teamId"), j.str("when") ?: "", j.str("title") ?: "", j.str("detail"))
    }
}

data class Scoring(
    val open: Boolean, val hint: String?, val primary: List<Stat>, val shortcuts: List<Stat>, val more: List<Stat>,
    val teams: List<Side>, val events: List<MatchEvent>, val clockBy: String?,
    /** A line over the tiles when the sport has one ("Set 2 · to 25", "Penalties"). */
    val title: String? = null,
) {
    fun side(teamId: String?) = teams.firstOrNull { it.teamId == teamId }

    companion object {
        fun of(j: JSONObject) = Scoring(
            j.optBoolean("open", false), j.str("hint"), j.list("primary", Stat::of), j.list("shortcuts", Stat::of), j.list("more", Stat::of),
            j.list("teams", Side::of), j.list("events", MatchEvent::of), j.str("clockBy"), j.str("title"),
        )
    }
}

data class Game(
    val id: String, val status: String, val event: EventInfo?, val teams: List<Team>,
    val role: String?, val canTime: Boolean, val unsupported: String?, val serverNow: String?,
    val startedAt: String?, val phase: Phase?, val timer: LegacyTimer?, val paused: Boolean,
    val lastBy: By?, val actions: List<Action>, val categoryName: String?,
    /** Scorer mode: may I record stats, and what this match offers. */
    val canScore: Boolean = false, val scoring: Scoring? = null,
    /** "down" = show the time LEFT in the period (basketball quarters). */
    val clockDirection: String? = null,
    /** When this view arrived on the watch (for clock skew). */
    val receivedAt: Long = System.currentTimeMillis(),
) {
    val title get() = teams.joinToString(" v ") { it.name }
    val scoreline get() = teams.joinToString(" – ") { it.score.toString() }

    companion object {
        fun of(j: JSONObject) = Game(
            j.str("id") ?: "", j.str("status") ?: "scheduled", j.obj("event")?.let(EventInfo::of),
            (0 until j.arr("teams").length()).mapNotNull { j.arr("teams").optJSONObject(it)?.let(Team::of) },
            j.str("role"), j.optBoolean("canTime"), j.str("unsupported"), j.str("serverNow"),
            j.str("startedAt"), j.obj("phase")?.let(Phase::of), j.obj("timer")?.let(LegacyTimer::of), j.optBoolean("paused"),
            j.obj("lastBy")?.let(By::of),
            (0 until j.arr("actions").length()).mapNotNull { j.arr("actions").optJSONObject(it)?.let(Action::of) },
            j.obj("category")?.str("name"),
            canScore = j.optBoolean("canScore", false),
            scoring = j.obj("scoring")?.let(Scoring::of),
            clockDirection = j.str("clockDirection"),
        )
    }
}

data class Home(val invites: List<Invite>, val games: List<Game>) {
    companion object {
        fun of(j: JSONObject) = Home(
            (0 until j.arr("invites").length()).mapNotNull { j.arr("invites").optJSONObject(it)?.let(Invite::of) },
            (0 until j.arr("games").length()).mapNotNull { j.arr("games").optJSONObject(it)?.let(Game::of) },
        )
    }
}

data class Ping(val type: String, val action: String?, val status: String?, val by: By?) {
    companion object { fun of(j: JSONObject) = Ping(j.str("type") ?: "", j.str("action"), j.str("status"), j.obj("by")?.let(By::of)) }
}
