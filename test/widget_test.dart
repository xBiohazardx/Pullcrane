import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pullcrane/main.dart';

void main() {
  testWidgets('Bottom navigation shows exercises and can switch to it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Exercises'), findsWidgets);

    await tester.tap(find.text('Exercises').first);
    await tester.pump(const Duration(milliseconds: 300));

    final bool hasEmptyState =
        find.text('No exercises yet.').evaluate().isNotEmpty;
    final bool hasExerciseList = find.byType(ListTile).evaluate().isNotEmpty;
    final bool isLoading =
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    expect(hasEmptyState || hasExerciseList || isLoading, isTrue);
  });
}
