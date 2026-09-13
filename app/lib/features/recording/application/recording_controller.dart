/// Recording state machine — M6 (§8, §9).
///
/// Runs the whole flow on a fake GPS timeline:
///
/// ```text
/// preparing → gpsAcquiring → ready → running ⇄ paused → finishing → completed
/// ```
///
/// The controller owns time and points; the UI is a pure projection of the
/// emitted [`LiveRunState`]. Live state is published at ~2 Hz (§7).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/units.dart';
import '../../../app/dependencies.dart';
import '../../../engine/fake_engine.dart';
import '../../../engine/models.dart';

/// Null until a run session exists; otherwise the current live state.
final recordingControllerProvider =
    NotifierProvider.autoDispose<RecordingController, LiveRunState?>(
        RecordingController.new);

class RecordingController extends Notifier<LiveRunState?> {
  static const Duration _tick = Duration(milliseconds: 500);

  /// Demo cruise speed: 4:57/km.
  static const double _baseSpeedMps = 1000.0 / 297.0;

  Timer? _timer;
  _RecSession? _session;
  final math.Random _random = math.Random(7);

  @override
  LiveRunState? build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    return null;
  }

  /// Starts (or keeps) a run session for [preferredRoutes]. Idempotent.
  void ensureSession(List<Route> preferredRoutes) {
    if (_session != null) {
      return;
    }
    final preferred = preferredRoutes.isNotEmpty
        ? preferredRoutes.firstWhere(
            (r) => r.id == FakeEngineService.riverLoopId,
            orElse: () => preferredRoutes.first,
          )
        : null;
    _session = _RecSession(preferred);
    _beginAcquisition();
  }

  /// Dropping the detected route (`Continue without route`, §11).
  void continueWithoutRoute() {
    final session = _requireSession();
    session.route = null;
    session.ghost = null;
    _emit(status: RunStatus.ready);
  }

  /// START on the pre-run screen: begin moving time.
  void beginRun() {
    final session = _requireSession();
    if (session.route == null) {
      session.loopLength =
          session.geometry.isEmpty ? 0 : polylineMeters(session.geometry);
    }
    _emit(status: RunStatus.running);
  }

  void pause() {
    if (state?.status != RunStatus.running) {
      return;
    }
    _emit(status: RunStatus.paused);
  }

  void resume() {
    if (state?.status != RunStatus.paused) {
      return;
    }
    _emit(status: RunStatus.running);
  }

  /// FINISH: one final "finishing" tick then a completed summary.
  void finishRun() {
    if (state?.status != RunStatus.running &&
        state?.status != RunStatus.paused) {
      return;
    }
    _emit(status: RunStatus.finishing);
  }

  /// Dismiss the completed run and reset the session.
  void dismissRun() {
    _timer?.cancel();
    _timer = null;
    _session = null;
    state = null;
  }

  Future<void> _beginAcquisition() async {
    await _prepareGhost();
    if (_session == null) {
      return; // dismissed while preparing
    }
    _emit(status: RunStatus.preparing);
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) => _onTick());
  }

  void _onTick() {
    switch (state?.status) {
      case RunStatus.preparing:
        _emit(status: RunStatus.gpsAcquiring);
      case RunStatus.gpsAcquiring:
        _emit(status: RunStatus.ready);
      case RunStatus.running:
        _advance();
      case RunStatus.finishing:
        _complete();
      default:
        break;
    }
  }

  void _advance() {
    final session = _requireSession();
    final tickSeconds = _tick.inMilliseconds / 1000.0;

    // Slightly variable, deterministic pace.
    final speed =
        _baseSpeedMps * (0.97 + _random.nextDouble() * 0.06);
    final step = speed * tickSeconds;
    session.distanceM = _clampMeters(session.distanceM + step, session.loopLength);
    session.moving = session.moving + Elapsed.seconds(tickSeconds);

    final position = pointAlongPolyline(session.geometry, session.distanceM);

    GhostState? gap;
    GeoPoint? ghostPosition;
    if (session.ghost != null) {
      gap = _gapAt(session, session.distanceM);
      final ghostDistance = _ghostDistanceAt(session, session.moving.seconds);
      ghostPosition =
          pointAlongPolyline(session.geometry, ghostDistance);
    }

    _emit(
      status: RunStatus.running,
      position: position,
      gap: gap,
      ghostPosition: ghostPosition,
    );
  }

  /// Distance the PB ghost has covered by [liveSeconds] of live moving time.
  double _ghostDistanceAt(_RecSession session, double liveSeconds) {
    final samples = session.ghost!.samples;
    if (samples.isEmpty) {
      return 0;
    }
    if (liveSeconds <= samples.first.elapsed.seconds) {
      return samples.first.distance.meters;
    }
    for (var i = 1; i < samples.length; i++) {
      if (liveSeconds <= samples[i].elapsed.seconds) {
        final a = samples[i - 1];
        final b = samples[i];
        final span = b.elapsed.seconds - a.elapsed.seconds;
        final fraction = span <= 0 ? 0 : (liveSeconds - a.elapsed.seconds) / span;
        return a.distance.meters +
            (b.distance.meters - a.distance.meters) * fraction;
      }
    }
    return samples.last.distance.meters;
  }

  GhostState _gapAt(_RecSession session, double distanceM) {
    final reference = session.ghost!.samples;
    // Live time at this distance: constant cruise pace.
    final liveTime = session.moving.seconds *
        (distanceM / (session.loopLength <= 0 ? 1 : session.loopLength));
    final referenceTime = _referenceTimeAt(reference, distanceM);
    final difference = Elapsed.seconds(liveTime - referenceTime);
    return GhostState(
      distance: Distance.meters(distanceM),
      timeDifference: difference,
      ahead: difference.seconds <= 0,
    );
  }

  /// Interpolates the reference (ghost/PB) time at [distanceM].
  double _referenceTimeAt(List<AttemptSample> samples, double distanceM) {
    if (samples.isEmpty) {
      return 0;
    }
    if (distanceM <= samples.first.distance.meters) {
      return samples.first.elapsed.seconds;
    }
    for (var i = 1; i < samples.length; i++) {
      if (distanceM <= samples[i].distance.meters) {
        final a = samples[i - 1];
        final b = samples[i];
        final span = b.distance.meters - a.distance.meters;
        final fraction = span <= 0 ? 0 : (distanceM - a.distance.meters) / span;
        return a.elapsed.seconds +
            (b.elapsed.seconds - a.elapsed.seconds) * fraction;
      }
    }
    return samples.last.elapsed.seconds;
  }

  void _complete() {
    final session = _requireSession();
    final gap = session.ghost != null
        ? _gapAt(session, session.distanceM)
        : null;
    _emit(
      status: RunStatus.completed,
      gap: gap,
      hasUnsavedData: false,
    );
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _prepareGhost() async {
    final session = _requireSession();
    final route = session.route;
    if (route == null) {
      session.geometry = FakeEngineService.riverLoop;
      session.loopLength = polylineMeters(session.geometry);
      return;
    }
    session.geometry = route.geometry;
    session.loopLength = polylineMeters(session.geometry);

if (route.personalBest case final pb?) {
      // Ghost = the PB attempt run at constant PB speed. M9: generated by
      // whichever engine is wired in (fake or Rust).
      final engine = ref.read(engineServiceProvider);
      final speed = session.loopLength / pb.seconds;
      final recording =
          engine.generateRecording(
              noiseMeters: 1.0,
              speedMetersPerSecond: speed,
              sampleEverySeconds: 1.0);
      final attempt = await engine.createAttempt(
        activityId: 'ghost-${route.id}',
        routeId: route.id,
        points: recording,
        routeGeometry: route.geometry,
      );
      session.ghost =
          Ghost(attemptId: attempt.activityId, samples: attempt.samples);
    }
  }

  void _emit({
    required RunStatus status,
    GeoPoint? position,
    GhostState? gap,
    GeoPoint? ghostPosition,
    bool hasUnsavedData = true,
  }) {
    final session = _requireSession();
    final keepGap = gap ?? state?.ghostGap;
    state = LiveRunState(
      status: status,
      elapsed: session.moving,
      distance: Distance.meters(session.distanceM),
      currentPosition: position ?? state?.currentPosition,
      pace: Speed.metersPerSecond(_baseSpeedMps),
      ghostGap: keepGap,
      routeProgress: session.loopLength <= 0
          ? 0
          : session.distanceM / session.loopLength,
      gpsQuality: status == RunStatus.gpsAcquiring ? 'reduced' : 'good',
      hasUnsavedData: hasUnsavedData,
      route: session.route,
      ghostPosition: ghostPosition ?? state?.ghostPosition,
    );
  }

  _RecSession _requireSession() {
    final session = _session;
    assert(session != null, 'RecordingController has no active session');
    return session!;
  }

  double _clampMeters(double value, double max) {
    if (max <= 0) {
      return value;
    }
    return value > max ? max : value;
  }
}

/// Internal mutable recording session.
class _RecSession {
  _RecSession(this.route);

  Route? route;
  List<GeoPoint> geometry = FakeEngineService.riverLoop;
  double loopLength = 0;
  Ghost? ghost;
  Elapsed moving = Elapsed.zero();
  double distanceM = 0;
}