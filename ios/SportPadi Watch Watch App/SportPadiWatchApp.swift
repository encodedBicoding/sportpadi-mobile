import Combine
import Foundation
import SwiftUI
import UserNotifications
import WatchKit

/// SportPadi Watch — officiant mode on the wrist (docs/design/
/// watch-officiant.md). Phase 2: invites and a live match face. The watch
/// never signs in: it takes the session from the paired iPhone app
/// (ContextStore) and calls the same API the phone does.
@main
struct SportPadiWatchApp: App {
  @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
  @StateObject private var ctx = ContextStore.shared
  @StateObject private var router = WatchRouter.shared
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      HomeView()
        .environmentObject(ctx)
        .environmentObject(router)
        .onAppear { UsageTracker.shared.start() }
        // Owner console → Usage: sessions and foreground time on the watch.
        .onChange(of: scenePhase) { _, phase in UsageTracker.shared.scenePhase(phase) }
    }
  }
}

/// Where a tapped notification sends us.
@MainActor
final class WatchRouter: ObservableObject {
  static let shared = WatchRouter()
  @Published var openGameId: String?
}

/// Push: the phone's notifications are mirrored here by iOS. The officiant
/// invite carries `gameId` (and `watch: "/watch/games/<id>"`); tapping it
/// opens that match's invite. Nothing to register — mirroring is automatic
/// while the phone app has notification permission.
final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
  func applicationDidFinishLaunching() {
    UNUserNotificationCenter.current().delegate = self
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    let info = response.notification.request.content.userInfo
    // The server puts its `data` object top-level in the FCM payload on iOS.
    let gameId = (info["gameId"] as? String) ?? (info["data"] as? [String: Any])?["gameId"] as? String
    if let gameId {
      await MainActor.run {
        WatchRouter.shared.openGameId = gameId
        ContextStore.shared.askPhone()
      }
    }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }
}
