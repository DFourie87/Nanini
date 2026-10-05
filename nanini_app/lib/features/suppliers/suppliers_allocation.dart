import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../theme/nanini_theme.dart';
import 'suppliers_data.dart';
import 'suppliers_models.dart';

/// A line of an invoice or credit note being confirmed, with the contra
/// account it goes to (amounts as positive; a credit note's are saved negative).
class AllocRow {
  AllocRow({this.lineId, this.description, required this.excl, this.vat, this.account, this.read = false});

  /// The line read from the PDF, when it is one.
  final String? lineId;
  final String? description;
  final double excl;
  final double? vat;
  String? account;

  /// Read from the PDF (remembered for its item when confirmed), not made up here.
  final bool read;
  double get incl => _r(excl + (vat ?? 0));
}

double _r(double v) => (v * 100).roundToDouble() / 100;

/// The lines of [d] to allocate, each with its account to start with: the
/// lines read from the PDF when they add up to [amount], else the document
/// as one line -- split into the part with VAT and the zero-rated rest for a
/// supplier whose lines with VAT go elsewhere (Kalkor: transport).
List<AllocRow> allocationFor(SuppliersData data, Supplier s, SupplierDoc d, double amount, double? vat) {
  final gl = GlAllocator(data.glRules, data.glAccounts);
  final read = data.docLines.where((l) => l.docId == d.id).toList()..sort((a, b) => a.lineNo.compareTo(b.lineNo));
  final readTotal = read.fold<double>(0, (t, l) => t + l.excl + (l.vat ?? 0)).abs();
  if (read.isNotEmpty && (readTotal - amount.abs()).abs() < 0.01) {
    return [
      for (final l in read)
        AllocRow(
          lineId: l.id,
          description: l.description,
          excl: l.excl.abs(),
          vat: l.vat?.abs(),
          account: gl.accountFor(s, l.glAccount, l.description, l.vat).$1,
          read: true,
        ),
    ];
  }
  final v = vat ?? 0;
  final rest = _r(amount - v - v / 0.15);
  if (contraAccount(s.vatAccount, gl.chart) != null && v > 0 && rest > 0.01) {
    return [
      AllocRow(description: 'Part with VAT', excl: _r(v / 0.15), vat: v, account: gl.accountFor(s, null, null, v).$1),
      AllocRow(description: 'Zero-rated part', excl: rest, vat: 0, account: gl.accountFor(s, null, null, 0).$1),
    ];
  }
  return [AllocRow(description: d.description, excl: _r(amount - v), vat: vat, account: gl.accountFor(s, null, d.description, vat).$1)];
}

/// Every line has its account (nothing to choose when there's no chart of accounts).
bool allAllocated(SuppliersData data, List<AllocRow> rows) => data.glAccounts.isEmpty || rows.every((r) => r.account != null);

/// The lines saved against their accounts, and the items read from the PDF
/// remembered for next time.
Future<void> saveAllocation(SuppliersData data, String supplierId, SupplierDoc d, SupplierDocKind kind, List<AllocRow> rows) async {
  if (data.glAccounts.isEmpty || kind == SupplierDocKind.statement) return;
  final sign = kind == SupplierDocKind.creditNote ? -1 : 1;
  if (rows.every((r) => r.lineId != null)) {
    for (final r in rows) {
      await data.repo.setLineAccount(r.lineId!, r.account!);
    }
  } else {
    await data.repo.replaceLines(d.id, [
      for (final r in rows) (description: r.description, excl: sign * r.excl, vat: sign * (r.vat ?? 0), glAccount: r.account!),
    ]);
  }
  for (final r in rows.where((r) => r.read)) {
    await data.repo.rememberItem(supplierId, r.description, r.account!);
  }
}

/// The lines to allocate, each with a dropdown of the chart of accounts.
class AllocationLines extends StatelessWidget {
  const AllocationLines({super.key, required this.data, required this.rows, required this.onChanged});
  final SuppliersData data;
  final List<AllocRow> rows;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (data.glAccounts.isEmpty) return const SizedBox.shrink();
    final chart = [...data.glAccounts]..sort((a, b) => a.code.compareTo(b.code));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Each line to a contra account', style: Theme.of(context).textTheme.titleSmall),
        Text(rows.any((r) => r.read) ? 'The lines read from the PDF.' : 'The document as one line (its lines weren\'t read).',
            style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
        for (final (i, r) in rows.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(r.description ?? 'Line ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text(fmtRCents(r.incl)),
                  ],
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('alloc-$i-${r.lineId}'),
                  initialValue: chart.any((g) => g.code == r.account) ? r.account : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Contra account',
                    errorText: r.account == null ? 'Choose its contra account' : null,
                  ),
                  items: [for (final g in chart) DropdownMenuItem(value: g.code, child: Text(g.label, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) {
                    r.account = v;
                    onChanged();
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}
