/// JSON codec for the persisted domain models (M10, §27).
///
/// Handles the compact blob format for routes and activities. Timestamps are
/// epoch-milliseconds (UTC) per track point and ISO-8601 for session starts;
/// keep this in sync with [`Activity`] / [`Route`] in `engine/models.dart`.
library;

import 'dart:convert';

import '../core/units.dart';
import '../engine/models.dart';

Map<String, Object?> _geoJson(GeoPoint p) => {
      'lat': p.latitude,
      'lon': p.longitude,
    };

GeoPoint _geoFrom(Map<String, Object?> json) => GeoPoint(
      latitude: (json['lat']! as num).toDouble(),
      longitude: (json['lon']! as num).toDouble(),
    );

Map<String, Object?> _pointJson(TrackPoint p) => {
      'lat': p.position.latitude,
      'lon': p.position.longitude,
      'alt': ?p.altitudeMeters,
      't': p.timestamp.millisecondsSinceEpoch,
    };

TrackPoint _pointFrom(Map<String, Object?> json) => TrackPoint(
      position: GeoPoint(
        latitude: (json['lat']! as num).toDouble(),
        longitude: (json['lon']! as num).toDouble(),
      ),
      altitudeMeters:
          json['alt'] == null ? null : (json['alt']! as num).toDouble(),
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(json['t']! as int, isUtc: true),
    );

Map<String, Object?> _routeJson(Route r) => {
      'id': r.id,
      'name': r.name,
      'distance_m': r.distance.meters,
      'geometry': [for (final p in r.geometry) _geoJson(p)],
      'attempt_count': r.attemptCount,
      'pb_s': ?r.personalBest?.seconds,
    };

Route _routeFrom(Map<String, Object?> json) => Route(
      id: json['id']! as String,
      name: json['name']! as String,
      distance: Distance.meters((json['distance_m']! as num).toDouble()),
      geometry: [
        for (final point in json['geometry']! as List)
          _geoFrom(point as Map<String, Object?>),
      ],
      attemptCount: json['attempt_count']! as int,
      personalBest: json['pb_s'] == null
          ? null
          : Elapsed.seconds((json['pb_s']! as num).toDouble()),
    );

Map<String, Object?> _activityJson(Activity a) {
  final track = a.track;
  return {
    'id': a.id,
    'route_id': ?a.routeId,
    'started_at': a.startedAt.toUtc().toIso8601String(),
    'duration_s': ?a.duration?.seconds,
    'distance_m': ?a.distance?.meters,
    'performance': ?a.performance,
    if (track != null)
      'track': [for (final p in track) _pointJson(p)],
  };
}

Activity _activityFrom(Map<String, Object?> json) => Activity(
      id: json['id']! as String,
      routeId: json['route_id'] as String?,
      startedAt: DateTime.parse(json['started_at']! as String).toUtc(),
      duration: json['duration_s'] == null
          ? null
          : Elapsed.seconds((json['duration_s']! as num).toDouble()),
      distance: json['distance_m'] == null
          ? null
          : Distance.meters((json['distance_m']! as num).toDouble()),
      performance: json['performance'] as String?,
      track: json['track'] == null
          ? null
          : [
              for (final point in json['track']! as List)
                _pointFrom(point as Map<String, Object?>),
            ],
    );

/// Serializes a route list to a compact JSON string.
String routeListToJson(List<Route> routes) =>
    const JsonEncoder().convert([for (final r in routes) _routeJson(r)]);

/// Parses a route list previously written by [routeListToJson].
List<Route> parseRouteList(String json) => [
      for (final route in (jsonDecode(json) as List).cast<Map<String, Object?>>())
        _routeFrom(route),
    ];

/// Serializes an activity list to a compact JSON string.
String activityListToJson(List<Activity> activities) =>
    const JsonEncoder().convert([for (final a in activities) _activityJson(a)]);

/// Parses an activity list previously written by [activityListToJson].
List<Activity> parseActivityList(String json) => [
      for (final activity
          in (jsonDecode(json) as List).cast<Map<String, Object?>>())
        _activityFrom(activity),
    ];