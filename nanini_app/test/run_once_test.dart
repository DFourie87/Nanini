import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/run_once.dart';

void main() {
  test('A second tap while the first still saves is ignored; afterwards it works again', () async {
    var saves = 0;
    final slow = Completer<void>();
    Future<void> save() async {
      saves++;
      await slow.future;
    }

    final first = runOnce('add', save);
    await runOnce('add', save); // tapped again while loading
    expect(saves, 1);
    // Another button isn't held up.
    await runOnce('other', () async => saves++);
    expect(saves, 2);
    slow.complete();
    await first;
    await runOnce('add', () async => saves++);
    expect(saves, 3);
  });

  test('A failed save frees the button', () async {
    await expectLater(runOnce('fails', () async => throw StateError('no signal')), throwsStateError);
    var ran = false;
    await runOnce('fails', () async => ran = true);
    expect(ran, isTrue);
  });
}
