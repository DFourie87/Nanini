import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/formatters.dart';
import 'delivery_models.dart';

const _companyName = 'NANINI 121 CC T/A NANINI BOERDERY';
const _addressPepper = ['Farm Haaskraal 134MR', 'Swartwater', 'Limpopo Province', '0622'];
const _addressDefault = ['Farm Limpopodraai 751LQ', 'Lephalale', 'Limpopo Province', '0555'];
const _companyContact = [
  'E-MAIL: fourie05@gmail.com',
  'TEL: 082 790 7808 / 082 442 4329',
  'REG: 2000/026925/23',
  'VAT: 4840191854',
];
const _producerNo = '92220';
const _logoAspectRatio = 1598 / 1157;
const _headerBlockHeight = 92.0;

final _rust = PdfColor.fromInt(0xFFEC1F24);
final _rustDark = PdfColor.fromInt(0xFFC41A1E);
final _muted = PdfColor.fromInt(0xFF4A4A4A);
final _line = PdfColor.fromInt(0xFFE4D6C3);

List<String> _addressFor(String produceType) => produceType == 'pepper' ? _addressPepper : _addressDefault;

String _sizeLabel(String key) => kPalletSizes.firstWhere((s) => s.key == key, orElse: () => PalletSize(key, key, 0, '', 1)).label;

/// Total bags/boxes across all line items -- matches the DeliveryNote.total
/// stored value for pepper/butternut, and is the bag count (as opposed to
/// pallet count) for potato.
int _totalQty(List<List<String>> rows) => rows.fold<int>(0, (s, r) => s + (int.tryParse(r[0]) ?? 0));

String _totalLine(DeliveryNote note, List<List<String>> rows) {
  final qty = _totalQty(rows);
  switch (note.produceType) {
    case 'potato':
      final pallets = note.total;
      return 'Total: $qty bag${qty == 1 ? '' : 's'} / $pallets pallet${pallets == 1 ? '' : 's'}';
    case 'pepper':
      return 'Total: $qty box${qty == 1 ? '' : 'es'}';
    default:
      return 'Total: $qty bag${qty == 1 ? '' : 's'}';
  }
}

/// [quantity, description] pairs -- quantity is always bags/boxes, never
/// pallets; potato rows note the pallet count in the description instead.
List<List<String>> _buildRows(DeliveryNote note) {
  final rows = <List<String>>[];

  if (note.produceType == 'potato') {
    for (final s in kPalletSizes) {
      final palletCount = (note.pallets[s.key] as num?)?.toInt() ?? 0;
      if (palletCount <= 0) continue;
      final bags = palletCount * s.bagsPerPallet;
      rows.add(['$bags', '${s.label} (${palletCount} pallet${palletCount == 1 ? '' : 's'})']);
    }
    for (final mp in note.mixedPallets) {
      final m = (mp as Map).cast<String, dynamic>();
      final totalBags = m.values.fold<int>(0, (s, v) => s + ((v as num?)?.toInt() ?? 0));
      final parts = m.entries.map((e) => '${_sizeLabel(e.key)}: ${e.value}').join(', ');
      rows.add(['$totalBags', '$parts (1 pallet)']);
    }
  } else if (note.produceDetail != null) {
    note.produceDetail!.forEach((k, v) {
      final n = (v as num?)?.toInt() ?? 0;
      if (n > 0) rows.add(['$n', k]);
    });
  }

  return rows;
}

Future<pw.Document> buildDeliveryNotePdf(DeliveryNote note) async {
  final doc = pw.Document();
  final rows = _buildRows(note);
  final address = _addressFor(note.produceType);
  final logoBytes = await rootBundle.load('assets/images/hub-logo.jpg');
  final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Image(logo, height: _headerBlockHeight, width: _headerBlockHeight * _logoAspectRatio),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(_companyName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  for (final l in address) pw.Text(l, style: pw.TextStyle(fontSize: 8, color: _muted)),
                  pw.SizedBox(height: 4),
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
              child: pw.Text('DELIVERY NOTE', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Center(child: pw.Text('No: ${note.noteNumber ?? '-'}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _rustDark))),
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text('Producer No: $_producerNo', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _rustDark))),
          pw.SizedBox(height: 8),
          pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Date: ${fmtDateDisplay(note.noteDate)}', style: pw.TextStyle(color: _muted))),
          pw.SizedBox(height: 14),
          pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 1))),
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text('RECIPIENT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _rustDark)),
          ),
          pw.SizedBox(height: 6),
          if (note.agentName != null) pw.Text(note.agentName!),
          if (note.agentAttention != null && note.agentAttention!.isNotEmpty) pw.Text(note.agentAttention!),
          if (note.agentMarket != null && note.agentMarket!.isNotEmpty) pw.Text(note.agentMarket!),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['QUANTITY', 'DESCRIPTION'],
            data: rows,
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
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Truck reg: ${note.reg ?? '-'}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                  if (note.transportCompany != null && note.transportCompany!.isNotEmpty)
                    pw.Text('Transport: ${note.transportCompany}', style: pw.TextStyle(fontSize: 10, color: _muted)),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFFBF6EF), borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Text(_totalLine(note, rows), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _rustDark)),
              ),
            ],
          ),
          pw.SizedBox(height: 28),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              for (final label in ['NANINI BOERDERY', 'DRIVER', 'RECIPIENT'])
                pw.Column(
                  children: [
                    pw.Container(width: 130, height: 1, color: _line),
                    pw.SizedBox(height: 4),
                    pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _muted)),
                  ],
                ),
            ],
          ),
      ],
    ),
  );
  return doc;
}

Future<void> showDeliveryNotePreview(BuildContext context, DeliveryNote note) async {
  await showDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 500,
        height: 700,
        child: PdfPreview(
          build: (format) async => (await buildDeliveryNotePdf(note)).save(),
          allowSharing: true,
          allowPrinting: true,
          canChangeOrientation: false,
          canChangePageFormat: false,
        ),
      ),
    ),
  );
}
