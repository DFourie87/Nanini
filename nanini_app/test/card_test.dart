import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/cards/card_models.dart';
import 'package:nanini_app/features/cards/card_repository.dart';
import 'package:nanini_app/features/cards/card_screen.dart';
import 'package:nanini_app/features/cards/card_xlsx.dart';

// Made-up figures, laid out as ABSA's statements are.
CardStatement st(String id, String date, double opening, double closing) => CardStatement(id: id, date: date, opening: opening, closing: closing);
CardLine ln(String id, String sid, String date, String what, double amount, {String? sent, bool manual = false}) =>
    CardLine(id: id, statementId: sid, date: date, description: what, amount: amount, xeroSentAt: sent, manual: manual);

final statements = [
  st('mar', '2026-03-11', 200000, 15), // with February's lines
  st('apr', '2026-04-10', 15, 18),
  st('sep', '2026-09-09', 30, 33), // statements in between missing
  st('oct', '2026-10-09', 33, -1000),
];
final lines = [
  ln('a', 'mar', '2026-02-14', 'Nanini 121 CC', 100000),
  ln('b', 'mar', '2026-02-18', 'ABSA BRANCHES', -300000),
  ln('c', 'mar', '2026-03-11', 'Interest', 15),
  ln('d', 'apr', '2026-04-10', 'Interest', 3),
  ln('e', 'sep', '2026-09-09', 'Interest', 3),
  ln('f', 'oct', '2026-10-02', 'CARD FEE', -80),
  ln('g', 'oct', '2026-10-05', 'EXTERNAL PURCHASE', -953),
];

void main() {
  test('the year: opening from the first statement (its lines before 1 March), each statement checked against its lines', () {
    final y = cardYear(card: CardKind.credit, yearStart: '2026-03-01', statements: statements, lines: lines);
    expect((y.opening, y.openingFrom), (0.0, 'statement'));
    expect([for (final m in y.months) m.statement.id], ['mar', 'apr', 'sep', 'oct']);
    expect(y.months[0].lines.map((l) => l.id), ['c']);
    expect(y.months[0].difference, 0);
    expect(y.months[1].difference, 0);
    expect(y.months[2].opening, 18);
    expect(y.months[2].difference, 12); // the statements in between
    expect(y.months[3].difference, 0);
    expect(y.paidIn, 21);
    expect(y.spent, -1033);
    expect(y.differences, 12);
    expect(y.closing, -1000);
    expect(y.xeroOpening, 18);
    final entered = cardYear(card: CardKind.credit, yearStart: '2026-03-01', opening: 5, statements: statements, lines: lines);
    expect((entered.opening, entered.openingFrom, entered.months[0].difference), (5.0, 'entered', -5.0));
  });

  test('to Xero: the lines from 1 Sep not sent yet', () {
    final y = cardYear(
      card: CardKind.fleet,
      yearStart: '2026-03-01',
      statements: statements,
      lines: [for (final l in lines) l.id == 'f' ? ln('f', 'oct', '2026-10-02', 'CARD FEE', -80, sent: 'x') : l],
    );
    final todo = cardXeroLines(y);
    expect(todo.map((l) => l.id), ['e', 'g']);
    expect(cardXeroRows(CardKind.fleet, todo, {for (final s in statements) s.id: s}), [
      ['*Date', '*Amount', 'Payee', 'Description', 'Reference'],
      ['09/09/2026', '3.00', 'ABSA Fleet Card', 'Interest', 'Statement 9 Sep 2026'],
      ['05/10/2026', '-953.00', 'ABSA Fleet Card', 'EXTERNAL PURCHASE', 'Statement 9 Oct 2026'],
    ]);
  });

  test('the working paper as Excel', () {
    final y = cardYear(card: CardKind.credit, yearStart: '2026-03-01', statements: statements, lines: lines);
    final x = Excel.decodeBytes(cardWorkingPaperXlsx(y, preparedOn: '2026-11-21'));
    final rows = x['Credit card'].rows.map((r) => r.map((c) => c?.value?.toString() ?? '').join('|')).toList();
    expect(rows.first, startsWith('Nanini 121 CC -- ABSA credit card (Xero: NANINI CREDIT)'));
    expect(rows.any((r) => r.startsWith('Balance per statement 9 Oct 2026') && r.contains('-1000')), isTrue);
    expect(rows.any((r) => r.contains('Not explained by the lines') && r.contains('12')), isTrue);
  });

  testWidgets('the screen: a line added by hand, already in Xero, the CSV and the Excel working paper', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    final saved = <String, Uint8List>{};
    await tester.pumpWidget(
      MaterialApp(
        home: CardScreen(
          card: CardKind.credit,
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
    expect(find.textContaining('A line left out'), findsOneWidget);

    await tester.tap(find.byKey(const Key('card_add_2026-09-09')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('card_line_what')), 'Interest (statements missing)');
    await tester.enterText(find.byKey(const Key('card_line_amount')), '12');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(repo.rows.last.manual, isTrue);
    expect(find.textContaining('A line left out'), findsNothing);

    // The lines listed before saving; Cancel marks nothing.
    await tester.tap(find.byKey(const Key('card_xero_csv')));
    await tester.pumpAndSettle();
    expect(find.text('4 line(s) for Xero, -R1 018.00'), findsOneWidget);
    expect(find.textContaining('5 Oct 2026  EXTERNAL PURCHASE  -R953.00'), findsOneWidget);
    expect(find.text('Already in Xero'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((saved.length, repo.sent.length), (0, 0));

    // Saved: marked, and where it went with what to do in Xero.
    await tester.tap(find.byKey(const Key('card_xero_csv')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card_save_csv')));
    await tester.pumpAndSettle();
    expect(repo.sent.length, 4);
    expect(find.text('Saved for Xero'), findsOneWidget);
    expect(find.textContaining('Import a statement'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    repo.sent.clear();
    saved.clear();
    await tester.tap(find.byKey(const Key('card_add_2026-10-09')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('card_line_what')), 'Interest');
    await tester.enterText(find.byKey(const Key('card_line_amount')), '1');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card_xero_csv')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card_save_csv')));
    await tester.pumpAndSettle();
    expect(utf8.decode(saved.values.single), contains('09/10/2026,1.00,ABSA Credit Card,Interest'));
    expect(repo.sent, [repo.rows.last.id]);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('card_excel')));
    await tester.pumpAndSettle();
    expect(saved.keys, contains('Credit card working paper year 2027.xlsx'));
    expect(tester.takeException(), isNull);
  });
}

class _Repo extends CardRepository {
  final rows = [...lines];
  final sent = <String>[];
  final marked = <String>{};

  @override
  Future<List<CardStatement>> fetchStatements(CardKind card) async => statements;
  @override
  Future<List<CardLine>> fetchLines(List<String> statementIds) async => [
    for (final l in rows) marked.contains(l.id) ? ln(l.id, l.statementId, l.date, l.description, l.amount, sent: 'now', manual: l.manual) : l,
  ];
  @override
  Future<Map<String, double>> fetchOpenings(CardKind card) async => const {};
  @override
  Future<void> addLine({required String statementId, required String date, required String description, required double amount}) async =>
      rows.add(ln('n${rows.length}', statementId, date, description, amount, manual: true));
  @override
  Future<void> markSent(List<String> lineIds) async {
    sent.addAll(lineIds);
    marked.addAll(lineIds);
  }
}
