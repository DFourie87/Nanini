import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/hours/hours_models.dart';
import 'package:nanini_app/features/hours/pay_run.dart';

// Made-up workers and figures.
final limpo = Farm(id: 'fl', name: 'Farm Limpopodraai - Stockpoort');
final haas = Farm(id: 'fh', name: 'Farm Haaskraal - Swartwater');

Employee worker(String id, Farm farm) => Employee(id: id, firstName: id, lastName: '', farmId: farm.id, ratePerHour: 20);

HoursEntry h(String emp, String date, double hours, {String? farm, double? special, String? group}) => HoursEntry(
      id: '$emp$date',
      employeeId: emp,
      date: date,
      hours: hours,
      rate: 20,
      dailyThreshold: 9,
      otMultiplier: 1.5,
      normalHours: hours,
      otHours: 0,
      gross: hours * 20,
      farmId: farm,
      specialRate: special,
      groupName: group,
    );

void main() {
  test('Haaskraal: hours on a Saturday or Sunday at 1.5 x the tariff; other farms and weekdays at the tariff', () {
    // Fri 13, Sat 14, Sun 15 Nov 2026.
    final work = [
      h('anna', '2026-11-13', 8),
      h('anna', '2026-11-14', 6),
      h('anna', '2026-11-15', 4),
      h('ben', '2026-11-14', 6), // Limpopodraai: the tariff
      h('anna', '2026-11-21', 5, farm: 'fl'), // Haaskraal's worker, a Saturday at Limpopodraai: the tariff
      h('cas', '2026-11-22', 3, farm: 'fh'), // Limpopodraai's worker, a Sunday at Haaskraal: 1.5 x
      h('cas', '2026-11-21', 2, farm: 'fh', special: 28, group: 'Potatoes'), // a group's own tariff: as it is
    ];
    final lines = buildPayRun(
      payUpTo: '2026-11-27',
      employees: [worker('anna', haas), worker('ben', limpo), worker('cas', limpo)],
      entries: work,
      kgEntries: const [],
      purchases: const [],
      payslips: const [],
      weekendFarms: weekendRateFarmIds([limpo, haas]),
    );
    final anna = lines.firstWhere((l) => l.employee.id == 'anna');
    expect((anna.tariffHours, anna.weekendHours), (13.0, 10.0));
    expect(anna.hoursPay, 13 * 20 + 10 * 30);
    expect(anna.specialHours.single.description, 'Hours: Weekend');
    final slip = draftPayslip(anna, upTo: '2026-11-27', paidDate: '2026-11-27');
    expect(slip.gross, 560);
    expect(slip.extras.single, {'description': 'Hours: Weekend', 'hours': 10.0, 'rate': 30.0, 'amount': 300.0});
    final ben = lines.firstWhere((l) => l.employee.id == 'ben');
    expect((ben.weekendHours, ben.hoursPay), (0.0, 120.0));
    final cas = lines.firstWhere((l) => l.employee.id == 'cas');
    expect((cas.weekendHours, cas.hoursPay), (3.0, 3 * 30 + 2 * 28));
    // Without the farms given (e.g. the members' run): as before.
    final plain = buildPayRun(
        payUpTo: '2026-11-27', employees: [worker('anna', haas)], entries: work, kgEntries: const [], purchases: const [], payslips: const []);
    expect(plain.single.hoursPay, 23 * 20);
  });
}
