/// The engine facade — the only thing Flutter features may talk to (§6).
///
/// The rest of the app depends on this abstract interface and never on raw
/// FFI calls or on the concrete implementation. Two implementations exist:
///
/// - [`FakeEngineService`] (see `fake_engine.dart`) — deterministic, used for
///   UI development before the Rust bridge is wired up (M4).
/// - `RustEngineService` (planned M9) — calls the Rust engine through FFI.
library;

import '../core/units.dart';
import 'models.dart';

abstract class EngineService {
  /// Cleans a recording into a processed track summary.
  Future<ProcessedTrack> processTrack({
    required String id,
    required List<TrackPoint> points,
  });

  /// Whether two recordings are the same route, with diagnostics.
  Future<RouteMatchResult> matchRoutes({
    required List<TrackPoint> a,
    required List<TrackPoint> b,
  });

  /// Reduces a recording onto the route distance axis.
  Future<Attempt> createAttempt({
    required String activityId,
    required String routeId,
    required List<TrackPoint> points,
    required List<GeoPoint> routeGeometry,
  });

  /// Live ghost state at a given distance along the route.
  GhostState ghostStateAt({
    required Ghost ghost,
    required Attempt current,
    required Distance distance,
  });
}