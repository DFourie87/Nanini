import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/capture/capture_models.dart';
import '../../theme/nanini_theme.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../fridge_reader.dart';
import '../ref_data.dart';
import '../timesheet_reader.dart';
import '../../core/run_once.dart';
import 'timesheet_flow.dart';

/// Reads a fridge sheet photo on the phone: the QR code, then the marks.
/// (Replaced in tests.)
Future<Map<String, dynamic>> Function(String path, RefData ref) readFridgePhoto = (path, ref) async {
  final t = await readSheetPhotoText(path, 'NFS');
  return readFridgeSheet(code: FridgeCode.parse(t.qr), words: t.words, symbols: t.symbols, ref: ref);
};

/// A filled-in fridge sheet (wors, chicken pieces), one page at a time:
/// photographed and read on the phone (the page's QR code says which farm,
/// items and workers), then sent to the office with the photo, where someone
/// checks the counts in the hub (Tuck shop > Captured) before they go on
/// the workers' tuck shop accounts.
class FridgeSheetFlow extends StatefulWidget {
  const FridgeSheetFlow({super.key});
  @override
  State<FridgeSheetFlow> createState() => _FridgeSheetFlowState();
}

class _FridgeSheetFlowState extends State<FridgeSheetFlow> {
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
      final r = await readFridgePhoto(shot.path, ref);
      if (mounted) setState(() => read = r);
    } on SheetReadProblem catch (e) {
      if (mounted) setState(() => problem = e.message);
    } catch (e) {
      if (mounted) setState(() => problem = 'Could not read the photo -- take it again ($e)');
    } finally {
      if (mounted) setState(() => reading = false);
    }
  }

  /// Per item: how many were taken on this page, as read (the total written,
  /// else the marks counted).
  static List<(String, int)> _taken(Map<String, dynamic> r) {
    final items = (r['items'] as List).cast<Map>();
    final rows = (r['rows'] as List).cast<Map>();
    return [
      for (final (i, item) in items.indexed)
        (
          '${item['name']}',
          rows.fold<int>(0, (s, row) {
            final c = ((row['counts'] as List)[i] as Map);
            return s + (int.tryParse('${c['total']}') ?? (c['marks'] as num).toInt());
          }),
        ),
    ];
  }

  static int _people(Map<String, dynamic> r) =>
      (r['rows'] as List).cast<Map>().where((row) => (row['counts'] as List).cast<Map>().any((c) => c['marks'] != 0 || '${c['total']}'.isNotEmpty)).length;

  Future<void> _send() async {
    final r = read;
    if (photo == null || r == null) return showNeed(context, 'Take a photo that can be read first');
    final taken = _taken(r).map((t) => '${t.$2} ${t.$1}').join(', ');
    await context.read<CaptureStore>().add(CaptureModule.fridgeSheet, {'kind': 'page', 'read': r}, 'Fridge sheet ${r['farm_name']} page ${r['page']}: $taken',
        photo: photo);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(task: 'page', another: (_) => const FridgeSheetFlow())));
  }

  @override
  Widget build(BuildContext context) {
    final r = read;
    return StepPage(
      task: 'Fridge sheet',
      step: 1,
      steps: 1,
      question: 'Photo of one page',
      hint: 'Flat, in good light, the whole page with its 4 black corners and the QR code',
      onBack: () => Navigator.of(context).pop(),
      onNext: r == null ? null : () => runOnce('fridge_sheet_flow.2', _send),
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
        if (problem != null) CheckLine(icon: Icons.error, color: NaniniColors.red, text: problem!),
        if (r != null) ...[
          CheckLine(icon: Icons.check_circle, color: NaniniColors.green, text: '${r['farm_name']} · page ${r['page']}'),
          CheckLine(icon: Icons.people, text: '${_people(r)} workers took something'),
          for (final (name, n) in _taken(r)) CheckLine(icon: Icons.kitchen, text: '$name: $n'),
          if ('${r['notes']}'.isNotEmpty) CheckLine(icon: Icons.help, color: NaniniColors.amber, text: '${r['notes']} -- the office checks them'),
        ],
        const SizedBox(height: 8),
        if (!reading)
          BigChoice(icon: Icons.photo_camera, label: photo == null ? 'TAKE PHOTO' : 'TAKE AGAIN', onTap: () => runOnce('fridge_sheet_flow.1', _take)),
      ]),
    );
  }
}
