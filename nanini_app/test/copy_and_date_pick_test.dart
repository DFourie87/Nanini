import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/widgets/confirm_dialog.dart';
import 'package:nanini_app/core/widgets/date_pick.dart';
import 'package:nanini_app/core/widgets/dialog_error.dart';

void main() {
  testWidgets('pop-up messages: selectable, and Copy puts the title and message on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => Column(
              children: [
                TextButton(
                  onPressed: () => showProblem(c, 'Xero refused 4 invoices', title: 'Xero'),
                  child: const Text('problem'),
                ),
                TextButton(
                  onPressed: () => confirmDialog(c, message: 'Send 12 invoices?'),
                  child: const Text('confirm'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('problem'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SelectableText, 'Xero refused 4 invoices'), findsOneWidget);
    await tester.tap(find.byKey(const Key('copy_message')));
    await tester.pumpAndSettle();
    expect(copied, 'Xero\n\nXero refused 4 invoices');
    expect(find.text('Copied'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('confirm'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SelectableText, 'Send 12 invoices?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('copy_message')));
    await tester.pumpAndSettle();
    expect(copied, 'Are you sure?\n\nSend 12 invoices?');
  });

  testWidgets('date picker: one click selects (OK to choose), a double-click on a day chooses it at once', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () async => picked = await pickDate(c, initialDate: DateTime(2026, 11, 1), firstDate: DateTime(2026, 8, 29), lastDate: DateTime(2100)),
              child: const Text('pick'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget); // still open
    await tester.tap(find.byKey(const Key('pick_date_ok')));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2026, 11, 12));

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsNothing); // closed on the double-click
    expect(picked, DateTime(2026, 11, 20));
  });
}
