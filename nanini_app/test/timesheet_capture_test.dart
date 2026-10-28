import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/capture_app/capture_store.dart';
import 'package:nanini_app/capture_app/flows/timesheet_flow.dart';
import 'package:nanini_app/capture_app/ref_data.dart';
import 'package:nanini_app/features/capture/capture_models.dart';
import 'package:nanini_app/features/capture/captured_review_screen.dart';
import 'package:nanini_app/features/capture/timesheet_capture.dart';
import 'package:provider/provider.dart';

final _png = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));

RefData _ref() => RefData(farms: const [], people: const [], groups: const [], tanks: const [], vehicles: const [], activities: const [], shopItems: const []);

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
  testWidgets('Phone: TIMESHEET sends a photo of a page', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    takeTimesheetPhoto = () async => _png;
    final store = CaptureStore.forTest(_ref());
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const MaterialApp(home: TimesheetFlow())));
    await tester.pumpAndSettle();
    // No SEND before there's a photo.
    expect(find.text('SEND'), findsNothing);
    await tester.tap(find.text('TAKE PHOTO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SEND'));
    await tester.pumpAndSettle();
    final e = store.queue.single;
    expect(e.module, CaptureModule.timesheet);
    expect(e.payload, {'kind': 'page', 'photo': true});
    expect(find.text('SAVED'), findsOneWidget);
  });

  test('A page as read on the office PC: the sheet, its days and each line', () {
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
    expect(captureDetailLines(e({'kind': 'page', 'photo': true}))[1], startsWith('Waiting for the office PC'));
    expect(captureDetailLines(e({'kind': 'page', 'photo': true, 'read_error': 'No QR code found'}))[1], 'Could not read it: No QR code found');
    final lines = captureDetailLines(e(_readPayload()));
    expect(lines[0], 'Timesheet Farm Haaskraal - Swartwater · 2026-10 · page 1/2');
    expect(lines[1], startsWith('Read: 3 workers with hours, 3 days'));
  });
}
