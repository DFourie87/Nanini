import 'dart:math' as math;

import '../../core/formatters.dart';

/// The register's groups, as in the working papers, each with its accounts
/// in the chart (cost, accumulated depreciation) and its usual rate.
enum AssetCategory {
  land('land', 'A', 'Land and property', '5504/000', null, 0),
  improvements('improvements', 'A', 'Fixed improvements', '5505/100', null, 0),
  vehicles('vehicles', 'B', 'Vehicles', '6100/100', '6100/200', 20),
  implements('implements', 'C', 'Implements and equipment', '5510/100', '5510/200', 20),
  computers('computers', 'D', 'Computer equipment', '5510/100', '5510/200', 20),
  linen('linen', 'E', 'Linen and bedding', '5510/100', '5510/200', 20),
  software('software', 'F', 'Computer software', '5510/100', '5510/200', 20);

  const AssetCategory(this.code, this.letter, this.label, this.costAccount, this.depAccount, this.rate);

  /// assets.category.
  final String code;
  final String letter;
  final String label;
  final String costAccount;

  /// Null: not depreciated (land, fixed improvements).
  final String? depAccount;

  /// Straight line on cost, % a year.
  final double rate;

  static AssetCategory of(String code) => values.firstWhere((c) => c.code == code, orElse: () => implements);

  /// By a purchase's account: 6100 vehicles, 5504 land, 5505 improvements, else implements.
  static AssetCategory forAccount(String? account) {
    final a = account ?? '';
    if (a.startsWith('6100')) return vehicles;
    if (a.startsWith('5504')) return land;
    if (a.startsWith('5505')) return improvements;
    return implements;
  }
}

/// The chart's depreciation account.
const kDepreciationAccount = '3610/000';

double _round(num v) => (v * 100).roundToDouble() / 100;

/// One asset: its cost and when bought; depreciated straight line on cost at
/// [rate] % a year, by the month, from the month of [depFrom] (else the
/// purchase) to the month sold, never below nil. [openingYear]: the
/// financial year (1 March) [openingAccum] (the accumulated depreciation)
/// is at -- the register brought into the hub; null for one bought since.
class Asset {
  Asset({
    required this.id,
    required this.category,
    this.number,
    required this.description,
    this.purchaseDate,
    required this.cost,
    required this.rate,
    this.depFrom,
    this.openingYear,
    this.openingAccum = 0,
    this.disposedDate,
    this.disposalProceeds,
    this.sourceKey,
    this.source,
    this.notes,
  });

  final String id;
  final AssetCategory category;
  final int? number;
  final String description;
  final String? purchaseDate;
  final double cost;
  final double rate;
  final String? depFrom;
  final String? openingYear;
  final double openingAccum;
  final String? disposedDate;
  final double? disposalProceeds;

  /// The purchase it came from (a supplier invoice's line), once only.
  final String? sourceKey;
  final String? source;
  final String? notes;

  factory Asset.fromJson(Map<String, dynamic> j) => Asset(
    id: j['id'] as String,
    category: AssetCategory.of(j['category'] as String),
    number: (j['number'] as num?)?.toInt(),
    description: j['description'] as String,
    purchaseDate: j['purchase_date'] as String?,
    cost: (j['cost'] as num).toDouble(),
    rate: (j['rate'] as num).toDouble(),
    depFrom: j['dep_from'] as String?,
    openingYear: j['opening_year'] as String?,
    openingAccum: (j['opening_accum'] as num?)?.toDouble() ?? 0,
    disposedDate: j['disposed_date'] as String?,
    disposalProceeds: (j['disposal_proceeds'] as num?)?.toDouble(),
    sourceKey: j['source_key'] as String?,
    source: j['source'] as String?,
    notes: j['notes'] as String?,
  );

  Map<String, dynamic> toRow() => {
    'category': category.code,
    'number': number,
    'description': description,
    'purchase_date': purchaseDate,
    'cost': cost,
    'rate': rate,
    'dep_from': depFrom,
    'opening_year': openingYear,
    'opening_accum': openingAccum,
    'disposed_date': disposedDate,
    'disposal_proceeds': disposalProceeds,
    'source_key': sourceKey,
    'source': source,
    'notes': notes,
  };

  /// The month depreciation starts (the 1st).
  DateTime? get _start {
    final d = depFrom ?? purchaseDate;
    if (d == null) return openingYear == null ? null : DateTime.parse(openingYear!);
    final p = DateTime.parse(d);
    return DateTime(p.year, p.month);
  }

  /// Months from [from] to [to] (both 1sts, [to] included) that it is
  /// depreciated in: from its first month, to the month it was sold.
  int monthsIn(DateTime from, DateTime to) {
    final start = _start;
    if (start == null || rate == 0) return 0;
    var a = from.isBefore(start) ? start : from;
    var b = to;
    if (disposedDate != null) {
      final s = DateTime.parse(disposedDate!);
      final last = DateTime(s.year, s.month);
      if (last.isBefore(b)) b = last;
    }
    if (b.isBefore(a)) return 0;
    a = DateTime(a.year, a.month);
    return (b.year - a.year) * 12 + b.month - a.month + 1;
  }

  /// Depreciation for [months] months, after [accum] already written off.
  double depreciation(int months, double accum) {
    if (months <= 0) return 0;
    final full = _round(cost * rate / 100 * months / 12);
    return _round(math.max(0, math.min(full, cost - accum)));
  }
}

/// A year's override of an asset's depreciation (asset_dep_overrides).
typedef DepOverride = ({String assetId, String yearStart, double amount});

/// The start (1 March, yyyy-MM-dd) of the financial year [iso] falls in.
String assetYearStart(String iso) {
  final d = DateTime.parse(iso);
  return toDateStr(DateTime(d.month >= 3 ? d.year : d.year - 1, 3, 1));
}

String _yearEnd(String yearStart) => toDateStr(DateTime(DateTime.parse(yearStart).year + 1, 3, 0));

/// One asset in a year's register: cost at the start, bought in the year,
/// sold in the year, accumulated depreciation at the start, the year's
/// depreciation, written off on the sale, and the book values.
class AssetYearLine {
  AssetYearLine({
    required this.asset,
    required this.costStart,
    required this.bought,
    required this.sold,
    required this.accumStart,
    required this.depreciation,
    required this.accumSold,
    required this.overridden,
  });

  final Asset asset;
  final double costStart;
  final double bought;
  final double sold;
  final double accumStart;
  final double depreciation;
  final double accumSold;
  final bool overridden;

  double get costEnd => _round(costStart + bought - sold);
  double get accumEnd => _round(accumStart + depreciation - accumSold);
  double get bookStart => _round(costStart - accumStart);
  double get bookEnd => _round(costEnd - accumEnd);

  /// Profit (plus) or loss on a sale in the year.
  double? get profitOnSale => sold == 0 ? null : _round((asset.disposalProceeds ?? 0) - (sold - accumSold));
}

/// [asset]'s accumulated depreciation at the start of [yearStart]: its
/// opening figure, plus each year since (as worked out, or overridden).
double accumAt(Asset asset, String yearStart, List<DepOverride> overrides) {
  final from = asset.openingYear;
  var accum = from == null ? 0.0 : asset.openingAccum;
  var y = from ?? (asset.purchaseDate == null ? yearStart : assetYearStart(asset.purchaseDate!));
  while (y.compareTo(yearStart) < 0) {
    accum = _round(accum + _yearDep(asset, y, accum, overrides).$1);
    y = toDateStr(DateTime(DateTime.parse(y).year + 1, 3, 1));
  }
  return accum;
}

(double, bool) _yearDep(Asset a, String yearStart, double accum, List<DepOverride> overrides) {
  for (final o in overrides) {
    if (o.assetId == a.id && o.yearStart == yearStart) return (o.amount, true);
  }
  final s = DateTime.parse(yearStart);
  return (a.depreciation(a.monthsIn(s, DateTime(s.year + 1, 2)), accum), false);
}

/// The register for the financial year from [yearStart]: every asset owned
/// in it (bought by its end, not sold before its start), by group.
List<AssetYearLine> assetYear(String yearStart, List<Asset> assets, List<DepOverride> overrides) {
  final end = _yearEnd(yearStart);
  final out = <AssetYearLine>[];
  for (final a in assets) {
    final bought = a.purchaseDate;
    // Brought in with opening figures: from that year on; bought since: from its purchase.
    if (a.openingYear != null ? a.openingYear!.compareTo(yearStart) > 0 : (bought != null && bought.compareTo(end) > 0)) continue;
    if (a.disposedDate != null && a.disposedDate!.compareTo(yearStart) < 0) continue;
    final newThisYear = a.openingYear == null && bought != null && bought.compareTo(yearStart) >= 0;
    final accum = accumAt(a, yearStart, overrides);
    final (dep, overridden) = _yearDep(a, yearStart, accum, overrides);
    final soldNow = a.disposedDate != null && a.disposedDate!.compareTo(end) <= 0;
    out.add(
      AssetYearLine(
        asset: a,
        costStart: newThisYear ? 0 : a.cost,
        bought: newThisYear ? a.cost : 0,
        sold: soldNow ? a.cost : 0,
        accumStart: accum,
        depreciation: dep,
        accumSold: soldNow ? _round(accum + dep) : 0,
        overridden: overridden,
      ),
    );
  }
  out.sort((x, y) {
    final c = x.asset.category.index.compareTo(y.asset.category.index);
    if (c != 0) return c;
    final n = (x.asset.number ?? 1 << 30).compareTo(y.asset.number ?? 1 << 30);
    return n != 0 ? n : (x.asset.purchaseDate ?? '').compareTo(y.asset.purchaseDate ?? '');
  });
  return out;
}

/// The depreciation of the months from [from] to [to] (1sts, both
/// included) within the financial year from [yearStart], per account
/// (accumulated depreciation): what a journal for those months debits to
/// [kDepreciationAccount]. A year's override is spread evenly over its months.
Map<String, double> depreciationForMonths(String yearStart, DateTime from, DateTime to, List<Asset> assets, List<DepOverride> overrides) {
  final out = <String, double>{};
  for (final l in assetYear(yearStart, assets, overrides)) {
    final acc = l.asset.category.depAccount;
    if (acc == null || l.depreciation == 0) continue;
    final s = DateTime.parse(yearStart);
    final yearMonths = l.asset.monthsIn(s, DateTime(s.year + 1, 2));
    final months = l.asset.monthsIn(from, to);
    if (yearMonths == 0 || months == 0) continue;
    // Its share of the year's depreciation (capped at what is left).
    out[acc] = _round((out[acc] ?? 0) + _round(l.depreciation * months / yearMonths));
  }
  return out;
}

/// A month's depreciation journal for Xero (yyyy-MM-01), and whether it is in Xero.
typedef DepJournal = ({String month, double amount, String? sentAt});

const kXeroJournalHeader = [
  '*Narration',
  '*Date',
  'Description',
  '*AccountCode',
  '*TaxRate',
  '*Amount',
  'TrackingName1',
  'TrackingOption1',
  'TrackingName2',
  'TrackingOption2',
];

String _csvDate(String iso) {
  final p = iso.split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}

/// A Xero manual journal (Accounting > Manual journals > Import) dated
/// [date]: the depreciation debited to [kDepreciationAccount], each
/// account's accumulated depreciation credited.
List<List<String>> depreciationJournalRows(String narration, String date, Map<String, double> byAccount) {
  final total = _round(byAccount.values.fold(0.0, (s, v) => s + v));
  return [
    [narration, _csvDate(date), 'Depreciation', kDepreciationAccount, 'No VAT', total.toStringAsFixed(2), '', '', '', ''],
    for (final e in byAccount.entries) [narration, _csvDate(date), 'Accumulated depreciation', e.key, 'No VAT', (-e.value).toStringAsFixed(2), '', '', '', ''],
  ];
}

/// Xero starts on this day; the depreciation of the months before it in the
/// year goes in one journal dated the day before.
const kAssetXeroFrom = '2026-09-01';

/// A depreciation journal still to go to Xero: its date and narration, the
/// months it covers (yyyy-MM-01) and the depreciation per account.
typedef JournalDue = ({String date, String narration, List<String> months, Map<String, double> byAccount});

String _monthEnd(DateTime m) => toDateStr(DateTime(m.year, m.month + 1, 0));

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _monthName(DateTime m) => '${_monthNames[m.month - 1]} ${m.year}';

/// The depreciation journals of the year from [yearStart] up to the last
/// month ended by [today], for the months not in Xero yet ([journaled]):
/// one per month from [kAssetXeroFrom], the months before it together.
List<JournalDue> journalsDue(String yearStart, DateTime today, List<Asset> assets, List<DepOverride> overrides, Set<String> journaled) {
  final s = DateTime.parse(yearStart);
  final yearLast = DateTime(s.year + 1, 2);
  final lastEnded = DateTime(today.year, today.month - 1);
  final last = lastEnded.isBefore(yearLast) ? lastEnded : yearLast;
  final xeroFrom = DateTime.parse(kAssetXeroFrom);
  final before = <DateTime>[];
  final after = <DateTime>[];
  for (var m = s; !m.isAfter(last); m = DateTime(m.year, m.month + 1)) {
    if (journaled.contains(toDateStr(m))) continue;
    (m.isBefore(xeroFrom) ? before : after).add(m);
  }
  final out = <JournalDue>[];
  if (before.isNotEmpty) {
    final byAccount = <String, double>{};
    for (final m in before) {
      depreciationForMonths(yearStart, m, m, assets, overrides).forEach((k, v) => byAccount[k] = _round((byAccount[k] ?? 0) + v));
    }
    out.add((
      date: toDateStr(xeroFrom.subtract(const Duration(days: 1))),
      narration: 'Depreciation ${_monthName(before.first)}${before.length > 1 ? ' to ${_monthName(before.last)}' : ''}',
      months: [for (final m in before) toDateStr(m)],
      byAccount: byAccount,
    ));
  }
  for (final m in after) {
    out.add((
      date: _monthEnd(m),
      narration: 'Depreciation ${_monthName(m)}',
      months: [toDateStr(m)],
      byAccount: depreciationForMonths(yearStart, m, m, assets, overrides),
    ));
  }
  return out;
}
