import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/capture/capture_models.dart';
import 'package:nanini_app/features/petty_cash/cash_slip_models.dart';
import 'package:nanini_app/features/petty_cash/cash_slip_repository.dart';
import 'package:nanini_app/features/petty_cash/petty_cash_screen.dart';
import 'package:nanini_app/features/suppliers/suppliers_models.dart';

// Made-up slips and bank lines.
CashSlip slip(String id, String date, String shop, double amount, {double vat = 0, String? account, bool confirmed = false, String? xero}) =>
    CashSlip(id: id, date: date, shop: shop, amount: amount, vat: vat, glAccount: account, cashConfirmed: confirmed, xeroId: xero);

final bank = [
  BankLine(date: '2026-11-12', spentOn: '2026-11-10', description: 'POS PURCHASE (EFFEC 10112026) BUILDERS LEPHALALE CARD NO. 4258', amount: 456.90),
  BankLine(date: '2026-10-01', description: 'DIGITAL PAYMENT ABSA BANK Omnia', amount: 456.90),
];
final List<PaidElsewhere> cards = [(where: 'Fleet card', date: '2026-11-20', description: 'EXTERNAL PURCHASE', amount: -320.00)];

void main() {
  test('paid by bank or card already: the same amount within 5 days of the slip', () {
    expect(paidElsewhere(slip('a', '2026-11-11', 'Builders', 456.90), bank, cards).map((p) => (p.where, p.date)), [('ABSA', '2026-11-10')]);
    expect(paidElsewhere(slip('b', '2026-11-20', 'Builders', 456.90), bank, cards), isEmpty); // 10 days later
    expect(paidElsewhere(slip('c', '2026-11-11', 'Builders', 456.00), bank, cards), isEmpty); // another amount
    expect(paidElsewhere(slip('d', '2026-11-18', 'Engen', 320), bank, cards).single.where, 'Fleet card');
  });

  test('to Xero: spend money from Petty Cash, the shop as contact, 15% with the slip\'s VAT or No VAT; the account last used suggested', () {
    final taxed = xeroSpendMoneyJson(slip('a', '2026-11-11', 'Builders', 115, vat: 15, account: '4350/200'), 'BANK1', {
      'Standard Rate Purchases': 'INPUT',
      'No VAT': 'NONE',
    });
    expect(taxed['Type'], 'SPEND');
    expect(taxed['Contact'], {'Name': 'Builders'});
    expect(taxed['BankAccount'], {'AccountID': 'BANK1'});
    expect(taxed['LineAmountTypes'], 'Inclusive');
    final line = (taxed['LineItems'] as List).single as Map;
    expect((line['UnitAmount'], line['AccountCode'], line['TaxType'], line['TaxAmount']), (115.0, '4350/200', 'INPUT', 15.0));
    final plain =
        (xeroSpendMoneyJson(slip('b', '2026-11-11', 'Spaza', 40, account: '3780/000'), 'BANK1', {
                      'Standard Rate Purchases': 'INPUT',
                      'No VAT': 'NONE',
                    })['LineItems']
                    as List)
                .single
            as Map;
    expect((plain['TaxType'], plain.containsKey('TaxAmount')), ('NONE', false));
    expect(cashSlipNotReady(slip('c', '2026-11-11', 'X', 10)), 'no account');
    expect(cashSlipNotReady(slip('d', '2026-08-01', 'X', 10, account: '1')), startsWith('before Xero'));
    expect(
      lastAccountFor('builders ', [slip('e', '2026-10-01', 'Builders', 1, account: '4350/100'), slip('f', '2026-11-01', 'BUILDERS', 1, account: '4350/200')]),
      '4350/200',
    );
  });

  testWidgets('the screen: a phone\'s slip paid by bank already is flagged and rejected; another approved with the account last used', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    final pending = StreamController<List<CaptureEntry>>.broadcast();
    addTearDown(pending.close);
    final approved = <CashSlip>[];
    final rejected = <String>[];
    CaptureEntry entry(String id, String shop, double amount, String date) => CaptureEntry(
      id: id,
      module: CaptureModule.cashSlip,
      payload: {'shop': shop, 'amount': amount, 'vat': 0, 'date': date, 'description': 'Bolts', 'photo': true},
      summary: 'Cash slip',
      capturedAt: DateTime(2026, 11, 21),
      deviceName: 'Haaskraal phone',
    );
    final paidByBank = entry('e1', 'Builders Lephalale', 456.90, '2026-11-10');
    final cash = entry('e2', 'Spaza', 85, '2026-11-15');
    await tester.pumpWidget(
      MaterialApp(
        home: PettyCashScreen(
          repo: repo,
          pending: pending.stream,
          loadCapturePhoto: (_) async => null,
          approve: (e, s) async => approved.add(s),
          reject: (e, r) async => rejected.add(r),
        ),
      ),
    );
    await tester.pumpAndSettle(); // loaded: the list (and its stream) shown
    pending.add([paidByBank, cash]);
    await tester.pumpAndSettle();
    expect(find.text('From the phones -- to check (2)'), findsOneWidget);
    expect(find.textContaining('Paid by bank already? ABSA 10 Nov 2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('petty_pending_e1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('petty_elsewhere')), findsOneWidget);
    await tester.tap(find.byKey(const Key('petty_reject')));
    await tester.pumpAndSettle();
    expect(rejected.single, startsWith('Paid by bank already: ABSA 10 Nov 2026'));

    await tester.tap(find.byKey(const Key('petty_pending_e2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('petty_elsewhere')), findsNothing);
    await tester.tap(find.byKey(const Key('petty_save')));
    await tester.pumpAndSettle();
    expect((approved.single.shop, approved.single.amount, approved.single.glAccount, approved.single.date), ('Spaza', 85.0, '3780/000', '2026-11-15'));

    // A kept slip of the same amount as a bank payment: held back from Xero.
    expect(find.textContaining('Paid by bank already: ABSA 10 Nov 2026'), findsOneWidget);
    expect(find.text('Send 1 to Xero'), findsOneWidget); // the Spaza slip only, not the one paid by bank
    expect(tester.takeException(), isNull);
  });
}

class _Repo extends CashSlipRepository {
  @override
  Future<List<CashSlip>> fetchSlips() async => [
    slip('s1', '2026-11-01', 'Spaza', 40, account: '3780/000'),
    slip('s2', '2026-11-11', 'Builders', 456.90, account: '4350/200'),
  ];
  @override
  Future<List<GlAccount>> fetchChart() async => [GlAccount(code: '3780/000', name: 'Fuel'), GlAccount(code: '4350/200', name: 'Repairs')];
  @override
  Future<List<BankLine>> fetchBankLines() async => bank;
  @override
  Future<List<PaidElsewhere>> fetchCardLines() async => cards;
  @override
  Future<Uint8List?> photo(String slipId) async => null;
}
