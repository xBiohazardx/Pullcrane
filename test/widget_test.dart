import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pullcrane/main.dart';

void main() {
  testWidgets('Bottom navigation shows benchmark and can switch to it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Benchmark'), findsOneWidget);

    await tester.tap(find.text('Benchmark'));
    await tester.pump(const Duration(milliseconds: 300));

    final bool hasEmptyState =
        find.text('No exercises available for benchmark.').evaluate().isNotEmpty;
    final bool hasExerciseList = find.byType(ListTile).evaluate().isNotEmpty;
    final bool isLoading =
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    expect(hasEmptyState || hasExerciseList || isLoading, isTrue);
  });
}
