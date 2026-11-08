import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/employees/employees_repository.dart';
import 'package:nanini_app/features/hours/hours_data.dart';
import 'package:nanini_app/features/hours/hours_repository.dart';
import 'package:nanini_app/features/hours/pay_edit.dart';
import 'package:nanini_app/features/hours/pay_run.dart';

/// The database: saves the rent, or (refuse) changes no row.
class _Repo extends EmployeesRepository {
  _Repo(this.rows);
  final Map<String, Employee> rows;
  bool refuse = false;

  @override
  Future<Employee?> updatePay(String id, {double? ratePerHour, double? rentDeduction, double? loanDeduction, bool? uifDeduct}) async {
    if (refuse || rows[id] == null) return null;
    return rows[id] = rows[id]!.copyWithPay(ratePerHour: ratePerHour, rentDeduction: rentDeduction, loanDeduction: loanDeduction, uifDeduct: uifDeduct);
  }
}

class _Data extends HoursData {
  _Data(List<Employee> e)
      : db = _Repo({for (final x in e) x.id: x}),
        super.forTest(HoursRepository(), employees: e, entries: const []);
  final _Repo db;
  @override
  EmployeesRepository get employeesRepo => db;
}

void main() {
  final anna = Employee(id: 'a', firstName: 'Anna', lastName: '', farmId: 'f', ratePerHour: 30, rentDeduction: 200);

  Future<_Data> openRent(WidgetTester tester) async {
    final data = _Data([anna]);
    final line = PayLine(employee: anna, since: null, entries: const [], kgEntries: const [], purchases: const []);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => showPayLineEditor(c, data, line, DateTime(2026, 9, 27)), child: const Text('open')))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('R200'), findsOneWidget);
    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    return data;
  }

  testWidgets('Summary: a new rent is saved and shown at once (and kept for the pay)', (tester) async {
    final data = await openRent(tester);
    await tester.enterText(find.byType(TextField), '350');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(data.db.rows['a']!.rentDeduction, 350);
    expect(data.employees!.single.rentDeduction, 350);
    expect(find.text('R350'), findsOneWidget);
    // Opened again: the saved amount, not the old one.
    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '350'), findsOneWidget);
  });

  testWidgets('Summary: rent the database didn\'t save -- says so, dialog stays open', (tester) async {
    final data = await openRent(tester);
    data.db.refuse = true;
    await tester.enterText(find.byType(TextField), '350');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Not saved'), findsOneWidget);
    expect(data.employees!.single.rentDeduction, 200);
  });
}
