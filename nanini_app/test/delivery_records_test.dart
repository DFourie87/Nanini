import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_records_screen.dart';

DeliveryNote _n(String id, String produce, String date, {String? reg, int? no}) => DeliveryNote(
    id: id, noteNumber: no, reg: reg, noteDate: date, pallets: const {}, mixedPallets: const [], produceType: produce, total: 1, createdAt: DateTime(2026));

void main() {
  test('Delivery notes per produce; a truck with two produce under both, each pointing to the other', () {
    final notes = [
      _n('a', 'pepper', '2026-10-20', reg: 'ABC 123 L', no: 26110),
      _n('b', 'butternut', '2026-10-20', reg: 'abc123l', no: 26111),
      _n('c', 'potato', '2026-10-20', reg: 'XYZ 9', no: 26112),
      _n('d', 'pepper', '2026-10-21', reg: 'ABC 123 L', no: 26113),
      _n('e', 'potato', '2026-10-22', no: 26114), // pending: no registration yet
    ];
    final groups = deliveryNotesByProduce(notes);
    expect(groups.map((g) => g.$1), ['potato', 'pepper', 'butternut']);
    expect(groups.map((g) => g.$2.map((n) => n.id).join()), ['ce', 'ad', 'b']);
    expect(sameTruck(notes[0], notes).map((n) => n.id), ['b']); // same day and truck, spaces/case aside
    expect(sameTruck(notes[1], notes).map((n) => n.id), ['a']);
    expect(sameTruck(notes[2], notes), isEmpty); // another truck
    expect(sameTruck(notes[3], notes), isEmpty); // same truck, another day
    expect(sameTruck(notes[4], notes), isEmpty);
    expect(produceLabel('butternut'), 'Butternuts');
  });
}
