//! Point-to-polyline projection.

use super::coordinate::Coordinate;
use super::distance::{EARTH_RADIUS_METERS, distance};
use super::interpolation::interpolate;
use crate::units::Distance;

/// Segments shorter than this are treated as degenerate points.
const MIN_SEGMENT_LENGTH_M: f64 = 1e-6;

/// A point projected onto a polyline or route.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Projection {
    /// Distance along the segment (or polyline cumulative distance) from the
    /// segment start, clamped to `[0, segment_length]`.
    pub distance_along: Distance,
    /// Actual geodesic distance from the original point to the projected
    /// point.
    pub lateral_error: Distance,
    /// Fraction within the segment in `[0, 1]` (`0` = at start, `1` = at end).
    pub fraction: f64,
    /// The nearest point on the segment.
    pub projected: Coordinate,
    /// The 0-based index of the matched segment.
    pub segment_index: usize,
}

/// Projects coordinates onto the local tangent plane (equirectangular around
/// `reference_latitude`): `x` points east, `y` points north, in meters.
///
/// The planar model is exact for segments along a meridian or the equator and
/// remains accurate at GPS scales because each segment's reference latitude is
/// its own start point.
fn to_flat(point: Coordinate, reference_latitude: f64) -> (f64, f64) {
    let x = point.longitude().to_radians()
        * EARTH_RADIUS_METERS
        * reference_latitude.to_radians().cos();
    let y = point.latitude().to_radians() * EARTH_RADIUS_METERS;
    (x, y)
}

/// Projects `point` onto a single segment `a` → `b`.
///
/// Points before the segment start clamp to `a` (`fraction == 0`), points
/// after the segment end clamp to `b` (`fraction == 1`). `distance_along` is
/// the geodesic distance from `a` to the projected point; `lateral_error` is
/// the geodesic distance from `point` to the projected point.
pub fn project_to_segment(
    point: Coordinate,
    a: Coordinate,
    b: Coordinate,
    segment_index: usize,
) -> Projection {
    let segment_len = distance(a, b);

    if segment_len.meters() < MIN_SEGMENT_LENGTH_M {
        let error = distance(a, point);
        return Projection {
            distance_along: Distance::ZERO,
            lateral_error: error,
            fraction: 0.0,
            projected: a,
            segment_index,
        };
    }

    let (ax, ay) = to_flat(a, a.latitude());
    let (bx, by) = to_flat(b, a.latitude());
    let (px, py) = to_flat(point, a.latitude());

    let ab_x = bx - ax;
    let ab_y = by - ay;
    let ab_sq = ab_x * ab_x + ab_y * ab_y;

    let ap_x = px - ax;
    let ap_y = py - ay;
    let fraction = ((ap_x * ab_x + ap_y * ab_y) / ab_sq).clamp(0.0, 1.0);

    let projected = interpolate(a, b, fraction);
    let distance_along = segment_len * fraction;
    let lateral_error = distance(point, projected);

    Projection {
        distance_along,
        lateral_error,
        fraction,
        projected,
        segment_index,
    }
}

/// Projects `point` onto a polyline, returning the projection onto the
/// segment whose projected point is nearest to `point`.
///
/// Returns `None` if the polyline has fewer than two points.
pub fn project_to_polyline(point: Coordinate, polyline: &[Coordinate]) -> Option<Projection> {
    if polyline.len() < 2 {
        return None;
    }
    polyline
        .windows(2)
        .enumerate()
        .map(|(index, pair)| project_to_segment(point, pair[0], pair[1], index))
        .min_by(|a, b| {
            a.lateral_error
                .meters()
                .partial_cmp(&b.lateral_error.meters())
                .expect("distances are finite")
        })
}
