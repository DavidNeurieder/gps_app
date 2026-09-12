use crate::error::TrackError;
use crate::units::{Duration, Timestamp};

use super::point::TrackPoint;

/// A chronologically ordered GPS activity.
///
/// A `Track` is always valid after construction: it has at least two points,
/// timestamps are monotonically non-decreasing, and every numeric observation
/// is finite. Holding the internal vector private keeps those invariants.
///
/// A `Track` is a recording of where the device actually was. It is distinct
/// from a canonical route (a cleaned, repeatable geometry) which is introduced
/// in a later phase.
#[derive(Debug, Clone, PartialEq)]
pub struct Track {
    points: Vec<TrackPoint>,
}

impl Track {
    /// Constructs a track, validating the invariants described above.
    pub fn new(points: Vec<TrackPoint>) -> Result<Self, TrackError> {
        if points.is_empty() {
            return Err(TrackError::Empty);
        }
        if points.len() < 2 {
            return Err(TrackError::TooFewPoints(points.len()));
        }

        let mut previous: Option<Timestamp> = None;
        for (index, point) in points.iter().enumerate() {
            point.validate(index)?;
            if let Some(prev) = previous
                && point.timestamp() < prev
            {
                return Err(TrackError::NonMonotonicTimestamp(index));
            }
            previous = Some(point.timestamp());
        }

        Ok(Track { points })
    }

    /// All points, in chronological order.
    pub fn points(&self) -> &[TrackPoint] {
        &self.points
    }

    /// The first point, if any.
    pub fn start(&self) -> Option<&TrackPoint> {
        self.points.first()
    }

    /// The last point, if any.
    pub fn end(&self) -> Option<&TrackPoint> {
        self.points.last()
    }

    /// Number of points in the track.
    pub fn len(&self) -> usize {
        self.points.len()
    }

    /// Whether the track has no points.
    pub fn is_empty(&self) -> bool {
        self.points.is_empty()
    }

    /// Elapsed wall-clock time from the first to the last point.
    pub fn duration(&self) -> Duration {
        match (self.points.first(), self.points.last()) {
            (Some(first), Some(last)) => last.timestamp().elapsed_since(first.timestamp()),
            _ => Duration::ZERO,
        }
    }
}
