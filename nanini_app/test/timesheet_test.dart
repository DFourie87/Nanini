import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/formatters.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/timesheet_pdf.dart';

Employee worker(String id, String first, String surname, {String farm = 'farm-limpo', String? group, bool member = false, String? left, double? salary}) =>
    Employee(id: id, firstName: first, lastName: surname, surname: surname, farmId: farm, currentGroupId: group, isMember: member, leftOn: left, monthlySalary: salary);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final farm = Farm(id: 'farm-limpo', name: 'Limpopodraai');
  final groups = [
    EmployeeGroup(id: 'group-potato', name: 'Potatoes - packhouse', farmId: 'farm-limpo', ratePerHour: 28.5),
    EmployeeGroup(id: 'group-plain', name: 'Tractor drivers', farmId: 'farm-limpo'),
  ];
  final employees = [
    for (var i = 0; i < 23; i++) worker('worker-${i.toString().padLeft(3, '0')}', 'Name$i', 'Surname${String.fromCharCode(90 - i)}'),
    worker('potato-01', 'Thabo', 'Baloyi', farm: 'farm-haas', group: 'group-potato'), // from another farm
    worker('member-01', 'Anna', 'Member', member: true),
    worker('salary-01', 'Piet', 'Salaried', salary: 9000),
    worker('gone-001', 'Jan', 'Left', left: '2026-10-15'),
  ];

  test('Timesheets: one list for the farm, or a sheet per work group (harvest time)', () {
    // Normally one list: everyone who works on the farm -- with the potato
    // packer paid at Haaskraal (in a Limpopodraai group).
    final one = timesheetsFor(farm, employees, groups, DateTime(2026, 11));
    expect(one.map((s) => s.workers.length), [24]);
    expect(one.single.workers.map((e) => e.firstName), contains('Thabo'));
    // ...and not on Haaskraal's, where he's paid.
    final haaskraal = timesheetsFor(Farm(id: 'farm-haas', name: 'Haaskraal'), employees, groups, DateTime(2026, 11));
    expect(haaskraal.single.workers, isEmpty);
    // Harvest time: a sheet per work group with members, and the rest.
    final sheets = timesheetsFor(farm, employees, groups, DateTime(2026, 11), byGroup: true);
    expect(sheets.map((s) => s.title), ['Potatoes - packhouse', 'Not in a work group']);
    // Hourly workers of the farm only: not members, monthly salaries, or gone by the 1st; by surname.
    expect(sheets[1].workers.length, 23);
    expect(sheets[1].workers.first.surname, 'SurnameD');
    expect(sheets[0].workers.map((e) => e.firstName), ['Thabo']);
    // Hours only: no tariffs on the sheets.
    expect(sheets.map((s) => s.subtitle), ['Only hours worked in this work group', 'Hours of the workers in none of the groups']);
  });

  test('Timesheet days: the day after the previous payroll to the last Friday of the month', () {
    String r(List<DateTime> d) => '${toDateStr(d.first)}..${toDateStr(d.last)} (${d.length})';
    // October 2026: paid up to Friday 25 Sep -> 26 Sep to Friday 30 Oct.
    expect(r(timesheetDays(DateTime(2026, 10), paidUpTo: ['2026-08-28', '2026-09-25'])), '2026-09-26..2026-10-30 (35)');
    // November, October's payroll run (up to 30 Oct): 31 Oct to Friday 27 Nov.
    expect(r(timesheetDays(DateTime(2026, 11), paidUpTo: ['2026-09-25', '2026-10-30'])), '2026-10-31..2026-11-27 (28)');
    // November printed before October's payroll: still from after October's last Friday.
    expect(r(timesheetDays(DateTime(2026, 11), paidUpTo: ['2026-09-25'])), '2026-10-31..2026-11-27 (28)');
    // Paid up to the day before the last Friday (Thursday 29 Oct): from Friday 30 Oct.
    expect(r(timesheetDays(DateTime(2026, 11), paidUpTo: ['2026-09-30', '2026-10-29'])), '2026-10-30..2026-11-27 (29)');
    // Paid up to Wednesday 30 Sep (Haaskraal): October's sheet from 1 Oct.
    expect(r(timesheetDays(DateTime(2026, 10), paidUpTo: ['2026-09-30'])), '2026-10-01..2026-10-30 (30)');
    // A payroll run later than the last Friday (up to Sunday 1 Nov): from the Monday.
    expect(r(timesheetDays(DateTime(2026, 11), paidUpTo: ['2026-11-01'])), '2026-11-02..2026-11-27 (26)');
    // October's own payroll (up to its last day) doesn't empty October's sheet.
    expect(r(timesheetDays(DateTime(2026, 10), paidUpTo: ['2026-09-25', '2026-10-30'])), '2026-09-26..2026-10-30 (35)');
    // No payroll yet: from after the previous month's last Friday.
    expect(r(timesheetDays(DateTime(2027, 1))), '2026-12-26..2027-01-29 (35)');
  });

  test('Timesheets PDF: 20 workers a page, 20 empty lines; a QR code per page', () async {
    final sheets = timesheetsFor(farm, employees, groups, DateTime(2026, 11), byGroup: true);
    final doc = await buildTimesheetsPdf(farmName: 'Limpopodraai', farmId: farm.id, month: DateTime(2026, 11), sheets: sheets);
    final bytes = await doc.save();
    // Potatoes: 1 + 20 empty -> 2 pages; the rest: 23 + 20 = 43 rows -> 3 pages.
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length, 5);
    expect(
        timesheetCode(
            month: DateTime(2026, 11), days: timesheetDays(DateTime(2026, 11)), farmId: farm.id, page: 1, pages: 3, rows: sheets[1].workers.take(2).toList()),
        'NTS2|2026-11|2026-10-31|2026-11-27|farm-lim|-|1/3|worker-0,worker-0');
    // A farm without work groups of its own (Swartwater): one sheet, its fixed list.
    final swartwater = Farm(id: 'farm-swart', name: 'Swartwater');
    final one = timesheetsFor(swartwater, [worker('swart-001', 'Sipho', 'Maluleke', farm: 'farm-swart')], groups, DateTime(2026, 11));
    expect(one.map((s) => s.workers.length), [1]);
    // Doornbult: its permanent workers; seasonal pickers (paid only per kg in
    // the 3 months before) aren't on it -- one who also worked hours is.
    final doornbult = Farm(id: 'farm-doorn', name: 'Doornbult');
    final staff = [
      worker('perm-001', 'Petrus', 'Mabunda', farm: 'farm-doorn'),
      worker('pick-001', 'Grace', 'Chauke', farm: 'farm-doorn'),
      worker('both-001', 'Lucky', 'Ngobeni', farm: 'farm-doorn'),
    ];
    HoursEntry h(String id, String date) =>
        HoursEntry(id: 'h$id$date', employeeId: id, date: date, hours: 8, rate: 20, dailyThreshold: 9, otMultiplier: 1.5, normalHours: 8, otHours: 0, gross: 160);
    KgEntry k(String id, String date) => KgEntry(id: 'k$id$date', employeeId: id, date: date, kg: 300, ratePerKg: 0.5, gross: 150);
    final d = timesheetsFor(doornbult, staff, groups, DateTime(2026, 11),
        hours: [h('perm-001', '2026-10-10'), h('both-001', '2026-09-03')], kg: [k('pick-001', '2026-10-12'), k('both-001', '2026-10-12'), k('perm-001', '2026-06-01')]);
    expect(d.single.workers.map((e) => e.firstName), ['Petrus', 'Lucky']);
    final out = Platform.environment['TIMESHEET_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
