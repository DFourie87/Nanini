import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/formatters.dart';
import '../employees/employees_models.dart';
import 'hunting_models.dart';

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

Future<pw.MemoryImage> _logo() async {
  final bytes = await rootBundle.load(_logoAssetPath);
  return pw.MemoryImage(bytes.buffer.asUint8List());
}

pw.Widget _letterhead(pw.MemoryImage logo) => pw.Row(
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
    );

pw.Widget _titleBanner(String text) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 10),
      decoration: pw.BoxDecoration(color: _rust, borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Center(
        child: pw.Text(text, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
      ),
    );

/// EFT gets a formal tax invoice; cash just gets a plain breakdown of what's
/// owed -- same line items and total either way, different heading.
Future<pw.Document> buildHuntingInvoicePdf(
  HuntingInvoice invoice,
  Farm farm,
  List<HuntingAnimalLine> animals,
  List<HuntingAccommodationLine> accommodation,
) async {
  final doc = pw.Document();
  final logo = await _logo();
  final isEft = invoice.paymentMethod == HuntingPaymentMethod.eft;
  final total = animals.fold<double>(0, (s, a) => s + a.price) + accommodation.fold<double>(0, (s, a) => s + a.total);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _letterhead(logo),
          pw.SizedBox(height: 12),
          pw.Container(height: 3, color: _rust),
          pw.SizedBox(height: 16),
          _titleBanner(isEft ? 'TAX INVOICE' : 'STATEMENT OF ACCOUNT'),
          pw.SizedBox(height: 10),
          if (invoice.invoiceNumber != null)
            pw.Center(
              child: pw.Text('No: ${invoice.invoiceNumber}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _rustDark)),
            ),
          pw.SizedBox(height: 14),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('HUNTER', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _rustDark)),
                  pw.SizedBox(height: 4),
                  pw.Text(invoice.hunterName),
                  if ((invoice.idOrPassport ?? '').isNotEmpty) pw.Text('ID/Passport: ${invoice.idOrPassport}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(guestTypeLabel(invoice.guestType), style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('FARM', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _rustDark)),
                  pw.SizedBox(height: 4),
                  pw.Text(farm.name, style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 8),
                  pw.Text('Date: ${fmtDateDisplay(invoice.visitDate)}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Payment: ${isEft ? 'EFT' : 'Cash'}', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['DESCRIPTION', 'AMOUNT'],
            data: [
              for (final a in animals) ['Animal: ${a.species} (${fmtDateDisplay(a.huntDate)})', fmtR(a.price)],
              for (final a in accommodation)
                ['Accommodation: ${a.nights.toStringAsFixed(0)} night${a.nights == 1 ? '' : 's'} from ${fmtDateDisplay(a.fromDate)}', fmtR(a.total)],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: pw.BoxDecoration(color: _rust),
            headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            cellStyle: const pw.TextStyle(fontSize: 9),
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
              child: pw.Text(
                '${isEft ? 'Total due' : 'Total owed'}: ${fmtR(total)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _rustDark, fontSize: 12),
              ),
            ),
          ),
          pw.Expanded(child: pw.SizedBox()),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              for (final label in ['NANINI BOERDERY', 'HUNTER'])
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

/// Placeholder layout pending the actual provincial permit template --
/// covers the fields a transport permit is likely to need (hunter, farm,
/// species, date, permit number) so the workflow is usable now.
Future<pw.Document> buildTransportPermitPdf(HuntingInvoice invoice, Farm farm, HuntingAnimalLine animal) async {
  final doc = pw.Document();
  final logo = await _logo();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _letterhead(logo),
          pw.SizedBox(height: 12),
          pw.Container(height: 3, color: _rust),
          pw.SizedBox(height: 16),
          _titleBanner('TRANSPORT PERMIT'),
          pw.SizedBox(height: 10),
          if (animal.permitNumber != null)
            pw.Center(
              child: pw.Text('Permit No: ${animal.permitNumber}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _rustDark)),
            ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            data: [
              ['Hunter', invoice.hunterName],
              if ((invoice.idOrPassport ?? '').isNotEmpty) ['ID/Passport', invoice.idOrPassport!],
              ['Guest type', guestTypeLabel(invoice.guestType)],
              ['Farm', farm.name],
              ['Species', animal.species],
              ['Date hunted', fmtDateDisplay(animal.huntDate)],
            ],
            cellStyle: const pw.TextStyle(fontSize: 11),
            oddRowDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFFBF6EF)),
            border: pw.TableBorder.all(color: _line, width: 0.5),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(2)},
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'This permit authorises the transport of the above animal/trophy from the farm named above.',
            style: pw.TextStyle(fontSize: 9, color: _muted),
          ),
          pw.Expanded(child: pw.SizedBox()),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              for (final label in ['NANINI BOERDERY', 'HUNTER'])
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

Future<void> _showPdfPreview(BuildContext context, Future<pw.Document> Function() build) async {
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

Future<void> showHuntingInvoicePreview(
  BuildContext context,
  HuntingInvoice invoice,
  Farm farm,
  List<HuntingAnimalLine> animals,
  List<HuntingAccommodationLine> accommodation,
) =>
    _showPdfPreview(context, () => buildHuntingInvoicePdf(invoice, farm, animals, accommodation));

Future<void> showTransportPermitPreview(BuildContext context, HuntingInvoice invoice, Farm farm, HuntingAnimalLine animal) =>
    _showPdfPreview(context, () => buildTransportPermitPdf(invoice, farm, animal));
