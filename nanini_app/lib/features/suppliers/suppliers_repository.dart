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

  Stream<List<SupplierDoc>> watchDocs() =>
      watchAllRows('supplier_docs', orderBy: 'doc_date').map((r) => r.map(SupplierDoc.fromJson).toList());

  Stream<List<SupplierPayment>> watchPayments() =>
      watchAllRows('supplier_payments', orderBy: 'pay_date').map((r) => r.map(SupplierPayment.fromJson).toList());

  Future<void> saveSupplier(Supplier s, {bool isNew = false}) async {
    if (isNew) {
      await sb.from('suppliers').insert(s.toJson());
    } else {
      await sb.from('suppliers').update(s.toJson()).eq('id', s.id);
    }
  }

  /// Uploads [pdf] (if given) and saves the document.
  Future<void> addDoc({
    required String supplierId,
    required SupplierDocKind kind,
    required String date,
    required double amount,
    String? reference,
    String? notes,
    Uint8List? pdf,
    String? fileName,
  }) async {
    String? path;
    if (pdf != null) {
      path = '$supplierId/${const Uuid().v4()}.pdf';
      await sb.storage.from(bucket).uploadBinary(path, pdf, fileOptions: const FileOptions(contentType: 'application/pdf'));
    }
    try {
      await sb.from('supplier_docs').insert({
        'supplier_id': supplierId,
        'kind': docKindKey(kind),
        'doc_date': date,
        'amount': amount,
        'reference': (reference ?? '').trim().isEmpty ? null : reference!.trim(),
        'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
        'file_path': path,
        'file_name': fileName,
      });
    } catch (_) {
      // Not saved: don't leave the PDF behind.
      if (path != null) await sb.storage.from(bucket).remove([path]);
      rethrow;
    }
  }

  /// A document from email, checked: its details as corrected, and it now
  /// counts in the account.
  Future<void> confirmDoc(String id, {required SupplierDocKind kind, required String date, required double amount, String? reference, String? notes}) =>
      sb.from('supplier_docs').update({
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
