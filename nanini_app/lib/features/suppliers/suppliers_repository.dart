import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/live_rows.dart';
import '../../core/supabase_client.dart';
import 'suppliers_models.dart';

/// Suppliers, their documents (PDFs in the "supplier-docs" storage bucket)
/// and payments. Needs docs/sql/suppliers.sql.
class SuppliersRepository {
  static const bucket = 'supplier-docs';

  Stream<List<Supplier>> watchSuppliers() =>
      watchAllRows('suppliers', orderBy: 'name').map((r) => r.map(Supplier.fromJson).toList());

  /// Read again straight away (a change made here shows at once, even where
  /// the live updates don't reach).
  Future<List<Supplier>> fetchSuppliers() async => (await fetchAllRows('suppliers', orderBy: 'name')).map(Supplier.fromJson).toList();
  Future<List<SupplierDoc>> fetchDocs() async => (await fetchAllRows('supplier_docs', orderBy: 'doc_date')).map(SupplierDoc.fromJson).toList();
  Future<List<SupplierPayment>> fetchPayments() async =>
      (await fetchAllRows('supplier_payments', orderBy: 'pay_date')).map(SupplierPayment.fromJson).toList();

  /// The last day the imported bank statements cover (docs/sql/bank_import.sql); null if not known.
  Future<String?> fetchBankDate() async {
    try {
      final row = await sb.from('bank_import').select('last_date').eq('id', 1).maybeSingle();
      return row?['last_date'] as String?;
    } catch (_) {
      return null;
    }
  }

  Stream<List<SupplierDoc>> watchDocs() =>
      watchAllRows('supplier_docs', orderBy: 'doc_date').map((r) => r.map(SupplierDoc.fromJson).toList());

  Stream<List<SupplierPayment>> watchPayments() =>
      watchAllRows('supplier_payments', orderBy: 'pay_date').map((r) => r.map(SupplierPayment.fromJson).toList());

  // The purchases report (docs/sql/suppliers_purchases.sql).
  Stream<List<GlAccount>> watchGlAccounts() =>
      watchAllRows('gl_accounts', orderBy: 'code', key: 'code').map((r) => r.map(GlAccount.fromJson).toList());

  Stream<List<DocLine>> watchDocLines() =>
      watchAllRows('supplier_doc_lines', orderBy: 'doc_id').map((r) => r.map(DocLine.fromJson).toList());

  Stream<List<GlRule>> watchGlRules() =>
      watchAllRows('supplier_gl_rules', orderBy: 'item').map((r) => r.map(GlRule.fromJson).toList());

  Future<void> addGlAccount(String code, String name) => sb.from('gl_accounts').upsert({'code': code.trim(), 'name': name.trim()});

  /// Puts purchase lines against [code]; [remember]: the supplier's item
  /// goes there from now on too.
  /// A document's lines, each against its contra account (as allocated when
  /// a captured document is approved).
  Future<void> addLines(String docId, List<({String? description, double excl, double vat, String glAccount})> lines) async {
    if (lines.isEmpty) return;
    await sb.from('supplier_doc_lines').insert([
      for (final (i, l) in lines.indexed)
        {'doc_id': docId, 'line_no': i + 1, 'description': l.description, 'excl_amount': l.excl, 'vat_amount': l.vat, 'gl_account': l.glAccount},
    ]);
  }

  Future<void> allocate(List<PurchaseLine> lines, String code, {bool remember = true}) async {
    for (final p in lines) {
      if (p.line != null) {
        await sb.from('supplier_doc_lines').update({'gl_account': code}).eq('id', p.line!.id);
      } else {
        // The whole document as one line: kept as a line now.
        await sb.from('supplier_doc_lines').upsert({
          'doc_id': p.doc.id,
          'line_no': 1,
          'description': p.description,
          'excl_amount': p.excl,
          'vat_amount': p.vat,
          'gl_account': code,
        }, onConflict: 'doc_id,line_no');
      }
      final item = glItemKey(p.description);
      if (remember && item.isNotEmpty && !p.fromStatement) {
        await sb.from('supplier_gl_rules').upsert({'supplier_id': p.supplier.id, 'item': item, 'gl_account': code}, onConflict: 'supplier_id,item');
      }
    }
  }

  Future<void> saveSupplier(Supplier s, {bool isNew = false}) async {
    if (isNew) {
      await sb.from('suppliers').insert(s.toJson());
    } else {
      await sb.from('suppliers').update(s.toJson()).eq('id', s.id);
    }
  }

  /// Uploads [pdf] (if given) and saves the document; its id.
  Future<String> addDoc({
    required String supplierId,
    required SupplierDocKind kind,
    required String date,
    required double amount,
    String? reference,
    String? notes,
    String? dueDate,
    double? overdueAmount,
    double? vatAmount,
    Uint8List? pdf,
    String? fileName,
  }) async {
    String? path;
    if (pdf != null) {
      path = '$supplierId/${const Uuid().v4()}.pdf';
      await sb.storage.from(bucket).uploadBinary(path, pdf, fileOptions: const FileOptions(contentType: 'application/pdf'));
    }
    try {
      final row = await sb.from('supplier_docs').insert({
        'supplier_id': supplierId,
        'kind': docKindKey(kind),
        'doc_date': date,
        'amount': amount,
        'reference': (reference ?? '').trim().isEmpty ? null : reference!.trim(),
        'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
        'file_path': path,
        'file_name': fileName,
        'due_date': dueDate,
        // Statements only (docs/sql/suppliers_statement_due.sql).
        if (kind == SupplierDocKind.statement) 'overdue_amount': overdueAmount,
        if (vatAmount != null) 'vat_amount': vatAmount,
      }).select('id').single();
      return row['id'] as String;
    } catch (_) {
      // Not saved: don't leave the PDF behind.
      if (path != null) await sb.storage.from(bucket).remove([path]);
      rethrow;
    }
  }

  /// A document from email, checked: its details as corrected, and it now
  /// counts in the account.
  Future<void> confirmDoc(String id,
          {required String supplierId,
          required SupplierDocKind kind,
          required String date,
          required double amount,
          String? reference,
          String? notes,
          String? dueDate,
          double? overdueAmount}) =>
      sb.from('supplier_docs').update({
        'supplier_id': supplierId,
        'due_date': dueDate,
        if (kind == SupplierDocKind.statement) 'overdue_amount': overdueAmount,
        'kind': docKindKey(kind),
        'doc_date': date,
        'amount': amount,
        'reference': (reference ?? '').trim().isEmpty ? null : reference!.trim(),
        'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
        'status': 'confirmed',
      }).eq('id', id);

  Future<void> deleteDoc(SupplierDoc d) async {
    await sb.from('supplier_docs').delete().eq('id', d.id);
    if (d.filePath != null) await sb.storage.from(bucket).remove([d.filePath!]);
  }

  Future<Uint8List> downloadPdf(String path) => sb.storage.from(bucket).download(path);

  Future<void> addPayment({required String supplierId, required String date, required double amount, String? reference, String? notes}) =>
      sb.from('supplier_payments').insert({
        'supplier_id': supplierId,
        'pay_date': date,
        'amount': amount,
        'reference': (reference ?? '').trim().isEmpty ? null : reference!.trim(),
        'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
      });

  Future<void> deletePayment(String id) => sb.from('supplier_payments').delete().eq('id', id);
}
