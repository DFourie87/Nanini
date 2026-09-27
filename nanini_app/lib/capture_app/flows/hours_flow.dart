import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/capture/capture_models.dart';
import '../../theme/nanini_theme.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../ref_data.dart';

enum _Mode { group, person, kg }

enum _S { mode, farm, group, day, amount, absent, person, check }

/// Hours worked (a whole group, or person by person) and kg picked. Rates
/// are never typed on the phone -- the hub uses each person's rate (or asks
/// for the R/kg) when a manager approves.
class HoursFlow extends StatefulWidget {
  const HoursFlow({super.key});
  @override
  State<HoursFlow> createState() => _HoursFlowState();
}

class _HoursFlowState extends State<HoursFlow> {
  _Mode? mode;
  RefItem? farm;
  RefItem? group;
  DateTime? day;
  String amount = '';
  final absent = <String>{};

  /// Person/kg mode: people done so far, and the one being typed now.
  final lines = <(RefPerson, double)>[];
  RefPerson? current;
  int i = 0;

  List<_S> get steps => switch (mode) {
        _Mode.group => const [_S.mode, _S.farm, _S.group, _S.day, _S.amount, _S.absent, _S.check],
        _Mode.person || _Mode.kg => const [_S.mode, _S.farm, _S.day, _S.person, _S.amount, _S.check],
        null => const [_S.mode, _S.farm, _S.day, _S.amount, _S.check],
      };

  void go(_S s) => setState(() => i = steps.indexOf(s));
  void next() => setState(() => i = (i + 1).clamp(0, steps.length - 1));
  void back() {
    if (i == 0) return Navigator.of(context).pop();
    // Going back from the amount of a second/third person returns to the list.
    if (steps[i] == _S.person && lines.isNotEmpty) return go(_S.check);
    // From the person-by-person list, BACK goes to the day (the list is kept).
    if (steps[i] == _S.check && mode != _Mode.group) return go(_S.day);
    setState(() => i--);
  }

  void _need(String msg) => showNeed(context, msg);

  String get _task => mode == _Mode.kg ? 'Kg picked' : 'Hours';
  String get _unit => mode == _Mode.kg ? 'kg' : 'hours';

  List<RefItem> _farms(RefData ref) {
    final withPeople = ref.people.map((p) => p.farmId).toSet();
    final f = ref.farms.where((f) => withPeople.contains(f.id)).toList();
    return f.isEmpty ? ref.farms : f;
  }

  List<RefPerson> _people(RefData ref) {
    final onFarm = ref.people.where((p) => p.farmId == farm?.id).toList();
    return onFarm.isEmpty ? ref.people : onFarm;
  }

  List<RefPerson> _members(RefData ref) => ref.people.where((p) => p.groupId == group?.id).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<CaptureStore>().ref;
    final s = steps[i];
    StepPage page(String q, Widget child, {VoidCallback? onNext, String? hint, String nextLabel = 'NEXT', IconData nextIcon = Icons.arrow_forward}) =>
        StepPage(task: _task, step: i + 1, steps: steps.length, question: q, hint: hint, onBack: back, onNext: onNext, nextLabel: nextLabel, nextIcon: nextIcon, child: child);

    switch (s) {
      case _S.mode:
        return page(
          'What do you want to write down?',
          ListView(children: [
            BigChoice(emoji: '👥', label: 'HOURS FOR A GROUP', sub: 'Everyone in the group worked', selected: mode == _Mode.group, onTap: () {
              setState(() => mode = _Mode.group);
              next();
            }),
            BigChoice(emoji: '👤', label: 'HOURS PER PERSON', selected: mode == _Mode.person, onTap: () {
              setState(() => mode = _Mode.person);
              next();
            }),
            BigChoice(emoji: '⚖️', label: 'KG PICKED', sub: 'Kilograms each person picked', selected: mode == _Mode.kg, onTap: () {
              setState(() => mode = _Mode.kg);
              next();
            }),
          ]),
        );
      case _S.farm:
        final farms = _farms(ref);
        return page(
          'Which farm?',
          farms.isEmpty
              ? const EmptyListNote()
              : ListView(children: [
                  for (final f in farms)
                    BigChoice(icon: Icons.landscape, label: f.name, selected: farm?.id == f.id, onTap: () {
                      setState(() {
                        if (farm?.id != f.id) group = null;
                        farm = f;
                      });
                      next();
                    }),
                ]),
        );
      case _S.group:
        final groups = ref.groups.where((g) => g.farmId == farm?.id).toList();
        return page(
          'Which group?',
          groups.isEmpty
              ? const EmptyListNote()
              : ListView(children: [
                  for (final g in groups)
                    BigChoice(
                      icon: Icons.groups,
                      label: g.name,
                      sub: '${ref.people.where((p) => p.groupId == g.id).length} people',
                      selected: group?.id == g.id,
                      onTap: () {
                        setState(() {
                          if (group?.id != g.id) absent.clear();
                          group = g;
                        });
                        next();
                      },
                    ),
                ]),
        );
      case _S.day:
        return page('Which day?', DayChoice(selected: day, onPick: (d) {
          setState(() => day = d);
          next();
        }));
      case _S.person:
        return page(
          mode == _Mode.kg ? 'Who picked?' : 'Who worked?',
          PersonPicker(
            people: _people(ref).where((p) => !lines.any((l) => l.$1.id == p.id)).toList(),
            onPick: (p) {
              setState(() {
                current = p;
                amount = '';
              });
              next();
            },
          ),
        );
      case _S.amount:
        final q = switch (mode) {
          _Mode.kg => 'How many kg did ${current?.name} pick?',
          _Mode.group => 'How many hours did the group work?',
          _ => 'How many hours did ${current?.name} work?',
        };
        return page(
          q,
          NumberPad(value: amount, unit: _unit == 'kg' ? 'kg' : 'h', onChanged: (v) => setState(() => amount = v)),
          onNext: () {
            final v = padValue(amount) ?? 0;
            if (v <= 0) return _need('Type the $_unit');
            if (mode != _Mode.kg && v > 24) return _need('More than 24 hours? Check the number');
            if (mode != _Mode.group && current != null) {
              setState(() {
                lines.add((current!, v));
                current = null;
              });
            }
            next();
          },
        );
      case _S.absent:
        final members = _members(ref);
        return page(
          'Who was NOT at work?',
          members.isEmpty
              ? const EmptyListNote()
              : ListView(children: [
                  for (final m in members)
                    BigChoice(
                      icon: absent.contains(m.id) ? Icons.cancel : Icons.check_circle,
                      color: absent.contains(m.id) ? NaniniColors.red : NaniniColors.green,
                      label: m.name,
                      sub: absent.contains(m.id) ? 'NOT at work' : 'At work',
                      onTap: () => setState(() => absent.contains(m.id) ? absent.remove(m.id) : absent.add(m.id)),
                    ),
                ]),
          hint: 'Tap a name to mark them absent. Tap again to undo.',
          onNext: () => members.any((m) => !absent.contains(m.id)) ? next() : _need('Nobody is at work'),
        );
      case _S.check:
        if (mode == _Mode.group) {
          final present = _members(ref).where((m) => !absent.contains(m.id)).toList();
          final h = padValue(amount) ?? 0;
          return page(
            'Is this right?',
            ListView(children: [
              CheckLine(icon: Icons.groups, text: '${group?.name} · ${_dayLabel(day)}'),
              CheckLine(icon: Icons.schedule, text: '${fmtNum(h)} hours each'),
              for (final m in present) CheckLine(icon: Icons.person, text: m.name),
              if (absent.isNotEmpty) CheckLine(icon: Icons.cancel, text: '${absent.length} not at work'),
            ]),
            hint: 'If something is wrong, press BACK',
            nextLabel: 'SAVE',
            nextIcon: Icons.check,
            onNext: () => _save(ref),
          );
        }
        return page(
          'Is this right?',
          ListView(children: [
            CheckLine(icon: Icons.today, text: _dayLabel(day)),
            for (final (idx, l) in lines.indexed)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person, size: 32, color: NaniniColors.rust),
                  title: Text(l.$1.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  subtitle: Text('${fmtNum(l.$2)} $_unit', style: const TextStyle(fontSize: 20)),
                  trailing: IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.delete_outline, color: NaniniColors.red),
                    onPressed: () => setState(() => lines.removeAt(idx)),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: OutlinedButton.icon(
                onPressed: () => go(_S.person),
                icon: const Icon(Icons.person_add, size: 30),
                label: const Text('ADD ANOTHER PERSON', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
          hint: 'Add everyone, then press SAVE',
          nextLabel: 'SAVE',
          nextIcon: Icons.check,
          onNext: () => lines.isEmpty ? _need('Add at least one person') : _save(ref),
        );
    }
  }

  String _dayLabel(DateTime? d) {
    if (d == null) return '';
    final today = DateTime.now();
    if (d.year == today.year && d.month == today.month && d.day == today.day) return 'Today';
    final y = today.subtract(const Duration(days: 1));
    if (d.year == y.year && d.month == y.month && d.day == y.day) return 'Yesterday';
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _save(RefData ref) async {
    final store = context.read<CaptureStore>();
    final date = dayStr(day!);
    if (mode == _Mode.group) {
      final h = padValue(amount) ?? 0;
      final present = _members(ref).where((m) => !absent.contains(m.id)).toList();
      await store.add(
        CaptureModule.hours,
        {
          'mode': 'group',
          'date': date,
          'group_id': group!.id,
          'group_name': group!.name,
          'entries': [for (final m in present) {'employee_id': m.id, 'employee_name': m.name, 'hours': h}],
        },
        '${group!.name}: ${fmtNum(h)} h × ${present.length}',
      );
    } else if (mode == _Mode.kg) {
      await store.add(
        CaptureModule.kg,
        {
          'date': date,
          'entries': [for (final l in lines) {'employee_id': l.$1.id, 'employee_name': l.$1.name, 'kg': l.$2}],
        },
        'Kg picked: ${lines.length} people',
      );
    } else {
      await store.add(
        CaptureModule.hours,
        {
          'mode': 'individual',
          'date': date,
          'entries': [for (final l in lines) {'employee_id': l.$1.id, 'employee_name': l.$1.name, 'hours': l.$2}],
        },
        'Hours: ${lines.length} people',
      );
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(task: 'hours', another: (_) => const HoursFlow())));
  }
}
