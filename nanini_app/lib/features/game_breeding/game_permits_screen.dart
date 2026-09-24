import 'package:flutter/material.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import 'game_breeding_models.dart';
import 'game_breeding_repository.dart';

/// The Dept. of Agriculture "Registration of Land for the Keeping of
/// Buffalo" -- one per registered farm, doesn't expire, so this is just
/// reference data (no renewal warning, unlike the Hunting module's P3
/// exemption certificates).
class GamePermitsScreen extends StatelessWidget {
  const GamePermitsScreen({super.key, required this.repo});
  final GameBreedingRepository repo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Farm>>(
      future: fetchBuffaloFarms(),
      builder: (context, farmSnap) {
        final farms = farmSnap.data ?? [];
        return StreamBuilder<List<BuffaloRegistration>>(
          stream: repo.watchRegistrations(),
          builder: (context, regSnap) {
            final registrations = regSnap.data ?? [];
            if (farms.isEmpty) return const Center(child: Text('No farms yet.'));
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final farm in farms) ...[
                  _registrationCard(context, farm, registrations.where((r) => r.farmId == farm.id).firstOrNull),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _registrationCard(BuildContext context, Farm farm, BuffaloRegistration? registration) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(farm.name, style: Theme.of(context).textTheme.titleMedium)),
                TextButton(
                  onPressed: () async {
                    if (!await requireAdmin(context)) return;
                    if (!context.mounted) return;
                    await _showEditRegistrationDialog(context, farm, registration);
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

  Future<void> _showEditRegistrationDialog(BuildContext context, Farm farm, BuffaloRegistration? existing) async {
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
                  farmId: farm.id,
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

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
