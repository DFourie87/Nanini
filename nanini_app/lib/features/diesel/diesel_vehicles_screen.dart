import 'package:flutter/material.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'diesel_models.dart';
import 'diesel_repository.dart';

/// Admin-only equipment/vehicle list -- add, edit, and remove the entries
/// the diesel log entry form's "Equipment / vehicle" dropdown offers.
class DieselVehiclesScreen extends StatelessWidget {
  const DieselVehiclesScreen({super.key, required this.repo});
  final DieselRepository repo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Equipment & vehicles')),
      body: StreamBuilder<List<DieselVehicle>>(
        stream: repo.watchVehicles(),
        builder: (context, snap) {
          final vehicles = [...(snap.data ?? <DieselVehicle>[])]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          if (vehicles.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No equipment or vehicles yet.'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        if (!await requireAdmin(context)) return;
                        if (!context.mounted) return;
                        await _showVehicleDialog(context, repo);
                      },
                      child: const Text('Add equipment / vehicle'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final v in vehicles)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(v.name),
                    subtitle: Text([
                      if (v.asset?.trim().isNotEmpty ?? false) 'Reg: ${v.asset}',
                      if (v.vin?.trim().isNotEmpty ?? false) 'VIN: ${v.vin}',
                      v.unit == 'km' ? 'Kilometers' : 'Hours',
                    ].join(' · ')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () async {
                            if (!await requireAdmin(context)) return;
                            if (!context.mounted) return;
                            await _showVehicleDialog(context, repo, existing: v);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: NaniniColors.red),
                          onPressed: () async {
                            if (!await requireAdmin(context)) return;
                            if (!context.mounted) return;
                            final ok = await confirmDialog(
                              context,
                              message: 'Remove "${v.name}"? Past usage records that reference it are kept.',
                            );
                            if (!ok) return;
                            await repo.deleteVehicle(v.id);
                            if (context.mounted) showToast(context, 'Removed');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          if (!await requireAdmin(context)) return;
          if (!context.mounted) return;
          await _showVehicleDialog(context, repo);
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

Future<void> _showVehicleDialog(BuildContext context, DieselRepository repo, {DieselVehicle? existing}) async {
  final nameCtrl = TextEditingController(text: existing?.name);
  final assetCtrl = TextEditingController(text: existing?.asset);
  final vinCtrl = TextEditingController(text: existing?.vin);
  String unit = existing?.unit ?? 'hours';

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(existing == null ? 'Add equipment / vehicle' : 'Edit equipment / vehicle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Description')),
              const SizedBox(height: 10),
              TextField(controller: assetCtrl, decoration: const InputDecoration(labelText: 'Registration number')),
              const SizedBox(height: 10),
              TextField(controller: vinCtrl, decoration: const InputDecoration(labelText: 'VIN number')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: unit,
                decoration: const InputDecoration(labelText: 'Logged in'),
                items: const [
                  DropdownMenuItem(value: 'hours', child: Text('Hours (tractors, equipment)')),
                  DropdownMenuItem(value: 'km', child: Text('Kilometers (trucks, vehicles)')),
                ],
                onChanged: (v) => setDialogState(() => unit = v ?? 'hours'),
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
              if (existing == null) {
                await repo.addVehicle(name: name, asset: assetCtrl.text.trim(), vin: vinCtrl.text.trim(), unit: unit);
              } else {
                await repo.updateVehicle(existing.id, name: name, asset: assetCtrl.text.trim(), vin: vinCtrl.text.trim(), unit: unit);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
