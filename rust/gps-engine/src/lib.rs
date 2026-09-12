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
//! processing, GPX input ([`gpx`]), synthetic generation ([`synthetic`]), and
//! the [`route`] model with projection.

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

/// Synthetic GPS generation: deterministic test tracks from clean routes.
pub mod synthetic;

/// Domain value types: [`Distance`], [`Duration`], [`Speed`], [`Timestamp`].
pub mod units;

pub use error::{GeoError, GpxError, RouteError, TrackError, TrackField};
pub use geo::{Bearing, Coordinate, Projection};
pub use gpx::{parse_gpx, read_gpx, read_gpx_file};
pub use route::{MatchConfig, MatchScore, Route, RoutePoint, compare, compare_with};
pub use track::{
    FilterConfig, MovingConfig, ProcessingReport, SimplifyConfig, Track, TrackPoint, filter,
    resample_by_distance, simplify,
};
pub use units::{Distance, Duration, Speed, Timestamp};
