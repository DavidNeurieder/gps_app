//! Typed errors for the engine.
//!
//! Constructors validate their input and return explicit errors; the engine
//! never panics on malformed data.

use std::fmt;

use thiserror::Error;

/// The optional fields of a [`crate::TrackPoint`] that refer to a numeric
/// observation, used to report which value failed validation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrackField {
    /// Altitude in meters.
    Altitude,
    /// GPS-reported speed in meters per second.
    Speed,
    /// Horizontal accuracy in meters.
    Accuracy,
}

impl fmt::Display for TrackField {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TrackField::Altitude => write!(f, "altitude"),
            TrackField::Speed => write!(f, "speed"),
            TrackField::Accuracy => write!(f, "accuracy"),
        }
    }
}

/// Errors produced by geographic primitives.
#[derive(Debug, Clone, PartialEq, Error)]
pub enum GeoError {
    /// Latitude outside `[-90, 90]`.
    #[error("latitude {0} is out of range [-90, 90]")]
    LatitudeOutOfRange(f64),
    /// Longitude outside `[-180, 180]`.
    #[error("longitude {0} is out of range [-180, 180]")]
    LongitudeOutOfRange(f64),
    /// A value that must be finite is NaN or infinite.
    #[error("non-finite {0}")]
    NonFinite(&'static str),
}

/// Errors produced when constructing or validating a [`crate::Track`].
#[derive(Debug, Clone, PartialEq, Error)]
pub enum TrackError {
    /// The track has no points at all.
    #[error("track contains no points")]
    Empty,
    /// The track has fewer than two points, so distance cannot be computed.
    #[error("track requires at least two points, got {0}")]
    TooFewPoints(usize),
    /// Timestamps are not monotonically (non-decreasing) ordered.
    #[error("timestamp at index {0} violates monotonic ordering")]
    NonMonotonicTimestamp(usize),
    /// A point carries a non-finite numeric observation.
    #[error("point at index {index} has {field} value {value} which is not finite")]
    InvalidValue {
        /// 0-based index of the offending point.
        index: usize,
        /// Which field was invalid.
        field: TrackField,
        /// The offending value.
        value: f64,
    },
    /// A resampling interval that is not finite and positive.
    #[error("resampling interval {0} m must be finite and positive")]
    InvalidInterval(f64),
}
