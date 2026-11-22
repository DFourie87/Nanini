import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/run_once.dart';
import '../../features/capture/capture_models.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import 'supplier_flow.dart' show takeSupplierPhoto;

enum _S { photo, shop, amount, vat, what, date, check }

/// A till slip paid from the petty cash: photographed, with the shop, the
/// total, the VAT on it, what it was for and the date. Goes to the office,
/// where it is checked, put against an account and sent to Xero.
class CashSlipFlow extends StatefulWidget {
  const CashSlipFlow({super.key});
  @override
  State<CashSlipFlow> createState() => _CashSlipFlowState();
}

class _CashSlipFlowState extends State<CashSlipFlow> {
  Uint8List? photo;
  final shopCtrl = TextEditingController();
  final whatCtrl = TextEditingController();
  String amount = '';
  String vat = '';
  DateTime? date;
  int i = 0;

  static const steps = _S.values;

  void next() => setState(() => i = (i + 1).clamp(0, steps.length - 1));
  void back() => i == 0 ? Navigator.of(context).pop() : setState(() => i--);
  void _need(String msg) => showNeed(context, msg);

  @override
  void dispose() {
    shopCtrl.dispose();
    whatCtrl.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final p = await takeSupplierPhoto();
    if (p != null && mounted) setState(() => photo = p);
  }

  Widget _text(TextEditingController c, String hint) => ListView(
    children: [
      TextField(
        controller: c,
        style: const TextStyle(fontSize: 24),
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    StepPage page(String q, Widget child, {VoidCallback? onNext, String? hint, String nextLabel = 'NEXT', IconData nextIcon = Icons.arrow_forward}) => StepPage(
      task: 'Cash slip',
      step: i + 1,
      steps: steps.length,
      question: q,
      hint: hint,
      onBack: back,
      onNext: onNext,
      nextLabel: nextLabel,
      nextIcon: nextIcon,
      child: child,
    );

    switch (steps[i]) {
      case _S.photo:
        return page(
          'Take a photo of the slip',
          ListView(
            children: [
              if (photo != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(photo!, height: 320, fit: BoxFit.contain),
                  ),
                ),
              BigChoice(icon: Icons.photo_camera, label: photo == null ? 'TAKE PHOTO' : 'TAKE AGAIN', onTap: () => runOnce('cash_slip_flow.photo', _takePhoto)),
            ],
          ),
          hint: 'The whole slip, flat, in good light',
          onNext: () => photo == null ? _need('Take the photo first') : next(),
        );
      case _S.shop:
        return page(
          'Which shop?',
          _text(shopCtrl, 'e.g. Builders Lephalale'),
          hint: 'As on the slip',
          onNext: () => shopCtrl.text.trim().isEmpty ? _need('Type the shop') : next(),
        );
      case _S.amount:
        return page(
          'Total paid (with VAT)?',
          NumberPad(value: amount, prefix: 'R', onChanged: (v) => setState(() => amount = v)),
          onNext: () => (padValue(amount) ?? 0) <= 0 ? _need('Type the amount') : next(),
        );
      case _S.vat:
        return page(
          'How much VAT is on it?',
          NumberPad(value: vat, prefix: 'R', onChanged: (v) => setState(() => vat = v)),
          hint: 'Leave empty if the slip shows no VAT',
          onNext: () {
            final v = padValue(vat) ?? 0;
            if (v < 0 || v >= (padValue(amount) ?? 0)) return _need('The VAT must be less than the total');
            next();
          },
        );
      case _S.what:
        return page(
          'What was it for?',
          _text(whatCtrl, 'e.g. Bolts for the planter'),
          hint: 'A few words, for the office',
          onNext: () => whatCtrl.text.trim().isEmpty ? _need('Type what it was for') : next(),
        );
      case _S.date:
        return page(
          'Date on the slip?',
          DayChoice(
            selected: date,
            onPick: (d) {
              setState(() => date = d);
              next();
            },
          ),
        );
      case _S.check:
        final v = padValue(vat) ?? 0;
        return page(
          'Is this right?',
          ListView(
            children: [
              if (photo != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(photo!, height: 160, fit: BoxFit.contain),
                  ),
                ),
              CheckLine(icon: Icons.storefront, text: shopCtrl.text.trim()),
              CheckLine(icon: Icons.notes, text: whatCtrl.text.trim()),
              CheckLine(icon: Icons.today, text: date == null ? '' : dayLabel(date!)),
              CheckLine(icon: Icons.payments, text: 'R${fmtNum(padValue(amount) ?? 0)}${v > 0 ? ' (VAT R${fmtNum(v)})' : ' (no VAT)'}'),
            ],
          ),
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
    final payload = <String, dynamic>{
      'date': dayStr(date ?? DateTime.now()),
      'shop': shopCtrl.text.trim(),
      'description': whatCtrl.text.trim(),
      'amount': total,
      'vat': padValue(vat) ?? 0,
    };
    await store.add(CaptureModule.cashSlip, payload, 'Cash slip: ${shopCtrl.text.trim()} R${fmtNum(total)}', photo: photo);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SavedScreen(task: 'cash slip', another: (_) => const CashSlipFlow()),
      ),
    );
  }
}
