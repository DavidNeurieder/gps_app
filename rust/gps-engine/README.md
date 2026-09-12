# gps-engine

A standalone, platform-independent Rust engine for:

```
GPS data → Track → cleaned Track → Route → Attempts → Performance → Ghost
```

It powers route matching and "you vs your previous self" ghost racing for
running and cycling. The crate has **no** Flutter, SQLite, network, or mobile
bindings: it is a pure, deterministic, synchronous library plus a small CLI.

## Run

```
cargo test
cargo run --example analyze
cargo doc --no-deps
```

Everything can be exercised on Linux without a phone, GPS chip, or internet
connection.

## Module map

| Module      | Responsibility                                              |
|-------------|-------------------------------------------------------------|
| `units`     | `Distance`, `Duration`, `Speed`, `Timestamp` newtypes       |
| `geo`       | distance, bearing, interpolation, polyline, projection      |
| `track`     | `TrackPoint` / `Track` model, validation, statistics        |
| `track`     | processing: filter / simplify / resample-by-distance       |
| `route`     | canonical `Route` model + projection to the distance axis   |
| `route`     | pairwise matching: structured `MatchScore` diagnostics      |
| `route`     | discovery: cluster recordings into routes (`RouteCatalog`)  |
| `route`     | canonicalization: one robust `Route` from a cluster         |
| `gpx`       | GPX → `Track` adapter (RFC 3339 times, Garmin speed ext)    |
| `synthetic` | deterministic synthetic GPS generation for tests            |
| `error`     | typed errors                                                |

Planned (later phases): `attempt` (progress + performance), `ghost`.
Matching currently exposes individual metrics (start/end distance, length
ratio, spatial overlap, direction) rather than one magic score — the
provisional `overall_score` is documented as tunable against a labeled corpus.

## Fixtures

Small hand-written GPX files live in `testdata/gpx/` and are loaded by
[`tests/gpx.rs`](tests/gpx.rs). External datasets are out of scope for the
repository; see `scripts/` in later phases for downloading real material.