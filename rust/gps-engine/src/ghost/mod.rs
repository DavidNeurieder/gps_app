//! Ghost: race your own best effort.
//!
//! A ghost is the reference (PB) attempt replayed against the live runner:
//! at any elapsed time we know how far the runner is, how far the ghost is,
//! and whether we are ahead.
//!
//! ```text
//! at 20:00    you are at 4,812m, ghost at 4,812m was at 19:43
//!             → 17s behind
//! distance: 4812m  difference: +17s  ahead: false
//! ```

use crate::attempt::Attempt;
use crate::units::{Distance, Duration};

/// The duel state between the runner and the ghost at one instant or at one
/// distance.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GhostState {
    /// Route distance at which the comparison is made.
    pub distance: Distance,
    /// `current - reference` at this distance:
    /// positive means the live runner is behind the ghost.
    pub time_difference: Duration,
    /// `true` when the live runner is ahead of the ghost
    /// (`time_difference < 0`).
    pub ahead: bool,
}

/// A ghost built from a reference (PB) attempt, competing against a live
/// (`current`) attempt.
#[derive(Debug, Clone, PartialEq)]
pub struct Ghost {
    reference: Attempt,
    current: Attempt,
}

impl Ghost {
    /// Creates a ghost duel. `reference` is the personal best; `current` is
    /// the live attempt.
    pub fn new(reference: Attempt, current: Attempt) -> Self {
        Self { reference, current }
    }

    /// Evaluates the duel at an elapsed time of the *live* runner.
    ///
    /// The state reports how far the runner has come by `elapsed`, what the
    /// reference's time at that distance was, and whether the runner is
    /// ahead. `None` for negative or non-finite elapsed times.
    pub fn state_at(&self, elapsed: Duration) -> Option<GhostState> {
        let current_distance = self.current.distance_at(elapsed)?;
        let reference_time = match self.reference.time_at(current_distance) {
            Some(t) => t,
            // The runner is past every distance the reference ever covered:
            // fall back to the reference's finishing time.
            None => self.reference.elapsed_time,
        };
        let time_difference = Duration::from_secs(elapsed.as_secs() - reference_time.as_secs());
        Some(GhostState {
            distance: current_distance,
            time_difference,
            ahead: time_difference.as_secs() < 0.0,
        })
    }

    /// Evaluates the duel at a fixed route distance (a split-point query).
    ///
    /// `None` if either attempt never covered that distance. At the start
    /// (`0m`) both are even.
    pub fn state_at_distance(&self, distance: Distance) -> Option<GhostState> {
        let current_time = self.current.time_at(distance)?;
        let reference_time = match self.reference.time_at(distance) {
            Some(t) => t,
            None => self.reference.elapsed_time,
        };
        let time_difference = current_time - reference_time;
        Some(GhostState {
            distance,
            time_difference,
            ahead: time_difference.as_secs() < 0.0,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::attempt::AttemptSample;

    /// PB: 10 km in 50 min, 5 km split at 25 min.
    fn pb() -> Attempt {
        Attempt::from_samples(vec![
            AttemptSample {
                distance: Distance::ZERO,
                elapsed: Duration::ZERO,
            },
            AttemptSample {
                distance: Distance::from_meters(5_000.0),
                elapsed: Duration::from_secs(1_500.0),
            },
            AttemptSample {
                distance: Distance::from_meters(10_000.0),
                elapsed: Duration::from_secs(3_000.0),
            },
        ])
        .unwrap()
    }

    /// Current: 10 km in 52 min, 5 km split at 25:30.
    fn current() -> Attempt {
        Attempt::from_samples(vec![
            AttemptSample {
                distance: Distance::ZERO,
                elapsed: Duration::ZERO,
            },
            AttemptSample {
                distance: Distance::from_meters(5_000.0),
                elapsed: Duration::from_secs(1_530.0),
            },
            AttemptSample {
                distance: Distance::from_meters(10_000.0),
                elapsed: Duration::from_secs(3_120.0),
            },
        ])
        .unwrap()
    }

    #[test]
    fn behind_by_exactly_30_seconds_at_5km() {
        // Spec: PB 5km = 25:00, current 5km = 25:30 → behind 30s.
        let ghost = Ghost::new(pb(), current());
        let state = ghost
            .state_at_distance(Distance::from_meters(5_000.0))
            .unwrap();
        assert!((state.time_difference.as_secs() - 30.0).abs() < 1e-9);
        assert!(!state.ahead);
        assert!((state.distance.meters() - 5_000.0).abs() < 1e-9);
    }

    #[test]
    fn ahead_when_current_is_faster() {
        let faster = Attempt::from_samples(vec![
            AttemptSample {
                distance: Distance::ZERO,
                elapsed: Duration::ZERO,
            },
            AttemptSample {
                distance: Distance::from_meters(5_000.0),
                elapsed: Duration::from_secs(1_470.0),
            },
            AttemptSample {
                distance: Distance::from_meters(10_000.0),
                elapsed: Duration::from_secs(2_940.0),
            },
        ])
        .unwrap();
        let ghost = Ghost::new(pb(), faster);
        let state = ghost
            .state_at_distance(Distance::from_meters(5_000.0))
            .unwrap();
        assert!((state.time_difference.as_secs() + 30.0).abs() < 1e-9);
        assert!(state.ahead);
    }

    #[test]
    fn tied_attempts_are_never_ahead() {
        let ghost = Ghost::new(pb(), pb());
        for d in [0.0, 5_000.0, 10_000.0] {
            let state = ghost.state_at_distance(Distance::from_meters(d)).unwrap();
            assert!(state.time_difference.as_secs().abs() < 1e-9);
            assert!(!state.ahead);
        }
    }

    #[test]
    fn before_start_and_after_finish() {
        let ghost = Ghost::new(pb(), current());

        // Before the start: even at the start line.
        let state = ghost.state_at(Duration::ZERO).unwrap();
        assert!(state.distance.meters().abs() < 1e-9);
        assert!(state.time_difference.as_secs().abs() < 1e-9);
        assert!(!state.ahead);

        // Past the finish: runner finished 10000 m, ghost benchmark 3000 s:
        // by t = 3120 s the runner has just finished ⇒ +120 s behind.
        let state = ghost.state_at(Duration::from_secs(3_120.0)).unwrap();
        assert!((state.distance.meters() - 10_000.0).abs() < 1e-9);
        assert!((state.time_difference.as_secs() - 120.0).abs() < 1e-9);
        assert!(!state.ahead);
    }

    #[test]
    fn mid_race_state_uses_live_distance() {
        let ghost = Ghost::new(pb(), current());
        // At t = 1500 s: the current attempt has been running 25 min.
        // distance_at(1500) on a linear 0..1530s→0..5000m ramp gives 4901.96m.
        let state = ghost.state_at(Duration::from_secs(1_500.0)).unwrap();
        let expected = 5_000.0 * (1_500.0 / 1_530.0);
        assert!((state.distance.meters() - expected).abs() < 1e-6);
        // Ghost's time at that distance lies on the 0..1500s→0..5000m ramp,
        // so the deficit is purely the 5k split gap at this early stage.
        assert!(state.time_difference.as_secs() > 0.0);
        assert!(!state.ahead);
    }

    #[test]
    fn state_at_rejects_negative_elapsed() {
        let ghost = Ghost::new(pb(), current());
        assert!(ghost.state_at(Duration::from_secs(-1.0)).is_none());
        assert!(ghost.state_at(Duration::from_secs(f64::NAN)).is_none());
    }
}
