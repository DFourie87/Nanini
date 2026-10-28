import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../features/capture/capture_models.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../../core/run_once.dart';

/// Takes a photo of a timesheet page; null when cancelled. Larger and sharper
/// than other photos: every day's box must be readable. (Replaced in tests.)
Future<Uint8List?> Function() takeTimesheetPhoto = () async {
  final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 3200, maxHeight: 3200);
  return shot?.readAsBytes();
};

/// A filled-in printed timesheet, one page at a time: photographed and sent
/// to the office. The office PC reads the hours from it (the page's QR code
/// says which farm, days and workers); someone checks them in the hub.
class TimesheetFlow extends StatefulWidget {
  const TimesheetFlow({super.key});
  @override
  State<TimesheetFlow> createState() => _TimesheetFlowState();
}

class _TimesheetFlowState extends State<TimesheetFlow> {
  Uint8List? photo;

  Future<void> _take() async {
    final p = await takeTimesheetPhoto();
    if (p != null && mounted) setState(() => photo = p);
  }

  Future<void> _send() async {
    if (photo == null) return showNeed(context, 'Take the photo first');
    await context.read<CaptureStore>().add(CaptureModule.timesheet, {'kind': 'page'}, 'Timesheet page', photo: photo);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(task: 'page', another: (_) => const TimesheetFlow())));
  }

  @override
  Widget build(BuildContext context) {
    return StepPage(
      task: 'Timesheet',
      step: 1,
      steps: 1,
      question: 'Photo of one page',
      hint: 'Flat, in good light, the whole page with its 4 black corners and the QR code',
      onBack: () => Navigator.of(context).pop(),
      onNext: photo == null ? null : () => runOnce('timesheet_flow.2', _send),
      nextLabel: 'SEND',
      nextIcon: Icons.send,
      child: ListView(children: [
        if (photo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(photo!, height: 320, fit: BoxFit.contain)),
          ),
        BigChoice(icon: Icons.photo_camera, label: photo == null ? 'TAKE PHOTO' : 'TAKE AGAIN', onTap: () => runOnce('timesheet_flow.1', _take)),
      ]),
    );
  }
}
