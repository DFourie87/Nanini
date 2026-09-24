import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/formatters.dart';
import '../employees/employees_models.dart';
import 'hunting_models.dart';
import 'hunting_repository.dart';

String _animalDescription(HuntingAnimalLine a) {
  final parts = <String>[a.species];
  if (a.sex != null) parts.add(a.sex == 'male' ? 'Male' : 'Female');
  if (a.hornInches != null) parts.add('${a.hornInches!.toStringAsFixed(1)}in');
  return '${parts.join(', ')} (${fmtDateDisplay(a.huntDate)})';
}

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
              for (final a in animals) ['Animal: ${_animalDescription(a)}', fmtR(a.price)],
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

/// Fixed per-farm identity fields that appear on the permit letterhead
/// (registration number/district/province) -- these are the farm's official
/// details, not per-visit data, so they're looked up by farm rather than
/// stored on the invoice. Only Limpopodraai's are confirmed from the actual
/// paper template; fill in the rest here once they're known.
class _FarmPermitInfo {
  const _FarmPermitInfo({required this.displayName, required this.registrationNumber, required this.district, required this.province});
  final String displayName;
  final String registrationNumber;
  final String district;
  final String province;
}

_FarmPermitInfo _permitInfoFor(Farm farm) {
  final name = farm.name.toLowerCase();
  if (name.contains('limpopodraai')) {
    return const _FarmPermitInfo(
      displayName: 'LIMPOPODRAAI',
      registrationNumber: '751 LQ',
      district: 'WATERBERG DISTRICT',
      province: 'LIMPOPO PROVINCE',
    );
  }
  if (name.contains('haaskraal')) {
    return const _FarmPermitInfo(displayName: 'HAASKRAAL', registrationNumber: '', district: '', province: '');
  }
  return _FarmPermitInfo(displayName: farm.name.toUpperCase(), registrationNumber: '', district: '', province: '');
}

pw.Widget _permitFieldRow(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.SizedBox(width: 165, child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
          pw.Expanded(
            child: value.isEmpty
                ? pw.Container(height: 0.75, color: _line, margin: const pw.EdgeInsets.only(bottom: 2))
                : pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );

/// Picks the exemption permit number to print: the farm's certificate with
/// the latest expiry date that hasn't already lapsed, or -- if all of them
/// have -- the most recently expired one, so there's still a number to
/// cross-check by hand rather than a misleadingly blank field.
String? _currentExemptionNumber(List<HuntingExemptionCertificate> certs, String farmId) {
  final forFarm = certs.where((c) => c.farmId == farmId).toList()..sort((a, b) => b.expiryDate.compareTo(a.expiryDate));
  if (forFarm.isEmpty) return null;
  final today = todayStr();
  final current = forFarm.where((c) => c.expiryDate.compareTo(today) >= 0).toList();
  return (current.isNotEmpty ? current.first : forFarm.first).permitNumber;
}

/// One permit per hunter, covering every animal on their invoice -- matches
/// the farm's paper "Permission to hunt and to transport carcass/meat"
/// template, wording and field order preserved as on the original. Only
/// relevant for local hunters -- callers should not offer this for
/// international guests.
Future<pw.Document> buildTransportPermitPdf(HuntingInvoice invoice, Farm farm, List<HuntingAnimalLine> animals, HuntingRepository repo) async {
  final doc = pw.Document();
  final logo = await _logo();
  final info = _permitInfoFor(farm);
  final certs = await repo.watchCertificates().first;
  final exemptionNumber = _currentExemptionNumber(certs, farm.id) ?? '';

  final speciesCounts = <String, int>{};
  for (final a in animals) {
    speciesCounts[a.species] = (speciesCounts[a.species] ?? 0) + 1;
  }

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
          _titleBanner('PERMISSION TO HUNT AND TO TRANSPORT CARCASS/MEAT'),
          pw.SizedBox(height: 14),
          pw.Text(
            'I, the undersigned, authorised representitive of NANINI 121 CC (CK 2000/026925/23) '
            'who is the owner of the following property:',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          _permitFieldRow('FARM NAME', info.displayName),
          _permitFieldRow('REGISTRATION NUMBER', info.registrationNumber),
          _permitFieldRow('DISCTRICT', info.district),
          _permitFieldRow('PROVINCE', info.province),
          _permitFieldRow('EXEMPTION PERMIT NUMBER', exemptionNumber),
          pw.SizedBox(height: 8),
          pw.Text('hereby give permission to:', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 12),
          _permitFieldRow('FULL NAMES OF HUNTER/TRANSPORTER', invoice.hunterName),
          _permitFieldRow('ID NUMBER', invoice.idOrPassport ?? ''),
          _permitFieldRow('PHONE NUMBER', ''),
          _permitFieldRow('EMAIL', ''),
          _permitFieldRow('RESIDENTIAL ADDRESS', ''),
          pw.SizedBox(height: 10),
          pw.Text(
            'to hunt the following game species on the abovementioned property from ${fmtDateDisplay(invoice.visitDate)} '
            'to ${fmtDateDisplay(invoice.visitDate)} and to transport the carcass(es)/meat to '
            '_________________________:',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['SPECIE', 'NUMBER'],
            data: [
              for (final e in speciesCounts.entries) [e.key, e.value.toString()],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFFBF6EF)),
            headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            cellStyle: const pw.TextStyle(fontSize: 10),
            border: pw.TableBorder.all(color: _line, width: 0.5),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1)},
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Should you have any enquiries, please contact me on ${_companyContact[1].replaceFirst('TEL: ', '')}.',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Expanded(child: pw.SizedBox()),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              for (final label in ['SIGNED (NANINI 121 CC)', 'DATE'])
                pw.Column(
                  children: [
                    pw.Container(width: 200, height: 1, color: _line),
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

Future<void> showTransportPermitPreview(
  BuildContext context,
  HuntingInvoice invoice,
  Farm farm,
  List<HuntingAnimalLine> animals,
  HuntingRepository repo,
) =>
    _showPdfPreview(context, () => buildTransportPermitPdf(invoice, farm, animals, repo));
