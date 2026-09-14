import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_app/app/app.dart';

void main() {
  Finder tab(String label) =>
      find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

  testWidgets('Routes tab lists the route library with stats', (tester) async {
    await tester.pumpWidget(const GpsApp());
    await tester.pumpAndSettle();

    await tester.tap(tab('Routes'));
    await tester.pumpAndSettle();

    expect(find.text('River Loop'), findsOneWidget);
    expect(find.text('Park 5K'), findsOneWidget);
    expect(find.text('Hügelrunde'), findsOneWidget);
    expect(find.textContaining('runs'), findsNWidgets(3));
    expect(find.text('PB'), findsNWidgets(3));
  });

  testWidgets('tapping a route card opens its detail', (tester) async {
    await tester.pumpWidget(const GpsApp());
    await tester.pumpAndSettle();

    await tester.tap(tab('Routes'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('River Loop'));
    await tester.pumpAndSettle();

    // §23 blocks.
    expect(find.text('Personal Best'), findsOneWidget);
    expect(find.text('Average'), findsOneWidget);
    expect(find.text('Last'), findsOneWidget);
    expect(find.text('Performance'), findsOneWidget);

    // The seeded PB clocks in at 24:30.
    expect(find.text('24:30'), findsOneWidget);

    // Scroll down to the Attempts section which may be below the fold.
    await tester.dragUntilVisible(
      find.text('Attempts'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.text('Attempts'), findsOneWidget);
    expect(find.text('Yesterday'), findsWidgets);
  });
}