import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/hours/member_loan.dart';

void main() {
  test('Members loan: lent less repaid', () {
    final entries = [
      MemberLoanEntry.fromJson({'id': '1', 'entry_date': '2026-01-01', 'kind': 'loan', 'amount': 100000}),
      MemberLoanEntry.fromJson({'id': '2', 'entry_date': '2026-09-30', 'kind': 'repayment', 'amount': 5000.50}),
      MemberLoanEntry.fromJson({'id': '3', 'entry_date': '2026-10-31', 'kind': 'repayment', 'amount': 5000.50, 'note': 'October'}),
    ];
    expect(entries.first.isLoan, isTrue);
    expect(entries.last.note, 'October');
    expect(memberLoanBalance(entries), closeTo(89999, 0.001));
  });
}
