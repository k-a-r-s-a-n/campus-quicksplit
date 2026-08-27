import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:campus_quicksplit/main.dart';

void main() {
  testWidgets('App launches and drains splash screen timers', (WidgetTester tester) async {
    final appProvider = AppProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: appProvider,
        child: const CampusQuickSplitApp(),
      ),
    );

    expect(find.byType(CampusQuickSplitApp), findsOneWidget);

    // Pump and settle all async timers (typewriter delays + animations)
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}