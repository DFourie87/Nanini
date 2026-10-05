import 'sales_models.dart';

/// Peppadew's grading reports over a period, per colour (Red, Yellow): the kg
/// delivered, and the rejected fruit per reason as the grader reported it.
class PeppadewSummary {
  PeppadewSummary(Iterable<SalesLineItem> lines) {
    for (final li in lines) {
      final colour = li.subcategory ?? 'Other';
      if (!colours.contains(colour)) colours.add(colour);
      final kg = li.units ?? 0;
      delivered[colour] = (delivered[colour] ?? 0) + kg;
      if (li.effectiveClass == 'Rejected') {
        final byColour = rejected.putIfAbsent(rejectReason(li), () => {});
        byColour[colour] = (byColour[colour] ?? 0) + kg;
      }
    }
    colours.sort((a, b) => _rank(a).compareTo(_rank(b)));
  }

  /// Red, then Yellow, then anything else.
  final List<String> colours = [];

  /// Colour -> kg delivered (every class and the rejected fruit).
  final Map<String, double> delivered = {};

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
  double rejectedOf(String colour) => rejected.values.fold(0, (a, m) => a + (m[colour] ?? 0));
  double totalOf(String reason) => rejected[reason]!.values.fold(0, (a, b) => a + b);

  /// Reasons by total kg, most first.
  List<String> get reasons => rejected.keys.toList()..sort((a, b) => totalOf(b).compareTo(totalOf(a)));

  static int _rank(String colour) => switch (colour) { 'Red' => 0, 'Yellow' => 1, _ => 2 };
}
