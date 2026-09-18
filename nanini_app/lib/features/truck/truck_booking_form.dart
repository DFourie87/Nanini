import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/widgets/confirm_dialog.dart';
import 'truck_models.dart';
import 'truck_repository.dart';

const _defaultCenter = LatLng(-23.9, 29.45);

Future<void> showBookingForm(
  BuildContext context, {
  required TruckRepository repo,
  required List<TruckBooking> existing,
  TruckBooking? editing,
}) async {
  DateTime start = editing?.startAt ?? DateTime.now();
  DateTime end = editing?.endAt ?? DateTime.now().add(const Duration(hours: 4));
  final locationCtrl = TextEditingController(text: editing?.locationText);
  final bookedByCtrl = TextEditingController(text: editing?.bookedBy);
  final notesCtrl = TextEditingController(text: editing?.notes);
  LatLng? pin = editing?.lat != null ? LatLng(editing!.lat!, editing.lng!) : null;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(editing == null ? 'Book the truck' : 'Edit booking', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              _DateTimeField(
                label: 'Start',
                value: start,
                onChanged: (v) => setState(() => start = v),
              ),
              const SizedBox(height: 12),
              _DateTimeField(
                label: 'End',
                value: end,
                onChanged: (v) => setState(() => end = v),
              ),
              const SizedBox(height: 12),
              TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Location (e.g. Jhb Fresh Produce Market)')),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: pin ?? _defaultCenter,
                      initialZoom: 9,
                      onTap: (tapPos, point) => setState(() => pin = point),
                    ),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.naniniboerdery.nanini_app'),
                      if (pin != null) MarkerLayer(markers: [Marker(point: pin!, width: 36, height: 36, child: const Icon(Icons.location_pin, color: Colors.red, size: 36))]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text('Tap the map to place a pin', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(controller: bookedByCtrl, decoration: const InputDecoration(labelText: 'Your name')),
              const SizedBox(height: 12),
              TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  if (!end.isAfter(start)) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('End must be after start')));
                    return;
                  }
                  final draft = TruckBooking(
                    id: editing?.id ?? '',
                    startAt: start,
                    endAt: end,
                    locationText: locationCtrl.text.trim().isEmpty ? null : locationCtrl.text.trim(),
                    lat: pin?.latitude,
                    lng: pin?.longitude,
                    bookedBy: bookedByCtrl.text.trim().isEmpty ? null : bookedByCtrl.text.trim(),
                    notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                  );
                  if (repo.overlaps(draft, existing, excludeId: editing?.id)) {
                    final proceed = await confirmDialog(ctx, message: 'This overlaps an existing booking. Book anyway?');
                    if (!proceed) return;
                  }
                  if (editing != null) {
                    await repo.updateBooking(editing.id, draft);
                  } else {
                    await repo.addBooking(draft);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save booking'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({required this.label, required this.value, required this.onChanged});
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(context: context, initialDate: value, firstDate: DateTime(2020), lastDate: DateTime(2100));
        if (date == null) return;
        if (!context.mounted) return;
        final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(value));
        if (time == null) return;
        onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text('${value.day}/${value.month}/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}'),
      ),
    );
  }
}
