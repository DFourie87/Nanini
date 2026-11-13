import '../delivery/delivery_models.dart' show MarketAgent;
import '../delivery/pallet_stock.dart' show palletInvoiceNumber;
import '../sales/sales_customers_models.dart';
import '../sales/sales_models.dart';
import '../suppliers/suppliers_models.dart';

/// Financials > Xero export: the CSV files Xero imports, built from the hub.

/// The first day Xero takes from the hub: Pastel (and the VAT submitted
/// from it) runs up to 28 Aug 2026, so what is dated 29 Aug on -- with its
/// VAT -- goes to Xero.
const kXeroFrom = '2026-08-29';

/// One deduction line of an account sale (sales_deductions): commission,
/// market fees, bank charges... before VAT, with its VAT; minus with kind
/// "pallets" for pallets the buyer paid for.
class XeroDeduction {
  const XeroDeduction({required this.reportId, required this.label, required this.amount, required this.vat, this.kind, this.ord = 1});
  final String reportId;
  final String label;
  final double amount;
  final double vat;
  final String? kind;
  final int ord;
  bool get isPallets => kind == 'pallets';

  factory XeroDeduction.fromJson(Map<String, dynamic> j) => XeroDeduction(
        reportId: j['report_id'] as String,
        label: j['label'] as String? ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        vat: (j['vat'] as num?)?.toDouble() ?? 0,
        kind: j['kind'] as String?,
        ord: (j['ord'] as num?)?.toInt() ?? 1,
      );
}

/// Xero's tax rates as named in Nanini's Xero.
const kZeroRated = 'Zero Rate (Excluding Goods Exported) (0%)';
const kStandardSales = 'Standard Rate Sales (15%)';
const kStandardPurchases = 'Standard Rate Purchases (15%)';
const kNoVat = 'No VAT (0%)';

/// The sales account for a crop (Xero's chart: Pastel's codes); '' for one
/// without (Xero then won't import the invoice -- add the account).
String xeroSalesAccount(String category) => switch (category) {
      'potatoes' => '1000/800',
      'peppers' => '1000/400',
      'butternut' => '1000/500',
      'peppadew' => '1000/200',
      'watermelon' => '1000/300',
      'tobacco' => '1200/000',
      _ => '',
    };

/// The expense a deduction goes to, by its name on the account sale.
String xeroDeductionAccount(String label) {
  final l = label.toUpperCase();
  if (l.contains('BANK')) return '3200/000'; // Bank Charges
  if (RegExp('TRANSPORT|VERVOER|FREIGHT|TRSP').hasMatch(l)) return '4800/000'; // Transport
  if (RegExp('PALLET|PACK|VERPAK|HANDLING|HANTERING').hasMatch(l)) return '4280/000'; // Packaging: pallets, packing material and charges, handling fees
  return '3490/000'; // Commission Paid: commission, market fees, levies
}

/// "1234.50"; never "-0.00".
String xeroMoney(double v) {
  final s = v.toStringAsFixed(2);
  return s == '-0.00' ? '0.00' : s;
}

String _xeroDate(String iso) {
  final p = iso.split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}

String _isoAdd(String iso, int days) {
  final d = DateTime.parse(iso).add(Duration(days: days));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

double _round(double v) => (v * 100).roundToDouble() / 100;

const kXeroInvoiceHeader = [
  '*ContactName', 'EmailAddress', 'POAddressLine1', 'POAddressLine2', 'POAddressLine3', 'POAddressLine4', 'POCity', 'PORegion',
  'POPostalCode', 'POCountry', '*InvoiceNumber', 'Reference', '*InvoiceDate', '*DueDate', 'Total', 'InventoryItemCode',
  '*Description', '*Quantity', '*UnitAmount', 'Discount', '*AccountCode', '*TaxType', 'TaxAmount', 'TrackingName1',
  'TrackingOption1', 'TrackingName2', 'TrackingOption2', 'Currency', 'BrandingTheme',
];

/// One line of a Xero invoice.
class XeroLine {
  const XeroLine(this.description, this.amount, this.account, this.taxType, [this.tax]);
  final String description;
  final double amount;
  final String account;
  final String taxType;

  /// The VAT exactly (as on the document); null: Xero works it out.
  final double? tax;
  double get total => amount + (tax ?? 0);
}

/// An account sale as a Xero invoice.
class XeroInvoice {
  XeroInvoice(
      {required this.report, required this.contact, required this.number, required this.dueDate, required this.lines, required this.deductionsByLine, String? reference})
      : reference = reference ?? 'Account sale ${report.reportNumber}';
  final SalesReport report;
  final String contact;
  final String number;
  final String dueDate;
  final List<XeroLine> lines;

  /// "Account sale 15060"; "Pallets with account sale IN160835" for pallets paid for.
  final String reference;

  /// False when its deductions weren't read line by line (one line instead).
  final bool deductionsByLine;
  double get total => _round(lines.fold(0.0, (s, l) => s + l.total));
}

/// The account sales as Xero invoices at nett: a line per product (gross;
/// tobacco with its VAT as on the invoice), less each deduction with its VAT
/// to its expense. Without deduction lines: one "Commission and charges"
/// line. Pallets the buyer paid for: an invoice of their own (its number,
/// Packaging, 15%).
List<XeroInvoice> xeroInvoices({
  required List<SalesReport> reports,
  required Map<String, List<SalesLineItem>> lineItems,
  required Map<String, List<XeroDeduction>> deductions,
  required List<Customer> customers,
}) {
  final byAgent = {for (final c in customers) c.agent: c};
  final numbers = <String, int>{};
  for (final r in reports) {
    numbers[r.reportNumber] = (numbers[r.reportNumber] ?? 0) + 1;
  }
  final out = <XeroInvoice>[];
  for (final r in [...reports]..sort((a, b) => '${a.reportDate}${a.reportNumber}'.compareTo('${b.reportDate}${b.reportNumber}'))) {
    final customer = byAgent[r.agent];
    final contact = (customer?.name.trim().isNotEmpty ?? false) ? customer!.name.trim() : (r.agent ?? 'Unknown customer');
    final agentTag = (r.agent ?? '').replaceAll(RegExp('[^A-Za-z]'), '');
    final number = (numbers[r.reportNumber] ?? 0) > 1 ? '${r.reportNumber}-${agentTag.substring(0, agentTag.length < 3 ? agentTag.length : 3).toUpperCase()}' : r.reportNumber;
    final account = xeroSalesAccount(r.category);
    final tobacco = r.category == 'tobacco';
    final lines = <XeroLine>[];

    final items = [...?lineItems[r.id]]..sort((a, b) => b.grossAmount.compareTo(a.grossAmount));
    final products = items.isEmpty
        ? [(desc: 'Account sale ${r.reportNumber}', amount: _round(r.grossTotal))]
        : [
            for (final li in items)
              (
                desc: (li.description ?? '').trim().isNotEmpty
                    ? li.description!.trim()
                    : [r.category[0].toUpperCase() + r.category.substring(1), li.subcategory, li.klass].whereType<String>().join(' '),
                amount: _round(li.grossAmount),
              ),
          ];
    if (tobacco) {
      // 15% on each line, the cents left over on the biggest so the VAT is the invoice's.
      final each = [for (final p in products) _round(p.amount * 0.15)];
      final rest = each.skip(1).fold(0.0, (s, v) => s + v);
      for (var i = 0; i < products.length; i++) {
        lines.add(XeroLine(products[i].desc, products[i].amount, account, kStandardSales, i == 0 ? _round((r.vatOnSales ?? 0) - rest) : each[i]));
      }
    } else {
      for (final p in products) {
        lines.add(XeroLine(p.desc, p.amount, account, kZeroRated));
      }
    }

    final ded = [...?deductions[r.id]]..sort((a, b) => a.ord.compareTo(b.ord));
    final costs = ded.where((d) => !d.isPallets).toList();
    for (final d in costs) {
      lines.add(XeroLine(d.label, -_round(d.amount), xeroDeductionAccount(d.label), d.vat == 0 ? kNoVat : kStandardPurchases, d.vat == 0 ? null : -_round(d.vat)));
    }
    if (costs.isEmpty && (r.commissionBeforeVat != 0 || r.vat != 0)) {
      lines.add(XeroLine('Commission and charges (account sale ${r.reportNumber})', -_round(r.commissionBeforeVat), '3490/000',
          r.vat == 0 ? kNoVat : kStandardPurchases, r.vat == 0 ? null : -_round(r.vat)));
    }
    final due = customer?.paidBy(r.reportDate) ?? _isoAdd(r.reportDate, 7);
    out.add(XeroInvoice(
      report: r,
      contact: contact,
      number: number,
      dueDate: due,
      lines: lines,
      deductionsByLine: costs.isNotEmpty || (r.commissionBeforeVat == 0 && r.vat == 0),
    ));
    // Pallets the buyer paid for (Green Network's pallet invoice): an invoice of their own.
    for (final (n, d) in ded.where((d) => d.isPallets).indexed) {
      out.add(XeroInvoice(
        report: r,
        contact: contact,
        number: palletInvoiceNumber(d.label) ?? '$number-PAL${n == 0 ? '' : n + 1}',
        dueDate: due,
        lines: [XeroLine(d.label, -_round(d.amount), '4280/000', d.vat == 0 ? kNoVat : kStandardSales, d.vat == 0 ? null : -_round(d.vat))],
        deductionsByLine: true,
        reference: 'Pallets with account sale ${r.reportNumber}',
      ));
    }
  }
  return out;
}

/// The invoices as Xero's sales invoice CSV (import Tax Exclusive).
List<List<String>> xeroInvoiceRows(List<XeroInvoice> invoices) {
  final i = {for (var k = 0; k < kXeroInvoiceHeader.length; k++) kXeroInvoiceHeader[k]: k};
  return [
    kXeroInvoiceHeader,
    for (final inv in invoices)
      for (final l in inv.lines)
        (List.filled(kXeroInvoiceHeader.length, '')
          ..[i['*ContactName']!] = inv.contact
          ..[i['*InvoiceNumber']!] = inv.number
          ..[i['Reference']!] = inv.reference
          ..[i['*InvoiceDate']!] = _xeroDate(inv.report.reportDate)
          ..[i['*DueDate']!] = _xeroDate(inv.dueDate)
          ..[i['*Description']!] = l.description
          ..[i['*Quantity']!] = '1'
          ..[i['*UnitAmount']!] = xeroMoney(l.amount)
          ..[i['*AccountCode']!] = l.account
          ..[i['*TaxType']!] = l.taxType
          ..[i['TaxAmount']!] = l.tax == null ? '' : xeroMoney(l.tax!)
          ..[i['Currency']!] = 'ZAR'),
  ];
}

const kXeroContactHeader = [
  '*ContactName', 'AccountNumber', 'EmailAddress', 'FirstName', 'LastName', 'POAttentionTo', 'POAddressLine1', 'POAddressLine2',
  'POAddressLine3', 'POAddressLine4', 'POCity', 'PORegion', 'POPostalCode', 'POCountry', 'SAAttentionTo', 'SAAddressLine1',
  'SAAddressLine2', 'SAAddressLine3', 'SAAddressLine4', 'SACity', 'SARegion', 'SAPostalCode', 'SACountry', 'PhoneNumber',
  'FaxNumber', 'MobileNumber', 'DDINumber', 'SkypeName', 'BankAccountName', 'BankAccountNumber', 'BankAccountParticulars',
  'TaxNumber', 'AccountsReceivableTaxCodeName', 'AccountsPayableTaxCodeName', 'Website', 'LegalName', 'Discount',
  'CompanyNumber', 'DueDateBillDay', 'DueDateBillTerm', 'DueDateSalesDay', 'DueDateSalesTerm', 'SalesAccount',
  'PurchasesAccount', 'TrackingName1', 'SalesTrackingOption1', 'PurchasesTrackingOption1', 'TrackingName2',
  'SalesTrackingOption2', 'PurchasesTrackingOption2', 'BrandingTheme', 'DefaultTaxBills', 'DefaultTaxSales',
  'Person1FirstName', 'Person1LastName', 'Person1Email', 'Person1IncludeInEmail', 'Person2FirstName', 'Person2LastName',
  'Person2Email', 'Person2IncludeInEmail', 'Person3FirstName', 'Person3LastName', 'Person3Email', 'Person3IncludeInEmail',
  'Person4FirstName', 'Person4LastName', 'Person4Email', 'Person4IncludeInEmail', 'Person5FirstName', 'Person5LastName',
  'Person5Email', 'Person5IncludeInEmail',
];

List<String> _contactRow(Map<String, String> values) {
  final row = List.filled(kXeroContactHeader.length, '');
  values.forEach((k, v) => row[kXeroContactHeader.indexOf(k)] = v);
  return row;
}

String _t(String? s) => (s ?? '').trim();

/// Sales > Customers as Xero contacts: name, Nanini's account number with
/// the agent, and the contact person of the market agent with its name
/// (Packaging). No email: the hub keeps where account sales come from.
List<List<String>> xeroCustomerRows(List<Customer> customers, List<MarketAgent> recipients) {
  final attention = {for (final r in recipients) if (_t(r.attention).isNotEmpty) r.name.trim().toLowerCase(): _t(r.attention)};
  final sorted = [...customers]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return [
    kXeroContactHeader,
    for (final c in sorted)
      _contactRow({
        '*ContactName': c.name.trim(),
        'AccountNumber': _t(c.accountNo),
        'POAttentionTo': attention[c.name.trim().toLowerCase()] ?? '',
      }),
  ];
}

/// The suppliers as Xero contacts: contact, phone, email, address, VAT
/// number, bank details and payment terms.
List<List<String>> xeroSupplierRows(List<Supplier> suppliers) {
  final sorted = [...suppliers]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return [
    kXeroContactHeader,
    for (final s in sorted)
      () {
        final address = [for (final l in _t(s.address).split(RegExp(r'[\n,]+'))) if (l.trim().isNotEmpty) l.trim()];
        return _contactRow({
          '*ContactName': s.name.trim(),
          'AccountNumber': _t(s.accountNo),
          'EmailAddress': _t(s.email),
          'POAttentionTo': _t(s.contact),
          'PhoneNumber': _t(s.phone),
          for (var i = 0; i < 3 && i < address.length; i++) 'POAddressLine${i + 1}': address[i],
          if (address.length > 3) 'POAddressLine4': address.skip(3).join(', '),
          if (address.isNotEmpty) 'POCountry': 'South Africa',
          'BankAccountName': _t(s.bankAccountHolder),
          'BankAccountNumber': _t(s.bankAccountNo),
          'BankAccountParticulars': [
            if (_t(s.bankName).isNotEmpty) _t(s.bankName),
            if (_t(s.bankBranchCode).isNotEmpty) 'branch ${_t(s.bankBranchCode)}',
            if (_t(s.paymentReference).isNotEmpty) 'ref ${_t(s.paymentReference)}',
          ].join(' '),
          'TaxNumber': _t(s.vatNo),
          'DueDateBillDay': '${s.termsDays}',
          'DueDateBillTerm': s.termsKind == PaymentTerms.daysFromStatement ? 'DAYSAFTERBILLMONTH' : 'DAYSAFTERBILLDATE',
        });
      }(),
  ];
}

// ---------------------------------------------------------------------------
// Supplier invoices as Xero bills
// ---------------------------------------------------------------------------

const kXeroBillHeader = [
  '*ContactName', 'EmailAddress', 'POAddressLine1', 'POAddressLine2', 'POAddressLine3', 'POAddressLine4', 'POCity', 'PORegion',
  'POPostalCode', 'POCountry', '*InvoiceNumber', '*InvoiceDate', '*DueDate', 'Total', 'InventoryItemCode', 'Description',
  '*Quantity', '*UnitAmount', '*AccountCode', '*TaxType', 'TaxAmount', 'TrackingName1', 'TrackingOption1', 'TrackingName2',
  'TrackingOption2', 'Currency',
];

const kCapitalPurchases = 'Standard Rate Purchases - Capital Goods (15%)';

/// Where lines without an account go when saved anyway (Xero's chart:
/// Suspense Account), to be put right in Xero.
const kXeroSuspense = '9990/000';

/// A fixed asset account (land, buildings, machinery, furniture, computers,
/// vehicles): its VAT is on capital goods.
bool xeroFixedAsset(String account) => RegExp(r'^(55\d\d|6100)/').hasMatch(account);

/// A supplier's invoice, credit note (minus) or bill as a Xero bill.
class XeroBill {
  XeroBill({required this.supplier, required this.doc, required this.number, required this.dueDate, required this.lines});
  final Supplier supplier;
  final SupplierDoc doc;
  final String number;
  final String dueDate;
  final List<PurchaseLine> lines;
  double get total => _round(lines.fold(0.0, (s, l) => s + l.incl));
}

/// The purchases (Expenses > Purchases, each line against its account) as
/// Xero bills: one per document, from Xero's conversion date on (what was
/// owed before is in Xero's opening balances, so the earlier bills' charges
/// paid since aren't).
List<XeroBill> xeroBills(List<PurchaseLine> lines) {
  final byDoc = <String, List<PurchaseLine>>{};
  for (final l in lines) {
    if (l.doc.date.compareTo(kXeroFrom) < 0) continue;
    if (l.line == null && l.fromStatement && (l.description ?? '').endsWith('(VAT on the amount paid)')) continue;
    (byDoc[l.doc.id] ??= []).add(l);
  }
  final out = <XeroBill>[];
  for (final ls in byDoc.values) {
    final d = ls.first.doc;
    final s = ls.first.supplier;
    final ref = (d.reference ?? '').trim();
    out.add(XeroBill(
      supplier: s,
      doc: d,
      number: ref.isNotEmpty ? ref : '${docKindLabel(d.kind)} ${_xeroDate(d.date)}',
      dueDate: d.dueDate ?? s.dueDateFor(d.date),
      lines: ls,
    ));
  }
  out.sort((a, b) => '${a.doc.date}${a.supplier.name.toLowerCase()}${a.number}'.compareTo('${b.doc.date}${b.supplier.name.toLowerCase()}${b.number}'));
  return out;
}

/// The tax rate of a purchase line: 15% (on capital goods for a fixed
/// asset) with its VAT exactly, else No VAT -- also when its VAT wasn't read.
(String, double?) xeroBillTax(PurchaseLine l) {
  final vat = l.vat;
  if (vat == null || vat.abs() < 0.005) return (kNoVat, null);
  return (xeroFixedAsset(l.account ?? '') ? kCapitalPurchases : kStandardPurchases, _round(vat));
}

/// One Xero line of a purchase line: (description, excl, account, tax type,
/// VAT). A line whose VAT isn't 15% of it (a whole Omnia invoice: zero-rated
/// fertilizer with 15% on its transport) becomes two: the part with VAT
/// (its VAT / 15%) and the zero-rated rest.
List<(String, double, String, String, double?)> xeroBillLineParts(PurchaseLine l, String description, String account) {
  final (taxType, tax) = xeroBillTax(l);
  if (tax != null && (tax - l.excl * 0.15).abs() > 1) {
    final withVat = _round(tax / 0.15);
    final rest = _round(l.excl - withVat);
    if (rest.abs() >= 0.01 && rest.sign == l.excl.sign) {
      return [
        ('$description (part with VAT)', withVat, account, taxType, tax),
        ('$description (zero-rated part)', rest, account, kNoVat, null),
      ];
    }
  }
  return [(description, l.excl, account, taxType, tax)];
}

/// The bills as Xero's bills CSV (import Tax Exclusive); a line without an
/// account on [fallbackAccount].
List<List<String>> xeroBillRows(List<XeroBill> bills, {String? fallbackAccount}) {
  final i = {for (var k = 0; k < kXeroBillHeader.length; k++) kXeroBillHeader[k]: k};
  return [
    kXeroBillHeader,
    for (final b in bills)
      for (final l in b.lines)
        for (final (description, excl, account, taxType, tax) in xeroBillLineParts(
            l,
            (l.description ?? '').trim().isNotEmpty ? l.description!.trim() : docKindLabel(b.doc.kind),
            (l.account ?? '').isNotEmpty ? l.account! : (fallbackAccount ?? '')))
          List.filled(kXeroBillHeader.length, '')
            ..[i['*ContactName']!] = b.supplier.name.trim()
            ..[i['*InvoiceNumber']!] = b.number
            ..[i['*InvoiceDate']!] = _xeroDate(b.doc.date)
            ..[i['*DueDate']!] = _xeroDate(b.dueDate)
            ..[i['Description']!] = description
            ..[i['*Quantity']!] = '1'
            ..[i['*UnitAmount']!] = xeroMoney(excl)
            ..[i['*AccountCode']!] = account
            ..[i['*TaxType']!] = taxType
            ..[i['TaxAmount']!] = tax == null ? '' : xeroMoney(tax)
            ..[i['Currency']!] = 'ZAR',
  ];
}

/// Already sent to Xero (docs/sql/xero_sent.sql): when, and the total sent
/// (null when marked by hand from Xero's own list -- then not compared).
class XeroSent {
  const XeroSent(this.at, this.total);
  final String at;
  final double? total;

  factory XeroSent.fromJson(Map<String, dynamic> j) => XeroSent(j['xero_sent_at'] as String, (j['xero_sent_total'] as num?)?.toDouble());
}

/// [items] by their document ([idOf]; an account sale can give two Xero
/// invoices, its pallets on their own): never sent ([fresh]), sent but with
/// another total now ([changed] -- to fix in Xero by hand, not to send
/// again) and how many documents were sent already, unchanged.
({List<T> fresh, List<T> changed, int alreadySent}) xeroNotSentYet<T>(
    List<T> items, String Function(T) idOf, double Function(T) totalOf, Map<String, XeroSent> sent) {
  final totals = xeroTotalsByDoc(items, idOf, totalOf);
  final fresh = <T>[], changed = <T>[];
  final already = <String>{};
  for (final i in items) {
    final s = sent[idOf(i)];
    if (s == null) {
      fresh.add(i);
    } else if (s.total != null && (s.total! - totals[idOf(i)]!).abs() > 0.005) {
      changed.add(i);
    } else {
      already.add(idOf(i));
    }
  }
  return (fresh: fresh, changed: changed, alreadySent: already.length);
}

/// Each document's total over its Xero invoices or bills ([idOf] its id).
Map<String, double> xeroTotalsByDoc<T>(List<T> items, String Function(T) idOf, double Function(T) totalOf) {
  final out = <String, double>{};
  for (final i in items) {
    out[idOf(i)] = _round((out[idOf(i)] ?? 0) + totalOf(i));
  }
  return out;
}

/// A customer's payment (its payment summary) to match in Xero's bank
/// reconciliation: the receipt and the invoices -- its account sales -- to
/// tick in Find & Match, each with what it paid, and whether that invoice is
/// in Xero yet (sent from the hub).
class XeroPaymentToMatch {
  XeroPaymentToMatch({required this.payment, required this.customer, required this.invoices});
  final CustomerPayment payment;
  final String customer;
  final List<({String number, double nett, double loans, bool inXero})> invoices;

  /// When it was in the bank, else the payment summary's date.
  String get date => payment.bankDate ?? payment.date;
  bool get allInXero => invoices.every((i) => i.inXero);
}

/// The payment summaries in the bank (or dated) [from] to [to] -- one
/// customer's when [customerId] -- newest first, each with the invoices to
/// tick in Xero; [sentReportNumbers]: the account sales already sent to Xero.
List<XeroPaymentToMatch> xeroPaymentsToMatch({
  required List<CustomerPayment> payments,
  required List<Customer> customers,
  required Set<String> sentReportNumbers,
  required String from,
  required String to,
  String? customerId,
}) {
  final names = {for (final c in customers) c.id: c.name};
  final out = <XeroPaymentToMatch>[];
  for (final p in payments) {
    final day = p.bankDate ?? p.date;
    if (day.compareTo(from) < 0 || day.compareTo(to) > 0) continue;
    if (customerId != null && p.customerId != customerId) continue;
    out.add(XeroPaymentToMatch(
      payment: p,
      customer: names[p.customerId] ?? 'Unknown customer',
      invoices: [
        for (final l in p.lines)
          (number: l.reportNumber.trim(), nett: l.nett, loans: l.loans, inXero: sentReportNumbers.contains(l.reportNumber.trim())),
      ],
    ));
  }
  out.sort((a, b) => '${b.date}${b.customer}'.compareTo('${a.date}${a.customer}'));
  return out;
}
