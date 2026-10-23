import Combine
import Foundation
import WatchConnectivity

/// The pairing context the phone sends (docs/design/watch-officiant.md
/// "Pairing"): API base URL, bearer token, who the user is, the match open in
/// officiant mode on the phone. Read from WatchConnectivity's application
/// context — delivered live when both are awake, and waiting in
/// `receivedApplicationContext` otherwise — and kept in UserDefaults so the
/// watch works from cold without the phone nearby.
///
/// The watch never signs in itself. No token = "Open SportPadi on your phone".
@MainActor
final class ContextStore: NSObject, ObservableObject {
  static let shared = ContextStore()

  @Published private(set) var apiBaseUrl: URL?
  @Published private(set) var token: String?
  @Published private(set) var userId: String?
  @Published private(set) var userName: String?
  @Published private(set) var deviceId: String?
  @Published private(set) var currentGameId: String?
  @Published private(set) var contextVersion: Int = 0
  @Published private(set) var phoneReachable = false

  /// The phone app is newer than this watch build understands.
  static let supportedContextVersion = 1
  var needsPhoneUpdate: Bool { contextVersion > Self.supportedContextVersion }
  var signedIn: Bool { token != nil && apiBaseUrl != nil }

  private let defaults = UserDefaults.standard
  private let key = "sp.context"

  private override init() {
    super.init()
    if let saved = defaults.dictionary(forKey: key) { apply(saved) }
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  /// The watch woke without a context (or the token went stale): ask the phone.
  func askPhone() {
    guard WCSession.isSupported() else { return }
    let s = WCSession.default
    // Whatever the phone last pushed, even while it was away.
    if !s.receivedApplicationContext.isEmpty { apply(s.receivedApplicationContext) }
    guard s.isReachable else { return }
    s.sendMessage(["type": "needsContext"], replyHandler: { [weak self] reply in
      Task { @MainActor in self?.apply(reply) }
    }, errorHandler: { _ in })
  }

  /// A match tapped here opens on the phone too (when it's reachable).
  func tellPhoneOpen(gameId: String) {
    guard WCSession.isSupported(), WCSession.default.isReachable else { return }
    WCSession.default.sendMessage(["type": "openGame", "gameId": gameId], replyHandler: nil, errorHandler: nil)
  }

  /// The server answered 401: the token is gone. Forget it and ask again.
  func tokenRejected() {
    token = nil
    persist()
    askPhone()
  }

  private func apply(_ ctx: [String: Any]) {
    contextVersion = ctx["version"] as? Int ?? 0
    apiBaseUrl = (ctx["apiBaseUrl"] as? String).flatMap(URL.init(string:))
    token = (ctx["signedIn"] as? Bool ?? true) ? ctx["token"] as? String : nil
    userId = ctx["userId"] as? String
    userName = ctx["userName"] as? String
    deviceId = ctx["deviceId"] as? String
    currentGameId = ctx["currentGameId"] as? String
    persist()
  }

  private func persist() {
    var d: [String: Any] = ["version": contextVersion]
    if let apiBaseUrl { d["apiBaseUrl"] = apiBaseUrl.absoluteString }
    if let token { d["token"] = token }
    if let userId { d["userId"] = userId }
    if let userName { d["userName"] = userName }
    if let deviceId { d["deviceId"] = deviceId }
    if let currentGameId { d["currentGameId"] = currentGameId }
    defaults.set(d, forKey: key)
  }
}

extension ContextStore: WCSessionDelegate {
  nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    let ctx = session.receivedApplicationContext
    let reachable = session.isReachable
    Task { @MainActor in
      if !ctx.isEmpty { self.apply(ctx) }
      self.phoneReachable = reachable
      if !self.signedIn { self.askPhone() }
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    Task { @MainActor in self.apply(applicationContext) }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    Task { @MainActor in
      self.phoneReachable = reachable
      if reachable && !self.signedIn { self.askPhone() }
    }
  }
}
