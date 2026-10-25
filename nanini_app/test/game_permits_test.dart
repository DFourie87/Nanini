import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/employees/employees_models.dart';
import 'package:nanini_app/features/game_breeding/game_breeding_models.dart';
import 'package:nanini_app/features/game_breeding/game_breeding_repository.dart';
import 'package:nanini_app/features/game_breeding/game_permits_screen.dart';

class _Repo extends GameBreedingRepository {
  @override
  Stream<List<BuffaloRegistration>> watchRegistrations() => Stream.value([
        BuffaloRegistration(
          farmId: 'l',
          registrationNumber: 'BUF 123/2020',
          holderName: 'Nanini 121 CC',
          farmDescription: 'Limpopodraai 751 LQ and Portion 1 of Shortlands 752 LQ',
          fmdStatus: 'No',
        ),
      ]);
}

void main() {
  testWidgets('Permits: a long property wraps, each property on its own line (phone width)', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: GamePermitsScreen(repo: _Repo(), farms: () async => [Farm(id: 'l', name: 'Limpopodraai')])),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Limpopodraai 751 LQ\nPortion 1 of Shortlands 752 LQ'), findsOneWidget);
    expect(find.text('Foot and Mouth Disease infected'), findsOneWidget);
    expect(tester.takeException(), isNull); // no overflow
  });
}
