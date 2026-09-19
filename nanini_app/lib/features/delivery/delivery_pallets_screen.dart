import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/toast.dart';
import 'delivery_models.dart';
import 'delivery_repository.dart';

class DeliveryPalletsScreen extends StatefulWidget {
  const DeliveryPalletsScreen({super.key, required this.repo});
  final DeliveryRepository repo;
  @override
  State<DeliveryPalletsScreen> createState() => _DeliveryPalletsScreenState();
}

class _DeliveryPalletsScreenState extends State<DeliveryPalletsScreen> {
  List<MarketAgent> agents = [];
  String? agentId;
  final qtyCtrl = TextEditingController();
  DateTime date = DateTime.now();

  @override
  void initState() {
    super.initState();
    widget.repo.fetchMarketAgents().then((a) {
      if (!mounted) return;
      setState(() {
        agents = a;
        agentId = a.isNotEmpty ? a.first.id : null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PalletPurchase>>(
      stream: widget.repo.watchPurchases(),
      builder: (context, purSnap) {
        return StreamBuilder<List<DeliveryNote>>(
          stream: widget.repo.watchNotes(),
          builder: (context, noteSnap) {
            final purchases = purSnap.data ?? [];
            final notes = noteSnap.data ?? [];

            final bought = <String, int>{};
            for (final p in purchases) {
              bought[p.agentName] = (bought[p.agentName] ?? 0) + p.qty;
            }
            final delivered = <String, int>{};
            for (final n in notes.where((n) => n.produceType == 'potato' && n.agentName != null)) {
              delivered[n.agentName!] = (delivered[n.agentName!] ?? 0) + n.total;
            }
            final agentNames = {...bought.keys, ...delivered.keys}.toList()..sort();
            final sortedAgents = [...agents]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Log pallet purchase', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: agentId,
                  decoration: const InputDecoration(labelText: 'Market agent'),
                  items: sortedAgents.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                  onChanged: (v) => setState(() => agentId = v),
                ),
                const SizedBox(height: 8),
                TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pallets bought')),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (picked != null) setState(() => date = picked);
                  },
                  child: InputDecorator(decoration: const InputDecoration(labelText: 'Date'), child: Text(fmtDateDisplay(toDateStr(date)))),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final qty = int.tryParse(qtyCtrl.text) ?? 0;
                    final agent = agents.where((a) => a.id == agentId).firstOrNull;
                    if (agent == null || qty <= 0) {
                      showToast(context, 'Select an agent and enter pallets', isError: true);
                      return;
                    }
                    await widget.repo.logPalletPurchase(agent: agent, qty: qty, date: toDateStr(date));
                    if (!context.mounted) return;
                    showToast(context, 'Logged $qty pallets from ${agent.name}');
                    qtyCtrl.clear();
                  },
                  child: const Text('Log purchase'),
                ),
                const SizedBox(height: 24),
                Text('Pallet balance by agent', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (final name in agentNames)
                        ListTile(
                          title: Text(name),
                          subtitle: Text('Bought ${bought[name] ?? 0} · Delivered ${delivered[name] ?? 0}'),
                          trailing: Text('${(bought[name] ?? 0) - (delivered[name] ?? 0)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      if (agentNames.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No pallet activity yet.')),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
