import 'dart:convert';
import 'dart:typed_data';

import '../../core/live_rows.dart';
import '../../core/supabase_client.dart';
import '../capture/capture_models.dart';
import '../cards/card_models.dart';
import '../cards/card_repository.dart';
import '../suppliers/suppliers_capture_approval.dart' show capturedPhoto;
import '../suppliers/suppliers_models.dart';
import 'cash_slip_models.dart';

/// The petty cash slips (docs/sql/cash_slips.sql) and their photos.
class CashSlipRepository {
  Future<List<CashSlip>> fetchSlips() async => (await fetchAllRows('cash_slips', orderBy: 'slip_date')).map(CashSlip.fromJson).toList();

  Future<List<GlAccount>> fetchChart() async {
    try {
      return (await fetchAllRows('gl_accounts', orderBy: 'code', key: 'code')).map(GlAccount.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// The bank's money out (bank_lines); empty until bank_lines.sql is run
  /// and the bank import has run.
  Future<List<BankLine>> fetchBankLines() async {
    try {
      return (await fetchAllRows('bank_lines', orderBy: 'line_date')).map(BankLine.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// The credit and fleet cards' statement lines, as places a slip may have been paid.
  Future<List<PaidElsewhere>> fetchCardLines() async {
    final out = <PaidElsewhere>[];
    try {
      for (final card in CardKind.values) {
        final st = await CardRepository().fetchStatements(card);
        for (final l in await CardRepository().fetchLines([for (final s in st) s.id])) {
          out.add((where: card.label, date: l.date, description: l.description, amount: l.amount));
        }
      }
    } catch (_) {
      // The cards' tables not there yet.
    }
    return out;
  }

  Future<Uint8List?> photo(String slipId) async {
    final row = await sb.from('cash_slip_photos').select('data').eq('slip_id', slipId).maybeSingle();
    final data = row?['data'] as String?;
    return data == null ? null : base64Decode(data);
  }

  /// Adds [s] (with its photo); its id.
  Future<String> add(CashSlip s, {Uint8List? photo}) async {
    final row = await sb.from('cash_slips').insert(s.toRow()).select('id').single();
    final id = row['id'] as String;
    if (photo != null) await sb.from('cash_slip_photos').insert({'slip_id': id, 'data': base64Encode(photo)});
    return id;
  }

  Future<void> update(CashSlip s) => sb.from('cash_slips').update(s.toRow()).eq('id', s.id);

  Future<void> delete(String id) => sb.from('cash_slips').delete().eq('id', id).isFilter('xero_id', null);

  Future<void> markSent(String id, String xeroId) =>
      sb.from('cash_slips').update({'xero_id': xeroId, 'xero_sent_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
}

/// Approving a captured cash slip: kept in cash_slips as checked ([slip]),
/// with the photo the phone sent.
Future<void> applyCashSlipCapture(CaptureEntry entry, CashSlip slip) async {
  final photo = entry.payload['photo'] == true ? await capturedPhoto(entry.id) : null;
  await CashSlipRepository().add(slip, photo: photo);
  // Kept with the slip now.
  await sb.from('capture_photos').delete().eq('entry_id', entry.id);
}
