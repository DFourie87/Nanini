import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../features/capture/capture_models.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../ref_data.dart';

enum _S { supplier, kind, photo, amount, vat, number, date, check }

/// Takes a photo of an invoice page (one page per document); null when
/// cancelled. Kept small for sending over the farm's Wi-Fi. (Replaced in tests.)
Future<Uint8List?> Function() takeSupplierPhoto = () async {
  final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 60, maxWidth: 1600);
  return shot?.readAsBytes();
};

/// A supplier's invoice, credit note or statement: photographed, with its
/// total (and VAT), number and date typed from it. Goes to the office, where
/// an admin checks it and allocates it to GL accounts.
class SupplierFlow extends StatefulWidget {
  const SupplierFlow({super.key});
  @override
  State<SupplierFlow> createState() => _SupplierFlowState();
}

class _SupplierFlowState extends State<SupplierFlow> {
  RefItem? supplier;
  String? kind; // 'invoice', 'credit_note', 'statement'
  Uint8List? photo;
  String amount = '';
  String vat = '';
  final numberCtrl = TextEditingController();
  DateTime? date;
  int i = 0;

  bool get statement => kind == 'statement';
  List<_S> get steps => [
        _S.supplier,
        _S.kind,
        _S.photo,
        _S.amount,
        if (!statement) _S.vat,
        if (!statement) _S.number,
        _S.date,
        _S.check,
      ];

  String get kindLabel => switch (kind) { 'credit_note' => 'credit note', 'statement' => 'statement', _ => 'invoice' };

  void next() => setState(() => i = (i + 1).clamp(0, steps.length - 1));
  void back() => i == 0 ? Navigator.of(context).pop() : setState(() => i--);
  void _need(String msg) => showNeed(context, msg);

  @override
  void dispose() {
    numberCtrl.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final p = await takeSupplierPhoto();
    if (p != null && mounted) setState(() => photo = p);
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<CaptureStore>().ref;
    StepPage page(String q, Widget child, {VoidCallback? onNext, String? hint, String nextLabel = 'NEXT', IconData nextIcon = Icons.arrow_forward}) =>
        StepPage(task: 'Suppliers', step: i + 1, steps: steps.length, question: q, hint: hint, onBack: back, onNext: onNext, nextLabel: nextLabel, nextIcon: nextIcon, child: child);

    switch (steps[i]) {
      case _S.supplier:
        return page(
          'Which supplier?',
          ref.suppliers.isEmpty
              ? const EmptyListNote()
              : ListView(children: [
                  for (final s in ref.suppliers)
                    BigChoice(icon: Icons.store_mall_directory_outlined, label: s.name, selected: supplier?.id == s.id, onTap: () {
                      setState(() => supplier = s);
                      next();
                    }),
                ]),
        );
      case _S.kind:
        return page(
          'What is it?',
          ListView(children: [
            for (final (k, label, icon) in [
              ('invoice', 'INVOICE', Icons.receipt_long),
              ('credit_note', 'CREDIT NOTE', Icons.undo),
              ('statement', 'STATEMENT', Icons.description_outlined),
            ])
              BigChoice(icon: icon, label: label, selected: kind == k, onTap: () {
                setState(() => kind = k);
                next();
              }),
          ]),
        );
      case _S.photo:
        return page(
          'Take a photo of the $kindLabel',
          ListView(children: [
            if (photo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(photo!, height: 320, fit: BoxFit.contain)),
              ),
            BigChoice(icon: Icons.photo_camera, label: photo == null ? 'TAKE PHOTO' : 'TAKE AGAIN', onTap: _takePhoto),
          ]),
          hint: 'The whole page, flat, in good light',
          onNext: () => photo == null ? _need('Take the photo first') : next(),
        );
      case _S.amount:
        return page(
          statement ? 'Balance on the statement?' : 'Total of the $kindLabel (with VAT)?',
          NumberPad(value: amount, prefix: 'R', onChanged: (v) => setState(() => amount = v)),
          onNext: () => padValue(amount) == null || (!statement && padValue(amount)! <= 0) ? _need('Type the amount') : next(),
          hint: statement ? 'In credit? Type it and tell the office' : null,
        );
      case _S.vat:
        return page(
          'How much VAT is on it?',
          NumberPad(value: vat, prefix: 'R', onChanged: (v) => setState(() => vat = v)),
          hint: 'Leave empty if there is no VAT',
          onNext: () {
            final v = padValue(vat) ?? 0;
            if (v < 0 || v > (padValue(amount) ?? 0)) return _need('The VAT must be less than the total');
            next();
          },
        );
      case _S.number:
        return page(
          '${kindLabel[0].toUpperCase()}${kindLabel.substring(1)} number?',
          ListView(children: [
            TextField(
              controller: numberCtrl,
              style: const TextStyle(fontSize: 24),
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'e.g. INV12345'),
            ),
          ]),
          hint: 'You may leave it empty',
          onNext: next,
        );
      case _S.date:
        return page(
          'Date on the $kindLabel?',
          DayChoice(selected: date, onPick: (d) {
            setState(() => date = d);
            next();
          }),
        );
      case _S.check:
        final v = padValue(vat) ?? 0;
        return page(
          'Is this right?',
          ListView(children: [
            if (photo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(photo!, height: 160, fit: BoxFit.contain)),
              ),
            CheckLine(icon: Icons.store_mall_directory_outlined, text: supplier?.name ?? ''),
            CheckLine(icon: Icons.receipt_long, text: '${kindLabel[0].toUpperCase()}${kindLabel.substring(1)}'
                '${numberCtrl.text.trim().isEmpty ? '' : ' ${numberCtrl.text.trim()}'}'),
            CheckLine(icon: Icons.today, text: date == null ? '' : dayLabel(date!)),
            CheckLine(icon: Icons.payments, text: 'R${fmtNum(padValue(amount) ?? 0)}${statement ? '' : v > 0 ? ' (VAT R${fmtNum(v)})' : ' (no VAT)'}'),
          ]),
          hint: 'If something is wrong, press BACK',
          nextLabel: 'SAVE',
          nextIcon: Icons.check,
          onNext: _save,
        );
    }
  }

  Future<void> _save() async {
    final store = context.read<CaptureStore>();
    final total = padValue(amount) ?? 0;
    final v = statement ? null : (padValue(vat) ?? 0);
    final payload = <String, dynamic>{
      'supplier_id': supplier!.id,
      'supplier_name': supplier!.name,
      'kind': kind,
      'date': dayStr(date ?? DateTime.now()),
      'amount': total,
      'vat': ?v,
      if (numberCtrl.text.trim().isNotEmpty) 'reference': numberCtrl.text.trim(),
    };
    await store.add(CaptureModule.supplierDoc, payload, '${supplier!.name}: $kindLabel R${fmtNum(total)}', photo: photo);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(task: kindLabel, another: (_) => const SupplierFlow())));
  }
}
