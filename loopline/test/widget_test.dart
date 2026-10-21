// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loopline/main.dart';

void main() {
  testWidgets('shows the forex source option in the source selector', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ArbitrageApp());

    expect(find.text('Finnhub FX'), findsOneWidget);
  });

  testWidgets('loads the selected sample scenario', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ArbitrageApp());

    await tester.scrollUntilVisible(
      find.text('Sample data'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    final sampleSelector = find.byType(DropdownButtonFormField<String>);
    await tester.tap(sampleSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consistent FX').last);
    await tester.pumpAndSettle();

    final loadButton = find.text('Load selected sample');
    await tester.ensureVisible(loadButton);
    await tester.tap(loadButton);
    await tester.pumpAndSettle();

    final detectButton = find.text('Detect');
    await tester.ensureVisible(detectButton);
    await tester.tap(detectButton);
    await tester.pumpAndSettle();

    expect(find.text('No arbitrage found'), findsOneWidget);
  });
}
