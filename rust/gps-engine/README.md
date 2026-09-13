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
cargo run --release --example bench -- --tracks 200
cargo run --example generate_corpus
cargo doc --no-deps
```

The `bench` example (§34) generates a deterministic synthetic corpus and times
projection, processing, discovery and the pairwise matching matrix. The
`generate_corpus` example (§33) writes the synthetic GPX corpus under
`testdata/synthetic/`.

Everything can be exercised on Linux without a phone, GPS chip, or internet
connection.

## CLI

A companion binary ships with the library:

```
cargo run --bin gps-engine -- inspect  testdata/unit/noisy_loop.gpx
cargo run --bin gps-engine -- process  testdata/synthetic/clean.gpx
cargo run --bin gps-engine -- compare  a.gpx b.gpx
cargo run --bin gps-engine -- discover ./tracks/
cargo run --bin gps-engine -- benchmark ./tracks/
```

`inspect`/`process` summarize a track; `compare` prints the structured
`MatchScore` metrics plus a SAME/DIFFERENT classification; `discover` clusters
tracks into routes; `benchmark` times discovery and the pairwise matrix
(§34/§36 of the crate plan). Only the benchmark reads the wall clock.

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
| `attempt`   | GPS → route distance → elapsed time (`time_at`, `distance_at`) |
| `attempt`   | performance comparison: pointwise `ComparisonPoint`s        |
| `ghost`     | PB-vs-live duel: `GhostState { distance, difference, ahead }` |
| `gpx`       | GPX ↔ `Track` adapter (RFC 3339 times, Garmin speed ext)   |
| `synthetic` | deterministic synthetic GPS generation for tests            |
| `error`     | typed errors                                                |

Planned (later phases): FFI bindings for Flutter.
Matching currently exposes individual metrics (start/end distance, length
ratio, spatial overlap, direction) rather than one magic score — the
provisional `overall_score` is documented as tunable against a labeled corpus.

## Fixtures (§33)

Three categories, deliberately never mixed:

- `testdata/unit/` — tiny hand-written GPX fixtures (loaded by
  [`tests/gpx.rs`](tests/gpx.rs)).
- `testdata/synthetic/` — generated from a known loop by
  `examples/generate_corpus.rs` (clean/noisy/sparse/gapped/stopped/outliers/
  reversed/detour) and round-tripped by `tests/roundtrip.rs`.
- `testdata/real/` — your own recordings; `testdata/real/*.gpx` is git-ignored.
  External datasets are for the FFI milestone.