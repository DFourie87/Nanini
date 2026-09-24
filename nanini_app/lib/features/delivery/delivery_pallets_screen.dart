import 'package:flutter/material.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'delivery_market_agents_screen.dart';
import 'delivery_models.dart';
import 'delivery_repository.dart';

class DeliveryPalletsScreen extends StatefulWidget {
  const DeliveryPalletsScreen({super.key, required this.repo});
  final DeliveryRepository repo;
  @override
  State<DeliveryPalletsScreen> createState() => _DeliveryPalletsScreenState();
}

class _DeliveryPalletsScreenState extends State<DeliveryPalletsScreen> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Pallets')),
              ButtonSegment(value: 1, label: Text('Transport')),
            ],
            selected: {index},
            onSelectionChanged: (s) => setState(() => index = s.first),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: NaniniColors.rust,
              selectedForegroundColor: Colors.white,
            ),
          ),
        ),
        Expanded(child: index == 0 ? _PalletsTab(repo: widget.repo) : _TransportTab(repo: widget.repo)),
      ],
    );
  }
}

class _PalletsTab extends StatefulWidget {
  const _PalletsTab({required this.repo});
  final DeliveryRepository repo;
  @override
  State<_PalletsTab> createState() => _PalletsTabState();
}

class _PalletsTabState extends State<_PalletsTab> {
  List<MarketAgent> agents = [];
  String? agentId;
  final qtyCtrl = TextEditingController();
  DateTime date = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  Future<void> _loadAgents() async {
    final a = await widget.repo.fetchMarketAgents();
    if (!mounted) return;
    setState(() {
      agents = a;
      agentId ??= a.isNotEmpty ? a.first.id : null;
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: agentId,
                        decoration: const InputDecoration(labelText: 'Market agent'),
                        items: sortedAgents.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                        onChanged: (v) => setState(() => agentId = v),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: 'Manage market agents (admin)',
                      onPressed: () async {
                        if (!await requireAdmin(context)) return;
                        if (!context.mounted) return;
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryMarketAgentsScreen(repo: widget.repo)));
                        await _loadAgents();
                      },
                    ),
                  ],
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

class _TransportTab extends StatefulWidget {
  const _TransportTab({required this.repo});
  final DeliveryRepository repo;
  @override
  State<_TransportTab> createState() => _TransportTabState();
}

class _TransportTabState extends State<_TransportTab> {
  DateTime? from;
  DateTime? to;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DeliveryNote>>(
      stream: widget.repo.watchNotes(),
      builder: (context, noteSnap) {
        return StreamBuilder<List<TransportRate>>(
          stream: widget.repo.watchTransportRates(),
          builder: (context, rateSnap) {
            return StreamBuilder<List<TransportPayment>>(
              stream: widget.repo.watchTransportPayments(),
              builder: (context, paySnap) {
                final rates = rateSnap.data ?? [];
                final payments = paySnap.data ?? [];

                // Approved, externally-transported loads only -- self
                // transport has no company to bill and is excluded.
                final transportNotes = (noteSnap.data ?? [])
                    .where((n) => n.isApproved && !n.isSelfTransport && (n.transportCompany ?? '').isNotEmpty)
                    .toList();

                final rateFor = {for (final r in rates) '${r.transportCompany}||${r.market}': r.pricePerLoad};
                double chargeFor(DeliveryNote n) => rateFor['${n.transportCompany}||${n.agentMarket ?? ''}'] ?? 0;

                bool inPeriod(String dateStr) {
                  final d = parseDateStr(dateStr);
                  if (d == null) return false;
                  if (from != null && d.isBefore(from!)) return false;
                  if (to != null && d.isAfter(to!)) return false;
                  return true;
                }

                final periodNotes = transportNotes.where((n) => inPeriod(n.noteDate)).toList();
                final byCompanyPeriod = <String, List<DeliveryNote>>{};
                for (final n in periodNotes) {
                  (byCompanyPeriod[n.transportCompany!] ??= []).add(n);
                }
                final byCompanyAll = <String, List<DeliveryNote>>{};
                for (final n in transportNotes) {
                  (byCompanyAll[n.transportCompany!] ??= []).add(n);
                }

                final knownCompanies = byCompanyAll.keys.toList()..sort();
                final knownMarkets = transportNotes.map((n) => n.agentMarket).whereType<String>().where((m) => m.isNotEmpty).toSet().toList()
                  ..sort();

                final allCompanies = {...byCompanyAll.keys, ...payments.map((p) => p.transportCompany), ...rates.map((r) => r.transportCompany)}
                    .toList()
                  ..sort();

                double owedFor(String company) => (byCompanyAll[company] ?? []).fold<double>(0, (s, n) => s + chargeFor(n));
                double paidFor(String company) => payments.where((p) => p.transportCompany == company).fold<double>(0, (s, p) => s + p.amount);

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Loads by transport company', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(context: context, initialDate: from ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                              if (picked != null) setState(() => from = picked);
                            },
                            child: Text(from == null ? 'From' : fmtDateDisplay(toDateStr(from!))),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await showDatePicker(context: context, initialDate: to ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                              if (picked != null) setState(() => to = picked);
                            },
                            child: Text(to == null ? 'To' : fmtDateDisplay(toDateStr(to!))),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          for (final company in byCompanyPeriod.keys.toList()..sort())
                            Builder(builder: (context) {
                              final companyNotes = byCompanyPeriod[company]!;
                              final unpriced = companyNotes.where((n) => !rateFor.containsKey('$company||${n.agentMarket ?? ''}')).length;
                              final charge = companyNotes.fold<double>(0, (s, n) => s + chargeFor(n));
                              return ListTile(
                                title: Text(company),
                                subtitle: Text(
                                  '${companyNotes.length} load${companyNotes.length == 1 ? '' : 's'}'
                                  '${unpriced > 0 ? ' · $unpriced with no rate set' : ''}',
                                  style: unpriced > 0 ? const TextStyle(color: NaniniColors.amber) : null,
                                ),
                                trailing: Text(fmtR(charge), style: const TextStyle(fontWeight: FontWeight.w700)),
                              );
                            }),
                          if (byCompanyPeriod.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No external-transport loads in this period.')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Price per load', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (knownCompanies.isEmpty || knownMarkets.isEmpty)
                      const Text(
                        'Approve a delivery note with a transport company and market agent first -- rates are set per company/market pair.',
                        style: TextStyle(color: NaniniColors.muted, fontSize: 12),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () async {
                          if (!await requireAdmin(context)) return;
                          if (!context.mounted) return;
                          await _showSetRateDialog(context, widget.repo, knownCompanies, knownMarkets);
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Set a rate'),
                      ),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: [
                          for (final r in rates)
                            ListTile(
                              dense: true,
                              title: Text('${r.transportCompany} → ${r.market}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(fmtR(r.pricePerLoad)),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                    onPressed: () async {
                                      if (!await requireAdmin(context)) return;
                                      if (!context.mounted) return;
                                      final ok = await confirmDialog(context, message: 'Remove this rate?');
                                      if (ok) await widget.repo.deleteTransportRate(r.id);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          if (rates.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No rates set yet.')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Outstanding by transport company', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text(
                      'All-time totals, independent of the date range above.',
                      style: TextStyle(color: NaniniColors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    if (knownCompanies.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () async {
                          if (!await requireAdmin(context)) return;
                          if (!context.mounted) return;
                          await _showRecordPaymentDialog(context, widget.repo, knownCompanies);
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Record payment'),
                      ),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: [
                          for (final company in allCompanies)
                            ListTile(
                              title: Text(company),
                              subtitle: Text('Owed ${fmtR(owedFor(company))} · Paid ${fmtR(paidFor(company))}'),
                              trailing: Text(
                                fmtR(owedFor(company) - paidFor(company)),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          if (allCompanies.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No transport activity yet.')),
                        ],
                      ),
                    ),
                    if (payments.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('Payment history', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        child: Column(
                          children: [
                            for (final p in [...payments]..sort((a, b) => b.date.compareTo(a.date)))
                              ListTile(
                                dense: true,
                                title: Text(p.transportCompany),
                                subtitle: Text('${fmtDateDisplay(p.date)}${(p.note ?? '').isNotEmpty ? ' · ${p.note}' : ''}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(fmtR(p.amount)),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18),
                                      onPressed: () async {
                                        if (!await requireAdmin(context)) return;
                                        if (!context.mounted) return;
                                        final ok = await confirmDialog(context, message: 'Remove this payment record?', danger: true);
                                        if (ok) await widget.repo.deleteTransportPayment(p.id);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

Future<void> _showSetRateDialog(BuildContext context, DeliveryRepository repo, List<String> companies, List<String> markets) async {
  String company = companies.first;
  String market = markets.first;
  final priceCtrl = TextEditingController();
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Set price per load'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: company,
              decoration: const InputDecoration(labelText: 'Transport company'),
              items: companies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setLocal(() => company = v!),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: market,
              decoration: const InputDecoration(labelText: 'Market / destination'),
              items: markets.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) => setLocal(() => market = v!),
            ),
            const SizedBox(height: 10),
            TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price per load (R)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final price = double.tryParse(priceCtrl.text);
              if (price == null || price < 0) return;
              await repo.setTransportRate(transportCompany: company, market: market, pricePerLoad: price);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showRecordPaymentDialog(BuildContext context, DeliveryRepository repo, List<String> companies) async {
  String company = companies.first;
  final amountCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  DateTime date = DateTime.now();
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Record payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: company,
              decoration: const InputDecoration(labelText: 'Transport company'),
              items: companies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setLocal(() => company = v!),
            ),
            const SizedBox(height: 10),
            TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount paid (R)')),
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (picked != null) setLocal(() => date = picked);
              },
              child: InputDecorator(decoration: const InputDecoration(labelText: 'Date'), child: Text(fmtDateDisplay(toDateStr(date)))),
            ),
            const SizedBox(height: 10),
            TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text);
              if (amount == null || amount <= 0) return;
              await repo.addTransportPayment(transportCompany: company, amount: amount, date: toDateStr(date), note: noteCtrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
