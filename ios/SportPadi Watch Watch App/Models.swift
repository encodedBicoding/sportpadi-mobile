import Foundation

// The watch API's shapes — docs/design/watch-officiant.md. Decoded loosely
// (every field optional where the server may omit it) so a server change
// never crashes the watch.

struct WatchHome: Decodable {
  var invites: [WatchInvite] = []
  var games: [WatchGame] = []
  var serverNow: String?
}

struct WatchInvite: Decodable, Identifiable {
  var gameId: String
  var eventId: String?
  var title: String
  var groupName: String?
  var date: String?
  var startTime: String?
  var locationName: String?
  var teams: [String] = []
  var id: String { gameId }
}

struct WatchTeam: Decodable, Identifiable {
  var teamId: String
  var name: String
  var color: String?
  var score: Int
  var id: String { teamId }
}

struct WatchEvent: Decodable {
  var id: String
  var title: String
  var date: String?
  var startTime: String?
  var locationName: String?
  var timezone: String?
  var groupId: String?
  var groupName: String?
}

struct WatchPhase: Decodable {
  var key: String
  var label: String
  var kind: String
  var status: String
  var nominalMinutes: Int?
  var nominalOffset: Int
  var startedAt: String?
  var endedAt: String?
  var pausedAt: String?
  var pausedMs: Double
  var stoppageMin: Int
  var index: Int
  var of: Int
}

struct WatchTimer: Decodable {
  var pausedAt: String?
  var pausedMs: Double
  var stoppageMin: Int
  var durationMinutes: Int?
}

struct WatchBy: Decodable {
  var userId: String?
  var name: String
  var action: String?
  var at: String?
}

struct WatchAction: Decodable, Identifiable {
  var action: String
  var label: String
  var hold: Bool?
  var minutes: [Int]?
  var id: String { action }
}

struct WatchCategory: Decodable {
  var name: String
  var emoji: String?
}

struct WatchGame: Decodable, Identifiable {
  var id: String
  var status: String
  var event: WatchEvent?
  var category: WatchCategory?
  var teams: [WatchTeam] = []
  var role: String?
  var canTime: Bool = false
  var unsupported: String?
  var serverNow: String?
  var startedAt: String?
  var endedAt: String?
  var phase: WatchPhase?
  var timer: WatchTimer?
  var paused: Bool = false
  var lastBy: WatchBy?
  var actions: [WatchAction] = []

  var title: String { teams.map(\.name).joined(separator: " v ") }
  var scoreline: String { teams.map { String($0.score) }.joined(separator: " – ") }
}

/// A realtime ping on the game's SSE stream.
struct WatchPing: Decodable {
  var type: String
  var action: String?
  var status: String?
  var by: WatchBy?
}

/// Server error body `{ message, code }`.
struct ApiMessage: Decodable {
  var message: String
  var code: String?
}

// ISO-8601 with fractional seconds (the server's `toISOString`).
enum ISO {
  static let frac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()
  static let plain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()
  static func date(_ s: String?) -> Date? {
    guard let s else { return nil }
    return frac.date(from: s) ?? plain.date(from: s)
  }
}
