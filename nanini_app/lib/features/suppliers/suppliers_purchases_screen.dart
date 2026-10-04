import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/formatters.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import 'suppliers_data.dart';
import 'suppliers_models.dart';
import 'suppliers_period.dart';
import 'suppliers_recon_screen.dart';
import '../../core/run_once.dart';

/// The purchases for a period: supplier, invoice, what was bought, the
/// contra (GL) account, excl., VAT and incl. -- with totals per account.
/// Tap a line to put it against another account.
class SuppliersPurchasesScreen extends StatefulWidget {
  const SuppliersPurchasesScreen({super.key, required this.data, required this.period, required this.onPeriod});
  final SuppliersData data;
  final SupplierPeriod period;
  final ValueChanged<SupplierPeriod> onPeriod;

  @override
  State<SuppliersPurchasesScreen> createState() => _SuppliersPurchasesScreenState();
}

class _SuppliersPurchasesScreenState extends State<SuppliersPurchasesScreen> {
  String? supplierId; // null: all

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (!data.loaded) return const Center(child: CircularProgressIndicator());
    final accounts = data.accounts..sort((a, b) => a.supplier.name.toLowerCase().compareTo(b.supplier.name.toLowerCase()));
    final lines = purchasesFor(accounts.where((a) => supplierId == null || a.supplier.id == supplierId).toList(), data.docLines, data.glRules,
        widget.period.from, widget.period.to,
        chart: data.glAccounts);
    final byAccount = <String?, (double, double, double)>{};
    for (final l in lines) {
      final t = byAccount[l.account] ?? (0.0, 0.0, 0.0);
      byAccount[l.account] = (t.$1 + l.excl, t.$2 + (l.vat ?? 0), t.$3 + l.incl);
    }
    final keys = byAccount.keys.toList()..sort((a, b) => (a ?? '~').compareTo(b ?? '~'));
    final noVat = lines.where((l) => l.vat == null).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        PeriodBar(period: widget.period, onChanged: widget.onPeriod),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: supplierId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Supplier'),
          items: [
            const DropdownMenuItem(value: null, child: Text('All suppliers')),
            for (final a in accounts) DropdownMenuItem(value: a.supplier.id, child: Text(a.supplier.name)),
          ],
          onChanged: (v) => setState(() => supplierId = v),
        ),
        if (data.purchasesMissing)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('Run docs/sql/suppliers_purchases.sql in Supabase to keep invoice lines and contra accounts.',
                  style: TextStyle(color: NaniniColors.red)),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text('By contra account', style: Theme.of(context).textTheme.titleMedium)),
            IconButton(tooltip: 'Share as CSV', icon: const Icon(Icons.ios_share), onPressed: lines.isEmpty ? null : () => runOnce('suppliers_purchases_screen.1', () => _share(lines))),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _amountsRow('Account', 'Excl.', 'VAT', 'Incl.', bold: true),
                const Divider(height: 12),
                for (final k in keys)
                  _amountsRow(data.accountLabel(k), fmtRCents(byAccount[k]!.$1), fmtRCents(byAccount[k]!.$2), fmtRCents(byAccount[k]!.$3),
                      color: k == null ? NaniniColors.amber : null),
                const Divider(height: 12),
                _amountsRow(
                  'Total',
                  fmtRCents(lines.fold<double>(0, (s, l) => s + l.excl)),
                  fmtRCents(lines.fold<double>(0, (s, l) => s + (l.vat ?? 0))),
                  fmtRCents(lines.fold<double>(0, (s, l) => s + l.incl)),
                  bold: true,
                ),
              ],
            ),
          ),
        ),
        if (noVat > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('$noVat line(s) without VAT read from the PDF -- counted at their full amount.',
                style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
          ),
        const SizedBox(height: 12),
        Text('Lines', style: Theme.of(context).textTheme.titleMedium),
        const Text('Tap a line to put it against another contra account.', style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
        const SizedBox(height: 4),
        if (lines.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No purchases in this period.', style: TextStyle(color: NaniniColors.muted)),
          ),
        for (final l in lines) _PurchaseTile(line: l, data: data, all: lines),
      ],
    );
  }

  /// The account (code and name) on its own line, its amounts below on one
  /// line -- each shrunk to fit rather than wrapped.
  Widget _amountsRow(String label, String excl, String vat, String incl, {bool bold = false, Color? color}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : null, color: color, fontSize: 12);
    Widget amount(String t) => Expanded(
        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(t, style: style, maxLines: 1, softWrap: false)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: style),
          Row(children: [amount(excl), const SizedBox(width: 8), amount(vat), const SizedBox(width: 8), amount(incl)]),
        ],
      ),
    );
  }

  Future<void> _share(List<PurchaseLine> lines) async {
    String n(double v) => v.toStringAsFixed(2);
    final rows = <List<Object?>>[
      ['Supplier', 'Date', 'Invoice', 'Description', 'Contra account', 'Excl', 'VAT', 'Incl'],
      for (final l in lines)
        [
          l.supplier.name,
          l.doc.date,
          l.doc.reference ?? '',
          l.description ?? '',
          widget.data.accountLabel(l.account),
          n(l.excl),
          l.vat == null ? '' : n(l.vat!),
          n(l.incl),
        ],
    ];
    await Share.share(const ListToCsvConverter().convert(rows), subject: 'purchases ${widget.period.from} to ${widget.period.to}.csv');
  }
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({required this.line, required this.data, required this.all});
  final PurchaseLine line;
  final SuppliersData data;
  final List<PurchaseLine> all;

  @override
  Widget build(BuildContext context) {
    final l = line;
    final what = l.doc.kind == SupplierDocKind.creditNote ? 'Credit note' : l.fromStatement || l.doc.kind == SupplierDocKind.statement ? 'Statement' : 'Invoice';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => runOnce('suppliers_purchases_screen.2', () => allocatePurchase(context, data, l, all.where((x) => x.doc.id == l.doc.id).toList())),
        onLongPress: l.doc.filePath == null ? null : () => openSupplierPdf(context, data, l.doc),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l.description ?? '${l.supplier.name} $what', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Text(fmtRCents(l.incl), maxLines: 1, softWrap: false, style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              Text('${l.supplier.name} · $what${(l.doc.reference ?? '').isEmpty ? '' : ' ${l.doc.reference}'} · ${fmtDateDisplay(l.doc.date)}',
                  style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${data.accountLabel(l.account)}${l.source == GlSource.remembered ? ' (remembered)' : l.source == GlSource.supplier ? ' (supplier)' : ''}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: l.account == null ? NaniniColors.amber : NaniniColors.rustDark),
                    ),
                  ),
                  Text('excl ${fmtRCents(l.excl)} · VAT ${l.vat == null ? '?' : fmtRCents(l.vat!)}',
                      maxLines: 1, softWrap: false, style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Puts a purchase line (or all lines of its invoice) against a contra
/// account, remembered for the item next time.
Future<void> allocatePurchase(BuildContext context, SuppliersData data, PurchaseLine line, List<PurchaseLine> sameDoc) async {
  String? code = line.account;
  var wholeDoc = false;
  var remember = true;
  var search = '';
  String? error;
  var saving = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final shown = data.glAccounts.where((g) => search.isEmpty || g.label.toLowerCase().contains(search.toLowerCase())).toList();
        return AlertDialog(
          title: dialogTitleWithError('Contra account', error),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${line.description ?? line.supplier.name} -- ${fmtRCents(line.incl)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(labelText: 'Find an account', prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setLocal(() => search = v),
                ),
                SizedBox(
                  height: 220,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final g in shown)
                        ListTile(
                          dense: true,
                          title: Text(g.label),
                          leading: Icon(g.code == code ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: g.code == code ? NaniniColors.rust : NaniniColors.muted),
                          onTap: () => setLocal(() => code = g.code),
                        ),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.add),
                        title: const Text('New account'),
                        onTap: () => runOnce('suppliers_purchases_screen.3', () async {
                          final added = await _newAccount(ctx, data);
                          if (added != null) setLocal(() => code = added);
                        }),
                      ),
                    ],
                  ),
                ),
                if (sameDoc.length > 1)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: wholeDoc,
                    onChanged: (v) => setLocal(() => wholeDoc = v ?? false),
                    title: Text('All ${sameDoc.length} lines of this invoice'),
                  ),
                if (!line.fromStatement)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: remember,
                    onChanged: (v) => setLocal(() => remember = v ?? true),
                    title: const Text('Remember for this item'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: saving || code == null
                  ? null
                  : () async {
                      setLocal(() => saving = true);
                      try {
                        await data.repo.allocate(wholeDoc ? sameDoc : [line], code!, remember: remember);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setLocal(() {
                          saving = false;
                          error = friendlyDbError(e);
                        });
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Save'),
            ),
          ],
        );
      },
    ),
  );
}

Future<String?> _newAccount(BuildContext context, SuppliersData data) async {
  final codeCtl = TextEditingController();
  final nameCtl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New contra account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: codeCtl, decoration: const InputDecoration(labelText: 'Account number, e.g. 3650')),
          const SizedBox(height: 8),
          TextField(controller: nameCtl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name, e.g. Electricity & Water')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => runOnce('suppliers_purchases_screen.4', () async {
            if (codeCtl.text.trim().isEmpty || nameCtl.text.trim().isEmpty) return;
            try {
              await data.repo.addGlAccount(codeCtl.text, nameCtl.text);
              if (ctx.mounted) Navigator.pop(ctx, codeCtl.text.trim());
            } catch (e) {
              if (ctx.mounted) showToast(ctx, friendlyDbError(e), isError: true);
            }
          }),
          child: const Text('Add'),
        ),
      ],
    ),
  );
}
