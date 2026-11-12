import Foundation
import SwiftUI
import WatchKit

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

// MARK: colours

/// A team colour from its hex, and whether text on it should be dark.
struct TeamColor {
  let color: Color
  let isLight: Bool

  init(_ hex: String?) {
    let h = (hex ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    guard h.count >= 6, let v = UInt32(h.prefix(6), radix: 16) else {
      color = .gray
      isLight = false
      return
    }
    let r = Double((v >> 16) & 0xff) / 255, g = Double((v >> 8) & 0xff) / 255, b = Double(v & 0xff) / 255
    color = Color(red: r, green: g, blue: b)
    isLight = (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
  }

  var onColor: Color { isLight ? .black : .white }
}

// MARK: what's being recorded

/// A stat in the making: opened by a tap on the Score tab.
struct StatDraft: Identifiable {
  let id = UUID()
  /// nil = opened from More (pick the stat first).
  var stat: WatchStat?
  /// nil = pick the team (shortcuts and More).
  var teamId: String?
  /// The first tap — what the minute is stamped from.
  let tappedAt: Date
}

/// A stat that was just queued, for the "Saved" screen and Undo.
struct RecordedStat {
  var actionId: String
  var stat: WatchStat
  var teamId: String
  var teamName: String
  /// The player it's credited to — for a substitution, who came ON; nil for
  /// a team tally.
  var player: WatchPlayer?
  /// The assist — for a substitution, who went OFF.
  var related: WatchPlayer?
  /// "67'" (empty when the clock isn't running in minutes).
  var minute: String
}

private func playerLine(_ p: WatchPlayer) -> String {
  if let n = p.number { return "\(n) \(p.name)" }
  return p.name
}

// MARK: Score tab

/// The clock in one line (the scorer still needs it), the teams with their
/// scoring buttons, the two shortcuts and More.
struct ScoreTab: View {
  let gameId: String
  let game: WatchGame
  let scoring: WatchScoring
  @ObservedObject var model: GameModel
  /// Set when this officiant also runs the clock: the strip jumps there.
  var onClock: (() -> Void)?
  @State private var draft: StatDraft? = nil

  var body: some View {
    ScrollView {
      VStack(spacing: 6) {
        ClockStrip(game: game, model: model, clockBy: game.canTime ? nil : scoring.clockBy, onTap: onClock)
        if scoring.open != true {
          Text(scoring.hint ?? "Stats open when the match starts")
            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .padding(.top, 14)
        } else {
          if let title = scoring.title {
            Text(title).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
          }
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(game.teams) { t in tile(t) }
          }
          HStack(spacing: 6) {
            ForEach(scoring.shortcutList) { s in
              small(icon: s.icon, systemImage: nil, label: s.button) { start(s, teamId: s.teamId) }
            }
            if !scoring.moreList.isEmpty {
              small(icon: nil, systemImage: "ellipsis", label: "More") { start(nil, teamId: nil) }
            }
          }
        }
      }
      .padding(.horizontal, 2)
    }
    .sheet(item: $draft) { d in
      StatFlow(gameId: gameId, game: game, scoring: scoring, model: model, draft: d) { draft = nil }
    }
  }

  private func start(_ stat: WatchStat?, teamId: String?) {
    WKInterfaceDevice.current().play(.click)
    draft = StatDraft(stat: stat, teamId: teamId, tappedAt: Date())
  }

  /// One team: name, score and a button per scoring action ("+ Goal", or
  /// "+2" "+3" "+1"). With a single action the whole tile is the button.
  private func tile(_ t: WatchTeam) -> some View {
    let side = scoring.side(t.teamId)
    let tc = TeamColor(side?.color ?? t.color)
    let primary = scoring.primaryList
    return VStack(spacing: 2) {
      HStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 2).fill(tc.color).frame(width: 4, height: 11)
        Text(t.name)
          .font(.system(size: 12, weight: .bold, design: .rounded))
          .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
      }
      // The sport's own number when it has one (a set's points), else the score.
      Text(side?.value ?? "\(t.score)")
        .font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
      if let caption = side?.caption {
        Text(caption).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
      }
      ForEach(primary) { s in
        Button {
          start(s, teamId: t.teamId)
        } label: {
          Text(primary.count > 1 ? s.button : "+ \(s.button)")
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(tc.onColor)
            .frame(maxWidth: .infinity).frame(height: 32)
            .background(tc.color, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(s.label) for \(t.name)")
      }
    }
    .padding(6)
    .frame(maxWidth: .infinity)
    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    .contentShape(RoundedRectangle(cornerRadius: 14))
    .onTapGesture {
      if primary.count == 1, let s = primary.first { start(s, teamId: t.teamId) }
    }
  }

  private func small(icon: String?, systemImage: String?, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 2) {
        if let systemImage {
          Image(systemName: systemImage).font(.system(size: 16, weight: .bold)).frame(height: 20)
        } else {
          Text(icon ?? "•").font(.system(size: 17)).frame(height: 20)
        }
        Text(label)
          .font(.system(size: 10, weight: .bold, design: .rounded))
          .lineLimit(1).minimumScaleFactor(0.6)
      }
      .frame(maxWidth: .infinity).frame(height: 46)
      .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }
}

/// "● 67:12 · 2nd half" — read-only; tapping it goes to the Clock page when
/// this officiant runs the clock. Also keeps the period-end wrist taps coming
/// while the timekeeper is on this page.
struct ClockStrip: View {
  let game: WatchGame
  @ObservedObject var model: GameModel
  var clockBy: String?
  var onTap: (() -> Void)?

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { tl in
      strip(now: tl.date)
    }
  }

  private func strip(now: Date) -> some View {
    let clock = BoardClock.of(game, skew: model.skew, now: now)
    if game.canTime { model.remind(game, now: now, skew: model.skew) }
    return VStack(spacing: 1) {
      HStack(spacing: 5) {
        Circle()
          .fill(clock.paused ? Color.orange : game.status == "live" ? Color.green : Color.gray)
          .frame(width: 6, height: 6)
        Text(clock.text)
          .font(.system(size: 14, weight: .heavy, design: .rounded)).monospacedDigit()
          .foregroundStyle(clock.paused ? .orange : .primary)
        Text(clock.sub).font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
      }
      .padding(.horizontal, 10).frame(height: 24)
      .background(Color.white.opacity(0.1), in: Capsule())
      if let clockBy {
        Text("\(clockBy) runs the clock").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { onTap?() }
  }
}

// MARK: recording flow

/// The steps after a tap on the Score tab, in one sheet: (what) → (which
/// team) → who → (assist | who's coming on) → saved, with Undo.
struct StatFlow: View {
  let gameId: String
  let game: WatchGame
  let scoring: WatchScoring
  @ObservedObject var model: GameModel
  let draft: StatDraft
  let close: () -> Void

  enum Step: Hashable {
    case stats
    case team(WatchStat)
    case player(WatchStat, String)
    case assist(WatchStat, String, WatchPlayer)
    case subOn(WatchStat, String, WatchPlayer)
  }

  @State private var path: [Step] = []
  @State private var saved: RecordedStat? = nil

  private var first: Step {
    guard let s = draft.stat else { return .stats }
    if let t = draft.teamId { return .player(s, t) }
    return .team(s)
  }

  var body: some View {
    Group {
      if let saved {
        SavedStat(rec: saved, scoreline: scoreline, onUndo: { undo(saved) }, onDone: close)
      } else {
        NavigationStack(path: $path) {
          screen(first)
            .navigationDestination(for: Step.self) { step in screen(step) }
        }
      }
    }
    .onAppear { autoStart() }
  }

  /// The score to show on "Saved": the tiles' own numbers when the sport has
  /// them (a set's points), else the match score.
  private var scoreline: String {
    let g = model.game ?? game
    let values = g.teams.map { t in g.scoring?.side(t.teamId)?.value }
    if values.contains(where: { $0 != nil }) { return values.map { $0 ?? "–" }.joined(separator: " – ") }
    return g.scoreline
  }

  /// Nothing to ask? Then don't: a team tally for a known team is recorded
  /// straight away, and a side of one (singles) is its only player.
  private func autoStart() {
    guard saved == nil, path.isEmpty, let s = draft.stat, let t = draft.teamId else { return }
    if s.isTeam {
      recordTeam(s, teamId: t)
    } else if let only = onlyPlayer(s, t) {
      playerPicked(s, t, only)
    }
  }

  private func onlyPlayer(_ s: WatchStat, _ teamId: String) -> WatchPlayer? {
    guard !s.isSub, let list = scoring.side(teamId)?.players, list.count == 1 else { return nil }
    return list[0]
  }

  private func teamPicked(_ s: WatchStat, _ teamId: String) {
    if s.isTeam {
      recordTeam(s, teamId: teamId)
    } else if let only = onlyPlayer(s, teamId) {
      playerPicked(s, teamId, only)
    } else {
      path.append(.player(s, teamId))
    }
  }

  /// The assist question only when there's a team-mate to credit.
  private func playerPicked(_ s: WatchStat, _ teamId: String, _ p: WatchPlayer) {
    if s.assist == true, (scoring.side(teamId)?.players?.count ?? 0) > 1 {
      path.append(.assist(s, teamId, p))
    } else {
      record(s, teamId: teamId, player: p, related: nil)
    }
  }

  private func teamName(_ teamId: String) -> String { game.teams.first { $0.teamId == teamId }?.name ?? "" }
  private func teamColor(_ teamId: String) -> TeamColor {
    TeamColor(scoring.side(teamId)?.color ?? game.teams.first { $0.teamId == teamId }?.color)
  }

  @ViewBuilder private func screen(_ step: Step) -> some View {
    switch step {
    case .stats:
      List {
        ForEach(scoring.moreList) { s in
          Button {
            if let t = s.teamId { teamPicked(s, t) } else { path.append(.team(s)) }
          } label: {
            HStack(spacing: 8) {
              Text(s.icon ?? "•").frame(width: 22)
              Text(s.label).font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.8)
            }
          }
        }
      }
      .navigationTitle("What happened?")

    case .team(let s):
      ScrollView {
        VStack(spacing: 6) {
          Text(s.label).font(.footnote).foregroundStyle(.secondary)
          ForEach(game.teams) { t in
            let tc = teamColor(t.teamId)
            Button {
              teamPicked(s, t.teamId)
            } label: {
              Text(t.name)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                .foregroundStyle(tc.onColor)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(tc.color, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 2)
      }
      .navigationTitle("Which team?")

    case .player(let s, let teamId):
      let all = scoring.side(teamId)?.players ?? []
      if s.isTeam {
        // Recorded as it opens (autoStart): nothing to pick.
        ProgressView()
      } else if s.isSub {
        players(
          title: "Coming off?", caption: "\(s.label) · \(teamName(teamId))",
          list: all.filter { $0.on == true }, teamId: teamId,
          empty: "Nobody from \(teamName(teamId)) is on the pitch."
        ) { off in path.append(.subOn(s, teamId, off)) }
      } else {
        players(
          title: s.score != nil ? "Who scored?" : "Which player?", caption: "\(s.label) · \(teamName(teamId))",
          list: all, teamId: teamId,
          empty: "No players on \(teamName(teamId))'s team sheet — add them on the phone."
        ) { p in playerPicked(s, teamId, p) }
      }

    case .assist(let s, let teamId, let scorer):
      let mates = (scoring.side(teamId)?.players ?? []).filter { $0.id != scorer.id }
      List {
        Text("\(s.label) · \(playerLine(scorer))").font(.footnote).foregroundStyle(.secondary).listRowBackground(Color.clear)
        Button {
          record(s, teamId: teamId, player: scorer, related: nil)
        } label: {
          Text("No assist").font(.system(size: 15, weight: .bold, design: .rounded)).frame(maxWidth: .infinity)
        }
        ForEach(mates) { m in
          Button { record(s, teamId: teamId, player: scorer, related: m) } label: { PlayerRow(player: m, color: teamColor(teamId)) }
        }
      }
      .navigationTitle("Assist?")

    case .subOn(let s, let teamId, let off):
      players(
        title: "Coming on?", caption: "for \(playerLine(off))",
        list: scoring.side(teamId)?.bench ?? [], teamId: teamId,
        empty: "No one on \(teamName(teamId))'s bench."
      ) { on in record(s, teamId: teamId, player: on, related: off) }
    }
  }

  /// A team's players, on the pitch first (the server's order).
  private func players(title: String, caption: String, list: [WatchPlayer], teamId: String, empty: String, pick: @escaping (WatchPlayer) -> Void) -> some View {
    List {
      Text(caption).font(.footnote).foregroundStyle(.secondary).listRowBackground(Color.clear)
      if list.isEmpty {
        Text(empty).font(.footnote).foregroundStyle(.orange).listRowBackground(Color.clear)
      }
      ForEach(list) { p in
        Button { pick(p) } label: { PlayerRow(player: p, color: teamColor(teamId)) }
      }
    }
    .navigationTitle(title)
  }

  /// Queue it (stamped with the first tap), move the score, show "Saved".
  private func record(_ s: WatchStat, teamId: String, player: WatchPlayer, related: WatchPlayer?) {
    var extra: [String: String] = [
      "teamId": teamId,
      "at": ISO.frac.string(from: draft.tappedAt.addingTimeInterval(model.skew)),
    ]
    let action: String
    if s.isSub {
      action = "sub"
      extra["playerOnId"] = player.id
      extra["playerOffId"] = related?.id ?? ""
    } else {
      action = "stat"
      extra["type"] = s.type
      extra["playerId"] = player.id
      if let related { extra["relatedPlayerId"] = related.id }
    }
    // "67:12" → "67'" ("45+2:30" → "45+2'"); a count-down clock reads as it
    // stands ("4:48"); nothing when the clock isn't in minutes.
    var minute = ""
    if let g = model.game, g.status == "live" {
      let text = BoardClock.of(g, skew: model.skew, now: draft.tappedAt).text
      if g.clockDirection == "down" {
        minute = text
      } else if let colon = text.firstIndex(of: ":") {
        minute = "\(text[..<colon])'"
      }
    }
    let id = ActionQueue.shared.enqueue(gameId: gameId, action: action, extra: extra)
    model.optimisticScore(teamId: teamId, stat: s, sign: 1)
    WKInterfaceDevice.current().play(.success)
    saved = RecordedStat(actionId: id, stat: s, teamId: teamId, teamName: teamName(teamId), player: player, related: related, minute: minute)
  }

  /// A team tally (a shootout penalty): no player, no minute.
  private func recordTeam(_ s: WatchStat, teamId: String) {
    let id = ActionQueue.shared.enqueue(gameId: gameId, action: "teamStat", extra: ["type": s.type, "teamId": teamId])
    WKInterfaceDevice.current().play(.success)
    saved = RecordedStat(actionId: id, stat: s, teamId: teamId, teamName: teamName(teamId), player: nil, related: nil, minute: "")
  }

  /// Still in the queue → just take it out. Already sent (or on its way) →
  /// the server takes it back, in order, by the stat's own id.
  private func undo(_ rec: RecordedStat) {
    if !ActionQueue.shared.cancel(id: rec.actionId) {
      if rec.stat.isTeam {
        // A team tally is taken back by its own opposite.
        if let back = rec.stat.undo {
          ActionQueue.shared.enqueue(gameId: gameId, action: "teamStat", extra: ["type": back, "teamId": rec.teamId])
        }
      } else {
        ActionQueue.shared.enqueue(gameId: gameId, action: "undoStat", extra: ["ref": rec.actionId])
      }
    }
    model.optimisticScore(teamId: rec.teamId, stat: rec.stat, sign: -1)
    WKInterfaceDevice.current().play(.directionDown)
    close()
  }
}

/// Shirt number (in the team's colour) and name; dimmed when not on the pitch.
struct PlayerRow: View {
  let player: WatchPlayer
  let color: TeamColor

  var body: some View {
    HStack(spacing: 8) {
      Text(player.number.map { String($0) } ?? "–")
        .font(.system(size: 14, weight: .heavy, design: .rounded)).monospacedDigit()
        .foregroundStyle(color.onColor)
        .frame(width: 28, height: 24)
        .background(color.color, in: RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 0) {
        Text(player.name).font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
        if player.sentOff == true {
          Text("sent off").font(.system(size: 10)).foregroundStyle(.red)
        } else if player.on == false {
          Text("bench").font(.system(size: 10)).foregroundStyle(.secondary)
        }
      }
    }
    .opacity(player.on == false ? 0.7 : 1)
  }
}

/// "Saved": what was recorded, the score, and Undo for five seconds — then
/// back to the Score tab by itself.
struct SavedStat: View {
  let rec: RecordedStat
  let scoreline: String
  let onUndo: () -> Void
  let onDone: () -> Void
  @State private var progress = 0.0

  private var headline: String {
    [rec.stat.label, rec.minute].filter { !$0.isEmpty }.joined(separator: " · ")
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 3) {
        Image(systemName: "checkmark.circle.fill").font(.system(size: 30)).foregroundStyle(.green)
        Text(headline).font(.system(size: 15, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
        if rec.stat.score != nil {
          Text(scoreline).font(.system(size: 24, weight: .heavy, design: .rounded)).monospacedDigit()
        }
        Text(rec.player.map(playerLine) ?? rec.teamName)
          .font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
        if let r = rec.related {
          Text(rec.stat.isSub ? "for \(playerLine(r))" : "assist \(playerLine(r))")
            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        // (An undo of its own has nothing to take back.)
        if !rec.stat.isTeam || rec.stat.undo != nil {
          Button(action: onUndo) {
            Label("Undo", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .padding(.top, 4)
        }
        ProgressView(value: progress).tint(.gray).padding(.horizontal, 16)
      }
      .padding(.horizontal, 2)
    }
    .task {
      // Five seconds to change your mind.
      let steps = 50
      for i in 1...steps {
        try? await Task.sleep(nanoseconds: 100_000_000)
        if Task.isCancelled { return }
        progress = Double(i) / Double(steps)
      }
      onDone()
    }
  }
}

// MARK: Events tab

/// What's been recorded, newest first. Tap one, then HOLD to remove it (a
/// stray tap can't delete a goal). A scorer who doesn't run the clock leaves
/// a live match from here.
struct EventsTab: View {
  let gameId: String
  let game: WatchGame
  let scoring: WatchScoring
  @ObservedObject var model: GameModel
  var onExit: (() -> Void)?
  @ObservedObject private var queue = ActionQueue.shared
  @State private var removing: WatchMatchEvent? = nil

  var body: some View {
    let events = scoring.eventList
    let waiting = queue.count(for: gameId) - queue.clockCount(for: gameId)
    return ScrollView {
      VStack(spacing: 5) {
        HStack(alignment: .firstTextBaseline) {
          Text("Events").font(.system(size: 15, weight: .heavy, design: .rounded))
          Spacer()
          if !events.isEmpty { Text("Tap to remove").font(.system(size: 10)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 4)
        if waiting > 0 {
          Text(queue.sending ? "Sending \(waiting)…" : "\(waiting) not sent yet — no connection")
            .font(.system(size: 10)).foregroundStyle(.orange)
        }
        if events.isEmpty {
          Text("Nothing recorded yet").font(.footnote).foregroundStyle(.secondary).padding(.top, 14)
        }
        ForEach(events) { e in
          Button { removing = e } label: { row(e) }.buttonStyle(.plain)
        }
        if let onExit {
          HoldButton(label: "Exit", systemImage: "xmark", tint: .gray, seconds: 2, action: onExit).padding(.top, 8)
        }
      }
      .padding(.horizontal, 2)
    }
    .sheet(item: $removing) { e in
      RemoveEvent(event: e) {
        ActionQueue.shared.enqueue(gameId: gameId, action: "removeStat", extra: ["activityId": e.id])
        model.optimisticRemove(eventId: e.id)
        removing = nil
      }
    }
  }

  private func row(_ e: WatchMatchEvent) -> some View {
    let tc = TeamColor(e.teamId.flatMap { id in scoring.side(id)?.color ?? game.teams.first { $0.teamId == id }?.color })
    return HStack(spacing: 6) {
      RoundedRectangle(cornerRadius: 2).fill(tc.color).frame(width: 3, height: 26)
      Text(e.when ?? "").font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
        .foregroundStyle(.secondary).frame(width: 30, alignment: .leading).lineLimit(1).minimumScaleFactor(0.6)
      Text(e.icon ?? "•").font(.system(size: 14))
      VStack(alignment: .leading, spacing: 0) {
        Text(e.title).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
        if let d = e.detail {
          Text(d).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 7).frame(height: 40)
    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
  }
}

/// "Remove this?" — held, like the other things a wrist can't take back.
struct RemoveEvent: View {
  let event: WatchMatchEvent
  let onConfirm: () -> Void

  var body: some View {
    ScrollView {
      VStack(spacing: 4) {
        Text(event.icon ?? "").font(.system(size: 22))
        Text(event.title).font(.system(size: 15, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
        Text([event.detail, event.when].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
          .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        HoldButton(label: "Remove", systemImage: "trash.fill", tint: .red, action: onConfirm).padding(.top, 6)
        Text("Hold to remove").font(.system(size: 10)).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 2)
    }
  }
}
