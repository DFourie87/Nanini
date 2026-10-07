import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/emp201_year.dart';
import 'package:nanini_app/features/hours/emp201_year_pdf.dart';
import 'package:nanini_app/features/hours/emp201_year_screen.dart';
import 'package:nanini_app/features/hours/emp201_year_sheet.dart';
import 'package:nanini_app/features/hours/emp201_year_xlsx.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/payroll_month.dart';

void main() {
  test('UIF: 1% up to the R17 712 ceiling (R177.12)', () {
    expect(calcUIF(5000), 50);
    expect(calcUIF(29600), closeTo(177.12, 0.001));
    expect(calcUIF(27000), closeTo(177.12, 0.001));
  });

  test('tax year: March to February, named by the year it ends', () {
    expect(taxYearOf(DateTime(2026, 3, 1)), 2027);
    expect(taxYearOf(DateTime(2027, 2, 28)), 2027);
    expect(taxYearOf(DateTime(2026, 2, 28)), 2026);
    final m = taxYearMonths(2027);
    expect(m.first, '2026-03-01');
    expect(m.last, '2027-02-01');
  });

  Payslip slip(String emp, String paid, double gross, double paye) => Payslip(
        id: emp + paid,
        employeeId: emp,
        farmId: 'fa',
        periodStart: paid,
        periodEnd: paid,
        paidDate: paid,
        gross: gross,
        hoursWorked: 0,
        paye: paye,
        uif: calcUIF(gross),
        rent: 0,
        loan: 0,
        tuckshopDeduction: 0,
        nett: gross - paye - calcUIF(gross),
        createdAt: DateTime(2026),
      );
  final employees = [
    Employee(id: 'f', firstName: 'Francois', lastName: 'Fourie', farmId: 'fa', isMember: true, monthlySalary: 29600),
    Employee(id: 'a', firstName: 'Anna', lastName: 'Mokoena', farmId: 'fa'),
  ];
  final history = [
    const Emp201HistoryLine(month: '2026-08-01', name: 'JF FOURIE', employeeId: 'f', salary: 29600, uif: 354.24, sdl: 0, paye: 4577),
    const Emp201HistoryLine(month: '2026-08-01', name: 'Brian', salary: 5600, uif: 112, sdl: 0, paye: 0),
  ];
  final payslips = [
    slip('f', '2026-09-30', 29600, 4577),
    slip('a', '2026-09-12', 2500, 0),
    slip('a', '2026-09-26', 2600, 0),
    slip('a', '2026-08-28', 9999, 0), // August is from the old workbook: not counted
  ];
  final submitted = [const Emp201Submitted(month: '2026-09-01', uif: 456.24, sdl: 0, paye: 4577, submittedOn: '2026-10-07')];

  test('a month from the old workbook, a month from the payslips, and what was submitted', () {
    final year = emp201Year(taxYear: 2027, payslips: payslips, history: history, employees: employees, submitted: submitted, includeSdl: false);
    expect(year.length, 12);
    final aug = year[5];
    expect(aug.month, '2026-08-01');
    expect(aug.fromHistory, isTrue);
    expect(aug.uif, closeTo(466.24, 0.001));
    expect(aug.paye, 4577);
    // Linked: the app's name. Anna isn't in the workbook: listed, not counted.
    expect(aug.lines.map((l) => l.name), ['Anna Mokoena', 'Brian', 'Francois Fourie']);
    expect(aug.counted.map((l) => l.name), ['Brian', 'Francois Fourie']);
    expect(aug.salary, 35200);
    final sep = year[6];
    expect(sep.fromHistory, isFalse);
    expect(sep.employees, 2);
    expect(sep.salary, 34700);
    // UIF: employee and employer -- 177.12 x 2 for Francois (ceiling), 2% of 5 100 for Anna.
    expect(sep.uif, closeTo(354.24 + 102, 0.001));
    expect(sep.paye, 4577);
    expect(sep.difference, 0);
    expect(year[7].difference, isNull); // October: nothing submitted yet
    final withSdl = emp201Year(taxYear: 2027, payslips: payslips, history: history, employees: employees, submitted: submitted, includeSdl: true);
    expect(withSdl[6].sdl, closeTo(347, 0.001));
    expect(withSdl[6].difference, closeTo(-347, 0.001));
  });

  test('EMP501 Excel: one sheet -- employer, reconciliation, then each employee\'s IRP5/IT3(a)', () {
    final year = emp201Year(taxYear: 2027, payslips: payslips, history: history, employees: employees, submitted: submitted, includeSdl: false);
    final x = Excel.decodeBytes(sheetXlsx('EMP501', emp501Sheet(2027, year, interim: false)));
    expect(x.tables.keys, ['EMP501']);
    final rows = x.tables['EMP501']!.rows.map((r) => [for (final c in r) c?.value?.toString()]).toList();
    final firsts = rows.map((r) => r.isEmpty ? null : r.first).toList();
    expect(firsts, containsAll(['PAYE reference', 'Period of reconciliation', 'Reconciliation', 'EMP201 declarations per month']));
    expect(rows.firstWhere((r) => r.isNotEmpty && r.first == 'Period of reconciliation')[1], '202702');
    // Francois as on the IRP5: declared in August (workbook) and September (payslip).
    final irp5 = rows.firstWhere((r) => r.isNotEmpty && r.first == 'Francois Fourie');
    expect(irp5.sublist(1, 4), ['FOURIE', 'F', 'FRANCOIS']);
    expect(irp5.sublist(8, 12), ['2026-08-01', '2026-09-30', '2', 'IRP5']);
    final codes = irp5.sublist(12, 17).map((v) => double.parse(v!)).toList();
    expect(codes[0], 59200); // 3601
    expect(codes[1], 59200); // 3699
    expect(codes[2], 9154); // 4102 PAYE
    expect(codes[3], closeTo(708.48, 0.001)); // 4141 UIF
    expect(codes[4], closeTo(9862.48, 0.001)); // 4149
    // Interim: March to August only.
    final interim = emp501Sheet(2027, year, interim: true);
    expect(interim.first.tables[2].rows.first.cells.length, 1 + 6 + 1);
  });

  test('EMP201: one month -- employer, what to declare, submitted, the employees in three groups', () {
    final year = emp201Year(taxYear: 2027, payslips: payslips, history: history, employees: employees, submitted: submitted, includeSdl: false);
    final sep = emp201MonthSheet(year[6]);
    final rows = [for (final t in sep.first.tables) for (final r in t.rows) r];
    String? textOf(String item) => rows.firstWhere((r) => r.cells.first.text == item).cells[1].text;
    double? numOf(String item) => rows.firstWhere((r) => r.cells.first.text == item).cells[1].number;
    expect(textOf('PAYE reference'), '7470796030');
    expect(textOf('Due by'), '2026-10-07');
    expect(numOf('PAYE'), 4577);
    expect(numOf('UIF -- employees (1%)'), closeTo(228.12, 0.001));
    expect(numOf('UIF -- employer (1%)'), closeTo(228.12, 0.001));
    expect(numOf('Total payable'), closeTo(5033.24, 0.001));
    expect(numOf('Difference (submitted less worked out)'), 0);
    // The employees: three groups.
    expect(sep.last.tables.map((t) => t.heading!.split(' (').first), ['On EMP201', 'Not on EMP201 -- ID/passport on file', 'Not on EMP201 -- no ID/passport']);
    final x = Excel.decodeBytes(sheetXlsx('EMP201', sep));
    expect(x.tables.keys, ['EMP201']);
  });

  test('PDF previews: the EMP201 (portrait) and the EMP501 (landscape)', () async {
    final year = emp201Year(taxYear: 2027, payslips: payslips, history: history, employees: employees, submitted: submitted, includeSdl: false);
    expect((await (await buildSheetPdf(emp201MonthSheet(year[6]), landscape: false)).save()).length, greaterThan(1000));
    final bytes = await (await buildSheetPdf(emp501Sheet(2027, year, interim: false))).save();
    expect(bytes.length, greaterThan(1000));
    final out = Platform.environment['EMP201_PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });

  testWidgets('EMP201 and EMP501 open on their own previews and buttons (no database here)', (tester) async {
    tester.view.physicalSize = const Size(2280, 1080);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    Stream<PdfRaster> fake(Uint8List pdf, List<int>? pages, double dpi) async* {
      for (final _ in pages ?? [0, 1, 2]) {
        final w = (11.69 * dpi).round(), h = (8.27 * dpi).round();
        yield PdfRaster(w, h, Uint8List(w * h * 4));
      }
    }

    Future<void> settle() async {
      for (var n = 0; n < 8; n++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    await tester.pumpWidget(MaterialApp(
        home: TaxReportScreen(
            report: TaxReport.emp201, payslips: payslips, employees: employees, includeSdl: false, month: DateTime(2026, 9), raster: fake)));
    await settle();
    expect(find.textContaining('EMP201 -- September 2026'), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Excel'), findsOneWidget);
    expect(find.text('Interim'), findsNothing);
    await tester.tap(find.text('Submitted'));
    for (var n = 0; n < 4; n++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Submitted on eFiling -- Sep 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(MaterialApp(
        home: TaxReportScreen(report: TaxReport.emp501, payslips: payslips, employees: employees, includeSdl: false, raster: fake)));
    await settle();
    expect(find.textContaining('EMP501'), findsWidgets);
    expect(find.text('Interim'), findsOneWidget);
    expect(find.text('Annual'), findsOneWidget);
    expect(find.text('Submitted'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('EMP201 summary: on EMP201, not on it with an ID, not on it without; only the declared count', () {
    final staff = [
      Employee(id: 'f', firstName: 'Francois', lastName: 'Fourie', farmId: 'fa', idOrPassport: '8001015009087', onEmp201: true),
      Employee(id: 'a', firstName: 'Anna', lastName: 'Mokoena', farmId: 'fa', idOrPassport: 'FN123456', onEmp201: false),
      Employee(id: 'b', firstName: 'Ben', lastName: 'Sithole', farmId: 'fb', onEmp201: false),
    ];
    final slips = [slip('f', '2026-09-30', 29600, 4577), slip('a', '2026-09-12', 2500, 0), slip('a', '2026-09-26', 2600, 0), slip('b', '2026-09-26', 3000, 0)];
    final months = emp201Year(taxYear: 2027, payslips: slips, history: const [], employees: staff, submitted: const [], includeSdl: false);
    final g = emp201YearByEmployee(months);
    expect(g[Emp201Group.declared]!.map((y) => y.key), ['f']);
    expect(g[Emp201Group.notDeclaredWithId]!.single.salary, 5100);
    expect(g[Emp201Group.notDeclaredWithId]!.single.uif, 51); // taken off their pay, not doubled
    expect(g[Emp201Group.notDeclaredNoId]!.single.name, 'Ben Sithole');
    expect(g[Emp201Group.declared]!.single.months['2026-09-01']!.uif, closeTo(354.24, 0.001));
    // The EMP201: Francois only.
    final e = Emp201(DateTime(2026, 9), declaredSlips(slips, staff), includeSdl: false);
    expect(e.employees, 1);
    expect(e.remuneration, 29600);
    final year = emp201Year(taxYear: 2027, payslips: slips, history: const [], employees: staff, submitted: const [], includeSdl: false);
    expect(year[6].employees, 1);
    // Before emp201_declared.sql (no column): everyone counts, as before.
    expect(Employee(id: 'x', firstName: 'X', lastName: '').declared, isTrue);
  });

  test('registered (e.g. for UIF) on a day: in the EMP201 group, counted only from that day', () {
    final staff = [Employee(id: 'a', firstName: 'Anna', lastName: 'Mokoena', farmId: 'fa', idOrPassport: 'FN1', onEmp201: true, emp201From: '2026-09-20')];
    final slips = [slip('a', '2026-08-28', 2400, 0), slip('a', '2026-09-12', 2500, 0), slip('a', '2026-09-26', 2600, 0)];
    final year = emp201Year(taxYear: 2027, payslips: slips, history: const [], employees: staff, submitted: const [], includeSdl: false);
    final aug = year[5], sep = year[6];
    expect(aug.employees, 0); // before: not declared
    expect(aug.uif, 0);
    expect(sep.salary, 2600); // only the pay from the 20th
    expect(sep.uif, closeTo(52, 0.001));
    final g = emp201YearByEmployee(year);
    final anna = g[Emp201Group.declared]!.single;
    expect(anna.months['2026-08-01']!.salary, 2400); // the salary still shows
    expect(anna.months['2026-08-01']!.dUif, 0);
    expect(anna.months['2026-08-01']!.withheldNotDeclared, isTrue); // UIF taken off before registered
    expect(declaredSlips(slips, staff).map((p) => p.paidDate), ['2026-09-26']);
  });

  test('date of birth from a South African ID number; none from a passport', () {
    expect(dobFromSaId('7205166148088'), '1972-05-16');
    expect(dobFromSaId('0101015009087'), '2001-01-01');
    expect(dobFromSaId('FN123456'), isNull);
  });

  test('EMP501 reconciliation: certificates against the EMP201s declared, month by month', () {
    final year = emp201Year(taxYear: 2027, payslips: payslips, history: history, employees: employees, submitted: submitted, includeSdl: false);
    final recon = emp501Sheet(2027, year, interim: false).first;
    expect(recon.tables[1].heading, 'Reconciliation');
    final rows = recon.tables[1].rows;
    // PAYE: Francois 4577 in August (workbook) and September; September as submitted.
    expect(rows[1].cells.first.text, 'PAYE');
    expect(rows[1].cells[1].number, 9154);
    expect(rows[1].cells[2].number, 9154);
    expect(rows[1].cells[3].number, 0);
    // Submitted different from worked out: the difference shows.
    final off = emp201Year(
        taxYear: 2027,
        payslips: payslips,
        history: history,
        employees: employees,
        submitted: const [Emp201Submitted(month: '2026-09-01', uif: 456.24, sdl: 0, paye: 4500)],
        includeSdl: false);
    expect(emp501Sheet(2027, off, interim: false).first.tables[1].rows[1].cells[3].number, 77);
    // Per month: what was declared, and as what.
    final declared = recon.tables[2].rows;
    expect(declared.last.cells[7].text, 'submitted'); // September
    expect(declared.last.cells[6].text, 'worked out'); // August
  });
}
