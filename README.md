# sportpadi-mobile

The native Flutter client for sportpadi. It talks to the existing backend
(`sportpadi-workspace`) through an OpenAPI/REST bridge over the tRPC API, with a
generated Dart client. This repo is **Phase 0** of the migration plan: the
foundation plus a runnable "sign in and view a group" slice.

## Prerequisites

- Flutter 3.22+ / Dart 3.4+ (`flutter --version`)
- The backend running locally (`sportpadi-workspace`, default `http://localhost:3000`)

## First-time setup

The native iOS/Android shells were **not** generated here (the machine used to
scaffold this repo had no Flutter SDK). Generate them once:

```bash
flutter create . --platforms=android,ios --org com.sportpadi --project-name sportpadi_mobile
```

`flutter create` may regenerate a few authored files. This is a git repo, so
restore ours afterward:

```bash
git checkout -- pubspec.yaml analysis_options.yaml README.md .gitignore
rm -f lib/main.dart test/widget_test.dart   # we use main_dev/staging/prod.dart
flutter pub get
```

## Run

```bash
# Android emulator (10.0.2.2 = host localhost)
flutter run -t lib/main_dev.dart --dart-define=API_BASE_URL=http://10.0.2.2:3000

# iOS simulator
flutter run -t lib/main_dev.dart --dart-define=API_BASE_URL=http://localhost:3000
```

Or with the Makefile: `make run` / `make run-ios`.

## Flavors

Phase 0 uses lightweight entrypoint flavors — `lib/main_dev.dart`,
`main_staging.dart`, `main_prod.dart` — each bootstraps a different `AppConfig`.
The API base URL is overridable with `--dart-define=API_BASE_URL=...`. True
native flavors (separate bundle IDs, icons) come later.

## Layout

```
lib/
  core/       env & flavors, theme, router, dio + interceptors, secure storage
  data/       repositories + models (auth, groups); generated API client -> data/api/generated
  features/   auth, groups, splash  (screens + Riverpod controllers)
  shared/     reusable widgets & formatters
  main_*.dart flavor entrypoints
```

## API client codegen

See `openapi/README.md`. Once the backend emits `openapi.json`, drop it in
`openapi/`, run `make api-client`, and swap the hand-written repositories for
the generated client.

## Backend (Phase 0 — done)

Both live in `sportpadi-workspace`:

- **Bearer auth** — the Better Auth `bearer()` plugin is enabled, so sign-in /
  sign-up return a `set-auth-token` header and `Authorization: Bearer <token>`
  authenticates every request.
- **REST bridge** — `GET /api/mobile/groups` and `GET /api/mobile/groups/:id`
  (`apps/web/src/app/api/mobile/`) reuse the tRPC procedures `groups.mineDetailed`
  and `groups.get` through a request-scoped caller, so auth and entitlement
  checks are identical to the web app.

## Next: auto-generated OpenAPI client

The Phase 0 REST endpoints are hand-wired over the tRPC caller. The productised
path is `trpc-to-openapi`: add it to the backend, tag the exposed procedures
with `.meta({ openapi })` + Zod output schemas, emit `openapi.json`, and swap the
hand-written repositories for the generated Dart client (see `openapi/README.md`).
