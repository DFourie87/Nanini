import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import 'hunting_invoice_detail_screen.dart';
import 'hunting_models.dart';
import 'hunting_repository.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

class HuntingBookingsScreen extends StatefulWidget {
  const HuntingBookingsScreen({super.key, required this.repo});
  final HuntingRepository repo;
  @override
  State<HuntingBookingsScreen> createState() => _HuntingBookingsScreenState();
}

class _HuntingBookingsScreenState extends State<HuntingBookingsScreen> {
  List<Farm> farms = [];
  String? farmId;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String selectedDay = todayStr();

  @override
  void initState() {
    super.initState();
    fetchHuntingFarms().then((f) {
      if (!mounted) return;
      final limpopodraai = f.where((farm) => farm.name.toLowerCase().contains('limpopodraai'));
      setState(() {
        farms = f;
        farmId = limpopodraai.isNotEmpty ? limpopodraai.first.id : (f.isNotEmpty ? f.first.id : null);
      });
    });
  }

  Farm? get _farm => farms.where((f) => f.id == farmId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<List<HuntingBooking>>(
          stream: widget.repo.watchBookings(),
          builder: (context, snap) {
            final bookings = (snap.data ?? []).where((b) => b.farmId == farmId).toList()
              ..sort((a, b) => a.fromDate.compareTo(b.fromDate));
            final dayBookings = bookings.where((b) => b.coversDay(selectedDay)).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              children: [
                if (farms.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final f in farms)
                        ChoiceChip(
                          label: Text(f.name),
                          selected: farmId == f.id,
                          onSelected: (_) => setState(() => farmId = f.id),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _calendar(context, bookings),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Bookings on ${fmtDateDisplay(selectedDay)}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (dayBookings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No bookings on this day.', style: TextStyle(color: NaniniColors.muted)),
                  ),
                for (final b in dayBookings)
                  Card(
                    child: ListTile(
                      title: Text(b.hunterName),
                      subtitle: Text(
                        '${fmtDateDisplay(b.fromDate)} – ${fmtDateDisplay(b.toDate)} · ${guestTypeLabel(b.guestType)}'
                        '${b.depositPaid > 0 ? ' · Deposit ${fmtR(b.depositPaid)}' : ''}',
                      ),
                      trailing: b.converted
                          ? const Chip(label: Text('Invoiced'), visualDensity: VisualDensity.compact)
                          : const Icon(Icons.chevron_right),
                      onTap: () => _showBookingDetails(context, b),
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
            onPressed: farmId == null ? null : () => _showBookingDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Add booking'),
          ),
        ),
      ],
    );
  }

  Widget _calendar(BuildContext context, List<HuntingBooking> bookings) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1; // weeks start on Monday
    final cellCount = ((leading + daysInMonth) / 7).ceil() * 7;
    final today = todayStr();

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)),
            ),
            Expanded(
              child: Text(
                '${_monthNames[month.month - 1]} ${month.year}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)),
            ),
          ],
        ),
        Row(
          children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(child: Text(d, style: const TextStyle(color: NaniniColors.muted, fontWeight: FontWeight.w600))),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var row = 0; row < cellCount / 7; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: Builder(builder: (context) {
                    final dayNum = row * 7 + col - leading + 1;
                    if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox(height: 40);
                    final day = toDateStr(DateTime(month.year, month.month, dayNum));
                    final booked = bookings.any((b) => b.coversDay(day));
                    final selected = day == selectedDay;
                    return Padding(
                      padding: const EdgeInsets.all(2),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => selectedDay = day),
                        child: Container(
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: booked ? NaniniColors.red : null,
                            borderRadius: BorderRadius.circular(8),
                            border: selected ? Border.all(color: NaniniColors.ink, width: 2) : null,
                          ),
                          child: Text(
                            '$dayNum',
                            style: TextStyle(
                              color: booked ? Colors.white : NaniniColors.ink,
                              fontWeight: day == today || booked ? FontWeight.w700 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _showBookingDetails(BuildContext context, HuntingBooking b) async {
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 110, child: Text(label, style: const TextStyle(color: NaniniColors.muted))),
              Expanded(child: Text(value)),
            ],
          ),
        );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.hunterName, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              row('Farm', _farm?.name ?? ''),
              row('Guest type', guestTypeLabel(b.guestType)),
              row('Dates', '${fmtDateDisplay(b.fromDate)} – ${fmtDateDisplay(b.toDate)}'),
              row('Phone', b.phone ?? ''),
              if ((b.email ?? '').isNotEmpty) row('Email', b.email!),
              row('Deposit paid', b.depositPaid > 0 ? fmtR(b.depositPaid) : 'None yet'),
              if ((b.notes ?? '').isNotEmpty) row('Notes', b.notes!),
              row('Status', b.converted ? 'Invoiced' : 'Booked'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!b.converted)
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _convertToInvoice(context, b);
                      },
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('Hunting done – make invoice'),
                    )
                  else if (b.invoiceId != null)
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openInvoice(context, b.invoiceId!);
                      },
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('Open invoice'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showBookingDialog(context, existing: b);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit / deposit'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await confirmDialog(ctx, message: 'Delete this booking?', danger: true);
                      if (!ok) return;
                      await widget.repo.deleteBooking(b.id);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openInvoice(BuildContext context, String invoiceId) async {
    final farm = _farm;
    if (farm == null) return;
    try {
      final invoice = await widget.repo.fetchInvoice(invoiceId);
      if (!context.mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => HuntingInvoiceDetailScreen(repo: widget.repo, invoice: invoice, farm: farm)));
    } catch (e) {
      if (context.mounted) showToast(context, 'Could not open invoice: $e', isError: true);
    }
  }

  /// Hunting's done: turn the booking into the hunter's invoice (EFT) or
  /// breakdown (cash), carrying the deposit over to be subtracted.
  Future<void> _convertToInvoice(BuildContext context, HuntingBooking booking) async {
    final farm = _farm;
    if (farm == null) return;
    var paymentMethod = HuntingPaymentMethod.eft;
    final idCtrl = TextEditingController(text: booking.idOrPassport);
    final nicknameCtrl = TextEditingController();
    var saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Make invoice'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.hunterName, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (booking.depositPaid > 0)
                  Text('Deposit ${fmtR(booking.depositPaid)} will be deducted', style: const TextStyle(color: NaniniColors.muted)),
                const SizedBox(height: 10),
                TextField(
                  controller: nicknameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nickname *'),
                ),
                const SizedBox(height: 10),
                TextField(controller: idCtrl, decoration: const InputDecoration(labelText: 'ID/Passport number *')),
                const SizedBox(height: 10),
                DropdownButtonFormField<HuntingPaymentMethod>(
                  initialValue: paymentMethod,
                  decoration: const InputDecoration(labelText: 'Payment method'),
                  items: const [
                    DropdownMenuItem(value: HuntingPaymentMethod.eft, child: Text('EFT (invoice)')),
                    DropdownMenuItem(value: HuntingPaymentMethod.cash, child: Text('Cash (breakdown)')),
                  ],
                  onChanged: (v) => setLocal(() => paymentMethod = v!),
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
                      final nickname = nicknameCtrl.text.trim();
                      final idNumber = idCtrl.text.trim();
                      if (nickname.isEmpty || idNumber.isEmpty) {
                        showToast(ctx, 'Please fill in the nickname and ID/passport number', isError: true);
                        return;
                      }
                      setLocal(() => saving = true);
                      try {
                        final invoice = await widget.repo.addInvoice(
                          hunterName: booking.hunterName,
                          firstName: booking.firstName,
                          nickname: nickname,
                          surname: booking.surname,
                          idOrPassport: idNumber,
                          farmId: booking.farmId,
                          guestType: booking.guestType,
                          paymentMethod: paymentMethod,
                          visitDate: booking.fromDate,
                          visitToDate: booking.toDate,
                          depositPaid: booking.depositPaid,
                        );
                        await widget.repo.markBookingConverted(booking.id, invoice.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => HuntingInvoiceDetailScreen(repo: widget.repo, invoice: invoice, farm: farm)),
                        );
                      } catch (e) {
                        if (ctx.mounted) {
                          setLocal(() => saving = false);
                          showToast(ctx, 'Could not make invoice: $e', isError: true);
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Make invoice'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBookingDialog(BuildContext context, {HuntingBooking? existing}) async {
    final currentFarmId = existing?.farmId ?? farmId;
    if (currentFarmId == null) return;
    final firstNameCtrl = TextEditingController(text: existing?.firstName ?? existing?.hunterName);
    final surnameCtrl = TextEditingController(text: existing?.surname);
    final phoneCtrl = TextEditingController(text: existing?.phone);
    final emailCtrl = TextEditingController(text: existing?.email);
    final notesCtrl = TextEditingController(text: existing?.notes);
    final depositCtrl = TextEditingController(
      text: (existing?.depositPaid ?? 0) > 0 ? existing!.depositPaid.toStringAsFixed(0) : '',
    );
    var bookingFarmId = currentFarmId;
    var guestType = existing?.guestType ?? kGuestTypes.first;
    var fromDate = existing?.fromDate ?? selectedDay;
    var toDate = existing?.toDate ?? selectedDay;
    var saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add booking' : 'Edit booking'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: firstNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: surnameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Surname *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: bookingFarmId,
                  decoration: const InputDecoration(labelText: 'Farm'),
                  items: farms.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
                  onChanged: (v) => setLocal(() => bookingFarmId = v!),
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
                    if (picked == null) return;
                    setLocal(() {
                      fromDate = toDateStr(picked);
                      if (toDate.compareTo(fromDate) < 0) toDate = fromDate;
                    });
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('To: ${fmtDateDisplay(toDate)}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final from = parseDateStr(fromDate) ?? DateTime.now();
                    final current = parseDateStr(toDate) ?? from;
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: current.isBefore(from) ? from : current,
                      firstDate: from,
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setLocal(() => toDate = toDateStr(picked));
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: depositCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Deposit paid (R)', helperText: 'Can be filled in later'),
                ),
                const SizedBox(height: 10),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)'), maxLines: 2),
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
                      final surname = surnameCtrl.text.trim();
                      final phone = phoneCtrl.text.trim();
                      final missing = [
                        if (firstName.isEmpty) 'name',
                        if (surname.isEmpty) 'surname',
                        if (phone.isEmpty) 'phone number',
                      ];
                      if (missing.isNotEmpty) {
                        showToast(ctx, 'Please fill in: ${missing.join(', ')}', isError: true);
                        return;
                      }
                      final depositText = depositCtrl.text.trim().replaceAll(',', '.');
                      final deposit = depositText.isEmpty ? 0.0 : double.tryParse(depositText);
                      if (deposit == null || deposit < 0) {
                        showToast(ctx, 'Deposit must be a number', isError: true);
                        return;
                      }
                      setLocal(() => saving = true);
                      try {
                        await widget.repo.saveBooking(
                          id: existing?.id,
                          firstName: firstName,
                          surname: surname,
                          farmId: bookingFarmId,
                          guestType: guestType,
                          fromDate: fromDate,
                          toDate: toDate,
                          phone: phone,
                          email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                          notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                          depositPaid: deposit,
                        );
                        // A deposit that comes in after the invoice was made
                        // still has to come off the hunter's total.
                        if (existing?.invoiceId != null && deposit != existing!.depositPaid) {
                          await widget.repo.setInvoiceDeposit(existing.invoiceId!, deposit);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          setState(() {
                            farmId = bookingFarmId;
                            selectedDay = fromDate;
                            final d = parseDateStr(fromDate);
                            if (d != null) month = DateTime(d.year, d.month);
                          });
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setLocal(() => saving = false);
                          showToast(ctx, 'Could not save booking: $e', isError: true);
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save'),
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
