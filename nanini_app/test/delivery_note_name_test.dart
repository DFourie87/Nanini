import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_note_preview.dart';

DeliveryNote _note(int? number) => DeliveryNote(
      id: 'n1',
      noteNumber: number,
      noteDate: '2026-10-28',
      pallets: const {},
      mixedPallets: const [],
      produceType: 'potato',
      total: 0,
      createdAt: DateTime(2026, 10, 28),
    );

void main() {
  test('A shared or printed delivery note is named with its number', () {
    expect(deliveryNoteFileName(_note(261010)), 'Nanini Boerdery - Delivery Note 261010.pdf');
    expect(deliveryNoteFileName(_note(null)), 'Nanini Boerdery - Delivery Note draft.pdf');
  });
}
