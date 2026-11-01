import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/auth/app_user.dart';
import 'package:nanini_app/core/auth/session.dart';
import 'package:nanini_app/features/employees/employee_form.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:provider/provider.dart';

void main() {
  final farms = [Farm(id: 'fa', name: 'Farm Limpopodraai - Stockpoort')];
  Employee? saved;

  Future<void> open(WidgetTester tester, {Employee? existing, bool member = false}) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final session = Session()..currentUser = AppUser(id: 'a', username: 'admin', displayName: 'Admin', role: 'admin');
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => saved = await showEmployeeForm(context, existing: existing, groups: const [], farms: farms, emp201Column: true, member: member),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Add employee: clear sections, no member tickbox, paid by chosen in the form', (tester) async {
    await open(tester);
    expect(find.text('Add employee'), findsOneWidget);
    for (final s in ['PERSON', 'WORK', 'PAY', 'SARS']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    expect(find.text('Member of Nanini 121 CC'), findsNothing);
    expect(find.textContaining('everyone knows'), findsNothing); // no long descriptions
    await tester.enterText(find.widgetWithText(TextField, 'Known as *'), 'Sipho');
    // How they're paid must be chosen.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Choose how they are paid: Bank, ATM or Cash.'), findsOneWidget);
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ATM'));
    await tester.pumpAndSettle();
    expect(find.text('Phone number *'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Phone number *'), '0820000000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.firstName, 'Sipho');
    expect(saved?.paymentMethod, PaymentMethod.atm);
    expect(saved?.isMember, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A member (from the Members list): salary and On payroll, no group or paid-by choice', (tester) async {
    await open(tester, member: true);
    expect(find.text('Add member'), findsOneWidget);
    expect(find.text('On payroll'), findsOneWidget);
    expect(find.text('Monthly salary'), findsOneWidget);
    expect(find.text('Cash'), findsNothing);
    expect(find.text('Group'), findsNothing);
  });
}
