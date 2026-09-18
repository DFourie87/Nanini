// Basic smoke test placeholder.
//
// The app requires a live Supabase connection at startup (see lib/main.dart),
// so a full widget pump test needs a test double for SupabaseClient — not
// set up in this first version. See docs/ARCHITECTURE.md.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder', () {
    expect(1 + 1, 2);
  });
}
