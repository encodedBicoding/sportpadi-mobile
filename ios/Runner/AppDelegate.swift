import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Kept for plugins that only learn about the launch AFTER it happened
  /// (see didInitializeImplicitFlutterEngine).
  private var launchOptions: [UIApplication.LaunchOptionsKey: Any]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    self.launchOptions = launchOptions
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // iOS push fix (UIScene lifecycle).
    //
    // With the scene-based lifecycle, plugins are registered HERE — after the
    // app has finished launching. firebase_messaging (15.x) does all of its
    // iOS setup in an observer of UIApplicationDidFinishLaunchingNotification
    // that it adds when it is registered: hooking the app delegate for the
    // APNs callbacks, becoming the UNUserNotificationCenter delegate, and
    // calling registerForRemoteNotifications(). Registered late, it never sees
    // that notification, so none of it happens: no APNs token, so no FCM
    // token, so no push on iOS at all (Android is unaffected).
    //
    // Hand the plugin the launch it missed — only this plugin, directly, with
    // the real launch options — instead of re-posting the system notification
    // to every observer in the process. pubspec pins firebase_messaging to
    // ^15; when moving to a version that supports scenes itself, delete this
    // block (running its launch setup twice would double-register it).
    let selector = NSSelectorFromString("application_onDidFinishLaunchingNotification:")
    if let messaging = engineBridge.pluginRegistry.valuePublished(
      byPlugin: "FLTFirebaseMessagingPlugin"),
      messaging.responds(to: selector)
    {
      let launch = Notification(
        name: UIApplication.didFinishLaunchingNotification,
        object: UIApplication.shared,
        userInfo: launchOptions.map { opts in
          Dictionary(uniqueKeysWithValues: opts.map { ($0.key.rawValue as AnyHashable, $0.value) })
        })
      messaging.perform(selector, with: launch)
    } else {
      // Plugin API changed (a future version that supports scenes natively):
      // at minimum make sure APNs registration happens.
      UIApplication.shared.registerForRemoteNotifications()
    }
  }
}
