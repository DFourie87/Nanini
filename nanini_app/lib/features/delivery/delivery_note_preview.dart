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
  'PRODUCER NO: 92220',
];

List<String> _addressFor(String produceType) => produceType == 'pepper' ? _addressPepper : _addressDefault;

String _sizeLabel(String key) => kPalletSizes.firstWhere((s) => s.key == key, orElse: () => PalletSize(key, key, 0, '', 1)).label;

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
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Image(logo, width: 70),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(_companyName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    for (final l in address) pw.Text(l, style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 4),
                    for (final l in _companyContact) pw.Text(l, style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Center(child: pw.Text('DELIVERY NOTE', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('No: ${note.noteNumber ?? '-'}'),
              pw.Text('Date: ${fmtDateDisplay(note.noteDate)}'),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text('RECIPIENT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.SizedBox(height: 4),
          if (note.agentName != null) pw.Text(note.agentName!),
          if (note.agentAttention != null && note.agentAttention!.isNotEmpty) pw.Text(note.agentAttention!),
          if (note.agentMarket != null && note.agentMarket!.isNotEmpty) pw.Text(note.agentMarket!),
          pw.SizedBox(height: 8),
          pw.Text('Truck reg: ${note.reg ?? '-'}', style: const pw.TextStyle(fontSize: 10)),
          if (note.transportCompany != null && note.transportCompany!.isNotEmpty)
            pw.Text('Transport: ${note.transportCompany}', style: const pw.TextStyle(fontSize: 10)),
          if (note.field != null && note.field!.isNotEmpty) pw.Text('Field: ${note.field}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['QUANTITY', 'DESCRIPTION'],
            data: rows,
          ),
          pw.SizedBox(height: 16),
          pw.Text('Total: ${note.total}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 40),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(children: [pw.Text('____________________'), pw.Text('NANINI BOERDERY', style: const pw.TextStyle(fontSize: 9))]),
              pw.Column(children: [pw.Text('____________________'), pw.Text('DRIVER', style: const pw.TextStyle(fontSize: 9))]),
              pw.Column(children: [pw.Text('____________________'), pw.Text('RECIPIENT', style: const pw.TextStyle(fontSize: 9))]),
            ],
          ),
        ],
      ),
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
