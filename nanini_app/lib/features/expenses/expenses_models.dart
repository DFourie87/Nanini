import '../suppliers/suppliers_models.dart';

/// One contra (expense) account's purchases over a period: the totals, per
/// month and per supplier.
class ExpenseTotals {
  ExpenseTotals(this.account, List<PurchaseLine> lines, String from, String to)
      : lines = [...lines]..sort((a, b) => b.doc.date.compareTo(a.doc.date)) {
    for (final m in monthsBetween(from, to)) {
      byMonth[m] = 0;
    }
    for (final l in this.lines) {
      excl += l.excl;
      vat += l.vat ?? 0;
      final m = l.doc.date.substring(0, 7);
      byMonth[m] = (byMonth[m] ?? 0) + l.excl;
      final s = bySupplier[l.supplier.name] ?? (0.0, 0);
      bySupplier[l.supplier.name] = (s.$1 + l.excl, s.$2 + 1);
    }
    excl = _r(excl);
    vat = _r(vat);
  }

  /// The account code; null: not allocated yet.
  final String? account;

  /// Newest first.
  final List<PurchaseLine> lines;
  double excl = 0;
  double vat = 0;
  double get incl => _r(excl + vat);

  /// yyyy-MM -> excl., every month of the period (0 when nothing was bought).
  final Map<String, double> byMonth = {};

  /// Supplier -> (excl., lines).
  final Map<String, (double, int)> bySupplier = {};

  /// Suppliers, most spent first.
  List<String> get suppliers => bySupplier.keys.toList()..sort((a, b) => bySupplier[b]!.$1.compareTo(bySupplier[a]!.$1));

  /// The average a month (excl.) over the months of the period.
  double get perMonth => byMonth.isEmpty ? 0 : _r(excl / byMonth.length);

  /// The lines' accounts, each with its totals, most spent first (Unallocated last).
  static List<ExpenseTotals> byAccount(List<PurchaseLine> lines, String from, String to) {
    final grouped = <String?, List<PurchaseLine>>{};
    for (final l in lines) {
      (grouped[l.account] ??= []).add(l);
    }
    return [for (final e in grouped.entries) ExpenseTotals(e.key, e.value, from, to)]
      ..sort((a, b) => a.account == null ? 1 : b.account == null ? -1 : b.excl.compareTo(a.excl));
  }
}

/// The months (yyyy-MM) from [from] to [to] (yyyy-MM-dd), both included.
List<String> monthsBetween(String from, String to) {
  var y = int.parse(from.substring(0, 4)), m = int.parse(from.substring(5, 7));
  final end = to.substring(0, 7);
  final out = <String>[];
  while (true) {
    final k = '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}';
    if (k.compareTo(end) > 0 || out.length > 240) break;
    out.add(k);
    if (++m > 12) {
      m = 1;
      y++;
    }
  }
  return out;
}

/// The same day a year earlier (yyyy-MM-dd; 29 Feb -> 28 Feb).
String yearEarlier(String date) {
  final d = DateTime.parse(date);
  final day = d.month == 2 && d.day == 29 ? 28 : d.day;
  final e = DateTime(d.year - 1, d.month, day);
  return '${e.year.toString().padLeft(4, '0')}-${e.month.toString().padLeft(2, '0')}-${e.day.toString().padLeft(2, '0')}';
}

double _r(double v) => (v * 100).roundToDouble() / 100;
