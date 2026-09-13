/// Home feature application layer: seeded demo catalogs (§M10 persistence later).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/units.dart';
import '../../../engine/fake_engine.dart';
import '../../../engine/models.dart';

/// Routes shown on the home screen. Replace with the repository at M10.
final homeRoutesProvider = Provider<List<Route>>((_) {
  return const [
    Route(
      id: FakeEngineService.riverLoopId,
      name: 'River Loop',
      distance: Distance.kilometers(4.76),
      geometry: FakeEngineService.riverLoop,
      attemptCount: 12,
      personalBest: Elapsed.seconds(1470),
    ),
    Route(
      id: 'park-5k',
      name: 'Park 5K',
      distance: Distance.kilometers(5.0),
      geometry: _park5k,
      attemptCount: 8,
      personalBest: Elapsed.seconds(1625),
    ),
    Route(
      id: 'huegelrunde',
      name: 'Hügelrunde',
      distance: Distance.kilometers(8.2),
      geometry: _huegelrunde,
      attemptCount: 3,
      personalBest: Elapsed.seconds(2770),
    ),
  ];
});

/// Recent activities sorted by start time (newest first). Replace at M10.
final recentActivitiesProvider = Provider<List<Activity>>((_) {
  final now = DateTime.now().toUtc();
  return [
    Activity(
      id: 'act-003',
      routeId: FakeEngineService.riverLoopId,
      startedAt: now.subtract(const Duration(hours: 26)),
      duration: const Elapsed.seconds(1502),
      distance: const Distance.kilometers(4.75),
      performance: '24:22 · 1st',
    ),
    Activity(
      id: 'act-002',
      routeId: 'park-5k',
      startedAt: now.subtract(const Duration(days: 4)),
      duration: const Elapsed.seconds(1630),
      distance: const Distance.kilometers(5.01),
      performance: '27:10 · 3rd',
    ),
  ];
});

/// Minimal loop geometries until M8 replaces them with real ones.
const List<GeoPoint> _park5k = <GeoPoint>[
  GeoPoint(latitude: 52.5200, longitude: 13.3800),
  GeoPoint(latitude: 52.5320, longitude: 13.3860),
  GeoPoint(latitude: 52.5200, longitude: 13.3920),
  GeoPoint(latitude: 52.5080, longitude: 13.3860),
  GeoPoint(latitude: 52.5200, longitude: 13.3800),
];

const List<GeoPoint> _huegelrunde = <GeoPoint>[
  GeoPoint(latitude: 52.4900, longitude: 13.3000),
  GeoPoint(latitude: 52.5100, longitude: 13.3100),
  GeoPoint(latitude: 52.4900, longitude: 13.3200),
  GeoPoint(latitude: 52.4700, longitude: 13.3100),
  GeoPoint(latitude: 52.4900, longitude: 13.3000),
];