import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/capture/capture_models.dart';
import '../../theme/nanini_theme.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../ref_data.dart';

enum _S { kind, tank, vehicle, litres, reading, activity, person, supplier, note, check }

/// Diesel: either diesel given out of a tank into a vehicle/machine, or a
/// delivery of diesel into a tank. Mirrors the hub's Diesel > Log entry.
class DieselFlow extends StatefulWidget {
  const DieselFlow({super.key});
  @override
  State<DieselFlow> createState() => _DieselFlowState();
}

class _DieselFlowState extends State<DieselFlow> {
  bool? isUsage;
  RefItem? tank;
  RefItem? vehicle;
  String litres = '';
  String reading = '';
  RefItem? activity;
  bool activityChosen = false;
  RefPerson? person;
  bool personChosen = false;
  final supplierCtrl = TextEditingController();
  String deliveryNote = '';
  int i = 0;

  List<_S> get steps => isUsage == false
      ? const [_S.kind, _S.tank, _S.litres, _S.supplier, _S.note, _S.check]
      : const [_S.kind, _S.tank, _S.vehicle, _S.litres, _S.reading, _S.activity, _S.person, _S.check];

  void next() => setState(() => i = (i + 1).clamp(0, steps.length - 1));
  void back() => i == 0 ? Navigator.of(context).pop() : setState(() => i--);

  void _need(String msg) => showNeed(context, msg);

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<CaptureStore>().ref;
    final s = steps[i];
    StepPage page(String q, Widget child, {VoidCallback? onNext, String? hint, String nextLabel = 'NEXT', IconData nextIcon = Icons.arrow_forward}) =>
        StepPage(task: 'Diesel', step: i + 1, steps: steps.length, question: q, hint: hint, onBack: back, onNext: onNext, nextLabel: nextLabel, nextIcon: nextIcon, child: child);

    switch (s) {
      case _S.kind:
        return page(
          'What happened?',
          ListView(children: [
            BigChoice(emoji: '🚚', label: 'DIESEL - IN', highlight: 'IN', highlightColor: NaniniColors.green, selected: isUsage == false, onTap: () {
              setState(() => isUsage = false);
              next();
            }),
            BigChoice(emoji: '⛽', label: 'DIESEL - OUT', highlight: 'OUT', highlightColor: NaniniColors.red, selected: isUsage == true, onTap: () {
              setState(() => isUsage = true);
              next();
            }),
          ]),
        );
      case _S.tank:
        return page(
          'Which tank?',
          ref.tanks.isEmpty
              ? const EmptyListNote()
              : ListView(children: [
                  for (final t in ref.tanks)
                    BigChoice(icon: Icons.local_gas_station, label: t.name, selected: tank?.id == t.id, onTap: () {
                      setState(() => tank = t);
                      next();
                    }),
                ]),
        );
      case _S.vehicle:
        return page(
          'Which machine or vehicle?',
          ref.vehicles.isEmpty
              ? const EmptyListNote()
              : ListView(children: [
                  for (final v in ref.vehicles)
                    BigChoice(
                      icon: v.unit == 'km' ? Icons.local_shipping : Icons.agriculture,
                      label: v.name,
                      selected: vehicle?.id == v.id,
                      onTap: () {
                        setState(() => vehicle = v);
                        next();
                      },
                    ),
                ]),
        );
      case _S.litres:
        return page(
          isUsage == false ? 'How many litres were delivered?' : 'How many litres?',
          NumberPad(value: litres, unit: 'L', onChanged: (v) => setState(() => litres = v)),
          onNext: () => (padValue(litres) ?? 0) > 0 ? next() : _need('Type the litres'),
        );
      case _S.reading:
        final km = vehicle?.unit == 'km';
        return page(
          km ? 'Kilometre reading (km)?' : 'Hour meter reading?',
          Column(children: [
            Expanded(child: NumberPad(value: reading, unit: km ? 'km' : 'hrs', onChanged: (v) => setState(() => reading = v))),
            TextButton(
              onPressed: () {
                setState(() => reading = '');
                next();
              },
              child: const Text('NO METER / CAN\'T READ IT', style: TextStyle(fontSize: 18)),
            ),
          ]),
          hint: 'Look at the meter on the ${km ? 'dashboard' : 'machine'}',
          onNext: () => reading.isEmpty ? _need('Type the reading, or tap NO METER') : next(),
        );
      case _S.activity:
        return page(
          'What work is it for?',
          ListView(children: [
            for (final a in ref.activities)
              BigChoice(label: a.name, selected: activityChosen && activity?.id == a.id, onTap: () {
                setState(() {
                  activity = a;
                  activityChosen = true;
                });
                next();
              }),
            BigChoice(icon: Icons.help_outline, label: "DON'T KNOW", color: NaniniColors.muted, selected: activityChosen && activity == null, onTap: () {
              setState(() {
                activity = null;
                activityChosen = true;
              });
              next();
            }),
          ]),
        );
      case _S.person:
        return page(
          'Who filled the diesel?',
          Column(children: [
            BigChoice(icon: Icons.skip_next, label: 'SKIP', color: NaniniColors.muted, onTap: () {
              setState(() {
                person = null;
                personChosen = true;
              });
              next();
            }),
            Expanded(
              child: PersonPicker(
                people: ref.people,
                selectedIds: {?person?.id},
                onPick: (p) {
                  setState(() {
                    person = p;
                    personChosen = true;
                  });
                  next();
                },
              ),
            ),
          ]),
        );
      case _S.supplier:
        return page(
          'Supplier name?',
          ListView(children: [
            TextField(
              controller: supplierCtrl,
              style: const TextStyle(fontSize: 24),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'e.g. Total, Engen'),
            ),
          ]),
          hint: 'You may leave it empty',
          onNext: next,
        );
      case _S.note:
        return page(
          'Delivery note number?',
          Column(children: [
            Expanded(child: NumberPad(value: deliveryNote, decimal: false, onChanged: (v) => setState(() => deliveryNote = v))),
            TextButton(
              onPressed: () {
                setState(() => deliveryNote = '');
                next();
              },
              child: const Text('NO DELIVERY NOTE', style: TextStyle(fontSize: 18)),
            ),
          ]),
          hint: 'The number on the slip from the driver',
          onNext: next,
        );
      case _S.check:
        final l = padValue(litres) ?? 0;
        return page(
          'Is this right?',
          ListView(children: [
            if (isUsage == true) ...[
              CheckLine(icon: Icons.local_gas_station, text: '${fmtNum(l)} L from ${tank?.name}'),
              CheckLine(icon: Icons.agriculture, text: 'Into ${vehicle?.name}'),
              CheckLine(icon: Icons.speed, text: reading.isEmpty ? 'No meter reading' : 'Meter: ${reading.replaceAll('.', ',')} ${vehicle?.unit == 'km' ? 'km' : 'hrs'}'),
              CheckLine(icon: Icons.work_outline, text: activity?.name ?? "Work: don't know"),
              if (person != null) CheckLine(icon: Icons.person, text: 'Filled by ${person!.name}'),
            ] else ...[
              CheckLine(icon: Icons.local_shipping, text: '${fmtNum(l)} L delivered'),
              CheckLine(icon: Icons.local_gas_station, text: 'Into ${tank?.name}'),
              if (supplierCtrl.text.trim().isNotEmpty) CheckLine(icon: Icons.store, text: supplierCtrl.text.trim()),
              if (deliveryNote.isNotEmpty) CheckLine(icon: Icons.receipt, text: 'Delivery note $deliveryNote'),
            ],
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
    final l = padValue(litres) ?? 0;
    final today = dayStr(DateTime.now());
    if (isUsage == true) {
      await store.add(
        CaptureModule.dieselUsage,
        {
          'tank_id': tank!.id,
          'tank_name': tank!.name,
          'date': today,
          'litres': l,
          'vehicle_id': vehicle?.id,
          'vehicle_name': vehicle?.name,
          'unit': vehicle?.unit ?? 'hours',
          'reading': reading,
          'activity_id': activity?.id,
          'activity_name': activity?.name,
          'employee_id': person?.id,
          'employee_name': person?.name,
        },
        '${fmtNum(l)} L into ${vehicle?.name}',
      );
    } else {
      await store.add(
        CaptureModule.dieselPurchase,
        {
          'tank_id': tank!.id,
          'tank_name': tank!.name,
          'date': today,
          'litres': l,
          'supplier': supplierCtrl.text.trim(),
          'delivery_note': deliveryNote,
        },
        '${fmtNum(l)} L delivered into ${tank!.name}',
      );
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => SavedScreen(
        task: 'diesel',
        another: (_) => const DieselFlow(),
      ),
    ));
  }
}
