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
/// name and account number; ATM needs the phone number and access code.
List<pw.Widget> _paymentLines(Employee employee) {
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
        pw.Text('Phone: ${employee.phoneNumber ?? '-'}', style: style),
        pw.Text('Access code: ${employee.atmAccessCode ?? '-'}', style: style),
      ];
    case PaymentMethod.cash:
      return [pw.Text('Cash', style: style)];
  }
}

Future<pw.Document> buildPayslipPdf(Payslip payslip, Employee employee) async {
  final doc = pw.Document();
  final logoBytes = await rootBundle.load(_logoAssetPath);
  final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());

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
                  pw.Text(employee.displayName),
                  if ((employee.idOrPassport ?? '').isNotEmpty) pw.Text('ID/Passport: ${employee.idOrPassport}', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 8),
                  pw.Text('PAYMENT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _rustDark)),
                  pw.SizedBox(height: 4),
                  ..._paymentLines(employee),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('PAY PERIOD', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _rustDark)),
                  pw.SizedBox(height: 4),
                  pw.Text('${fmtDateDisplay(payslip.periodStart)} – ${fmtDateDisplay(payslip.periodEnd)}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Paid: ${fmtDateDisplay(payslip.paidDate)}', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['', 'Amount'],
            data: [
              ['Gross pay', fmtR(payslip.gross)],
              ['PAYE', '- ${fmtR(payslip.paye)}'],
              ['UIF', '- ${fmtR(payslip.uif)}'],
              ['Rent deduction', '- ${fmtR(payslip.rent)}'],
              ['Loan deduction', '- ${fmtR(payslip.loan)}'],
              ['Tuck shop', '- ${fmtR(payslip.tuckshopDeduction)}'],
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
  return doc;
}

Future<void> showPayslipPreview(BuildContext context, Payslip payslip, Employee employee) async {
  await showDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 500,
        height: 700,
        child: PdfPreview(
          build: (format) async => (await buildPayslipPdf(payslip, employee)).save(),
          allowSharing: true,
          allowPrinting: true,
          canChangeOrientation: false,
          canChangePageFormat: false,
        ),
      ),
    ),
  );
}
