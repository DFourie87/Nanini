import 'package:flutter/material.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'delivery_models.dart';
import 'delivery_repository.dart';

class DeliveryLogScreen extends StatefulWidget {
  const DeliveryLogScreen({super.key, required this.repo});
  final DeliveryRepository repo;
  @override
  State<DeliveryLogScreen> createState() => _DeliveryLogScreenState();
}

class _DeliveryLogScreenState extends State<DeliveryLogScreen> {
  static const _pepperYellow = Color(0xFFF9A825);

  ActiveTruck truck = ActiveTruck(produceType: ProduceType.potato);

  void setProduce(ProduceType t) {
    setState(() => truck = ActiveTruck(produceType: t));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text('Active truck', style: Theme.of(context).textTheme.titleMedium)),
            if (truck.totalPallets + truck.totalPepperBoxes + truck.totalButternutBags > 0)
              IconButton(
                tooltip: 'Clear all',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => truck = ActiveTruck(produceType: truck.produceType)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SegmentedButton<ProduceType>(
          segments: const [
            ButtonSegment(value: ProduceType.potato, label: Text('Potatoes', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ButtonSegment(value: ProduceType.pepper, label: Text('Peppers', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ButtonSegment(value: ProduceType.butternut, label: Text('Butternuts', maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          selected: {truck.produceType},
          onSelectionChanged: (s) => setProduce(s.first),
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: NaniniColors.rust,
            selectedForegroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        if (truck.produceType == ProduceType.potato) _potatoSection(),
        if (truck.produceType == ProduceType.pepper) _pepperSection(),
        if (truck.produceType == ProduceType.butternut) _butternutSection(),
        const SizedBox(height: 24),
        if (!_canFinish) ...[
          Text(
            'Loaded pallets (${truck.totalPallets}) must match the target (${truck.target}) before finishing the truck.',
            style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],
        FilledButton.icon(
          onPressed: _canFinish ? () => _finishTruck(context) : null,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Finish Truck'),
        ),
      ],
    );
  }

  /// Peppers/butternuts have no pallet target; potatoes can only finish
  /// once the loaded pallets exactly match the target.
  bool get _canFinish => truck.produceType != ProduceType.potato || truck.totalPallets == truck.target;

  Widget _potatoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Target pallets: '),
            SizedBox(
              width: 80,
              child: TextFormField(
                initialValue: truck.target.toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(isDense: true),
                onChanged: (v) => setState(() => truck.target = int.tryParse(v) ?? kDefaultTarget),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _palletProgressBar(),
        const SizedBox(height: 4),
        Text('${truck.totalPallets} / ${truck.target} pallets'),
        const SizedBox(height: 16),
        for (final s in kPalletSizes)
          _counterRow(
            s.label,
            truck.pallets[s.key] ?? 0,
            (v) => setState(() => truck.pallets[s.key] = v),
            labelColor: Color(s.color),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _showMixedPalletDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('Add mixed pallet'),
        ),
        for (var i = 0; i < truck.mixedPallets.length; i++)
          ListTile(
            dense: true,
            title: Text('Mixed pallet ${i + 1}'),
            subtitle: Text(truck.mixedPallets[i].entries.where((e) => e.value > 0).map((e) => '${e.key}: ${e.value}').join(', ')),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => truck.mixedPallets.removeAt(i))),
          ),
      ],
    );
  }

  /// A bar built from one colored segment per pallet size actually loaded
  /// (width proportional to its count, same color as its label), plus a
  /// grey segment for whatever's still needed to reach the target.
  Widget _palletProgressBar() {
    final target = truck.target > 0 ? truck.target : 1;
    final segments = <(Color, int)>[
      for (final s in kPalletSizes)
        if ((truck.pallets[s.key] ?? 0) > 0) (Color(s.color), truck.pallets[s.key]!),
      if (truck.mixedPallets.isNotEmpty) (NaniniColors.muted, truck.mixedPallets.length),
    ];
    final remaining = target - truck.totalPallets;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 12,
        child: Row(
          children: [
            for (final seg in segments) Expanded(flex: seg.$2, child: Container(color: seg.$1)),
            if (remaining > 0) Expanded(flex: remaining, child: Container(color: NaniniColors.disabledBg)),
          ],
        ),
      ),
    );
  }

  Widget _pepperSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pepperGroup('5kg'),
        const SizedBox(height: 12),
        _pepperGroup('4kg'),
        const SizedBox(height: 8),
        Text('Total boxes: ${truck.totalPepperBoxes}'),
      ],
    );
  }

  Widget _pepperGroup(String weight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(weight, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        _typedCountField('Red', truck.peppers['${weight}Red']!, (v) => setState(() => truck.peppers['${weight}Red'] = v), labelColor: NaniniColors.red),
        _typedCountField(
            'Yellow', truck.peppers['${weight}Yellow']!, (v) => setState(() => truck.peppers['${weight}Yellow'] = v), labelColor: _pepperYellow),
        _typedCountField(
            'Green', truck.peppers['${weight}Green']!, (v) => setState(() => truck.peppers['${weight}Green'] = v), labelColor: NaniniColors.green),
      ],
    );
  }

  Widget _butternutSection() {
    return Column(
      children: [
        for (final key in truck.butternuts.keys)
          _typedCountField(key, truck.butternuts[key]!, (v) => setState(() => truck.butternuts[key] = v)),
        const SizedBox(height: 8),
        Text('Total bags: ${truck.totalButternutBags}'),
      ],
    );
  }

  Widget _counterRow(String label, int value, ValueChanged<int> onChanged, {Color? labelColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelColor != null ? TextStyle(color: labelColor) : null)),
          IconButton(onPressed: value > 0 ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
          SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center)),
          IconButton(onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add_circle_outline)),
        ],
      ),
    );
  }

  Widget _typedCountField(String label, int value, ValueChanged<int> onChanged, {Color? labelColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelColor != null ? TextStyle(color: labelColor) : null)),
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: value == 0 ? '' : value.toString(),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(isDense: true, hintText: '0'),
              onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMixedPalletDialog(BuildContext context) async {
    final lines = <String, int>{for (final s in kPalletSizes) s.key: 0};
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Mixed pallet'),
          content: SizedBox(
            width: 350,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in kPalletSizes)
                    Row(
                      children: [
                        Expanded(child: Text(s.label, style: const TextStyle(fontSize: 13))),
                        SizedBox(
                          width: 70,
                          child: TextFormField(
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'bags', isDense: true),
                            onChanged: (v) => setLocal(() => lines[s.key] = int.tryParse(v) ?? 0),
                          ),
                        ),
                      ],
                    ),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total: ${lines.values.fold(0, (a, b) => a + b)} bags',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                setState(() => truck.mixedPallets.add(Map.of(lines)..removeWhere((k, v) => v <= 0)));
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finishTruck(BuildContext context) async {
    final ok = await confirmDialog(context, message: 'Finish this truck? It will be sent to Records as pending, ready for approval.');
    if (!ok) return;
    if (!context.mounted) return;
    try {
      await widget.repo.saveNote(truck);
    } catch (e) {
      if (context.mounted) showToast(context, 'Could not log truck: $e', isError: true);
      return;
    }
    if (!context.mounted) return;
    setState(() => truck = ActiveTruck(produceType: ProduceType.potato));
    showToast(context, 'Truck logged -- add details and approve it in Records');
  }
}
