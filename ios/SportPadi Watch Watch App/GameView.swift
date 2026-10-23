import Combine
import Foundation
import SwiftUI
import WatchKit

/// One match — full officiant mode (Phase 3). Teams, score, period and a
/// clock that runs from the server's timestamps; the buttons the server says
/// are allowed right now, drawn from `actions[]` (so the watch knows nothing
/// sport-specific): pause / resume, add time, hold-to-confirm for kick-off,
/// end of period and full time, and hold-to-exit. Taps go through
/// ActionQueue (ordered, retried, idempotent). Every realtime ping refetches;
/// "Paused by Ade" when another device did it. Always-on: the clock stays
/// readable with the wrist down; the buttons hide.
struct GameView: View {
  let gameId: String
  @EnvironmentObject private var ctx: ContextStore
  @StateObject private var model = GameModel()
  @StateObject private var live = LiveStream()
  @ObservedObject private var queue = ActionQueue.shared
  @ObservedObject private var matchSession = MatchSession.shared
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.isLuminanceReduced) private var dimmed
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    content
      .navigationTitle(model.game?.event?.title ?? "Match")
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarBackButtonHidden(isLive)   // live: leave by holding Exit
      .task { await appeared() }
      .onDisappear { left() }
      .onChange(of: live.lastPing?.type) { _, _ in pinged() }
      .onChange(of: live.lastPing?.action) { _, _ in pinged() }
      .onChange(of: queue.lastResult?.serverNow) { _, _ in adoptQueueResult() }
      .onChange(of: model.game?.status) { _, status in statusChanged(status) }
      .onChange(of: scenePhase) { _, phase in phaseChanged(phase) }
      .alert("Not applied", isPresented: refusalShown) {
        Button("OK") { queue.refusal = nil }
      } message: {
        Text(queue.refusal ?? "")
      }
  }

  @ViewBuilder private var content: some View {
    if let g = model.game {
      TimelineView(.periodic(from: .now, by: dimmed ? 1 : 0.5)) { tl in
        face(g, now: tl.date)
      }
    } else if let err = model.error {
      Pitch(icon: "wifi.slash", title: err, text: "Tap to try again")
        .onTapGesture { Task { await model.load(gameId) } }
    } else {
      ProgressView()
    }
  }

  private var isLive: Bool { model.game?.status == "live" }

  private var refusalShown: Binding<Bool> {
    Binding(get: { queue.refusal != nil }, set: { shown in
      // SwiftUI calls this mid-update when the alert closes: clear it after.
      if !shown { Task { @MainActor in ActionQueue.shared.refusal = nil } }
    })
  }

  // MARK: lifecycle

  private func appeared() async {
    UsageTracker.shared.screen("/watch/games/\(gameId)")
    await model.load(gameId)
    live.start(gameId: gameId)
    ctx.tellPhoneOpen(gameId: gameId)
  }

  private func left() {
    live.stop()
    UsageTracker.shared.screen("/watch")
  }

  private func pinged() {
    let ping = live.lastPing
    Task { await model.load(gameId, ping: ping) }
  }

  private func adoptQueueResult() {
    if let g = queue.lastResult, g.id == gameId { model.adopt(g) }
  }

  // Live → keep the app frontmost for the whole match (MatchSession);
  // over → let the workout close and save.
  private func statusChanged(_ status: String?) {
    guard let g = model.game, g.canTime else { return }
    if status == "live" {
      matchSession.start(gameId: gameId, categoryName: g.category?.name)
    } else if status == "completed" || status == "abandoned", matchSession.runningGameId == gameId {
      matchSession.end()
    }
  }

  private func phaseChanged(_ phase: ScenePhase) {
    if phase == .active {
      Task { await model.load(gameId) }
      live.start(gameId: gameId)
    } else if phase == .background {
      live.stop()
    }
  }

  // MARK: face

  private func face(_ g: WatchGame, now: Date) -> some View {
    let clock = BoardClock.of(g, skew: model.skew, now: now)
    model.remind(g, now: now, skew: model.skew)
    return ScrollView {
      VStack(spacing: 6) {
        HStack(alignment: .top) {
          team(g.teams.first)
          Text(g.status == "scheduled" ? "v" : g.scoreline)
            .font(.system(size: g.status == "scheduled" ? 16 : 26, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 4)
          team(g.teams.dropFirst().first)
        }
        .opacity(dimmed ? 0.6 : 1)

        Text(clock.text)
          .font(.system(size: dimmed ? 44 : 40, weight: .heavy, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(clock.paused ? .orange : .primary)
          .padding(.top, 2)
          .privacySensitive(false)
        Text(clock.sub).font(.footnote).foregroundStyle(g.status == "live" ? Color.green : .secondary)

        if !dimmed {
          if let by = g.lastBy, let action = by.action, g.status == "live", by.userId != ctx.userId {
            Text("\(verb(action)) by \(by.name)").font(.caption2).foregroundStyle(.secondary)
          }
          if let u = g.unsupported {
            Text(u).font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.top, 4)
          } else if g.role != nil && !g.canTime && g.status != "completed" {
            Text("Scorer only — the timekeeper runs the clock").font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
          }
          controls(g)
          status
        }
      }
      .padding(.horizontal, 4)
    }
  }

  // MARK: controls

  @ViewBuilder private func controls(_ g: WatchGame) -> some View {
    let busy = queue.count(for: gameId) > 0
    VStack(spacing: 6) {
      ForEach(g.actions) { a in
        if let minutes = a.minutes {
          // "Add time": one tap per minute option.
          VStack(spacing: 4) {
            Text(a.label).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 4) {
              ForEach(minutes, id: \.self) { m in
                Button("+\(m)") { send(a.action, minutes: m) }
                  .buttonStyle(.bordered).tint(.blue)
                  .font(.system(size: 14, weight: .bold, design: .rounded))
              }
            }
          }
          .padding(.top, 4)
        } else if a.hold == true {
          HoldButton(
            label: a.label,
            systemImage: a.action == "kickoff" ? "play.fill" : "flag.fill",
            tint: a.action == "fullTime" ? .red : a.action == "kickoff" ? .green : .orange,
            disabled: busy
          ) { send(a.action) }
        } else {
          Button {
            send(a.action)
          } label: {
            Label(a.label, systemImage: icon(a.action)).frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(a.action == "pause" ? .orange : a.action == "resume" ? .green : .blue)
          .disabled(busy && a.action != "pause")   // pause always goes through; it's what a ref reaches for
        }
      }
      if g.status == "live" {
        if case .denied = matchSession.state {
          Text("To keep SportPadi on screen all match: Watch app → General → Return to Clock → SportPadi → Always.")
            .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 6)
        }
        HoldButton(label: "Exit", systemImage: "xmark", tint: .gray, seconds: 2) {
          ActionQueue.shared.clear(gameId: gameId)
          if matchSession.runningGameId == gameId { matchSession.end() }
          dismiss()
        }
        .padding(.top, 8)
      }
    }
    .padding(.top, 8)
  }

  private func send(_ action: String, minutes: Int? = nil) {
    queue.enqueue(gameId: gameId, action: action, minutes: minutes)
    // Show the tap at once: pause / resume flip locally until the server answers.
    model.optimistic(action)
  }

  @ViewBuilder private var status: some View {
    let n = queue.count(for: gameId)
    HStack(spacing: 4) {
      Circle().fill(live.connected ? Color.green : Color.gray).frame(width: 6, height: 6)
      Text(n > 0 ? (queue.sending ? "sending…" : "\(n) queued — no connection") : live.connected ? "live" : "reconnecting…")
        .font(.caption2).foregroundStyle(n > 0 && !queue.sending ? .orange : .secondary)
    }
    .padding(.top, 6)
  }

  private func team(_ t: WatchTeam?) -> some View {
    VStack(spacing: 2) {
      Circle().fill(color(t?.color)).frame(width: 14, height: 14)
      Text(t?.name ?? "TBD").font(.caption2.bold()).lineLimit(2).multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
  }

  private func color(_ hex: String?) -> Color {
    guard let hex, let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16), hex.count >= 6 else { return .gray }
    return Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
  }

  private func icon(_ a: String) -> String {
    switch a {
    case "pause": return "pause.fill"
    case "resume": return "play.fill"
    case "startNext": return "forward.fill"
    case "extraTime", "overtime": return "clock.badge.exclamationmark"
    case "penalties": return "target"
    default: return "circle"
    }
  }

  private func verb(_ a: String) -> String {
    switch a {
    case "kickoff": return "Kicked off"
    case "pause": return "Paused"
    case "resume": return "Resumed"
    case "stoppage": return "Time added"
    case "endPhase": return "Period ended"
    case "startNext": return "Period started"
    case "fullTime": return "Full time"
    default: return a.capitalized
    }
  }
}

// MARK: model

@MainActor
final class GameModel: ObservableObject {
  @Published var game: WatchGame?
  @Published var error: String?
  /// serverNow − the moment we received it: the watch's clock offset.
  @Published var skew: TimeInterval = 0
  private var remindedPhase: String?
  private var remindedOver: String?

  func load(_ gameId: String, ping: WatchPing? = nil) async {
    do {
      adopt(try await ApiClient.shared.game(gameId))
      error = nil
      // Haptics for the moments that matter when ANOTHER device did them.
      if let p = ping, let by = p.by, by.userId != ContextStore.shared.userId {
        switch (p.type, p.action, p.status) {
        case ("status", _, "live"), ("phase", _, _): WKInterfaceDevice.current().play(.start)
        case ("timer", "pause", _): WKInterfaceDevice.current().play(.stop)
        case ("status", _, "completed"): WKInterfaceDevice.current().play(.success)
        default: break
        }
      }
    } catch {
      if game == nil { self.error = error.localizedDescription }
    }
  }

  func adopt(_ g: WatchGame) {
    if let s = ISO.date(g.serverNow) { skew = s.timeIntervalSinceNow }
    game = g
  }

  /// Flip pause/resume locally so the tap shows at once; the server's view
  /// replaces it a moment later (or the queue's refusal puts it back).
  func optimistic(_ action: String) {
    guard var g = game else { return }
    let nowIso = ISO.frac.string(from: Date().addingTimeInterval(skew))
    switch action {
    case "pause":
      g.paused = true
      if g.phase != nil { g.phase?.pausedAt = nowIso } else { g.timer?.pausedAt = nowIso }
    case "resume":
      g.paused = false
      if var ph = g.phase, let p = ISO.date(ph.pausedAt) {
        ph.pausedMs += Date().addingTimeInterval(skew).timeIntervalSince(p) * 1000
        ph.pausedAt = nil
        g.phase = ph
      } else if var t = g.timer, let p = ISO.date(t.pausedAt) {
        t.pausedMs += Date().addingTimeInterval(skew).timeIntervalSince(p) * 1000
        t.pausedAt = nil
        g.timer = t
      }
    default:
      return
    }
    game = g
  }

  /// Wrist taps when the period reaches its nominal end, and again when the
  /// added time runs out — once each per period.
  func remind(_ g: WatchGame, now: Date, skew: TimeInterval) {
    guard g.status == "live", let ph = g.phase, ph.status == "live", let started = ISO.date(ph.startedAt), let nominal = ph.nominalMinutes else { return }
    var paused = ph.pausedMs / 1000
    if let p = ISO.date(ph.pausedAt) { paused += max(0, now.addingTimeInterval(skew).timeIntervalSince(p)) }
    let mins = (now.addingTimeInterval(skew).timeIntervalSince(started) - paused) / 60
    if mins >= Double(nominal), remindedPhase != ph.key {
      remindedPhase = ph.key
      WKInterfaceDevice.current().play(.notification)
    }
    if ph.stoppageMin > 0, mins >= Double(nominal + ph.stoppageMin), remindedOver != ph.key {
      remindedOver = ph.key
      WKInterfaceDevice.current().play(.notification)
    }
  }
}
