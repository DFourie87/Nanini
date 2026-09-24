import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import 'hunting_invoice_detail_screen.dart';
import 'hunting_models.dart';
import 'hunting_repository.dart';

class HuntingBookingsScreen extends StatefulWidget {
  const HuntingBookingsScreen({super.key, required this.repo});
  final HuntingRepository repo;
  @override
  State<HuntingBookingsScreen> createState() => _HuntingBookingsScreenState();
}

class _HuntingBookingsScreenState extends State<HuntingBookingsScreen> {
  List<Farm> farms = [];

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
        StreamBuilder<List<HuntingBooking>>(
          stream: widget.repo.watchBookings(),
          builder: (context, snap) {
            final bookings = (snap.data ?? []).where((b) => !b.converted).toList()
              ..sort((a, b) => (parseDateStr(a.fromDate) ?? a.createdAt).compareTo(parseDateStr(b.fromDate) ?? b.createdAt));
            return bookings.isEmpty
                ? const Center(child: Text('No upcoming bookings.'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    itemCount: bookings.length,
                    itemBuilder: (context, i) {
                      final b = bookings[i];
                      final farm = farms.where((f) => f.id == b.farmId).firstOrNull;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(b.hunterName, style: Theme.of(context).textTheme.titleMedium),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                    onPressed: () async {
                                      final ok = await confirmDialog(context, message: 'Delete this booking?', danger: true);
                                      if (ok) await widget.repo.deleteBooking(b.id);
                                    },
                                  ),
                                ],
                              ),
                              Text(
                                '${farm?.name ?? 'Unknown farm'} · ${guestTypeLabel(b.guestType)}',
                                style: const TextStyle(color: NaniniColors.muted),
                              ),
                              Text(
                                '${fmtDateDisplay(b.fromDate)} → ${fmtDateDisplay(b.toDate)}',
                                style: const TextStyle(color: NaniniColors.muted),
                              ),
                              if ((b.phone ?? '').isNotEmpty || (b.email ?? '').isNotEmpty)
                                Text(
                                  [if ((b.phone ?? '').isNotEmpty) b.phone, if ((b.email ?? '').isNotEmpty) b.email].join(' · '),
                                  style: const TextStyle(color: NaniniColors.muted),
                                ),
                              if ((b.notes ?? '').isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(b.notes!),
                              ],
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton.icon(
                                  onPressed: farm == null ? null : () => _convertToInvoice(context, b, farm),
                                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                                  label: const Text('Convert to invoice'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
          },
        ),
        Positioned(
          right: 16,
          bottom: 32,
          child: FloatingActionButton.extended(
            onPressed: () => _showAddBookingDialog(context),
            icon: const Icon(Icons.event_available),
            label: const Text('Add booking'),
          ),
        ),
      ],
    );
  }

  Future<void> _convertToInvoice(BuildContext context, HuntingBooking booking, Farm farm) async {
    var paymentMethod = HuntingPaymentMethod.eft;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Convert to invoice'),
          content: DropdownButtonFormField<HuntingPaymentMethod>(
            initialValue: paymentMethod,
            decoration: const InputDecoration(labelText: 'Payment method'),
            items: const [
              DropdownMenuItem(value: HuntingPaymentMethod.eft, child: Text('EFT')),
              DropdownMenuItem(value: HuntingPaymentMethod.cash, child: Text('Cash')),
            ],
            onChanged: (v) => setLocal(() => paymentMethod = v!),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create invoice')),
          ],
        ),
      ),
    );
    if (proceed != true) return;

    final invoice = await widget.repo.addInvoice(
      hunterName: booking.hunterName,
      idOrPassport: booking.idOrPassport,
      farmId: booking.farmId,
      guestType: booking.guestType,
      paymentMethod: paymentMethod,
      visitDate: booking.fromDate,
    );
    await widget.repo.markBookingConverted(booking.id);
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => HuntingInvoiceDetailScreen(repo: widget.repo, invoice: invoice, farm: farm)));
  }

  Future<void> _showAddBookingDialog(BuildContext context) async {
    if (farms.isEmpty) return;
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    var farmId = farms.first.id;
    var guestType = kGuestTypes.first;
    var fromDate = todayStr();
    var toDate = todayStr();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add booking'),
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('From: ${fmtDateDisplay(fromDate)}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: parseDateStr(fromDate) ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setLocal(() => fromDate = toDateStr(picked));
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('To: ${fmtDateDisplay(toDate)}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: parseDateStr(toDate) ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setLocal(() => toDate = toDateStr(picked));
                  },
                ),
                const SizedBox(height: 10),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone (optional)')),
                const SizedBox(height: 10),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email (optional)')),
                const SizedBox(height: 10),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)'), maxLines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                await widget.repo.addBooking(
                  hunterName: name,
                  idOrPassport: idCtrl.text.trim().isEmpty ? null : idCtrl.text.trim(),
                  farmId: farmId,
                  guestType: guestType,
                  fromDate: fromDate,
                  toDate: toDate,
                  phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                  email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                  notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
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
