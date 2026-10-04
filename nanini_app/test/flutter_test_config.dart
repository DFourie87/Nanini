import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/run_once.dart';

/// Every test starts with every button free (see resetRunOnce).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(resetRunOnce);
  await testMain();
}
