import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/formatters.dart';
import '../../core/auth/session.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'truck_booking_form.dart';
import 'truck_models.dart';
import 'truck_repository.dart';

class TruckHomeScreen extends StatefulWidget {
  const TruckHomeScreen({super.key});
  @override
  State<TruckHomeScreen> createState() => _TruckHomeScreenState();
}

class _TruckHomeScreenState extends State<TruckHomeScreen> {
  final repo = TruckRepository();
  DateTime calMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? selectedDate;
  String? trackingUrl;

  @override
  void initState() {
    super.initState();
    repo.fetchTrackingUrl().then((u) => setState(() => trackingUrl = u));
  }

  @override
  Widget build(BuildContext context) {
    final isManager = context.watch<Session>().isAdmin;
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Truck'),
      body: StreamBuilder<List<TruckBooking>>(
        stream: repo.watchBookings(),
        builder: (context, snap) {
          final bookings = snap.data ?? [];
          final bookedDays = bookings.map((b) => DateTime(b.startAt.year, b.startAt.month, b.startAt.day)).toSet();

          final visible = selectedDate != null
              ? bookings.where((b) => _sameDay(b.startAt, selectedDate!)).toList()
              : bookings.where((b) => b.endAt.isAfter(DateTime.now())).toList();
          visible.sort((a, b) => a.startAt.compareTo(b.startAt));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (trackingUrl != null && trackingUrl!.isNotEmpty)
                Card(
                  color: NaniniColors.disabledBg,
                  child: ListTile(
                    leading: const Icon(Icons.gps_fixed),
                    title: const Text('Live tracking'),
                    subtitle: Text(trackingUrl!, overflow: TextOverflow.ellipsis),
                  ),
                ),
              if (isManager)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _showTrackingUrlDialog(context),
                    child: Text(trackingUrl == null || trackingUrl!.isEmpty ? 'Add tracking link' : 'Edit tracking link'),
                  ),
                ),
              const SizedBox(height: 8),
              _CalendarHeader(
                month: calMonth,
                onPrev: () => setState(() => calMonth = DateTime(calMonth.year, calMonth.month - 1)),
                onNext: () => setState(() => calMonth = DateTime(calMonth.year, calMonth.month + 1)),
              ),
              _CalendarGrid(
                month: calMonth,
                bookedDays: bookedDays,
                selectedDate: selectedDate,
                onSelect: (d) => setState(() => selectedDate = _sameDay(d, selectedDate ?? DateTime(0)) ? null : d),
              ),
              const SizedBox(height: 20),
              if (isManager)
                FilledButton.icon(
                  onPressed: () => showBookingForm(context, repo: repo, existing: bookings),
                  icon: const Icon(Icons.add),
                  label: const Text('Book the truck'),
                ),
              const SizedBox(height: 12),
              Text(selectedDate != null ? 'Bookings on ${fmtDateDisplay(toDateStr(selectedDate!))}' : 'Upcoming bookings',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (visible.isEmpty) const Text('No bookings.'),
              for (final b in visible)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('${fmtDateTimeDisplay(b.startAt.toIso8601String())} → ${fmtDateTimeDisplay(b.endAt.toIso8601String())}'),
                    subtitle: Text([
                      if (b.locationText != null) b.locationText!,
                      if (b.bookedBy != null) 'Booked by ${b.bookedBy}',
                      if (b.notes != null) b.notes!,
                    ].join(' · ')),
                    trailing: isManager
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => showBookingForm(context, repo: repo, existing: bookings, editing: b),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final ok = await confirmDialog(context, message: 'Cancel this booking?', danger: true);
                                  if (ok) {
                                    await repo.deleteBooking(b.id);
                                    if (context.mounted) showToast(context, 'Booking cancelled');
                                  }
                                },
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showTrackingUrlDialog(BuildContext context) async {
    if (!await requireAdmin(context)) return;
    if (!context.mounted) return;
    final controller = TextEditingController(text: trackingUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Live tracking link'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'URL')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (url != null) {
      await repo.setTrackingUrl(url);
      setState(() => trackingUrl = url);
    }
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({required this.month, required this.onPrev, required this.onNext});
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  static const _names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
        Text('${_names[month.month - 1]} ${month.year}', style: Theme.of(context).textTheme.titleMedium),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({required this.month, required this.bookedDays, required this.selectedDate, required this.onSelect});
  final DateTime month;
  final Set<DateTime> bookedDays;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final leading = firstOfMonth.weekday % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
    ];

    return Column(
      children: [
        Row(children: const ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d) => Expanded(child: Center(child: Text(d, style: const TextStyle(color: NaniniColors.muted))))).toList()),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cells.map((d) {
            if (d == null) return const SizedBox.shrink();
            final hasBooking = bookedDays.contains(d);
            final isSelected = selectedDate != null && d.year == selectedDate!.year && d.month == selectedDate!.month && d.day == selectedDate!.day;
            return InkWell(
              onTap: () => onSelect(d),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isSelected ? NaniniColors.rust : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${d.day}', style: TextStyle(color: isSelected ? Colors.white : NaniniColors.ink)),
                    if (hasBooking) Container(width: 5, height: 5, decoration: BoxDecoration(color: isSelected ? Colors.white : NaniniColors.rustDark, shape: BoxShape.circle)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
