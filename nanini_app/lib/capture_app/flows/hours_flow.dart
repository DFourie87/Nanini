import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/capture/capture_models.dart';
import '../../theme/nanini_theme.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../ref_data.dart';
import 'work_groups_flow.dart';

enum _Mode { group, person }

enum _S { mode, farm, group, day, amount, absent, person, check }

/// Hours worked on a day (a whole group, or person by person). Rates are
/// never typed on the phone -- the hub uses each person's rate when a
/// manager approves. A total since the last pay is corrected in Payslips.
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

  /// Group members who worked on another farm today: clocked there, not here.
  final movedTo = <String, RefItem>{};

  /// Not clocked with the group: absent, or at another farm.
  bool _out(String id) => absent.contains(id) || movedTo.containsKey(id);

  /// Person mode: people done so far, and the one being typed now.
  final lines = <(RefPerson, double)>[];
  RefPerson? current;
  int i = 0;

  /// The farm first, then group or person by person; a group then picks
  /// its work (the group), the day and hours, and ticks off its people.
  List<_S> get steps => switch (mode) {
        _Mode.group => const [_S.farm, _S.mode, _S.group, _S.day, _S.amount, _S.absent, _S.check],
        _Mode.person => const [_S.farm, _S.mode, _S.day, _S.person, _S.amount, _S.check],
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

  static const _task = 'Hours';

  /// The farm the work was done on today -- saved with the hours. Workers
  /// move between farms, so anyone can be put on any farm's hours; they're
  /// still paid at their own farm.
  List<RefItem> _farms(RefData ref) => ref.farms;

  List<RefPerson> _people(RefData ref) => ref.people;

  List<RefPerson> _members(RefData ref) {
    final store = context.read<CaptureStore>();
    return ref.people.where((p) => store.groupOf(p) == group?.id || extra.contains(p.id)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<CaptureStore>().ref;
    final s = steps[i];
    StepPage page(String q, Widget child, {VoidCallback? onNext, String? hint, String nextLabel = 'NEXT', IconData nextIcon = Icons.arrow_forward}) =>
        StepPage(task: _task, step: i + 1, steps: steps.length, question: q, hint: hint, onBack: back, onNext: onNext, nextLabel: nextLabel, nextIcon: nextIcon, child: child);

    switch (s) {
      case _S.mode:
        return page(
          'Hours for:',
          ListView(children: [
            BigChoice(emoji: '👥', label: 'Group', selected: mode == _Mode.group, onTap: () {
              setState(() => mode = _Mode.group);
              next();
            }),
            BigChoice(emoji: '👤', label: 'Person', selected: mode == _Mode.person, onTap: () {
              setState(() => mode = _Mode.person);
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
                  const SizedBox(height: 16),
                  // Put workers in the groups used to clock a whole group.
                  SizedBox(
                    height: 64,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WorkGroupsFlow())),
                      icon: const Icon(Icons.groups, size: 30),
                      label: const Text('WORK GROUPS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
        );
      case _S.group:
        final store = context.read<CaptureStore>();
        final groups = store.groupsFor(farm?.id);
        return page(
          'What work did you do?',
          groups.isEmpty
              ? const EmptyListNote()
              : ListView(children: [
                  for (final g in groups)
                    BigChoice(
                      icon: Icons.groups,
                      label: g.name,
                      sub: '${ref.people.where((p) => store.groupOf(p) == g.id).length} people',
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
        void pick(RefPerson p) {
          setState(() {
            current = p;
            amount = '';
          });
          next();
        }
        // Sent here from another farm's group today: tap to clock them.
        final sent = context
            .read<CaptureStore>()
            .sentToFarm(farm?.id, dayStr(day ?? DateTime.now()))
            .where((s) => !lines.any((l) => l.$1.id == s.employeeId))
            .map((s) => (s, ref.people.where((p) => p.id == s.employeeId).firstOrNull))
            .where((x) => x.$2 != null)
            .toList();
        return page(
          'Who worked?',
          Column(children: [
            for (final (s, p) in sent)
              BigChoice(
                icon: Icons.swap_horiz,
                color: NaniniColors.amber,
                label: p!.name,
                sub: 'Sent here from ${s.fromFarm} -- clock here',
                onTap: () => pick(p),
              ),
            Expanded(
              child: PersonPicker(
                farmId: farm?.id,
                people: _people(ref).where((p) => !lines.any((l) => l.$1.id == p.id)).toList(),
                onPick: pick,
              ),
            ),
          ]),
        );
      case _S.amount:
        final who = mode == _Mode.group ? 'the group' : current?.name;
        return page(
          'How many hours did $who work?',
          NumberPad(value: amount, unit: 'h', onChanged: (v) => setState(() => amount = v)),
          onNext: () {
            final v = padValue(amount) ?? 0;
            if (v <= 0) return _need('Type the hours');
            if (v > 24) return _need('More than 24 hours? Check the number');
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
          ListView(children: [
                  // Nobody put in this group yet (e.g. new workers): add the
                  // farm's people, or anyone, here.
                  if (members.isEmpty) ...[
                    Text('Nobody is in ${group?.name ?? 'this group'} yet. Add the people who worked:',
                        style: const TextStyle(fontSize: 18, color: NaniniColors.muted)),
                    const SizedBox(height: 8),
                    if (ref.people.any((p) => p.farmId == farm?.id))
                      SizedBox(
                        height: 64,
                        child: FilledButton.icon(
                          onPressed: () => setState(() => extra.addAll(ref.people.where((p) => p.farmId == farm?.id).map((p) => p.id))),
                          icon: const Icon(Icons.groups, size: 30),
                          label: Text('EVERYONE FROM ${(farm?.name ?? '').toUpperCase()}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                  ..._sentHere(ref, members),
                  for (final m in members)
                    () {
                      final isAbsent = absent.contains(m.id);
                      final other = otherHours[m.id];
                      final moved = movedTo[m.id];
                      return BigChoice(
                        icon: isAbsent ? Icons.cancel : (moved != null ? Icons.swap_horiz : (other != null ? Icons.schedule : Icons.check_circle)),
                        color: isAbsent ? NaniniColors.red : (moved != null || other != null ? NaniniColors.amber : NaniniColors.green),
                        label: m.name,
                        sub: isAbsent ? 'ABSENT' : (moved != null ? 'AT ${moved.name.toUpperCase()}' : '${fmtNum(other ?? h)} hours'),
                        onTap: () => isAbsent || other != null || moved != null
                            // Back to the group's hours.
                            ? setState(() {
                                absent.remove(m.id);
                                otherHours.remove(m.id);
                                movedTo.remove(m.id);
                              })
                            : _untick(m, ref),
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
          hint: 'Everyone is ticked. Tap a name if they were absent, worked other hours or on another farm.',
          onNext: () => members.any((m) => !_out(m.id)) ? next() : _need('Nobody is at work'),
        );
      case _S.check:
        if (mode == _Mode.group) {
          final present = _members(ref).where((m) => !_out(m.id)).toList();
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
              for (final e in movedTo.entries)
                CheckLine(
                  icon: Icons.swap_horiz,
                  color: NaniniColors.amber,
                  text: '${ref.people.where((p) => p.id == e.key).firstOrNull?.name ?? ''}: at ${e.value.name} -- clock there',
                ),
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
                  subtitle: Text('${fmtNum(l.$2)} hours', style: const TextStyle(fontSize: 20)),
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
        child: PersonPicker(
          farmId: farm?.id,
          people: ref.people.where((p) => !members.contains(p.id)).toList(),
          onPick: (p) => Navigator.pop(ctx, p),
        ),
      ),
    ));
    if (p != null && mounted) setState(() => extra.add(p.id));
  }

  /// A group member didn't work the group's hours: absent, or other hours.
  /// People another farm's group sent to work here on this day: clock them.
  List<Widget> _sentHere(RefData ref, List<RefPerson> members) {
    final store = context.read<CaptureStore>();
    final sent = store.sentToFarm(farm?.id, dayStr(day ?? DateTime.now()))
        .where((s) => !members.any((m) => m.id == s.employeeId))
        .toList();
    if (sent.isEmpty) return const [];
    return [
      Card(
        color: NaniniColors.paper,
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Sent to work here -- clock them here:', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: NaniniColors.rust)),
              for (final s in sent)
                Row(children: [
                  Expanded(child: Text('${s.employeeName} (from ${s.fromFarm})', style: const TextStyle(fontSize: 17))),
                  if (ref.people.any((p) => p.id == s.employeeId))
                    TextButton(onPressed: () => setState(() => extra.add(s.employeeId)), child: const Text('ADD', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                ]),
            ],
          ),
        ),
      ),
    ];
  }

  /// Which other farm [m] worked on today.
  Future<RefItem?> _pickOtherFarm(RefPerson m, RefData ref) => Navigator.of(context).push<RefItem>(MaterialPageRoute(
        builder: (ctx) => StepPage(
          task: _task,
          step: 1,
          steps: 1,
          question: 'Which farm did ${m.name} work on?',
          onBack: () => Navigator.pop(ctx),
          child: ListView(children: [
            for (final f in ref.farms.where((f) => f.id != farm?.id))
              BigChoice(icon: Icons.landscape, label: f.name, onTap: () => Navigator.pop(ctx, f)),
          ]),
        ),
      ));

  Future<void> _untick(RefPerson m, RefData ref) async {
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
              BigChoice(icon: Icons.swap_horiz, color: NaniniColors.amber, label: 'WORKED ON OTHER FARM', onTap: () => Navigator.pop(ctx, 'farm')),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'absent') return setState(() => absent.add(m.id));
    if (choice == 'farm') {
      final f = await _pickOtherFarm(m, ref);
      if (f != null && mounted) setState(() => movedTo[m.id] = f);
      return;
    }
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
      final present = _members(ref).where((m) => !_out(m.id)).toList();
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
          // Worked on another farm today: that farm's phone is told to clock them.
          'moved': [
            for (final e in movedTo.entries)
              {
                'employee_id': e.key,
                'employee_name': ref.people.where((p) => p.id == e.key).firstOrNull?.name ?? '',
                'farm_id': e.value.id,
                'farm_name': e.value.name,
              },
          ],
        },
        '${group!.name}: ${fmtNum(h)} h × ${present.length}',
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
