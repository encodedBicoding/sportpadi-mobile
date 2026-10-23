import Combine
import Foundation
import SwiftUI

/// Owner console → Usage, for the watch (the same first-party analytics the
/// web and phone send: packages/api/src/analytics/ingest.ts). So the owner
/// can see whether anyone actually uses the watch app: sessions, foreground
/// time and the screens opened, per device, tied to the account.
///
///  • device   — this watch's own id (not the phone's), kept in UserDefaults
///  • session  — from foreground; a new one after 30 minutes away
///  • time     — foreground time only
///  • screens  — "/watch", "/watch/games/<id>", reported when left
///
/// Batches go to POST /api/t every 30 s while open and when the app goes to
/// the background, with the phone's bearer token (so the server knows the
/// user and the platform — the User-Agent says "watchos"). Never throws.
@MainActor
final class UsageTracker: ObservableObject {
  static let shared = UsageTracker()

  private let sessionGap: TimeInterval = 30 * 60
  private var sessionId = UUID().uuidString.lowercased()
  private var sessionStart = Date()
  private var backgroundSince: Date?
  private var foregroundSince: Date? = Date()
  private var activeMs = 0
  private var page: (path: String, at: Date, ms: Int)?
  private var queue: [[String: Any]] = []
  private var timer: Timer?

  private var deviceId: String {
    if let d = UserDefaults.standard.string(forKey: "sp.watchDeviceId") { return d }
    let d = "w" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    UserDefaults.standard.set(d, forKey: "sp.watchDeviceId")
    return d
  }

  func start() {
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.flush() }
    }
  }

  /// A screen came on: close the one before it.
  func screen(_ path: String) {
    if page?.path == path { return }
    accrue()
    closePage()
    page = (path, Date(), 0)
  }

  func scenePhase(_ phase: ScenePhase) {
    switch phase {
    case .active:
      let away = backgroundSince
      backgroundSince = nil
      foregroundSince = Date()
      if let away, Date().timeIntervalSince(away) > sessionGap {
        sessionId = UUID().uuidString.lowercased()
        sessionStart = Date()
        if var p = page { p.at = Date(); p.ms = 0; page = p }
      }
    case .background, .inactive:
      guard backgroundSince == nil, phase == .background else { return }
      accrue()
      foregroundSince = nil
      backgroundSince = Date()
      let current = page?.path
      closePage()
      if let current { page = (current, Date(), 0) }
      Task { await flush() }
    @unknown default:
      break
    }
  }

  /// Milliseconds since 1970 as Int64. Apple Watch hardware is arm64_32:
  /// `Int` is 32-bit there (max ~2.1 billion) and today's epoch-ms is ~1.8
  /// trillion — `Int(...)` would trap. The simulator is 64-bit, so it hid this.
  static func epochMs(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970 * 1000) }

  private func accrue() {
    guard let since = foregroundSince else { return }
    let ms = Int(min(max(0, Date().timeIntervalSince(since)), 15 * 60) * 1000)   // capped before converting (32-bit Int)
    foregroundSince = Date()
    activeMs += ms
    if var p = page { p.ms += ms; page = p }
  }

  private func closePage() {
    guard let p = page else { return }
    queue.append(["kind": "page", "path": p.path, "at": Self.epochMs(p.at), "ms": p.ms])
    if queue.count > 60 { queue.removeFirst(queue.count - 60) }
    page = nil
  }

  private func flush() async {
    accrue()
    guard !queue.isEmpty || activeMs >= 1000 else { return }
    let ctx = ContextStore.shared
    guard let base = ctx.apiBaseUrl, let token = ctx.token else { return }
    let events = queue
    queue.removeAll()
    let active = activeMs
    activeMs = 0
    var body: [String: Any] = [
      "deviceId": deviceId,
      "sessionId": sessionId,
      "startedAt": Self.epochMs(sessionStart),
      "activeMs": active,
      "tz": TimeZone.current.identifier,
      "lang": Locale.current.identifier,
      "events": events,
    ]
    if let p = page { body["current"] = p.path }
    var r = URLRequest(url: base.appendingPathComponent("/api/t"))
    r.httpMethod = "POST"
    r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    r.setValue(ApiClient.userAgent, forHTTPHeaderField: "User-Agent")
    r.httpBody = try? JSONSerialization.data(withJSONObject: body)
    _ = try? await URLSession.shared.data(for: r)   // offline: dropped, like the phone
  }
}
