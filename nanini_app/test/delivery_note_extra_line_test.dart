import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';
import 'package:nanini_app/features/delivery/delivery_note_preview.dart';

void main() {
  test('Delivery note: the extra line under the agent is read, and the note builds with it', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final n = DeliveryNote.fromJson({
      'id': 'n1',
      'note_number': 26111,
      'agent_name': 'Grow Green Network',
      'agent_extra': 'Stand 12, Cold room 3',
      'note_date': '2026-11-03',
      'pallets': {'large10': 2},
      'produce_type': 'potato',
      'total': 2,
    });
    expect(n.agentExtra, 'Stand 12, Cold room 3');
    expect(DeliveryNote.fromJson({'id': 'n2', 'note_date': '2026-11-03'}).agentExtra, isNull);
    final pdf = await (await buildDeliveryNotePdf(n)).save();
    expect(pdf.length, greaterThan(1000));
  });
}
