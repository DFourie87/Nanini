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
    expect(botha.recipientId, 'r1');
    expect(botha.isCustomer, isTrue);
    expect(choices.firstWhere((c) => c.name == 'Local buyer').isCustomer, isFalse);
  });

  test('a recipient saved with a customer\'s exact name is that customer\'s, before word matches', () {
    final choices = customerChoices([
      ('c1', 'Botha Roodt Johannesburg'),
      ('c2', 'Wenpro Markagente'),
    ], [
      MarketAgent(id: 'r1', name: 'Grow Botha Roodt', attention: 'David Nel'),
      // Saved from the delivery note customers screen for Wenpro.
      MarketAgent(id: 'r2', name: 'Wenpro Markagente', attention: 'Koos', market: 'Tshwane Market'),
    ]);
    expect(choices.map((c) => c.name), ['Botha Roodt Johannesburg', 'Wenpro Markagente']);
    final wenpro = choices.firstWhere((c) => c.name == 'Wenpro Markagente');
    expect((wenpro.attention, wenpro.market, wenpro.recipientId), ('Koos', 'Tshwane Market', 'r2'));
  });
}
