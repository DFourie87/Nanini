import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/formatters.dart';
import 'delivery_models.dart';

const _letterhead = [
  'NANINI 121 CC T/A NANINI BOERDERY',
  'Farm Limpopodraai 751 LQ',
  'Lephalale',
  'Limpopo Province',
  '0555',
  'E-MAIL: fourie05@gmail.com',
  'TEL: 082 790 7808 / 082 442 4329',
  'REG: 2000/026925/23',
  'VAT: 4840191854',
];

Future<pw.Document> buildDeliveryNotePdf(DeliveryNote note) async {
  final doc = pw.Document();
  final rows = <List<String>>[];

  if (note.produceType == 'potato') {
    for (final s in kPalletSizes) {
      final count = (note.pallets[s.key] as num?)?.toInt() ?? 0;
      if (count > 0) rows.add([s.label, '$count pallets']);
    }
    for (final mp in note.mixedPallets) {
      final m = (mp as Map).cast<String, dynamic>();
      final lines = (m['lines'] as List?)?.cast<dynamic>() ?? [];
      rows.add(['Mixed pallet', lines.length.toString()]);
    }
  } else if (note.produceDetail != null) {
    note.produceDetail!.forEach((k, v) {
      final n = (v as num?)?.toInt() ?? 0;
      if (n > 0) rows.add([k, '$n']);
    });
  }

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('DELIVERY NOTE', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          for (final l in _letterhead) pw.Text(l, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Note #: ${note.noteNumber ?? '-'}'),
              pw.Text('Date: ${fmtDateDisplay(note.noteDate)}'),
            ],
          ),
          pw.Text('Truck reg: ${note.reg ?? '-'}'),
          if (note.transportCompany != null && note.transportCompany!.isNotEmpty) pw.Text('Transport: ${note.transportCompany}'),
          if (note.agentName != null) pw.Text('Market agent: ${note.agentName} (${note.agentAttention ?? ''})'),
          if (note.field != null && note.field!.isNotEmpty) pw.Text('Field: ${note.field}'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['Item', 'Quantity'],
            data: rows,
          ),
          pw.SizedBox(height: 16),
          pw.Text('Total: ${note.total}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
