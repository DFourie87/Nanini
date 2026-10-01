import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/hours_payslip_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Payslip slip(String emp, {double hours = 80, double rate = 30, List<Map<String, dynamic>> extras = const [], double paye = 0, double uif = 0, double tuck = 0, double loan = 0}) {
    final extra = extras.fold<double>(0, (a, x) => a + (x['amount'] as num).toDouble());
    final gross = hours * rate + extra;
    return Payslip(
      id: 's$emp',
      employeeId: emp,
      farmId: 'fa',
      periodStart: '2026-09-01',
      periodEnd: '2026-09-26',
      paidDate: '2026-09-27',
      gross: gross,
      hoursWorked: hours,
      hourlyRate: rate,
      extraPay: extra,
      extras: extras,
      paye: paye,
      uif: uif,
      rent: 0,
      loan: loan,
      tuckshopDeduction: tuck,
      nett: gross - paye - uif - loan - tuck,
      createdAt: DateTime(2026),
    );
  }

  test('run PDF: landscape summary page first, then the payslips', () async {
    final slips = [
      (
        slip('a', uif: 24, tuck: 120, loan: 100, extras: [
          {'description': 'Sunday work', 'hours': 8, 'rate': 45, 'amount': 360},
          {'description': 'Bonus', 'amount': 250},
        ]),
        Employee(id: 'a', firstName: 'Annie', lastName: '', fullNames: 'Anna Maria', surname: 'Mokoena', idOrPassport: '8505055009081', paymentMethod: PaymentMethod.bank, bankName: 'Capitec', bankAccountNo: '1234567890'),
      ),
      (slip('b', hours: 64), Employee(id: 'b', firstName: 'Ben', lastName: 'Sithole')),
    ];
    final doc = await buildRunPdf(farmName: 'Limpopodraai', slips: slips);
    final bytes = await doc.save();
    expect(bytes.length, greaterThan(1000));
    // Known by another name: in brackets after the names on the ID.
    expect(payslipName(slips.first.$2), 'Anna Maria Mokoena (Annie)');
    expect(payslipName(Employee(id: 'c', firstName: 'Anna', lastName: '', fullNames: 'Anna Maria', surname: 'Mokoena')), 'Anna Maria Mokoena');
    // The Summary button's preview: the summary page only.
    final preview = await buildRunPdf(farmName: 'Limpopodraai', slips: slips, preview: true);
    final previewBytes = await preview.save();
    final previewOut = Platform.environment['PREVIEW_OUT'];
    if (previewOut != null) File(previewOut).writeAsBytesSync(previewBytes);
    final out = Platform.environment['PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
