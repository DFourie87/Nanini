import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/pay_run.dart';

void main() {
  test('members: salary paid in their own group; not on payroll: left out', () {
    final farm = Farm(id: 'fa', name: 'Limpopodraai');
    final employees = [
      Employee(id: 'w', firstName: 'Anna', lastName: '', farmId: 'fa', ratePerHour: 30),
      Employee(id: 'd', firstName: 'Dereck', lastName: '', surname: 'Fourie', farmId: 'fa', isMember: true, monthlySalary: 20000),
      Employee(id: 't', firstName: 'Thys', lastName: '', surname: 'Fourie', farmId: 'fa', isMember: true, onPayroll: false, monthlySalary: 9999),
    ];
    final lines = buildPayRun(payUpTo: '2026-09-30', employees: employees, entries: const [], kgEntries: const [], purchases: const [], payslips: const [], includeAll: true);
    expect(lines.map((l) => l.employee.id), unorderedEquals(['w', 'd']));
    final dereck = lines.firstWhere((l) => l.employee.id == 'd');
    expect(dereck.salary, 20000);
    expect(dereck.gross, 20000);
    expect(byFarm(lines, [farm]).single.$2.map((l) => l.employee.id), ['w']);
    expect(membersOf(lines).map((l) => l.employee.id), ['d']);
  });

  test('member columns are only saved once the database has them', () {
    final e = Employee(id: 'w', firstName: 'Anna', lastName: '');
    expect(e.toUpdate().containsKey('is_member'), isFalse);
    final m = Employee.fromJson({'id': 'd', 'first_name': 'Dereck', 'is_member': true, 'on_payroll': true, 'monthly_salary': 20000});
    expect(m.isMember, isTrue);
    expect(m.toUpdate()['monthly_salary'], 20000);
  });
}
