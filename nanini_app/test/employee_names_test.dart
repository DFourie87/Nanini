import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/capture_app/ref_data.dart';
import 'package:nanini_app/features/employees/employees_models.dart';

void main() {
  test('name everyone knows + surname, never the full names', () {
    Employee e(String first, {String last = '', String? full, String? surname}) =>
        Employee(id: 'x', firstName: first, lastName: last, fullNames: full, surname: surname);
    expect(e('Sipho', full: 'Siphiwe Johannes', surname: 'Dlamini').displayName, 'Sipho Dlamini');
    expect(e('Sipho Dlamini', surname: 'Dlamini').displayName, 'Sipho Dlamini');
    expect(e('Sipho', last: 'Dlamini').displayName, 'Sipho Dlamini');
    expect(e('Sipho').displayName, 'Sipho');
  });

  test('capture phones: name + surname shown, the known name kept for editing', () {
    const p = RefPerson(id: 'x', name: 'Sipho', fullNames: 'Siphiwe Johannes', surname: 'Dlamini');
    expect(p.name, 'Sipho Dlamini');
    expect(p.knownName, 'Sipho');
    expect(RefPerson.fromJson(p.toJson()).name, 'Sipho Dlamini');
  });
}
