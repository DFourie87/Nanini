import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/capture_app/capture_store.dart';
import 'package:nanini_app/capture_app/flows/fridge_sheet_flow.dart';
import 'package:nanini_app/capture_app/flows/timesheet_flow.dart';
import 'package:nanini_app/capture_app/ref_data.dart';
import 'package:nanini_app/features/capture/capture_models.dart';
import 'package:provider/provider.dart';

final _png = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));

RefData _ref() => RefData(
      farms: const [],
      people: const [RefPerson(id: 'w1', name: 'Lucas', surname: 'Moyo'), RefPerson(id: 'w2', name: 'Lackson', surname: 'Dube')],
      groups: const [],
      tanks: const [],
      vehicles: const [],
      activities: const [],
      shopItems: const [RefShopItem(id: 'wors-1', name: 'Wors', price: 45, stock: 30), RefShopItem(id: 'chic-2', name: 'Chicken pieces', price: 60, stock: 20)],
    );

Map<String, dynamic> _read() => {
      'farm_id': 'farm-lim',
      'farm_name': 'Farm Limpopodraai - Stockpoort',
      'month': '2026-11',
      'first': '2026-10-31',
      'last': '2026-11-27',
      'page': '1/1',
      'items': [
        {'id': 'wors-1', 'prefix': 'wors', 'name': 'Wors'},
        {'id': 'chic-2', 'prefix': 'chic', 'name': 'Chicken pieces'},
      ],
      'rows': [
        {'row': 1, 'employee_id': 'w1', 'name': 'Moyo Lucas', 'counts': [{'marks': 4, 'total': '4'}, {'marks': 2, 'total': ''}]},
        // Marks 3, total written 5: to check (amber) -- the total is kept unless changed.
        {'row': 2, 'employee_id': 'w2', 'name': 'Dube Lackson', 'counts': [{'marks': 3, 'total': '5'}, {'marks': 0, 'total': ''}]},
      ],
    };

void main() {
  testWidgets('Phone: FRIDGE SHEET -- photo, counts checked on the phone, saved to go straight on the accounts', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    takeTimesheetPhoto = () async => (bytes: _png, path: '/photo.jpg');
    readFridgePhoto = (path, ref) async => _read();
    final store = CaptureStore.forTest(_ref());
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: FridgeSheetFlow())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TAKE PHOTO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CHECK'));
    await tester.pumpAndSettle();
    expect(find.text('Are the counts right?'), findsOneWidget);
    expect(find.text('1. Moyo Lucas'), findsOneWidget);
    // Lackson's wors: the total written (5) -- corrected to 3 after looking at the photo.
    await tester.scrollUntilVisible(find.widgetWithText(TextField, '5'), 200, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.widgetWithText(TextField, '5'), '3');
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    final e = store.queue.single;
    expect(e.module, CaptureModule.fridgeSheet);
    final checked = (e.payload['checked'] as Map).cast<String, dynamic>();
    expect(checked['note'], 'Fridge sheet Farm Limpopodraai - Stockpoort from 2026-10-31, page 1/1');
    expect([for (final l in (checked['lines'] as List).cast<Map>()) '${l['employee_id']} ${l['item_id']} ${l['qty']}'], ['w1 wors-1 4', 'w1 chic-2 2', 'w2 wors-1 3']);
    expect(e.summary, contains('7 Wors'));
    expect(find.text('SAVED'), findsOneWidget);
  });
}
