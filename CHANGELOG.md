# Changelog

All notable changes to `gps_app` (Flutter client + `gps-engine` Rust crate) are
documented here, grouped by the implementation milestones in
`specification/app_implementation_plan.txt`.

---

## [Unreleased]

- **Test expansion** (per `ideas/test_plan.txt`) — Flutter suite grows from 89
  to 152 tests, closing behavioural gaps:
  - `test/state_machine_test.dart` — invalid transitions are strict no-ops
    (pause/finish before running, resume while running, double-pause,
    double-finish, second `beginRun`, `ensureSession`, resume-after-completion),
    GPS quality reduced→good through acquisition, distance/pace invariants at
    the loop seam.
  - `test/pause_resume_test.dart` — paused time never counts toward moving time
    or distance (multi-pause, immediate-pause, 1-second run, resume/immediate
    finish).
  - `test/persistence_recovery_test.dart` — snapshot cleared on finish,
    stale/unknown `routeId` resumes safely on river-loop geometry, headless
    runs clamp at `polylineMeters(riverLoop)`, malformed/missing/null snapshot
    documents degrade to `null`, corrupt history falls back to seeds.
  - `test/geometry_invariants_test.dart` — haversine symmetry/non-negativity/
    known reference (1° ≈ 111.19 km)/antimeridian/poles ≈ π·R; polyline
    monotonicity; `pointAlongPolyline` boundaries.
- `test/splits_boundary_test.dart` — 0.999/1.000/1.001 km thresholds,
    margin-beating the PB flips every delta negative, per-split pacing honesty.
- **UI state coverage** (`test/ui_state_test.dart`, plan Phase 11) — what the
  record flow *shows* at every phase: START disabled + hourglass while
  acquiring, controls flipping running→PAUSE / paused→RESUME, completed showing
  neither pause nor finish, and rapid pause/resume switching converging on a
  coherent state.
- **Failure injection** (`test/failure_injection_test.dart`, plan Phase 13) —
  a dead storage backend and failing route matching must degrade safely. Fixes
  landed in `persistence/` and the controller:
  - storage reads/writes are best-effort (`_readBestEffort` /
    `_writeBestEffort`): a failed disk write no longer surfaces as an unhandled
    async exception from snapshots, finishes, or dismissals; the in-memory
    repositories stay authoritative.
  - repository `build()`s also catch `TypeError` (valid JSON, wrong shape), so
    malformed-but-parseable documents fall back to seeds instead of exploding.
  - `_persistCompletedRun` catches the whole persist pipeline (including a
    failing engine `matchRoutes` on headless finishes) and re-emits the
    completed summary with `hasUnsavedData` set rather than crashing.
- **Integration tests** — on-device E2E suite (`integration_test/app_test.dart`):
  full run journey (Home → START → pause/resume → finish → result → history)
  and route-library browsing, running against the real app on an
  emulator/device with the deterministic fake engine. Verified green on an
  Android 16 (x86_64) emulator.
- **Android emulator runner** — `app/tool/android_integration_test.sh` boots a
  headless AVD (default `test_phone`) and runs the suite against it; CI gained
  a `flutter analyze`/`flutter test` job and an `android-integration-test` job
  (`reactivecircus/android-emulator-runner`).
- Cross-platform device testing against real GPS.

---

## 2026-09-14

### M14 — Polish

- **Animations** — record-flow phases crossfade and slide between pre-run /
  live / complete; the PAUSED overlay fades in and out; the PB gap color flips
  crossfade instead of snapping; the run-complete headline springs in
  (`easeOutBack`).
- **Haptics** — tactile feedback on START, PAUSE/RESUME, FINISH, VIEW RESULT,
  DONE, and route/activity card taps.
- **Accessibility** — spoken semantic labels for the PB gap and map markers
  (decorative text excluded); raised muted-text contrast to WCAG-AA on both
  surfaces; theme-scaled text on the START button, GPS pill, and map label.
- **Error handling** — engine/preparation failures surface as a real error
  state (previously never emitted) with a `Try again` recovery path.
- **Empty & loading states** — inline empty hints on Home for no activities /
  no routes; an hourglass GPS cue while acquiring a fix.
- **Battery & performance** — `RepaintBoundary` isolates the live map layer so
  2 Hz tick repaints don't bleed into the rest of the UI.

### M13 — Background recording

- Wall-clock (drift-free) elapsed timing via `package:clock`, so throttled or
  suspended background timers can't inflate pace.
- `WidgetsBindingObserver` lifecycle forwarding on `GpsApp`; backgrounding
  snapshots the run immediately, foregrounding resyncs the clock.
- Interrupted-run recovery: `RunSnapshot` (status, started-at, moving time,
  distance, loop, route) is persisted and resumed on next launch.
- Tests: `test/lifecycle_test.dart` (snapshot round-trip, throttled snapshots,
  lifecycle snapshot, resume/dismiss semantics, end-to-end backgrounding).

### M12 — Route library

- Routes tab with course cards (silhouette, runs count, PB) and route detail:
  static map, PB / Average / Last stats, a performance bar chart with a dashed
  PB baseline, and attempt history (`Today` / `Yesterday` / date labels).
- `computeRouteStats` merges seeded counters with real attempt history.
- Tests: `test/route_stats_test.dart`, `test/route_library_test.dart`.

### M11 — Results

- Run-complete interstitial with `NEW PERSONAL BEST` detection, VIEW RESULT
  and DONE actions.
- Result screen with per-km splits — cumulative deltas against the PB — plus
  activity detail from Home history.
- Split logic in `features/result/application/splits.dart`.
- Tests: `test/splits_test.dart`, extended `recording_flow_test.dart`.

### M10 — Persistence

- Repository layer over a pluggable store: `JsonFileStore` (device),
  `MemoryPersistenceStore` (tests), `NoopPersistenceStore` (default).
- Finished runs saved as activities; routes and history loaded reactively.
- Activity icons link to their detail screen from Home.

---

## 2026-09-13

### M9 — Rust integration

- `RustEngineService` FFI bridge over the `gps-engine` crate (`cdylib`).
- `EngineService` abstraction consumed everywhere; build-time switch via
  `--dart-define=USE_RUST_ENGINE=true` and `GPS_ENGINE_LIB`.
- Ghost preparation, route matching, and recording generation work with either
  engine behind the same facade.

### M8 — Map

- Self-contained `RouteMap` painter: route trace, travelled portion, YOU and
  PB-ghost markers, follow camera, pan, and a `Recenter` button.

### M7 — Live run UI

- Live screen: distance, moving time, pace, the hero PB gap, pause/resume and
  finish controls, plus a GPS-quality pill.

### M6 — Recording state machine

- `RecordingController` (Riverpod `Notifier`) implementing
  `preparing → gpsAcquiring → ready → running ⇄ paused → finishing → completed`.

### M5 — Home

- Greeting, "Start a run" primary action, route cards and recent activities.

### M2–M4 — Foundations

- **M4** — deterministic `FakeEngineService` (seeded, reproducible tracks) so
  the UI is fully buildable without the real engine.
- **M3** — local domain models: `Route`, `Activity`, `Attempt`, `Ghost`,
  `GhostState`, `LiveRunState`, `RunStatus`, plus `Distance`/`Elapsed`/`Speed`.
- **M2** — design system: semantic colors (AHEAD/BEHIND/PB/GPS WARNING),
  typography, spacing, cards/buttons, and the `PerformanceGap` component.

### M1 — Shell

- App root, theme, shell navigation (Home / Record / Routes), go_router
  routing, and Riverpod dependency injection.

---

## 2026-09-12 … 2026-09-13 — Rust engine (`gps-engine` v0.1)

Work on the standalone engine that later powers the app (M9):

- **GPX input & matching** — GPX ↔ Track adapter (RFC 3339 times, Garmin speed
  extension), pairwise route matching with structured `MatchScore`
  diagnostics.
- **Route discovery & canonicalization** — cluster recordings into routes and
  derive one robust canonical route per cluster.
- **Performance & ghost** — GPS → route distance → elapsed-time projection
  (`time_at`/`distance_at`), pointwise `ComparisonPoint`s, and the PB-vs-live
  `GhostState` duel.
- **CLI** — `inspect`, `process`, `compare`, `discover`, `evaluate`,
  `benchmark`.
- **Quality** — property-based testing (`proptest`), a synthetic labeled
  corpus (`testdata/synthetic/` + `manifest.json`), an `evaluate` example that
  reports the confusion matrix (precision 1.000, recall 0.778 at defaults), a
  benchmark harness, GPX robustness tests (parser never panics), and 178
  passing tests.