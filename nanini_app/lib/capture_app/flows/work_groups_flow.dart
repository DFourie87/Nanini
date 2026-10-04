import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../features/capture/capture_models.dart';
import '../../features/employees/employees_models.dart';
import '../../theme/nanini_theme.dart';
import '../capture_store.dart';
import '../capture_widgets.dart';
import '../ref_data.dart';
import '../../core/run_once.dart';

/// Hours > WORK GROUPS: for one farm, put workers in the work groups used to
/// clock hours for a whole group at once. Changes go to the hub (Employees)
/// to approve, and this phone uses them straight away.
class WorkGroupsFlow extends StatefulWidget {
  const WorkGroupsFlow({super.key, this.farm});

  /// Straight to this farm's groups (from Hours, after the farm is chosen).
  final RefItem? farm;
  @override
  State<WorkGroupsFlow> createState() => _WorkGroupsFlowState();
}

class _WorkGroupsFlowState extends State<WorkGroupsFlow> {
  late RefItem? farm = widget.farm;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CaptureStore>();
    final ref = store.ref;
    if (farm == null) {
      // Doornbult and Haaskraal clock everyone at the farm: no groups there.
      final farms = ref.farms.where((f) => farmUsesWorkGroups(f.name)).toList();
      return StepPage(
        task: 'Work groups',
        step: 1,
        steps: 2,
        question: 'Which farm?',
        onBack: () => Navigator.pop(context),
        child: farms.isEmpty
            ? const EmptyListNote()
            : ListView(children: [
                for (final f in farms) BigChoice(icon: Icons.landscape, label: f.name, onTap: () => setState(() => farm = f)),
              ]),
      );
    }
    final groups = store.groupsFor(farm!.id);
    int count(RefItem g) => ref.people.where((p) => store.groupOf(p) == g.id).length;
    final noGroup = ref.people.where((p) => p.farmId == farm!.id && store.groupOf(p) == null).length;
    return StepPage(
      task: 'Work groups',
      step: 2,
      steps: 2,
      question: 'Work groups at ${farm!.name}',
      hint: 'Tap a group to choose who is in it',
      onBack: () => widget.farm != null ? Navigator.pop(context) : setState(() => farm = null),
      nextLabel: 'DONE',
      nextIcon: Icons.check,
      onNext: () => Navigator.pop(context),
      child: ListView(children: [
        for (final g in groups)
          BigChoice(
            icon: Icons.groups,
            label: g.name,
            sub: '${count(g)} people${g.id.startsWith('new-') ? ' · new' : ''}',
            onTap: () => runOnce('work_groups_flow.1', () => _members(g)),
          ),
        if (noGroup > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('$noGroup ${noGroup == 1 ? 'person is' : 'people are'} in no group yet',
                style: const TextStyle(fontSize: 16, color: NaniniColors.muted)),
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: OutlinedButton.icon(
            onPressed: () => runOnce('work_groups_flow.2', _newGroup),
            icon: const Icon(Icons.group_add, size: 30),
            label: const Text('NEW GROUP', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Future<void> _newGroup() async {
    final name = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _GroupNamePage()));
    if (name == null || !mounted) return;
    await _members(RefItem('new-${const Uuid().v4()}', name, farmId: farm!.id));
  }

  Future<void> _members(RefItem group) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _GroupMembersPage(farm: farm!, group: group)));
}

/// The name of a new work group (the work they do, e.g. "Picking").
class _GroupNamePage extends StatefulWidget {
  const _GroupNamePage();
  @override
  State<_GroupNamePage> createState() => _GroupNamePageState();
}

class _GroupNamePageState extends State<_GroupNamePage> {
  final ctrl = TextEditingController();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StepPage(
        task: 'Work groups',
        step: 1,
        steps: 1,
        question: 'Name of the new group',
        hint: 'The work they do, e.g. Picking or Packing',
        onBack: () => Navigator.pop(context),
        nextLabel: 'OK',
        nextIcon: Icons.check,
        onNext: () => ctrl.text.trim().isEmpty ? showNeed(context, 'Type the name') : Navigator.pop(context, ctrl.text.trim()),
        child: ListView(children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(fontSize: 22),
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Group name'),
          ),
        ]),
      );
}

/// Tick who is in [group]: the farm's people, others under FROM OTHER FARM.
class _GroupMembersPage extends StatefulWidget {
  const _GroupMembersPage({required this.farm, required this.group});
  final RefItem farm;
  final RefItem group;
  @override
  State<_GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends State<_GroupMembersPage> {
  late final Set<String> ticked;
  late final Set<String> before;
  bool others = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<CaptureStore>();
    before = {for (final p in store.ref.people) if (store.groupOf(p) == widget.group.id) p.id};
    ticked = {...before};
    others = store.ref.people.any((p) => before.contains(p.id) && p.farmId != widget.farm.id);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CaptureStore>();
    final ref = store.ref;
    final allGroups = {for (final f in ref.farms) for (final g in store.groupsFor(f.id)) g.id: g.name};
    final people = ref.people.where((p) => others || p.farmId == widget.farm.id).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final moreCount = ref.people.where((p) => p.farmId != widget.farm.id).length;
    return StepPage(
      task: 'Work groups',
      step: 1,
      steps: 1,
      question: 'Who is in ${widget.group.name}?',
      hint: 'Tap to tick or untick. ${ticked.length} ticked.',
      onBack: () => Navigator.pop(context),
      nextLabel: 'SAVE',
      nextIcon: Icons.check,
      onNext: () => _save(store),
      child: ListView(children: [
        for (final p in people)
          () {
            final isIn = ticked.contains(p.id);
            final current = store.groupOf(p);
            final elsewhere = current != null && current != widget.group.id ? allGroups[current] : null;
            return BigChoice(
              icon: isIn ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isIn ? NaniniColors.green : NaniniColors.muted,
              label: p.name,
              sub: isIn ? null : (elsewhere != null ? 'now in $elsewhere' : null),
              onTap: () => setState(() => isIn ? ticked.remove(p.id) : ticked.add(p.id)),
            );
          }(),
        if (!others && moreCount > 0) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => others = true),
              icon: const Icon(Icons.group_add, size: 30),
              label: const Text('FROM OTHER FARM', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _save(CaptureStore store) async {
    final added = ticked.difference(before);
    final removed = before.difference(ticked);
    final isNew = widget.group.id.startsWith('new-');
    if (added.isEmpty && removed.isEmpty && !isNew) {
      Navigator.pop(context);
      return;
    }
    final byId = {for (final p in store.ref.people) p.id: p};
    await store.add(
      CaptureModule.workGroups,
      {
        'farm_id': widget.farm.id,
        'farm_name': widget.farm.name,
        'group_id': isNew ? null : widget.group.id,
        'group_name': widget.group.name,
        'members': [for (final id in ticked) {'employee_id': id, 'employee_name': byId[id]?.name ?? ''}],
        'removed': [for (final id in removed) {'employee_id': id, 'employee_name': byId[id]?.name ?? ''}],
      },
      '${widget.group.name}: ${ticked.length} people',
    );
    await store.rememberGroups(
      newGroup: isNew ? widget.group : null,
      set: {
        for (final id in added) ?byId[id]: widget.group.id,
        for (final id in removed) ?byId[id]: null,
      },
    );
    if (mounted) Navigator.pop(context);
  }
}
