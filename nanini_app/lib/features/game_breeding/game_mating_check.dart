import 'package:flutter/material.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import 'game_bloodline_book.dart' show bookName;
import 'game_breeding_models.dart';

/// Mating guide > Check an animal: an animal not in the herd (one to buy,
/// or a new one) -- its sire and dam, and grandparents if known -- against
/// a book's animals of the other sex: the calf's inbreeding with each, from
/// the register's pedigrees. Only worked out here; nothing is stored.
class GameMatingCheckScreen extends StatefulWidget {
  const GameMatingCheckScreen({super.key, required this.animals, required this.parents, required this.book});
  final List<GameAnimal> animals;

  /// The register's (and logged births') parents, by tag.
  final Map<String, (String?, String?)> parents;

  /// The herd it's checked against (its animals' owner).
  final String book;

  @override
  State<GameMatingCheckScreen> createState() => _GameMatingCheckScreenState();
}

/// The animal being checked, in the pedigree.
const _checked = '\u0000checked';

class _GameMatingCheckScreenState extends State<GameMatingCheckScreen> {
  String sex = 'F';
  final name = TextEditingController();
  final fields = {for (final k in ['sire', 'dam', 'sireSire', 'sireDam', 'damSire', 'damDam']) k: TextEditingController()};

  @override
  void dispose() {
    name.dispose();
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  late final _byKey = {
    for (final a in widget.animals) ...{a.tag.toLowerCase(): a.tag, if ((a.name ?? '').isNotEmpty) a.name!.toLowerCase(): a.tag},
  };

  /// What was typed, as a tag: the register's when it's there ("Shingwedzi
  /// 49 5/8"" is Shingwedzi), else the words themselves; null when empty.
  String? _resolve(String typed) {
    var t = typed.trim();
    if (t.isEmpty) return null;
    t = t.replaceAll(RegExp(r'\s*\(.*?\)\s*'), ' ').trim().replaceFirst(RegExp(r'\s+\d+(\s\d+/\d+)?"\+?.*$'), '').trim();
    return _byKey[t.toLowerCase()] ?? t;
  }

  bool _known(String? tag) => tag != null && widget.parents.containsKey(tag);

  @override
  Widget build(BuildContext context) {
    final sire = _resolve(fields['sire']!.text), dam = _resolve(fields['dam']!.text);
    // The pedigree: the register's, plus the checked animal and its parents
    // as typed (a parent in the register keeps its own parents).
    final parents = {...widget.parents, _checked: (sire, dam)};
    if (sire != null && !_known(sire)) parents[sire] = (_resolve(fields['sireSire']!.text), _resolve(fields['sireDam']!.text));
    if (dam != null && !_known(dam)) parents[dam] = (_resolve(fields['damSire']!.text), _resolve(fields['damDam']!.text));
    final ped = Pedigree(parents);
    final ready = sire != null || dam != null;
    final mates = widget.animals.where((a) => a.onFarm && a.isAlive && a.owner == widget.book && a.sex == (sex == 'F' ? 'M' : 'F')).toList();
    final results = [for (final m in mates) (m, ped.kinship(_checked, m.tag) * 100, ped.shared(_checked, m.tag)..remove(_checked))]
      ..sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.tag.toLowerCase().compareTo(b.$1.tag.toLowerCase()));
    final own = ped.inbreeding(_checked) * 100;
    final label = name.text.trim().isEmpty ? (sex == 'F' ? 'This cow' : 'This bull') : name.text.trim();

    Widget field(String key, String text, {bool indent = false}) {
      final typed = fields[key]!.text.trim();
      final tag = _resolve(typed);
      return Padding(
        // Boxes come and go above it: each keeps its own text.
        key: ValueKey(key),
        padding: EdgeInsets.only(left: indent ? 24 : 0, top: 6),
        child: Autocomplete<String>(
          initialValue: TextEditingValue(text: fields[key]!.text),
          optionsBuilder: (v) {
            final q = v.text.trim().toLowerCase();
            if (q.isEmpty) return const [];
            return widget.animals.map((a) => a.tag).where((t) => t.toLowerCase().contains(q)).take(8);
          },
          onSelected: (v) => setState(() => fields[key]!.text = v),
          fieldViewBuilder: (ctx, controller, focus, onSubmit) => TextField(
            controller: controller,
            focusNode: focus,
            onChanged: (v) => setState(() => fields[key]!.text = v),
            decoration: InputDecoration(
              labelText: text,
              isDense: true,
              helperText: tag == null ? null : (_known(tag) ? 'In the register – its own pedigree counts' : 'Not in the register'),
            ),
          ),
        ),
      );
    }

    // Grandparents only for a parent that isn't in the register (else its own count).
    final sireKnown = _known(sire), damKnown = _known(dam);
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Check an animal'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('An animal you may buy, or a new one: its calf with each of your animals is worked out here. Nothing is saved.',
              style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'F', label: Text('A cow')), ButtonSegment(value: 'M', label: Text('A bull'))],
            selected: {sex},
            onSelectionChanged: (s) => setState(() => sex = s.first),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(selectedBackgroundColor: NaniniColors.rust, selectedForegroundColor: Colors.white),
          ),
          TextField(controller: name, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Name or tag (optional)')),
          field('sire', 'Sire'),
          if (sire != null && !sireKnown) ...[field('sireSire', "Sire's sire (optional)", indent: true), field('sireDam', "Sire's dam (optional)", indent: true)],
          field('dam', 'Dam'),
          if (dam != null && !damKnown) ...[field('damSire', "Dam's sire (optional)", indent: true), field('damDam', "Dam's dam (optional)", indent: true)],
          const SizedBox(height: 20),
          if (!ready)
            const Text('Enter the sire or the dam to see the result.', style: TextStyle(color: NaniniColors.muted))
          else ...[
            Text('$label with ${bookName(widget.book)}\'s ${sex == 'F' ? 'bulls' : 'cows'}', style: Theme.of(context).textTheme.titleMedium),
            if (own > 0.05) Text('$label\'s own inbreeding: ${_pct(own)}', style: TextStyle(color: _tone(own))),
            const SizedBox(height: 8),
            if (results.isEmpty) Text('No ${sex == 'F' ? 'bulls' : 'cows'} in this book.'),
            for (final (m, f, shared) in results)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w700))),
                      Text(_pct(f), style: TextStyle(fontWeight: FontWeight.w700, color: _tone(f))),
                      const SizedBox(width: 10),
                      SizedBox(width: 82, child: Text(_word(f), style: TextStyle(color: _tone(f)))),
                    ]),
                    if (shared.isNotEmpty)
                      Text('Shared: ${shared.join(', ')}', style: const TextStyle(color: NaniniColors.muted, fontSize: 12)),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
                "The calf's inbreeding (Wright's F). 0%: outcross. Below 6.25%: mild. 6.25–12.5%: close line-breeding. "
                'Above 12.5%: avoid. Unknown ancestors count as unrelated, so the true figure can only be higher.',
                style: TextStyle(color: NaniniColors.muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  static String _pct(double v) => v < 0.05 ? '0%' : '${v.toStringAsFixed(1)}%';
  static Color _tone(double v) => v < 6.25 ? NaniniColors.green : (v <= 12.5 ? NaniniColors.amber : NaniniColors.red);
  static String _word(double v) => v < 0.05 ? 'Outcross' : (v < 6.25 ? 'Mild' : (v <= 12.5 ? 'Close' : 'Avoid'));
}
