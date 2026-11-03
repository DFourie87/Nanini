import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/tuckshop/tuckshop_purchases_screen.dart';

void main() {
  test('Tuck shop credit: up to what is on the account, whole items', () {
    expect(creditProblem('3', max: 3, isItem: true), isNull);
    expect(creditProblem('1', max: 3, isItem: true), isNull);
    expect(creditProblem('4', max: 3, isItem: true), 'Only 3 on the account');
    expect(creditProblem('1.5', max: 3, isItem: true), 'Whole items only');
    expect(creditProblem('', max: 3, isItem: true), 'Type how many to credit');
    expect(creditProblem('0', max: 3, isItem: true), 'Type how many to credit');
    expect(creditProblem('120,50', max: 120.5, isItem: false), isNull);
    expect(creditProblem('121', max: 120.5, isItem: false), startsWith('Only R'));
    expect(creditProblem('', max: 120.5, isItem: false), 'Type the amount to credit');
  });
}
