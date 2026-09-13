import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_app/app/app.dart';

void main() {
  testWidgets('home shows the primary start action and catalogs', (tester) async {
    await tester.pumpWidget(const GpsApp());
    await tester.pumpAndSettle();

    // Primary action per §43.
    expect(find.widgetWithText(FilledButton, 'Start a run'), findsOneWidget);

    // Section content from the seeded home directory.
    expect(find.text('River Loop'), findsOneWidget);
    expect(find.text('Park 5K'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Hügelrunde'), 200);
    expect(find.text('Hügelrunde'), findsOneWidget);
  });

  testWidgets('shell navigates between tabs', (tester) async {
    await tester.pumpWidget(const GpsApp());
    await tester.pumpAndSettle();

    Finder tab(String label) =>
        find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

    await tester.tap(tab('Routes'));
    await tester.pumpAndSettle();
    expect(find.text('Route library lands with M12.'), findsOneWidget);

    await tester.tap(tab('Record'));
    await tester.pumpAndSettle();
    expect(find.text('Recording arrives with M6'), findsOneWidget);

    await tester.tap(tab('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Start a run'), findsOneWidget);
  });

  testWidgets('start a run routes to pre-run screen', (tester) async {
    await tester.pumpWidget(const GpsApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Start a run'));
    await tester.pumpAndSettle();
    expect(find.text('Recording arrives with M6'), findsOneWidget);
  });
}