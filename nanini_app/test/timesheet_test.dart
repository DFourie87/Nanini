import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
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

  test('Timesheets: ordinary work for the farm, and a sheet per group paid at its own tariff', () {
    final sheets = timesheetsFor(farm, employees, groups, DateTime(2026, 11));
    expect(sheets.map((s) => s.title), ['Ordinary work', 'Potatoes - packhouse']);
    // Hourly workers of the farm only: not members, monthly salaries, or gone by the 1st; by surname.
    expect(sheets[0].workers.length, 23);
    expect(sheets[0].workers.first.surname, 'SurnameD');
    expect(sheets[1].workers.map((e) => e.firstName), ['Thabo']);
    // Hours only: no tariffs on the sheets.
    expect(sheets.map((s) => s.subtitle), ['All hours worked, except in Potatoes - packhouse (on its own sheet)', 'Only hours worked in this work group']);
  });

  test('Timesheets PDF: 20 workers a page, 5 empty lines; a QR code per page', () async {
    final sheets = timesheetsFor(farm, employees, groups, DateTime(2026, 11));
    final doc = await buildTimesheetsPdf(farmName: 'Limpopodraai', farmId: farm.id, month: DateTime(2026, 11), sheets: sheets);
    final bytes = await doc.save();
    // Ordinary: 23 + 5 empty = 28 rows -> 2 pages; potatoes: 1 + 5 -> 1 page.
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length, 3);
    expect(timesheetCode(month: DateTime(2026, 11), farmId: farm.id, page: 1, pages: 2, rows: sheets[0].workers.take(2).toList()),
        'NTS1|2026-11|farm-lim|-|1/2|worker-0,worker-0');
    final out = Platform.environment['TIMESHEET_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
