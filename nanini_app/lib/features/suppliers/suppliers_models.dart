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
  });

  final String id;
  final String name;
  final String? accountNo;
  final String? contact;
  final String? phone;
  final String? email;
  final double openingBalance;
  final String? openingDate;

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        accountNo: j['account_no'] as String?,
        contact: j['contact'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        openingBalance: (j['opening_balance'] as num?)?.toDouble() ?? 0,
        openingDate: j['opening_date'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'account_no': _blank(accountNo),
        'contact': _blank(contact),
        'phone': _blank(phone),
        'email': _blank(email),
        'opening_balance': openingBalance,
        'opening_date': openingDate,
      };
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
  StatementCheck({required this.statement, required this.ours});
  final SupplierDoc statement;

  /// What we have owing on the statement's date.
  final double ours;
  double get difference => statement.amount - ours;
  bool get matches => difference.abs() < 0.01;
}

/// A supplier's account worked out from its documents and payments.
class SupplierAccount {
  SupplierAccount(this.supplier, Iterable<SupplierDoc> docs, Iterable<SupplierPayment> payments)
      : docs = docs.where((d) => d.supplierId == supplier.id).toList(),
        payments = payments.where((p) => p.supplierId == supplier.id).toList();

  final Supplier supplier;
  final List<SupplierDoc> docs;
  final List<SupplierPayment> payments;

  /// What's owed up to and including [upTo] (yyyy-MM-dd), or now.
  double balanceAt([String? upTo]) {
    bool inRange(String d) => upTo == null || d.compareTo(upTo) <= 0;
    var b = (supplier.openingDate == null || inRange(supplier.openingDate!)) ? supplier.openingBalance : 0.0;
    for (final d in docs) {
      if (!inRange(d.date)) continue;
      if (d.kind == SupplierDocKind.invoice) b += d.amount;
      if (d.kind == SupplierDocKind.creditNote) b -= d.amount;
    }
    for (final p in payments) {
      if (inRange(p.date)) b -= p.amount;
    }
    return _r(b);
  }

  /// Amount due now.
  double get due => balanceAt();

  /// The account, oldest first, with the balance after each line
  /// (statements aren't lines -- they're checked against it).
  List<LedgerLine> get ledger {
    final items = <(String, int, LedgerLine Function(double))>[
      if (supplier.openingBalance != 0)
        (supplier.openingDate ?? '0000-00-00', 0, (b) => LedgerLine(date: supplier.openingDate ?? '', label: 'Opening balance', amount: supplier.openingBalance, balance: b)),
      for (final d in docs.where((d) => d.kind != SupplierDocKind.statement))
        (
          d.date,
          1,
          (b) => LedgerLine(
                date: d.date,
                label: '${docKindLabel(d.kind)}${(d.reference ?? '').isEmpty ? '' : ' ${d.reference}'}',
                amount: d.kind == SupplierDocKind.invoice ? d.amount : -d.amount,
                balance: b,
                doc: d,
              )
        ),
      for (final p in payments)
        (p.date, 2, (b) => LedgerLine(date: p.date, label: 'Payment${(p.reference ?? '').isEmpty ? '' : ' ${p.reference}'}', amount: -p.amount, balance: b, payment: p)),
    ]..sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
    var b = 0.0;
    final out = <LedgerLine>[];
    for (final (_, _, make) in items) {
      final probe = make(0);
      b = _r(b + probe.amount);
      out.add(make(b));
    }
    return out;
  }

  /// Each statement (newest first) against what we have owing on its date.
  List<StatementCheck> get statements => [
        for (final s in docs.where((d) => d.kind == SupplierDocKind.statement).toList()..sort((a, b) => b.date.compareTo(a.date)))
          StatementCheck(statement: s, ours: balanceAt(s.date)),
      ];
}

double _r(double v) => (v * 100).roundToDouble() / 100;
