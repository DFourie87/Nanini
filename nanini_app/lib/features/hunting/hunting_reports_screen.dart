import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import 'hunting_models.dart';
import 'hunting_repository.dart';

/// Off-take record: how many of each species were taken per farm per year,
/// with horn length for males -- the quota/record-book view, distinct from
/// the Invoices tab's per-hunter billing view of the same underlying data.
class HuntingReportsScreen extends StatefulWidget {
  const HuntingReportsScreen({super.key, required this.repo});
  final HuntingRepository repo;
  @override
  State<HuntingReportsScreen> createState() => _HuntingReportsScreenState();
}

class _HuntingReportsScreenState extends State<HuntingReportsScreen> {
  List<Farm> farms = [];
  String? selectedFarmId;
  int selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    fetchHuntingFarms().then((f) {
      if (!mounted) return;
      setState(() {
        farms = f;
        selectedFarmId = f.isNotEmpty ? f.first.id : null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HuntingInvoice>>(
      stream: widget.repo.watchInvoices(),
      builder: (context, invoiceSnap) {
        return StreamBuilder<List<HuntingAnimalLine>>(
          stream: widget.repo.watchAnimalLines(),
          builder: (context, animalSnap) {
            final invoices = invoiceSnap.data ?? [];
            final animals = animalSnap.data ?? [];
            final invoiceById = {for (final i in invoices) i.id: i};

            final years = <int>{DateTime.now().year};
            for (final a in animals) {
              final d = parseDateStr(a.huntDate);
              if (d != null) years.add(d.year);
            }
            final yearList = years.toList()..sort((a, b) => b.compareTo(a));

            final filtered = animals.where((a) {
              final invoice = invoiceById[a.invoiceId];
              if (invoice == null || invoice.farmId != selectedFarmId) return false;
              final d = parseDateStr(a.huntDate);
              return d != null && d.year == selectedYear;
            }).toList();

            final bySpecies = <String, List<HuntingAnimalLine>>{};
            for (final a in filtered) {
              bySpecies.putIfAbsent(a.species, () => []).add(a);
            }
            final speciesNames = bySpecies.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

            return Column(
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text('Year: ', style: Theme.of(context).textTheme.titleSmall),
                      DropdownButton<int>(
                        value: selectedYear,
                        items: yearList.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
                        onChanged: (y) => setState(() => selectedYear = y!),
                      ),
                      const Spacer(),
                      Text('${filtered.length} animal${filtered.length == 1 ? '' : 's'}', style: const TextStyle(color: NaniniColors.muted)),
                    ],
                  ),
                ),
                Expanded(
                  child: speciesNames.isEmpty
                      ? const Center(child: Text('No animals recorded for this farm/year.'))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                          children: [
                            for (final species in speciesNames)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: Text(species, style: Theme.of(context).textTheme.titleMedium)),
                                          Text(
                                            '${bySpecies[species]!.length}',
                                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: NaniniColors.rustDark),
                                          ),
                                        ],
                                      ),
                                      const Divider(),
                                      for (final a in bySpecies[species]!..sort((a, b) => a.huntDate.compareTo(b.huntDate)))
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 3),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${invoiceById[a.invoiceId]?.hunterName ?? 'Unknown'} · ${fmtDateDisplay(a.huntDate)}',
                                                ),
                                              ),
                                              if (a.sex != null)
                                                Text(a.sex == 'male' ? 'Male' : 'Female', style: const TextStyle(color: NaniniColors.muted)),
                                              if (a.hornInches != null)
                                                Padding(
                                                  padding: const EdgeInsets.only(left: 8),
                                                  child: Text(
                                                    '${a.hornInches!.toStringAsFixed(1)}in',
                                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
