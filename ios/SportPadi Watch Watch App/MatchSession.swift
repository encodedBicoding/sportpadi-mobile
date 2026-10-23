import Combine
import Foundation
import HealthKit
import WatchKit

/// Keeps SportPadi on the wrist for the whole match.
///
/// watchOS returns to the clock face after two minutes without a touch, so a
/// referee who hasn't needed a button for a while raises their wrist to see
/// the time of day. Apps with an ACTIVE WORKOUT SESSION are exempt: the watch
/// stays on them, wrist-raise always comes back to the app, and always-on
/// behaves like the built-in Workout app. A referee covering kilometres a
/// match is a workout, so that's what this is: a session that starts at
/// kick-off (or when a live match is opened) and ends at full time or Exit.
/// Side effect the ref may like: the match lands in Fitness as a workout.
///
/// Needs the HealthKit capability on the watch target and
/// NSHealthShareUsageDescription / NSHealthUpdateUsageDescription in its
/// Info.plist. If the user declines the permission, nothing breaks — the app
/// just falls back to the two-minute rule, and GameView shows a hint about
/// Settings → General → Return to Clock.
@MainActor
final class MatchSession: NSObject, ObservableObject {
  static let shared = MatchSession()

  enum State { case off, running(gameId: String), denied }
  @Published private(set) var state: State = .off

  private let store = HKHealthStore()
  private var session: HKWorkoutSession?
  private var builder: HKLiveWorkoutBuilder?

  var isRunning: Bool { if case .running = state { return true } else { return false } }
  var runningGameId: String? { if case .running(let id) = state { return id } else { return nil } }

  /// Start (idempotent per match). `categoryName` picks the activity type.
  func start(gameId: String, categoryName: String?) {
    guard HKHealthStore.isHealthDataAvailable() else { return }
    if runningGameId == gameId { return }
    if isRunning { end() }
    Task { await begin(gameId: gameId, categoryName: categoryName) }
  }

  private func begin(gameId: String, categoryName: String?) async {
    let types: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.heartRate)]
    do {
      try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: types)
    } catch {
      state = .denied
      return
    }
    // Sharing workouts is the one we need; "notDetermined"/"denied" → fall back.
    guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
      state = .denied
      return
    }
    let cfg = HKWorkoutConfiguration()
    cfg.activityType = Self.activity(for: categoryName)
    cfg.locationType = .outdoor
    do {
      let s = try HKWorkoutSession(healthStore: store, configuration: cfg)
      let b = s.associatedWorkoutBuilder()
      b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: cfg)
      s.delegate = self
      session = s
      builder = b
      s.startActivity(with: Date())
      try await b.beginCollection(at: Date())
      state = .running(gameId: gameId)
    } catch {
      state = .off
      session = nil
      builder = nil
    }
  }

  /// Full time / Exit: close the session and save the workout.
  func end() {
    guard let s = session else { state = .off; return }
    s.end()
    let b = builder
    session = nil
    builder = nil
    state = .off
    Task {
      try? await b?.endCollection(at: Date())
      _ = try? await b?.finishWorkout()
    }
  }

  /// The match's sport → a HealthKit activity, `.other` when unsure.
  static func activity(for category: String?) -> HKWorkoutActivityType {
    let c = (category ?? "").lowercased()
    if c.contains("soccer") || c.contains("football") && !c.contains("american") { return .soccer }
    if c.contains("basketball") { return .basketball }
    if c.contains("volleyball") { return .volleyball }
    if c.contains("rugby") { return .rugby }
    if c.contains("hockey") { return .hockey }
    if c.contains("cricket") { return .cricket }
    if c.contains("tennis") { return .tennis }
    if c.contains("badminton") { return .badminton }
    if c.contains("handball") { return .handball }
    if c.contains("american") { return .americanFootball }
    return .other
  }
}

extension MatchSession: HKWorkoutSessionDelegate {
  nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
    // The system can end it (e.g. the user ends it from the Workout app's
    // controls); mirror that so a new kick-off starts a fresh one.
    if toState == .ended {
      Task { @MainActor in
        self.session = nil
        self.builder = nil
        self.state = .off
      }
    }
  }

  nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
    Task { @MainActor in
      self.session = nil
      self.builder = nil
      self.state = .off
    }
  }
}
