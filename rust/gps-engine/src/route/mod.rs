//! Canonical one-dimensional route representation.
//!
//! A [`Route`] is a polyline through space with a stable axis of progress:
//!
//! ```text
//! distance_along_route: 0m ─────────────────────── 7,800m
//! ```
//!
//! Guardrails and geometry are validated at construction; every method is
//! pure. Identity, metadata, and user naming live outside the engine.

pub mod canonical;
pub mod discovery;
pub mod matching;

pub use canonical::{CanonicalError, CanonicalizeConfig, canonicalize};
pub use discovery::{DiscoveredRoute, RouteCatalog, TrackAddition};
pub use matching::{MatchConfig, MatchScore, compare, compare_either_direction, compare_with};

use crate::error::RouteError;
use crate::geo::{Coordinate, Projection, distance, interpolate, project_to_polyline};
use crate::units::Distance;

/// A point sampled from a route: its coordinate paired with its position along
/// the route's one-dimensional axis.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RoutePoint {
    /// Distance along the route from its start, in meters.
    pub distance: Distance,
    /// The point on the route's geometry at that distance.
    pub coordinate: Coordinate,
}

/// A canonical polyline route with a stable 0 → `length()` axis.
///
/// Geometry is validated once at construction (at least two finite points);
/// all methods are pure. A route is the canonical coordinate system that
/// turns noisy GPS points into "distance along route" + "lateral error".
#[derive(Debug, Clone, PartialEq)]
pub struct Route {
    geometry: Vec<Coordinate>,
    /// Meters along the route at each geometry vertex: `cumulative[0] == 0`.
    cumulative: Vec<f64>,
    /// Total length in meters, equal to the last entry of `cumulative`.
    total: f64,
}

impl Route {
    /// Builds a route from a polyline of at least two coordinates.
    ///
    /// Duplicate vertices are allowed and contribute zero length.
    pub fn new(geometry: Vec<Coordinate>) -> Result<Self, RouteError> {
        if geometry.is_empty() {
            return Err(RouteError::Empty);
        }
        if geometry.len() < 2 {
            return Err(RouteError::TooFewPoints(geometry.len()));
        }

        let mut cumulative = Vec::with_capacity(geometry.len());
        cumulative.push(0.0);
        for pair in geometry.windows(2) {
            cumulative
                .push(cumulative.last().expect("non-empty") + distance(pair[0], pair[1]).meters());
        }
        let total = *cumulative.last().expect("non-empty");

        Ok(Self {
            geometry,
            cumulative,
            total,
        })
    }

    /// The route's raw polyline geometry.
    pub fn geometry(&self) -> &[Coordinate] {
        &self.geometry
    }

    /// The route's total length, from start to finish.
    pub fn length(&self) -> Distance {
        Distance::from_meters(self.total)
    }

    /// The route's start coordinate.
    pub fn start(&self) -> Coordinate {
        self.geometry[0]
    }

    /// The route's finish coordinate.
    pub fn end(&self) -> Coordinate {
        *self.geometry.last().expect("route has at least two points")
    }

    /// The coordinate at `distance` meters along the route.
    ///
    /// Returns `None` when `distance` is non-finite, negative, or beyond the
    /// route's total length. `distance == length()` yields the finish point.
    #[allow(clippy::manual_find)]
    pub fn coordinate_at(&self, distance: Distance) -> Option<Coordinate> {
        let target = distance.meters();
        if !target.is_finite() || target < 0.0 || target > self.total {
            return None;
        }
        if target == self.total {
            return Some(self.end());
        }

        // Locate the segment with cumulative[i] <= target < cumulative[i+1].
        let mut i = 0;
        for idx in 0..self.cumulative.len() - 1 {
            if target >= self.cumulative[idx] && target < self.cumulative[idx + 1] {
                i = idx;
                break;
            }
        }

        let seg_len = self.cumulative[i + 1] - self.cumulative[i];
        if seg_len == 0.0 {
            // Duplicate vertices in a row: land on the shared vertex.
            return Some(self.geometry[i]);
        }

        let fraction = ((target - self.cumulative[i]) / seg_len).clamp(0.0, 1.0);
        Some(interpolate(
            self.geometry[i],
            self.geometry[i + 1],
            fraction,
        ))
    }

    /// Projects a coordinate onto the nearest route segment.
    ///
    /// Unlike `geo::project_to_polyline`, the returned `distance_along`
    /// accumulates the distance from the route's start through the matched
    /// segment, giving the one-dimensional position used by attempts and
    /// ghost racing.
    pub fn project(&self, point: Coordinate) -> Projection {
        let mut projection =
            project_to_polyline(point, &self.geometry).expect("route has at least two points");
        projection.distance_along = Distance::from_meters(
            self.cumulative[projection.segment_index] + projection.distance_along.meters(),
        );
        projection
    }

    /// Projects a coordinate and pairs its route distance with the projected
    /// coordinate on the geometry.
    pub fn nearest(&self, point: Coordinate) -> RoutePoint {
        let projection = self.project(point);
        RoutePoint {
            distance: projection.distance_along,
            coordinate: projection.projected,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geo::{Bearing, bearing, project_to_polyline};

    /// A 3-vertex polyline: north along a meridian, then east along a parallel.
    /// The vertical leg is ~0.88 km and the horizontal leg ~0.68 km.
    fn corner_route() -> (Route, Vec<Coordinate>) {
        let a = Coordinate::new(52.50, 13.40).unwrap();
        let b = Coordinate::new(52.508, 13.40).unwrap();
        let c = Coordinate::new(52.508, 13.41).unwrap();
        let coords = vec![a, b, c];
        let route = Route::new(coords.clone()).unwrap();
        (route, coords)
    }

    #[test]
    fn construction_validates_point_count() {
        assert_eq!(Route::new(vec![]).unwrap_err(), RouteError::Empty);
        let single = Coordinate::new(52.5, 13.4).unwrap();
        assert_eq!(
            Route::new(vec![single]).unwrap_err(),
            RouteError::TooFewPoints(1)
        );
    }

    #[test]
    fn length_matches_sum_of_segments() {
        let (route, coords) = corner_route();
        let total =
            distance(coords[0], coords[1]).meters() + distance(coords[1], coords[2]).meters();
        assert!((route.length().meters() - total).abs() < 1e-9);
    }

    #[test]
    fn coordinate_at_endpoints_and_midpoints() {
        let (route, _coords) = corner_route();

        assert_eq!(route.coordinate_at(Distance::ZERO), Some(route.start()));
        assert_eq!(
            route.coordinate_at(route.length()),
            Some(route.end()),
            "at total length should land on the finish"
        );
        assert_eq!(route.coordinate_at(Distance::from_meters(-1.0)), None);
        assert_eq!(
            route.coordinate_at(Distance::from_meters(route.length().meters() + 1.0)),
            None
        );
        assert_eq!(route.coordinate_at(Distance::from_meters(f64::NAN)), None);

        // Halfway along the first (vertical) segment:
        let mid = route.coordinate_at(Distance::from_meters(
            distance(route.start(), route.geometry()[1]).meters() / 2.0,
        ));
        let vertical_mid = interpolate(route.start(), route.geometry()[1], 0.5);
        assert!((mid.unwrap().latitude() - vertical_mid.latitude()).abs() < 1e-12);
    }

    #[test]
    fn coordinate_at_trailing_zero_length_segment_is_valid() {
        let a = Coordinate::new(52.50, 13.40).unwrap();
        let b = Coordinate::new(52.505, 13.40).unwrap();
        let b2 = b; // duplicate vertex at the end
        let route = Route::new(vec![a, b, b2]).unwrap();
        assert_eq!(
            route.coordinate_at(route.length()),
            Some(b),
            "duplicate finish vertex should not panic"
        );
        let halfway = route.coordinate_at(Distance::from_meters(route.length().meters() / 2.0));
        assert!(halfway.is_some());
    }

    #[test]
    fn project_at_vertices_and_midpoint() {
        let (route, coords) = corner_route();

        let start_projection = route.project(coords[0]);
        assert!(start_projection.distance_along.meters().abs() < 1e-9);
        assert!(start_projection.lateral_error.meters().abs() < 1e-9);

        let end_projection = route.project(coords[2]);
        assert!(
            (end_projection.distance_along.meters() - route.length().meters()).abs() < 1e-9,
            "finish projects to the full route length"
        );

        // Midpoint of the first segment projects to half its length.
        let mid = interpolate(coords[0], coords[1], 0.5);
        let mid_projection = route.project(mid);
        let expected = distance(coords[0], mid).meters();
        assert!(
            (mid_projection.distance_along.meters() - expected).abs() < 1e-6,
            "segment midpoint should project to half its length"
        );
    }

    #[test]
    fn projection_accumulates_across_segments() {
        // A point near the middle of the second segment should report its
        // track along the whole route, not just the segment.
        let (route, coords) = corner_route();
        let vertical = distance(coords[0], coords[1]).meters();

        let probe = interpolate(coords[1], coords[2], 0.25); // second segment, quarter in
        let projection = route.project(probe);
        let expected = vertical + distance(coords[1], probe).meters();
        assert!((projection.distance_along.meters() - expected).abs() < 1e-6);

        // The nearest's coordinate should reproduce the probe's along-track
        // coordinate up to projection tolerance.
        let nearest = route.nearest(probe);
        assert!((nearest.distance.meters() - expected).abs() < 1e-6);
    }

    #[test]
    fn lateral_offset_projects_with_correct_error() {
        // A probe 30 m west of the vertical leg's midpoint: lateral error
        // should be ~30 m while the along-route distance stays at the
        // vertical leg's midpoint.
        let (route, _coords) = corner_route();

        let bearing_north = bearing(route.start(), route.geometry()[1]).unwrap();
        let mid = crate::geo::destination(
            route.start(),
            bearing_north,
            Distance::from_meters(route.length().meters() / 2.0),
        );
        let probe = crate::geo::destination(
            mid,
            Bearing::from_degrees(270.0).unwrap(),
            Distance::from_meters(30.0),
        );

        let projection = route.project(probe);
        let expected_along = route.length().meters() / 2.0;
        assert!(
            (projection.distance_along.meters() - expected_along).abs() < 1e-3,
            "offset point should keep its along-route distance"
        );
        assert!(
            (projection.lateral_error.meters() - 30.0).abs() < 1e-3,
            "lateral error should match the 30 m offset"
        );
    }

    #[test]
    fn project_agrees_with_raw_polyline_projection() {
        let (route, coords) = corner_route();

        // Probe off the bend (the second vertex), where either segment could
        // win; both projections must agree on the shape.
        let probe = crate::geo::destination(
            route.geometry()[1],
            Bearing::from_degrees(315.0).unwrap(),
            Distance::from_meters(25.0),
        );

        let raw = project_to_polyline(probe, &coords).unwrap();
        let wrapped = route.project(probe);
        assert_eq!(raw.segment_index, wrapped.segment_index);
        assert!(
            (raw.lateral_error.meters() - wrapped.lateral_error.meters()).abs() < 1e-9,
            "lateral error must not change when wrapping"
        );
        // Wrapped distance_along = accumulated prefix + per-segment distance.
        let prefix = if raw.segment_index == 0 {
            0.0
        } else {
            distance(coords[0], coords[1]).meters()
        };
        assert!(
            (wrapped.distance_along.meters() - (prefix + raw.distance_along.meters())).abs() < 1e-6,
            "wrapped distance must accumulate across segments"
        );
    }
}
