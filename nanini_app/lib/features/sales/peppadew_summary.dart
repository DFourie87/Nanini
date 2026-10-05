import 'sales_models.dart';

/// Peppadew's grading reports over a period, per colour (Red, Yellow): kg
/// delivered and accepted (Class 1 and 2), kg and value of Class 1 and 2, and the rejected fruit
/// per reason as the grader reported it.
class PeppadewSummary {
  PeppadewSummary(Iterable<SalesLineItem> lines) {
    for (final li in lines) {
      final colour = li.subcategory ?? 'Other';
      if (!colours.contains(colour)) colours.add(colour);
      final kg = li.units ?? 0;
      delivered[colour] = (delivered[colour] ?? 0) + kg;
      final klass = li.effectiveClass ?? 'Class unknown';
      if (klass == 'Rejected') {
        final reason = rejectReason(li);
        final byColour = rejected.putIfAbsent(reason, () => {});
        byColour[colour] = (byColour[colour] ?? 0) + kg;
      } else if (klass == 'Class 1' || klass == 'Class 2') {
        // Class 3 and 4 (not paid for) left out: only in the kg delivered.
        accepted[colour] = (accepted[colour] ?? 0) + kg;
        final c = classes.putIfAbsent(colour, () => {});
        final (k, v) = c[klass] ?? (0.0, 0.0);
        c[klass] = (k + kg, v + li.grossAmount);
      }
    }
    colours.sort((a, b) => _rank(a).compareTo(_rank(b)));
  }

  /// Red, then Yellow, then anything else.
  final List<String> colours = [];
  final Map<String, double> delivered = {};
  final Map<String, double> accepted = {};

  /// Colour -> class -> (kg, rand).
  final Map<String, Map<String, (double, double)>> classes = {};

  /// Reason -> colour -> kg.
  final Map<String, Map<String, double>> rejected = {};

  /// Loads imported before the reasons were read: their rejects as one total.
  static const notItemised = 'Not itemised';

  /// "Sun burn: 126.53 kg @ R0.00/kg" -> "Sun burn".
  static String rejectReason(SalesLineItem li) {
    final m = RegExp(r'^([^:\d][^:]*): ').firstMatch(li.description ?? '');
    return m?.group(1) ?? notItemised;
  }

  double get totalDelivered => delivered.values.fold(0, (a, b) => a + b);
  double get totalAccepted => accepted.values.fold(0, (a, b) => a + b);
  double rejectedOf(String colour) => rejected.values.fold(0, (a, m) => a + (m[colour] ?? 0));

  /// Reasons by total kg, most first.
  List<String> get reasons {
    double total(String r) => rejected[r]!.values.fold(0, (a, b) => a + b);
    return rejected.keys.toList()..sort((a, b) => total(b).compareTo(total(a)));
  }

  static int _rank(String colour) => switch (colour) { 'Red' => 0, 'Yellow' => 1, _ => 2 };
}
