import Combine
import Foundation
import WatchKit

/// Clock actions from the wrist, in order, whatever the link is doing
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
    var createdAt: Date
    var attempts: Int = 0
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

  /// Tap → queued → sent. Returns the action id.
  @discardableResult
  func enqueue(gameId: String, action: String, minutes: Int? = nil) -> String {
    let p = Pending(id: UUID().uuidString.lowercased(), gameId: gameId, action: action, minutes: minutes, createdAt: Date())
    pending.append(p)
    persist()
    kick()
    return p.id
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
        let g = try await ApiClient.shared.act(next.gameId, action: next.action, minutes: next.minutes, actionId: next.id)
        pending.removeFirst()
        persist()
        lastResult = g
        WKInterfaceDevice.current().play(.click)
      } catch ApiError.server(let m) {
        // The server understood and said no: this one is gone, say why.
        pending.removeFirst()
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
        pending[0].attempts += 1
        persist()
        sending = false
        let delay = min(30, pow(2, Double(min(pending[0].attempts, 5))))
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        continue
      }
    }
    sending = false
  }
}
