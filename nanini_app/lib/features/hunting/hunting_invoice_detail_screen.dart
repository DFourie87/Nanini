import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import '../employees/employees_models.dart';
import 'hunting_document_preview.dart';
import 'hunting_models.dart';
import 'hunting_repository.dart';

class HuntingInvoiceDetailScreen extends StatelessWidget {
  const HuntingInvoiceDetailScreen({super.key, required this.repo, required this.invoice, required this.farm});
  final HuntingRepository repo;
  final HuntingInvoice invoice;
  final Farm farm;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NaniniAppBar(title: invoice.hunterName),
      body: StreamBuilder<List<HuntingAnimalLine>>(
        stream: repo.watchAnimalLines(),
        builder: (context, animalSnap) {
          return StreamBuilder<List<HuntingAccommodationLine>>(
            stream: repo.watchAccommodationLines(),
            builder: (context, accSnap) {
              final animals = (animalSnap.data ?? []).where((a) => a.invoiceId == invoice.id).toList()
                ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
              final accommodation = (accSnap.data ?? []).where((a) => a.invoiceId == invoice.id).toList()
                ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
              final total = animals.fold<double>(0, (s, a) => s + a.price) + accommodation.fold<double>(0, (s, a) => s + a.total);
              final isEft = invoice.paymentMethod == HuntingPaymentMethod.eft;

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(farm.name, style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            '${guestTypeLabel(invoice.guestType)} · ${fmtDateDisplay(invoice.visitDate)} · ${isEft ? 'EFT' : 'Cash'}',
                            style: const TextStyle(color: NaniniColors.muted),
                          ),
                          if ((invoice.idOrPassport ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('ID/Passport: ${invoice.idOrPassport}', style: const TextStyle(color: NaniniColors.muted)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Text('Animals', style: Theme.of(context).textTheme.titleMedium)),
                      TextButton.icon(
                        onPressed: () => _showAddAnimalDialog(context),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add animal'),
                      ),
                    ],
                  ),
                  if (animals.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No animals added yet.')),
                  for (final a in animals)
                    Card(
                      child: ListTile(
                        title: Text(a.species),
                        subtitle: Text(
                          [
                            fmtDateDisplay(a.huntDate),
                            if (a.sex != null) a.sex == 'male' ? 'Male' : 'Female',
                            if (a.hornInches != null) '${a.hornInches!.toStringAsFixed(1)}in',
                          ].join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(fmtR(a.price), style: const TextStyle(fontWeight: FontWeight.w700)),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () async {
                                final ok = await confirmDialog(context, message: 'Remove this animal?', danger: true);
                                if (ok) await repo.deleteAnimalLine(a.id);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Text('Accommodation', style: Theme.of(context).textTheme.titleMedium)),
                      TextButton.icon(
                        onPressed: () => _showAddAccommodationDialog(context),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add nights'),
                      ),
                    ],
                  ),
                  if (accommodation.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No accommodation added yet.')),
                  for (final a in accommodation)
                    Card(
                      child: ListTile(
                        title: Text('${a.personType == 'hunter' ? 'Hunter' : 'Non-hunter'} · ${a.nights.toStringAsFixed(0)} night${a.nights == 1 ? '' : 's'}'),
                        subtitle: Text('From ${fmtDateDisplay(a.fromDate)} · ${fmtR(a.ratePerNight)}/night'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(fmtR(a.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () async {
                                final ok = await confirmDialog(context, message: 'Remove this accommodation charge?', danger: true);
                                if (ok) await repo.deleteAccommodationLine(a.id);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Card(
                    color: NaniniColors.paper,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(isEft ? 'Total due' : 'Total owed', style: Theme.of(context).textTheme.titleMedium),
                          Text(fmtR(total), style: Theme.of(context).textTheme.titleLarge?.copyWith(color: NaniniColors.rustDark)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: (animals.isEmpty && accommodation.isEmpty)
                        ? null
                        : () => showHuntingInvoicePreview(context, invoice, farm, animals, accommodation),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(isEft ? 'Generate invoice' : 'Generate breakdown'),
                  ),
                  if (invoice.guestType == 'local') ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: animals.isEmpty ? null : () => showTransportPermitPreview(context, invoice, farm, animals, repo),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Generate transport permit'),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showAddAnimalDialog(BuildContext context) async {
    final priceCtrl = TextEditingController();
    final hornCtrl = TextEditingController();
    var huntDate = todayStr();
    var sex = 'female';

    final prices = await repo.watchPriceList().first;
    final bands = await repo.watchHornBands().first;
    final matching = prices.where((p) => p.farmId == farm.id && p.guestType == invoice.guestType).toList();
    final matchingBands = bands.where((b) => b.farmId == farm.id && b.guestType == invoice.guestType).toList();
    final speciesNames = {for (final p in matching) p.species, for (final b in matchingBands) b.species}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    String? selectedSpeciesName;

    if (!context.mounted) return;
    if (speciesNames.isEmpty) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No prices set'),
          content: Text('Add a price for ${farm.name} (${guestTypeLabel(invoice.guestType)}) in the Price Lists tab first.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void autoFillMalePrice() {
            if (sex != 'male' || selectedSpeciesName == null) return;
            final inches = double.tryParse(hornCtrl.text);
            if (inches == null) return;
            final matchedBands = matchingBands.where((b) => b.species == selectedSpeciesName && b.matches(inches)).toList();
            if (matchedBands.isNotEmpty) setLocal(() => priceCtrl.text = matchedBands.first.price.toStringAsFixed(0));
          }

          return AlertDialog(
            title: const Text('Add animal'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedSpeciesName,
                    decoration: const InputDecoration(labelText: 'Species'),
                    items: speciesNames.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) {
                      setLocal(() {
                        selectedSpeciesName = v;
                        final flatMatches = matching.where((p) => p.species == v).toList();
                        if (flatMatches.isNotEmpty) priceCtrl.text = flatMatches.first.price.toStringAsFixed(0);
                      });
                      autoFillMalePrice();
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: sex,
                    decoration: const InputDecoration(labelText: 'Sex'),
                    items: const [
                      DropdownMenuItem(value: 'female', child: Text('Female')),
                      DropdownMenuItem(value: 'male', child: Text('Male')),
                    ],
                    onChanged: (v) {
                      setLocal(() => sex = v!);
                      autoFillMalePrice();
                    },
                  ),
                  if (sex == 'male') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: hornCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Horn length (inches)'),
                      onChanged: (_) => autoFillMalePrice(),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price (R)')),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Date hunted: ${fmtDateDisplay(huntDate)}'),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: parseDateStr(huntDate) ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setLocal(() => huntDate = toDateStr(picked));
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final species = selectedSpeciesName;
                  final price = double.tryParse(priceCtrl.text);
                  if (species == null || price == null || price < 0) return;
                  final hornInches = sex == 'male' ? double.tryParse(hornCtrl.text) : null;
                  await repo.addAnimalLine(
                    invoiceId: invoice.id,
                    species: species,
                    sex: sex,
                    hornInches: hornInches,
                    price: price,
                    huntDate: huntDate,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddAccommodationDialog(BuildContext context) async {
    final nightsCtrl = TextEditingController(text: '1');
    final rates = await repo.watchAccommodationRates().first;
    final matchingRates = rates.where((r) => r.farmId == farm.id).toList();
    final rate = matchingRates.isEmpty ? null : matchingRates.first;
    var personType = 'hunter';
    final rateCtrl = TextEditingController(text: rate?.hunterRate.toStringAsFixed(0) ?? '');
    var fromDate = todayStr();

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add accommodation'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: personType,
                  decoration: const InputDecoration(labelText: 'For'),
                  items: const [
                    DropdownMenuItem(value: 'hunter', child: Text('Hunter')),
                    DropdownMenuItem(value: 'non_hunter', child: Text('Non-hunter (companion)')),
                  ],
                  onChanged: (v) {
                    setLocal(() {
                      personType = v!;
                      if (rate != null) rateCtrl.text = (v == 'hunter' ? rate.hunterRate : rate.nonHunterRate).toStringAsFixed(0);
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextField(controller: nightsCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nights')),
                const SizedBox(height: 10),
                TextField(controller: rateCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rate per night (R)')),
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
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final nights = double.tryParse(nightsCtrl.text);
                final rateValue = double.tryParse(rateCtrl.text);
                if (nights == null || nights <= 0 || rateValue == null || rateValue < 0) return;
                await repo.addAccommodationLine(
                  invoiceId: invoice.id,
                  personType: personType,
                  nights: nights,
                  ratePerNight: rateValue,
                  fromDate: fromDate,
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
