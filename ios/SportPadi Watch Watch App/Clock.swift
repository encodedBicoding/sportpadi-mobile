import Foundation

/// The board clock, computed from the server's timestamps — never from a
/// "remaining" number — so a dropped link changes nothing
/// (docs/design/watch-officiant.md "Running the clock locally").
struct BoardClock {
  var text: String      // "67:12", "45+2:30", "HT", "FT", "0:00"
  var sub: String       // "2nd half · +2 · paused"
  var paused: Bool

  /// `skew` = serverNow − the moment that view was received.
  static func of(_ g: WatchGame, skew: TimeInterval, now: Date = Date()) -> BoardClock {
    let serverNow = now.addingTimeInterval(skew)
    switch g.status {
    case "scheduled": return BoardClock(text: "0:00", sub: "Not started", paused: false)
    case "completed": return BoardClock(text: "FT", sub: "Full time", paused: false)
    case "abandoned": return BoardClock(text: "—", sub: "Abandoned", paused: false)
    default: break
    }
    if let ph = g.phase {
      guard ph.status == "live", let started = ISO.date(ph.startedAt), let nominal = ph.nominalMinutes else {
        return BoardClock(text: ph.label, sub: ph.status == "ended" ? "Period over" : "Waiting", paused: false)
      }
      var paused = ph.pausedMs / 1000
      if let p = ISO.date(ph.pausedAt) { paused += max(0, serverNow.timeIntervalSince(p)) }
      let total = max(0, Int(serverNow.timeIntervalSince(started) - paused))
      let mins = total / 60
      let minute = ph.nominalOffset + min(mins, nominal)
      let over = max(0, mins - nominal)
      var sub = ph.label
      if ph.stoppageMin > 0 { sub += " · +\(ph.stoppageMin)" }
      if ph.pausedAt != nil { sub += " · paused" }
      return BoardClock(text: "\(minute)\(over > 0 ? "+\(over)" : ""):\(String(format: "%02d", total % 60))", sub: sub, paused: ph.pausedAt != nil)
    }
    if let t = g.timer, let started = ISO.date(g.startedAt) {
      var paused = t.pausedMs / 1000
      if let p = ISO.date(t.pausedAt) { paused += max(0, serverNow.timeIntervalSince(p)) }
      let total = max(0, Int(serverNow.timeIntervalSince(started) - paused))
      var sub = t.pausedAt != nil ? "paused" : "running"
      if t.stoppageMin > 0 { sub = "+\(t.stoppageMin) · " + sub }
      return BoardClock(text: "\(total / 60):\(String(format: "%02d", total % 60))", sub: sub, paused: t.pausedAt != nil)
    }
    return BoardClock(text: "--:--", sub: "", paused: false)
  }
}

/// Kick-off as the officiant sees it: "Sat 25 Oct · 15:00" or "Today · 15:00".
enum When {
  static func line(date: String?, startTime: String?) -> String {
    guard let d = ISO.date(date) else { return "" }
    let cal = Calendar.current
    let day: String
    if cal.isDateInToday(d) { day = "Today" }
    else if cal.isDateInTomorrow(d) { day = "Tomorrow" }
    else {
      let f = DateFormatter(); f.dateFormat = "EEE d MMM"; f.timeZone = TimeZone(identifier: "UTC")
      day = f.string(from: d)
    }
    guard let t = ISO.date(startTime) else { return day }
    // Times are the venue's wall clock stored as UTC — show them as-is.
    let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = TimeZone(identifier: "UTC")
    return "\(day) · \(f.string(from: t))"
  }
}
