import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/members_auto_pay.dart';

void main() {
  test('last Friday of the month', () {
    expect(lastFridayOf(2026, 10), DateTime(2026, 10, 30));
    expect(lastFridayOf(2026, 11), DateTime(2026, 11, 27));
    expect(lastFridayOf(2027, 1), DateTime(2027, 1, 29));
  });

  test('members payday: first on 30 Sep 2026, then the last Friday of each month', () {
    expect(membersPayday(DateTime(2026, 9, 29)), isNull);
    expect(membersPayday(DateTime(2026, 9, 30)), '2026-09-30');
    expect(membersPayday(DateTime(2026, 10, 6)), '2026-09-30');
    expect(membersPayday(DateTime(2026, 10, 29)), '2026-09-30');
    expect(membersPayday(DateTime(2026, 10, 30)), '2026-10-30');
    expect(membersPayday(DateTime(2026, 11, 26)), '2026-10-30');
    expect(membersPayday(DateTime(2026, 11, 27)), '2026-11-27');
  });

  group('members due', () {
    final dereck = Employee(id: 'd', firstName: 'Dereck', lastName: 'Fourie', farmId: 'fa', isMember: true, monthlySalary: 30000, paymentMethod: PaymentMethod.bank);
    final jm = Employee(id: 'jm', firstName: 'JM', lastName: 'Fourie', farmId: 'fa', isMember: true, onPayroll: false);
    final worker = Employee(id: 'w', firstName: 'Anna', lastName: '', farmId: 'fa', ratePerHour: 30);
    Payslip slip(String emp, String end) => Payslip(
          id: emp + end,
          employeeId: emp,
          farmId: 'fa',
          periodStart: end,
          periodEnd: end,
          paidDate: end,
          gross: 100,
          hoursWorked: 0,
          paye: 0,
          uif: 0,
          rent: 0,
          loan: 0,
          tuckshopDeduction: 0,
          nett: 100,
          createdAt: DateTime(2026),
        );

    test('September: the fixed salary, paid 30 Sep, for the month', () {
      // The farm's workers were paid on 3 Oct: not the members' last pay.
      final due = membersDue(today: DateTime(2026, 10, 6), employees: [dereck, jm, worker], payslips: [slip('w', '2026-10-03')]);
      expect(due.length, 1);
      final p = due.single;
      expect(p.employeeId, 'd');
      expect(p.paidDate, '2026-09-30');
      expect(p.periodStart, '2026-09-01');
      expect(p.periodEnd, '2026-09-30');
      expect(p.gross, 30000);
      expect(p.paye, greaterThan(0));
    });

    test('never twice a month; October follows on from September', () {
      expect(membersDue(today: DateTime(2026, 10, 20), employees: [dereck], payslips: [slip('d', '2026-09-30')]), isEmpty);
      final oct = membersDue(today: DateTime(2026, 10, 30), employees: [dereck], payslips: [slip('d', '2026-09-30')]).single;
      expect(oct.periodStart, '2026-10-01');
      expect(oct.periodEnd, '2026-10-30');
      // Run by hand earlier in October: not again on the last Friday.
      expect(membersDue(today: DateTime(2026, 10, 30), employees: [dereck], payslips: [slip('d', '2026-10-28')]), isEmpty);
    });

    test('nothing before the first payday', () {
      expect(membersDue(today: DateTime(2026, 9, 25), employees: [dereck], payslips: const []), isEmpty);
    });
  });
}
