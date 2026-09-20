import 'package:flutter/material.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'delivery_market_agents_screen.dart';
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
    Future<void> loadAgents() async {
      try {
        agents = await widget.repo.fetchMarketAgents();
      } catch (_) {}
    }

    await loadAgents();

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final sortedAgents = [...agents]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return AlertDialog(
          title: const Text('Finish truck'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: transportCtrl, decoration: const InputDecoration(labelText: 'Transport company')),
              const SizedBox(height: 10),
              TextField(controller: regCtrl, decoration: const InputDecoration(labelText: 'Truck registration *')),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: agentId,
                      decoration: const InputDecoration(labelText: 'Market agent'),
                      items: sortedAgents.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                      onChanged: (v) => setLocal(() => agentId = v),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Manage market agents (admin)',
                    onPressed: () async {
                      if (!await requireAdmin(ctx)) return;
                      if (!ctx.mounted) return;
                      await Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => DeliveryMarketAgentsScreen(repo: widget.repo)));
                      await loadAgents();
                      setLocal(() {});
                    },
                  ),
                ],
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
          );
        },
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
