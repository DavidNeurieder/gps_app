# app — Flutter client

The Flutter client for `gps_app`. See the repository root
[`README.md`](../README.md) for the full picture.

## Run

```bash
flutter pub get
flutter run
```

## Tests & analysis

```bash
flutter analyze
flutter test
```

89 headless tests run with `fake_async`, an in-memory store, and the
deterministic fake engine — no device or GPS required.

## On-device integration tests

`integration_test/app_test.dart` drives the real app end to end on an
emulator/device (real clock, real timers): record a run (Home → READY → START
→ pause/resume → FINISH → result → DONE → history) and browse the route
library.

```bash
flutter test integration_test -d <device>
```

## Real engine

By default the app uses the deterministic `FakeEngineService`. To talk to the
Rust engine over FFI:

```bash
flutter run --dart-define=USE_RUST_ENGINE=true \
            --dart-define=GPS_ENGINE_LIB=/path/to/libgps_engine.so
```

## Layout

- `lib/app/` — root widget, router, shell tabs, dependency injection.
- `lib/features/` — feature folders: `home`, `recording`, `result`, `routes`,
  `activity` (each `presentation/` + `application/`).
- `lib/core/` — theme and units.
- `lib/engine/` — `EngineService` facade, fake + Rust FFI implementations.
- `lib/persistence/` — stores and repositories.
- `lib/widgets/` — shared components (`performance_gap`, `route_map`,
  `route_silhouette`).