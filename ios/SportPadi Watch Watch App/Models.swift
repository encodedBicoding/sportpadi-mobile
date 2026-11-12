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
  /// Sent back with the action (a timeout's team).
  var arg: String?
  var id: String { "\(action):\(arg ?? "")" }
}

struct WatchCategory: Decodable {
  var name: String
  var emoji: String?
}

// ── Scorer mode (docs/design/watch-officiant.md "Scoring") ──────────────────
// Everything here is optional: a server from before scorer mode simply
// doesn't send it, and the watch stays a clock.

/// What a stat does to the score, for instant feedback on the wrist.
struct WatchStatScore: Decodable, Hashable {
  var team: String      // "own" | "opponent"
  var points: Int
}

/// One thing a scorer can record ("goal", "yellow_card", a substitution…).
struct WatchStat: Decodable, Identifiable, Hashable {
  var type: String
  var label: String
  var short: String?
  var icon: String?
  var assist: Bool?
  var kind: String?
  var score: WatchStatScore?
  /// The team it can only be for right now (skips "Which team?").
  var teamId: String?
  /// "team" stats: the type that takes it back (Undo).
  var undo: String?
  var id: String { type }
  var isSub: Bool { kind == "sub" }
  /// A team tally with no player (a shootout penalty …).
  var isTeam: Bool { kind == "team" }
  var button: String { short ?? label }
}

struct WatchPlayer: Decodable, Identifiable, Hashable {
  var id: String
  var name: String
  var number: Int?
  var on: Bool?
  var sentOff: Bool?
}

/// One team's people: in the match (on the pitch first) and able to come on.
struct WatchSide: Decodable, Identifiable {
  var teamId: String
  var color: String?
  /// What the tile shows big when it isn't the match score (the current
  /// set's points, penalties scored); and a line under it ("Sets 1").
  var value: String?
  var caption: String?
  var players: [WatchPlayer]?
  var bench: [WatchPlayer]?
  var id: String { teamId }
}

/// A recorded event, already worded by the server.
struct WatchMatchEvent: Decodable, Identifiable {
  var id: String
  var type: String?
  var icon: String?
  var teamId: String?
  var when: String?
  var title: String
  var detail: String?
}

struct WatchScoring: Decodable {
  var open: Bool?
  var hint: String?
  /// A line over the tiles when the sport has one ("Set 2 · to 25", "Penalties").
  var title: String?
  var primary: [WatchStat]?
  var shortcuts: [WatchStat]?
  var more: [WatchStat]?
  var teams: [WatchSide]?
  var events: [WatchMatchEvent]?
  var clockBy: String?

  var primaryList: [WatchStat] { primary ?? [] }
  var shortcutList: [WatchStat] { shortcuts ?? [] }
  var moreList: [WatchStat] { more ?? [] }
  var eventList: [WatchMatchEvent] { events ?? [] }
  func side(_ teamId: String) -> WatchSide? { teams?.first { $0.teamId == teamId } }
}

struct WatchGame: Decodable, Identifiable {
  var id: String
  var status: String
  var event: WatchEvent?
  var category: WatchCategory?
  var teams: [WatchTeam] = []
  var role: String?
  var canTime: Bool = false
  var canScore: Bool?
  var scoring: WatchScoring?
  /// "down" = show the time LEFT in the period (basketball quarters).
  var clockDirection: String?
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
