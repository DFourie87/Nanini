import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/timesheet_pdf.dart';
import 'package:nanini_app/features/tuckshop/fridge_sheet_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final workers = [
    for (var i = 0; i < 25; i++) Employee(id: 'worker-${i.toString().padLeft(3, '0')}', firstName: 'Name$i', lastName: 'Surname$i', surname: 'Surname$i', farmId: 'farm-limpo'),
  ];
  const items = [(id: 'item-wors-1', name: 'Wors'), (id: 'item-chicken-1', name: 'Chicken pieces')];

  test('Fridge sheet: one sheet for wors and chicken pieces, a line per worker, 20 empty lines', () async {
    final days = timesheetDays(DateTime(2026, 11));
    final doc = await buildFridgeSheetPdf(farmName: 'Limpopodraai', farmId: 'farm-limpo-1', month: DateTime(2026, 11), days: days, workers: workers, items: items);
    final bytes = await doc.save();
    // 25 workers + 20 empty lines = 45 lines -> 3 pages (not a sheet per item).
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length, 3);
    expect(
      fridgeSheetCode(month: DateTime(2026, 11), days: days, farmId: 'farm-limpo-1', itemIds: [for (final i in items) i.id], page: 1, pages: 3, rows: workers.take(2).toList()),
      'NFS2|2026-11|2026-10-31|2026-11-27|farm-lim|item-wor,item-chi|1/3|worker-0,worker-0',
    );
    final out = Platform.environment['FRIDGE_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
