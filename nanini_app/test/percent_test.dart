import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/formatters.dart';

void main() {
  int sum(List<int> l) => l.fold(0, (a, b) => a + b);

  test('whole percentages always add up to 100', () {
    expect(wholePercents([1, 1, 1]), [34, 33, 33]); // not 33 + 33 + 33 = 99
    expect(wholePercents([12.5, 12.5, 12.5, 12.5, 50]), hasLength(5));
    expect(sum(wholePercents([12.5, 12.5, 12.5, 12.5, 50])), 100); // not 13 x 4 + 50 = 102
    expect(wholePercents([2, 1, 1]), [50, 25, 25]);
    for (final v in <List<double>>[
      [1234.5, 876.2, 45.1, 3.3],
      [0.4, 0.3, 0.3],
      [7, 7, 7, 7, 7, 7],
    ]) {
      expect(sum(wholePercents(v)), 100, reason: '$v');
    }
    expect(wholePercents([0, 0]), [0, 0]);
  });
}
