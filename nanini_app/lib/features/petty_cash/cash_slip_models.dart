import '../xero/xero_api.dart' show xeroTaxTypeOf;
import '../xero/xero_export.dart' show kNoVat, kStandardPurchases, kXeroFrom;

double _round(num v) => (v * 100).roundToDouble() / 100;

/// A till slip paid from the petty cash (cash_slips): its date, shop, what it
/// was for, the total paid with VAT, the VAT on it (0: none) and the account
/// it goes to; [xeroId] once sent to Xero as spend money.
class CashSlip {
  CashSlip({
    required this.id,
    required this.date,
    required this.shop,
    this.description,
    required this.amount,
    this.vat = 0,
    this.glAccount,
    this.source,
    this.xeroId,
    this.xeroSentAt,
    this.cashConfirmed = false,
  });

  final String id;
  final String date;
  final String shop;
  final String? description;
  final double amount;
  final double vat;
  final String? glAccount;
  final String? source;
  final String? xeroId;
  final String? xeroSentAt;

  /// Paid from the petty cash after all, though a bank or card payment of
  /// the same amount is around its date.
  final bool cashConfirmed;

  double get excl => _round(amount - vat);
  bool get inXero => xeroId != null;

  factory CashSlip.fromJson(Map<String, dynamic> j) => CashSlip(
    id: j['id'] as String,
    date: j['slip_date'] as String,
    shop: j['shop'] as String,
    description: j['description'] as String?,
    amount: (j['amount'] as num).toDouble(),
    vat: (j['vat'] as num?)?.toDouble() ?? 0,
    glAccount: j['gl_account'] as String?,
    source: j['source'] as String?,
    xeroId: j['xero_id'] as String?,
    xeroSentAt: j['xero_sent_at'] as String?,
    cashConfirmed: j['cash_confirmed'] as bool? ?? false,
  );

  Map<String, dynamic> toRow() => {
    'slip_date': date,
    'shop': shop,
    'description': description,
    'amount': amount,
    'vat': vat,
    'gl_account': glAccount,
    'source': source,
    'cash_confirmed': cashConfirmed,
  };

  CashSlip copyWith({String? date, String? shop, String? description, double? amount, double? vat, String? glAccount, bool? cashConfirmed}) => CashSlip(
    id: id,
    date: date ?? this.date,
    shop: shop ?? this.shop,
    description: description ?? this.description,
    amount: amount ?? this.amount,
    vat: vat ?? this.vat,
    glAccount: glAccount ?? this.glAccount,
    source: source,
    xeroId: xeroId,
    xeroSentAt: xeroSentAt,
    cashConfirmed: cashConfirmed ?? this.cashConfirmed,
  );
}

/// The account last used for [shop] (the same name, any case), to suggest it.
String? lastAccountFor(String shop, List<CashSlip> slips) {
  final key = shop.trim().toLowerCase();
  final mine = [
    for (final s in slips)
      if (s.shop.trim().toLowerCase() == key && (s.glAccount ?? '').isNotEmpty) s,
  ]..sort((a, b) => b.date.compareTo(a.date));
  return mine.isEmpty ? null : mine.first.glAccount;
}

/// Why [s] can't go to Xero yet, or null: it needs an account, and a date
/// from Xero's start ([kXeroFrom]).
String? cashSlipNotReady(CashSlip s) {
  if ((s.glAccount ?? '').isEmpty) return 'no account';
  if (s.date.compareTo(kXeroFrom) < 0) return 'before Xero (${s.date})';
  return null;
}

/// [s] as Xero spend money from the Petty Cash bank account [bankAccountId]:
/// the shop as the contact, one line with its total including VAT on its
/// account, at 15% with the slip's VAT when it shows VAT, else No VAT.
Map<String, dynamic> xeroSpendMoneyJson(CashSlip s, String bankAccountId, Map<String, String> taxTypes) {
  final taxed = s.vat > 0;
  return {
    'Type': 'SPEND',
    'Contact': {'Name': s.shop},
    'BankAccount': {'AccountID': bankAccountId},
    'Date': s.date,
    'Reference': 'Cash slip${(s.description ?? '').isEmpty ? '' : ': ${s.description}'}',
    'LineAmountTypes': 'Inclusive',
    'LineItems': [
      {
        'Description': '${s.shop}${(s.description ?? '').isEmpty ? '' : ' -- ${s.description}'}',
        'Quantity': 1,
        'UnitAmount': s.amount,
        'AccountCode': s.glAccount,
        'TaxType': xeroTaxTypeOf(taxTypes, taxed ? kStandardPurchases : kNoVat),
        if (taxed) 'TaxAmount': s.vat,
      },
    ],
  };
}

/// A line of money out of the ABSA current account (bank_lines, from the
/// bank CSVs on the office PC): its day, the card purchase's own day, what
/// it says and the amount (positive).
class BankLine {
  BankLine({required this.date, this.spentOn, required this.description, required this.amount});

  final String date;
  final String? spentOn;
  final String description;
  final double amount;

  factory BankLine.fromJson(Map<String, dynamic> j) => BankLine(
    date: j['line_date'] as String,
    spentOn: j['spent_on'] as String?,
    description: j['description'] as String,
    amount: (j['amount'] as num).toDouble(),
  );
}

/// Where a slip may already have been paid: the bank or a card, the day,
/// what it says and the amount.
typedef PaidElsewhere = ({String where, String date, String description, double amount});

/// Days either side of a slip's date a payment of the same amount counts.
const kPaidElsewhereDays = 5;

int _days(String a, String b) => DateTime.parse(a).difference(DateTime.parse(b)).inDays.abs();

/// The payments of [s]'s amount, by bank ([bank]) or card ([cards]: the
/// credit and fleet card statements' lines -- what, date, description,
/// amount, minus when spent), within [kPaidElsewhereDays] days of its date:
/// then it was most likely not paid from the petty cash.
List<PaidElsewhere> paidElsewhere(CashSlip s, List<BankLine> bank, List<PaidElsewhere> cards) => [
  for (final b in bank)
    if ((b.amount - s.amount).abs() < 0.005 && _days(b.spentOn ?? b.date, s.date) <= kPaidElsewhereDays)
      (where: 'ABSA', date: b.spentOn ?? b.date, description: b.description, amount: b.amount),
  for (final c in cards)
    if ((c.amount.abs() - s.amount).abs() < 0.005 && c.amount < 0 && _days(c.date, s.date) <= kPaidElsewhereDays) c,
];
