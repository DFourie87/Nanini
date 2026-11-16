import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/employees/employees_repository.dart';
import 'package:nanini_app/features/hours/hours_data.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/hours_repository.dart';
import 'package:nanini_app/features/hours/hours_summary_screen.dart';
import 'package:nanini_app/features/hours/pay_edit.dart';
import 'package:nanini_app/features/hours/pay_run.dart';

final limpo = Farm(id: 'fl', name: 'Farm Limpopodraai - Stockpoort');
final haas = Farm(id: 'fh', name: 'Farm Haaskraal - Swartwater');

Employee worker(String id, String name, Farm farm, PaymentMethod method, {bool? fee, bool column = true}) =>
    Employee(id: id, firstName: name, lastName: '', farmId: farm.id, ratePerHour: 30, paymentMethod: method, bankFeeDeduct: fee, hasBankFeeColumn: column);

HoursEntry day(String emp) => HoursEntry(
  id: 'h$emp',
  employeeId: emp,
  date: '2026-11-10',
  hours: 10,
  rate: 30,
  dailyThreshold: 9,
  otMultiplier: 1.5,
  normalHours: 10,
  otHours: 0,
  gross: 300,
);

/// The database: saves the bank fee choice.
class _Repo extends EmployeesRepository {
  _Repo(this.rows);
  final Map<String, Employee> rows;

  @override
  Future<Employee?> updatePay(String id, {double? ratePerHour, double? rentDeduction, double? loanDeduction, bool? uifDeduct, bool? bankFeeDeduct}) async =>
      rows[id] = rows[id]!.copyWithPay(bankFeeDeduct: bankFeeDeduct);
}

class _Data extends HoursData {
  _Data(List<Employee> e)
    : db = _Repo({for (final x in e) x.id: x}),
      super.forTest(HoursRepository(), employees: e, entries: [for (final x in e) day(x.id)], farms: [limpo, haas]);
  final _Repo db;
  @override
  EmployeesRepository get employeesRepo => db;
}

void main() {
  final workers = [
    worker('cash', 'Thabo', haas, PaymentMethod.cash),
    worker('eft', 'Eft', haas, PaymentMethod.bank),
    worker('atm', 'Atm', haas, PaymentMethod.atm),
    worker('chosen', 'Chosen', haas, PaymentMethod.bank, fee: true),
    worker('waived', 'Waived', haas, PaymentMethod.cash, fee: false),
    worker('limpo', 'Limpo', limpo, PaymentMethod.cash),
    worker('old', 'Old', haas, PaymentMethod.cash, column: false),
  ];
  List<PayLine> run(List<Employee> e) => buildPayRun(
    payUpTo: '2026-11-15',
    employees: e,
    entries: [for (final x in e) day(x.id)],
    kgEntries: const [],
    purchases: const [],
    payslips: const [],
    bankFeeFarms: bankFeeFarmIds([limpo, haas]),
  );

  test('Haaskraal: R110 off the pay of those paid in cash, unless chosen otherwise; nowhere else', () {
    expect(bankFeeFarmIds([limpo, haas]), {'fh'});
    final fee = {for (final l in run(workers)) l.employee.id: l.bankFee};
    expect(fee, {'cash': 110.0, 'eft': 0.0, 'atm': 0.0, 'chosen': 110.0, 'waived': 0.0, 'limpo': 0.0, 'old': 0.0});
    final cash = run(workers).firstWhere((l) => l.employee.id == 'cash');
    expect(cash.deductions, 110);
    expect(cash.nett, 300 - 110);
  });

  test('the payslip keeps the bank fee: in the deductions and the nett, saved only when taken', () {
    final lines = run(workers);
    final cash = draftPayslip(lines.firstWhere((l) => l.employee.id == 'cash'), upTo: '2026-11-15', paidDate: '2026-11-15');
    expect(cash.bankFee, 110);
    expect(cash.totalDeductions, 110);
    expect(cash.nett, 190);
    expect(cash.toInsert()['bank_fee'], 110);
    final eft = draftPayslip(lines.firstWhere((l) => l.employee.id == 'eft'), upTo: '2026-11-15', paidDate: '2026-11-15');
    expect(eft.toInsert().containsKey('bank_fee'), isFalse);
    final read = Payslip.fromJson({...cash.toInsert(), 'id': 'p', 'created_at': '2026-11-15T10:00:00'});
    expect(read.bankFee, 110);
    expect(Employee.fromJson({'id': 'x', 'bank_fee_deduct': false}).hasBankFeeColumn, isTrue);
    expect(Employee.fromJson({'id': 'x'}).hasBankFeeColumn, isFalse);
  });

  testWidgets('Summary: the fee in the sum; its Yes/No in the edit, below UIF, and saved', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final shown = [workers[0], workers[1], workers[5]]; // Thabo (cash), Eft (Haaskraal), Limpo
    final data = _Data(shown);
    final lines = run(shown);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HoursSummaryScreen(data: data, lines: lines, scopeBar: const SizedBox(), payUpTo: DateTime(2026, 11, 15), farmName: null),
        ),
      ),
    );
    expect(find.textContaining('Bank fee R110'), findsNothing); // not under the names
    expect(find.text('R190'), findsWidgets); // Thabo: R300 less the fee (and the totals' cash)
    // Opened: the fee is a line of the sum.
    await tester.tap(find.text('Thabo'));
    await tester.pumpAndSettle();
    expect(find.text('Bank fee'), findsOneWidget);

    // The edit: Bank fee R110 below UIF, on for Thabo (paid in cash).
    Future<void> openEdit(String id) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => showPayLineEditor(c, data, lines.firstWhere((l) => l.employee.id == id), DateTime(2026, 11, 15)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await openEdit('cash');
    final fee = find.byKey(const Key('pay_edit_bank_fee'));
    expect(fee, findsOneWidget);
    expect(tester.getTopLeft(find.text('UIF')).dy, lessThan(tester.getTopLeft(fee).dy));
    expect(find.text('Deducted: R110 · paid in cash'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(fee).value, isTrue);
    await tester.tap(fee);
    await tester.pumpAndSettle();
    expect(data.db.rows['cash']!.bankFeeDeduct, isFalse);
    expect(data.employees!.firstWhere((e) => e.id == 'cash').bankFeeDeducted, isFalse);
    expect(find.text('Not deducted · paid in cash'), findsOneWidget);
    Navigator.of(tester.element(fee)).pop();
    await tester.pumpAndSettle();

    // Limpopodraai: no bank fee in the edit.
    await openEdit('limpo');
    expect(find.byKey(const Key('pay_edit_bank_fee')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
