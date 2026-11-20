import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/xero/xero_export_screen.dart';

void main() {
  testWidgets('Changed since sent to Xero: "Fixed in Xero" takes them off the list, OK leaves them', (tester) async {
    bool? fixed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () async => fixed = await showChangedSinceSent(c, {'103593 (Grow Green Network)', 'IN160836 (Grow Green Network)'}, nothingNew: true),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Changed since sent to Xero'), findsOneWidget);
    expect(find.textContaining('103593 (Grow Green Network)'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(fixed, isFalse);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('xero_changed_fixed')));
    await tester.pumpAndSettle();
    expect(fixed, isTrue);
    expect(find.text('Changed since sent to Xero'), findsNothing);
  });

  test('the export\'s period at first: the financial year (from 1 March, not before the conversion date) to today', () {
    expect(xeroDefaultPeriod(DateTime(2026, 11, 20, 15, 30)), (DateTime(2026, 8, 29), DateTime(2026, 11, 20)));
    expect(xeroDefaultPeriod(DateTime(2027, 2, 10)), (DateTime(2026, 8, 29), DateTime(2027, 2, 10)));
    expect(xeroDefaultPeriod(DateTime(2027, 3, 1)), (DateTime(2027, 3, 1), DateTime(2027, 3, 1)));
    expect(xeroDefaultPeriod(DateTime(2027, 7, 4)), (DateTime(2027, 3, 1), DateTime(2027, 7, 4)));
  });
}
