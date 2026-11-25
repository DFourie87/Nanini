import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';

void main() {
  test('The day a worker joined their group: read, and saved only once the database has it', () {
    final e = Employee.fromJson({
      'id': 'e1',
      'first_name': 'Example',
      'current_group_id': 'g1',
      'current_group_since': '2026-11-11',
      'payment_method': 'cash',
    });
    expect((e.groupSince, e.hasGroupSinceColumn), ('2026-11-11', true));
    expect(e.toUpdate()['current_group_since'], '2026-11-11');
    // Kept through a pay change.
    expect(e.copyWithPay(ratePerHour: 30).groupSince, '2026-11-11');
    // No group: no day.
    final none = Employee(id: 'e1', firstName: 'Example', lastName: '', groupSince: '2026-11-11', hasGroupSinceColumn: true);
    expect(none.toUpdate()['current_group_since'], isNull);
    // Before group_since.sql: not sent (saving would fail).
    final old = Employee.fromJson({'id': 'e1', 'first_name': 'Example', 'current_group_id': 'g1', 'payment_method': 'cash'});
    expect(old.toUpdate().containsKey('current_group_since'), isFalse);
  });
}
