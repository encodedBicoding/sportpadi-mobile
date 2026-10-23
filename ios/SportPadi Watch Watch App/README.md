# SportPadi Watch (watchOS) — Phases 2 + 3

Officiant mode on the wrist: the invite list (accept / decline), a live match face whose
clock runs from the server's timestamps and follows every change made on any other device,
and the clock controls — kick-off, pause / resume, add time, end of period, start next,
extra time / penalties / overtime when drawn, full time — with hold-to-confirm, an ordered
offline queue, always-on display and period-end taps. Strictly the clock: stats, subs and
formations stay on the phone. Contract: `../../docs/design/watch-officiant.md` (workspace
repo). Phone side of pairing: `ios/Runner/WatchBridge.swift`.

The sources in this folder are the whole app. Xcode has to own the target, so add it once:

## Add the watch target (once, in Xcode)

1. Open `ios/Runner.xcworkspace`. **File → New → Target → watchOS → App.**
   - Product name: `SportPadi Watch` · Interface: SwiftUI · Language: Swift
   - **Bundle identifier must be `com.sportpadi.app.watchkitapp`** (the phone's id + `.watchkitapp`)
   - Team: the same as Runner (R2MDSB8B8T) · "Watch App for Existing iOS App" → Runner
   - Untick "Include Notification Scene" and tests.
2. Xcode creates a folder `SportPadi Watch/` with `SportPadi_WatchApp.swift`, `ContentView.swift`,
   `Assets.xcassets`. **Delete the two Swift files** and drag in every `.swift` file from this
   folder (copy items, target: SportPadi Watch). Keep Xcode's `Assets.xcassets`; put an app icon in it.
3. Replace the target's generated `Info.plist` keys with the ones in `Info.plist` here
   (`WKCompanionAppBundleIdentifier = com.sportpadi.app` is what pairs it with Runner).
4. Target settings: Deployment target **watchOS 10.0**; Signing & Capabilities → add
   **HealthKit** (MatchSession: the workout session that keeps the app frontmost all match;
   tick nothing under it) and **Background Modes → Workout processing**. Push Notifications is
   optional (mirroring works without it).
5. Runner target → General → "Frameworks, Libraries, and Embedded Content" should now list
   `SportPadi Watch.app` (Xcode adds the "Embed Watch Content" phase itself). If it didn't,
   add it there.
6. Build the **Runner** scheme to a phone + paired watch. The Flutter tool keeps working:
   `flutter build ipa` builds the embedded watch app too.

Nothing in `pubspec.yaml`, CocoaPods or the Flutter side changes.

## How it works

- `ContextStore` — the session from the phone (WatchConnectivity application context), kept
  in UserDefaults so the watch works from cold. No token → "Open SportPadi on your phone".
  A 401 → forgets the token and asks the phone again.
- `ApiClient` — `GET /api/mobile/watch`, `GET/POST /api/mobile/watch/:gameId`, with the phone's
  bearer token, `x-sp-device`, and `User-Agent: SportPadiWatch/<v> (watchos …)`.
- `LiveStream` — the match's SSE pings; any ping refetches; `by` → "Paused by Ade"; haptic on
  kick-off / pause / period / full time done elsewhere.
- `Clock` — the board clock from timestamps + skew (never from a countdown).
- `ActionQueue` — every tap is saved to disk with a client id and sent in order; network
  failures back off (2…30 s) and retry the SAME id (a no-op if it already landed); a server
  "no" (400/403) drops that one and shows why. Survives relaunch.
- `HoldButton` — press-and-hold (1.5 s; Exit 2 s) with a filling bar and haptics, for anything
  that can't be undone on a wrist.
- `MatchSession` — an HKWorkoutSession from kick-off (or opening a live match) to full time /
  Exit. Apps with an active workout session are exempt from watchOS's 2-minute "Return to
  Clock", so wrist-raise always comes back to the match. The sport is mapped from the
  category (soccer, basketball, …, else `other`); the match lands in Fitness as a workout.
  Permission declined → the 2-minute rule applies and the face shows the settings hint.
- `HomeView` / `GameView` — the two screens. GameView draws its buttons from the server's
  `actions[]`, flips pause/resume optimistically, hides the back button while live (hold Exit
  instead), dims to clock-only when the wrist drops (always-on), and taps the wrist when the
  period reaches its nominal end and again when added time runs out. The phone entering officiant mode on a match
  (`currentGameId`) pushes that match here; a tapped match tells the phone to open it.
- Push: iOS mirrors the phone's notifications; the invite's `gameId` deep-links into the match.

## Test checklist (real hardware)

- [ ] Phone signed in → watch shows Officiate home within a few seconds; sign out → "Open SportPadi on your phone".
- [ ] Invite a watch wearer to officiate from the web; notification lands on the wrist; tap → the invite row; Accept → the match opens.
- [ ] Kick off from the phone → watch clock starts; pause from the web → watch clock stops within ~2 s and says "Paused by <name>".
- [ ] Walk out of Bluetooth range of the phone with Wi-Fi/LTE on: clock keeps running; pings keep arriving.
- [ ] Airplane mode on the watch: clock keeps running from timestamps; "reconnecting…" shows; back online → catches up.
- [ ] Lock the phone in a bag for 10 minutes: watch still works (it has its own token).
- [ ] Phase 3: hold Kick off → match goes live on web within ~2 s; tap Pause → web pauses; +2 → "+2" on web.
- [ ] Phase 3: airplane mode, tap Pause, +1, Resume, then back online → all three land, in that order, once (web timeline shows one of each).
- [ ] Phase 3: hold End 1st half; web shows HT; hold Start 2nd half from the WEB → watch follows with a tap on the wrist.
- [ ] Phase 3: a drawn match at full time offers Extra time / Penalties only if the match plays them.
- [ ] Phase 3: wrist down mid-match → clock still readable, buttons gone; wrist up → back.
- [ ] Workout: first kick-off asks for Health permission; allow → wrist down for 5 minutes mid-match, raise → SportPadi, not the clock face; Fitness shows a Soccer workout afterwards.
- [ ] Workout: decline → the hint about Return to Clock shows under the buttons; everything else still works.
- [ ] Phase 3: battery after a full 90 + stoppage with the screen waking normally — note the % drop.
