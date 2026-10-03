/// A supplier the farm buys from. [openingBalance] is what was owed on
/// [openingDate] when the supplier was added (so older invoices needn't be
/// captured); everything after comes from invoices, credit notes and
/// payments.
class Supplier {
  Supplier({
    required this.id,
    required this.name,
    this.accountNo,
    this.contact,
    this.phone,
    this.email,
    this.openingBalance = 0,
    this.openingDate,
    this.bankName,
    this.bankAccountHolder,
    this.bankAccountNo,
    this.bankBranchCode,
    this.paymentReference,
    this.termsKind = PaymentTerms.daysFromInvoice,
    this.termsDays = 30,
    this.address,
    this.vatNo,
    this.category,
    this.popEmail,
    this.vatAccount,
  });

  final String id;
  final String name;
  final String? accountNo;
  final String? contact;
  final String? phone;
  final String? email;
  final double openingBalance;
  final String? openingDate;

  /// Where to pay them.
  final String? bankName;
  final String? bankAccountHolder;
  final String? bankAccountNo;
  final String? bankBranchCode;

  /// The reference to put on a payment (often our account number).
  final String? paymentReference;

  /// When an invoice must be paid: [termsDays] after the invoice, or after
  /// the end of the invoice's month (the statement).
  final PaymentTerms termsKind;
  final int termsDays;

  final String? address;
  final String? vatNo;

  /// What they supply / the ledger account, e.g. "3740 - Fertiliser".
  final String? category;

  /// Where to send proof of payment.
  final String? popEmail;

  /// The contra account for invoice lines with VAT on them (Omnia: the
  /// transport, 4800; its zero-rated fertilizer goes to the category's).
  final String? vatAccount;

  bool get hasBanking => [bankName, bankAccountHolder, bankAccountNo, bankBranchCode].any((v) => (v ?? '').trim().isNotEmpty);

  String get termsLabel => switch (termsKind) {
        PaymentTerms.daysFromInvoice => termsDays == 0 ? 'On invoice (cash)' : '$termsDays days from invoice',
        PaymentTerms.daysFromStatement => '$termsDays days from statement (month end)',
      };

  /// The day an invoice of [invoiceDate] (yyyy-MM-dd) must be paid by.
  String dueDateFor(String invoiceDate) {
    final d = DateTime.parse(invoiceDate);
    final DateTime due;
    if (termsKind == PaymentTerms.daysFromStatement && termsDays > 0 && termsDays % 30 == 0) {
      // 30 days from statement = the end of next month (Omnia: September's by 31 October).
      due = DateTime(d.year, d.month + 1 + termsDays ~/ 30, 0);
    } else {
      final from = termsKind == PaymentTerms.daysFromStatement ? DateTime(d.year, d.month + 1, 0) : d;
      due = from.add(Duration(days: termsDays));
    }
    return '${due.year.toString().padLeft(4, '0')}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
  }

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        accountNo: j['account_no'] as String?,
        contact: j['contact'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        openingBalance: (j['opening_balance'] as num?)?.toDouble() ?? 0,
        openingDate: j['opening_date'] as String?,
        bankName: j['bank_name'] as String?,
        bankAccountHolder: j['bank_account_holder'] as String?,
        bankAccountNo: j['bank_account_no'] as String?,
        bankBranchCode: j['bank_branch_code'] as String?,
        paymentReference: j['payment_reference'] as String?,
        termsKind: j['terms_kind'] == 'statement' ? PaymentTerms.daysFromStatement : PaymentTerms.daysFromInvoice,
        termsDays: (j['terms_days'] as num?)?.toInt() ?? 30,
        address: j['address'] as String?,
        vatNo: j['vat_no'] as String?,
        category: j['category'] as String?,
        vatAccount: j['vat_gl_account'] as String?,
        popEmail: j['pop_email'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'account_no': _blank(accountNo),
        'contact': _blank(contact),
        'phone': _blank(phone),
        'email': _blank(email),
        'opening_balance': openingBalance,
        'opening_date': openingDate,
        'bank_name': _blank(bankName),
        'bank_account_holder': _blank(bankAccountHolder),
        'bank_account_no': _blank(bankAccountNo),
        'bank_branch_code': _blank(bankBranchCode),
        'payment_reference': _blank(paymentReference),
        'terms_kind': termsKind == PaymentTerms.daysFromStatement ? 'statement' : 'invoice',
        'terms_days': termsDays,
        'address': _blank(address),
        'vat_no': _blank(vatNo),
        'category': _blank(category),
        // (docs/sql/suppliers_purchases.sql; sent only when set)
        if (_blank(vatAccount) != null) 'vat_gl_account': _blank(vatAccount),
        'pop_email': _blank(popEmail),
      };
}

/// How a supplier's invoices fall due.
enum PaymentTerms { daysFromInvoice, daysFromStatement }

/// Part of what's due, payable by [dueDate].
class PayableBy {
  PayableBy(this.dueDate, this.amount, this.invoices);
  final String dueDate;
  final double amount;

  /// The invoices (numbers) still open in it.
  final List<String> invoices;
}

String? _blank(String? s) => (s ?? '').trim().isEmpty ? null : s!.trim();

/// What a supplier document is: an invoice (we owe more), a credit note (we
/// owe less) or a statement (the supplier's balance, to reconcile against).
enum SupplierDocKind { invoice, creditNote, statement }

String docKindKey(SupplierDocKind k) => switch (k) {
      SupplierDocKind.invoice => 'invoice',
      SupplierDocKind.creditNote => 'credit_note',
      SupplierDocKind.statement => 'statement',
    };

SupplierDocKind docKindFrom(String? s) => switch (s) {
      'credit_note' => SupplierDocKind.creditNote,
      'statement' => SupplierDocKind.statement,
      _ => SupplierDocKind.invoice,
    };

String docKindLabel(SupplierDocKind k) => switch (k) {
      SupplierDocKind.invoice => 'Invoice',
      SupplierDocKind.creditNote => 'Credit note',
      SupplierDocKind.statement => 'Statement',
    };

/// An uploaded invoice, credit note or statement. [amount] is the invoice
/// or credit note total, or the statement's closing balance. [filePath] is
/// the PDF in storage (bucket "supplier-docs").
class SupplierDoc {
  SupplierDoc({
    required this.id,
    required this.supplierId,
    required this.kind,
    required this.date,
    required this.amount,
    this.reference,
    this.filePath,
    this.fileName,
    this.notes,
    this.toCheck = false,
    this.emailFrom,
    this.emailSubject,
    this.emailDate,
    this.dueDate,
    this.overdueAmount,
    this.vatAmount,
    this.purchasesAmount,
    this.description,
    this.broughtForward,
    this.paymentsReceived = const [],
    this.billDetails,
  });

  final String id;
  final String supplierId;
  final SupplierDocKind kind;
  final String date;
  final double amount;
  final String? reference;
  final String? filePath;
  final String? fileName;
  final String? notes;

  /// Brought in from email by the office PC: not counted until confirmed.
  final bool toCheck;
  final String? emailFrom;
  final String? emailSubject;
  final String? emailDate;

  /// The due date printed on the document (e.g. Eskom's); else the
  /// supplier's terms decide.
  final String? dueDate;

  /// On a statement: the part already due (VKB's "reeds betaalbaar"); the
  /// rest is due by [dueDate].
  final double? overdueAmount;

  /// The VAT on it, as read from the PDF.
  final double? vatAmount;

  /// On a bill that's a statement (Eskom): this bill's purchases incl. VAT.
  final double? purchasesAmount;

  /// A few words on what was bought.
  final String? description;

  /// On a bill that's a statement (Eskom): its account summary -- the
  /// balance brought forward when it was made out, and the payments
  /// received since (date may be null).
  final double? broughtForward;
  final List<({String? date, double amount})> paymentsReceived;

  /// An Eskom bill's charges: usage per kWh and fixed per day / kVA.
  final BillDetails? billDetails;

  /// An invoice and statement in one (Eskom): this month's charges are the
  /// invoice, the amount due is the balance.
  bool get isBill => kind == SupplierDocKind.statement && purchasesAmount != null;

  factory SupplierDoc.fromJson(Map<String, dynamic> j) => SupplierDoc(
        id: j['id'] as String,
        supplierId: j['supplier_id'] as String,
        kind: docKindFrom(j['kind'] as String?),
        date: j['doc_date'] as String,
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        reference: j['reference'] as String?,
        filePath: j['file_path'] as String?,
        fileName: j['file_name'] as String?,
        notes: j['notes'] as String?,
        toCheck: j['status'] == 'to_check',
        emailFrom: j['email_from'] as String?,
        emailSubject: j['email_subject'] as String?,
        emailDate: j['email_date'] as String?,
        dueDate: j['due_date'] as String?,
        overdueAmount: (j['overdue_amount'] as num?)?.toDouble(),
        vatAmount: (j['vat_amount'] as num?)?.toDouble(),
        purchasesAmount: (j['purchases_amount'] as num?)?.toDouble(),
        description: j['description'] as String?,
        broughtForward: (j['brought_forward'] as num?)?.toDouble(),
        paymentsReceived: [
          for (final p in (j['payments_received'] as List?) ?? const [])
            if (p is Map && p['amount'] is num) (date: p['date'] as String?, amount: (p['amount'] as num).toDouble()),
        ],
        billDetails: j['bill_details'] is Map ? BillDetails.fromJson((j['bill_details'] as Map).cast<String, dynamic>()) : null,
      );
}

/// A payment to a supplier, typed in by hand.
class SupplierPayment {
  SupplierPayment({required this.id, required this.supplierId, required this.date, required this.amount, this.reference, this.notes});

  final String id;
  final String supplierId;
  final String date;
  final double amount;
  final String? reference;
  final String? notes;

  factory SupplierPayment.fromJson(Map<String, dynamic> j) => SupplierPayment(
        id: j['id'] as String,
        supplierId: j['supplier_id'] as String,
        date: j['pay_date'] as String,
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        reference: j['reference'] as String?,
        notes: j['notes'] as String?,
      );
}

/// What a line of the account is.
enum LedgerKind { opening, invoice, creditNote, payment, statement }

/// One line of a supplier's account (its "GL account"), oldest first:
/// + what we owe more (opening balance, invoice, charges on a statement),
/// − what we owe less (credit note, payment).
class LedgerLine {
  LedgerLine({
    required this.date,
    required this.kind,
    required this.label,
    required this.amount,
    required this.balance,
    this.doc,
    this.payment,
  });
  final String date;
  final LedgerKind kind;
  final String label;

  /// Signed: positive adds to what's owed. On a statement line: the
  /// statement's balance less ours before it -- the charges on it (interest,
  /// purchases without an invoice here) or the difference to follow up.
  final double amount;

  /// What's owed after this line (on a statement line: the statement's).
  final double balance;
  final SupplierDoc? doc;
  final SupplierPayment? payment;
}

/// A statement checked against our own account on its date.
class StatementCheck {
  StatementCheck({required this.statement, required this.ours, required this.currentDueDate});
  final SupplierDoc statement;

  /// What we have owing just before the statement (the previous statement
  /// plus invoices, less credit notes and payments since); null when there's
  /// nothing of ours to check it against (no invoices captured for the
  /// supplier, or its first statement).
  final double? ours;

  /// When the statement's current part is due.
  final String currentDueDate;
  bool get checked => ours != null;
  double get difference => ours == null ? 0 : _r(statement.amount - ours!);
  bool get matches => ours != null && difference.abs() < 0.01;
  double get overdue => (statement.overdueAmount ?? 0).clamp(0, statement.amount > 0 ? statement.amount : 0).toDouble();
  double get current => _r(statement.amount - overdue);
}

/// A supplier's account for a period: the opening balance, what happened in
/// it, and the closing balance (what was due at its end).
class PeriodAccount {
  PeriodAccount({required this.from, required this.to, required this.opening, required this.lines, required this.closing});
  final String from;
  final String to;
  final double opening;
  final List<LedgerLine> lines;
  final double closing;

  double _sum(LedgerKind k) => _r(lines.where((l) => l.kind == k).fold<double>(0, (s, l) => s + l.amount));
  double get invoices => _sum(LedgerKind.invoice) + _sum(LedgerKind.opening);
  double get creditNotes => -_sum(LedgerKind.creditNote);
  double get payments => -_sum(LedgerKind.payment);

  /// Statement balances less ours: charges on statements (interest,
  /// purchases without an invoice here) or differences.
  double get statementCharges => _sum(LedgerKind.statement);
}

/// A supplier's account worked out from its documents and payments.
///
/// Every confirmed statement is a line of the account: from it on, the
/// balance is the statement's (the supplier's own figure, interest and
/// all), and invoices, credit notes and payments after it are added on.
/// With invoices captured, the statement line shows the difference to
/// follow up; without (statements or Eskom's bills only), it's the charges
/// on that statement. What's due now is the latest statement plus what came
/// after it.
class SupplierAccount {
  SupplierAccount(this.supplier, Iterable<SupplierDoc> docs, Iterable<SupplierPayment> payments)
      : docs = docs.where((d) => d.supplierId == supplier.id && !d.toCheck).toList(),
        toCheck = docs.where((d) => d.supplierId == supplier.id && d.toCheck).toList()..sort((a, b) => b.date.compareTo(a.date)),
        payments = payments.where((p) => p.supplierId == supplier.id).toList();

  final Supplier supplier;

  /// Confirmed documents: these make up the account.
  final List<SupplierDoc> docs;

  /// From email, still to be checked and confirmed (newest first).
  final List<SupplierDoc> toCheck;
  final List<SupplierPayment> payments;

  /// Confirmed statements, newest first.
  late final List<SupplierDoc> _statements =
      docs.where((d) => d.kind == SupplierDocKind.statement).toList()..sort((a, b) => b.date.compareTo(a.date));

  /// The newest statement: what's owed starts from it.
  SupplierDoc? get latestStatement => _statements.firstOrNull;

  /// Invoices are captured for this supplier: its statements can be checked.
  late final bool _keepsInvoices = docs.any((d) => d.kind == SupplierDocKind.invoice);

  bool _after(String date) => latestStatement == null || date.compareTo(latestStatement!.date) > 0;

  /// The whole account, oldest first, with the balance after each line.
  /// On a day: invoices and credit notes, then payments, then the statement.
  late final List<LedgerLine> ledger = _buildLedger();

  /// What we had owing just before each statement (by statement id).
  final Map<String, double> _beforeStatement = {};

  List<LedgerLine> _buildLedger() {
    String ref(SupplierDoc d) => (d.reference ?? '').isEmpty ? '' : ' ${d.reference}';
    // Bills (Eskom, invoice and statement in one): the account starts with
    // the first bill's balance brought forward, on the day of the first
    // payment it lists (earlier payments belong to bills not here).
    final bills = docs.where((d) => d.isBill).toList()..sort((a, b) => a.date.compareTo(b.date));
    String? billStart;
    var billOpening = 0.0;
    if (bills.isNotEmpty) {
      final first = bills.first;
      final paid = first.paymentsReceived;
      billStart = ([first.date, for (final p in paid) if (p.date != null) p.date!]..sort()).first;
      billOpening = first.broughtForward ?? _r(first.amount - first.purchasesAmount! + paid.fold<double>(0, (t, p) => t + p.amount));
    }
    final items = <(String, int, SupplierDoc?, SupplierPayment?)>[
      if (billStart != null) (billStart, -1, null, null),
      if (billStart == null && supplier.openingBalance != 0) (supplier.openingDate ?? '0000-00-00', 0, null, null),
      for (final d in docs) (d.date, d.kind == SupplierDocKind.statement ? 3 : 1, d, null),
      for (final p in payments)
        if (billStart == null || p.date.compareTo(billStart) >= 0) (p.date, 2, null, p),
    ]..sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
    var b = 0.0;
    var anyBefore = false;
    final out = <LedgerLine>[];
    for (final (date, order, d, p) in items) {
      if (order == -1) {
        out.add(LedgerLine(
            date: date, kind: LedgerKind.opening, label: 'Balance brought forward (bill ${bills.first.date})', amount: billOpening, balance: billOpening));
      } else if (d == null && p == null) {
        out.add(LedgerLine(
            date: supplier.openingDate ?? '', kind: LedgerKind.opening, label: 'Opening balance', amount: supplier.openingBalance, balance: _r(b + supplier.openingBalance)));
      } else if (p != null) {
        out.add(LedgerLine(
            date: date, kind: LedgerKind.payment, label: 'Payment${(p.reference ?? '').isEmpty ? '' : ' ${p.reference}'}', amount: -p.amount, balance: _r(b - p.amount), payment: p));
      } else if (d!.isBill) {
        // This month's charges are the invoice; the bill's amount due checks it.
        final after = _r(b + d.purchasesAmount!);
        _beforeStatement[d.id] = after;
        out.add(LedgerLine(
            date: date,
            kind: LedgerKind.invoice,
            label: '${d.purchasesAmount! < 0 ? 'Credit (rebill)' : 'Invoice'}${ref(d)}',
            amount: d.purchasesAmount!,
            balance: after,
            doc: d));
        final diff = _r(d.amount - after);
        if (diff.abs() >= 0.01) {
          out.add(LedgerLine(date: date, kind: LedgerKind.statement, label: 'Difference to the bill\'s amount due', amount: diff, balance: d.amount, doc: d));
        }
      } else if (d.kind == SupplierDocKind.statement) {
        _beforeStatement[d.id] = b;
        final diff = _r(d.amount - b);
        final label = !anyBefore
            ? 'Balance per statement'
            : _keepsInvoices
                ? (diff.abs() < 0.01 ? 'Statement -- matches' : 'Difference to statement')
                : 'Charges per statement';
        out.add(LedgerLine(date: date, kind: LedgerKind.statement, label: label, amount: diff, balance: d.amount, doc: d));
      } else {
        final amount = d.kind == SupplierDocKind.invoice ? d.amount : -d.amount;
        out.add(LedgerLine(
            date: date,
            kind: d.kind == SupplierDocKind.invoice ? LedgerKind.invoice : LedgerKind.creditNote,
            label: '${docKindLabel(d.kind)}${ref(d)}',
            amount: amount,
            balance: _r(b + amount),
            doc: d));
      }
      b = out.last.balance;
      anyBefore = true;
    }
    return out;
  }

  /// What's owed at the end of [upTo] (yyyy-MM-dd), or now.
  double balanceAt([String? upTo]) {
    var b = 0.0;
    for (final l in ledger) {
      if (upTo != null && l.date.compareTo(upTo) > 0) break;
      b = l.balance;
    }
    return b;
  }

  /// Amount due now.
  double get due => balanceAt();

  /// The account from [from] to [to] (yyyy-MM-dd, both included).
  PeriodAccount period(String from, String to) {
    final before = DateTime.parse(from).subtract(const Duration(days: 1));
    final dayBefore = '${before.year.toString().padLeft(4, '0')}-${before.month.toString().padLeft(2, '0')}-${before.day.toString().padLeft(2, '0')}';
    return PeriodAccount(
      from: from,
      to: to,
      opening: balanceAt(dayBefore),
      lines: [for (final l in ledger) if (l.date.compareTo(from) >= 0 && l.date.compareTo(to) <= 0) l],
      closing: balanceAt(to),
    );
  }

  /// When what's due must be paid, earliest first. From the latest
  /// statement: its part already due is due on its date, the rest by its
  /// due date (else the terms); invoices after it by theirs. Payments and
  /// credit notes after it settle the oldest first.
  List<PayableBy> get payable {
    final base = latestStatement;
    final check = statements.firstOrNull;
    final opening = supplier.openingBalance != 0 && (base == null || (supplier.openingDate != null && _after(supplier.openingDate!)));
    final owing = <(String date, int order, String due, String label, double amount)>[
      if (check != null && check.overdue > 0) (base!.date, 0, base.date, 'Already due on the statement', check.overdue),
      if (check != null && check.current > 0) (base!.date, 1, check.currentDueDate, 'Statement ${base.date}', check.current),
      if (opening && supplier.openingBalance > 0)
        (supplier.openingDate ?? '0000-00-00', 0, supplier.openingDate ?? '0000-00-00', 'Opening balance', supplier.openingBalance),
      for (final d in docs.where((d) => d.kind == SupplierDocKind.invoice && _after(d.date)))
        (d.date, 2, d.dueDate ?? supplier.dueDateFor(d.date), (d.reference ?? '').isEmpty ? 'Invoice ${d.date}' : d.reference!, d.amount),
    ]..sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
    var paid = payments.where((p) => _after(p.date)).fold<double>(0, (s, p) => s + p.amount) +
        docs.where((d) => d.kind == SupplierDocKind.creditNote && _after(d.date)).fold<double>(0, (s, d) => s + d.amount) +
        (opening && supplier.openingBalance < 0 ? -supplier.openingBalance : 0) +
        (base != null && base.amount < 0 ? -base.amount : 0);
    final byDue = <String, (double, List<String>)>{};
    for (final (_, _, due, label, amount) in owing) {
      final settled = paid >= amount ? amount : paid;
      paid -= settled;
      final open = _r(amount - settled);
      if (open <= 0) continue;
      final cur = byDue[due] ?? (0.0, <String>[]);
      byDue[due] = (_r(cur.$1 + open), [...cur.$2, label]);
    }
    return [for (final e in (byDue.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) PayableBy(e.key, e.value.$1, e.value.$2)];
  }

  /// Each statement (newest first), checked against our account just before
  /// it -- when invoices are captured for the supplier and it isn't the first
  /// line of the account.
  late final List<StatementCheck> statements = [
    for (final s in _statements)
      StatementCheck(
        statement: s,
        ours: () {
          ledger; // builds _beforeStatement
          final line = ledger.firstWhere((l) => l.doc?.id == s.id);
          if (s.isBill) return _beforeStatement[s.id];
          return _keepsInvoices && line.label != 'Balance per statement' ? _beforeStatement[s.id] : null;
        }(),
        currentDueDate: s.dueDate ?? supplier.dueDateFor(s.date),
      ),
  ];
}

double _r(double v) => (v * 100).roundToDouble() / 100;

/// A contra (GL) account purchases are allocated to.
class GlAccount {
  GlAccount({required this.code, required this.name});
  final String code;
  final String name;
  String get label => '$code $name';

  factory GlAccount.fromJson(Map<String, dynamic> j) => GlAccount(code: j['code'] as String, name: j['name'] as String? ?? '');
}

/// A line of an invoice, credit note or bill (negative on a credit note).
class DocLine {
  DocLine({required this.id, required this.docId, required this.lineNo, this.description, this.quantity, required this.excl, this.vat, this.glAccount});
  final String id;
  final String docId;
  final int lineNo;
  final String? description;
  final double? quantity;
  final double excl;
  final double? vat;

  /// Allocated by hand; null: the remembered account for the item, else the supplier's.
  final String? glAccount;

  factory DocLine.fromJson(Map<String, dynamic> j) => DocLine(
        id: j['id'] as String,
        docId: j['doc_id'] as String,
        lineNo: (j['line_no'] as num).toInt(),
        description: j['description'] as String?,
        quantity: (j['quantity'] as num?)?.toDouble(),
        excl: (j['excl_amount'] as num).toDouble(),
        vat: (j['vat_amount'] as num?)?.toDouble(),
        glAccount: j['gl_account'] as String?,
      );
}

/// A remembered allocation: this supplier's item goes to this account.
class GlRule {
  GlRule({required this.supplierId, required this.item, required this.glAccount});
  final String supplierId;
  final String item;
  final String glAccount;

  factory GlRule.fromJson(Map<String, dynamic> j) =>
      GlRule(supplierId: j['supplier_id'] as String, item: j['item'] as String, glAccount: j['gl_account'] as String);
}

/// The key an item is remembered by.
String glItemKey(String? description) => (description ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// The account code in a supplier's category, as in the chart of accounts:
/// "3650 - Electricity & Water" -> 3650/000, "4200/100 Fencing" -> 4200/100.
String? categoryAccount(String? category) {
  final m = RegExp(r'^\s*(\d{4})(?:/(\d{3}))?\b').firstMatch(category ?? '');
  return m == null ? null : '${m.group(1)}/${m.group(2) ?? '000'}';
}

/// How a purchase line got its contra account.
enum GlSource { line, remembered, supplier, none }

/// One line of the purchases report.
class PurchaseLine {
  PurchaseLine({
    required this.supplier,
    required this.doc,
    this.line,
    required this.description,
    required this.excl,
    required this.vat,
    required this.account,
    required this.source,
    this.fromStatement = false,
  });
  final Supplier supplier;
  final SupplierDoc doc;

  /// The stored line; null: the whole document as one line.
  final DocLine? line;
  final String? description;
  final double excl;

  /// Null: not known (no VAT read).
  final double? vat;
  double get incl => _r(excl + (vat ?? 0));
  final String? account;
  final GlSource source;

  /// "Charges per statement" (no invoices kept for the supplier).
  final bool fromStatement;
}

/// The purchases from [from] to [to] (by document date), each line against
/// its contra account.
List<PurchaseLine> purchasesFor(List<SupplierAccount> accounts, List<DocLine> lines, List<GlRule> rules, String from, String to) {
  bool inPeriod(String d) => d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
  final byDoc = <String, List<DocLine>>{};
  for (final l in lines) {
    (byDoc[l.docId] ??= []).add(l);
  }
  final remembered = {for (final r in rules) '${r.supplierId}|${r.item}': r.glAccount};
  final out = <PurchaseLine>[];
  for (final a in accounts) {
    final s = a.supplier;
    (String?, GlSource) accountFor(String? stored, String? description, [double? vat]) {
      if (stored != null) return (stored, GlSource.line);
      final r = remembered['${s.id}|${glItemKey(description)}'];
      if (r != null && glItemKey(description).isNotEmpty) return (r, GlSource.remembered);
      final v = categoryAccount(s.vatAccount);
      if (v != null && vat != null && vat.abs() >= 0.005) return (v, GlSource.supplier);
      final c = categoryAccount(s.category);
      return c != null ? (c, GlSource.supplier) : (null, GlSource.none);
    }

    for (final d in a.docs.where((d) => inPeriod(d.date))) {
      final total = switch (d.kind) {
        SupplierDocKind.invoice => d.amount,
        SupplierDocKind.creditNote => -d.amount,
        SupplierDocKind.statement => d.purchasesAmount,
      };
      if (total == null || total == 0) continue;
      final stored = [...?byDoc[d.id]]..sort((x, y) => x.lineNo.compareTo(y.lineNo));
      final storedTotal = stored.fold<double>(0, (t, l) => t + l.excl + (l.vat ?? 0));
      if (stored.isNotEmpty && (storedTotal - total).abs() < 1) {
        for (final l in stored) {
          final (acc, src) = accountFor(l.glAccount, l.description, l.vat);
          out.add(PurchaseLine(supplier: s, doc: d, line: l, description: l.description ?? d.description, excl: l.excl, vat: l.vat, account: acc, source: src));
        }
      } else {
        // One line: the whole document (lines not read, or the amount changed when confirming).
        final sign = total < 0 ? -1 : 1;
        final vat = d.vatAmount == null ? null : sign * d.vatAmount!.abs();
        final keep = stored.length == 1 ? stored.first : null;
        final (acc, src) = accountFor(keep?.glAccount, d.description, vat);
        out.add(PurchaseLine(supplier: s, doc: d, line: keep, description: d.description, excl: _r(total - (vat ?? 0)), vat: vat, account: acc, source: src));
      }
    }
    // Only statements kept for the supplier: what each statement charged.
    if (!a.docs.any((d) => d.kind == SupplierDocKind.invoice)) {
      for (final l in a.ledger.where((l) => l.label == 'Charges per statement' && inPeriod(l.date) && l.doc?.purchasesAmount == null)) {
        if (l.amount == 0) continue;
        final (acc, src) = accountFor(null, null);
        out.add(PurchaseLine(
            supplier: s, doc: l.doc!, description: 'Charges per statement (less payments, incl. VAT)', excl: l.amount, vat: null, account: acc, source: src, fromStatement: true));
      }
    }
  }
  out.sort((x, y) {
    final c = x.supplier.name.toLowerCase().compareTo(y.supplier.name.toLowerCase());
    if (c != 0) return c;
    final d = x.doc.date.compareTo(y.doc.date);
    return d != 0 ? d : (x.line?.lineNo ?? 0).compareTo(y.line?.lineNo ?? 0);
  });
  return out;
}


/// One charge line of an Eskom bill: usage (per kWh / kvarh) or fixed (per
/// day, or per kVA a month).
class BillCharge {
  BillCharge({required this.description, required this.kind, this.quantity, required this.unit, required this.rate, this.days, required this.amount});
  final String description;

  /// usage, fixed, or adjustment (a rebill correcting earlier bills).
  final String kind;
  bool get usage => kind == 'usage';
  final double? quantity;

  /// kWh, kvarh, day or kVA.
  final String unit;
  final double rate;
  final int? days;
  final double amount;

  factory BillCharge.fromJson(Map<String, dynamic> j) => BillCharge(
        description: j['description'] as String? ?? '',
        kind: j['kind'] as String? ?? 'usage',
        quantity: (j['quantity'] as num?)?.toDouble(),
        unit: j['unit'] as String? ?? '',
        rate: (j['rate'] as num?)?.toDouble() ?? 0,
        days: (j['days'] as num?)?.toInt(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
      );
}

/// What an Eskom bill charged for: the kWh used, the days, the reading
/// period, and each charge.
class BillDetails {
  BillDetails({this.kwh, this.days, this.from, this.to, this.reading, required this.charges});
  final double? kwh;

  /// "estimate" or "actual": an estimated reading is corrected later by a rebill.
  final String? reading;
  bool get estimated => reading == 'estimate';
  final int? days;
  final String? from;
  final String? to;
  final List<BillCharge> charges;

  List<BillCharge> get usage => charges.where((c) => c.usage).toList();
  List<BillCharge> get fixed => charges.where((c) => c.kind == 'fixed').toList();

  /// A rebill's corrections of earlier bills (credit when negative).
  List<BillCharge> get adjustments => charges.where((c) => c.kind == 'adjustment').toList();
  double get adjustmentsTotal => _r(adjustments.fold<double>(0, (t, c) => t + c.amount));
  double get usageTotal => _r(usage.fold<double>(0, (t, c) => t + c.amount));
  double get fixedTotal => _r(fixed.fold<double>(0, (t, c) => t + c.amount));

  /// The per-kWh charges grouped by the kWh they're on: one group per
  /// tariff period (7 704 kWh at the old tariffs, 4 402 at the new) or,
  /// on time-of-use bills, the charges on all the kWh.
  List<(double, List<BillCharge>)> get kwhGroups => _groups(usage.where((c) => c.unit == 'kWh' && c.quantity != null), (c) => c.quantity!);

  /// Usage charges in no group of two or more (time-of-use energy, reactive energy).
  List<BillCharge> get otherUsage => usage.where((c) => !kwhGroups.any((g) => g.$2.length > 1 && g.$2.contains(c))).toList();

  /// The per-day charges grouped by days (one group per tariff period).
  List<(double, List<BillCharge>)> get dayGroups => _groups(fixed.where((c) => c.unit == 'day' && c.days != null), (c) => c.days!.toDouble());
  List<BillCharge> get otherFixed => fixed.where((c) => c.unit != 'day' || c.days == null).toList();

  static List<(double, List<BillCharge>)> _groups(Iterable<BillCharge> cs, double Function(BillCharge) key) {
    final out = <(double, List<BillCharge>)>[];
    for (final c in cs) {
      final i = out.indexWhere((g) => (g.$1 - key(c)).abs() < 0.01);
      if (i < 0) {
        out.add((key(c), [c]));
      } else {
        out[i].$2.add(c);
      }
    }
    return out;
  }

  factory BillDetails.fromJson(Map<String, dynamic> j) => BillDetails(
        kwh: (j['kwh'] as num?)?.toDouble(),
        days: (j['days'] as num?)?.toInt(),
        from: j['from'] as String?,
        to: j['to'] as String?,
        reading: j['reading'] as String?,
        charges: [for (final c in (j['charges'] as List?) ?? const []) if (c is Map) BillCharge.fromJson(c.cast<String, dynamic>())],
      );
}