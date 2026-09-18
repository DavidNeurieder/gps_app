import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_app/app/dependencies.dart';
import 'package:gps_app/app/router.dart';
import 'package:gps_app/core/theme/app_theme.dart';
import 'package:gps_app/engine/models.dart';
import 'package:gps_app/features/dev/application/fixture_export.dart';
import 'package:gps_app/features/dev/presentation/diagnostics_screen.dart';
import 'package:gps_app/features/recording/application/recording_controller.dart';

/// M15 Phase 10: the developer diagnostics entry point and screen.
void main() {
  Widget app() => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routerConfig: buildRouter(),
      );

  test('fixture export matches the M15 fixture schema', () {
    final json = buildFixtureJson(
      route: const [
        GeoPoint(latitude: 52.5, longitude: 13.4),
        GeoPoint(latitude: 52.5, longitude: 13.4005),
      ],
      fixes: [
        TrackPoint(
          position: const GeoPoint(latitude: 52.5, longitude: 13.4),
          timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
        TrackPoint(
          position: const GeoPoint(latitude: 52.5, longitude: 13.4005),
          timestamp: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
        ),
      ],
    );

    final doc = jsonDecode(json) as Map<String, Object?>;
    final route = doc['route']! as List;
    expect(route, hasLength(2));
    expect((route.first as Map)['lat'], 52.5);
    expect((route.first as Map)['lon'], 13.4);

    final fixes = doc['fixes']! as List;
    expect(fixes, hasLength(2));
    final first = fixes.first as Map;
    expect(first['timestamp_ms'], 0);
    expect(first['latitude'], closeTo(52.5, 1e-9));
    expect(first['longitude'], closeTo(13.4, 1e-9));
    expect(first['bearing_deg'], isA<num>());
    // Second fix reports travelling speed; first (no predecessor) does not.
    expect(first.containsKey('speed_mps'), isFalse);
    expect(fixes.last as Map, containsPair('speed_mps', isNot(null)));
  });

  testWidgets('dev button is hidden by default', (tester) async {
    await tester.pumpWidget(ProviderScope(child: app()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dev-diagnostics')), findsNothing);
  });

  testWidgets('dev gate exposes diagnostics and the engine identity',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [devToolsEnabledProvider.overrideWithValue(true)],
      child: app(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Diagnostics'));
    await tester.pumpAndSettle();

    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('ENGINE'), findsOneWidget);
    expect(find.text('fake (deterministic demo)'), findsOneWidget);
  });

  testWidgets('a live run populates the GPS / TRACK / GHOST readouts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [devToolsEnabledProvider.overrideWithValue(true)],
      child: app(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Record'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('START'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byTooltip('Diagnostics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // GPS: the fake engine circles the river loop at 52.5°N.
    expect(
      find.descendant(
        of: find.byType(DiagnosticsScreen),
        matching: find.textContaining('52.5'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byType(DiagnosticsScreen),
        matching: find.text('4:57 /km'),
      ),
      findsOneWidget,
    );
    // TRACK: the run has synthesised session points.
    expect(find.text('Session points'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    // GHOST: River Loop carries a PB, so the live run races one.
    expect(find.text('Racing'), findsOneWidget);
    expect(find.text('yes'), findsOneWidget);
  });

  testWidgets('backgrounding surfaces the recovery snapshot', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [devToolsEnabledProvider.overrideWithValue(true)],
      child: app(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Record'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('START'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Simulate the OS backgrounding the app while the run is live (§28).
    final container = ProviderScope.containerOf(
      tester.element(find.text('PAUSE')),
    );
    container.read(recordingControllerProvider.notifier).appBackgrounded();
    await tester.pump();

    await tester.tap(find.byTooltip('Diagnostics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('PERSISTENCE'), findsOneWidget);
    expect(find.text('running'), findsWidgets);
    expect(find.text('available'), findsOneWidget);
  });

  testWidgets('export writes a schema-valid fixture to the clipboard',
      (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter/platform', JSONMethodCodec()),
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text']! as String);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter/platform', JSONMethodCodec()),
        null,
      );
    });

    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [devToolsEnabledProvider.overrideWithValue(true)],
      child: app(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Record'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('START'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byTooltip('Diagnostics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const ValueKey('export-fixture')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(copied, hasLength(1));
    final doc = jsonDecode(copied.single) as Map<String, Object?>;
    final fixes = doc['fixes']! as List;
    expect(fixes, isNotEmpty);
    expect((doc['route']! as List).length, greaterThanOrEqualTo(2));
    final first = fixes.first as Map;
    expect(first['timestamp_ms'], isA<int>());
    expect(first['latitude'], closeTo(52.5, 0.01));
    expect(first['longitude'], closeTo(13.36, 0.01));
    expect(
      find.text('Fixture JSON copied to clipboard.'),
      findsOneWidget,
    );
  });
}