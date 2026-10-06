import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';

void main() {
  test('a delivery note\'s customer: every customer, with its recipient\'s contact and market', () {
    final recipients = [
      MarketAgent(id: 'r1', name: 'Grow Botha Roodt', attention: 'David Nel', market: 'Johannesburg Fresh Produce Market'),
      MarketAgent(id: 'r2', name: 'Dapper Market Agents', attention: 'Monty', market: 'Johannesburg Fresh Produce Market'),
      MarketAgent(id: 'r3', name: 'Local buyer', market: 'Lephalale'),
    ];
    final choices = customerChoices([
      ('c1', 'Botha Roodt Johannesburg'),
      ('c2', 'Dapper Agencies'),
      ('c3', 'Wenpro Markagente'),
      ('c4', 'Peppadew'),
    ], recipients);
    expect(choices.map((c) => c.name), ['Botha Roodt Johannesburg', 'Dapper Agencies', 'Local buyer', 'Peppadew', 'Wenpro Markagente']);
    final botha = choices.firstWhere((c) => c.name == 'Botha Roodt Johannesburg');
    expect((botha.id, botha.attention, botha.market), ('customer:c1', 'David Nel', 'Johannesburg Fresh Produce Market'));
    expect(choices.firstWhere((c) => c.name == 'Dapper Agencies').attention, 'Monty');
    expect(choices.firstWhere((c) => c.name == 'Wenpro Markagente').attention, isNull);
  });
}
