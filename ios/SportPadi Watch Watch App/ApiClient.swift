import Foundation

enum ApiError: LocalizedError {
  case notPaired
  case unauthorized
  case server(String)
  case network

  var errorDescription: String? {
    switch self {
    case .notPaired: return "Open SportPadi on your phone"
    case .unauthorized: return "Signed out — open SportPadi on your phone"
    case .server(let m): return m
    case .network: return "No connection"
    }
  }
}

/// The watch's HTTP client: the same REST facade the phone uses, with the
/// phone's bearer token (docs/design/watch-officiant.md).
@MainActor
final class ApiClient {
  static let shared = ApiClient()
  private let ctx = ContextStore.shared
  private let session: URLSession = {
    let c = URLSessionConfiguration.default
    c.timeoutIntervalForRequest = 15
    c.waitsForConnectivity = true
    return URLSession(configuration: c)
  }()

  private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest {
    guard let base = ctx.apiBaseUrl, let token = ctx.token else { throw ApiError.notPaired }
    var r = URLRequest(url: base.appendingPathComponent(path))
    r.httpMethod = method
    r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    r.setValue("application/json", forHTTPHeaderField: "Accept")
    r.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    if let deviceId = ctx.deviceId { r.setValue(deviceId, forHTTPHeaderField: "x-sp-device") }
    if let body {
      r.setValue("application/json", forHTTPHeaderField: "Content-Type")
      r.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    return r
  }

  /// "SportPadiWatch/1.0 (watchos 11.1)" — the server reads the platform off it.
  static let userAgent: String = {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    let os = ProcessInfo.processInfo.operatingSystemVersion
    return "SportPadiWatch/\(v) (watchos \(os.majorVersion).\(os.minorVersion))"
  }()

  private func send<T: Decodable>(_ r: URLRequest, as: T.Type) async throws -> T {
    let (data, resp): (Data, URLResponse)
    do {
      (data, resp) = try await session.data(for: r)
    } catch {
      throw ApiError.network
    }
    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
    if code == 401 {
      ctx.tokenRejected()
      throw ApiError.unauthorized
    }
    if code >= 400 {
      let m = (try? JSONDecoder().decode(ApiMessage.self, from: data))?.message ?? "Something went wrong"
      throw ApiError.server(m)
    }
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw ApiError.server("Unexpected reply")
    }
  }

  func home() async throws -> WatchHome {
    try await send(try request("/api/mobile/watch"), as: WatchHome.self)
  }

  func game(_ id: String) async throws -> WatchGame {
    try await send(try request("/api/mobile/watch/\(id)"), as: WatchGame.self)
  }

  /// Accept / decline an officiant invite.
  func respond(_ gameId: String, accept: Bool) async throws {
    struct R: Decodable { var status: String }
    _ = try await send(try request("/api/mobile/watch/\(gameId)", method: "POST", body: ["action": accept ? "accept" : "decline"]), as: R.self)
  }

  /// A clock action (Phase 3 uses it; the id makes a retry a no-op).
  func act(_ gameId: String, action: String, minutes: Int? = nil, actionId: String = UUID().uuidString) async throws -> WatchGame {
    var body: [String: Any] = ["action": action, "actionId": actionId]
    if let minutes { body["minutes"] = minutes }
    return try await send(try request("/api/mobile/watch/\(gameId)", method: "POST", body: body), as: WatchGame.self)
  }

  /// The game's SSE stream URL + headers, for LiveStream.
  func streamRequest(_ gameId: String) throws -> URLRequest {
    var r = try request("/api/mobile/games/\(gameId)/stream")
    r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    r.timeoutInterval = 3600
    return r
  }
}
