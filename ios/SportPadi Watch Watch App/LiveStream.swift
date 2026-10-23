import Combine
import Foundation

/// The game's realtime pings (SSE at /api/mobile/games/:id/stream). Every
/// ping means "refetch the match"; `by` says who did it. Reconnects with a
/// short back-off while the view is on screen; stopped when it leaves.
@MainActor
final class LiveStream: NSObject, ObservableObject {
  @Published private(set) var lastPing: WatchPing?
  @Published private(set) var connected = false

  private var task: URLSessionDataTask?
  private var session: URLSession?
  private var buffer = Data()
  private var gameId: String?
  private var stopped = true
  private var retry: TimeInterval = 2

  func start(gameId: String) {
    stop()
    self.gameId = gameId
    stopped = false
    connect()
  }

  func stop() {
    stopped = true
    task?.cancel()
    task = nil
    session?.invalidateAndCancel()
    session = nil
    connected = false
    buffer.removeAll()
  }

  private func connect() {
    guard !stopped, let gameId, let req = try? ApiClient.shared.streamRequest(gameId) else { return }
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest = 3600
    cfg.waitsForConnectivity = true
    let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    session = s
    task = s.dataTask(with: req)
    task?.resume()
  }

  private func scheduleReconnect() {
    guard !stopped else { return }
    connected = false
    let delay = retry
    retry = min(retry * 2, 30)
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      self.connect()
    }
  }

  /// Parse complete `data: …` events out of the byte stream.
  private func drain() {
    while let range = buffer.range(of: Data("\n\n".utf8)) {
      let chunk = buffer.subdata(in: 0..<range.lowerBound)
      buffer.removeSubrange(0..<range.upperBound)
      guard let text = String(data: chunk, encoding: .utf8) else { continue }
      for line in text.split(separator: "\n") where line.hasPrefix("data:") {
        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if let d = json.data(using: .utf8), let ping = try? JSONDecoder().decode(WatchPing.self, from: d) {
          lastPing = ping
        }
      }
    }
  }
}

extension LiveStream: URLSessionDataDelegate {
  nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    let ok = (response as? HTTPURLResponse)?.statusCode == 200
    Task { @MainActor in
      self.connected = ok
      if ok { self.retry = 2 }
    }
    completionHandler(ok ? .allow : .cancel)
  }

  nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    Task { @MainActor in
      self.buffer.append(data)
      self.drain()
    }
  }

  nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    Task { @MainActor in self.scheduleReconnect() }
  }
}
