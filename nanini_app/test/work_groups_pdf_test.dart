import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/hours_payslip_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Work groups list: a table per group with name, surname, ID/passport and where paid', () async {
    Employee p(String id, String name, String surname, String farm, {String? idNo}) =>
        Employee(id: id, firstName: name, lastName: '', surname: surname, farmId: farm, idOrPassport: idNo);
    final packhouse = [for (var i = 0; i < 40; i++) p('p$i', 'Worker$i', 'Packer', i.isEven ? 'limpo' : 'doorn', idNo: 'XX00$i')];
    final field = [p('f1', 'Sipho', 'Field', 'limpo')];
    final doc = await buildWorkGroupsPdf(
      farmName: 'Limpopodraai',
      groups: [('Potatoes - field', field), ('Potatoes - packhouse', packhouse)],
      paidAt: (e) => e.farmId == 'limpo' ? 'Limpopodraai' : 'Doornbult',
      date: '2026-10-25',
    );
    final bytes = await doc.save();
    // 41 people: more than one page.
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length, greaterThan(1));
    final out = Platform.environment['GROUPS_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
