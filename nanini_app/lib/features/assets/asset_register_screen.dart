import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/run_once.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/date_pick.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../suppliers/suppliers_models.dart';
import 'asset_models.dart';
import 'asset_repository.dart';
import 'asset_xlsx.dart';

/// Hub > Financials > Asset register: the assets by group for a financial
/// year with their depreciation (kept up to date by the month), assets
/// bought (supplier invoices on a fixed asset account) to add, the register
/// as Excel and the depreciation journals for Xero.
class AssetRegisterScreen extends StatefulWidget {
  const AssetRegisterScreen({super.key, this.repo, this.save, this.today});

  final AssetRepository? repo;

  /// Tests: saves a file instead of the save dialog. True when saved.
  final Future<bool> Function(String name, Uint8List bytes)? save;
  final DateTime? today;

  @override
  State<AssetRegisterScreen> createState() => _AssetRegisterScreenState();
}

class _AssetRegisterScreenState extends State<AssetRegisterScreen> {
  late final AssetRepository repo = widget.repo ?? AssetRepository();
  List<Asset>? assets;
  List<DepOverride> overrides = const [];
  Set<String> journaled = const {};
  List<PurchaseLine> purchases = const [];
  String? problem;
  late final DateTime today = widget.today ?? DateTime.now();
  late String yearStart = assetYearStart(toDateStr(today));

  String get yearEnd => toDateStr(DateTime(DateTime.parse(yearStart).year + 1, 3, 0));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await repo.fetchAssets();
      final o = await repo.fetchOverrides();
      final j = await repo.fetchJournaled();
      var p = const <PurchaseLine>[];
      try {
        p = await repo.fetchAssetPurchases(yearStart, yearEnd);
      } catch (_) {
        // The suppliers can't be read: no purchases to add.
      }
      if (!mounted) return;
      setState(() {
        assets = a;
        overrides = o;
        journaled = j;
        purchases = p;
        problem = null;
      });
    } catch (e) {
      if (mounted) setState(() => problem = friendlyDbError(e));
    }
  }

  List<AssetYearLine> get lines => assetYear(yearStart, assets ?? const [], overrides);

  List<String> get years {
    final out = <String>{assetYearStart(toDateStr(today))};
    for (final a in assets ?? const <Asset>[]) {
      final from = a.openingYear ?? (a.purchaseDate == null ? null : assetYearStart(a.purchaseDate!));
      if (from != null) out.add(from);
    }
    final first = out.reduce((a, b) => a.compareTo(b) < 0 ? a : b);
    final all = <String>[];
    for (var y = DateTime.parse(first); !y.isAfter(DateTime.parse(assetYearStart(toDateStr(today)))); y = DateTime(y.year + 1, 3, 1)) {
      all.add(toDateStr(y));
    }
    return all.reversed.toList();
  }

  /// Purchases on a fixed asset account not in the register yet.
  List<PurchaseLine> get toAdd {
    final taken = {
      for (final a in assets ?? const <Asset>[])
        if (a.sourceKey != null) a.sourceKey!,
    };
    return [
      for (final p in purchases)
        if (!taken.contains(purchaseKey(p)) && p.excl > 0) p,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      appBar: const NaniniAppBar(title: 'Asset register'),
      body: problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$problem\n\n(Run nanini_app/docs/sql/assets.sql once?)', textAlign: TextAlign.center),
              ),
            )
          : assets == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _body(text)),
    );
  }

  Widget _body(TextTheme text) {
    final ls = lines;
    final due = journalsDue(yearStart, today, assets!, overrides, journaled);
    final add = toAdd;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        DropdownButton<String>(
          key: const Key('asset_year'),
          value: yearStart,
          items: [
            for (final s in years)
              DropdownMenuItem(
                value: s,
                child: Text(
                  'Year ${DateTime.parse(s).year + 1} (${fmtDateDisplay(s)} to ${fmtDateDisplay(toDateStr(DateTime(DateTime.parse(s).year + 1, 3, 0)))})',
                ),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => yearStart = v);
            _load();
          },
        ),
        const SizedBox(height: 8),
        _summary(ls, text),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(key: const Key('asset_add'), onPressed: () => _edit(null), icon: const Icon(Icons.add), label: const Text('Add asset')),
            OutlinedButton.icon(
              key: const Key('asset_journal'),
              onPressed: due.isEmpty ? null : () => runOnce('asset_journal', () => _journals(due)),
              icon: const Icon(Icons.upload_file),
              label: Text(due.isEmpty ? 'Depreciation in Xero: up to date' : 'Depreciation journal for Xero (${due.length})'),
            ),
            OutlinedButton.icon(
              key: const Key('asset_excel'),
              onPressed: ls.isEmpty ? null : () => runOnce('asset_excel', () => _saveExcel(ls)),
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Register (Excel)'),
            ),
          ],
        ),
        if (add.isNotEmpty) ...[const SizedBox(height: 12), _bought(add, text)],
        const SizedBox(height: 12),
        if (ls.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No assets in this year yet. Bring in the register (the SQL from Claude), or add them.', style: TextStyle(color: NaniniColors.muted)),
          ),
        for (final c in AssetCategory.values)
          ..._group(c, [
            for (final l in ls)
              if (l.asset.category == c) l,
          ], text),
      ],
    );
  }

  Widget _row(String label, double value, {bool bold = false, Color? color}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(fmtRCents(value), style: style),
        ],
      ),
    );
  }

  Widget _summary(List<AssetYearLine> ls, TextTheme text) {
    double sum(double Function(AssetYearLine) f) => ls.fold(0.0, (s, l) => s + f(l));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Year to ${fmtDateDisplay(yearEnd)}', style: text.titleSmall),
            const SizedBox(height: 6),
            _row('Cost at the start', sum((l) => l.costStart)),
            _row('Bought', sum((l) => l.bought)),
            _row('Sold', -sum((l) => l.sold)),
            _row('Cost at the end', sum((l) => l.costEnd), bold: true),
            _row('Depreciation for the year ($kDepreciationAccount)', sum((l) => l.depreciation)),
            _row('Accumulated depreciation at the end', -sum((l) => l.accumEnd)),
            const Divider(),
            _row('Book value at the end', sum((l) => l.bookEnd), bold: true),
          ],
        ),
      ),
    );
  }

  Widget _bought(List<PurchaseLine> add, TextTheme text) => Card(
    key: const Key('asset_bought'),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bought, not in the register yet (${add.length})', style: text.titleSmall?.copyWith(color: NaniniColors.red)),
          const Text('Supplier invoices this year on a fixed asset account.', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
          for (final p in add)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${fmtDateDisplay(p.doc.date)}  ${p.supplier.name}: ${p.description ?? p.doc.reference ?? ''} (${p.account})',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(fmtRCents(p.excl)),
                TextButton(
                  key: Key('asset_take_${purchaseKey(p)}'),
                  onPressed: () => _edit(null, from: p),
                  child: const Text('Add'),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  List<Widget> _group(AssetCategory c, List<AssetYearLine> ls, TextTheme text) {
    if (ls.isEmpty) return const [];
    double sum(double Function(AssetYearLine) f) => ls.fold(0.0, (s, l) => s + f(l));
    return [
      Card(
        child: ExpansionTile(
          key: Key('asset_group_${c.code}'),
          title: Text('${c.letter}. ${c.label} (${ls.length})', style: text.titleSmall),
          subtitle: Text(
            'Cost ${fmtR(sum((l) => l.costEnd))} · depreciation ${fmtR(sum((l) => l.depreciation))} · book value ${fmtR(sum((l) => l.bookEnd))}',
            style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
          ),
          children: [
            for (final l in ls)
              ListTile(
                key: Key('asset_${l.asset.id}'),
                dense: true,
                title: Text('${l.asset.number == null ? '' : '${l.asset.number}. '}${l.asset.description}${l.asset.disposedDate == null ? '' : ' (sold)'}'),
                subtitle: Text(
                  '${l.asset.purchaseDate == null ? '' : '${fmtDateDisplay(l.asset.purchaseDate)} · '}cost ${fmtRCents(l.costEnd)} · ${l.asset.rate == 0 ? 'not depreciated' : '${l.asset.rate}%'}'
                  '${l.overridden ? ' (set by hand)' : ''}',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(fmtRCents(l.bookEnd)),
                    if (l.depreciation != 0) Text('dep. ${fmtRCents(l.depreciation)}', style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                  ],
                ),
                onTap: () => _edit(l),
              ),
          ],
        ),
      ),
    ];
  }

  /// Adds an asset (from a purchase, [from]) or changes [line]'s.
  Future<void> _edit(AssetYearLine? line, {PurchaseLine? from}) async {
    final a = line?.asset;
    final cat = ValueNotifier(a?.category ?? AssetCategory.forAccount(from?.account));
    final what = TextEditingController(text: a?.description ?? from?.description ?? '');
    final cost = TextEditingController(text: (a?.cost ?? from?.excl)?.toStringAsFixed(2) ?? '');
    final rate = TextEditingController(text: (a?.rate ?? cat.value.rate).toString());
    final proceeds = TextEditingController(text: a?.disposalProceeds?.toStringAsFixed(2) ?? '');
    final over = TextEditingController(text: line?.overridden == true ? line!.depreciation.toStringAsFixed(2) : '');
    String? bought = a?.purchaseDate ?? from?.doc.date;
    String? sold = a?.disposedDate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<String?> pick(String? current) async {
            final d = await pickDate(ctx, initialDate: current == null ? today : DateTime.parse(current), firstDate: DateTime(2000), lastDate: DateTime(2100));
            return d == null ? current : toDateStr(d);
          }

          return AlertDialog(
            title: Text(a == null ? 'Add an asset' : 'Asset'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (from != null)
                      Text(
                        'From ${from.supplier.name}, ${from.doc.reference ?? ''} (${from.account})',
                        style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
                      ),
                    DropdownButton<AssetCategory>(
                      key: const Key('asset_edit_category'),
                      value: cat.value,
                      isExpanded: true,
                      items: [for (final c in AssetCategory.values) DropdownMenuItem(value: c, child: Text('${c.letter}. ${c.label}'))],
                      onChanged: (v) => setLocal(() {
                        if (v == null) return;
                        cat.value = v;
                        if (a == null) rate.text = v.rate.toString();
                      }),
                    ),
                    TextField(
                      key: const Key('asset_edit_what'),
                      controller: what,
                      decoration: const InputDecoration(labelText: 'Description'),
                    ),
                    TextField(
                      key: const Key('asset_edit_cost'),
                      controller: cost,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Cost (R, excluding VAT)'),
                    ),
                    TextField(
                      key: const Key('asset_edit_rate'),
                      controller: rate,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Depreciation, % a year (0: none)'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('asset_edit_bought'),
                      onPressed: () async {
                        final d = await pick(bought);
                        setLocal(() => bought = d);
                      },
                      icon: const Icon(Icons.event),
                      label: Text('Bought: ${bought == null ? '--' : fmtDateDisplay(bought)}'),
                    ),
                    if (a != null) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const Key('asset_edit_sold'),
                        onPressed: () async {
                          final d = await pick(sold);
                          setLocal(() => sold = d);
                        },
                        icon: const Icon(Icons.sell_outlined),
                        label: Text('Sold: ${sold == null ? 'not sold' : fmtDateDisplay(sold)}'),
                      ),
                      if (sold != null)
                        TextField(
                          key: const Key('asset_edit_proceeds'),
                          controller: proceeds,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Sold for (R, excluding VAT)'),
                        ),
                      TextField(
                        key: const Key('asset_edit_override'),
                        controller: over,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText:
                              'Depreciation for year ${DateTime.parse(yearStart).year + 1} set by hand (empty: worked out, ${fmtRCents(line!.depreciation)})',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              if (a != null && a.openingYear == null)
                TextButton(key: const Key('asset_edit_delete'), onPressed: () => Navigator.pop(ctx, null), child: const Text('Remove')),
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(key: const Key('asset_edit_save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    if (ok == null && a != null) {
      if (await confirmDialog(context, message: 'Remove "${a.description}" from the register?') && mounted) {
        if (await trySave(context, () => repo.delete(a.id))) await _load();
      }
      return;
    }
    if (ok != true) return;
    double? num(TextEditingController c) => double.tryParse(c.text.replaceAll(' ', '').replaceAll(',', ''));
    final c = num(cost);
    if (what.text.trim().isEmpty || c == null) {
      await showProblem(context, 'Give a description and the cost.');
      return;
    }
    final asset = Asset(
      id: a?.id ?? '',
      category: cat.value,
      number: a?.number,
      description: what.text.trim(),
      purchaseDate: bought,
      cost: c,
      rate: num(rate) ?? cat.value.rate,
      depFrom: a?.depFrom,
      openingYear: a?.openingYear,
      openingAccum: a?.openingAccum ?? 0,
      disposedDate: sold,
      disposalProceeds: sold == null ? null : num(proceeds),
      sourceKey: a?.sourceKey ?? (from == null ? null : purchaseKey(from)),
      source: a?.source ?? (from == null ? null : '${from.supplier.name} ${from.doc.reference ?? ''}'.trim()),
      notes: a?.notes,
    );
    final saved = await trySave(context, () async {
      await repo.save(asset, isNew: a == null);
      if (a != null) {
        final o = over.text.trim().isEmpty ? null : num(over);
        if (o != null || line!.overridden) await repo.setOverride(a.id, yearStart, o);
      }
    });
    if (saved) await _load();
  }

  /// The depreciation journals not in Xero yet: saved as a CSV (Manual
  /// journals > Import), or marked as already in Xero.
  Future<void> _journals(List<JournalDue> due) async {
    final total = due.fold(0.0, (s, j) => s + j.byAccount.values.fold(0.0, (t, v) => t + v));
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Depreciation journals for Xero: ${fmtRCents(total)}'),
        content: Text(
          '${due.map((j) => '${j.narration} (${fmtDateDisplay(j.date)}): ${fmtRCents(j.byAccount.values.fold<double>(0, (s, v) => s + v))}').join('\n')}\n\n'
          'Debit $kDepreciationAccount, credit each group\'s accumulated depreciation. Already in Xero? "Already in Xero" marks them without saving.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          OutlinedButton(key: const Key('asset_journal_already'), onPressed: () => Navigator.pop(ctx, 'mark'), child: const Text('Already in Xero')),
          FilledButton(key: const Key('asset_journal_save'), onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save CSV')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'save') {
      final rows = [
        kXeroJournalHeader,
        for (final j in due)
          if (j.byAccount.isNotEmpty) ...depreciationJournalRows(j.narration, j.date, j.byAccount),
      ];
      final bytes = Uint8List.fromList(utf8.encode(const ListToCsvConverter().convert(rows)));
      if (!await _save('Xero depreciation journals to ${fmtDateDisplay(due.last.date)}.csv', bytes, 'csv') || !mounted) return;
    }
    final ok = await trySave(context, () async {
      for (final j in due) {
        await repo.markJournaled(j.months, j.byAccount.values.fold<double>(0, (s, v) => s + v));
      }
    });
    if (!ok || !mounted) return;
    await _load();
    if (mounted) showToast(context, choice == 'save' ? 'Saved: in Xero, Accounting > Manual journals > Import' : 'Marked as in Xero');
  }

  Future<void> _saveExcel(List<AssetYearLine> ls) async {
    final bytes = Uint8List.fromList(assetRegisterXlsx(yearStart, ls, preparedOn: toDateStr(today)));
    final name = 'Asset register year ${DateTime.parse(yearStart).year + 1}.xlsx';
    if (await _save(name, bytes, 'xlsx') && mounted) showToast(context, 'Saved $name');
  }

  Future<bool> _save(String name, Uint8List bytes, String ext) async {
    if (widget.save != null) return widget.save!(name, bytes);
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Save $name', fileName: name, type: FileType.custom, allowedExtensions: [ext], bytes: bytes);
    if (path == null) return false;
    if (!Platform.isAndroid && !Platform.isIOS) await File(path).writeAsBytes(bytes);
    return true;
  }
}
