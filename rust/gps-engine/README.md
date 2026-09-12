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

| Module    | Responsibility                                          |
|-----------|---------------------------------------------------------|
| `units`   | `Distance`, `Duration`, `Speed`, `Timestamp` newtypes   |
| `geo`     | distance, bearing, interpolation, polyline, projection  |
| `track`   | `TrackPoint` / `Track` model + validation               |
| `error`   | typed errors                                            |

Planned (later phases): `track` processing (filter/simplify/resample), `route`
+ matching, `attempt`, `ghost`, and `formats::gpx`.