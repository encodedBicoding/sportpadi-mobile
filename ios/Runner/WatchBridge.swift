import Flutter
import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Smartwatch pairing — iOS half (docs/design/watch-officiant.md "Pairing").
///
/// The phone hands the watch everything it needs to call the API as this
/// user: WatchConnectivity's *application context* is a "latest value wins"
/// dictionary the watch can read whenever it wakes, even if it was off when
/// the phone sent it. Dart (lib/core/watch/watch_bridge.dart) sends the whole
/// context on every change over the `sportpadi/watch` method channel; this
/// class forwards it, and relays the watch's few messages back:
///
///   watch → phone  { "type": "needsContext" }            → Dart re-sends
///                  { "type": "openGame", "gameId": … }   → Dart opens it
///
/// No paired watch, or WatchConnectivity unsupported: every call is a no-op.
final class WatchBridge: NSObject {
  private let channel: FlutterMethodChannel
  private var lastContext: [String: Any] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "sportpadi/watch", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    #if canImport(WatchConnectivity)
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
    #endif
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "updateContext":
      guard let ctx = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "context must be a map", details: nil))
        return
      }
      lastContext = ctx
      send(ctx)
      result(nil)
    case "isPaired":
      #if canImport(WatchConnectivity)
      result(WCSession.isSupported() && WCSession.default.isPaired && WCSession.default.isWatchAppInstalled)
      #else
      result(false)
      #endif
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func send(_ ctx: [String: Any]) {
    #if canImport(WatchConnectivity)
    guard WCSession.isSupported() else { return }
    let s = WCSession.default
    guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
    // Application context must be plist-safe: drop nulls, keep strings/numbers/bools.
    let clean = ctx.compactMapValues { v -> Any? in
      if v is NSNull { return nil }
      return v
    }
    do {
      try s.updateApplicationContext(clean)
    } catch {
      NSLog("[watch] updateApplicationContext failed: \(error.localizedDescription)")
    }
    #endif
  }
}

#if canImport(WatchConnectivity)
extension WatchBridge: WCSessionDelegate {
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    if let error { NSLog("[watch] activation failed: \(error.localizedDescription)") }
    // Just activated: push whatever we last had so a freshly paired watch
    // doesn't wait for the next change.
    if activationState == .activated, !lastContext.isEmpty { send(lastContext) }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    // Switching to another paired watch: re-activate for the new one.
    session.activate()
  }

  func sessionWatchStateDidChange(_ session: WCSession) {
    if session.isPaired, session.isWatchAppInstalled, !lastContext.isEmpty { send(lastContext) }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    DispatchQueue.main.async {
      self.channel.invokeMethod("reachability", arguments: ["reachable": session.isReachable])
    }
  }

  /// Watch → phone, no reply expected.
  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    relay(message)
  }

  /// Watch → phone, reply expected: answer "needsContext" with the context itself.
  func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    if message["type"] as? String == "needsContext" {
      replyHandler(lastContext)
      // And ask Dart for a fresh one in case the token moved on.
      DispatchQueue.main.async { self.channel.invokeMethod("needsContext", arguments: nil) }
      return
    }
    relay(message)
    replyHandler(["ok": true])
  }

  private func relay(_ message: [String: Any]) {
    guard let type = message["type"] as? String else { return }
    DispatchQueue.main.async {
      switch type {
      case "needsContext":
        self.channel.invokeMethod("needsContext", arguments: nil)
      case "openGame":
        self.channel.invokeMethod("openGame", arguments: ["gameId": message["gameId"] as? String ?? ""])
      default:
        break
      }
    }
  }
}
#endif
