import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/pallet_stock.dart';

DeliveryNote _note(String agent, int pallets, String date, {String produce = 'potato'}) => DeliveryNote(
    id: '$agent$date', agentName: agent, noteDate: date, pallets: const {}, mixedPallets: const [], produceType: produce, total: pallets, createdAt: DateTime(2026));

void main() {
  test('Pallets sent to each agent: this season and all', () {
    final sent = palletsSentByAgent([
      _note('B', 32, '2026-10-01'),
      _note('A', 30, '2026-10-02'),
      _note('B', 20, '2026-04-01'),
      _note('A', 500, '2026-10-03', produce: 'pepper'),
    ], from: '2026-09-01');
    expect(sent.keys, ['A', 'B']);
    expect(sent['A'], (30, 30));
    expect(sent['B'], (32, 52));
  });
}
