import 'package:flutter/material.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'delivery_models.dart';
import 'delivery_repository.dart';
import 'delivery_note_preview.dart';

class DeliveryLogScreen extends StatefulWidget {
  const DeliveryLogScreen({super.key, required this.repo});
  final DeliveryRepository repo;
  @override
  State<DeliveryLogScreen> createState() => _DeliveryLogScreenState();
}

class _DeliveryLogScreenState extends State<DeliveryLogScreen> {
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
        SegmentedButton<ProduceType>(
          segments: const [
            ButtonSegment(value: ProduceType.potato, label: Text('Potato')),
            ButtonSegment(value: ProduceType.pepper, label: Text('Pepper')),
            ButtonSegment(value: ProduceType.butternut, label: Text('Butternut')),
          ],
          selected: {truck.produceType},
          onSelectionChanged: (s) => setProduce(s.first),
        ),
        const SizedBox(height: 16),
        if (truck.produceType == ProduceType.potato) _potatoSection(),
        if (truck.produceType == ProduceType.pepper) _pepperSection(),
        if (truck.produceType == ProduceType.butternut) _butternutSection(),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => _showFinishDialog(context),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Finish Truck'),
        ),
      ],
    );
  }

  Widget _potatoSection() {
    final progress = truck.target > 0 ? (truck.totalPallets / truck.target).clamp(0, 1.5) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: truck.field,
          decoration: const InputDecoration(labelText: 'Field'),
          items: kFieldNames.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
          onChanged: (v) => setState(() => truck.field = v),
        ),
        const SizedBox(height: 12),
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
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress > 1 ? 1 : progress.toDouble(),
            minHeight: 12,
            backgroundColor: NaniniColors.disabledBg,
            color: truck.totalPallets > truck.target ? NaniniColors.rustDark : NaniniColors.green,
          ),
        ),
        const SizedBox(height: 4),
        Text('${truck.totalPallets} / ${truck.target} pallets'),
        const SizedBox(height: 16),
        for (final s in kPalletSizes) _counterRow(s.label, truck.pallets[s.key] ?? 0, (v) => setState(() => truck.pallets[s.key] = v)),
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

  Widget _pepperSection() {
    return Column(
      children: [
        for (final key in truck.peppers.keys) _counterRow(key, truck.peppers[key]!, (v) => setState(() => truck.peppers[key] = v)),
        const SizedBox(height: 8),
        Text('Total boxes: ${truck.totalPepperBoxes}'),
      ],
    );
  }

  Widget _butternutSection() {
    return Column(
      children: [
        for (final key in truck.butternuts.keys) _counterRow(key, truck.butternuts[key]!, (v) => setState(() => truck.butternuts[key] = v)),
        const SizedBox(height: 8),
        Text('Total bags: ${truck.totalButternutBags}'),
      ],
    );
  }

  Widget _counterRow(String label, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(onPressed: value > 0 ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
          SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center)),
          IconButton(onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add_circle_outline)),
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
                            onChanged: (v) => lines[s.key] = int.tryParse(v) ?? 0,
                          ),
                        ),
                      ],
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

  Future<void> _showFinishDialog(BuildContext context) async {
    final regCtrl = TextEditingController();
    final transportCtrl = TextEditingController();
    List<MarketAgent> agents = [];
    String? agentId;
    try {
      agents = await widget.repo.fetchMarketAgents();
    } catch (_) {}
    final sortedAgents = [...agents]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Finish truck'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: transportCtrl, decoration: const InputDecoration(labelText: 'Transport company')),
              const SizedBox(height: 10),
              TextField(controller: regCtrl, decoration: const InputDecoration(labelText: 'Truck registration *')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: agentId,
                decoration: const InputDecoration(labelText: 'Market agent'),
                items: sortedAgents.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                onChanged: (v) => setLocal(() => agentId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (regCtrl.text.trim().isEmpty) {
                  showToast(ctx, 'Truck registration is required', isError: true);
                  return;
                }
                final agent = agents.where((a) => a.id == agentId).firstOrNull;
                final note = await widget.repo.saveNote(truck, reg: regCtrl.text.trim(), transportCompany: transportCtrl.text.trim(), agent: agent);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                setState(() => truck = ActiveTruck(produceType: ProduceType.potato));
                if (context.mounted) {
                  showDeliveryNotePreview(context, note);
                }
              },
              child: const Text('Save & generate note'),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
