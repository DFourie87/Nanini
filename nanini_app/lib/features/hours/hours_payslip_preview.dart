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
        pw.Text('ATM card', style: style),
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
Future<pw.Document> buildRunPdf({required String farmName, required List<(Payslip, Employee)> slips}) async {
  final doc = pw.Document();
  final logo = await _loadLogo();
  final sorted = [...slips]..sort((a, b) => a.$2.displayName.toLowerCase().compareTo(b.$2.displayName.toLowerCase()));
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
    _Col('Full names', 1.5, (p, e) => _or(e.fullNames), text: true),
    _Col('Name', 0.9, (p, e) => _or(e.firstName), text: true),
    _Col('Surname', 0.9, (p, e) => _or((e.surname ?? '').trim().isNotEmpty ? e.surname : e.lastName), text: true),
    _Col('ID / Passport', 1.25, (p, e) => _or(e.idOrPassport), text: true),
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
        _titleBar('PAYSLIPS SUMMARY -- ${farmName.toUpperCase()}'),
        pw.SizedBox(height: 6),
        pw.Text('Work up to ${fmtDateDisplay(ps.first.periodEnd)} (from ${fmtDateDisplay(first)}) · paid ${fmtDateDisplay(ps.first.paidDate)} · ${ps.length} workers',
            style: pw.TextStyle(fontSize: 9, color: _muted)),
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
  for (final (p, e) in sorted) {
    _addPayslipPage(doc, p, e, logo);
  }
  return doc;
}

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
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Image(logo, height: _headerBlockHeight, width: _headerBlockHeight * _logoAspectRatio),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(_companyName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  for (final l in _companyContact) pw.Text(l, style: pw.TextStyle(fontSize: 8, color: _muted)),
                ],
              ),
            ],
          ),
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

Future<void> showPdfPreview(BuildContext context, Future<pw.Document> Function() build) async {
  await showDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 500,
        height: 700,
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
