package com.sportpadi.watch

import java.time.Instant

/**
 * The board clock from the server's timestamps — never from a countdown —
 * so a dropped link changes nothing (docs/design/watch-officiant.md).
 */
data class BoardClock(val text: String, val sub: String, val paused: Boolean) {
    companion object {
        /** `skew` = serverNow − the moment the view arrived (ms). */
        fun of(g: Game, skewMs: Long, nowMs: Long = System.currentTimeMillis()): BoardClock {
            val serverNow = nowMs + skewMs
            when (g.status) {
                "scheduled" -> return BoardClock("0:00", "Not started", false)
                "completed" -> return BoardClock("FT", "Full time", false)
                "abandoned" -> return BoardClock("—", "Abandoned", false)
            }
            val ph = g.phase
            if (ph != null) {
                val started = parseIso(ph.startedAt)
                val nominal = ph.nominalMinutes
                if (ph.status != "live" || started == null || nominal == null) {
                    return BoardClock(ph.label, if (ph.status == "ended") "Period over" else "Waiting", false)
                }
                var paused = ph.pausedMs / 1000.0
                parseIso(ph.pausedAt)?.let { paused += ((serverNow - it.toEpochMilli()) / 1000.0).coerceAtLeast(0.0) }
                val total = ((serverNow - started.toEpochMilli()) / 1000.0 - paused).toInt().coerceAtLeast(0)
                val mins = total / 60
                val minute = ph.nominalOffset + minOf(mins, nominal)
                val over = (mins - nominal).coerceAtLeast(0)
                var sub = ph.label
                if (ph.stoppageMin > 0) sub += " · +${ph.stoppageMin}"
                if (ph.pausedAt != null) sub += " · paused"
                return BoardClock("$minute${if (over > 0) "+$over" else ""}:${"%02d".format(total % 60)}", sub, ph.pausedAt != null)
            }
            val t = g.timer
            val started = parseIso(g.startedAt)
            if (t != null && started != null) {
                var paused = t.pausedMs / 1000.0
                parseIso(t.pausedAt)?.let { paused += ((serverNow - it.toEpochMilli()) / 1000.0).coerceAtLeast(0.0) }
                val total = ((serverNow - started.toEpochMilli()) / 1000.0 - paused).toInt().coerceAtLeast(0)
                var sub = if (t.pausedAt != null) "paused" else "running"
                if (t.stoppageMin > 0) sub = "+${t.stoppageMin} · $sub"
                return BoardClock("${total / 60}:${"%02d".format(total % 60)}", sub, t.pausedAt != null)
            }
            return BoardClock("--:--", "", false)
        }

        /** Minutes elapsed in the current live phase (for the period-end taps). */
        fun phaseMinutes(g: Game, skewMs: Long, nowMs: Long = System.currentTimeMillis()): Double? {
            val ph = g.phase ?: return null
            val started = parseIso(ph.startedAt) ?: return null
            if (ph.status != "live") return null
            val serverNow = nowMs + skewMs
            var paused = ph.pausedMs / 1000.0
            parseIso(ph.pausedAt)?.let { paused += ((serverNow - it.toEpochMilli()) / 1000.0).coerceAtLeast(0.0) }
            return ((serverNow - started.toEpochMilli()) / 1000.0 - paused) / 60.0
        }
    }
}

/** "Today · 15:00", "Sat 25 Oct · 15:00". Times are the venue's wall clock stored as UTC. */
fun whenLine(date: String?, startTime: String?): String {
    val d = parseIso(date) ?: return ""
    val z = java.time.ZoneOffset.UTC
    val day = d.atZone(z).toLocalDate()
    // The event date is a calendar day stored as midnight UTC (read in UTC);
    // "today" is the officiant's own calendar day.
    val today = java.time.LocalDate.now()
    val dayText = when (day) {
        today -> "Today"
        today.plusDays(1) -> "Tomorrow"
        today.minusDays(1) -> "Yesterday"
        else -> day.format(java.time.format.DateTimeFormatter.ofPattern("EEE d MMM"))
    }
    val t = parseIso(startTime) ?: return dayText
    return "$dayText · ${t.atZone(z).toLocalTime().format(java.time.format.DateTimeFormatter.ofPattern("HH:mm"))}"
}
