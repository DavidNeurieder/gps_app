import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_app/core/units.dart';
import 'package:gps_app/engine/fake_engine.dart';
import 'package:gps_app/engine/models.dart';
import 'package:gps_app/features/recording/application/recording_controller.dart';

const _route = Route(
  id: FakeEngineService.riverLoopId,
  name: 'River Loop',
  distance: Distance.kilometers(4.76),
  geometry: FakeEngineService.riverLoop,
  attemptCount: 12,
  personalBest: Elapsed.seconds(1470),
);

void main() {
  /// Keeps the autoDispose provider alive while a fake-async test runs.
  ProviderSubscription<LiveRunState?> keepAlive(ProviderContainer c) {
    final sub = c.listen(recordingControllerProvider, (_, _) {});
    addTearDown(sub.close);
    return sub;
  }

  LiveRunState? state(ProviderContainer c) =>
      c.read(recordingControllerProvider);

  test('pre-run flow: preparing → gpsAcquiring → ready', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      keepAlive(c);
      c.read(recordingControllerProvider.notifier).ensureSession([_route]);
      async.flushMicrotasks();

      expect(state(c)!.status, RunStatus.preparing);

      async.elapse(const Duration(milliseconds: 500));
      expect(state(c)!.status, RunStatus.gpsAcquiring);

      async.elapse(const Duration(milliseconds: 500));
      expect(state(c)!.status, RunStatus.ready);
      expect(state(c)!.route?.name, 'River Loop');
    });
  });

  test('running advances distance and moving time', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      keepAlive(c);
      final notifier = c.read(recordingControllerProvider.notifier);
      notifier.ensureSession([_route]);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1000)); // ready
      expect(state(c)!.status, RunStatus.ready);

      notifier.beginRun();
      expect(state(c)!.status, RunStatus.running);
      async.elapse(const Duration(seconds: 2));

      final running = state(c)!;
      expect(running.status, RunStatus.running);
      expect(running.distance.meters, greaterThan(0));
      expect(running.elapsed.seconds, closeTo(2, 0.01));
      expect(running.hasUnsavedData, isTrue);
    });
  });

  test('paused time does not count toward performance', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      keepAlive(c);
      final notifier = c.read(recordingControllerProvider.notifier);
      notifier.ensureSession([_route]);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1000));
      notifier.beginRun();
      async.elapse(const Duration(milliseconds: 1000));

      notifier.pause();
      final distanceAtPause = state(c)!.distance.meters;
      final elapsedAtPause = state(c)!.elapsed.seconds;

      async.elapse(const Duration(seconds: 3));
      expect(state(c)!.status, RunStatus.paused);
      expect(state(c)!.distance.meters, distanceAtPause);
      expect(state(c)!.elapsed.seconds, elapsedAtPause);

      notifier.resume();
      async.elapse(const Duration(milliseconds: 500));
      expect(state(c)!.distance.meters, greaterThan(distanceAtPause));
    });
  });

  test('finish completes the run and leaves a gap vs PB', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      keepAlive(c);
      final notifier = c.read(recordingControllerProvider.notifier);
      notifier.ensureSession([_route]);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1000));
      notifier.beginRun();
      async.elapse(const Duration(seconds: 30));

      notifier.finishRun();
      expect(state(c)!.status, RunStatus.finishing);
      async.elapse(const Duration(milliseconds: 500));

      final done = state(c)!;
      expect(done.status, RunStatus.completed);
      expect(done.hasUnsavedData, isFalse);
      expect(done.ghostGap, isNotNull);
    });
  });

  test('dismissing resets the session', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      keepAlive(c);
      final notifier = c.read(recordingControllerProvider.notifier);
      notifier.ensureSession([_route]);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1000));
      notifier.dismissRun();
      expect(state(c), isNull);
      // A fresh session can be started again.
      notifier.ensureSession([_route]);
      async.flushMicrotasks();
      expect(state(c)!.status, RunStatus.preparing);
    });
  });

  test('continue without route clears the ghost', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      keepAlive(c);
      final notifier = c.read(recordingControllerProvider.notifier);
      notifier.ensureSession([_route]);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1000));
      notifier.continueWithoutRoute();
      final ready = state(c)!;
      expect(ready.status, RunStatus.ready);
      expect(ready.route, isNull);
      expect(ready.ghostGap, isNull);
    });
  });
}