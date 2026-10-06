import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/delivery/delivery_models.dart';

void main() {
  test('approximate weight: each bag/box at its weight plus packaging (1% potatoes, 5% others)', () {
    // 2 pallets of Large 10kg (110 bags) + a mixed pallet of 20 x 7kg: (2200 + 140) x 1.01.
    expect(approxWeightKg(ProduceType.potato, pallets: {'large10': 2}, mixed: [{'med7': 20}]), closeTo(2363.4, 0.01));
    // 100 x 5kg + 50 x 4kg peppers: 700 x 1.05.
    expect(approxWeightKg(ProduceType.pepper, peppers: {'5kgRed': 100, '4kgYellow': 50}), closeTo(735, 0.01));
    expect(approxWeightKg(ProduceType.butternut, butternuts: {'10kg': 10, '7kg': 10}), closeTo(178.5, 0.01));
    expect(fmtApproxKg(2363.4), '2 363 kg');
    expect(fmtApproxKg(735), '735 kg');
  });
}
