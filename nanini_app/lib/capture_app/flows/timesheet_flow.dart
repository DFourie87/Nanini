import 'dart:io';
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
import '../photo_orientation.dart';
import '../timesheet_reader.dart';
import '../../features/capture/timesheet_capture.dart' show TimesheetRead;
import 'sheet_check.dart';
import '../../core/run_once.dart';

/// Takes a photo of a timesheet page: its bytes and the file (for reading);
/// null when cancelled. The camera's own photo, full size and not compressed
/// again: the QR code and every day's box must be readable (a smaller copy
/// blurred them). (Replaced in tests.)
Future<({Uint8List bytes, String path})?> Function() takeTimesheetPhoto = () async {
  final shot = await ImagePicker().pickImage(source: ImageSource.camera);
  return shot == null ? null : (bytes: await shot.readAsBytes(), path: shot.path);
};

/// A sheet photo's QR code (the first starting with [prefix]) and its text,
/// read on the phone with Google's on-phone recognition (free, no internet).
/// The text reader reads only text the right way up: a landscape sheet
/// photographed with the phone upright is sideways, so when the photo as it
/// is doesn't read as a sheet the right way up it is also read turned a
/// quarter each way and upside down, and the way reading best is used
/// ([sheetUprightScore]).
/// [qrPath]: a close photo of just the QR code, when it couldn't be read in
/// the page's photo ([NoQrCode]).
Future<({String qr, List<OcrBox> words, List<OcrBox> symbols})> readSheetPhotoText(String path, String prefix, {String? qrPath}) async {
  final scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  String? qr;
  try {
    qr = (await scanner.processImage(InputImage.fromFilePath(qrPath ?? path))).map((b) => b.rawValue).whereType<String>().where((t) => t.startsWith(prefix)).firstOrNull;
  } finally {
    await scanner.close();
  }
  if (qr == null && qrPath != null) throw SheetReadProblem('No QR code in that photo -- take it again: closer, sharp, only the QR code');
  if (qr == null) throw NoQrCode('No QR code found -- take the photo again: close up, flat, sharp, in good light, the QR code in it');
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    var best = await _readText(recognizer, path);
    if (sheetUprightScore(best.words) < kUprightNumbers) {
      final bytes = await File(path).readAsBytes();
      for (final turn in const [90, 270, 180]) {
        final turned = jpegTurned(bytes, turn);
        if (turned == null) break;
        final file = File('$path.turned$turn.jpg');
        try {
          await file.writeAsBytes(turned, flush: true);
          final t = await _readText(recognizer, file.path);
          if (sheetUprightScore(t.words) > sheetUprightScore(best.words)) best = t;
        } finally {
          if (await file.exists()) await file.delete();
        }
        if (sheetUprightScore(best.words) >= kUprightNumbers) break;
      }
    }
    return (qr: qr, words: best.words, symbols: best.symbols);
  } finally {
    await recognizer.close();
  }
}

Future<({List<OcrBox> words, List<OcrBox> symbols})> _readText(TextRecognizer recognizer, String path) async {
  final text = await recognizer.processImage(InputImage.fromFilePath(path));
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
  return (words: words, symbols: symbols);
}

/// Reads a timesheet photo on the phone: the QR code, then the text.
/// (Replaced in tests.)
/// [qrPath]: a close photo of just its QR code (see [NoQrCode]).
Future<Map<String, dynamic>> Function(String path, RefData ref, String? qrPath) readTimesheetPhoto = (path, ref, qrPath) async {
  final t = await readSheetPhotoText(path, 'NTS', qrPath: qrPath);
  return readSheet(code: SheetCode.parse(t.qr), words: t.words, symbols: t.symbols, ref: ref);
};

/// A filled-in printed timesheet, one page at a time: photographed and read
/// on the phone (the page's QR code says which farm, days and workers),
/// checked on the phone by the person who took it, then saved: the hours go
/// straight in (no office approval), with the photo kept.
class TimesheetFlow extends StatefulWidget {
  const TimesheetFlow({super.key, this.farm});

  /// The farm chosen in Hours: a sheet of another farm is refused.
  final RefItem? farm;
  @override
  State<TimesheetFlow> createState() => _TimesheetFlowState();
}

class _TimesheetFlowState extends State<TimesheetFlow> {
  Uint8List? photo;
  String? photoPath;
  Map<String, dynamic>? read;
  String? problem;
  bool reading = false;

  /// The page's photo has no readable QR code (printed small, before Nov
  /// 2026): a close photo of just the QR code is asked for.
  bool needQr = false;

  Future<void> _take() async {
    final shot = await takeTimesheetPhoto();
    if (shot == null || !mounted) return;
    setState(() {
      photo = shot.bytes;
      photoPath = shot.path;
      needQr = false;
    });
    await _read(shot.path, null);
  }

  /// A close photo of just the QR code, for the page photographed already.
  Future<void> _takeQr() async {
    final page = photoPath;
    if (page == null) return;
    final shot = await takeTimesheetPhoto();
    if (shot == null || !mounted) return;
    await _read(page, shot.path);
  }

  Future<void> _read(String path, String? qrPath) async {
    setState(() {
      read = null;
      problem = null;
      reading = true;
    });
    final ref = context.read<CaptureStore>().ref;
    try {
      final r = await readTimesheetPhoto(path, ref, qrPath);
      final farm = widget.farm;
      if (farm != null && r['farm_id'] != farm.id) {
        throw SheetReadProblem("This is ${r['farm_name']}'s timesheet, not ${farm.name}'s -- go back and choose ${r['farm_name']}, or photograph ${farm.name}'s sheet");
      }
      if (mounted) {
        setState(() {
          read = r;
          needQr = false;
        });
      }
    } on NoQrCode {
      if (mounted) {
        setState(() {
          needQr = true;
          problem = "The QR code couldn't be read in this photo: take a close one of just the QR code (top right).";
        });
      }
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
    final shot = photo;
    if (shot == null || r == null) return showNeed(context, 'Take a photo that can be read first');
    // Checked here, by the person who took it: first who the workers
    // written in by hand are (new ones' details captured), then the hours --
    // then straight in.
    var workers = const <int, WrittenWorker>{};
    if (NewWorkersPage.writtenLines(TimesheetRead.fromPayload({'read': r})!).isNotEmpty) {
      final w = await Navigator.of(context).push<Map<int, WrittenWorker>>(MaterialPageRoute(builder: (_) => NewWorkersPage(read: r)));
      if (w == null || !mounted) return;
      workers = w;
    }
    final checked =
        await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => TimesheetCheckPage(photo: shot, read: r, workers: workers)));
    if (checked == null || !mounted) return;
    final people = {for (final l in (checked['lines'] as List).cast<Map>()) l['employee_id']}.length;
    await context.read<CaptureStore>().add(CaptureModule.timesheet, {'kind': 'page', 'read': r, 'checked': checked},
        'Timesheet ${r['farm_name']} page ${r['page']}: $people workers', photo: shot);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(task: 'page', another: (_) => TimesheetFlow(farm: widget.farm))));
  }

  @override
  Widget build(BuildContext context) {
    final r = read;
    final rows = r == null ? const <Map>[] : (r['rows'] as List).cast<Map>();
    final people = rows.where((x) => (x['hours'] as List).any((h) => '$h'.isNotEmpty)).length;
    return StepPage(
      task: 'Timesheet',
      step: 1,
      steps: 2,
      question: widget.farm == null ? 'Photo of one page' : "Photo of one page of ${widget.farm!.name}'s timesheet",
      hint: 'Flat, in good light: the whole sheet, from the numbers on the left to the QR code on the right',
      onBack: () => Navigator.of(context).pop(),
      onNext: r == null ? null : () => runOnce('timesheet_flow.2', _send),
      nextLabel: 'CHECK',
      nextIcon: Icons.arrow_forward,
      child: ListView(children: [
        if (photo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            // Smaller while the QR code's photo is asked for: its button in view.
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(photo!, height: needQr ? 140 : 280, fit: BoxFit.contain)),
          ),
        if (!reading && needQr && read == null)
          BigChoice(icon: Icons.qr_code_2, label: 'PHOTO OF THE QR CODE', onTap: () => runOnce('timesheet_flow.qr', _takeQr)),
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
          if ('${r['notes']}'.isNotEmpty) CheckLine(icon: Icons.help, color: NaniniColors.amber, text: '${r['notes']} -- check them on the next screen'),
        ],
        const SizedBox(height: 8),
        if (!reading)
          BigChoice(icon: Icons.photo_camera, label: photo == null ? 'TAKE PHOTO' : 'TAKE AGAIN', onTap: () => runOnce('timesheet_flow.1', _take)),
      ]),
    );
  }
}
