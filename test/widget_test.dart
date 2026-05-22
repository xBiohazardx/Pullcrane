import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pullcrane/main.dart';

void main() {
  testWidgets('Bottom navigation shows benchmark and can switch to it', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Benchmark'), findsOneWidget);

    await tester.tap(find.text('Benchmark'));
    await tester.pumpAndSettle();

    expect(find.text('No exercises available for benchmark.'), findsOneWidget);
  });
}
