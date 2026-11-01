import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/capture_app/capture_store.dart';
import 'package:nanini_app/capture_app/flows/timesheet_flow.dart';
import 'package:nanini_app/capture_app/ref_data.dart';
import 'package:nanini_app/capture_app/timesheet_reader.dart';
import 'package:nanini_app/features/capture/capture_models.dart';
import 'package:nanini_app/features/capture/captured_review_screen.dart';
import 'package:nanini_app/features/capture/timesheet_capture.dart';
import 'package:provider/provider.dart';

final _png = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));

RefData _ref() => RefData(
    farms: const [],
    people: const [
      RefPerson(id: 'w1', name: 'Lucas', surname: 'Moyo'),
      RefPerson(id: 'w2', name: 'Lackson', surname: 'Dube'),
      RefPerson(id: 'w3', name: 'Tendai', surname: 'Ncube'),
    ],
    groups: const [],
    tanks: const [],
    vehicles: const [],
    activities: const [],
    shopItems: const []);

Map<String, dynamic> _readPayload() => {
      'kind': 'page',
      'photo': true,
      'read': {
        'farm_id': 'farm-haas',
        'farm_name': 'Farm Haaskraal - Swartwater',
        'month': '2026-10',
        'page': '1/2',
        'days': ['2026-09-26', '2026-09-27', '2026-09-28'],
        'group_id': null,
        'group_name': null,
        'notes': 'Row 2, 28 Sep unclear',
        'rows': [
          {'row': 1, 'employee_id': 'w1', 'name': 'Moyo Lucas', 'hours': ['8', '', '9,5'], 'total': '17.5'},
          {'row': 2, 'employee_id': 'w2', 'name': 'Dube Lackson', 'hours': ['8', '', '?'], 'total': '17'},
          {'row': 21, 'employee_id': null, 'written_name': 'Tendai Ncube', 'id_number': 'FN123456', 'hours': ['', '', '8'], 'total': '8'},
        ],
      },
    };

void main() {
  testWidgets('Phone: TIMESHEET -- photo, checked on the phone, then saved to go straight in', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    takeTimesheetPhoto = () async => (bytes: _png, path: '/photo.jpg');
    var fail = true;
    readTimesheetPhoto = (path, ref) async {
      if (fail) throw SheetReadProblem('No QR code found -- take the photo again');
      return (_readPayload()['read'] as Map).cast<String, dynamic>();
    };
    final store = CaptureStore.forTest(_ref());
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: TimesheetFlow())));
    await tester.pumpAndSettle();
    // No CHECK before there's a photo.
    expect(find.text('CHECK'), findsNothing);
    // Can't be read: says why, and there's no CHECK -- take it again.
    await tester.tap(find.text('TAKE PHOTO'));
    await tester.pumpAndSettle();
    expect(find.text('No QR code found -- take the photo again'), findsOneWidget);
    expect(find.text('CHECK'), findsNothing);
    fail = false;
    await tester.ensureVisible(find.text('TAKE AGAIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TAKE AGAIN'));
    await tester.pumpAndSettle();
    expect(find.text('Farm Haaskraal - Swartwater · page 1/2'), findsOneWidget);
    expect(find.text('3 workers with hours'), findsOneWidget);
    await tester.tap(find.text('CHECK'));
    await tester.pumpAndSettle();

    // 1. Who the worker written in by hand is: a NEW WORKER, details captured and confirmed.
    expect(find.text('New workers on the sheet'), findsOneWidget);
    expect(find.text('Line 21: Tendai Ncube'), findsOneWidget);
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Say who is on line 21'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));
    await tester.tap(find.text('NEW WORKER'));
    await tester.pumpAndSettle();
    expect(find.text('New worker at Farm Haaskraal - Swartwater'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Name (known as) *'), 'Tendai');
    await tester.enterText(find.widgetWithText(TextField, 'Surname'), 'Ncube');
    await tester.enterText(find.widgetWithText(TextField, 'ID / passport number'), 'FN123456');
    // With an ID, the full names are needed; and how they're paid.
    await tester.tap(find.text('CONFIRM'));
    await tester.pumpAndSettle();
    expect(find.textContaining('full names and surname'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));
    await tester.enterText(find.widgetWithText(TextField, 'Full names (as on ID)'), 'Tendai Blessing');
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRM'));
    await tester.pumpAndSettle();
    expect(find.text('New: Tendai Ncube · FN123456'), findsOneWidget);
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();

    // 2. The hours, as an electronic sheet: every box as read; the unclear one must be fixed first.
    expect(find.text('Are the hours right?'), findsOneWidget);
    expect(find.text('1. Moyo Lucas'), findsOneWidget);
    expect(find.text('Total 17.5 h · written 17.5'), findsOneWidget);
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fix or clear the amber boxes'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));
    await tester.scrollUntilVisible(find.widgetWithText(TextField, '?'), 200, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.widgetWithText(TextField, '?'), '9');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('21. Tendai Ncube (new)'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    final e = store.queue.single;
    expect(e.module, CaptureModule.timesheet);
    expect(e.payload['photo'], true);
    expect((e.payload['read'] as Map)['farm_id'], 'farm-haas');
    final checked = (e.payload['checked'] as Map).cast<String, dynamic>();
    expect(checked['farm_id'], 'farm-haas');
    final lines = (checked['lines'] as List).cast<Map>();
    expect([for (final l in lines) '${l['employee_id']} ${l['date']} ${l['hours']}'],
        ['w1 2026-09-26 8.0', 'w1 2026-09-28 9.5', 'w2 2026-09-26 8.0', 'w2 2026-09-28 9.0', 'new:21 2026-09-28 8.0']);
    final added = (checked['new_workers'] as List).cast<Map>().single;
    expect(added['key'], 'new:21');
    expect([added['name'], added['surname'], added['full_names'], added['id_or_passport'], added['payment_method']], ['Tendai', 'Ncube', 'Tendai Blessing', 'FN123456', 'cash']);
    expect(find.text('SAVED'), findsOneWidget);
  });

  testWidgets('Phone: TIMESHEET -- a name written in is an existing worker: picked, no details', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    takeTimesheetPhoto = () async => (bytes: _png, path: '/photo.jpg');
    readTimesheetPhoto = (path, ref) async {
      final r = (_readPayload()['read'] as Map).cast<String, dynamic>();
      ((r['rows'] as List)[1] as Map)['hours'] = ['8', '', '9']; // nothing unclear
      return r;
    };
    final store = CaptureStore.forTest(_ref());
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: TimesheetFlow())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TAKE PHOTO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CHECK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Already a worker? Pick them'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tendai Ncube').last);
    await tester.pumpAndSettle();
    expect(find.text('Is Tendai Ncube'), findsOneWidget);
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    final checked = (store.queue.single.payload['checked'] as Map).cast<String, dynamic>();
    expect((checked['lines'] as List).cast<Map>().where((l) => l['employee_id'] == 'w3').map((l) => l['date']), ['2026-09-28']);
    expect(checked['new_workers'], isEmpty);
  });

  testWidgets("Phone: Hours > ADD TIMESHEET for one farm refuses another farm's sheet", (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    takeTimesheetPhoto = () async => (bytes: _png, path: '/photo.jpg');
    readTimesheetPhoto = (path, ref) async => (_readPayload()['read'] as Map).cast<String, dynamic>();
    final store = CaptureStore.forTest(_ref());
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store, child: const MaterialApp(home: TimesheetFlow(farm: RefItem('farm-lim', 'Farm Limpopodraai - Stockpoort')))));
    await tester.pumpAndSettle();
    expect(find.text("Photo of one page of Farm Limpopodraai - Stockpoort's timesheet"), findsOneWidget);
    await tester.tap(find.text('TAKE PHOTO'));
    await tester.pumpAndSettle();
    // The photo is Haaskraal's sheet: said so, and no CHECK.
    expect(find.textContaining("This is Farm Haaskraal - Swartwater's timesheet, not Farm Limpopodraai - Stockpoort's"), findsOneWidget);
    expect(find.text('CHECK'), findsNothing);
  });

  test('A page as read on the phone: the sheet, its days and each line', () {
    final r = TimesheetRead.fromPayload(_readPayload())!;
    expect(r.farmId, 'farm-haas');
    expect(r.days.length, 3);
    expect(r.rows.map((x) => x.employeeId), ['w1', 'w2', null]);
    expect(r.rows[2].writtenName, 'Tendai Ncube');
    expect(r.rows[1].cells, ['8', '', '?']);
    // Not read yet: nothing.
    expect(TimesheetRead.fromPayload({'kind': 'page', 'photo': true}), isNull);
  });

  test('A day\'s box as hours: empty, a number (comma or point), or unreadable', () {
    expect(timesheetHours(''), isNull);
    expect(timesheetHours(' '), isNull);
    expect(timesheetHours('8'), 8);
    expect(timesheetHours('9,5'), 9.5);
    expect(timesheetHours('0'), 0);
    expect(timesheetHours('?')!.isNaN, isTrue);
    expect(timesheetHours('A')!.isNaN, isTrue);
    expect(timesheetHours('30')!.isNaN, isTrue); // more than a day
  });

  test('Paid days and days clocked at another farm are not put in from the sheet', () {
    final ctx = timesheetContextFrom(
      farmId: 'farm-haas',
      payslips: [
        {'employee_id': 'w1', 'period_end': '2026-09-25'},
        {'employee_id': 'w1', 'period_end': '2026-09-26'},
      ],
      hours: [
        {'employee_id': 'w2', 'entry_date': '2026-09-28', 'hours': 9, 'farm_id': 'farm-limpo'},
        {'employee_id': 'w2', 'entry_date': '2026-09-26', 'hours': 8, 'farm_id': 'farm-haas'}, // this farm: replaced by the sheet
        {'employee_id': 'w2', 'entry_date': '2026-09-27', 'hours': 9, 'farm_id': 'farm-limpo'},
        {'employee_id': 'w2', 'entry_date': '2026-09-27', 'hours': -9, 'farm_id': 'farm-limpo'}, // taken off again
      ],
      farmNames: {'farm-limpo': 'Farm Limpopodraai - Stockpoort'},
    );
    expect(ctx.blockFor('w1', '2026-09-26'), TimesheetBlock.paid);
    expect(ctx.blockFor('w1', '2026-09-28'), isNull);
    expect(ctx.blockFor('w2', '2026-09-28'), TimesheetBlock.otherFarm);
    expect(ctx.otherFarmHours[('w2', '2026-09-28')], 'Farm Limpopodraai - Stockpoort 9 h');
    expect(ctx.blockFor('w2', '2026-09-26'), isNull);
    expect(ctx.blockFor('w2', '2026-09-27'), isNull);
  });

  test('Hub: the Captured list says whether a page is read yet', () {
    CaptureEntry e(Map<String, dynamic> p) => CaptureEntry(id: 'e1', module: CaptureModule.timesheet, payload: p, summary: 'Timesheet page', capturedAt: DateTime(2026, 10, 30));
    expect(captureDetailLines(e({'kind': 'page', 'photo': true}))[1], startsWith('Not read on the phone'));
    expect(captureDetailLines(e({'kind': 'page', 'photo': true, 'read_error': 'No QR code found'}))[1], 'Could not read it: No QR code found');
    final lines = captureDetailLines(e(_readPayload()));
    expect(lines[0], 'Timesheet Farm Haaskraal - Swartwater · 2026-10 · page 1/2');
    expect(lines[1], startsWith('Read: 3 workers with hours, 3 days'));
  });
}
