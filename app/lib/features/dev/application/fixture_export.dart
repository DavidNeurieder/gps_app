/// Serializes a record to the M15 raw-GPS fixture schema (developer
/// diagnostics, M15 Phase 10 / 12).
///
/// The emitted document is exactly what `rust/gps-engine`'s
/// `Fixture::from_json` parses back:
///
/// ```json
/// {"route":[{"lat":..,"lon":..}],
///  "fixes":[{"timestamp_ms":..,"latitude":..,"longitude":..,
///            "accuracy_m":..,"altitude_m":..,"speed_mps":..,"bearing_deg":..}]}
/// ```
///
/// A trace recorded on a physical phone can be pasted straight into
/// `tests/fixtures/` and replayed as a regression test.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../../../engine/models.dart';

const double _exportAccuracyM = 5.0;
const double _exportAltitudeM = 60.0;

/// Builds a fixture JSON document from [route] geometry and raw [fixes].
String buildFixtureJson({
  required List<GeoPoint> route,
  required List<TrackPoint> fixes,
}) {
  return const JsonEncoder().convert({
    'route': [
      for (final p in route) {'lat': p.latitude, 'lon': p.longitude},
    ],
    'fixes': [
      for (var i = 0; i < fixes.length; i++)
        _fixJson(fixes, i),
    ],
  });
}

Map<String, Object?> _fixJson(List<TrackPoint> fixes, int i) {
  final fix = fixes[i];
  final previous = i == 0 ? null : fixes[i - 1];
  final next = i + 1 < fixes.length ? fixes[i + 1] : null;
  final heading = previous == null
      ? (next == null ? 0.0 : _bearingDeg(fix.position, next.position))
      : _bearingDeg(previous.position, fix.position);
  final speed = previous == null
      ? null
      : _speedMps(previous, fix);
  return {
    'timestamp_ms': fix.timestamp.millisecondsSinceEpoch,
    'latitude': fix.position.latitude,
    'longitude': fix.position.longitude,
    'accuracy_m': _exportAccuracyM,
    'altitude_m': _exportAltitudeM,
    'speed_mps': ?speed,
    'bearing_deg': heading,
  };
}

/// Average ground speed between two fixes, in m/s (`null` for the first fix).
double? _speedMps(TrackPoint a, TrackPoint b) {
  final dt = b.timestamp.difference(a.timestamp).inMilliseconds / 1000.0;
  if (dt <= 0) {
    return null;
  }
  return haversineMeters(a.position, b.position) / dt;
}

/// Initial forward azimuth from [a] to [b], in degrees 0..360 (WGS84
/// great-circle). Mirrors `geo::bearing` on the Rust side.
double _bearingDeg(GeoPoint a, GeoPoint b) {
  final lat1 = _rad(a.latitude);
  final lat2 = _rad(b.latitude);
  final dLon = _rad(b.longitude - a.longitude);
  final x = math.sin(dLon) * math.cos(lat2);
  final y = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  var degrees = math.atan2(x, y) * (180.0 / math.pi);
  if (degrees < 0) {
    degrees += 360.0;
  }
  return degrees;
}

double _rad(double degrees) => degrees * (math.pi / 180.0);