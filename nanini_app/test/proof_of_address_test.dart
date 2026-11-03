import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/employees/proof_of_address_dialog.dart';
import 'package:nanini_app/features/employees/proof_of_address_pdf.dart';
import 'package:nanini_app/features/employees/proof_of_address_utility.dart';
import 'package:nanini_app/features/suppliers/suppliers_models.dart';
import 'dart:convert';

Employee _member(String id, String name, String surname, {String? idNo, String? farmId, String? address}) =>
    Employee(id: id, firstName: name, lastName: '', fullNames: name, surname: surname, idOrPassport: idNo, farmId: farmId, isMember: true, residentialAddress: address);

void main() {
  test('Proof of address: the member, the ID, the farm address and since when', () {
    final p = proofOfAddressParagraphs(ProofOfAddress(
      memberName: 'Test Person Member',
      idNumber: '0000000000000',
      address: kFarmAddresses['Haaskraal']!,
      date: '2026-11-03',
      signedBy: 'Another Member',
      since: '2010',
    ));
    expect(p[0], contains('Test Person Member (identity number 0000000000000) is a member of NANINI 121 CC (registration number 2000/026925/23)'));
    expect(p[1], 'Farm Haaskraal 134MR, Swartwater, Limpopo Province, 0622');
    expect(p[2], 'Test Person Member has lived at this address since 2010.');
    // No ID and no "since": left out.
    final q = proofOfAddressParagraphs(
        ProofOfAddress(memberName: 'A B', idNumber: null, address: kFarmAddresses['Limpopodraai']!, date: '2026-11-03', signedBy: 'C D'));
    expect(q[0], isNot(contains('identity number')));
    expect(q.length, 3);
    expect(farmAddressFor('Haaskraal'), 'Haaskraal');
    expect(farmAddressFor('Limpopodraai'), 'Limpopodraai');
    expect(farmAddressFor(null), 'Limpopodraai');
  });

  test('What is said after the address: the farm, the registered office, or nothing (own address)', () {
    expect(addressNote('Limpopodraai'), 'This is the address of the farm run by NANINI 121 CC T/A NANINI BOERDERY.');
    expect(addressNote(kRegisteredOffice), 'This is the registered office of NANINI 121 CC.');
    expect(kFarmAddresses[kRegisteredOffice], ['Plot 108 Doornbult', 'Polokwane', 'Limpopo Province', '0699']);
    expect(addressNote(null), isNull);
    final own = proofOfAddressParagraphs(
        ProofOfAddress(memberName: 'A B', idNumber: '1', address: addressLines('1 Test Street\nTesttown, 0001'), date: '2026-11-03', signedBy: 'C D'));
    expect(own[1], '1 Test Street, Testtown, 0001');
    expect(own.last, startsWith('Please do not hesitate'));
    expect(addressLines(' 1 Test Street, Testtown \n\n 0001 '), ['1 Test Street', 'Testtown', '0001']);
    expect(addressLines(null), isEmpty);
  });

  testWidgets("A member's own address on file comes first", (tester) async {
    final members = [_member('m1', 'Anna', 'Alpha', idNo: '1', farmId: 'f1', address: '1 Test Street\nTesttown\n0001'), _member('m2', 'Ben', 'Beta')];
    await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => TextButton(onPressed: () => showProofOfAddress(context, members: members, farms: const []), child: const Text('go')))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Own: 1 Test Street, Testtown, 0001'), findsOneWidget);
  });

  testWidgets('Members with the same full names: the name they are known by too', (tester) async {
    final members = [
      Employee(id: 'a', firstName: 'Thys', lastName: '', fullNames: 'Test Same', surname: 'Name', isMember: true),
      Employee(id: 'b', firstName: 'Test', lastName: '', fullNames: 'Test Same', surname: 'Name', isMember: true),
    ];
    await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => TextButton(onPressed: () => showProofOfAddress(context, members: members, farms: const []), child: const Text('go')))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Test Same Name'), findsOneWidget);
    expect(find.text('Test Same Name (Thys)'), findsOneWidget);
  });

  test('The utility bill: the latest of the Eskom account, not older than 3 months before the letter', () {
    final suppliers = [Supplier(id: 's1', name: 'Eskom Test', accountNo: '1234 567 890'), Supplier(id: 's2', name: 'Eskom 999')];
    SupplierDoc bill(String id, String supplier, String date, {String? file = 'f.pdf'}) =>
        SupplierDoc(id: id, supplierId: supplier, kind: SupplierDocKind.statement, date: date, amount: 1, filePath: file);
    final docs = [bill('a', 's1', '2026-08-25'), bill('b', 's1', '2026-10-25'), bill('c', 's1', '2026-11-25'), bill('d', 's1', '2026-10-30', file: null), bill('e', 's2', '2026-11-01')];
    expect(utilityBillFrom('2026-11-03'), '2026-08-03');
    final (b, p) = latestUtilityBill('1234567890', suppliers, docs, '2026-11-03');
    expect(b?.id, 'b'); // not the one after the letter, not the one without its PDF
    expect(p, isNull);
    // By the number in the supplier's name too.
    expect(latestUtilityBill('999', suppliers, docs, '2026-11-03').$1?.id, 'e');
    final (old, why) = latestUtilityBill('1234567890', suppliers, [docs[0]], '2026-11-30');
    expect(old, isNull);
    expect(why, contains('more than 3 months'));
    expect(latestUtilityBill('555', suppliers, docs, '2026-11-03').$2, 'Eskom account 555 is not in the Suppliers app');
    expect(latestUtilityBill('999', suppliers, const [], '2026-11-03').$2, 'No bill for Eskom account 999 in the Suppliers app');
  });

  testWidgets('No letter when the Eskom bill is too old: says why', (tester) async {
    final members = [
      Employee(id: 'a', firstName: 'Anna', lastName: '', fullNames: 'Anna', surname: 'Alpha', isMember: true, utilityAccount: '123'),
      _member('b', 'Ben', 'Beta'),
    ];
    String? asked;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showProofOfAddress(context, members: members, farms: const [], loadUtility: (account, date) async {
                      asked = account;
                      return (null, 'The latest bill for Eskom account 123 is from 1 Jun 2026 -- more than 3 months before the letter\'s date.');
                    }),
                child: const Text('go')))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show letter'));
    await tester.pumpAndSettle();
    expect(asked, '123');
    expect(find.textContaining('more than 3 months'), findsOneWidget);
    expect(find.text('Show letter'), findsOneWidget); // still here: no letter
  });

  test('The letter with the utility bill page after it', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    final p = ProofOfAddress(
        memberName: 'A B', idNumber: '1', address: kFarmAddresses['Limpopodraai']!, date: '2026-11-03', signedBy: 'C D', utilityPage: png, utilityLabel: 'Eskom account 1, bill of 25 Oct 2026');
    expect(proofOfAddressParagraphs(p), contains('Attached is the first page of the latest utility account for this address (Eskom account 1, bill of 25 Oct 2026).'));
    expect((await (await buildProofOfAddressPdf(p)).save()).length, greaterThan(1000));
  });

  test('The letter builds', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final doc = await buildProofOfAddressPdf(
        ProofOfAddress(memberName: 'A B', idNumber: '123', address: kFarmAddresses['Limpopodraai']!, date: '2026-11-03', signedBy: 'C D'));
    expect((await doc.save()).length, greaterThan(1000));
  });

  testWidgets('Pick a member: the farm address follows, someone else signs', (tester) async {
    final farms = [Farm(id: 'f1', name: 'Limpopodraai'), Farm(id: 'f2', name: 'Haaskraal')];
    final members = [_member('m1', 'Anna', 'Alpha', idNo: '1', farmId: 'f1'), _member('m2', 'Ben', 'Beta', farmId: 'f2')];
    await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => TextButton(onPressed: () => showProofOfAddress(context, members: members, farms: farms), child: const Text('go')))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Anna Alpha'), findsOneWidget); // member
    expect(find.text('Ben Beta'), findsOneWidget); // signed by
    expect(find.text('Farm Limpopodraai 751LQ, Lephalale, Limpopo Province, 0555'), findsOneWidget);
    await tester.tap(find.byKey(const Key('poa_member')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ben Beta').last);
    await tester.pumpAndSettle();
    expect(find.text('Farm Haaskraal 134MR, Swartwater, Limpopo Province, 0622'), findsOneWidget);
    expect(find.text('No ID number on file: the letter goes without it (add it on the Members tab).'), findsOneWidget);
    expect(find.text('Anna Alpha'), findsOneWidget); // now signs
  });
}
