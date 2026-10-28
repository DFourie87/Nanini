import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../features/capture/capture_models.dart';
import '../../theme/nanini_theme.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../ref_data.dart';
import '../timesheet_reader.dart';
import '../../core/run_once.dart';

/// Takes a photo of a timesheet page: its bytes and the file (for reading);
/// null when cancelled. Larger and sharper than other photos: every day's box
/// must be readable. (Replaced in tests.)
Future<({Uint8List bytes, String path})?> Function() takeTimesheetPhoto = () async {
  final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 3200, maxHeight: 3200);
  return shot == null ? null : (bytes: await shot.readAsBytes(), path: shot.path);
};

/// Reads a timesheet photo on the phone with Google's on-phone recognition
/// (free, no internet): the QR code, then the text. (Replaced in tests.)
Future<Map<String, dynamic>> Function(String path, RefData ref) readTimesheetPhoto = (path, ref) async {
  final image = InputImage.fromFilePath(path);
  final scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  final List<Barcode> codes;
  try {
    codes = await scanner.processImage(image);
  } finally {
    await scanner.close();
  }
  final qr = codes.map((b) => b.rawValue).whereType<String>().where((t) => t.startsWith('NTS')).firstOrNull;
  if (qr == null) throw SheetReadProblem('No QR code found -- take the photo again: the whole page, flat, sharp, in good light');
  final code = SheetCode.parse(qr);
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final RecognizedText text;
  try {
    text = await recognizer.processImage(image);
  } finally {
    await recognizer.close();
  }
  OcrBox box(String t, Rect r) => OcrBox(t, r.center.dx, r.center.dy, w: r.width, h: r.height);
  final words = <OcrBox>[], symbols = <OcrBox>[];
  for (final block in text.blocks) {
    for (final line in block.lines) {
      for (final e in line.elements) {
        words.add(box(e.text, e.boundingBox));
        for (final s in e.symbols) {
          symbols.add(box(s.text, s.boundingBox));
        }
      }
    }
  }
  return readSheet(code: code, words: words, symbols: symbols, ref: ref);
};

/// A filled-in printed timesheet, one page at a time: photographed and read
/// on the phone (the page's QR code says which farm, days and workers), then
/// sent to the office with the photo, where someone checks it in the hub.
class TimesheetFlow extends StatefulWidget {
  const TimesheetFlow({super.key});
  @override
  State<TimesheetFlow> createState() => _TimesheetFlowState();
}

class _TimesheetFlowState extends State<TimesheetFlow> {
  Uint8List? photo;
  Map<String, dynamic>? read;
  String? problem;
  bool reading = false;

  Future<void> _take() async {
    final shot = await takeTimesheetPhoto();
    if (shot == null || !mounted) return;
    setState(() {
      photo = shot.bytes;
      read = null;
      problem = null;
      reading = true;
    });
    final ref = context.read<CaptureStore>().ref;
    try {
      final r = await readTimesheetPhoto(shot.path, ref);
      if (mounted) setState(() => read = r);
    } on SheetReadProblem catch (e) {
      if (mounted) setState(() => problem = e.message);
    } catch (e) {
      if (mounted) setState(() => problem = 'Could not read the photo -- take it again ($e)');
    } finally {
      if (mounted) setState(() => reading = false);
    }
  }

  Future<void> _send() async {
    final r = read;
    if (photo == null || r == null) return showNeed(context, 'Take a photo that can be read first');
    final rows = (r['rows'] as List).cast<Map>();
    final people = rows.where((x) => (x['hours'] as List).any((h) => '$h'.isNotEmpty)).length;
    await context.read<CaptureStore>().add(CaptureModule.timesheet, {'kind': 'page', 'read': r}, 'Timesheet ${r['farm_name']} page ${r['page']}: $people workers',
        photo: photo);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(task: 'page', another: (_) => const TimesheetFlow())));
  }

  @override
  Widget build(BuildContext context) {
    final r = read;
    final rows = r == null ? const <Map>[] : (r['rows'] as List).cast<Map>();
    final people = rows.where((x) => (x['hours'] as List).any((h) => '$h'.isNotEmpty)).length;
    return StepPage(
      task: 'Timesheet',
      step: 1,
      steps: 1,
      question: 'Photo of one page',
      hint: 'Flat, in good light, the whole page with its 4 black corners and the QR code',
      onBack: () => Navigator.of(context).pop(),
      onNext: r == null ? null : () => runOnce('timesheet_flow.2', _send),
      nextLabel: 'SEND',
      nextIcon: Icons.send,
      child: ListView(children: [
        if (photo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(photo!, height: 280, fit: BoxFit.contain)),
          ),
        if (reading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text('Reading the sheet…', style: TextStyle(fontSize: 20))]),
          ),
        if (problem != null)
          CheckLine(icon: Icons.error, color: NaniniColors.red, text: problem!),
        if (r != null) ...[
          CheckLine(icon: Icons.check_circle, color: NaniniColors.green, text: '${r['farm_name']} · page ${r['page']}'),
          CheckLine(icon: Icons.people, text: '$people workers with hours'),
          if ('${r['notes']}'.isNotEmpty) CheckLine(icon: Icons.help, color: NaniniColors.amber, text: '${r['notes']} -- the office checks them'),
        ],
        const SizedBox(height: 8),
        if (!reading)
          BigChoice(icon: Icons.photo_camera, label: photo == null ? 'TAKE PHOTO' : 'TAKE AGAIN', onTap: () => runOnce('timesheet_flow.1', _take)),
      ]),
    );
  }
}
