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

/// One line of a supplier's account, oldest first: + what we owe more
/// (opening balance, invoice), − what we owe less (credit note, payment).
class LedgerLine {
  LedgerLine({required this.date, required this.label, required this.amount, required this.balance, this.doc, this.payment});
  final String date;
  final String label;

  /// Signed: positive adds to what's owed.
  final double amount;

  /// What's owed after this line.
  final double balance;
  final SupplierDoc? doc;
  final SupplierPayment? payment;
}

/// A statement checked against our own account on its date.
class StatementCheck {
  StatementCheck({required this.statement, required this.ours, required this.currentDueDate});
  final SupplierDoc statement;

  /// What we have owing on the statement's date; null when the account is
  /// kept from statements (nothing of ours to check it against).
  final double? ours;

  /// When the statement's current part is due.
  final String currentDueDate;
  bool get checked => ours != null;
  double get difference => ours == null ? 0 : _r(statement.amount - ours!);
  bool get matches => ours != null && difference.abs() < 0.01;
  double get overdue => (statement.overdueAmount ?? 0).clamp(0, statement.amount > 0 ? statement.amount : 0).toDouble();
  double get current => _r(statement.amount - overdue);
}

/// A supplier's account worked out from its documents and payments.
///
/// The latest statement is the balance (the supplier's own figure, with
/// interest and anything else on it); invoices, credit notes and payments
/// after it are added on. Before the first statement -- or with none --
/// the account is the opening balance and what's captured. Invoices up to
/// a statement check it.
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

  /// The newest statement on or before [upTo] (or the newest).
  SupplierDoc? _statementAt(String? upTo) => _statements.where((s) => upTo == null || s.date.compareTo(upTo) <= 0).firstOrNull;

  /// What's owed up to and including [upTo] (yyyy-MM-dd), or now: from the
  /// statement of that time, plus what came after it.
  double balanceAt([String? upTo]) => _balance(upTo, _statementAt(upTo));

  /// Our own figure, without any statement: opening balance + invoices −
  /// credit notes − payments.
  double _capturedAt(String? upTo) => _balance(upTo, null);

  double _balance(String? upTo, SupplierDoc? base) {
    bool counts(String? d) =>
        (d == null ? base == null : (upTo == null || d.compareTo(upTo) <= 0) && (base == null || d.compareTo(base.date) > 0));
    var b = base?.amount ?? 0.0;
    if (supplier.openingDate == null ? base == null : counts(supplier.openingDate)) b += supplier.openingBalance;
    for (final d in docs) {
      if (!counts(d.date)) continue;
      if (d.kind == SupplierDocKind.invoice) b += d.amount;
      if (d.kind == SupplierDocKind.creditNote) b -= d.amount;
    }
    for (final p in payments) {
      if (counts(p.date)) b -= p.amount;
    }
    return _r(b);
  }

  bool _after(String date) => latestStatement == null || date.compareTo(latestStatement!.date) > 0;

  /// Amount due now.
  double get due => balanceAt();

  /// The account, oldest first, with the balance after each line. The
  /// latest statement is a line too: the balance becomes the statement's.
  List<LedgerLine> get ledger {
    final base = latestStatement;
    final items = <(String, int, LedgerLine Function(double))>[
      if (supplier.openingBalance != 0)
        (supplier.openingDate ?? '0000-00-00', 0, (b) => LedgerLine(date: supplier.openingDate ?? '', label: 'Opening balance', amount: supplier.openingBalance, balance: b + supplier.openingBalance)),
      for (final d in docs.where((d) => d.kind != SupplierDocKind.statement))
        (
          d.date,
          1,
          (b) {
            final amount = d.kind == SupplierDocKind.invoice ? d.amount : -d.amount;
            return LedgerLine(
              date: d.date,
              label: '${docKindLabel(d.kind)}${(d.reference ?? '').isEmpty ? '' : ' ${d.reference}'}',
              amount: amount,
              balance: _r(b + amount),
              doc: d,
            );
          }
        ),
      for (final p in payments)
        (p.date, 2, (b) => LedgerLine(date: p.date, label: 'Payment${(p.reference ?? '').isEmpty ? '' : ' ${p.reference}'}', amount: -p.amount, balance: _r(b - p.amount), payment: p)),
      if (base != null)
        (base.date, 3, (b) => LedgerLine(date: base.date, label: 'Balance on statement', amount: _r(base.amount - b), balance: base.amount, doc: base)),
    ]..sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
    var b = 0.0;
    final out = <LedgerLine>[];
    for (final (_, _, make) in items) {
      final line = make(b);
      b = line.balance;
      out.add(line);
    }
    return out;
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

  /// Each statement (newest first) against our own captured account on its
  /// date -- when invoices up to it are captured (else nothing to check).
  late final List<StatementCheck> statements = [
    for (final s in _statements)
      StatementCheck(
        statement: s,
        ours: docs.any((d) => d.kind == SupplierDocKind.invoice && d.date.compareTo(s.date) <= 0) ? _capturedAt(s.date) : null,
        currentDueDate: s.dueDate ?? supplier.dueDateFor(s.date),
      ),
  ];
}

double _r(double v) => (v * 100).roundToDouble() / 100;
