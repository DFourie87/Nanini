import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/employees/proof_of_address_dialog.dart';
import 'package:nanini_app/features/employees/proof_of_address_pdf.dart';

Employee _member(String id, String name, String surname, {String? idNo, String? farmId}) =>
    Employee(id: id, firstName: name, lastName: '', fullNames: name, surname: surname, idOrPassport: idNo, farmId: farmId, isMember: true);

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
