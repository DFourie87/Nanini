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

  const head = pw.TextStyle(fontSize: 8);
  final headBold = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
  const cell = pw.TextStyle(fontSize: 8);
  final small = pw.TextStyle(fontSize: 7, color: _muted);
  final bold = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
  pw.Widget pad(pw.Widget child, {pw.Alignment align = pw.Alignment.topLeft}) =>
      pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5), alignment: align, child: child);
  pw.Widget lines(List<(String, String)> items, (String, String) total) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (final (label, amount) in items)
            pw.Row(children: [pw.Expanded(child: pw.Text(label, style: small)), pw.Text(amount, style: small)]),
          pw.Row(children: [pw.Expanded(child: pw.Text(total.$1, style: bold)), pw.Text(total.$2, style: bold)]),
        ],
      );
  const headers = ['Full names', 'Name', 'Surname', 'ID / Passport', 'Gross pay', 'Deductions', 'Nett pay', 'Signature'];
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
          columnWidths: const {
            0: pw.FlexColumnWidth(1.6),
            1: pw.FlexColumnWidth(1.0),
            2: pw.FlexColumnWidth(1.0),
            3: pw.FlexColumnWidth(1.2),
            4: pw.FlexColumnWidth(2.4),
            5: pw.FlexColumnWidth(1.8),
            6: pw.FlexColumnWidth(0.9),
            7: pw.FlexColumnWidth(1.4),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: pw.BoxDecoration(color: _rust),
              children: [for (final h in headers) pad(pw.Text(h, style: headBold))],
            ),
            for (final (i, (p, e)) in sorted.indexed)
              pw.TableRow(
                decoration: i.isOdd ? pw.BoxDecoration(color: PdfColor.fromInt(0xFFFBF6EF)) : null,
                children: [
                  pad(pw.Text(_or(e.fullNames), style: cell)),
                  pad(pw.Text(_or(e.firstName), style: cell)),
                  pad(pw.Text(_or((e.surname ?? '').trim().isNotEmpty ? e.surname : e.lastName), style: cell)),
                  pad(pw.Text(_or(e.idOrPassport), style: cell)),
                  pad(lines(_grossParts(p, e), ('Gross', fmtR(p.gross)))),
                  pad(lines([
                    if (p.paye > 0) ('PAYE', fmtR(p.paye)),
                    if (p.uif > 0) ('UIF', fmtR(p.uif)),
                    if (p.rent > 0) ('Rent', fmtR(p.rent)),
                    if (p.loan > 0) ('Loan', fmtR(p.loan)),
                    if (p.tuckshopDeduction > 0) ('Tuck shop', fmtR(p.tuckshopDeduction)),
                  ], ('Total', fmtR(p.totalDeductions)))),
                  pad(pw.Text(fmtR(p.nett), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _rustDark)), align: pw.Alignment.topRight),
                  pad(pw.SizedBox(height: 26)),
                ],
              ),
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3E7D8)),
              children: [
                pad(pw.Text('TOTAL', style: bold)),
                pad(pw.Text('${ps.length} workers', style: head)),
                pad(pw.SizedBox()),
                pad(pw.SizedBox()),
                pad(pw.Text(fmtR(sum((p) => p.gross)), style: bold), align: pw.Alignment.topRight),
                pad(pw.Text(fmtR(sum((p) => p.totalDeductions)), style: bold), align: pw.Alignment.topRight),
                pad(pw.Text(fmtR(sum((p) => p.nett)), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _rustDark)), align: pw.Alignment.topRight),
                pad(pw.SizedBox()),
              ],
            ),
          ],
        ),
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

/// How [p]'s gross is made up: hours × tariff, kg × rate, each extra pay,
/// and whatever is left (a member's salary).
List<(String, String)> _grossParts(Payslip p, Employee e) {
  final hoursPay = p.hoursWorked * p.hourlyRate;
  final kgPay = p.kgWorked * p.kgRate;
  final extras = p.extras.fold<double>(0, (a, x) => a + ((x['amount'] as num?)?.toDouble() ?? 0));
  final rest = p.gross - hoursPay - kgPay - extras;
  return [
    if (p.hoursWorked > 0) ('${p.hoursWorked.toStringAsFixed(1)} h × ${fmtRCents(p.hourlyRate)}', fmtR(hoursPay)),
    if (p.kgWorked > 0) ('${p.kgWorked.toStringAsFixed(1)} kg × ${fmtRCents(p.kgRate)}', fmtR(kgPay)),
    for (final x in p.extras)
      (
        (x['hours'] as num?) != null && (x['hours'] as num) > 0
            ? '${x['description']}: ${(x['hours'] as num).toStringAsFixed(1)} h × ${fmtRCents(x['rate'] as num?)}'
            : '${x['description']}',
        fmtR(x['amount'] as num?),
      ),
    if (rest.abs() >= 0.5) ((e.monthlySalary ?? 0) > 0 ? 'Salary' : 'Other', fmtR(rest)),
  ];
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

void _addPayslipPage(pw.Document doc, Payslip payslip, Employee employee, pw.MemoryImage logo) {
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
                  pw.Text(employee.legalName),
                  if (employee.legalName != employee.displayName) pw.Text('Known as ${employee.displayName}', style: const pw.TextStyle(fontSize: 10)),
                  if ((employee.idOrPassport ?? '').isNotEmpty) pw.Text('ID/Passport: ${employee.idOrPassport}', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 8),
                  pw.Text('PAYMENT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _rustDark)),
                  pw.SizedBox(height: 4),
                  ..._paymentLines(employee, payslip),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('PAY PERIOD', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _rustDark)),
                  pw.SizedBox(height: 4),
                  pw.Text('${fmtDateDisplay(payslip.periodStart)} to ${fmtDateDisplay(payslip.periodEnd)}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Paid: ${fmtDateDisplay(payslip.paidDate)}', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          if (payslip.hoursWorked > 0 || payslip.kgWorked > 0 || payslip.extras.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            if (payslip.hoursWorked > 0)
              pw.Text(
                '${payslip.hoursWorked.toStringAsFixed(1)} hrs × ${fmtR(payslip.hourlyRate)}/hr = ${fmtR(payslip.hoursWorked * payslip.hourlyRate)}',
                style: pw.TextStyle(fontSize: 9, color: _muted),
              ),
            if (payslip.kgWorked > 0)
              pw.Text(
                '${payslip.kgWorked.toStringAsFixed(1)} kg × ${fmtR(payslip.kgRate)}/kg = ${fmtR(payslip.kgWorked * payslip.kgRate)}',
                style: pw.TextStyle(fontSize: 9, color: _muted),
              ),
            for (final x in payslip.extras)
              pw.Text(
                (x['hours'] as num?) != null && (x['hours'] as num) > 0
                    ? '${x['description']}: ${(x['hours'] as num).toStringAsFixed(1)} hrs × ${fmtR(x['rate'] as num?)}/hr = ${fmtR(x['amount'] as num?)}'
                    : '${x['description']}: ${fmtR(x['amount'] as num?)}',
                style: pw.TextStyle(fontSize: 9, color: _muted),
              ),
          ],
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['', 'Amount'],
            data: [
              ['Gross pay', fmtR(payslip.gross)],
              if (payslip.paye > 0) ['PAYE', '- ${fmtR(payslip.paye)}'],
              if (payslip.uif > 0) ['UIF', '- ${fmtR(payslip.uif)}'],
              if (payslip.rent > 0) ['Rent deduction', '- ${fmtR(payslip.rent)}'],
              if (payslip.loan > 0) ['Loan deduction', '- ${fmtR(payslip.loan)}'],
              if (payslip.tuckshopDeduction > 0) ['Tuck shop', '- ${fmtR(payslip.tuckshopDeduction)}'],
              ['Total deductions', '- ${fmtR(payslip.totalDeductions)}'],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: pw.BoxDecoration(color: _rust),
            headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            cellStyle: const pw.TextStyle(fontSize: 10),
            oddRowDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFFBF6EF)),
            border: pw.TableBorder.all(color: _line, width: 0.5),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFFBF6EF), borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Text('Nett pay: ${fmtR(payslip.nett)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _rustDark, fontSize: 12)),
            ),
          ),
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
