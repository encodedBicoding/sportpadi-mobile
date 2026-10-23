import Combine
import Foundation
import SwiftUI

/// The watch's home: officiant invites (accept / decline), then the matches
/// I'm on. Opens straight onto the match the phone has in officiant mode.
struct HomeView: View {
  @EnvironmentObject private var ctx: ContextStore
  @EnvironmentObject private var router: WatchRouter
  @StateObject private var model = HomeModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    NavigationStack(path: $model.path) {
      Group {
        if ctx.needsPhoneUpdate {
          Pitch(icon: "iphone.and.arrow.forward", title: "Update SportPadi", text: "Update the app on your phone to use the watch.")
        } else if !ctx.signedIn {
          Pitch(icon: "iphone", title: "Open SportPadi on your phone", text: "Sign in there once — the watch follows.")
            .onTapGesture { ctx.askPhone() }
        } else {
          list
        }
      }
      .navigationTitle("Officiate")
      .navigationDestination(for: String.self) { gameId in GameView(gameId: gameId) }
    }
    .task { await model.load() }
    .onAppear { UsageTracker.shared.screen("/watch") }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await model.load() } }
    }
    .onChange(of: ctx.token) { _, _ in Task { await model.load() } }
    .onChange(of: ctx.currentGameId) { _, id in model.openIfNew(id) }
    .onChange(of: router.openGameId) { _, id in
      // A tapped notification: straight to that match (its invite is on the way in).
      guard let id else { return }
      router.openGameId = nil
      Task { await model.load() }
      model.path = [id]
    }
    .onAppear { model.openIfNew(ctx.currentGameId) }
  }

  @ViewBuilder private var list: some View {
    if model.loading && model.home == nil {
      ProgressView()
    } else if let err = model.error, model.home == nil {
      Pitch(icon: "wifi.slash", title: err, text: "Tap to try again").onTapGesture { Task { await model.load() } }
    } else {
      List {
        if let h = model.home, !h.invites.isEmpty {
          Section("Invites") {
            ForEach(h.invites) { inv in InviteRow(invite: inv, busy: model.responding == inv.gameId) { accept in
              Task { await model.respond(inv.gameId, accept: accept) }
            } }
          }
        }
        Section(model.home?.games.isEmpty == false ? "My matches" : "") {
          if let games = model.home?.games, !games.isEmpty {
            ForEach(games) { g in
              NavigationLink(value: g.id) { GameRow(game: g) }
            }
          } else {
            Text("No matches to officiate in the next week.")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
      }
      .refreshable { await model.load() }
    }
  }
}

@MainActor
final class HomeModel: ObservableObject {
  @Published var home: WatchHome?
  @Published var loading = false
  @Published var error: String?
  @Published var responding: String?
  @Published var path: [String] = []
  private var opened: String?

  func load() async {
    loading = true
    defer { loading = false }
    do {
      home = try await ApiClient.shared.home()
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
  }

  func respond(_ gameId: String, accept: Bool) async {
    responding = gameId
    defer { responding = nil }
    do {
      try await ApiClient.shared.respond(gameId, accept: accept)
      await load()
      if accept { path = [gameId] }
    } catch {
      self.error = error.localizedDescription
    }
  }

  /// The phone entered officiant mode on a match: follow it, once.
  func openIfNew(_ gameId: String?) {
    guard let gameId, gameId != opened else { return }
    opened = gameId
    path = [gameId]
  }
}

struct InviteRow: View {
  let invite: WatchInvite
  let busy: Bool
  let respond: (Bool) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(invite.title).font(.headline).lineLimit(2)
      if !invite.teams.isEmpty { Text(invite.teams.joined(separator: " v ")).font(.footnote) }
      Text([invite.groupName, When.line(date: invite.date, startTime: invite.startTime)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
        .font(.caption2).foregroundStyle(.secondary)
      HStack {
        Button { respond(true) } label: { Label("Accept", systemImage: "checkmark") }
          .buttonStyle(.borderedProminent).tint(.green)
        Button { respond(false) } label: { Image(systemName: "xmark") }
          .buttonStyle(.bordered)
      }
      .disabled(busy)
      .padding(.top, 2)
    }
    .padding(.vertical, 4)
  }
}

struct GameRow: View {
  let game: WatchGame
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(game.title).font(.headline).lineLimit(2)
        Spacer()
        if game.status == "live" {
          Text("LIVE").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.red.opacity(0.85), in: Capsule())
        }
      }
      Text(game.event?.title ?? "").font(.footnote).lineLimit(1)
      Text(game.status == "live" ? game.scoreline : When.line(date: game.event?.date, startTime: game.event?.startTime))
        .font(.caption2).foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }
}

struct Pitch: View {
  let icon: String
  let title: String
  let text: String
  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
      Text(title).font(.headline).multilineTextAlignment(.center)
      Text(text).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
    .padding()
  }
}
