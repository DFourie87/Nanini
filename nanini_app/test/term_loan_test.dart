import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/term_loan/term_loan_models.dart';
import 'package:nanini_app/features/term_loan/term_loan_repository.dart';
import 'package:nanini_app/features/term_loan/term_loan_screen.dart';
import 'package:nanini_app/features/term_loan/term_loan_xlsx.dart';

// Made-up figures, laid out as ABSA's statements are.
TermLoanStatement st(String id, String date, double capital, double advance, {String? from, double? interestSent}) => TermLoanStatement(
  id: id,
  date: date,
  from: from,
  to: date,
  capital: capital,
  advance: advance,
  rate: 12,
  xeroInterestSent: interestSent,
  interestPortion: 1000,
  interestBenefit: 900,
);

TermLoanLine ln(String id, String sid, String date, String what, double amount, {bool manual = false, String? sent}) =>
    TermLoanLine(id: id, statementId: sid, date: date, description: what, amount: amount, manual: manual, xeroSentAt: sent);

final statements = [
  st('feb', '2026-02-17', 5000000, 3700000),
  st('mar', '2026-03-17', 5000000, 3600000, from: '2026-02-17'), // -1 400 000
  st('apr', '2026-04-17', 5050000, 3640000, from: '2026-03-17'), // -1 410 000: nothing listed
  st('jul', '2026-07-17', 5100000, 3988000, from: '2026-06-17'), // -1 112 000: a payment left out
  st('sep', '2026-09-17', 5200000, 4100000, from: '2026-08-17'), // -1 100 000
];
final lines = [
  ln('a', 'mar', '2026-02-20', 'Transfer debit', -100000), // before the year: in the opening
  ln('b', 'mar', '2026-03-01', 'Instalment due', 50000),
  ln('c', 'mar', '2026-03-03', 'Transfer debit', -400000),
  ln('d', 'sep', '2026-08-25', 'Transfer credit', 5000),
  ln('e', 'sep', '2026-09-05', 'Transfer credit', 10000),
  ln('f', 'sep', '2026-09-01', 'Instalment due', 52000),
];

void main() {
  test('the year: from the opening balance, each statement\'s money and the rest as interest; a month short flagged', () {
    final y = termLoanYear(yearStart: '2026-03-01', opening: -1000000, statements: statements, lines: lines);
    expect(y.yearEnd, '2027-02-28');
    expect([for (final m in y.months) m.statement.id], ['mar', 'apr', 'jul', 'sep']);
    final mar = y.months[0];
    expect(mar.opening, -1000000);
    expect(mar.money.map((l) => l.id), ['c']); // not February's
    expect(mar.info.map((l) => l.id), ['b']);
    expect(mar.interest, 0);
    expect(y.months[1].interest, -10000);
    expect((y.interestPortion, y.interestBenefit, y.interestNet), (4000.0, 3600.0, 400.0));
    expect(y.months[1].looksShort, isFalse);
    final jul = y.months[2];
    expect(jul.interest, 298000);
    expect(jul.looksShort, isTrue);
    // The payment the statement left out, added by hand.
    final fixed = termLoanYear(
      yearStart: '2026-03-01',
      opening: -1000000,
      statements: statements,
      lines: [...lines, ln('m', 'jul', '2026-06-25', 'Payment', 300000, manual: true)],
    );
    expect(fixed.months[2].interest, -2000);
    expect(fixed.months[2].looksShort, isFalse);
    expect(fixed.paidIn, 315000);
    expect(fixed.drawn, -400000);
    expect(fixed.interest, -10000 - 2000 - 3000);
    expect(fixed.closing, -1100000);
    expect(-1000000 + fixed.paidIn + fixed.drawn + fixed.interest, fixed.closing);
    // Xero opens on 31 Aug: the balance before the September statement, with its August line.
    expect(fixed.xeroOpening, -1112000 + 5000);
    // No opening balance entered: the last statement before the year.
    final noOpening = termLoanYear(yearStart: '2026-03-01', statements: statements, lines: lines);
    expect((noOpening.opening, noOpening.openingEntered), (-1300000.0, false));
    expect(termLoanYearStart('2027-02-17'), '2026-03-01');
    expect(termLoanYearStart('2027-03-17'), '2027-03-01');
  });

  test('to Xero: payments and drawings from 1 Sep and each month\'s interest, once; changed interest listed', () {
    final y = termLoanYear(yearStart: '2026-03-01', opening: -1000000, statements: statements, lines: lines);
    final r = termLoanXeroItems(y);
    expect([for (final i in r.items) (i.date, i.amount)], [('2026-09-05', 10000.0), ('2026-09-17', -3000.0)]);
    expect(termLoanXeroRows(r.items), [
      ['*Date', '*Amount', 'Payee', 'Description', 'Reference'],
      ['05/09/2026', '10000.00', 'ABSA Term Loan 3053810190', 'Transfer credit', 'Term loan statement 17 Sep 2026'],
      ['17/09/2026', '-3000.00', 'ABSA Term Loan 3053810190', 'Interest and charges (net) to 17 Sep 2026', 'Term loan statement 17 Sep 2026'],
    ]);
    // Sent: not again; the interest sent as -2 500 has changed since.
    final sent = termLoanYear(
      yearStart: '2026-03-01',
      opening: -1000000,
      statements: [...statements.where((s) => s.id != 'sep'), st('sep', '2026-09-17', 5200000, 4100000, interestSent: -2500)],
      lines: [for (final l in lines) l.id == 'e' ? ln('e', 'sep', '2026-09-05', 'Transfer credit', 10000, sent: '2026-09-20') : l],
    );
    final again = termLoanXeroItems(sent);
    expect(again.items, isEmpty);
    expect(again.changed.map((m) => m.statement.id), ['sep']);
  });

  test('the working paper as Excel: the lead schedule and every statement', () {
    final y = termLoanYear(yearStart: '2026-03-01', opening: -1000000, statements: statements, lines: lines);
    final x = Excel.decodeBytes(termLoanWorkingPaperXlsx(y, preparedOn: '2026-11-21'));
    final rows = x['Term loan'].rows.map((r) => r.map((c) => c?.value?.toString() ?? '').toList()).toList();
    String find(String start) => rows.firstWhere((r) => r.first.startsWith(start) || (r.length > 1 && r[1].startsWith(start))).join('|');
    expect(rows.first.first, 'Nanini 121 CC -- ABSA term loan 3053810190');
    expect(find('Opening balance 1 Mar 2026'), contains('-1000000'));
    expect(find('Balance per statement 17 Sep 2026'), contains('-1100000'));
    expect(find('Statement 17 Jul 2026'), isNotEmpty);
    expect(rows.any((r) => r.join('|').contains('a payment or drawing left off the statement?')), isTrue);
    expect(rows.last.join('|'), startsWith('Total|4000|3600|400|'));
  });

  testWidgets('the screen: the year, a line added by hand, the CSV for Xero and the Excel working paper', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    final saved = <String, Uint8List>{};
    await tester.pumpWidget(
      MaterialApp(
        home: TermLoanScreen(
          repo: repo,
          today: DateTime(2026, 11, 21),
          save: (n, b) async {
            saved[n] = b;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Year 2027 (1 Mar 2026 to 28 Feb 2027)'), findsOneWidget);
    expect(find.textContaining('the statement left a payment or drawing out?'), findsOneWidget);
    expect(find.textContaining('should open on'), findsOneWidget);

    await tester.tap(find.byKey(const Key('term_loan_add_2026-07-17')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('term_loan_line_what')), 'Payment from ABSA current account');
    await tester.enterText(find.byKey(const Key('term_loan_line_amount')), '300000');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(repo.rows.last.amount, 300000);
    expect(repo.rows.last.manual, isTrue);
    expect(find.textContaining('the statement left a payment or drawing out?'), findsNothing);

    await tester.tap(find.byKey(const Key('term_loan_xero_csv')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('term_loan_save_csv')));
    await tester.pumpAndSettle();
    final csv = utf8.decode(saved.entries.firstWhere((e) => e.key.endsWith('.csv')).value);
    expect(csv, contains('05/09/2026,10000.00'));
    expect(repo.sent.length, 2);
    expect(find.text('Saved for Xero'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('term_loan_excel')));
    await tester.pumpAndSettle();
    expect(saved.keys, contains('Term loan working paper year 2027.xlsx'));
    expect(tester.takeException(), isNull);
  });
}

class _Repo extends TermLoanRepository {
  final rows = [...lines];
  final sent = <TermLoanXeroItem>[];

  @override
  Future<List<TermLoanStatement>> fetchStatements() async => statements;
  @override
  Future<List<TermLoanLine>> fetchLines() async => rows;
  @override
  Future<Map<String, double>> fetchOpenings() async => {'2026-03-01': -1000000};
  @override
  Future<void> addLine({required String statementId, required String date, required String description, required double amount}) async =>
      rows.add(ln('n${rows.length}', statementId, date, description, amount, manual: true));
  @override
  Future<void> markSent(List<TermLoanXeroItem> items) async => sent.addAll(items);
}
