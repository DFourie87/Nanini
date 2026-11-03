import 'dart:typed_data';

import 'package:printing/printing.dart';

import '../../core/formatters.dart';
import '../suppliers/suppliers_models.dart';
import '../suppliers/suppliers_repository.dart';

/// A proof of address's utility bill: the latest Eskom bill of the member's
/// account in the Suppliers app, no older than 3 months before the letter.
typedef UtilityBill = ({Uint8List page, String label});

String _digits(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');

/// The 3 months before the letter: its oldest bill day (yyyy-MM-dd).
String utilityBillFrom(String letterDate) {
  final d = DateTime.parse(letterDate);
  return toDateStr(DateTime(d.year, d.month - 3, d.day));
}

/// The latest bill (with its PDF) of Eskom [account] on or before
/// [letterDate]: (bill, null), or (null, why not) -- none, or older than 3
/// months.
(SupplierDoc?, String?) latestUtilityBill(String account, List<Supplier> suppliers, List<SupplierDoc> docs, String letterDate) {
  final no = _digits(account);
  final ids = {for (final s in suppliers) if (no.isNotEmpty && (_digits(s.accountNo) == no || _digits(s.name).contains(no))) s.id};
  if (ids.isEmpty) return (null, 'Eskom account $account is not in the Suppliers app');
  final bills = [for (final d in docs) if (ids.contains(d.supplierId) && d.filePath != null && d.date.compareTo(letterDate) <= 0) d]
    ..sort((a, b) => b.date.compareTo(a.date));
  if (bills.isEmpty) return (null, 'No bill for Eskom account $account in the Suppliers app');
  final last = bills.first;
  if (last.date.compareTo(utilityBillFrom(letterDate)) < 0) {
    return (null, "The latest bill for Eskom account $account is from ${fmtDateDisplay(last.date)} -- more than 3 months before the letter's date. "
        'Bring in the new bill (Suppliers) first.');
  }
  return (last, null);
}

/// [latestUtilityBill] from the app, its first page drawn as a picture:
/// (bill, null) or (null, why not).
Future<(UtilityBill?, String?)> loadUtilityBill(String account, String letterDate) async {
  final repo = SuppliersRepository();
  final (bill, problem) = latestUtilityBill(account, await repo.fetchSuppliers(), await repo.fetchDocs(), letterDate);
  if (bill == null) return (null, problem);
  final pdf = await repo.downloadPdf(bill.filePath!);
  await for (final page in Printing.raster(pdf, pages: const [0], dpi: 150)) {
    return ((page: await page.toPng(), label: 'Eskom account $account, bill of ${fmtDateDisplay(bill.date)}'), null);
  }
  return (null, "The Eskom bill's PDF could not be read");
}
