import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/hours/hours_models.dart';

Payslip _slip(String paid, String? code) => Payslip(
      id: 'x',
      employeeId: 'e',
      periodStart: paid,
      periodEnd: paid,
      paidDate: paid,
      gross: 0,
      paye: 0,
      uif: 0,
      rent: 0,
      loan: 0,
      tuckshopDeduction: 0,
      nett: 0,
      createdAt: DateTime(2026),
      atmAccessCode: code,
    );

void main() {
  test('one 6-digit ATM code per payday, new on every other payday', () {
    final code = atmCodeFor('2026-10-01', const []);
    expect(isAtmCode(code), isTrue);
    // Another farm paid the same day: same code.
    expect(atmCodeFor('2026-10-01', [_slip('2026-10-01', '482913'), _slip('2026-10-01', null)]), '482913');
    // Another payday: a new code, never one used before.
    for (var seed = 0; seed < 50; seed++) {
      final c = atmCodeFor('2026-10-15', [_slip('2026-10-01', '482913')], random: Random(seed));
      expect(isAtmCode(c), isTrue);
      expect(c, isNot('482913'));
    }
    expect(isAtmCode('12345'), isFalse);
    expect(isAtmCode('12a456'), isFalse);
  });

  test('the code is saved only when there is one', () {
    expect(_slip('2026-10-01', null).toInsert().containsKey('atm_access_code'), isFalse);
    expect(_slip('2026-10-01', '482913').toInsert()['atm_access_code'], '482913');
  });
}
