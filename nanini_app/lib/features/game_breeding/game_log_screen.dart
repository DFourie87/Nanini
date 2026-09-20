import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'game_breeding_models.dart';
import 'game_breeding_repository.dart';

class GameLogScreen extends StatefulWidget {
  const GameLogScreen({super.key, required this.repo, required this.species});
  final GameBreedingRepository repo;
  final String species;

  @override
  State<GameLogScreen> createState() => _GameLogScreenState();
}

class _GameLogScreenState extends State<GameLogScreen> {
  final tagCtrl = TextEditingController();
  final weightCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  GameEventType eventType = GameEventType.birth;
  DateTime eventDate = DateTime.now();

  bool get _isWeighing => eventType == GameEventType.weighing;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GameEvent>>(
      stream: widget.repo.watchEvents(),
      builder: (context, snap) {
        final events = (snap.data ?? []).where((e) => e.species == widget.species).toList()
          ..sort((a, b) => b.eventDate.compareTo(a.eventDate));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('New event', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<GameEventType>(
              initialValue: eventType,
              decoration: const InputDecoration(labelText: 'Event type'),
              items: GameEventType.values.map((t) => DropdownMenuItem(value: t, child: Text(gameEventTypeLabel(t)))).toList(),
              onChanged: (v) => setState(() => eventType = v!),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(context: context, initialDate: eventDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (picked != null) setState(() => eventDate = picked);
              },
              child: InputDecorator(decoration: const InputDecoration(labelText: 'Date'), child: Text(fmtDateDisplay(toDateStr(eventDate)))),
            ),
            const SizedBox(height: 12),
            TextField(controller: tagCtrl, decoration: const InputDecoration(labelText: 'Tag number')),
            if (_isWeighing) ...[
              const SizedBox(height: 12),
              TextField(controller: weightCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Weight (kg)')),
            ],
            const SizedBox(height: 12),
            TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Log event')),
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 12),
            Text('Events', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (events.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No events logged yet.'))
            else
              for (final e in events) _eventCard(context, e),
          ],
        );
      },
    );
  }

  Widget _eventCard(BuildContext context, GameEvent e) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_iconFor(e.eventType), color: NaniniColors.rustDark),
        title: Text('${gameEventTypeLabel(e.eventType)}${(e.tagNumber ?? '').isNotEmpty ? ' · ${e.tagNumber}' : ''}'),
        subtitle: Text([
          fmtDateDisplay(e.eventDate),
          if (e.weightKg != null) '${e.weightKg} kg',
          if ((e.notes ?? '').isNotEmpty) e.notes!,
        ].join(' · ')),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ok = await confirmDialog(context, message: 'Delete this event?', danger: true);
            if (ok) {
              await widget.repo.deleteEvent(e.id!);
              if (context.mounted) showToast(context, 'Event deleted');
            }
          },
        ),
      ),
    );
  }

  IconData _iconFor(GameEventType t) => switch (t) {
        GameEventType.birth => Icons.child_care,
        GameEventType.death => Icons.heart_broken_outlined,
        GameEventType.sale => Icons.sell_outlined,
        GameEventType.purchase => Icons.add_shopping_cart_outlined,
        GameEventType.weighing => Icons.monitor_weight_outlined,
        GameEventType.health => Icons.medical_services_outlined,
      };

  Future<void> _save() async {
    final weight = _isWeighing ? double.tryParse(weightCtrl.text) : null;
    await widget.repo.addEvent(GameEvent(
      species: widget.species,
      tagNumber: tagCtrl.text.trim().isEmpty ? null : tagCtrl.text.trim(),
      eventType: eventType,
      eventDate: toDateStr(eventDate),
      weightKg: weight,
      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
    ));
    if (!mounted) return;
    showToast(context, 'Event logged');
    setState(() {
      tagCtrl.clear();
      weightCtrl.clear();
      notesCtrl.clear();
      eventType = GameEventType.birth;
      eventDate = DateTime.now();
    });
  }
}
