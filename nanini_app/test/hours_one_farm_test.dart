import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/hours/hours_repository.dart';

void main() {
  const here = 'farm-haaskraal';
  const names = {'farm-limpopodraai': 'Farm Limpopodraai - Stockpoort', 'farm-doornbult': 'Farm Doornbult'};

  test('Hours at another farm that day are found, per farm', () {
    final rows = [
      {'employee_id': 'w1', 'farm_id': 'farm-limpopodraai', 'hours': 9},
      {'employee_id': 'w2', 'farm_id': here, 'hours': 8.5},
      {'employee_id': 'w3', 'farm_id': 'farm-limpopodraai', 'hours': 10.5},
      {'employee_id': 'w3', 'farm_id': 'farm-doornbult', 'hours': 2},
    ];
    expect(clockedElsewhereFrom(rows, here, names), {
      'w1': 'Farm Limpopodraai - Stockpoort 9 h',
      'w3': 'Farm Limpopodraai - Stockpoort 10.5 h, Farm Doornbult 2 h',
    });
  });

  test('Hours on this farm, without a farm, or taken off to nothing are not a clash', () {
    final rows = [
      {'employee_id': 'w1', 'farm_id': here, 'hours': 9},
      {'employee_id': 'w2', 'farm_id': null, 'hours': 9},
      {'employee_id': 'w3', 'farm_id': 'farm-limpopodraai', 'hours': 9},
      {'employee_id': 'w3', 'farm_id': 'farm-limpopodraai', 'hours': -9},
    ];
    expect(clockedElsewhereFrom(rows, here, names), isEmpty);
  });
}
