import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/capture_app/ref_data.dart';
import 'package:nanini_app/features/employees/employees_models.dart';

void main() {
  test('farms are shown by name only, without "Farm" or the location', () {
    expect(farmDisplayName('Farm Limpopodraai - Stockpoort'), 'Limpopodraai');
    expect(farmDisplayName('Farm Haaskraal - Swartwater'), 'Haaskraal');
    expect(farmDisplayName('Farm Doornbult - Polokwane'), 'Doornbult');
    expect(farmDisplayName('Haaskraal'), 'Haaskraal');
    expect(Farm.fromJson({'id': 'a', 'name': 'Farm Doornbult - Polokwane'}).name, 'Doornbult');
    final ref = RefData.fromJson({
      'farms': [
        {'id': 'a', 'name': 'Farm Haaskraal - Swartwater'},
      ],
    });
    expect(ref.farms.single.name, 'Haaskraal');
  });
}
