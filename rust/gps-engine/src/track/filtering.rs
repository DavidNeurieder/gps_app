//! GPS point filtering.
//!
//! Filtering removes obvious junk (bad sensor readings, spikes, impossible
//! jumps) without erasing legitimate movement. The first and last points of a
//! track are always preserved, so a filtered track is never shortened to
//! nothing.

use crate::geo::{distance, polyline_length};
use crate::units::{Distance, Duration, Speed};

use super::model::Track;
use super::point::TrackPoint;

/// Configuration controlling which points are removed.
#[derive(Debug, Clone, PartialEq)]
pub struct FilterConfig {
    /// Points whose reported horizontal accuracy is worse than this are
    /// removed. `None` disables the check.
    pub max_accuracy: Option<Distance>,
    /// Points whose reported speed exceeds this are removed, and points whose
    /// adjacent segments imply a faster-than-threshold speed are removed as
    /// spikes. `None` disables the check.
    pub max_speed: Option<Speed>,
    /// Points adjacent to a segment longer than this are removed.
    /// `None` disables the check.
    pub max_jump: Option<Distance>,
    /// Gaps longer than this are treated as pauses: the resampler and speed
    /// checks never bridge them. `None` means every gap is bridgeable.
    pub max_time_gap: Option<Duration>,
}

impl Default for FilterConfig {
    fn default() -> Self {
        FilterConfig {
            max_accuracy: Some(Distance::from_meters(50.0)),
            // 90 km/h: far above any run or ride, far below GPS artifacts.
            max_speed: Some(Speed::from_kmh(90.0)),
            max_jump: Some(Distance::from_meters(200.0)),
            max_time_gap: Some(Duration::from_secs(60.0)),
        }
    }
}

/// What a filtering pass did to a track.
#[derive(Debug, Clone, PartialEq)]
pub struct ProcessingReport {
    /// Points fed into the filter.
    pub input_points: usize,
    /// Points that survived.
    pub output_points: usize,
    /// Points removed (`input - output`).
    pub removed_points: usize,
    /// Total geodesic length before filtering.
    pub distance_before: Distance,
    /// Total geodesic length after filtering.
    pub distance_after: Distance,
}

/// Applies `config` to `track`, returning the filtered track and a report of
/// what was removed and how much distance changed.
pub fn filter(track: &Track, config: &FilterConfig) -> (Track, ProcessingReport) {
    let points = track.points();
    let input_count = points.len();
    let distance_before = polyline_length(&track.coordinates());

    // Pass 1: drop points that fail the sensor-quality checks.
    let mut kept: Vec<usize> = Vec::with_capacity(input_count);
    for (i, point) in points.iter().enumerate() {
        if i == 0 || i == input_count - 1 {
            kept.push(i);
            continue;
        }
        if !passes_sensor_checks(point, config) {
            continue;
        }
        kept.push(i);
    }

    // Pass 2: drop interior points that are impossible spikes. A point is a
    // spike only when BOTH the segment leading into it (from the last
    // surviving point) and the segment leading out of it (toward the next
    // candidate) are jumps. Anchoring on the last surviving point prevents a
    // single bad point from dragging its innocent neighbours down with it.
    let mut result: Vec<TrackPoint> = Vec::with_capacity(kept.len());
    let mut prev = kept[0];
    result.push(points[prev]);
    for k in 1..kept.len() - 1 {
        let i = kept[k];
        let next = kept[k + 1];
        let incoming_jump = is_jump(&points[prev], &points[i], config);
        let outgoing_jump = is_jump(&points[i], &points[next], config);
        if incoming_jump && outgoing_jump {
            continue;
        }
        result.push(points[i]);
        prev = i;
    }
    let last = kept[kept.len() - 1];
    if last != prev {
        result.push(points[last]);
    }

    let distance_after =
        polyline_length(&result.iter().map(|p| p.coordinate()).collect::<Vec<_>>());
    let output_count = result.len();

    (
        Track::from_unchecked(result),
        ProcessingReport {
            input_points: input_count,
            output_points: output_count,
            removed_points: input_count - output_count,
            distance_before,
            distance_after,
        },
    )
}

/// Internal sensor-quality rules: reported accuracy and reported speed.
fn passes_sensor_checks(point: &TrackPoint, config: &FilterConfig) -> bool {
    if let Some(max) = config.max_accuracy
        && let Some(accuracy) = point.accuracy()
        && accuracy > max.meters()
    {
        return false;
    }
    if let Some(max) = config.max_speed
        && let Some(speed) = point.speed()
        && speed > max.mps()
    {
        return false;
    }
    true
}

/// Whether the segment `a → b` looks like an impossible movement.
///
/// A segment is a jump if it is longer than `max_jump`, or if — provided it is
/// shorter than `max_time_gap` (so it is a real, connected movement) — its
/// implied speed exceeds `max_speed`.
fn is_jump(a: &TrackPoint, b: &TrackPoint, config: &FilterConfig) -> bool {
    let gap = distance(a.coordinate(), b.coordinate());

    if let Some(max) = config.max_jump
        && gap.meters() > max.meters()
    {
        return true;
    }

    let dt = b.timestamp().elapsed_since(a.timestamp()).as_secs();
    if dt <= 0.0 {
        return false;
    }

    if let Some(max_gap) = config.max_time_gap
        && dt > max_gap.as_secs()
    {
        // A pause: do not interpret the spatial separation as movement.
        return false;
    }

    if let Some(max) = config.max_speed {
        let speed = gap.meters() / dt;
        return speed > max.mps();
    }

    false
}
