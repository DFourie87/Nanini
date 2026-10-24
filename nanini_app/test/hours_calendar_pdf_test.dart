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

  test('hours calendar by work group: a page per group, hours on any farm', () async {
    final field = [for (var i = 1; i <= 4; i++) Employee(id: 'f$i', firstName: 'Field$i', lastName: '', surname: 'Worker')];
    final pack = [for (var i = 1; i <= 3; i++) Employee(id: 'p$i', firstName: 'Pack$i', lastName: '', surname: 'Worker')];
    final entries = [
      for (var d = 19; d <= 31; d++)
        if (DateTime(2026, 10, d).weekday <= DateTime.saturday) ...[
          for (final e in field) h(e.id, '2026-10-$d', 9),
          for (final e in pack) h(e.id, '2026-10-$d', 10.5),
        ],
    ];
    final doc = await buildCalendarsPdf(
      sections: [('Potatoes - field', field), ('Potatoes - packhouse', pack)],
      from: DateTime(2026, 10, 15),
      to: DateTime(2026, 10, 31),
      entries: entries,
    );
    final bytes = await doc.save();
    // One page per group.
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length, 2);
    final out = Platform.environment['GROUP_CAL_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
