# SportPadi Watch (Wear OS) — Phase 4

Officiant mode on a Wear OS wrist, the same thing as the watchOS app (`ios/SportPadiWatch/`):
invites (accept / decline), a live match face whose clock runs from the server's timestamps and
follows every change made on any other device, and the clock controls drawn from the server's
`actions[]` with hold-to-confirm, an ordered offline queue, ambient mode and period-end taps.
Strictly the clock — stats, subs and formations stay on the phone.
Contract: `../../docs/design/watch-officiant.md` (workspace repo). Phone side of pairing:
`android/app/src/main/kotlin/.../WatchBridge.kt`.

This is a Gradle module, `:wear`, inside the Flutter project's `android/` build.

## Wire it in (once)

1. `android/settings.gradle.kts`: add `include(":wear")` after `include(":app")`, and the Compose
   compiler plugin to the `plugins {}` block:
   `id("org.jetbrains.kotlin.plugin.compose") version "2.4.0" apply false`
2. **Same applicationId and signing as the phone app** — both are set here to match `:app`
   (`com.sportpadi.app`, `key.properties`). Without that the Data Layer never pairs. The Wear
   APK's `versionCode` is offset (+20 000 000) so Play accepts both on one listing.
3. Icon: a placeholder vector is in `res/drawable/ic_launcher.xml`; replace it with the designed one (round, 48 dp).
4. Build: `cd android && ./gradlew :wear:assembleRelease` (Flutter's own commands only build
   `:app`). Upload the Wear APK/AAB to the **Wear OS** form factor of the same Play listing.
5. Version: `-PwearVersionCode=N -PwearVersionName=1.0.0` on the Gradle command, or set them in
   `gradle.properties`.

## How it works

- `ContextStore` — the session from the phone: Data Layer item `/sportpadi/context` (via
  `DataLayerService`, which wakes even when the app isn't running), kept in SharedPreferences.
  No token → "Open SportPadi on your phone". A 401 → forgets the token and asks the phone.
- `ApiClient` (OkHttp) — `GET /api/mobile/watch`, `GET/POST /api/mobile/watch/:gameId`, with the
  phone's bearer token, `x-sp-device`, `User-Agent: SportPadiWatch/<v> (wearos …)`.
- `LiveStream` — the match's SSE pings; any ping refetches; `by` → "Paused by Ade"; haptics on
  kick-off / pause / period / full time done elsewhere.
- `BoardClock` — the board clock from timestamps + skew (never from a countdown).
- `ActionQueue` — every tap saved with a client id, sent in order; network failures back off
  (2…30 s) and retry the same id; a 400/403 drops that one and shows why. Survives relaunch.
- `MainActivity` — `AmbientLifecycleObserver`: wrist down → the clock only, dimmed, instead of
  the watch face; wrist up → the full face. Deep link `sportpadi://sportpadi.com/watch/games/<id>`.
- `OngoingMatch` — an Ongoing Activity while live: the match on the watch face / ongoing slot,
  one tap back in. (Wear's answer to the iOS workout session.)
- `HomeScreen` / `GameScreen` / `HoldButton` — the screens.

## Notifications

Android mirrors the phone's notifications to the watch; tapping a mirrored invite opens the
**phone** app (that's how bridging works). The invite is waiting on the watch's home screen when
the user opens SportPadi there. A watch-native push (the watch registering its own FCM token)
would double up with the bridged copy, so it's deliberately not done.

## Test checklist (real hardware)

- [ ] Phone signed in → watch shows Officiate home; sign out → "Open SportPadi on your phone".
- [ ] Invite a watch wearer from the web; mirrored notification lands; open SportPadi on the watch → Accept → match opens.
- [ ] Kick off from the phone → watch clock starts; pause from the web → watch clock stops within ~2 s, "Paused by <name>".
- [ ] Hold Kick off on the watch → web goes live; Pause / +2 / Resume from the watch → web follows.
- [ ] Airplane mode, tap Pause, +1, Resume, back online → all three land once, in order.
- [ ] Wrist down → ambient clock only; wrist up → full face. Screen off after a few minutes → the ongoing chip on the watch face reopens the match.
- [ ] Hold End 1st half; hold Start 2nd half from the WEB → the wrist taps.
- [ ] Battery after a full 90 + stoppage — note the % drop.
