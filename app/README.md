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

89 tests, run headlessly with `fake_async`, an in-memory store, and the
deterministic fake engine — no device or GPS required.

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