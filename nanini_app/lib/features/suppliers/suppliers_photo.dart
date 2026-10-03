import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Takes a photo of an invoice page with the camera; null when cancelled.
/// (Replaced in tests.)
Future<Uint8List?> Function() takeInvoicePhoto = _camera;

Future<Uint8List?> _camera() async {
  final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1800);
  return shot?.readAsBytes();
}

/// The photos of an invoice as one PDF, a page each (A4, the photo fitted).
Future<Uint8List> photosToPdf(List<Uint8List> photos) async {
  final doc = pw.Document();
  for (final p in photos) {
    final image = pw.MemoryImage(p);
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(16), build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))));
  }
  return doc.save();
}
