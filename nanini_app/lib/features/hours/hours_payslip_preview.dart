import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/formatters.dart';
import '../employees/employees_models.dart';
import 'hours_models.dart';

const _companyName = 'NANINI 121 CC T/A NANINI BOERDERY';
const _companyContact = [
  'E-MAIL: fourie05@gmail.com',
  'TEL: 082 790 7808 / 082 442 4329',
  'REG: 2000/026925/23',
  'VAT: 4840191854',
];
const _logoAssetPath = 'assets/images/hub-logo-print.png';
const _logoAspectRatio = 966 / 700;
const _headerBlockHeight = 92.0;

final _rust = PdfColor.fromInt(0xFFEC1F24);
final _rustDark = PdfColor.fromInt(0xFFC41A1E);
final _muted = PdfColor.fromInt(0xFF4A4A4A);
final _line = PdfColor.fromInt(0xFFE4D6C3);

/// Cash needs nothing extra on the payslip; bank transfer needs the bank
/// name and account number; ATM needs the phone number and that payday's
/// access code (kept on the payslip).
List<pw.Widget> _paymentLines(Employee employee, Payslip payslip) {
  final style = const pw.TextStyle(fontSize: 10);
  switch (employee.paymentMethod) {
    case PaymentMethod.bank:
      return [
        pw.Text('Bank transfer', style: style),
        pw.Text('Bank: ${employee.bankName ?? '-'}', style: style),
        pw.Text('Account: ${employee.bankAccountNo ?? '-'}', style: style),
      ];
    case PaymentMethod.atm:
      return [
        pw.Text('ATM', style: style),
        pw.Text('Phone number: ${employee.phoneNumber ?? '-'}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Text('ATM access code: ${payslip.atmAccessCode ?? '-'}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      ];
    case PaymentMethod.cash:
      return [pw.Text('Cash', style: style)];
  }
}

Future<pw.MemoryImage> _loadLogo() async => pw.MemoryImage((await rootBundle.load(_logoAssetPath)).buffer.asUint8List());

Future<pw.Document> buildPayslipPdf(Payslip payslip, Employee employee) async {
  final doc = pw.Document();
  _addPayslipPage(doc, payslip, employee, await _loadLogo());
  return doc;
}

pw.Widget _letterhead(pw.MemoryImage logo) => pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Image(logo, height: _headerBlockHeight * 0.7, width: _headerBlockHeight * 0.7 * _logoAspectRatio),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(_companyName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                for (final l in _companyContact) pw.Text(l, style: pw.TextStyle(fontSize: 8, color: _muted)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Container(height: 3, color: _rust),
        pw.SizedBox(height: 12),
      ],
    );

pw.Widget _titleBar(String title) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      decoration: pw.BoxDecoration(color: _rust, borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Center(child: pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
    );

pw.Widget _table(List<String> headers, List<List<String>> rows, {List<String>? footer}) => pw.TableHelper.fromTextArray(
      headers: headers,
      data: [...rows, ?footer],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
      headerDecoration: pw.BoxDecoration(color: _rust),
      cellStyle: const pw.TextStyle(fontSize: 8),
      oddRowDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFFBF6EF)),
      border: pw.TableBorder.all(color: _line, width: 0.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      cellAlignment: pw.Alignment.centerRight,
      cellAlignments: {0: pw.Alignment.centerLeft},
    );

/// A payroll run printed: a landscape summary page first (every worker's
/// names and ID, how the gross is made up, each deduction, nett and a column
/// for their signature, with totals), then each worker's payslip.
///
/// [preview]: before payroll is run -- the summary page only, marked so.
Future<pw.Document> buildRunPdf({required String farmName, required List<(Payslip, Employee)> slips, bool preview = false}) async {
  final doc = pw.Document();
  final logo = await _loadLogo();
  // By surname, then name (the summary's first columns).
  final sorted = [...slips]
    ..sort((a, b) {
      final c = _surname(a.$2).toLowerCase().compareTo(_surname(b.$2).toLowerCase());
      return c != 0 ? c : a.$2.displayName.toLowerCase().compareTo(b.$2.displayName.toLowerCase());
    });
  final ps = sorted.map((s) => s.$1).toList();
  double sum(double Function(Payslip) f) => ps.fold<double>(0, (a, p) => a + f(p));
  final first = ps.map((p) => p.periodStart).reduce((a, b) => a.compareTo(b) <= 0 ? a : b);

  // One column per item of gross pay and per deduction; an item nobody in
  // this run has (e.g. kg, rent) is left out.
  double extraOf(Payslip p, String key) => p.extras
      .where((x) => '${x['description'] ?? ''}'.trim().toLowerCase() == key)
      .fold<double>(0, (a, x) => a + ((x['amount'] as num?)?.toDouble() ?? 0));
  final extraKeys = <String, String>{
    for (final p in ps)
      for (final x in p.extras) '${x['description'] ?? ''}'.trim().toLowerCase(): '${x['description'] ?? ''}'.trim(),
  };
  double salaryOf(Payslip p) {
    final rest = p.gross - p.hoursWorked * p.hourlyRate - p.kgWorked * p.kgRate - p.extras.fold<double>(0, (a, x) => a + ((x['amount'] as num?)?.toDouble() ?? 0));
    return rest.abs() >= 0.5 ? rest : 0;
  }
  String hrs(double v) => v == 0 ? '' : v.toStringAsFixed(1);
  String r(double v) => v.abs() < 0.005 ? '' : fmtR(v);
  final cols = <_Col>[
    _Col('Surname', 0.9, (p, e) => _or(_surname(e)), text: true),
    _Col('Name', 0.9, (p, e) => _or(e.firstName), text: true),
    _Col('Full names', 1.5, (p, e) => _or(e.fullNames), text: true),
    _Col('ID / Passport', 1.25, (p, e) => _or(e.idOrPassport), text: true),
    if (sorted.any((x) => (x.$2.phoneNumber ?? '').trim().isNotEmpty))
      _Col('Phone', 1.05, (p, e) => (e.phoneNumber ?? '').trim(), text: true),
    if (ps.any((p) => p.hoursWorked > 0)) ...[
      _Col('Hours', 0.6, (p, e) => hrs(p.hoursWorked), total: hrs(sum((p) => p.hoursWorked)), kind: _Kind.gross),
      _Col('Tariff /h', 0.75, (p, e) => p.hoursWorked > 0 ? fmtRCents(p.hourlyRate) : '', kind: _Kind.gross),
      _Col('Hours pay', 0.8, (p, e) => r(p.hoursWorked * p.hourlyRate), total: r(sum((p) => p.hoursWorked * p.hourlyRate)), kind: _Kind.gross),
    ],
    if (ps.any((p) => p.kgWorked > 0)) ...[
      _Col('Kg picked', 0.65, (p, e) => hrs(p.kgWorked), total: hrs(sum((p) => p.kgWorked)), kind: _Kind.gross),
      _Col('Kg pay', 0.8, (p, e) => r(p.kgWorked * p.kgRate), total: r(sum((p) => p.kgWorked * p.kgRate)), kind: _Kind.gross),
    ],
    for (final MapEntry(:key, :value) in extraKeys.entries)
      _Col(value.isEmpty ? 'Extra' : value, 0.8, (p, e) => r(extraOf(p, key)), total: r(sum((p) => extraOf(p, key))), kind: _Kind.gross),
    if (ps.any((p) => salaryOf(p) != 0))
      _Col('Salary', 0.8, (p, e) => r(salaryOf(p)), total: r(sum(salaryOf)), kind: _Kind.gross),
    _Col('Gross pay', 0.85, (p, e) => fmtR(p.gross), total: fmtR(sum((p) => p.gross)), kind: _Kind.gross, strong: true),
    if (ps.any((p) => p.paye > 0)) _Col('PAYE', 0.7, (p, e) => r(p.paye), total: r(sum((p) => p.paye)), kind: _Kind.deduction),
    if (ps.any((p) => p.uif > 0)) _Col('UIF', 0.65, (p, e) => r(p.uif), total: r(sum((p) => p.uif)), kind: _Kind.deduction),
    if (ps.any((p) => p.rent > 0)) _Col('Rent', 0.7, (p, e) => r(p.rent), total: r(sum((p) => p.rent)), kind: _Kind.deduction),
    if (ps.any((p) => p.loan > 0)) _Col('Loan', 0.7, (p, e) => r(p.loan), total: r(sum((p) => p.loan)), kind: _Kind.deduction),
    if (ps.any((p) => p.tuckshopDeduction > 0))
      _Col('Tuck shop', 0.75, (p, e) => r(p.tuckshopDeduction), total: r(sum((p) => p.tuckshopDeduction)), kind: _Kind.deduction),
    _Col('Total deductions', 0.95, (p, e) => r(p.totalDeductions), total: r(sum((p) => p.totalDeductions)), kind: _Kind.deduction, strong: true),
    _Col('Nett pay', 0.9, (p, e) => fmtR(p.nett), total: fmtR(sum((p) => p.nett)), kind: _Kind.nett, strong: true),
    _Col('Signature', 1.3, (p, e) => '', text: true),
  ];
  final cellFont = cols.length > 18 ? 6.5 : 7.5;
  pw.Widget cellOf(String v, _Col c, {bool total = false}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        alignment: c.text ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
        constraints: c.header == 'Signature' && !total ? const pw.BoxConstraints(minHeight: 26) : null,
        child: pw.Text(v,
            style: pw.TextStyle(
              fontSize: cellFont,
              fontWeight: c.strong || total ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: c.kind == _Kind.nett ? _rustDark : null,
            )),
      );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) => [
        _letterheadCentred(logo),
        _titleBar('PAYSLIPS SUMMARY -- ${farmName.toUpperCase()}${preview ? ' (PREVIEW)' : ''}'),
        pw.SizedBox(height: 6),
        pw.Text(
            preview
                ? 'PREVIEW -- payroll not run yet. Work up to ${fmtDateDisplay(ps.first.periodEnd)} (from ${fmtDateDisplay(first)}) · ${ps.length} workers'
                : 'Work up to ${fmtDateDisplay(ps.first.periodEnd)} (from ${fmtDateDisplay(first)}) · paid ${fmtDateDisplay(ps.first.paidDate)} · ${ps.length} workers',
            style: pw.TextStyle(fontSize: 9, color: preview ? _rustDark : _muted, fontWeight: preview ? pw.FontWeight.bold : null)),
        // Paid by ATM: the payday's access code, once (the same for all).
        if (ps.map((p) => p.atmAccessCode).whereType<String>().firstOrNull case final code?) ...[
          pw.SizedBox(height: 4),
          pw.Text('ATM access code for this payday: $code', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _rustDark)),
        ],
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.5),
          columnWidths: {for (final (i, c) in cols.indexed) i: pw.FlexColumnWidth(c.flex)},
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            pw.TableRow(
              repeat: true,
              verticalAlignment: pw.TableCellVerticalAlignment.full,
              children: [
                for (final c in cols)
                  pw.Container(
                    color: switch (c.kind) { _Kind.deduction => _rustDark, _Kind.nett => PdfColor.fromInt(0xFF8F1215), _ => _rust },
                    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 5),
                    alignment: c.text ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
                    child: pw.Text(c.header, style: pw.TextStyle(fontSize: cellFont, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                  ),
              ],
            ),
            for (final (i, (p, e)) in sorted.indexed)
              pw.TableRow(
                decoration: i.isOdd ? pw.BoxDecoration(color: PdfColor.fromInt(0xFFFBF6EF)) : null,
                children: [for (final c in cols) cellOf(c.value(p, e), c)],
              ),
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3E7D8)),
              children: [
                for (final (i, c) in cols.indexed)
                  cellOf(i == 0 ? 'TOTAL' : i == 1 ? '${ps.length} workers' : c.total ?? '', c, total: true),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text('Gross pay columns in red, deductions in dark red. Tariff is per hour.', style: pw.TextStyle(fontSize: 7, color: _muted)),
        pw.SizedBox(height: 30),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            for (final label in ['PREPARED BY', 'APPROVED BY'])
              pw.Column(children: [pw.Container(width: 180, height: 1, color: _line), pw.SizedBox(height: 4), pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _muted))]),
          ],
        ),
      ],
    ),
  );
  if (!preview) {
    for (final (p, e) in sorted) {
      _addPayslipPage(doc, p, e, logo);
    }
  }
  return doc;
}

/// The surname as on the ID, else the last name typed in Employees > List.
String _surname(Employee e) => ((e.surname ?? '').trim().isNotEmpty ? e.surname! : e.lastName).trim();

String _or(String? v) => (v ?? '').trim().isEmpty ? '-' : v!.trim();

enum _Kind { info, gross, deduction, nett }

/// One column of the payslips summary.
class _Col {
  const _Col(this.header, this.flex, this.value, {this.total, this.kind = _Kind.info, this.text = false, this.strong = false});
  final String header;
  final double flex;
  final String Function(Payslip, Employee) value;
  final String? total;
  final _Kind kind;
  final bool text;
  final bool strong;
}

/// The letterhead with the logo in the middle (landscape summary).
pw.Widget _letterheadCentred(pw.MemoryImage logo) => pw.Column(
      children: [
        pw.Center(child: pw.Image(logo, height: 54, width: 54 * _logoAspectRatio)),
        pw.SizedBox(height: 4),
        pw.Text(_companyName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.Text(_companyContact.join('   ·   '), style: pw.TextStyle(fontSize: 8, color: _muted)),
        pw.SizedBox(height: 6),
        pw.Container(height: 3, color: _rust),
        pw.SizedBox(height: 8),
      ],
    );

/// Hours calendar for a farm and a month: a row per worker (name, surname,
/// ID/passport), a column per day of the month with the hours logged that
/// day, and totals per worker, per day and overall. Same look as the
/// payslips summary (landscape, logo in the middle).
Future<pw.Document> buildCalendarPdf({
  required String farmName,
  required DateTime month,
  required List<Employee> employees,
  required List<HoursEntry> entries,
}) async {
  final doc = pw.Document();
  final logo = await _loadLogo();
  final days = DateTime(month.year, month.month + 1, 0).day;
  String key(DateTime d) => toDateStr(d);
  final dates = [for (var d = 1; d <= days; d++) DateTime(month.year, month.month, d)];
  final ids = {for (final e in employees) e.id};
  // Hours per worker per day.
  final byDay = <String, Map<String, double>>{};
  for (final h in entries) {
    if (!ids.contains(h.employeeId)) continue;
    final d = parseDateStr(h.date);
    if (d == null || d.year != month.year || d.month != month.month) continue;
    final m = byDay.putIfAbsent(h.employeeId, () => {});
    m[h.date] = (m[h.date] ?? 0) + h.hours;
  }
  final sorted = [...employees]
    ..sort((a, b) {
      final c = _surname(a).toLowerCase().compareTo(_surname(b).toLowerCase());
      return c != 0 ? c : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  String h(double v) => v == 0 ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1));
  double rowTotal(Employee e) => (byDay[e.id] ?? const {}).values.fold<double>(0, (a, b) => a + b);
  double dayTotal(DateTime d) => sorted.fold<double>(0, (a, e) => a + (byDay[e.id]?[key(d)] ?? 0));
  final grand = sorted.fold<double>(0, (a, e) => a + rowTotal(e));
  const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  final shade = PdfColor.fromInt(0xFFFBF6EF);
  final weekend = PdfColor.fromInt(0xFFF3E7D8);
  const font = 6.5;
  pw.Widget cell(String t, {bool bold = false, bool left = false, PdfColor? color, PdfColor? bg}) => pw.Container(
        color: bg,
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        alignment: left ? pw.Alignment.centerLeft : pw.Alignment.center,
        child: pw.Text(t, style: pw.TextStyle(fontSize: font, fontWeight: bold ? pw.FontWeight.bold : null, color: color)),
      );
  bool isWeekend(DateTime d) => d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      build: (ctx) => [
        _letterheadCentred(logo),
        _titleBar('HOURS CALENDAR -- ${farmName.toUpperCase()} -- ${monthNames[month.month - 1].toUpperCase()} ${month.year}'),
        pw.SizedBox(height: 6),
        pw.Text('Hours logged per day · ${sorted.length} workers · ${h(grand).isEmpty ? '0' : h(grand)} hours in total',
            style: pw.TextStyle(fontSize: 9, color: _muted)),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.2),
            1: const pw.FlexColumnWidth(2.2),
            2: const pw.FlexColumnWidth(2.8),
            for (var i = 0; i < days; i++) 3 + i: const pw.FlexColumnWidth(0.62),
            3 + days: const pw.FlexColumnWidth(1.2),
          },
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            pw.TableRow(
              repeat: true,
              verticalAlignment: pw.TableCellVerticalAlignment.full,
              decoration: pw.BoxDecoration(color: _rust),
              children: [
                for (final t in ['Name', 'Surname', 'ID / Passport']) cell(t, bold: true, left: true, color: PdfColors.white),
                for (final d in dates)
                  cell('${d.day}', bold: true, color: PdfColors.white, bg: isWeekend(d) ? _rustDark : null),
                cell('Total', bold: true, color: PdfColors.white, bg: _rustDark),
              ],
            ),
            for (final (i, e) in sorted.indexed)
              pw.TableRow(
                verticalAlignment: pw.TableCellVerticalAlignment.full,
                decoration: i.isOdd ? pw.BoxDecoration(color: shade) : null,
                children: [
                  cell(_or(e.firstName), left: true),
                  cell(_or(_surname(e)), left: true),
                  cell(_or(e.idOrPassport), left: true),
                  for (final d in dates) cell(h(byDay[e.id]?[key(d)] ?? 0), bg: isWeekend(d) ? weekend : null),
                  cell(h(rowTotal(e)), bold: true, color: _rustDark),
                ],
              ),
            pw.TableRow(
              verticalAlignment: pw.TableCellVerticalAlignment.full,
              decoration: pw.BoxDecoration(color: weekend),
              children: [
                cell('TOTAL', bold: true, left: true),
                cell('${sorted.length} workers', left: true),
                cell(''),
                for (final d in dates) cell(h(dayTotal(d)), bold: true),
                cell(h(grand), bold: true, color: _rustDark),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text('Weekends shaded. Hours as logged (from the phones and the office).', style: pw.TextStyle(fontSize: 7, color: _muted)),
      ],
    ),
  );
  return doc;
}

/// Pay for all farms for a calendar month (by paid date), per farm and in
/// total, with the month's EMP201 figures for SARS.
Future<pw.Document> buildMonthPdf({
  required String monthLabel,
  required List<(String farm, List<String> cells)> farmRows,
  required List<String> totalRow,
  required List<(String, String)> emp201,
  required String dueLine,
}) async {
  final doc = pw.Document();
  final logo = await _loadLogo();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        _letterhead(logo),
        _titleBar('PAY SUMMARY -- ${monthLabel.toUpperCase()} -- ALL FARMS'),
        pw.SizedBox(height: 10),
        _table(
          ['Farm', 'Workers', 'Hours', 'Gross', 'PAYE', 'UIF', 'Rent', 'Loan', 'Tuck shop', 'Nett'],
          [for (final (farm, cells) in farmRows) [farm, ...cells]],
          footer: ['ALL FARMS', ...totalRow],
        ),
        pw.SizedBox(height: 24),
        _titleBar('EMP201 -- $monthLabel'.toUpperCase()),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          data: [for (final (k, v) in emp201) [k, v]],
          cellStyle: const pw.TextStyle(fontSize: 10),
          border: pw.TableBorder.all(color: _line, width: 0.5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
        ),
        pw.SizedBox(height: 8),
        pw.Text(dueLine, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _rustDark)),
      ],
    ),
  );
  return doc;
}

/// The employee's name on a payslip: full names and surname as on the ID,
/// with the name they're known by in brackets when that's different.
String payslipName(Employee e) {
  final legal = e.legalName;
  final nick = e.firstName.trim();
  if (legal == e.displayName || nick.isEmpty) return legal;
  final words = legal.toLowerCase().split(RegExp(r'\s+'));
  return words.contains(nick.toLowerCase()) ? legal : '$legal ($nick)';
}

void _addPayslipPage(pw.Document doc, Payslip payslip, Employee employee, pw.MemoryImage logo) {
  final p = payslip;
  final extrasTotal = p.extras.fold<double>(0, (a, x) => a + ((x['amount'] as num?)?.toDouble() ?? 0));
  final rest = p.gross - p.hoursWorked * p.hourlyRate - p.kgWorked * p.kgRate - extrasTotal;
  // (description, quantity, rate, amount)
  final earnings = <(String, String, String, double)>[
    if (p.hoursWorked > 0) ('Hours worked', '${p.hoursWorked.toStringAsFixed(1)} h', '${fmtRCents(p.hourlyRate)} /h', p.hoursWorked * p.hourlyRate),
    if (p.kgWorked > 0) ('Kg picked', '${p.kgWorked.toStringAsFixed(1)} kg', '${fmtRCents(p.kgRate)} /kg', p.kgWorked * p.kgRate),
    for (final x in p.extras)
      (
        '${x['description'] ?? 'Extra pay'}',
        (x['hours'] as num?) != null && (x['hours'] as num) > 0 ? '${(x['hours'] as num).toStringAsFixed(1)} h' : '',
        (x['hours'] as num?) != null && (x['hours'] as num) > 0 ? '${fmtRCents(x['rate'] as num?)} /h' : '',
        (x['amount'] as num?)?.toDouble() ?? 0,
      ),
    if (rest.abs() >= 0.5) ((employee.monthlySalary ?? 0) > 0 ? 'Salary' : 'Other pay', '', '', rest),
  ];
  final deductions = <(String, double)>[
    if (p.paye > 0) ('PAYE', p.paye),
    if (p.uif > 0) ('UIF (1%)', p.uif),
    if (p.rent > 0) ('Rent', p.rent),
    if (p.loan > 0) ('Loan repayment', p.loan),
    if (p.tuckshopDeduction > 0) ('Tuck shop', p.tuckshopDeduction),
  ];

  final shade = PdfColor.fromInt(0xFFFBF6EF);
  final sectionBg = PdfColor.fromInt(0xFFF3E7D8);
  const body = pw.TextStyle(fontSize: 10);
  final strong = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
  pw.Widget c(String t, {pw.TextStyle? style, bool right = false}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(t, style: style ?? body),
      );
  pw.TableRow section(String title) => pw.TableRow(
        decoration: pw.BoxDecoration(color: sectionBg),
        children: [c(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _rustDark)), c(''), c(''), c('')],
      );
  pw.TableRow totalRow(String label, String amount) => pw.TableRow(
        children: [c(label, style: strong), c(''), c(''), c(amount, style: strong, right: true)],
      );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(child: pw.Image(logo, height: _headerBlockHeight, width: _headerBlockHeight * _logoAspectRatio)),
          pw.SizedBox(height: 12),
          pw.Container(height: 3, color: _rust),
          pw.SizedBox(height: 16),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 10),
            decoration: pw.BoxDecoration(color: _rust, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Center(
              child: pw.Text('PAYSLIP', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('EMPLOYEE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _rustDark)),
                  pw.SizedBox(height: 4),
                  pw.Text(payslipName(employee)),
                  if ((employee.idOrPassport ?? '').isNotEmpty) pw.Text('ID/Passport: ${employee.idOrPassport}', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('PAY PERIOD', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _rustDark)),
                  pw.SizedBox(height: 4),
                  pw.Text('${fmtDateDisplay(p.periodStart)} to ${fmtDateDisplay(p.periodEnd)}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Paid: ${fmtDateDisplay(p.paidDate)}', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: _line, width: 0.5),
            columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.2), 2: pw.FlexColumnWidth(1.3), 3: pw.FlexColumnWidth(1.4)},
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _rust),
                children: [
                  for (final (h, right) in [('Description', false), ('Quantity', true), ('Rate', true), ('Amount', true)])
                    c(h, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), right: right),
                ],
              ),
              section('GROSS PAY'),
              for (final (i, (d, q, r, amt)) in earnings.indexed)
                pw.TableRow(
                  decoration: i.isOdd ? pw.BoxDecoration(color: shade) : null,
                  children: [c(d), c(q, right: true), c(r, right: true), c(fmtRCents(amt), right: true)],
                ),
              totalRow('Total gross pay', fmtRCents(p.gross)),
              section('DEDUCTIONS'),
              if (deductions.isEmpty)
                pw.TableRow(children: [c('None', style: pw.TextStyle(fontSize: 10, color: _muted)), c(''), c(''), c('')]),
              for (final (i, (d, amt)) in deductions.indexed)
                pw.TableRow(
                  decoration: i.isOdd ? pw.BoxDecoration(color: shade) : null,
                  children: [c(d), c(''), c(''), c('- ${fmtRCents(amt)}', right: true)],
                ),
              totalRow('Total deductions', '- ${fmtRCents(p.totalDeductions)}'),
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _rust),
                children: [
                  c('NETT PAY', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                  c(''),
                  c(''),
                  c(fmtRCents(p.nett), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white), right: true),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text('PAYMENT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _rustDark)),
          pw.SizedBox(height: 4),
          ..._paymentLines(employee, payslip),
          pw.Expanded(child: pw.SizedBox()),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              for (final label in ['NANINI BOERDERY', 'EMPLOYEE'])
                pw.Column(
                  children: [
                    pw.Container(width: 180, height: 1, color: _line),
                    pw.SizedBox(height: 4),
                    pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _muted)),
                  ],
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

Future<void> showPayslipPreview(BuildContext context, Payslip payslip, Employee employee) =>
    showPdfPreview(context, () => buildPayslipPdf(payslip, employee));

/// The PDF to look over before going ahead: true when [approveLabel] is
/// pressed, false for "Back to edit" (or closing the window).
Future<bool> confirmPdfPreview(BuildContext context, Future<pw.Document> Function() build,
    {required String title, required String approveLabel}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 900,
        height: 720,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            Expanded(
              child: PdfPreview(
                build: (format) async => (await build()).save(),
                allowSharing: false,
                allowPrinting: false,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, false),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Back to edit'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.check),
                    label: Text(approveLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return ok == true;
}

/// [landscape]: a wider window for a landscape page (the summary).
Future<void> showPdfPreview(BuildContext context, Future<pw.Document> Function() build, {bool landscape = false}) async {
  await showDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: landscape ? 900 : 500,
        height: landscape ? 640 : 700,
        child: PdfPreview(
          build: (format) async => (await build()).save(),
          allowSharing: true,
          allowPrinting: true,
          canChangeOrientation: false,
          canChangePageFormat: false,
        ),
      ),
    ),
  );
}
