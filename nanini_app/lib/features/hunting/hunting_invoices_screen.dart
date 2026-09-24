import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../employees/employees_models.dart';
import 'hunting_invoice_detail_screen.dart';
import 'hunting_models.dart';
import 'hunting_repository.dart';

class HuntingInvoicesScreen extends StatefulWidget {
  const HuntingInvoicesScreen({super.key, required this.repo});
  final HuntingRepository repo;
  @override
  State<HuntingInvoicesScreen> createState() => _HuntingInvoicesScreenState();
}

class _HuntingInvoicesScreenState extends State<HuntingInvoicesScreen> {
  List<Farm> farms = [];
  String? filterFarmId;

  @override
  void initState() {
    super.initState();
    fetchHuntingFarms().then((f) {
      if (!mounted) return;
      setState(() => farms = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<List<HuntingInvoice>>(
          stream: widget.repo.watchInvoices(),
          builder: (context, snap) {
            var invoices = (snap.data ?? []).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            if (filterFarmId != null) {
              invoices = invoices.where((i) => i.farmId == filterFarmId).toList();
            }
            return Column(
              children: [
                if (farms.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          child: ChoiceChip(
                            label: const Text('All farms'),
                            selected: filterFarmId == null,
                            onSelected: (_) => setState(() => filterFarmId = null),
                          ),
                        ),
                        for (final f in farms)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            child: ChoiceChip(
                              label: Text(f.name),
                              selected: filterFarmId == f.id,
                              onSelected: (_) => setState(() => filterFarmId = f.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: invoices.isEmpty
                      ? const Center(child: Text('No hunters yet.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                          itemCount: invoices.length,
                          itemBuilder: (context, i) {
                            final inv = invoices[i];
                            final farm = farms.where((f) => f.id == inv.farmId).firstOrNull;
                            return Card(
                              child: ListTile(
                                title: Text(inv.hunterName),
                                subtitle: Text(
                                  '${farm?.name ?? 'Unknown farm'} · ${guestTypeLabel(inv.guestType)} · ${fmtDateDisplay(inv.visitDate)}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Chip(
                                      label: Text(inv.paymentMethod == HuntingPaymentMethod.eft ? 'EFT' : 'Cash'),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18),
                                      onPressed: () async {
                                        final ok = await confirmDialog(context, message: 'Delete ${inv.hunterName}\'s invoice and all its line items?', danger: true);
                                        if (ok) await widget.repo.deleteInvoice(inv.id);
                                      },
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  if (farm == null) return;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => HuntingInvoiceDetailScreen(repo: widget.repo, invoice: inv, farm: farm)),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 32,
          child: FloatingActionButton.extended(
            onPressed: () => _showAddHunterDialog(context),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add hunter'),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddHunterDialog(BuildContext context) async {
    if (farms.isEmpty) return;
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    var farmId = filterFarmId ?? farms.first.id;
    var guestType = kGuestTypes.first;
    var paymentMethod = HuntingPaymentMethod.eft;
    var visitDate = todayStr();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add hunter'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Hunter name')),
                const SizedBox(height: 10),
                TextField(controller: idCtrl, decoration: const InputDecoration(labelText: 'ID/Passport (optional)')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: farmId,
                  decoration: const InputDecoration(labelText: 'Farm'),
                  items: farms.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
                  onChanged: (v) => setLocal(() => farmId = v!),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: guestType,
                  decoration: const InputDecoration(labelText: 'Guest type'),
                  items: kGuestTypes.map((g) => DropdownMenuItem(value: g, child: Text(guestTypeLabel(g)))).toList(),
                  onChanged: (v) => setLocal(() => guestType = v!),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<HuntingPaymentMethod>(
                  initialValue: paymentMethod,
                  decoration: const InputDecoration(labelText: 'Payment method'),
                  items: const [
                    DropdownMenuItem(value: HuntingPaymentMethod.eft, child: Text('EFT')),
                    DropdownMenuItem(value: HuntingPaymentMethod.cash, child: Text('Cash')),
                  ],
                  onChanged: (v) => setLocal(() => paymentMethod = v!),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Visit date: ${fmtDateDisplay(visitDate)}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: parseDateStr(visitDate) ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setLocal(() => visitDate = toDateStr(picked));
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final invoice = await widget.repo.addInvoice(
                  hunterName: name,
                  idOrPassport: idCtrl.text.trim().isEmpty ? null : idCtrl.text.trim(),
                  farmId: farmId,
                  guestType: guestType,
                  paymentMethod: paymentMethod,
                  visitDate: visitDate,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                final farm = farms.where((f) => f.id == farmId).firstOrNull;
                if (farm != null && context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => HuntingInvoiceDetailScreen(repo: widget.repo, invoice: invoice, farm: farm)),
                  );
                }
              },
              child: const Text('Add'),
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
