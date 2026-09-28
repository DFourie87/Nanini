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

  /// People from another group or farm who worked with the group today.
  final extra = <String>{};

  /// Group members who worked a different number of hours than the group.
  final otherHours = <String, double>{};

  /// Person/kg mode: people done so far, and the one being typed now.
  final lines = <(RefPerson, double)>[];
  RefPerson? current;
  int i = 0;

  /// The farm first, then group or person by person; a group then picks
  /// its work (the group), the day and hours, and ticks off its people.
  List<_S> get steps => switch (mode) {
        _Mode.group => const [_S.farm, _S.mode, _S.group, _S.day, _S.amount, _S.absent, _S.check],
        _Mode.person || _Mode.kg => const [_S.farm, _S.mode, _S.day, _S.person, _S.amount, _S.check],
        null => const [_S.farm, _S.mode],
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

  /// The farm the work was done on today -- saved with the hours. Workers
  /// move between farms, so anyone can be put on any farm's hours; they're
  /// still paid at their own farm.
  List<RefItem> _farms(RefData ref) => ref.farms;

  List<RefPerson> _people(RefData ref) => ref.people;

  List<RefPerson> _members(RefData ref) => ref.people.where((p) => p.groupId == group?.id || extra.contains(p.id)).toList()
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
            BigChoice(emoji: '👥', label: 'HOURS FOR A GROUP', sub: 'A group doing the same work', selected: mode == _Mode.group, onTap: () {
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
          'Which farm did you work on?',
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
          'What work did you do?',
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
                          if (group?.id != g.id) {
                            absent.clear();
                            otherHours.clear();
                            extra.clear();
                          }
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
        final h = padValue(amount) ?? 0;
        return page(
          'Who worked ${fmtNum(h)} hours?',
          members.isEmpty
              ? const EmptyListNote()
              : ListView(children: [
                  for (final m in members)
                    () {
                      final isAbsent = absent.contains(m.id);
                      final other = otherHours[m.id];
                      return BigChoice(
                        icon: isAbsent ? Icons.cancel : (other != null ? Icons.schedule : Icons.check_circle),
                        color: isAbsent ? NaniniColors.red : (other != null ? NaniniColors.amber : NaniniColors.green),
                        label: m.name,
                        sub: isAbsent ? 'ABSENT' : '${fmtNum(other ?? h)} hours',
                        onTap: () => isAbsent || other != null
                            // Back to the group's hours.
                            ? setState(() {
                                absent.remove(m.id);
                                otherHours.remove(m.id);
                              })
                            : _untick(m),
                      );
                    }(),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 64,
                    child: OutlinedButton.icon(
                      onPressed: () => _addSomeoneElse(ref),
                      icon: const Icon(Icons.person_add, size: 30),
                      label: const Text('ADD SOMEONE ELSE', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
          hint: 'Everyone is ticked. Tap a name if they were absent or worked other hours.',
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
              for (final m in present)
                CheckLine(
                  icon: otherHours.containsKey(m.id) ? Icons.schedule : Icons.person,
                  color: otherHours.containsKey(m.id) ? NaniniColors.amber : null,
                  text: '${m.name}: ${fmtNum(otherHours[m.id] ?? h)} h',
                ),
              if (absent.isNotEmpty) CheckLine(icon: Icons.cancel, color: NaniniColors.red, text: '${absent.length} absent'),
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

  /// Someone from another group or farm worked with this group today.
  Future<void> _addSomeoneElse(RefData ref) async {
    final members = _members(ref).map((m) => m.id).toSet();
    final p = await Navigator.of(context).push<RefPerson>(MaterialPageRoute(
      builder: (ctx) => StepPage(
        task: _task,
        step: 1,
        steps: 1,
        question: 'Who else worked with ${group?.name}?',
        onBack: () => Navigator.pop(ctx),
        child: PersonPicker(people: ref.people.where((p) => !members.contains(p.id)).toList(), onPick: (p) => Navigator.pop(ctx, p)),
      ),
    ));
    if (p != null && mounted) setState(() => extra.add(p.id));
  }

  /// A group member didn't work the group's hours: absent, or other hours.
  Future<void> _untick(RefPerson m) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(m.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              BigChoice(icon: Icons.cancel, color: NaniniColors.red, label: 'ABSENT', onTap: () => Navigator.pop(ctx, 'absent')),
              BigChoice(icon: Icons.schedule, color: NaniniColors.amber, label: 'OTHER HOURS', onTap: () => Navigator.pop(ctx, 'other')),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'absent') return setState(() => absent.add(m.id));
    final v = await Navigator.of(context).push<double>(MaterialPageRoute(builder: (_) => _OtherHoursPage(name: m.name)));
    if (v != null && mounted) setState(() => otherHours[m.id] = v);
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
          'farm_id': farm!.id,
          'farm_name': farm!.name,
          'group_id': group!.id,
          'group_name': group!.name,
          'entries': [for (final m in present) {'employee_id': m.id, 'employee_name': m.name, 'hours': otherHours[m.id] ?? h}],
        },
        '${group!.name}: ${fmtNum(h)} h × ${present.length}',
      );
    } else if (mode == _Mode.kg) {
      await store.add(
        CaptureModule.kg,
        {
          'date': date,
          'farm_id': farm!.id,
          'farm_name': farm!.name,
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
          'farm_id': farm!.id,
          'farm_name': farm!.name,
          'entries': [for (final l in lines) {'employee_id': l.$1.id, 'employee_name': l.$1.name, 'hours': l.$2}],
        },
        'Hours: ${lines.length} people',
      );
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SavedScreen(task: 'hours', another: (_) => const HoursFlow())));
  }
}

/// How many hours one group member worked, when not the group's hours.
class _OtherHoursPage extends StatefulWidget {
  const _OtherHoursPage({required this.name});
  final String name;
  @override
  State<_OtherHoursPage> createState() => _OtherHoursPageState();
}

class _OtherHoursPageState extends State<_OtherHoursPage> {
  String value = '';

  @override
  Widget build(BuildContext context) => StepPage(
        task: 'Hours',
        step: 1,
        steps: 1,
        question: 'How many hours did ${widget.name} work?',
        onBack: () => Navigator.pop(context),
        nextLabel: 'OK',
        nextIcon: Icons.check,
        onNext: () {
          final v = padValue(value) ?? 0;
          if (v <= 0) return showNeed(context, 'Type the hours (or go back and choose ABSENT)');
          if (v > 24) return showNeed(context, 'More than 24 hours? Check the number');
          Navigator.pop(context, v);
        },
        child: NumberPad(value: value, unit: 'h', onChanged: (v) => setState(() => value = v)),
      );
}
