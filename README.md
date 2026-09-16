# gps_app

A GPS run/cycling app built around one idea: **every route is a race with your
own personal best.** You run against a "ghost" of your PB, and the live gap —
AHEAD or BEHIND — is the hero metric of the whole experience.

```
Flutter app  →  EngineService (facade)  →  Rust engine (FFI)
                                   ↘  FakeEngineService (deterministic, for dev)
```

## Features

- **Record runs** — a state machine driving `preparing → GPS acquiring →
  ready → running ⇄ paused → finishing → completed`, with live distance, pace,
  elapsed time and the PB gap.
- **Ghost racing** — every route carries a PB; run against its ghost live on
  the map, and finish the run to see where you were faster or slower.
- **Route map** — self-contained painter (no map SDK): the route, the travelled
  portion, the YOU and PB-ghost markers, a follow camera with recenter.
- **Route library** — course cards with PB/average/last stats, a performance
  chart of every attempt, and attempt history.
- **Results & history** — run-complete interstitial with NEW PERSONAL BEST
  detection, a splits breakdown, activity detail, and home history.
- **Background recording** — wall-clock timing and persisted run snapshots, so
  an interrupted run survives process death and resumes where it left off.
- **Polish** — phase transitions, haptics, WCAG-AA contrast and semantics
  labels, error/empty/loading states, and repaint isolation.

## Repository layout

| Path                     | What it is                                              |
|--------------------------|---------------------------------------------------------|
| `app/`                   | The Flutter client (`lib/`, `test/`)                    |
| `rust/gps-engine/`       | The Rust engine: GPX → track → route → ghost pipeline   |
| `specification/`         | Plans: app implementation, UI/UX, engine, datasets      |
| `Cargo.toml`             | Cargo workspace root for the Rust crate                 |

The app consumes the engine only through the `EngineService` abstraction, so
it never talks to raw FFI. Swap `FakeEngineService` for `RustEngineService` at
build time without touching UI code.

## Getting started

```bash
# Flutter client
cd app
flutter pub get
flutter run

# Rust engine
cargo test
cargo run --example analyze
```

CI (`/.github/workflows/ci.yml`) runs `cargo fmt --check`, `cargo clippy -D
warnings`, `cargo test --all-features`, `cargo doc --no-deps`, Flutter's
`flutter analyze` + `flutter test`, and the on-device E2E suite on a headless
Android emulator (`flutter test integration_test`).

## Using the real Rust engine

The app defaults to the deterministic `FakeEngineService` (also used in
tests). To build against the native FFI engine instead:

```bash
flutter run --dart-define=USE_RUST_ENGINE=true
flutter run --dart-define=USE_RUST_ENGINE=true \
            --dart-define=GPS_ENGINE_LIB=/path/to/libgps_engine.so
```

The library is built as a `cdylib` by the `gps-engine` crate for this purpose.

## Tests

```bash
cd app && flutter analyze && flutter test   # Flutter: 153 tests
cargo test                                   # Rust: 178 tests + property cases
```

The Flutter tests run headlessly with `fake_async`, an in-memory store, and
the deterministic fake engine — no phone, GPS chip, or network needed.

## Status

Milestones M1–M14 are implemented (see [CHANGELOG.md](CHANGELOG.md)). The demo
ships with a seeded catalog and a deterministic fake GPS timeline (the ~4.8 km
"River Loop"), so the whole loop is explorable on any device or in tests.

## License

`MIT OR Apache-2.0` (engine workspace); the Flutter app is private to this
repository (`publish_to: none`).