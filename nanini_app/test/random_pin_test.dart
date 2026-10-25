import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/auth/auth_repository.dart';

void main() {
  test('Make a PIN: 6 digits, a valid PIN, never an easy one', () {
    final r = Random(7);
    for (var i = 0; i < 2000; i++) {
      final pin = randomPin(r);
      expect(pin.length, kMinPinLength);
      expect(isValidPin(pin), isTrue);
      expect(RegExp(r'^(\d)\1+$').hasMatch(pin), isFalse, reason: pin);
      expect(['012345', '123456', '234567', '345678', '456789', '987654', '876543', '765432', '654321', '543210'], isNot(contains(pin)));
    }
  });
}
