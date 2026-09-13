//! A standalone GPS engine for track processing, route matching, and ghost
//! racing.
//!
//! The crate is intentionally pure and deterministic: the same input always
//! produces the same output, with no platform, network, or database
//! dependencies.
//!
//! The conceptual pipeline is:
//!
//! ```text
//! GPX → Track → process (filter / simplify / resample) → Route
//!     → Attempt → Performance → Ghost
//! ```
//!
//! Currently implemented: domain value types ([`units`]), the [`geo`]
//! primitives, the [`track`] model with construction-time validation and
//! processing, GPX input ([`gpx`]), synthetic generation ([`synthetic`]),
//! the [`route`] model with matching/discovery/canonicalization, the
//! [`attempt`] representation (GPS → route distance → elapsed time), and
//! race analysis ([`ghost`]).

#![forbid(unsafe_code)]
#![warn(missing_docs)]
#![warn(rust_2018_idioms)]

/// Typed errors produced by the engine.
pub mod error;

/// Geographic primitives: coordinates, distance, bearing, interpolation,
/// polylines, and projection.
pub mod geo;

/// GPS activity model: [`TrackPoint`] and validated [`Track`], plus track
/// statistics and processing (filtering, simplification, resampling).
pub mod track;

/// GPX track input: adapter from GPX XML documents to validated [`Track`]s.
pub mod gpx;

/// Canonical polyline routes with a stable distance axis.
pub mod route;

/// A recording reduced to the route axis: distance ↔ elapsed time, plus
/// pointwise performance comparison between two attempts.
pub mod attempt;

/// Race a live attempt against a reference (PB) attempt.
pub mod ghost;

/// Synthetic GPS generation: deterministic test tracks from clean routes.
pub mod synthetic;

/// Standard processing pipeline and labeled-corpus evaluation (§33/§38–40).
pub mod evaluate;

/// Domain value types: [`Distance`], [`Duration`], [`Speed`], [`Timestamp`].
pub mod units;

pub use attempt::{
    Attempt, AttemptError, AttemptSample,
    performance::{
        ComparisonConfig, ComparisonPoint, PerformanceComparison, compare as compare_performances,
    },
};
pub use error::{GeoError, GpxError, RouteError, TrackError, TrackField};
pub use evaluate::{ConfusionMatrix, LabeledPair, evaluate, parse_manifest, standard_pipeline};
pub use geo::{Bearing, Coordinate, PolylineBounds, Projection};
pub use ghost::{Ghost, GhostState};
pub use gpx::{parse_gpx, read_gpx, read_gpx_file, write_gpx, write_gpx_file};
pub use route::{
    CanonicalError, CanonicalizeConfig, DiscoveredRoute, MatchConfig, MatchScore, Route,
    RouteCatalog, RoutePoint, TrackAddition, canonicalize, compare, compare_either_direction,
    compare_with,
};
pub use track::{
    FilterConfig, MovingConfig, ProcessingReport, SimplifyConfig, Track, TrackPoint, filter,
    resample_by_distance, simplify,
};
pub use units::{Distance, Duration, Speed, Timestamp};
