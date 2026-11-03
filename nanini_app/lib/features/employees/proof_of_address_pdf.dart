import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatters.dart';

/// A member's proof of address on NANINI 121 CC's letterhead (Employees >
/// List > Members > Proof of address): the member, the farm they live on,
/// the day and who signs -- picked, nothing typed.
const _companyName = 'NANINI 121 CC T/A NANINI BOERDERY';
const _companyReg = '2000/026925/23';
const _companyContact = [
  'E-MAIL: fourie05@gmail.com',
  'TEL: 082 790 7808 / 082 442 4329',
  'REG: $_companyReg',
  'VAT: 4840191854',
];
const _logoAssetPath = 'assets/images/hub-logo-print.png';
const _logoAspectRatio = 966 / 700;
const _headerBlockHeight = 92.0;

final _rust = PdfColor.fromInt(0xFFEC1F24);
final _rustDark = PdfColor.fromInt(0xFFC41A1E);
final _muted = PdfColor.fromInt(0xFF4A4A4A);

/// The farms' physical addresses (as on the delivery notes), and the CC's
/// registered office (on its founding statement).
const kFarmAddresses = <String, List<String>>{
  'Limpopodraai': ['Farm Limpopodraai 751LQ', 'Lephalale', 'Limpopo Province', '0555'],
  'Haaskraal': ['Farm Haaskraal 134MR', 'Swartwater', 'Limpopo Province', '0622'],
  'Doornbult': ['Plot 108 Doornbult', 'Polokwane', 'Limpopo Province', '0699'],
};

/// The registered office's key in [kFarmAddresses].
const kRegisteredOffice = 'Doornbult';

/// What the letter says about the address after it: the farm run by the CC,
/// its registered office, or nothing (the member's own address).
String? addressNote(String? key) => switch (key) {
      kRegisteredOffice => 'This is the registered office of NANINI 121 CC.',
      null => null,
      _ => 'This is the address of the farm run by NANINI 121 CC T/A NANINI BOERDERY.',
    };

/// A typed address (a line each, or commas) as its lines.
List<String> addressLines(String? text) =>
    [for (final l in (text ?? '').split(RegExp(r'[\n,]'))) if (l.trim().isNotEmpty) l.trim()];

/// The farm address for a member on [farmName] (Haaskraal, else
/// Limpopodraai).
String farmAddressFor(String? farmName) => (farmName ?? '').contains('Haaskraal') ? 'Haaskraal' : 'Limpopodraai';

/// What goes in a proof of address letter.
class ProofOfAddress {
  const ProofOfAddress({
    required this.memberName,
    required this.idNumber,
    required this.address,
    required this.date,
    required this.signedBy,
    this.since,
    this.addressedTo = 'To whom it may concern',
    this.note,
    this.letterhead,
    this.utilityPage,
    this.utilityLabel,
  });

  /// Full names and surname (as on the ID).
  final String memberName;
  final String? idNumber;
  final List<String> address;

  /// yyyy-MM-dd.
  final String date;
  final String signedBy;

  /// Living there since (e.g. "2005" or "March 2010"); null: not said.
  final String? since;
  final String addressedTo;

  /// Said after the address ([addressNote]); null: nothing.
  final String? note;

  /// The CC's address at the top; null: [address] (a farm's).
  final List<String>? letterhead;

  /// The utility bill's first page (a picture), on a page of its own after
  /// the letter; [utilityLabel] what it is ("Eskom account 64.., bill of ..").
  final Uint8List? utilityPage;
  final String? utilityLabel;
}

/// The letter's paragraphs (also used by the tests).
List<String> proofOfAddressParagraphs(ProofOfAddress p) {
  final id = (p.idNumber ?? '').trim();
  return [
    'This letter serves to confirm that ${p.memberName}'
        '${id.isEmpty ? '' : ' (identity number $id)'} is a member of NANINI 121 CC (registration number $_companyReg) '
        'and resides at the following physical address:',
    p.address.join(', '),
    if ((p.since ?? '').trim().isNotEmpty) '${p.memberName} has lived at this address since ${p.since!.trim()}.',
    if (p.utilityLabel != null) 'Attached is the first page of the latest utility account for this address (${p.utilityLabel}).',
    '${p.note == null ? '' : '${p.note} '}Please do not hesitate to contact the undersigned should you need any further information.',
  ];
}

Future<pw.Document> buildProofOfAddressPdf(ProofOfAddress p) async {
  final doc = pw.Document();
  final logo = pw.MemoryImage((await rootBundle.load(_logoAssetPath)).buffer.asUint8List());
  final paras = proofOfAddressParagraphs(p);
  const body = pw.TextStyle(fontSize: 11.5, lineSpacing: 3);
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(48, 40, 48, 40),
    build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Image(logo, height: _headerBlockHeight, width: _headerBlockHeight * _logoAspectRatio),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(_companyName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            for (final l in p.letterhead ?? p.address) pw.Text(l, style: pw.TextStyle(fontSize: 8, color: _muted)),
            pw.SizedBox(height: 4),
            for (final l in _companyContact) pw.Text(l, style: pw.TextStyle(fontSize: 8, color: _muted)),
          ]),
        ],
      ),
      pw.SizedBox(height: 12),
      pw.Container(height: 3, color: _rust),
      pw.SizedBox(height: 22),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(fmtDateDisplay(p.date), style: body)),
      pw.SizedBox(height: 18),
      pw.Text(p.addressedTo.trim().isEmpty ? 'To whom it may concern' : p.addressedTo.trim(), style: body),
      pw.SizedBox(height: 16),
      pw.Text('CONFIRMATION OF RESIDENTIAL ADDRESS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _rustDark)),
      pw.SizedBox(height: 14),
      pw.Text(paras[0], style: body),
      pw.SizedBox(height: 10),
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 24),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [for (final l in p.address) pw.Text(l, style: body.copyWith(fontWeight: pw.FontWeight.bold))]),
      ),
      pw.SizedBox(height: 10),
      for (final t in paras.skip(2)) ...[pw.Text(t, style: body), pw.SizedBox(height: 10)],
      pw.SizedBox(height: 6),
      pw.Text('Yours faithfully', style: body),
      pw.SizedBox(height: 46),
      pw.Container(width: 220, height: 0.8, color: PdfColors.black),
      pw.SizedBox(height: 4),
      pw.Text(p.signedBy, style: body.copyWith(fontWeight: pw.FontWeight.bold)),
      pw.Text('Member, NANINI 121 CC', style: body),
      pw.Text('Reg. $_companyReg', style: body.copyWith(color: _muted)),
    ]),
  ));
  if (p.utilityPage != null) {
    final bill = pw.MemoryImage(p.utilityPage!);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Utility account: ${p.utilityLabel ?? ''}', style: pw.TextStyle(fontSize: 9, color: _muted)),
        pw.SizedBox(height: 6),
        pw.Expanded(child: pw.Center(child: pw.Image(bill, fit: pw.BoxFit.contain))),
      ]),
    ));
  }
  return doc;
}
