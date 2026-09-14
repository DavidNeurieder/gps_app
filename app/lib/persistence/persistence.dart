/// Persistence for routes and activities (M10, §27).
///
/// Repositories own the data and expose it to the UI as [Notifier]s, so Home
/// and Record stay reactive without routing data through the recording
/// controller. By default a [`NoopPersistenceStore`] keeps state in memory
/// (deterministic demo data, hermetic widget tests); swap in a
/// [`JsonFileStore`] to make it survive restarts:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     persistenceStoreProvider.overrideWithValue(
///       JsonFileStore(Directory('data')),
///     ),
///   ],
/// )
/// ```
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/units.dart';
import '../engine/fake_engine.dart';
import '../engine/models.dart';
import 'serialization.dart';

/// Backing store for one or more JSON documents. Read is synchronous because
/// the documents are small; write is atomic (temp file + rename).
abstract class PersistenceStore {
  /// Returns the document for [key], or `null` when none exists.
  String? read(String key);

  /// Stores [value] under [key], atomically when the backend supports it.
  Future<void> write(String key, String value);
}

/// In-memory, stateless store — nothing is persisted to disk.
class NoopPersistenceStore implements PersistenceStore {
  const NoopPersistenceStore();

  @override
  String? read(String key) => null;

  @override
  Future<void> write(String key, String value) async {}
}

/// A flat JSON-file store rooted at a directory.
class JsonFileStore implements PersistenceStore {
  JsonFileStore(this.directory);

  final Directory directory;

  @override
  String? read(String key) {
    final file = File('${directory.path}/$key.json');
    if (!file.existsSync()) {
      return null;
    }
    return file.readAsStringSync();
  }

  @override
  Future<void> write(String key, String value) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/$key.json');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(value, flush: true);
    await tmp.rename(file.path);
  }
}

/// The backing store for every repository. Defaults to in-memory.
final persistenceStoreProvider = Provider<PersistenceStore>(
  (_) => const NoopPersistenceStore(),
);

/// Routed catalog — what Home and Record see.
final routeRepositoryProvider =
    NotifierProvider<RouteRepository, List<Route>>(RouteRepository.new);

/// Activity history — newest first.
final activityRepositoryProvider =
    NotifierProvider<ActivityRepository, List<Activity>>(
        ActivityRepository.new);

/// Routes can be stored, loaded, and (later, M12) grown by saving new runs.
class RouteRepository extends Notifier<List<Route>> {
  @override
  List<Route> build() {
    ref.watch(persistenceStoreProvider);
    final raw = ref.read(persistenceStoreProvider).read(_routesKey);
    if (raw != null) {
      try {
        return parseRouteList(raw);
      } on FormatException {
        // Corrupt store: fall back to the seeded catalog.
      }
    }
    return _seedRoutes;
  }

  /// Upserts [route] into the catalog.
  Future<void> saveRoute(Route route) async {
    final index = state.indexWhere((r) => r.id == route.id);
    final next = [...state];
    if (index >= 0) {
      next[index] = route;
    } else {
      next.add(route);
    }
    state = next;
    await _persist();
  }

  Future<void> _persist() async {
    final store = ref.read(persistenceStoreProvider);
    if (store is NoopPersistenceStore) {
      return;
    }
    await store.write(_routesKey, routeListToJson(state));
  }

  static const _routesKey = 'routes';
}

/// Completed activities can be stored and reloaded as history.
class ActivityRepository extends Notifier<List<Activity>> {
  @override
  List<Activity> build() {
    ref.watch(persistenceStoreProvider);
    final raw = ref.read(persistenceStoreProvider).read(_activitiesKey);
    if (raw != null) {
      try {
        return parseActivityList(raw);
      } on FormatException {
        // Corrupt store: fall back to the seeded history.
      }
    }
    return _seedActivities;
  }

  /// Inserts [activity] at the top of the history (newest first).
  Future<void> saveActivity(Activity activity) async {
    state = [activity, ...state.where((a) => a.id != activity.id)];
    await _persist();
  }

  Future<void> _persist() async {
    final store = ref.read(persistenceStoreProvider);
    if (store is NoopPersistenceStore) {
      return;
    }
    await store.write(_activitiesKey, activityListToJson(state));
  }

  static const _activitiesKey = 'activities';
}

/// Seeded route catalog shown until the user builds their own (M10 demo data).
List<Route> get _seedRoutes => const <Route>[
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

/// Seeded history so Home shows recent activity on first launch.
List<Activity> get _seedActivities {
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
}

/// Minimal loop geometry for the Park 5K demo route.
const List<GeoPoint> _park5k = <GeoPoint>[
  GeoPoint(latitude: 52.5200, longitude: 13.3800),
  GeoPoint(latitude: 52.5320, longitude: 13.3860),
  GeoPoint(latitude: 52.5200, longitude: 13.3920),
  GeoPoint(latitude: 52.5080, longitude: 13.3860),
  GeoPoint(latitude: 52.5200, longitude: 13.3800),
];

/// Minimal loop geometry for the Hügelrunde demo route.
const List<GeoPoint> _huegelrunde = <GeoPoint>[
  GeoPoint(latitude: 52.4900, longitude: 13.3000),
  GeoPoint(latitude: 52.5100, longitude: 13.3100),
  GeoPoint(latitude: 52.4900, longitude: 13.3200),
  GeoPoint(latitude: 52.4700, longitude: 13.3100),
  GeoPoint(latitude: 52.4900, longitude: 13.3000),
];