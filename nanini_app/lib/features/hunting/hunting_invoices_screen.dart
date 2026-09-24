import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/toast.dart';
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
      final limpopodraai = f.where((farm) => farm.name.toLowerCase().contains('limpopodraai'));
      setState(() {
        farms = f;
        filterFarmId = limpopodraai.isNotEmpty ? limpopodraai.first.id : (f.isNotEmpty ? f.first.id : null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<List<HuntingInvoice>>(
          stream: widget.repo.watchInvoices(),
          builder: (context, snap) {
            final invoices = (snap.data ?? []).where((i) => i.farmId == filterFarmId).toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return Column(
              children: [
                if (farms.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
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
                                title: Text(
                                  (inv.nickname ?? '').isEmpty ? inv.hunterName : '${inv.hunterName} (${inv.nickname})',
                                ),
                                subtitle: Text(
                                  '${farm?.name ?? 'Unknown farm'} · ${guestTypeLabel(inv.guestType)} · ${visitRangeLabel(inv, fmtDateDisplay)}',
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
    final firstNameCtrl = TextEditingController();
    final nicknameCtrl = TextEditingController();
    final surnameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    var farmId = filterFarmId ?? farms.first.id;
    var guestType = kGuestTypes.first;
    var paymentMethod = HuntingPaymentMethod.eft;
    var visitDate = todayStr();
    var visitToDate = todayStr();
    var saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add hunter'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: firstNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full first name(s) *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nicknameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nickname *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: surnameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Surname *'),
                ),
                const SizedBox(height: 10),
                TextField(controller: idCtrl, decoration: const InputDecoration(labelText: 'ID/Passport number *')),
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
                  title: Text('Visit from: ${fmtDateDisplay(visitDate)}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: parseDateStr(visitDate) ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked == null) return;
                    setLocal(() {
                      visitDate = toDateStr(picked);
                      if (visitToDate.compareTo(visitDate) < 0) visitToDate = visitDate;
                    });
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Visit to: ${fmtDateDisplay(visitToDate)}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final from = parseDateStr(visitDate) ?? DateTime.now();
                    final current = parseDateStr(visitToDate) ?? from;
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: current.isBefore(from) ? from : current,
                      firstDate: from,
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setLocal(() => visitToDate = toDateStr(picked));
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final firstName = firstNameCtrl.text.trim();
                      final nickname = nicknameCtrl.text.trim();
                      final surname = surnameCtrl.text.trim();
                      final idNumber = idCtrl.text.trim();
                      final missing = [
                        if (firstName.isEmpty) 'first name',
                        if (nickname.isEmpty) 'nickname',
                        if (surname.isEmpty) 'surname',
                        if (idNumber.isEmpty) 'ID/passport number',
                      ];
                      if (missing.isNotEmpty) {
                        showToast(ctx, 'Please fill in: ${missing.join(', ')}', isError: true);
                        return;
                      }
                      setLocal(() => saving = true);
                      try {
                        final invoice = await widget.repo.addInvoice(
                          hunterName: '$firstName $surname',
                          firstName: firstName,
                          nickname: nickname,
                          surname: surname,
                          idOrPassport: idNumber,
                          farmId: farmId,
                          guestType: guestType,
                          paymentMethod: paymentMethod,
                          visitDate: visitDate,
                          visitToDate: visitToDate,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        final farm = farms.where((f) => f.id == farmId).firstOrNull;
                        if (farm != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => HuntingInvoiceDetailScreen(repo: widget.repo, invoice: invoice, farm: farm)),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setLocal(() => saving = false);
                          showToast(ctx, 'Could not add hunter: $e', isError: true);
                        }
                      }
                    },
              child: Text(saving ? 'Adding…' : 'Add'),
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
