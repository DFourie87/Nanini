import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/capture_app/capture_widgets.dart';
import 'package:nanini_app/theme/nanini_theme.dart';

// A phone set to a very large font: the number keys must all still fit.
Widget _hoursStep({required bool clamp}) => MaterialApp(
      theme: NaniniTheme.light,
      builder: clamp ? NaniniTheme.clampTextScale : null,
      home: StepPage(
        task: 'Hours',
        step: 3,
        steps: 4,
        question: 'How many hours did they work?',
        hint: 'Type the hours for each person',
        onBack: () {},
        onNext: () {},
        child: NumberPad(value: '', onChanged: (_) {}),
      ),
    );

bool _allKeysShow(WidgetTester tester) {
  final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', ',', '0', '⌫']) {
    final f = find.descendant(of: find.byType(OutlinedButton), matching: find.text(k));
    if (f.evaluate().isEmpty) return false;
    final r = tester.getRect(f);
    if (!screen.contains(r.topLeft) || !screen.contains(r.bottomRight - const Offset(1, 1))) return false;
  }
  return true;
}

void main() {
  testWidgets('A very large phone font: every number key still shows', (tester) async {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(_hoursStep(clamp: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_allKeysShow(tester), isTrue);
    expect(MediaQuery.of(tester.element(find.byType(NumberPad))).textScaler.scale(10), closeTo(10 * NaniniTheme.maxTextScale, 0.01));
  });

  testWidgets('Without the limit the large font hides keys (what the phone showed)', (tester) async {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(_hoursStep(clamp: false));
    await tester.pumpAndSettle();
    final overflowed = tester.takeException() != null;
    expect(overflowed || !_allKeysShow(tester), isTrue);
  });

  testWidgets('A small phone (360 x 640) with a very large font: every number key still shows', (tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(_hoursStep(clamp: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_allKeysShow(tester), isTrue);
  });
}
