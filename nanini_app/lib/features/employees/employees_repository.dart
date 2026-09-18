import '../../core/supabase_client.dart';
import 'employees_models.dart';

const kDefaultFarms = [
  'Farm Limpopodraai - Stockpoort',
  'Farm Haaskraal - Swartwater',
  'Farm Doornbult - Polokwane',
];

class EmployeesRepository {
  /// Live stream of employees, ordered by first name — matches the web
  /// app's `.order('first_name')`.
  Stream<List<Employee>> watchEmployees() {
    return sb
        .from('employees')
        .stream(primaryKey: ['id'])
        .order('first_name')
        .map((rows) => rows.map(Employee.fromJson).toList());
  }

  Stream<List<EmployeeGroup>> watchGroups() {
    return sb
        .from('employee_groups')
        .stream(primaryKey: ['id'])
        .map((rows) => rows.map(EmployeeGroup.fromJson).toList());
  }

  Future<List<Farm>> fetchFarms() async {
    final rows = await sb.from('farms').select().order('name');
    var farms = (rows as List).map((r) => Farm.fromJson(r as Map<String, dynamic>)).toList();
    if (farms.isEmpty) {
      final seeded = await sb.from('farms').insert(kDefaultFarms.map((n) => {'name': n}).toList()).select();
      farms = (seeded as List).map((r) => Farm.fromJson(r as Map<String, dynamic>)).toList();
    }
    farms.sort((a, b) {
      if (a.name.contains('Limpopodraai')) return -1;
      if (b.name.contains('Limpopodraai')) return 1;
      return a.name.compareTo(b.name);
    });
    return farms;
  }

  Future<void> addEmployee(Employee e) => sb.from('employees').insert(e.toInsert());

  Future<void> updateEmployee(String id, Employee e) => sb.from('employees').update(e.toInsert()).eq('id', id);

  Future<void> deleteEmployee(String id) => sb.from('employees').delete().eq('id', id);

  Future<void> addGroup(EmployeeGroup g) => sb.from('employee_groups').insert(g.toInsert());

  Future<void> updateGroup(String id, EmployeeGroup g) => sb.from('employee_groups').update(g.toInsert()).eq('id', id);

  Future<void> deleteGroup(String id) async {
    await sb.from('employees').update({'current_group_id': null}).eq('current_group_id', id);
    await sb.from('employee_groups').delete().eq('id', id);
  }
}
