import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_note_preview.dart';

DeliveryNote _note(int? number, {String? agent}) => DeliveryNote(
      id: 'n1',
      noteNumber: number,
      agentName: agent,
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

  test('The customer / market agent goes in the name', () {
    expect(deliveryNoteFileName(_note(26107, agent: 'Grow Green Network')), 'Nanini Boerdery - Grow Green Network Delivery Note 26107.pdf');
    expect(deliveryNoteFileName(_note(26108, agent: ' Botha Roodt / JHB ')), 'Nanini Boerdery - Botha Roodt JHB Delivery Note 26108.pdf');
    expect(deliveryNoteFileName(_note(26109, agent: '  ')), 'Nanini Boerdery - Delivery Note 26109.pdf');
  });
}
