import '../../core/formatters.dart';

double _round(num v) => (v * 100).roundToDouble() / 100;

/// What the hub has for a two-month VAT period: supplies (zero-rated, and
/// standard-rated including VAT) and input VAT (standard and capital).
class VatHub {
  VatHub({
    this.zeroRated = 0,
    this.standard = 0,
    this.inputStandard = 0,
    this.inputCapital = 0,
    Map<String, double>? zeroByCrop,
    Map<String, double>? standardBySource,
  }) : zeroByCrop = zeroByCrop ?? {},
       standardBySource = standardBySource ?? {};

  double zeroRated;
  double standard;
  double inputStandard;
  double inputCapital;

  /// Zero-rated sales by crop (account sales' gross).
  final Map<String, double> zeroByCrop;

  /// Standard-rated supplies (including VAT) by where they come from.
  final Map<String, double> standardBySource;
}

/// A period's figures kept by hand (vat_periods): supplies the hub doesn't
/// have (hunting, game sales, rent, insurance claims), the diesel refund,
/// and the VAT201 as submitted.
class VatManual {
  VatManual({
    required this.periodStart,
    this.otherStandard = 0,
    this.otherZero = 0,
    this.capitalSupplies = 0,
    this.dieselRefund = 0,
    this.vat201Output,
    this.vat201Input,
    this.vat201Diesel,
    this.notes,
  });

  final String periodStart;
  final double otherStandard;
  final double otherZero;
  final double capitalSupplies;
  final double dieselRefund;
  final double? vat201Output;
  final double? vat201Input;
  final double? vat201Diesel;
  final String? notes;

  factory VatManual.fromJson(Map<String, dynamic> j) {
    double v(String k) => (j[k] as num?)?.toDouble() ?? 0;
    return VatManual(
      periodStart: j['period_start'] as String,
      otherStandard: v('other_standard'),
      otherZero: v('other_zero'),
      capitalSupplies: v('capital_supplies'),
      dieselRefund: v('diesel_refund'),
      vat201Output: (j['vat201_output'] as num?)?.toDouble(),
      vat201Input: (j['vat201_input'] as num?)?.toDouble(),
      vat201Diesel: (j['vat201_diesel'] as num?)?.toDouble(),
      notes: j['notes'] as String?,
    );
  }

  Map<String, dynamic> toRow() => {
    'period_start': periodStart,
    'other_standard': otherStandard,
    'other_zero': otherZero,
    'capital_supplies': capitalSupplies,
    'diesel_refund': dieselRefund,
    'vat201_output': vat201Output,
    'vat201_input': vat201Input,
    'vat201_diesel': vat201Diesel,
    'notes': notes,
  };
}

/// One two-month period of the VAT control, as the working papers' BTW
/// sheet: supplies, output VAT ((standard + capital) x 15/115), input VAT,
/// the diesel refund and the net VAT payable (refundable: minus), beside
/// the VAT201 as submitted.
class VatPeriod {
  VatPeriod({required this.start, required this.hub, required this.manual});

  /// The first day (yyyy-MM-01).
  final String start;
  final VatHub hub;
  final VatManual manual;

  String get end => toDateStr(DateTime(DateTime.parse(start).year, DateTime.parse(start).month + 2, 0));
  String get label {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final s = DateTime.parse(start);
    final e = DateTime(s.year, s.month + 1);
    return '${m[s.month - 1]} - ${m[e.month - 1]} ${e.year}';
  }

  double get standard => _round(hub.standard + manual.otherStandard);
  double get capitalSupplies => manual.capitalSupplies;
  double get zeroRated => _round(hub.zeroRated + manual.otherZero);
  double get outputVat => _round((standard + capitalSupplies) * 15 / 115);
  double get inputCapital => hub.inputCapital;
  double get inputStandard => hub.inputStandard;
  double get inputVat => _round(inputCapital + inputStandard);
  double get dieselRefund => manual.dieselRefund;
  double get net => _round(outputVat - inputVat - dieselRefund);

  /// Sales excluding VAT (as declared): standard and capital less their VAT, and zero-rated.
  double get salesExcl => _round((standard + capitalSupplies) * 100 / 115 + zeroRated);

  bool get hasVat201 => manual.vat201Output != null || manual.vat201Input != null;
  double? get vat201Net => hasVat201 ? _round((manual.vat201Output ?? 0) - (manual.vat201Input ?? 0) - (manual.vat201Diesel ?? 0)) : null;

  /// The VAT control less the VAT201: null without the VAT201.
  double? get difference => vat201Net == null ? null : _round(net - vat201Net!);
}

/// The six two-month periods (1sts) of the financial year from [yearStart] (1 March).
List<String> vatPeriodStarts(String yearStart) {
  final s = DateTime.parse(yearStart);
  return [for (var i = 0; i < 12; i += 2) toDateStr(DateTime(s.year, s.month + i))];
}

/// The period start (yyyy-MM-01) [iso] falls in, for a year from 1 March.
String vatPeriodOf(String iso) {
  final d = DateTime.parse(iso);
  // Periods start in the odd months from March: Mar, May, Jul, Sep, Nov, Jan.
  final m = d.month.isOdd ? d.month : d.month - 1;
  return toDateStr(DateTime(d.year, m));
}

/// The start (1 March, yyyy-MM-dd) of the financial year [iso] falls in.
String vatYearStart(String iso) {
  final d = DateTime.parse(iso);
  return toDateStr(DateTime(d.month >= 3 ? d.year : d.year - 1, 3, 1));
}

/// A year's VAT control: its periods, and the sales per the financial
/// statements ([fsSales], entered) to agree the declared sales to.
class VatYear {
  VatYear({required this.yearStart, required this.periods, this.fsSales});

  final String yearStart;
  final List<VatPeriod> periods;
  final double? fsSales;

  double _sum(double Function(VatPeriod) f) => _round(periods.fold(0.0, (s, p) => s + f(p)));
  double get standard => _sum((p) => p.standard);
  double get capitalSupplies => _sum((p) => p.capitalSupplies);
  double get zeroRated => _sum((p) => p.zeroRated);
  double get outputVat => _sum((p) => p.outputVat);
  double get inputCapital => _sum((p) => p.inputCapital);
  double get inputStandard => _sum((p) => p.inputStandard);
  double get inputVat => _sum((p) => p.inputVat);
  double get dieselRefund => _sum((p) => p.dieselRefund);
  double get net => _sum((p) => p.net);
  double get salesExcl => _sum((p) => p.salesExcl);
  double? get salesDifference => fsSales == null ? null : _round(salesExcl - fsSales!);

  /// Zero-rated sales by crop over the year (the hub's account sales).
  Map<String, double> get zeroByCrop {
    final out = <String, double>{};
    for (final p in periods) {
      p.hub.zeroByCrop.forEach((k, v) => out[k] = _round((out[k] ?? 0) + v));
    }
    return out;
  }

  /// Standard-rated supplies (including VAT) by source over the year.
  Map<String, double> get standardBySource {
    final out = <String, double>{};
    for (final p in periods) {
      p.hub.standardBySource.forEach((k, v) => out[k] = _round((out[k] ?? 0) + v));
      if (p.manual.otherStandard != 0) out['Other (entered)'] = _round((out['Other (entered)'] ?? 0) + p.manual.otherStandard);
    }
    return out;
  }
}

/// One account sale for the VAT control: its date, crop, gross (excluding
/// VAT), VAT on the sale (tobacco), VAT on its deductions (commission,
/// market fees: input VAT) and its pallets paid for (including VAT: a
/// standard-rated supply).
typedef VatSale = ({String date, String crop, double gross, double vatOnSales, double deductionsVat, double pallets});

/// A supplier invoice's line for the VAT control: its date, VAT and whether
/// it is on a fixed asset account (capital).
typedef VatPurchase = ({String date, double vat, bool capital});

/// The hub's figures per period of the year from [yearStart].
Map<String, VatHub> vatHubFigures(String yearStart, List<VatSale> sales, List<VatPurchase> purchases) {
  final starts = vatPeriodStarts(yearStart);
  final out = {for (final s in starts) s: VatHub()};
  for (final s in sales) {
    final h = out[vatPeriodOf(s.date)];
    if (h == null) continue;
    if (s.vatOnSales > 0) {
      final incl = _round(s.gross + s.vatOnSales);
      h.standard = _round(h.standard + incl);
      h.standardBySource['${s.crop} (account sales)'] = _round((h.standardBySource['${s.crop} (account sales)'] ?? 0) + incl);
    } else {
      h.zeroRated = _round(h.zeroRated + s.gross);
      h.zeroByCrop[s.crop] = _round((h.zeroByCrop[s.crop] ?? 0) + s.gross);
    }
    if (s.pallets != 0) {
      h.standard = _round(h.standard + s.pallets);
      h.standardBySource['Pallets sold'] = _round((h.standardBySource['Pallets sold'] ?? 0) + s.pallets);
    }
    h.inputStandard = _round(h.inputStandard + s.deductionsVat);
  }
  for (final p in purchases) {
    final h = out[vatPeriodOf(p.date)];
    if (h == null) continue;
    if (p.capital) {
      h.inputCapital = _round(h.inputCapital + p.vat);
    } else {
      h.inputStandard = _round(h.inputStandard + p.vat);
    }
  }
  return out;
}

/// The year's VAT control from the hub's figures and those kept by hand.
VatYear vatYear(String yearStart, Map<String, VatHub> hub, List<VatManual> manual, {double? fsSales}) => VatYear(
  yearStart: yearStart,
  fsSales: fsSales,
  periods: [
    for (final s in vatPeriodStarts(yearStart))
      VatPeriod(
        start: s,
        hub: hub[s] ?? VatHub(),
        manual: manual.firstWhere((m) => m.periodStart == s, orElse: () => VatManual(periodStart: s)),
      ),
  ],
);
