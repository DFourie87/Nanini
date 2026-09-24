import 'package:flutter/material.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import 'game_breeding_models.dart';
import 'game_breeding_repository.dart';

class GameOverviewScreen extends StatelessWidget {
  const GameOverviewScreen({super.key, required this.repo, required this.species});
  final GameBreedingRepository repo;
  final String species;

  @override
  Widget build(BuildContext context) {
    if (species != 'Buffalo') return _eventsBody(context, null);
    return StreamBuilder<BuffaloRegistration?>(
      stream: repo.watchRegistration(species),
      builder: (context, regSnap) => _eventsBody(context, regSnap.data),
    );
  }

  Widget _eventsBody(BuildContext context, BuffaloRegistration? registration) {
    return StreamBuilder<List<GameEvent>>(
      stream: repo.watchEvents(),
      builder: (context, snap) {
        final events = (snap.data ?? []).where((e) => e.species == species).toList();

        final counts = {for (final t in GameEventType.values) t: events.where((e) => e.eventType == t).length};

        final animalTags = {for (final e in events) if ((e.tagNumber ?? '').isNotEmpty) e.tagNumber!}.toList()..sort();
        final aliveCount = animalTags.where((t) => _isAlive(t, events)).length;

        final weighings = events.where((e) => e.eventType == GameEventType.weighing && e.weightKg != null).toList();
        final avgWeight = weighings.isEmpty ? null : weighings.fold<double>(0, (s, e) => s + e.weightKg!) / weighings.length;

        final byCamp = <String, int>{};
        for (final tag in {for (final e in events) if ((e.tagNumber ?? '').isNotEmpty) e.tagNumber!}) {
          if (!_isAlive(tag, events)) continue;
          final camp = currentCampFor(tag, events);
          if (camp == null) continue;
          byCamp[camp] = (byCamp[camp] ?? 0) + 1;
        }
        final campEntries = byCamp.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (species == 'Buffalo') ...[
              _registrationCard(context, registration),
              const SizedBox(height: 20),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Summary of animals', style: Theme.of(context).textTheme.titleMedium),
                Text('$aliveCount alive of ${animalTags.length}', style: const TextStyle(color: NaniniColors.muted)),
              ],
            ),
            const SizedBox(height: 12),
            if (animalTags.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No tagged animals yet.')))
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      for (var i = 0; i < animalTags.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _animalRow(animalTags[i], events),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Text('By event type', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (final t in GameEventType.values) _row(gameEventTypeLabel(t), '${counts[t] ?? 0}'),
                    if (avgWeight != null) ...[
                      const Divider(),
                      _row('Avg. weight (weighings)', '${avgWeight.toStringAsFixed(1)} kg'),
                    ],
                  ],
                ),
              ),
            ),
            if (campEntries.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('By camp', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [for (final c in campEntries) _row(c.key, '${c.value}')],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text('Total events: ${events.length}', style: const TextStyle(color: NaniniColors.muted)),
          ],
        );
      },
    );
  }

  Widget _registrationCard(BuildContext context, BuffaloRegistration? registration) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Buffalo keeping registration', style: Theme.of(context).textTheme.titleMedium)),
                TextButton(
                  onPressed: () async {
                    if (!await requireAdmin(context)) return;
                    if (!context.mounted) return;
                    await _showEditRegistrationDialog(context, registration);
                  },
                  child: Text(registration == null ? 'Add' : 'Edit'),
                ),
              ],
            ),
            if (registration == null)
              const Text('Not recorded yet.', style: TextStyle(color: NaniniColors.muted))
            else ...[
              if ((registration.registrationNumber ?? '').isNotEmpty) _row('Registration no.', registration.registrationNumber!),
              if ((registration.holderName ?? '').isNotEmpty) _row('Holder', registration.holderName!),
              if ((registration.farmDescription ?? '').isNotEmpty) _row('Property', registration.farmDescription!),
              if ((registration.applicationDate ?? '').isNotEmpty) _row('Application date', fmtDateDisplay(registration.applicationDate)),
              if ((registration.certifiedDate ?? '').isNotEmpty) _row('Certified date', fmtDateDisplay(registration.certifiedDate)),
              if ((registration.spifStatus ?? '').isNotEmpty) _row('Specific Infection Free (SPIF)', registration.spifStatus!),
              if ((registration.fmdStatus ?? '').isNotEmpty) _row('Foot and Mouth Disease infected', registration.fmdStatus!),
              if ((registration.corridorDiseaseStatus ?? '').isNotEmpty) _row('Corridor disease infected', registration.corridorDiseaseStatus!),
              const SizedBox(height: 4),
              const Text('This registration does not expire.', style: TextStyle(color: NaniniColors.muted, fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showEditRegistrationDialog(BuildContext context, BuffaloRegistration? existing) async {
    final regNoCtrl = TextEditingController(text: existing?.registrationNumber);
    final holderCtrl = TextEditingController(text: existing?.holderName);
    final propertyCtrl = TextEditingController(text: existing?.farmDescription);
    var applicationDate = existing?.applicationDate;
    var certifiedDate = existing?.certifiedDate;
    final spifCtrl = TextEditingController(text: existing?.spifStatus);
    final fmdCtrl = TextEditingController(text: existing?.fmdStatus);
    final corridorCtrl = TextEditingController(text: existing?.corridorDiseaseStatus);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Buffalo keeping registration'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: regNoCtrl, decoration: const InputDecoration(labelText: 'Registration number')),
                const SizedBox(height: 10),
                TextField(controller: holderCtrl, decoration: const InputDecoration(labelText: 'Holder')),
                const SizedBox(height: 10),
                TextField(controller: propertyCtrl, decoration: const InputDecoration(labelText: 'Property')),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Application date: ${fmtDateDisplay(applicationDate)}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: parseDateStr(applicationDate) ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setLocal(() => applicationDate = toDateStr(d));
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Certified date: ${fmtDateDisplay(certifiedDate)}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: parseDateStr(certifiedDate) ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setLocal(() => certifiedDate = toDateStr(d));
                  },
                ),
                const SizedBox(height: 10),
                TextField(controller: spifCtrl, decoration: const InputDecoration(labelText: 'Specific Infection Free (SPIF)')),
                const SizedBox(height: 10),
                TextField(controller: fmdCtrl, decoration: const InputDecoration(labelText: 'Foot and Mouth Disease infected')),
                const SizedBox(height: 10),
                TextField(controller: corridorCtrl, decoration: const InputDecoration(labelText: 'Corridor disease infected')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                await repo.upsertRegistration(BuffaloRegistration(
                  species: species,
                  registrationNumber: regNoCtrl.text.trim().isEmpty ? null : regNoCtrl.text.trim(),
                  holderName: holderCtrl.text.trim().isEmpty ? null : holderCtrl.text.trim(),
                  farmDescription: propertyCtrl.text.trim().isEmpty ? null : propertyCtrl.text.trim(),
                  applicationDate: applicationDate,
                  certifiedDate: certifiedDate,
                  spifStatus: spifCtrl.text.trim().isEmpty ? null : spifCtrl.text.trim(),
                  fmdStatus: fmdCtrl.text.trim().isEmpty ? null : fmdCtrl.text.trim(),
                  corridorDiseaseStatus: corridorCtrl.text.trim().isEmpty ? null : corridorCtrl.text.trim(),
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// An animal counts as alive as long as its most recent event isn't a
  /// death or sale.
  bool _isAlive(String tag, List<GameEvent> events) {
    final tagEvents = events.where((e) => e.tagNumber == tag).toList()
      ..sort((a, b) {
        final byDate = a.eventDate.compareTo(b.eventDate);
        return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
      });
    if (tagEvents.isEmpty) return true;
    final last = tagEvents.last.eventType;
    return last != GameEventType.death && last != GameEventType.sale;
  }

  Widget _animalRow(String tag, List<GameEvent> events) {
    final alive = _isAlive(tag, events);
    final tagEvents = events.where((e) => e.tagNumber == tag).toList()
      ..sort((a, b) {
        final byDate = a.eventDate.compareTo(b.eventDate);
        return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
      });
    final status = alive ? 'Alive' : gameEventTypeLabel(tagEvents.last.eventType);
    final statusColor = alive ? NaniniColors.green : NaniniColors.red;
    final camp = currentCampFor(tag, events);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(tag, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (camp != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(camp, style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
            child: Text(status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}
