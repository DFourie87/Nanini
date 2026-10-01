import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/hours_payslip_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HoursEntry h(String emp, String date, double hours) => HoursEntry(
      id: '$emp$date', employeeId: emp, date: date, hours: hours, rate: 30, dailyThreshold: 9, otMultiplier: 1.5, normalHours: hours, otHours: 0, gross: hours * 30);

  test('hours calendar: a column per day of the month, totals', () async {
    final employees = [
      Employee(id: 'a', firstName: 'Annie', lastName: '', surname: 'Mokoena', idOrPassport: '8505055009081'),
      Employee(id: 'b', firstName: 'Ben', lastName: 'Sithole'),
    ];
    final entries = [
      for (var d = 1; d <= 30; d++)
        if (DateTime(2026, 9, d).weekday <= DateTime.friday) ...[h('a', '2026-09-${d.toString().padLeft(2, '0')}', 8), if (d.isEven) h('b', '2026-09-${d.toString().padLeft(2, '0')}', 7.5)],
      h('a', '2026-08-31', 9), // other month: left out
      h('x', '2026-09-02', 9), // not on this farm: left out
    ];
    final doc = await buildCalendarPdf(farmName: 'Limpopodraai', month: DateTime(2026, 9), employees: employees, entries: entries);
    final bytes = await doc.save();
    expect(bytes.length, greaterThan(1000));
    final out = Platform.environment['CAL_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
