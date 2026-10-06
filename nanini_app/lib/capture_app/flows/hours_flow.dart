import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/capture/capture_models.dart';
import '../../features/employees/employees_models.dart';
import '../../theme/nanini_theme.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../ref_data.dart';
import 'work_groups_flow.dart';
import '../../core/run_once.dart';

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

  /// Workers who already had hours that day, whose hours are to be changed
  /// to these (the office replaces theirs for that day).
  final replace = <String>{};
  RefPerson? current;
  int i = 0;

  /// The farm first, then group or person by person. A group picks its
  /// work (the group -- only on a farm that has groups; otherwise everyone at
  /// the farm), the day, then one screen: the hours at the top, everyone
  /// ticked below.
  List<_S> get steps => switch (mode) {
        _Mode.group => [_S.farm, _S.mode, if (_farmHasGroups) _S.group, _S.day, _S.absent, _S.check],
        _Mode.person => const [_S.farm, _S.mode, _S.day, _S.person, _S.amount, _S.check],
        null => const [_S.farm, _S.mode],
      };

  /// Doornbult and Haaskraal have no work groups: Group clocks everyone at
  /// the farm. Other farms choose a group (or make one with WORK GROUPS).
  bool get _farmHasGroups => farmUsesWorkGroups(farm?.name);

  /// What's being clocked: the group, or the whole farm (no groups there).
  String get _groupLabel => group?.name ?? 'Everyone at ${farm?.name ?? 'the farm'}';

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
    return ref.people
        .where((p) => (group == null ? p.farmId == farm?.id : store.groupOf(p) == group!.id) || extra.contains(p.id))
        .toList()
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
              setState(() {
                mode = _Mode.group;
                if (!_farmHasGroups) group = null;
              });
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
                ]),
        );
      case _S.group:
        final store = context.read<CaptureStore>();
        final groups = store.groupsFor(farm?.id);
        return page(
          'What work did you do?',
          ListView(children: [
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
                  // No groups made yet: clock everyone at the farm.
                  if (groups.isEmpty)
                    BigChoice(
                      icon: Icons.landscape,
                      label: 'Everyone at ${farm?.name ?? 'the farm'}',
                      onTap: () {
                        setState(() => group = null);
                        next();
                      },
                    ),
                  const SizedBox(height: 16),
                  // Put this farm's workers in the groups used to clock a whole group.
                  SizedBox(
                    height: 64,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkGroupsFlow(farm: farm))),
                      icon: const Icon(Icons.groups, size: 30),
                      label: const Text('WORK GROUPS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
        );
      case _S.day:
        return page('Which day?', DayChoice(selected: day, onPick: (d) {
          setState(() => day = d);
          next();
        }));
      case _S.person:
        Future<void> pick(RefPerson p) async {
          // Already submitted for this day: change it, or pick someone else.
          final had = context.read<CaptureStore>().clockedHours(p.id, dayStr(day ?? DateTime.now()));
          if (had != null && !replace.contains(p.id)) {
            // One farm a day: clocked at another farm, so not here too.
            if (_otherFarm(p) != null) {
              await _clockedElsewhere([(p, had)]);
              return;
            }
            final change = await _askChange([(p, had)]);
            if (change != true || !mounted) return;
            replace.add(p.id);
          }
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
                onTap: () => runOnce('hours_flow.1', () => pick(p)),
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
        // One person: TAKE OFF (−) makes it negative, to take hours off
        // (typed twice, or too many) -- like a tuck shop return.
        final person = mode != _Mode.group;
        return page(
          'How many hours did $who work?',
          NumberPad(value: amount, unit: 'h', allowNegative: person, onChanged: (v) => setState(() => amount = v)),
          hint: person ? 'Too many hours sent before? Press TAKE OFF (−) and type how many to take off' : null,
          onNext: () {
            final v = padValue(amount) ?? 0;
            if (v == 0) return _need('Type the hours');
            if (v < 0 && !person) return _need('Type the hours');
            if (v > 24 || v < -24) return _need('More than 24 hours? Check the number');
            if (v < 0 && current != null) {
              // Taking off: from what's there for that day, never below 0.
              final had = context.read<CaptureStore>().clockedHours(current!.id, dayStr(day ?? DateTime.now()));
              if (had == null || had <= 0) return _need('No hours for ${current!.name} on that day to take off');
              if (had + v < -0.001) return _need('Only ${fmtNum(had)} h on that day -- you can take off at most that');
              replace.remove(current!.id);
            }
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
          'Who worked?',
          ListView(children: [
                  // The hours at the top, for everyone ticked below.
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => runOnce('hours_flow.2', () async {
                        final v = await Navigator.of(context).push<double>(MaterialPageRoute(
                          builder: (_) => _OtherHoursPage(
                              name: _groupLabel, question: 'How many hours did ${_groupLabel == group?.name ? 'the group' : 'they'} work?', allowNegative: true),
                        ));
                        if (v != null && mounted) setState(() => amount = fmtNum(v).replaceAll(',', '.'));
                      }),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          const Icon(Icons.schedule, size: 34, color: NaniniColors.rust),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              h > 0 ? '${fmtNum(h)} hours each' : h < 0 ? 'TAKE OFF ${fmtNum(-h)} hours each' : 'TAP TO ENTER THE HOURS',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: h > 0 ? NaniniColors.ink : NaniniColors.red),
                            ),
                          ),
                          const Icon(Icons.edit, color: NaniniColors.rust),
                        ]),
                      ),
                    ),
                  ),
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
                        sub: isAbsent
                            ? 'ABSENT'
                            : (moved != null
                                ? 'AT ${moved.name.toUpperCase()}'
                                : (other == null && h == 0
                                    ? 'the hours above'
                                    : (other ?? h) < 0
                                        ? 'take off ${fmtNum(-(other ?? h))} hours'
                                        : '${fmtNum(other ?? h)} hours')),
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
                      onPressed: () => runOnce('hours_flow.3', () => _addSomeoneElse(ref)),
                      icon: const Icon(Icons.person_add, size: 30),
                      label: const Text('ADD SOMEONE ELSE', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
          hint: 'Everyone is ticked. Tap a name if they were absent, worked other hours or on another farm.',
          onNext: () {
            if (h == 0) return _need('Enter the hours at the top');
            if (h > 24 || h < -24) return _need('More than 24 hours? Check the number');
            if (!members.any((m) => !_out(m.id))) return _need('Nobody is at work');
            // Taking off: never more than someone has on that day.
            final short = _shortOfHours(members.where((m) => !_out(m.id)), h);
            if (short.isNotEmpty) return _need('Not that many hours on that day to take off for: ${short.join(', ')}');
            next();
          },
        );
      case _S.check:
        if (mode == _Mode.group) {
          final present = _members(ref).where((m) => !_out(m.id)).toList();
          final h = padValue(amount) ?? 0;
          return page(
            'Is this right?',
            ListView(children: [
              CheckLine(icon: Icons.groups, text: '$_groupLabel · ${_dayLabel(day)}'),
              for (final m in present)
                CheckLine(
                  icon: otherHours.containsKey(m.id) ? Icons.schedule : Icons.person,
                  text: (otherHours[m.id] ?? h) < 0
                      ? '${m.name}: take off ${fmtNum(-(otherHours[m.id] ?? h))} h'
                      : '${m.name}: ${fmtNum(otherHours[m.id] ?? h)} h',
                  color: (otherHours[m.id] ?? h) < 0 ? NaniniColors.red : (otherHours.containsKey(m.id) ? NaniniColors.amber : null),
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
            onNext: () async {
              // Group: anyone who already has hours that day -- change theirs,
              // or leave them out of this group's hours.
              if (mode == _Mode.group) {
                final date = dayStr(day!);
                final store = context.read<CaptureStore>();
                final had = [
                  // Only those getting hours (taking off is meant for them).
                  for (final m in _members(ref).where((m) => !_out(m.id) && !replace.contains(m.id) && (otherHours[m.id] ?? padValue(amount) ?? 0) > 0))
                    if (store.clockedHours(m.id, date) case final h?) (m, h),
                ];
                // One farm a day: those clocked at another farm are left out.
                final elsewhere = had.where((x) => _otherFarm(x.$1) != null).toList();
                if (elsewhere.isNotEmpty) {
                  if (await _clockedElsewhere(elsewhere) != true || !mounted) return;
                  setState(() => absent.addAll(elsewhere.map((x) => x.$1.id)));
                  if (_members(ref).every((m) => _out(m.id))) return _need('Nobody left to clock -- press BACK');
                  had.removeWhere((x) => elsewhere.contains(x));
                }
                if (had.isNotEmpty) {
                  final change = await _askChange(had);
                  if (change == null || !mounted) return;
                  setState(() {
                    for (final (m, _) in had) {
                      change ? replace.add(m.id) : absent.add(m.id);
                    }
                  });
                  if (!change && _members(ref).every((m) => _out(m.id))) return _need('Nobody left to clock -- press BACK');
                }
                final short = _shortOfHours(_members(ref).where((m) => !_out(m.id)), padValue(amount) ?? 0);
                if (short.isNotEmpty) return _need('Not that many hours on that day to take off for: ${short.join(', ')}');
              }
              await _save(ref);
            },
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
                  subtitle: Text(l.$2 < 0 ? 'Take off ${fmtNum(-l.$2)} hours' : '${fmtNum(l.$2)} hours',
                      style: TextStyle(fontSize: 20, color: l.$2 < 0 ? NaniniColors.red : null, fontWeight: l.$2 < 0 ? FontWeight.w700 : null)),
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
        question: 'Who else worked with ${group?.name ?? 'them'}?',
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
    final v = await Navigator.of(context).push<double>(MaterialPageRoute(builder: (_) => _OtherHoursPage(name: m.name, allowNegative: true)));
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

  /// Names of [people] who'd end up below 0 hours on the day if [h] (or
  /// their own other hours) is taken off: "Anna Mokoena (has 4 h)".
  List<String> _shortOfHours(Iterable<RefPerson> people, double h) {
    final store = context.read<CaptureStore>();
    final date = dayStr(day ?? DateTime.now());
    return [
      for (final m in people)
        if ((otherHours[m.id] ?? h) case final v when v < 0)
          if ((store.clockedHours(m.id, date) ?? 0) + v < -0.001) '${m.name} (has ${fmtNum(store.clockedHours(m.id, date) ?? 0)} h)',
    ];
  }

  /// " (clocked by Limpopodraai)": which farm sent [p]'s hours that day, if known.
  String _byFarm(RefPerson p) {
    final by = context.read<CaptureStore>().clockedBy(p.id, dayStr(day ?? DateTime.now()));
    if (by == null) return '';
    return ' (clocked by ${by.split(', ').map(_farmShort).toSet().join(', ')})';
  }

  /// The other farm(s) that already clocked [p] that day ("Limpopodraai"),
  /// or null: not clocked, clocked here, or the farm isn't known.
  String? _otherFarm(RefPerson p) {
    final by = context.read<CaptureStore>().clockedBy(p.id, dayStr(day ?? DateTime.now()));
    if (by == null || farm == null) return null;
    final here = _farmShort(farm!.name).toLowerCase();
    final others = by.split(', ').map(_farmShort).where((f) => f.toLowerCase() != here).toSet();
    return others.isEmpty ? null : others.join(', ');
  }

  /// A worker is clocked at one farm a day: [had] were already clocked at
  /// another farm. Group: true = leave them out, null = back.
  Future<bool?> _clockedElsewhere(List<(RefPerson, double)> had) {
    final when = dayLabel(day ?? DateTime.now());
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clocked at another farm', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Text(
            [
              'A worker can only be clocked at one farm a day. Already clocked for $when:',
              for (final (p, h) in had) '• ${p.name}: ${fmtNum(h)} h (clocked by ${_otherFarm(p)})',
              '',
              if (mode == _Mode.group) 'They are left out of these hours.',
              if (mode != _Mode.group) 'Pick someone else.',
            ].join('\n'),
            style: const TextStyle(fontSize: 19),
          ),
        ),
        actions: [
          if (mode == _Mode.group) ...[
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('BACK', style: TextStyle(fontSize: 18))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('LEAVE THEM OUT', style: TextStyle(fontSize: 18))),
          ] else
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(fontSize: 18))),
        ],
      ),
    );
  }

  /// "Already submitted" for [had] (worker, hours already there that day):
  /// true = change to the new hours, false = leave theirs, null = back.
  Future<bool?> _askChange(List<(RefPerson, double)> had) {
    final when = dayLabel(day ?? DateTime.now());
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Already submitted', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Text(
            [
              'Hours were already sent for $when:',
              for (final (p, h) in had) '• ${p.name}: ${fmtNum(h)} h${_byFarm(p)}',
              '',
              had.length == 1 ? 'Do you want to change it to the new hours?' : 'Do you want to change theirs to the new hours?',
            ].join('\n'),
            style: const TextStyle(fontSize: 19),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('BACK', style: TextStyle(fontSize: 18))),
          if (mode == _Mode.group)
            OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('LEAVE THEIRS', style: TextStyle(fontSize: 18))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CHANGE', style: TextStyle(fontSize: 18))),
        ],
      ),
    );
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
          'group_id': group?.id,
          'group_name': _groupLabel,
          'entries': [for (final m in present) {'employee_id': m.id, 'employee_name': m.name, 'hours': otherHours[m.id] ?? h}],
          // Already had hours that day: the office replaces them with these.
          if (present.any((m) => replace.contains(m.id) && (otherHours[m.id] ?? h) > 0))
            'replace': [for (final m in present) if (replace.contains(m.id) && (otherHours[m.id] ?? h) > 0) m.id],
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
        '$_groupLabel: ${fmtNum(h)} h × ${present.length}',
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
          if (lines.any((l) => replace.contains(l.$1.id))) 'replace': [for (final l in lines) if (replace.contains(l.$1.id)) l.$1.id],
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
  const _OtherHoursPage({required this.name, this.question, this.allowNegative = false});
  final String name;
  final String? question;

  /// TAKE OFF (−): a negative number takes hours off (a correction).
  final bool allowNegative;
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
        question: widget.question ?? 'How many hours did ${widget.name} work?',
        onBack: () => Navigator.pop(context),
        nextLabel: 'OK',
        nextIcon: Icons.check,
        onNext: () {
          final v = padValue(value) ?? 0;
          if (v == 0 || (v < 0 && !widget.allowNegative)) return showNeed(context, 'Type the hours (or go back and choose ABSENT)');
          if (v > 24 || v < -24) return showNeed(context, 'More than 24 hours? Check the number');
          Navigator.pop(context, v);
        },
        child: NumberPad(value: value, unit: 'h', allowNegative: widget.allowNegative, onChanged: (v) => setState(() => value = v)),
      );
}

/// "Farm Limpopodraai - Stockpoort" -> "Limpopodraai", as in the hub.
String _farmShort(String n) {
  final name = n.trim().replaceFirst(RegExp(r'^Farm\s+'), '');
  final dash = name.indexOf(' - ');
  return dash > 0 ? name.substring(0, dash).trim() : name;
}
