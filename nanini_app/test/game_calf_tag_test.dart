import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/game_breeding/game_breeding_models.dart';

void main() {
  test("A calf's tag: the sire's initial and the dam's tag, as the herd's are made", () {
    const herd = ['PO20', 'SPO20', '1M10', 'T1M10', '328', 'B328'];
    // Shingwedzi x PO20 is SPO20 (already there): the next calf is 2SPO20.
    expect(suggestCalfTag(sire: 'Shingwedzi', dam: 'PO20', taken: herd), '2SPO20');
    expect(suggestCalfTag(sire: 'Shingwedzi', dam: 'PO20', taken: [...herd, '2SPO20']), '3SPO20');
    // Komati x 1M10: K1M10.
    expect(suggestCalfTag(sire: 'Komati', dam: '1M10', taken: herd), 'K1M10');
    // A sire by its tag (SPO20) -- its first letter.
    expect(suggestCalfTag(sire: 'SPO20', dam: '328', taken: herd), 'S328');
    // No sire known yet: the dam's tag alone (or numbered).
    expect(suggestCalfTag(sire: '', dam: 'Y64', taken: herd), 'Y64');
    expect(suggestCalfTag(sire: null, dam: '328', taken: herd), '2328');
    // The dam's birth year at the end of her tag (-21: born 2021) isn't the calf's.
    expect(suggestCalfTag(sire: 'Komati', dam: 'D²SJ26-21', taken: herd), 'KD²SJ26');
    expect(suggestCalfTag(sire: 'Thor', dam: 'Lb31-23', taken: herd), 'TLb31');
    expect(suggestCalfTag(sire: 'Thor', dam: 'Kr65-2019', taken: herd), 'TKr65');
    // No dam: nothing to suggest.
    expect(suggestCalfTag(sire: 'Thor', dam: '', taken: herd), '');
  });
}
