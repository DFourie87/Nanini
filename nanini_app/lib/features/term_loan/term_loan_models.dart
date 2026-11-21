import 'dart:math' as math;

import '../../core/formatters.dart';

/// ABSA's term loan (FlexiReserve), account 3053810190.
const kTermLoanAccount = '3053810190';

/// The name of the loan's bank account in Xero.
const kTermLoanXeroAccount = 'TERMLOAN';

/// Lines from this day go to Xero: the balances at 31 Aug 2026 are its
/// opening balances.
const kTermLoanXeroFrom = '2026-09-01';

double _round(num v) => (v * 100).roundToDouble() / 100;

/// One statement: its date, the outstanding capital and the prepaid amount
/// (Arrear/Advance). The loan's balance is prepaid less capital: plus when
/// more has been paid in than is owed.
class TermLoanStatement {
  TermLoanStatement({
    required this.id,
    required this.date,
    this.from,
    this.to,
    required this.capital,
    required this.advance,
    this.rate,
    this.amountPayable,
    this.payableDate,
    this.fileName,
    this.xeroSentAt,
    this.xeroInterestSent,
  });

  final String id;
  final String date;
  final String? from;
  final String? to;
  final double capital;
  final double advance;
  final double? rate;
  final double? amountPayable;
  final String? payableDate;
  final String? fileName;
  final String? xeroSentAt;
  final double? xeroInterestSent;

  double get balance => _round(advance - capital);

  factory TermLoanStatement.fromJson(Map<String, dynamic> j) => TermLoanStatement(
    id: j['id'] as String,
    date: j['statement_date'] as String,
    from: j['period_from'] as String?,
    to: j['period_to'] as String?,
    capital: (j['capital'] as num).toDouble(),
    advance: (j['advance'] as num).toDouble(),
    rate: (j['interest_rate'] as num?)?.toDouble(),
    amountPayable: (j['amount_payable'] as num?)?.toDouble(),
    payableDate: j['payable_date'] as String?,
    fileName: j['file_name'] as String?,
    xeroSentAt: j['xero_sent_at'] as String?,
    xeroInterestSent: (j['xero_interest_sent'] as num?)?.toDouble(),
  );
}

/// A transaction on a statement, or one added in the hub ([manual]) that the
/// statement left out. [amount]: plus paid into the loan, minus drawn.
class TermLoanLine {
  TermLoanLine({
    required this.id,
    required this.statementId,
    required this.date,
    required this.description,
    required this.amount,
    this.manual = false,
    this.xeroSentAt,
  });

  final String id;
  final String statementId;
  final String date;
  final String description;
  final double amount;
  final bool manual;
  final String? xeroSentAt;

  /// Money paid in or drawn (a transfer or journal, or added by hand). The
  /// rest ("Instalment due": the month's interest set off against the
  /// prepaid amount; "Interest rate": a new rate) are shown, not counted:
  /// they are in the month's interest.
  bool get isMoney => manual || RegExp('transfer|journal|payment|deposit', caseSensitive: false).hasMatch(description);

  factory TermLoanLine.fromJson(Map<String, dynamic> j) => TermLoanLine(
    id: j['id'] as String,
    statementId: j['statement_id'] as String,
    date: j['line_date'] as String,
    description: j['description'] as String,
    amount: (j['amount'] as num).toDouble(),
    manual: j['manual'] as bool? ?? false,
    xeroSentAt: j['xero_sent_at'] as String?,
  );
}

/// The start (1 March, yyyy-MM-dd) of the financial year [iso] falls in.
String termLoanYearStart(String iso) {
  final d = DateTime.parse(iso);
  return toDateStr(DateTime(d.month >= 3 ? d.year : d.year - 1, 3, 1));
}

String _nextYearStart(String yearStart) => toDateStr(DateTime(DateTime.parse(yearStart).year + 1, 3, 1));

/// One statement in the working paper: from [opening] (the balance before
/// it) to its balance. The money paid in or drawn is as on the statement
/// (and added by hand); the rest of the change is the month's interest and
/// charges, net of the interest set off against the prepaid amount.
class TermLoanMonth {
  TermLoanMonth({required this.statement, required this.opening, required this.money, required this.info});

  final TermLoanStatement statement;
  final double opening;
  final List<TermLoanLine> money;
  final List<TermLoanLine> info;

  double get movement => _round(statement.balance - opening);
  double get moneyTotal => _round(money.fold(0.0, (s, l) => s + l.amount));
  double get interest => _round(movement - moneyTotal);

  /// About a month's interest on the capital.
  double get monthInterest => statement.capital * (statement.rate ?? 12) / 100 / 12;

  /// More than a month's interest left over: a payment or drawing the
  /// statement left out (ABSA's statements sometimes list nothing).
  bool get looksShort => interest.abs() > math.max(monthInterest, 1000);
}

/// The working paper for a financial year: the opening balance, each
/// statement in the year and the closing balance.
class TermLoanYear {
  TermLoanYear({required this.yearStart, required this.opening, required this.openingEntered, required this.months});

  final String yearStart;

  /// Null: no opening balance entered and no statement before the year.
  final double? opening;
  final bool openingEntered;
  final List<TermLoanMonth> months;

  String get yearEnd => toDateStr(DateTime.parse(_nextYearStart(yearStart)).subtract(const Duration(days: 1)));
  double? get closing => months.isEmpty ? opening : months.last.statement.balance;
  double get paidIn => _round(months.fold(0.0, (s, m) => s + m.money.where((l) => l.amount > 0).fold(0.0, (t, l) => t + l.amount)));
  double get drawn => _round(months.fold(0.0, (s, m) => s + m.money.where((l) => l.amount < 0).fold(0.0, (t, l) => t + l.amount)));
  double get interest => _round(months.fold(0.0, (s, m) => s + m.interest));

  /// The balance Xero's TERMLOAN account opens on (31 Aug 2026): before the
  /// first statement dated from [kTermLoanXeroFrom], with that statement's
  /// lines before then. Null when the year has no such statement.
  double? get xeroOpening {
    for (final m in months) {
      if (m.statement.date.compareTo(kTermLoanXeroFrom) >= 0) {
        return _round(m.opening + m.money.where((l) => l.date.compareTo(kTermLoanXeroFrom) < 0).fold(0.0, (s, l) => s + l.amount));
      }
    }
    return null;
  }
}

/// The financial year from [yearStart]: the statements dated in it, each
/// with its lines (those dated in the year). It opens on [opening] (the
/// financial statements' balance), else on the last statement before it.
TermLoanYear termLoanYear({required String yearStart, double? opening, required List<TermLoanStatement> statements, required List<TermLoanLine> lines}) {
  final next = _nextYearStart(yearStart);
  final sorted = [...statements]..sort((a, b) => a.date.compareTo(b.date));
  final before = [
    for (final s in sorted)
      if (s.date.compareTo(yearStart) < 0) s,
  ];
  final start = opening ?? (before.isEmpty ? null : before.last.balance);
  final months = <TermLoanMonth>[];
  if (start != null) {
    var bal = start;
    for (final s in sorted) {
      if (s.date.compareTo(yearStart) < 0 || s.date.compareTo(next) >= 0) continue;
      final own = [
        for (final l in lines)
          if (l.statementId == s.id && l.date.compareTo(yearStart) >= 0) l,
      ]..sort((a, b) => a.date == b.date ? (a.manual ? 1 : 0) - (b.manual ? 1 : 0) : a.date.compareTo(b.date));
      final m = TermLoanMonth(
        statement: s,
        opening: bal,
        money: [
          for (final l in own)
            if (l.isMoney) l,
        ],
        info: [
          for (final l in own)
            if (!l.isMoney) l,
        ],
      );
      months.add(m);
      bal = s.balance;
    }
  }
  return TermLoanYear(yearStart: yearStart, opening: start, openingEntered: opening != null, months: months);
}

/// A line of the CSV for Xero's TERMLOAN account: a payment or drawing
/// ([line]) or a month's interest and charges ([month]).
class TermLoanXeroItem {
  TermLoanXeroItem({required this.date, required this.amount, required this.description, required this.reference, this.line, this.month});

  final String date;
  final double amount;
  final String description;
  final String reference;
  final TermLoanLine? line;
  final TermLoanMonth? month;
}

/// What goes to Xero from [year]: the payments and drawings dated from
/// [kTermLoanXeroFrom], and each statement's interest and charges (when not
/// nil) -- only those not sent yet when [newOnly]. [changed]: interest sent
/// before that has changed since (a line added afterwards): fix it in Xero.
({List<TermLoanXeroItem> items, List<TermLoanMonth> changed}) termLoanXeroItems(TermLoanYear year, {bool newOnly = true}) {
  final items = <TermLoanXeroItem>[];
  final changed = <TermLoanMonth>[];
  for (final m in year.months) {
    final ref = 'Term loan statement ${fmtDateDisplay(m.statement.date)}';
    for (final l in m.money) {
      if (l.date.compareTo(kTermLoanXeroFrom) < 0 || (newOnly && l.xeroSentAt != null)) continue;
      items.add(TermLoanXeroItem(date: l.date, amount: l.amount, description: l.description, reference: ref, line: l));
    }
    if (m.statement.date.compareTo(kTermLoanXeroFrom) < 0) continue;
    final sent = m.statement.xeroInterestSent;
    if (newOnly && sent != null) {
      if ((sent - m.interest).abs() > 0.005) changed.add(m);
      continue;
    }
    if (m.interest == 0) continue;
    items.add(
      TermLoanXeroItem(
        date: m.statement.date,
        amount: m.interest,
        description: 'Interest and charges (net) to ${fmtDateDisplay(m.statement.date)}',
        reference: ref,
        month: m,
      ),
    );
  }
  items.sort((a, b) => a.date.compareTo(b.date));
  return (items: items, changed: changed);
}

String _csvDate(String iso) {
  final p = iso.split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}

/// The rows of a Xero bank statement CSV (Accounting > Bank accounts >
/// TERMLOAN > Import a statement).
List<List<String>> termLoanXeroRows(List<TermLoanXeroItem> items) => [
  ['*Date', '*Amount', 'Payee', 'Description', 'Reference'],
  for (final i in items) [_csvDate(i.date), i.amount.toStringAsFixed(2), 'ABSA Term Loan $kTermLoanAccount', i.description, i.reference],
];
