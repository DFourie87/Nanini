import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/hours_payslip_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HoursEntry h(String emp, String date, double hours) => HoursEntry(
      id: '$emp$date', employeeId: emp, date: date, hours: hours, rate: 30, dailyThreshold: 9, otMultiplier: 1.5, normalHours: hours, otHours: 0, gross: hours * 30);

  test('hours calendar: a column per calendar date of the pay period, totals', () async {
    final employees = [
      Employee(id: 'a', firstName: 'Annie', lastName: '', surname: 'Mokoena', idOrPassport: '8505055009081'),
      Employee(id: 'b', firstName: 'Ben', lastName: 'Sithole'),
    ];
    final entries = [
      for (var d = 1; d <= 30; d++)
        if (DateTime(2026, 9, d).weekday <= DateTime.friday) ...[h('a', '2026-09-${d.toString().padLeft(2, '0')}', 8), if (d.isEven) h('b', '2026-09-${d.toString().padLeft(2, '0')}', 7.5)],
      h('a', '2026-08-31', 9), // before the period: left out
      h('x', '2026-09-02', 9), // not on this farm: left out
    ];
    // A pay period over two months: 15 Sep to 14 Oct.
    final doc = await buildCalendarPdf(farmName: 'Limpopodraai', from: DateTime(2026, 9, 15), to: DateTime(2026, 10, 14), employees: employees, entries: [
      ...entries,
      for (var d = 1; d <= 14; d++)
        if (DateTime(2026, 10, d).weekday <= DateTime.friday) h('a', '2026-10-${d.toString().padLeft(2, '0')}', 8),
    ]);
    final bytes = await doc.save();
    expect(bytes.length, greaterThan(1000));
    final out = Platform.environment['CAL_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
