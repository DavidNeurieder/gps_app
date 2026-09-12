//! Pairwise route similarity.
//!
//! Given two GPS tracks, answers the MVP question *"do these recordings
//! represent the same route?"* with structured diagnostics rather than a bare
//! boolean:
//!
//! ```text
//! start:       8m
//! end:         13m
//! length:      1.02
//! overlap:     94%
//! direction:   0.98
//! ```
//!
//! See [`MatchConfig`] for the thresholds and [`MatchScore`] for the metrics.
//! The [`overall_score`](MatchScore::overall_score) is a provisional single
//! number; debugging should use the individual components.

use crate::geo::{bearing, distance, project_to_polyline};
use crate::units::Distance;
use crate::{Coordinate, Track};

/// Thresholds for pairwise track comparison.
///
/// `min_*`/`max_*` fields bound the reported metrics; `lateral_tolerance` is
/// the distance within which a point counts as "on" the other track's
/// geometry when computing spatial overlap.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MatchConfig {
    /// A point is "on" another track when it projects within this many meters.
    pub lateral_tolerance: Distance,
    /// Minimum spatial overlap for a route match (0..1).
    pub min_spatial_overlap: f64,
    /// Minimum ratio `length_a / length_b` for a route match.
    pub min_distance_ratio: f64,
    /// Maximum ratio `length_a / length_b` for a route match.
    pub max_distance_ratio: f64,
    /// Maximum allowed start-to-start distance, in meters.
    pub max_start_distance: Distance,
    /// Maximum allowed finish-to-finish distance, in meters.
    pub max_end_distance: Distance,
}

impl Default for MatchConfig {
    fn default() -> Self {
        Self {
            lateral_tolerance: Distance::from_meters(25.0),
            min_spatial_overlap: 0.6,
            min_distance_ratio: 0.85,
            max_distance_ratio: 1.18,
            max_start_distance: Distance::from_meters(150.0),
            max_end_distance: Distance::from_meters(150.0),
        }
    }
}

/// Structured similarity report between two tracks.
///
/// All metrics are 0..1 fractions (or distances/ratios) that can be inspected
/// individually. `overall_score` aggregates them and is provisional — tune it
/// against a labeled corpus before trusting it as a threshold.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MatchScore {
    /// Geodesic distance between the two start points, in meters.
    pub start_distance: Distance,
    /// Geodesic distance between the two finish points, in meters.
    pub end_distance: Distance,
    /// `length_a / length_b`.
    pub distance_ratio: f64,
    /// Fraction of each track's points near the other's geometry (the smaller
    /// of the two directions), 0..1.
    pub spatial_overlap: f64,
    /// Mean directional agreement of matched segments, 0..1 (~0 if one track
    /// runs the route reversed relative to the other).
    pub direction_similarity: f64,
    /// Provisional weighted aggregate of the metrics above, 0..1.
    pub overall_score: f64,
}

impl MatchScore {
    /// Conservative "same route?" decision from geometry-only metrics.
    ///
    /// Direction is *not* part of the boolean: a route run in reverse is still
    /// the same route, so reversed recordings keep matching while
    /// [`direction_similarity`](MatchScore::direction_similarity) is reported
    /// separately. All thresholds come from `config`.
    pub fn is_match(&self, config: &MatchConfig) -> bool {
        self.proximity_ok(config)
            && self.distance_ratio >= config.min_distance_ratio
            && self.distance_ratio <= config.max_distance_ratio
            && self.spatial_overlap >= config.min_spatial_overlap
    }

    /// Whether the start and finish pairs are within their proximity caps.
    fn proximity_ok(&self, config: &MatchConfig) -> bool {
        self.start_distance.meters() <= config.max_start_distance.meters()
            && self.end_distance.meters() <= config.max_end_distance.meters()
    }
}

/// Compares `a` against `b` in either travel orientation, returning the better
/// matching score when either the forward or the reversed comparison satisfies
/// `config`; `None` when neither does.
///
/// This lets route discovery cluster recordings that run the same route in the
/// opposite direction. The returned score reports the orientation that
/// matched.
pub fn compare_either_direction(a: &Track, b: &Track, config: &MatchConfig) -> Option<MatchScore> {
    let forward = compare_with(a, b, config);
    if forward.is_match(config) {
        return Some(forward);
    }

    let reversed_b = b.reversed();
    let reversed = compare_with(a, &reversed_b, config);
    if reversed.is_match(config) {
        Some(reversed)
    } else {
        None
    }
}

/// Compares two tracks with [`MatchConfig::default`].
pub fn compare(a: &Track, b: &Track) -> MatchScore {
    compare_with(a, b, &MatchConfig::default())
}

/// Compares two tracks under custom thresholds.
pub fn compare_with(a: &Track, b: &Track, config: &MatchConfig) -> MatchScore {
    let start_distance = distance(
        a.start().expect("track non-empty").coordinate(),
        b.start().expect("track non-empty").coordinate(),
    );
    let end_distance = distance(
        a.end().expect("track non-empty").coordinate(),
        b.end().expect("track non-empty").coordinate(),
    );

    let distance_ratio = robust_length(a).meters() / robust_length(b).meters();
    let spatial_overlap = overlap(a, b, config);
    let direction_similarity = direction_similarity(a, b, config.lateral_tolerance);

    let closure = |d: Distance, max: Distance| -> f64 {
        if max.meters() <= 0.0 {
            return 0.0;
        }
        (1.0 - (d.meters() / max.meters())).clamp(0.0, 1.0)
    };

    let overall_score = 0.40 * spatial_overlap
        + 0.25 * direction_similarity
        + 0.20 * closure(start_distance, config.max_start_distance)
        + 0.15 * closure(end_distance, config.max_end_distance);

    MatchScore {
        start_distance,
        end_distance,
        distance_ratio,
        spatial_overlap,
        direction_similarity,
        overall_score,
    }
}

/// Fraction of `b`'s points near `a`'s geometry, then the reverse, taking the
/// minimum. Direction-agnostic: a reversed recording still overlaps.
fn overlap(a: &Track, b: &Track, config: &MatchConfig) -> f64 {
    let tol = config.lateral_tolerance;
    let ab = fraction_near(b, &polyline(a), tol);
    let ba = fraction_near(a, &polyline(b), tol);
    ab.min(ba)
}

fn polyline(track: &Track) -> Vec<Coordinate> {
    track.points().iter().map(|p| p.coordinate()).collect()
}

/// Along-track length robust to lateral GPS noise: the length of the track
/// re-sampled onto 50 m chords. Lateral jitter barely inflates a 50 m chord,
/// so recording-length ratios stay meaningful for the matcher (a raw point
/// length would be the noisy GPS path, not the route distance).
fn robust_length(track: &Track) -> Distance {
    const CHORD_M: f64 = 50.0;
    match track.resample_by_distance(Distance::from_meters(CHORD_M)) {
        Ok(resampled) => {
            let length = resampled.distance().meters();
            if length > 0.0 {
                Distance::from_meters(length)
            } else {
                track.distance() // too short to span a 50 m chord
            }
        }
        Err(_) => track.distance(),
    }
}

fn fraction_near(subject: &Track, geometry: &[Coordinate], tol: Distance) -> f64 {
    let mut near = 0usize;
    let mut total = 0usize;
    for p in subject.points() {
        let Some(projection) = project_to_polyline(p.coordinate(), geometry) else {
            continue;
        };
        total += 1;
        if projection.lateral_error.meters() <= tol.meters() {
            near += 1;
        }
    }
    if total == 0 {
        return 0.0;
    }
    near as f64 / total as f64
}

/// Mean directional agreement between matched segments: for each chord of `b`
/// spanning at least [`MIN_DIRECTION_STEP_M`] meters whose midpoint is near
/// `a`, compare the chord bearing with the bearing of the `a`-segment the
/// midpoint projects onto. Same direction scores +1, reversed scores 0.
///
/// A chord basis is used (rather than consecutive fixes) so that GPS noise
/// does not dominate the direction signal on short, slow steps.
const MIN_DIRECTION_STEP_M: f64 = 20.0;

fn direction_similarity(a: &Track, b: &Track, tol: Distance) -> f64 {
    let pa = polyline(a);

    let mut sum = 0.0f64;
    let mut count = 0usize;

    let pts = b.points();
    let mut chord_start = pts[0].coordinate();
    for point in &pts[1..] {
        let step = distance(chord_start, point.coordinate()).meters();
        if step < MIN_DIRECTION_STEP_M {
            continue; // keep building the chord
        }

        let Ok(chord_bearing) = bearing(chord_start, point.coordinate()) else {
            chord_start = point.coordinate();
            continue;
        };
        let mid = crate::geo::destination(
            chord_start,
            chord_bearing,
            Distance::from_meters(step / 2.0),
        );
        let Some(projection) = project_to_polyline(mid, &pa) else {
            chord_start = point.coordinate();
            continue;
        };

        if projection.lateral_error.meters() <= tol.meters() {
            let seg_from = pa[projection.segment_index];
            let seg_to = pa[projection.segment_index + 1];
            let Ok(a_bearing) = bearing(seg_from, seg_to) else {
                chord_start = point.coordinate();
                continue;
            };

            let delta = (chord_bearing.as_radians() - a_bearing.as_radians())
                .rem_euclid(std::f64::consts::TAU);
            sum += delta.cos().max(0.0);
            count += 1;
        }

        chord_start = point.coordinate();
    }

    if count == 0 {
        return 0.0;
    }
    sum / count as f64
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::synthetic::{SyntheticConfig, add_detour, generate, reverse};
    use crate::{FilterConfig, SimplifyConfig, TrackPoint};

    fn route() -> Vec<Coordinate> {
        vec![
            Coordinate::new(52.500, 13.400).unwrap(),
            Coordinate::new(52.506, 13.403).unwrap(),
            Coordinate::new(52.512, 13.401).unwrap(),
            Coordinate::new(52.518, 13.408).unwrap(),
        ]
    }

    fn clean(seed: u64) -> Track {
        generate(&route(), &SyntheticConfig::clean(seed))
    }

    fn noisy(seed: u64) -> Track {
        generate(&route(), &SyntheticConfig::noisy(seed, 6.0))
    }

    /// The real pipeline: messy recording → filter + simplify + resample (25 m),
    /// then compare. Resampling by distance gives a jitter-robust length basis.
    fn cleaned(track: &Track) -> Track {
        let (filtered, _report) = track.filter(&FilterConfig::default());
        let simplified = filtered.simplify(&SimplifyConfig::default());
        simplified
            .resample_by_distance(Distance::from_meters(25.0))
            .unwrap()
    }

    #[test]
    fn identical_track_scores_perfectly() {
        let a = clean(1);
        let score = compare(&a, &a);
        assert!(score.start_distance.meters() < 1e-9);
        assert!(score.end_distance.meters() < 1e-9);
        assert!((score.distance_ratio - 1.0).abs() < 1e-9);
        assert!(score.spatial_overlap > 0.99);
        assert!(score.direction_similarity > 0.99);
        assert!(score.overall_score > 0.95);
    }

    #[test]
    fn two_recordings_of_same_route_match() {
        let a = cleaned(&clean(1));
        let b = cleaned(&noisy(2));
        let score = compare(&a, &b);
        assert!(
            score.spatial_overlap > 0.8,
            "overlap {}",
            score.spatial_overlap
        );
        assert!(
            score.direction_similarity > 0.8,
            "direction {}",
            score.direction_similarity
        );
        assert!(
            (score.distance_ratio - 1.0).abs() < 0.4,
            "ratio {}",
            score.distance_ratio
        );
    }

    #[test]
    fn reversed_track_keeps_overlap_but_panics_direction() {
        let a = clean(1);
        let b = reverse(&clean(1));
        let score = compare(&a, &b);
        assert!(
            score.spatial_overlap > 0.8,
            "geometry overlap is direction-neutral"
        );
        assert!(
            score.direction_similarity < 0.2,
            "reversed recording should disagree in direction, got {}",
            score.direction_similarity
        );
    }

    #[test]
    fn crossing_routes_do_not_match() {
        // Two routes of similar length crossing near-perpendicularly at their
        // midpoint: they share only a tiny region, so they must not match.
        let route_a = vec![
            Coordinate::new(52.500, 13.400).unwrap(),
            Coordinate::new(52.520, 13.400).unwrap(),
        ];
        let route_b = vec![
            Coordinate::new(52.510, 13.390).unwrap(),
            Coordinate::new(52.510, 13.410).unwrap(),
        ];
        let a = cleaned(&generate(&route_a, &SyntheticConfig::clean(1)));
        let b = cleaned(&generate(&route_b, &SyntheticConfig::clean(2)));

        let score = compare(&a, &b);
        assert!(
            score.spatial_overlap < 0.3,
            "perpendicular crossing routes barely overlap, got {}",
            score.spatial_overlap
        );
        assert!(!score.is_match(&MatchConfig::default()));
    }

    #[test]
    fn parallel_routes_do_not_match() {
        // Two ~1 km parallel lanes 200 m apart: lateral error alone must
        // separate them (default tolerance is 25 m).
        let route_a = vec![
            Coordinate::new(52.500, 13.400).unwrap(),
            Coordinate::new(52.510, 13.400).unwrap(),
        ];
        let offset_west = Coordinate::new(52.500, 13.3980).unwrap();
        let offset_east = Coordinate::new(52.510, 13.3980).unwrap();
        let route_b = vec![offset_west, offset_east];
        let a = generate(&route_a, &SyntheticConfig::clean(1));
        let b = generate(&route_b, &SyntheticConfig::clean(2));

        let score = compare(&a, &b);
        assert!(
            score.spatial_overlap < 0.3,
            "200 m apart lanes must not count as on-route (25 m tolerance)",
        );
        assert!(!score.is_match(&MatchConfig::default()));
    }

    #[test]
    fn different_route_scores_low() {
        let a = clean(1);
        let other_route = vec![
            Coordinate::new(52.510, 13.410).unwrap(),
            Coordinate::new(52.505, 13.430).unwrap(),
            Coordinate::new(52.498, 13.455).unwrap(),
        ];
        let b = generate(&other_route, &SyntheticConfig::clean(2));
        let score = compare(&a, &b);
        assert!(
            score.spatial_overlap < 0.3,
            "different routes barely overlap"
        );
    }

    #[test]
    fn partial_route_reports_intermediate_overlap() {
        // b is a ~half-length prefix of a.
        let full = clean(1);
        let half: Vec<TrackPoint> = full.points()[..full.points().len() / 2].to_vec();
        let prefix = Track::new(half).unwrap();
        let score = compare(&full, &prefix);
        assert!(
            score.spatial_overlap < 0.8,
            "half route should not fully overlap"
        );
        assert!(score.spatial_overlap > 0.3);
        assert!(
            score.distance_ratio > 1.2 && score.distance_ratio < 3.0,
            "full/prefix length ratio was {}",
            score.distance_ratio
        );
    }

    #[test]
    fn detour_degrades_similarity_gracefully() {
        let a = clean(1);
        let b = add_detour(&a, Distance::from_meters(40.0));
        let score = compare(&a, &b);
        assert!(
            score.spatial_overlap > 0.5,
            "small detour keeps most points near"
        );
        assert!(score.spatial_overlap < 0.99, "but not all");
    }

    #[test]
    fn reversed_plus_noise_is_recovered_by_comparing_in_forward_order() {
        // The engine compares in the given order; a user recording the loop
        // in reverse should still show high overlap, which the caller can
        // combine with the low direction to decide it's the same route.
        let a = clean(1);
        let b = noisy(7);
        let b = reverse(&b);
        let score = compare(&a, &b);
        assert!(score.spatial_overlap > 0.6);
        assert!(score.direction_similarity < 0.3);
    }

    #[test]
    fn looser_lateral_tolerance_raises_overlap() {
        let a = clean(1);
        let b = add_detour(&a, Distance::from_meters(40.0));

        let tight = compare_with(
            &a,
            &b,
            &MatchConfig {
                lateral_tolerance: Distance::from_meters(10.0),
                ..MatchConfig::default()
            },
        );
        let loose = compare_with(
            &a,
            &b,
            &MatchConfig {
                lateral_tolerance: Distance::from_meters(100.0),
                ..MatchConfig::default()
            },
        );

        assert!(loose.spatial_overlap >= tight.spatial_overlap);
        assert!(
            loose.spatial_overlap > 0.9,
            "wide tolerance covers the detour"
        );
    }
}
