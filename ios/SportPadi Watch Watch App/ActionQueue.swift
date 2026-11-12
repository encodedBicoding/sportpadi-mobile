import Combine
import Foundation
import WatchKit

/// Clock actions — and, in scorer mode, stats — from the wrist, in order, whatever the link is doing
/// (docs/design/watch-officiant.md "Act"). Each action gets a client id when
/// it's tapped, is saved to disk at once, and is sent one at a time in the
/// order tapped; a send that fails on the network is retried with back-off,
/// and the id makes a retry a no-op server-side — so a full time is never
/// lost and never applied twice. A server "no" (400/403: the action isn't
/// valid any more) drops that action and tells the officiant.
@MainActor
final class ActionQueue: ObservableObject {
  static let shared = ActionQueue()

  struct Pending: Codable, Identifiable {
    var id: String
    var gameId: String
    var action: String
    var minutes: Int?
    /// Scorer mode: the stat's fields (type, teamId, playerId, at …).
    var extra: [String: String]?
    var createdAt: Date
    var attempts: Int = 0

    /// Stats don't hold the clock's buttons back; clock actions do.
    var isClock: Bool { !["stat", "sub", "teamStat", "undoStat", "removeStat"].contains(action) }
  }

  @Published private(set) var pending: [Pending] = []
  @Published private(set) var sending = false
  /// The last thing the server refused, for a moment on screen.
  @Published var refusal: String?
  /// The fresh match view after a successful send (GameView adopts it).
  @Published var lastResult: WatchGame?

  private let key = "sp.actionQueue"
  private var retryTask: Task<Void, Never>?

  private init() {
    if let d = UserDefaults.standard.data(forKey: key), let p = try? JSONDecoder().decode([Pending].self, from: d) {
      pending = p
    }
    if !pending.isEmpty { kick() }
  }

  func count(for gameId: String) -> Int { pending.filter { $0.gameId == gameId }.count }
  /// Clock actions still to send (what makes the clock's buttons wait).
  func clockCount(for gameId: String) -> Int { pending.filter { $0.gameId == gameId && $0.isClock }.count }

  /// Tap → queued → sent. Returns the action id.
  @discardableResult
  func enqueue(gameId: String, action: String, minutes: Int? = nil, extra: [String: String]? = nil) -> String {
    let p = Pending(id: UUID().uuidString.lowercased(), gameId: gameId, action: action, minutes: minutes, extra: extra, createdAt: Date())
    pending.append(p)
    persist()
    kick()
    return p.id
  }

  /// Undo before it was sent: take it back out of the queue. False when it
  /// is already on its way (or gone) — then the server has to undo it.
  func cancel(id: String) -> Bool {
    guard let i = pending.firstIndex(where: { $0.id == id }) else { return false }
    if i == 0 && sending { return false }
    pending.remove(at: i)
    persist()
    return true
  }

  /// Drop everything queued for a match (hold-to-exit after a long outage).
  func clear(gameId: String) {
    pending.removeAll { $0.gameId == gameId }
    persist()
  }

  private func persist() {
    UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: key)
  }

  private func kick() {
    guard retryTask == nil else { return }
    retryTask = Task { await drain() }
  }

  private func drain() async {
    defer { retryTask = nil }
    while let next = pending.first {
      sending = true
      do {
        let g = try await ApiClient.shared.act(next.gameId, action: next.action, minutes: next.minutes, extra: next.extra ?? [:], actionId: next.id)
        if pending.first?.id == next.id { pending.removeFirst() }
        persist()
        lastResult = g
        WKInterfaceDevice.current().play(.click)
      } catch ApiError.server(let m) {
        // The server understood and said no: this one is gone, say why.
        if pending.first?.id == next.id { pending.removeFirst() }
        persist()
        refusal = m
        WKInterfaceDevice.current().play(.failure)
      } catch ApiError.unauthorized, ApiError.notPaired {
        // No session: keep the queue, wait for the phone.
        sending = false
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        continue
      } catch {
        // Network: back off (2, 4, 8 … 30 s) and try the same one again.
        var attempts = 1
        if pending.first?.id == next.id {
          pending[0].attempts += 1
          attempts = pending[0].attempts
        }
        persist()
        sending = false
        let delay = min(30, pow(2, Double(min(attempts, 5))))
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        continue
      }
    }
    sending = false
  }
}
