import 'package:flutter/material.dart';

import '../theme/nanini_theme.dart';
import 'ref_data.dart';

/// One question per screen: a big question, a progress bar, the answer area,
/// and big Back / Next buttons. Built for people who read slowly -- as few
/// words as possible, large text, large tap targets.
class StepPage extends StatelessWidget {
  const StepPage({
    super.key,
    required this.task,
    required this.step,
    required this.steps,
    required this.question,
    required this.child,
    this.onBack,
    this.onNext,
    this.nextLabel = 'NEXT',
    this.nextIcon = Icons.arrow_forward,
    this.hint,
  });

  final String task;
  final int step;
  final int steps;
  final String question;
  final String? hint;
  final Widget child;
  final VoidCallback? onBack;

  /// Null hides the Next button (e.g. when tapping a choice moves on by itself).
  final VoidCallback? onNext;
  final String nextLabel;
  final IconData nextIcon;

  @override
  Widget build(BuildContext context) {
    // The phone's own back button goes one step back, like BACK.
    return PopScope(
      canPop: onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack?.call();
      },
      child: _page(context),
    );
  }

  Widget _page(BuildContext context) {
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      appBar: AppBar(
        title: Text(task, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 26, fontWeight: FontWeight.w700)),
        leading: IconButton(iconSize: 32, icon: const Icon(Icons.close), tooltip: 'Home', onPressed: () => Navigator.of(context).pop()),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  for (var i = 1; i <= steps; i++)
                    Expanded(
                      child: Container(
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(color: i <= step ? NaniniColors.rust : NaniniColors.disabledBg, borderRadius: BorderRadius.circular(5)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(
                question,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: NaniniColors.ink),
              ),
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(hint!, style: const TextStyle(fontSize: 17, color: NaniniColors.muted)),
              ),
            Expanded(
              child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: child),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  // Equal halves, and labels shrink to fit rather than being
                  // cut off on narrow phones.
                  if (onBack != null)
                    Expanded(
                      child: SizedBox(
                        height: 64,
                        child: OutlinedButton(
                          onPressed: onBack,
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                          child: const _ButtonLabel(icon: Icons.arrow_back, text: 'BACK', fontSize: 20),
                        ),
                      ),
                    ),
                  if (onBack != null && onNext != null) const SizedBox(width: 12),
                  if (onNext != null)
                    Expanded(
                      child: SizedBox(
                        height: 64,
                        child: FilledButton(
                          onPressed: onNext,
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                          child: _ButtonLabel(icon: nextIcon, text: nextLabel, fontSize: 22),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon + word for the big BACK / NEXT buttons, scaled down (never cut off)
/// when the button is narrow.
class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel({required this.icon, required this.text, required this.fontSize});
  final IconData icon;
  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 8),
            Text(text, maxLines: 1, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

/// Big full-width answer button.
class BigChoice extends StatelessWidget {
  const BigChoice({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.emoji,
    this.color,
    this.selected = false,
    this.sub,
    this.highlight,
    this.highlightColor,
    this.leading,
  });
  final String label;

  /// A drawn picture in place of [icon]/[emoji] (e.g. the sprayer).
  final Widget? leading;

  /// Part of [label] drawn in [highlightColor] (e.g. "IN" in green).
  final String? highlight;
  final Color? highlightColor;
  final String? sub;
  final IconData? icon;
  final String? emoji;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? NaniniColors.rust;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: selected ? c.withValues(alpha: 0.15) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? c : NaniniColors.line, width: selected ? 3 : 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  ?leading,
                  if (emoji != null) Text(emoji!, style: const TextStyle(fontSize: 38)),
                  if (icon != null) Icon(icon, size: 40, color: c),
                  if (leading != null || emoji != null || icon != null) const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: NaniniColors.ink),
                            children: [
                              if (highlight != null && label.contains(highlight!)) ...[
                                TextSpan(text: label.substring(0, label.indexOf(highlight!))),
                                TextSpan(text: highlight, style: TextStyle(color: highlightColor)),
                                TextSpan(text: label.substring(label.indexOf(highlight!) + highlight!.length)),
                              ] else
                                TextSpan(text: label),
                            ],
                          ),
                        ),
                        if (sub != null) Text(sub!, style: const TextStyle(fontSize: 16, color: NaniniColors.muted)),
                      ],
                    ),
                  ),
                  if (selected) Icon(Icons.check_circle, color: c, size: 34),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Big number keypad. [value] is the typed text (digits and at most one
/// decimal point); shows it large above the keys.
class NumberPad extends StatelessWidget {
  const NumberPad({super.key, required this.value, required this.onChanged, this.unit, this.decimal = true});
  final String value;
  final ValueChanged<String> onChanged;
  final String? unit;
  final bool decimal;

  void _tap(String k) {
    if (k == '⌫') {
      if (value.isNotEmpty) onChanged(value.substring(0, value.length - 1));
      return;
    }
    if (k == '.') {
      if (value.contains('.')) return;
      onChanged(value.isEmpty ? '0.' : '$value.');
      return;
    }
    if (value.length >= 9) return;
    onChanged(value == '0' ? k : value + k);
  }

  @override
  Widget build(BuildContext context) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', decimal ? '.' : '', '0', '⌫'];
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NaniniColors.line, width: 1.5),
          ),
          child: Text(
            value.isEmpty ? '0${unit == null ? '' : ' $unit'}' : '$value${unit == null ? '' : ' $unit'}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: value.isEmpty ? NaniniColors.muted : NaniniColors.ink),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              // 4 rows, each with 8px padding below it.
              final keyH = ((box.maxHeight - 4 * 8) / 4).clamp(36.0, 84.0);
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  children: [
                    for (var row = 0; row < 4; row++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            for (var col = 0; col < 3; col++)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: keys[row * 3 + col].isEmpty
                                      ? SizedBox(height: keyH)
                                      : SizedBox(
                                          height: keyH,
                                          child: OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                              backgroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                            ),
                                            onPressed: () => _tap(keys[row * 3 + col]),
                                            child: Text(
                                              keys[row * 3 + col] == '.' ? ',' : keys[row * 3 + col],
                                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: NaniniColors.ink),
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

double? padValue(String s) => s.isEmpty ? null : double.tryParse(s);

/// Pick a person: a row of first letters to jump by, then big name buttons.
class PersonPicker extends StatefulWidget {
  const PersonPicker({super.key, required this.people, required this.onPick, this.selectedIds = const {}});
  final List<RefPerson> people;
  final ValueChanged<RefPerson> onPick;
  final Set<String> selectedIds;
  @override
  State<PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<PersonPicker> {
  String? letter;

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.people]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final letters = sorted.map((p) => p.name.isEmpty ? '?' : p.name[0].toUpperCase()).toSet().toList()..sort();
    final shown = letter == null ? sorted : sorted.where((p) => p.name.toUpperCase().startsWith(letter!)).toList();
    if (sorted.isEmpty) return const EmptyListNote();
    return Column(
      children: [
        if (sorted.length > 12)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _letterChip('ALL', letter == null, () => setState(() => letter = null)),
                for (final l in letters) _letterChip(l, letter == l, () => setState(() => letter = l)),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            children: [
              for (final p in shown) BigChoice(label: p.name, icon: Icons.person, selected: widget.selectedIds.contains(p.id), onTap: () => widget.onPick(p)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _letterChip(String l, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: SizedBox(
      width: l == 'ALL' ? 72 : 52,
      child: selected
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(l, style: const TextStyle(fontSize: 20)),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(l, style: const TextStyle(fontSize: 20)),
            ),
    ),
  );
}

class EmptyListNote extends StatelessWidget {
  const EmptyListNote({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'The list is empty.\nConnect the phone to Wi-Fi once so it can download the lists.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20, color: NaniniColors.muted),
      ),
    ),
  );
}

/// One line on the "Is this right?" screen.
class CheckLine extends StatelessWidget {
  const CheckLine({super.key, required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;

  /// Icon colour -- e.g. the bag's colour from the counter; text stays black.
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 34, color: color ?? NaniniColors.rust),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: NaniniColors.ink),
          ),
        ),
      ],
    ),
  );
}

/// Shown after saving: a big green tick and what happens next.
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key, required this.task, required this.another});
  final String task;

  /// Builds a fresh copy of the flow for "ANOTHER ...".
  final WidgetBuilder another;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NaniniColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle, size: 140, color: NaniniColors.green),
              const SizedBox(height: 16),
              const Text(
                'SAVED',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: NaniniColors.green),
              ),
              const SizedBox(height: 8),
              const Text(
                'It is kept on this phone and sent to the office when the phone is on Wi-Fi.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, color: NaniniColors.ink),
              ),
              const SizedBox(height: 40),
              SizedBox(
                height: 68,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: another)),
                  icon: const Icon(Icons.add, size: 30),
                  label: Text('ANOTHER $task'.toUpperCase(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 68,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.home, size: 30),
                  label: const Text('HOME', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Today" / "Yesterday" / other day, as big buttons.
class DayChoice extends StatelessWidget {
  const DayChoice({super.key, required this.selected, required this.onPick});
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final today = _day(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final other = selected != null && selected != today && selected != yesterday;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String fmt(DateTime d) => '${d.day} ${months[d.month - 1]}';
    return ListView(
      children: [
        BigChoice(label: 'TODAY', sub: fmt(today), icon: Icons.today, selected: selected == today, onTap: () => onPick(today)),
        BigChoice(label: 'YESTERDAY', sub: fmt(yesterday), icon: Icons.history, selected: selected == yesterday, onTap: () => onPick(yesterday)),
        BigChoice(
          label: 'OTHER DAY',
          sub: other ? fmt(selected!) : null,
          icon: Icons.calendar_month,
          selected: other,
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: yesterday, firstDate: today.subtract(const Duration(days: 60)), lastDate: today);
            if (d != null) onPick(_day(d));
          },
        ),
      ],
    );
  }
}

String dayStr(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String fmtNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');

/// Red "you still need to..." message, floating above the BACK/NEXT buttons
/// so it never covers them.
void showNeed(BuildContext context, String msg) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(fontSize: 20)),
    backgroundColor: NaniniColors.red,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
    duration: const Duration(seconds: 3),
  ));
