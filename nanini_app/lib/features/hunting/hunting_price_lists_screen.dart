import 'package:flutter/material.dart';
import '../../core/auth/admin_gate.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import '../employees/employees_repository.dart';
import 'hunting_models.dart';
import 'hunting_repository.dart';

class HuntingPriceListsScreen extends StatefulWidget {
  const HuntingPriceListsScreen({super.key, required this.repo});
  final HuntingRepository repo;
  @override
  State<HuntingPriceListsScreen> createState() => _HuntingPriceListsScreenState();
}

class _HuntingPriceListsScreenState extends State<HuntingPriceListsScreen> {
  final employeesRepo = EmployeesRepository();
  List<Farm> farms = [];
  String? selectedFarmId;

  @override
  void initState() {
    super.initState();
    employeesRepo.fetchFarms().then((f) {
      if (!mounted) return;
      setState(() {
        farms = f;
        selectedFarmId = f.isNotEmpty ? f.first.id : null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HuntingPriceEntry>>(
      stream: widget.repo.watchPriceList(),
      builder: (context, priceSnap) {
        return StreamBuilder<List<HuntingAccommodationRate>>(
          stream: widget.repo.watchAccommodationRates(),
          builder: (context, rateSnap) {
            return StreamBuilder<List<HuntingHornPriceBand>>(
              stream: widget.repo.watchHornBands(),
              builder: (context, bandSnap) {
            final prices = priceSnap.data ?? [];
            final rates = rateSnap.data ?? [];
            final bands = bandSnap.data ?? [];
            final farmPrices = prices.where((p) => p.farmId == selectedFarmId).toList()
              ..sort((a, b) => a.species.toLowerCase().compareTo(b.species.toLowerCase()));
            final farmBands = bands.where((b) => b.farmId == selectedFarmId).toList()
              ..sort((a, b) {
                final species = a.species.toLowerCase().compareTo(b.species.toLowerCase());
                return species != 0 ? species : a.minInches.compareTo(b.minInches);
              });
            final accommodationRate = rates.where((r) => r.farmId == selectedFarmId).firstOrNull;

            return Stack(
              children: [
                Column(
                  children: [
                if (farms.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: farms
                          .map((f) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                child: ChoiceChip(
                                  label: Text(f.name),
                                  selected: selectedFarmId == f.id,
                                  onSelected: (_) => setState(() => selectedFarmId = f.id),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                Expanded(
                  child: selectedFarmId == null
                      ? const Center(child: Text('No farms yet.'))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                          children: [
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(child: Text('Accommodation', style: Theme.of(context).textTheme.titleMedium)),
                                        TextButton(
                                          onPressed: () async {
                                            if (!await requireAdmin(context)) return;
                                            if (!context.mounted) return;
                                            await _showAccommodationRateDialog(context, widget.repo, selectedFarmId!, accommodationRate);
                                          },
                                          child: Text(accommodationRate == null ? 'Set rate' : 'Edit'),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      accommodationRate == null
                                          ? 'No rate set'
                                          : 'Hunter: ${fmtR(accommodationRate.hunterRate)}/night · Non-hunter: ${fmtR(accommodationRate.nonHunterRate)}/night',
                                      style: const TextStyle(color: NaniniColors.muted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text('Animal prices (flat / female)', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Card(
                              child: Column(
                                children: [
                                  if (farmPrices.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No prices set for this farm yet.')),
                                  for (final p in farmPrices)
                                    ListTile(
                                      title: Text(p.species),
                                      subtitle: Text(guestTypeLabel(p.guestType)),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(fmtR(p.price), style: const TextStyle(fontWeight: FontWeight.w700)),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 18),
                                            onPressed: () async {
                                              if (!await requireAdmin(context)) return;
                                              if (!context.mounted) return;
                                              final ok = await confirmDialog(context, message: 'Remove this price?');
                                              if (ok) await widget.repo.deletePrice(p.id);
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: Text('Male pricing (by horn length)', style: Theme.of(context).textTheme.titleMedium)),
                                TextButton.icon(
                                  onPressed: () async {
                                    if (!await requireAdmin(context)) return;
                                    if (!context.mounted) return;
                                    await showAddHornBandDialog(context, widget.repo, farms, selectedFarmId);
                                  },
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add band'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Card(
                              child: Column(
                                children: [
                                  if (farmBands.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No horn-length bands set for this farm yet.')),
                                  for (final b in farmBands)
                                    ListTile(
                                      title: Text(b.species),
                                      subtitle: Text(
                                        '${guestTypeLabel(b.guestType)} · ${b.minInches.toStringAsFixed(0)}${b.maxInches == null ? 'in +' : '–${b.maxInches!.toStringAsFixed(0)}in'}',
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(fmtR(b.price), style: const TextStyle(fontWeight: FontWeight.w700)),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 18),
                                            onPressed: () async {
                                              if (!await requireAdmin(context)) return;
                                              if (!context.mounted) return;
                                              final ok = await confirmDialog(context, message: 'Remove this band?');
                                              if (ok) await widget.repo.deleteHornBand(b.id);
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
                  ],
                ),
                if (selectedFarmId != null)
                  Positioned(
                    right: 16,
                    bottom: 32,
                    child: FloatingActionButton.extended(
                      onPressed: () async {
                        if (!await requireAdmin(context)) return;
                        if (!context.mounted) return;
                        await showAddHuntingPriceDialog(context, widget.repo, farms, selectedFarmId);
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add price'),
                    ),
                  ),
              ],
            );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showAccommodationRateDialog(
    BuildContext context,
    HuntingRepository repo,
    String farmId,
    HuntingAccommodationRate? existing,
  ) async {
    final hunterCtrl = TextEditingController(text: existing?.hunterRate.toStringAsFixed(0));
    final nonHunterCtrl = TextEditingController(text: existing?.nonHunterRate.toStringAsFixed(0));
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accommodation rate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: hunterCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Hunter — price per night (R)')),
            const SizedBox(height: 10),
            TextField(
              controller: nonHunterCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Non-hunter — price per night (R)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final hunterRate = double.tryParse(hunterCtrl.text);
              final nonHunterRate = double.tryParse(nonHunterCtrl.text);
              if (hunterRate == null || hunterRate < 0 || nonHunterRate == null || nonHunterRate < 0) return;
              await repo.setAccommodationRate(farmId: farmId, hunterRate: hunterRate, nonHunterRate: nonHunterRate);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

Future<void> showAddHuntingPriceDialog(BuildContext context, HuntingRepository repo, List<Farm> farms, String? initialFarmId) async {
  if (farms.isEmpty) return;
  var farmId = initialFarmId ?? farms.first.id;
  var guestType = kGuestTypes.first;
  final speciesCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Add price'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: farmId,
              decoration: const InputDecoration(labelText: 'Farm'),
              items: farms.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
              onChanged: (v) => setLocal(() => farmId = v!),
            ),
            const SizedBox(height: 10),
            TextField(controller: speciesCtrl, decoration: const InputDecoration(labelText: 'Species')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: guestType,
              decoration: const InputDecoration(labelText: 'Guest type'),
              items: kGuestTypes.map((g) => DropdownMenuItem(value: g, child: Text(guestTypeLabel(g)))).toList(),
              onChanged: (v) => setLocal(() => guestType = v!),
            ),
            const SizedBox(height: 10),
            TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price (R)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final species = speciesCtrl.text.trim();
              final price = double.tryParse(priceCtrl.text);
              if (species.isEmpty || price == null || price < 0) return;
              await repo.upsertPrice(farmId: farmId, species: species, guestType: guestType, price: price);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showAddHornBandDialog(BuildContext context, HuntingRepository repo, List<Farm> farms, String? initialFarmId) async {
  if (farms.isEmpty) return;
  var farmId = initialFarmId ?? farms.first.id;
  var guestType = kGuestTypes.first;
  final speciesCtrl = TextEditingController();
  final minCtrl = TextEditingController();
  final maxCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Add horn-length band'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: farmId,
                decoration: const InputDecoration(labelText: 'Farm'),
                items: farms.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
                onChanged: (v) => setLocal(() => farmId = v!),
              ),
              const SizedBox(height: 10),
              TextField(controller: speciesCtrl, decoration: const InputDecoration(labelText: 'Species')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: guestType,
                decoration: const InputDecoration(labelText: 'Guest type'),
                items: kGuestTypes.map((g) => DropdownMenuItem(value: g, child: Text(guestTypeLabel(g)))).toList(),
                onChanged: (v) => setLocal(() => guestType = v!),
              ),
              const SizedBox(height: 10),
              TextField(controller: minCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Min horn length (inches)')),
              const SizedBox(height: 10),
              TextField(
                controller: maxCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max horn length (inches, blank = no limit)'),
              ),
              const SizedBox(height: 10),
              TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price (R)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final species = speciesCtrl.text.trim();
              final minInches = double.tryParse(minCtrl.text);
              final maxInches = maxCtrl.text.trim().isEmpty ? null : double.tryParse(maxCtrl.text);
              final price = double.tryParse(priceCtrl.text);
              if (species.isEmpty || minInches == null || price == null || price < 0) return;
              await repo.addHornBand(farmId: farmId, species: species, guestType: guestType, minInches: minInches, maxInches: maxInches, price: price);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
