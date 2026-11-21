import '../../core/formatters.dart';

/// Lines from this day go to Xero: the balances at 31 Aug 2026 are its
/// opening balances.
const kCardXeroFrom = '2026-09-01';

/// ABSA's two cards, each with its statements folder and bank account in Xero.
enum CardKind {
  credit('credit', 'Credit card', 'Credit card', 'NANINI CREDIT', 'ABSA Credit Card'),
  fleet('fleet', 'Fleet card', 'Fleet Card', 'ABSA Fleet Card - 7082831000194732', 'ABSA Fleet Card');

  const CardKind(this.code, this.label, this.folder, this.xeroAccount, this.payee);

  /// card_statements.card.
  final String code;
  final String label;

  /// The client folder's `<year>\Bank\<folder>`.
  final String folder;
  final String xeroAccount;
  final String payee;
}

double _round(num v) => (v * 100).roundToDouble() / 100;

/// One statement: its date (and period), the balance brought forward and the
/// closing balance. Plus: in credit; minus: owed to ABSA.
class CardStatement {
  CardStatement({
    required this.id,
    required this.date,
    this.from,
    this.to,
    this.number,
    this.accountNo,
    required this.opening,
    required this.closing,
    this.fileName,
  });

  final String id;
  final String date;
  final String? from;
  final String? to;
  final int? number;
  final String? accountNo;
  final double opening;
  final double closing;
  final String? fileName;

  factory CardStatement.fromJson(Map<String, dynamic> j) => CardStatement(
    id: j['id'] as String,
    date: j['statement_date'] as String,
    from: j['period_from'] as String?,
    to: j['period_to'] as String?,
    number: (j['statement_no'] as num?)?.toInt(),
    accountNo: j['account_no'] as String?,
    opening: (j['opening'] as num).toDouble(),
    closing: (j['closing'] as num).toDouble(),
    fileName: j['file_name'] as String?,
  );
}

/// A line of a statement, or one added in the hub ([manual]). [amount]: plus
/// into the card (a payment, credit interest), minus spent or charged.
class CardLine {
  CardLine({
    required this.id,
    required this.statementId,
    required this.date,
    required this.description,
    this.reference,
    required this.amount,
    this.manual = false,
    this.xeroSentAt,
  });

  final String id;
  final String statementId;
  final String date;
  final String description;
  final String? reference;
  final double amount;
  final bool manual;
  final String? xeroSentAt;

  factory CardLine.fromJson(Map<String, dynamic> j) => CardLine(
    id: j['id'] as String,
    statementId: j['statement_id'] as String,
    date: j['line_date'] as String,
    description: j['description'] as String,
    reference: j['reference'] as String?,
    amount: (j['amount'] as num).toDouble(),
    manual: j['manual'] as bool? ?? false,
    xeroSentAt: j['xero_sent_at'] as String?,
  );
}

/// The start (1 March, yyyy-MM-dd) of the financial year [iso] falls in.
String cardYearStart(String iso) {
  final d = DateTime.parse(iso);
  return toDateStr(DateTime(d.month >= 3 ? d.year : d.year - 1, 3, 1));
}

String _nextYearStart(String yearStart) => toDateStr(DateTime(DateTime.parse(yearStart).year + 1, 3, 1));

/// One statement in the working paper: from [opening] (the balance after the
/// statement before), its lines in the year, to its closing balance.
/// [difference]: what the lines don't explain -- a line missing (add it), or
/// a balance brought forward that isn't the last closing balance.
class CardMonth {
  CardMonth({required this.statement, required this.opening, required this.lines});

  final CardStatement statement;
  final double opening;
  final List<CardLine> lines;

  double get total => _round(lines.fold(0.0, (s, l) => s + l.amount));
  double get difference => _round(statement.closing - opening - total);
}

/// The working paper for a financial year.
class CardYear {
  CardYear({required this.card, required this.yearStart, required this.opening, required this.openingFrom, required this.months});

  final CardKind card;
  final String yearStart;
  final double? opening;

  /// Where [opening] comes from: 'entered' (the financial statements), 'last
  /// statement' (the closing balance before the year) or 'statement' (the
  /// year's first statement, with its lines before 1 March).
  final String openingFrom;
  final List<CardMonth> months;

  String get yearEnd => toDateStr(DateTime.parse(_nextYearStart(yearStart)).subtract(const Duration(days: 1)));
  double? get closing => months.isEmpty ? opening : months.last.statement.closing;
  double get paidIn => _round(months.fold(0.0, (s, m) => s + m.lines.where((l) => l.amount > 0).fold(0.0, (t, l) => t + l.amount)));
  double get spent => _round(months.fold(0.0, (s, m) => s + m.lines.where((l) => l.amount < 0).fold(0.0, (t, l) => t + l.amount)));
  double get differences => _round(months.fold(0.0, (s, m) => s + m.difference));

  /// The balance the card's Xero account opens on (31 Aug 2026): before the
  /// first statement dated from [kCardXeroFrom], with that statement's lines
  /// before then. Null when the year has no such statement.
  double? get xeroOpening {
    for (final m in months) {
      if (m.statement.date.compareTo(kCardXeroFrom) >= 0) {
        return _round(m.opening + m.lines.where((l) => l.date.compareTo(kCardXeroFrom) < 0).fold(0.0, (s, l) => s + l.amount));
      }
    }
    return null;
  }
}

/// The financial year from [yearStart] for [card]: its statements dated in
/// the year, each with its lines dated in the year.
CardYear cardYear({
  required CardKind card,
  required String yearStart,
  double? opening,
  required List<CardStatement> statements,
  required List<CardLine> lines,
}) {
  final next = _nextYearStart(yearStart);
  final sorted = [...statements]..sort((a, b) => a.date.compareTo(b.date));
  final before = [
    for (final s in sorted)
      if (s.date.compareTo(yearStart) < 0) s,
  ];
  final inYear = [
    for (final s in sorted)
      if (s.date.compareTo(yearStart) >= 0 && s.date.compareTo(next) < 0) s,
  ];
  List<CardLine> linesOf(CardStatement s) => [
    for (final l in lines)
      if (l.statementId == s.id) l,
  ]..sort((a, b) => a.date.compareTo(b.date));
  double? start = opening;
  var from = 'entered';
  if (start == null && before.isNotEmpty) {
    start = before.last.closing;
    from = 'last statement';
  } else if (start == null && inYear.isNotEmpty) {
    final first = inYear.first;
    start = _round(first.opening + linesOf(first).where((l) => l.date.compareTo(yearStart) < 0).fold(0.0, (s, l) => s + l.amount));
    from = 'statement';
  }
  final months = <CardMonth>[];
  if (start != null) {
    var bal = start;
    for (final s in inYear) {
      months.add(
        CardMonth(
          statement: s,
          opening: bal,
          lines: [
            for (final l in linesOf(s))
              if (l.date.compareTo(yearStart) >= 0) l,
          ],
        ),
      );
      bal = s.closing;
    }
  }
  return CardYear(card: card, yearStart: yearStart, opening: start, openingFrom: from, months: months);
}

/// The lines of [year] for Xero: dated from [kCardXeroFrom], not sent yet
/// (all of them, when not [newOnly]).
List<CardLine> cardXeroLines(CardYear year, {bool newOnly = true}) => [
  for (final m in year.months)
    for (final l in m.lines)
      if (l.date.compareTo(kCardXeroFrom) >= 0 && (!newOnly || l.xeroSentAt == null)) l,
]..sort((a, b) => a.date.compareTo(b.date));

String _csvDate(String iso) {
  final p = iso.split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}

/// The rows of a Xero bank statement CSV for [card]'s account.
List<List<String>> cardXeroRows(CardKind card, List<CardLine> lines, Map<String, CardStatement> statementOf) => [
  ['*Date', '*Amount', 'Payee', 'Description', 'Reference'],
  for (final l in lines)
    [
      _csvDate(l.date),
      l.amount.toStringAsFixed(2),
      card.payee,
      l.description,
      [if (l.reference != null) l.reference!, 'Statement ${fmtDateDisplay(statementOf[l.statementId]?.date)}'].join(' '),
    ],
];
