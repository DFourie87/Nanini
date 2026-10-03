import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/capture_app/capture_store.dart';
import 'package:nanini_app/capture_app/flows/supplier_flow.dart';
import 'package:nanini_app/capture_app/ref_data.dart';
import 'package:nanini_app/features/capture/capture_models.dart';
import 'package:nanini_app/features/capture/captured_review_screen.dart';
import 'package:nanini_app/features/suppliers/suppliers_capture_approval.dart';
import 'package:nanini_app/features/suppliers/suppliers_models.dart';
import 'package:provider/provider.dart';

final _png = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));

RefData _ref() => RefData(
      farms: const [],
      people: const [],
      groups: const [],
      tanks: const [],
      vehicles: const [],
      activities: const [],
      shopItems: const [],
      suppliers: const [RefItem('k', 'Kalkor'), RefItem('n', 'Novon')],
    );

Future<CaptureStore> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final store = CaptureStore.forTest(_ref());
  await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: SupplierFlow())));
  await tester.pumpAndSettle();
  return store;
}

Future<void> _tap(WidgetTester tester, String text) async {
  final f = find.text(text, findRichText: true);
  await tester.ensureVisible(f.first);
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await _tap(tester, d == '.' ? ',' : d);
  }
}

void main() {
  testWidgets('Phone: an invoice photographed, with its total, VAT, number and date', (tester) async {
    var shots = 0;
    takeSupplierPhoto = () async {
      shots++;
      return _png;
    };
    final store = await _pump(tester);
    await _tap(tester, 'Kalkor');
    await _tap(tester, 'INVOICE');
    // The photo is needed.
    await _tap(tester, 'NEXT');
    expect(find.text('Take the photo first'), findsOneWidget);
    await _tap(tester, 'TAKE PHOTO');
    expect(shots, 1);
    expect(find.text('TAKE AGAIN'), findsOneWidget);
    await _tap(tester, 'NEXT');
    await _type(tester, '34158.85');
    await _tap(tester, 'NEXT');
    await _type(tester, '2672.85');
    await _tap(tester, 'NEXT');
    await tester.enterText(find.byType(TextField), 'INV99794');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'TODAY');
    expect(find.text('Is this right?'), findsOneWidget);
    expect(find.textContaining('Invoice INV99794'), findsOneWidget);
    await _tap(tester, 'SAVE');
    final e = store.queue.single;
    expect(e.module, CaptureModule.supplierDoc);
    expect(e.payload, {
      'supplier_id': 'k',
      'supplier_name': 'Kalkor',
      'kind': 'invoice',
      'date': e.payload['date'],
      'amount': 34158.85,
      'vat': 2672.85,
      'reference': 'INV99794',
      'photo': true,
    });
    // As the office and the phone's Sent list show it.
    expect(captureDetailLines(e).first, startsWith('Invoice INV99794 · Kalkor'));
  });

  testWidgets('Phone: a statement -- no VAT or number asked', (tester) async {
    takeSupplierPhoto = () async => _png;
    final store = await _pump(tester);
    await _tap(tester, 'Novon');
    await _tap(tester, 'STATEMENT');
    await _tap(tester, 'TAKE PHOTO');
    await _tap(tester, 'NEXT');
    expect(find.text('Balance on the statement?'), findsOneWidget);
    await _type(tester, '845.57');
    await _tap(tester, 'NEXT');
    await _tap(tester, 'TODAY');
    await _tap(tester, 'SAVE');
    expect(store.queue.single.payload['kind'], 'statement');
    expect(store.queue.single.payload.containsKey('vat'), isFalse);
  });

  testWidgets('Office: checked and allocated -- the part with VAT to transport, the rest to fertilizer', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final entry = CaptureEntry(
      id: 'e1',
      module: CaptureModule.supplierDoc,
      payload: {'supplier_id': 'k', 'supplier_name': 'Kalkor', 'kind': 'invoice', 'date': '2026-07-31', 'amount': 34158.85, 'vat': 2672.85, 'reference': 'INV99794', 'photo': true},
      summary: '',
      capturedAt: DateTime(2026, 8, 1),
      deviceName: 'Office phone',
    );
    final chart = [GlAccount(code: '3740/000', name: 'Fertilizer'), GlAccount(code: '4800/000', name: 'Transport')];
    final kalkor = Supplier(id: 'k', name: 'Kalkor', category: '3740 - Fertilizer', vatAccount: '4800 - Transport');
    SupplierDocApproval? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await Navigator.of(context).push<SupplierDocApproval>(MaterialPageRoute(
              builder: (_) => SupplierCaptureApprovalPage(entry: entry, reference: (supplier: kalkor, chart: chart), loadPhoto: (_) async => _png))),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Kalkor'), findsOneWidget);
    expect(find.text('Open the photo'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Approve'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('The lines add up to the total.'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(result!.kind, SupplierDocKind.invoice);
    expect((result!.amount, result!.vat, result!.reference, result!.date), (34158.85, 2672.85, 'INV99794', '2026-07-31'));
    expect(result!.lines.map((l) => (l.excl, l.vat, l.glAccount)), [(17819.0, 2672.85, '4800/000'), (13667.0, 0.0, '3740/000')]);
  });

  testWidgets('Office: lines that don\'t add up, or without an account, are not approved', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final entry = CaptureEntry(
      id: 'e2',
      module: CaptureModule.supplierDoc,
      payload: {'supplier_id': 'v', 'supplier_name': 'VKB', 'kind': 'credit_note', 'date': '2026-07-31', 'amount': 115.0, 'vat': 15.0},
      summary: '',
      capturedAt: DateTime(2026, 8, 1),
    );
    final vkb = Supplier(id: 'v', name: 'VKB', category: 'Various');
    SupplierDocApproval? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await Navigator.of(context).push<SupplierDocApproval>(MaterialPageRoute(
              builder: (_) => SupplierCaptureApprovalPage(entry: entry, reference: (supplier: vkb, chart: [GlAccount(code: '4100/000', name: 'Repairs')])))),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // "Various" isn't an account: one has to be chosen.
    await tester.scrollUntilVisible(find.text('Approve'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Line 1: choose its contra account.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contra account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4100/000 Repairs').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    // A credit note's lines count as negative.
    expect(result!.lines.single, (description: 'Various', excl: -100.0, vat: -15.0, glAccount: '4100/000'));
  });
}
