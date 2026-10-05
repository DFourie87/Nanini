class SalesCategory {
  const SalesCategory(this.key, this.label, this.subcats, {this.classLabel, this.classOptions});
  final String key;
  final String label;
  final List<String> subcats;

  /// A second dimension alongside subcategory (e.g. potato Class, pepper
  /// Weight) -- when set, the entry form shows an extra dropdown and the
  /// summary groups/colors by subcategory + this combined.
  final String? classLabel;
  final List<String>? classOptions;
  bool get hasClass => classOptions != null;
}

const kSalesCategories = <SalesCategory>[
  SalesCategory('potatoes', 'Potatoes', ['Baby', 'Small', 'Small/Medium', 'Medium', 'Large/Medium', 'Large'],
      classLabel: 'Class', classOptions: kPotatoClasses),
  SalesCategory('peppers', 'Peppers', ['Red', 'Yellow', 'Green'], classLabel: 'Weight', classOptions: kPepperWeights),
  SalesCategory('tobacco', 'Tobacco', ['F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'S1', 'S2', 'S3', 'S4']),
  SalesCategory('butternut', 'Butternuts', ['10kg', '7kg']),
];

const kPotatoClasses = ['Class 1', 'Class 2'];
const kPepperWeights = ['5kg', '4kg'];

class SalesLineItem {
  SalesLineItem(
      {this.id, this.reportId, required this.category, this.subcategory, this.klass, this.description, required this.grossAmount, this.qty});
  final String? id;
  final String? reportId;
  final String category;
  final String? subcategory;
  final String? klass;
  final String? description;
  final double grossAmount;

  /// Boxes (peppers) or bags (potatoes, butternut) delivered -- not
  /// captured for tobacco, which isn't sold by a per-unit count.
  final double? qty;

  /// Boxes / bags / kg: [qty], or -- market reports imported before qty was
  /// saved -- read from the description ("5kg: 120 boxes @ R85.00/boxes").
  double? get units {
    if (qty != null) return qty;
    final m = RegExp(r'([0-9][0-9,]*(?:\.[0-9]+)?) (?:boxes|bags|kg|units) @').firstMatch(description ?? '');
    return m == null ? null : double.tryParse(m.group(1)!.replaceAll(',', ''));
  }

  /// Class / box size: [klass], or for imported peppers the size at the
  /// start of the description ("5kg: ...", or "L: " / "M: " = 5kg / 4kg).
  String? get effectiveClass {
    if (klass != null || category != 'peppers') return klass;
    final m = RegExp(r'^(5kg|4kg|L|M): ').firstMatch(description ?? '');
    return switch (m?.group(1)) { 'L' => '5kg', 'M' => '4kg', final s => s };
  }

  factory SalesLineItem.fromJson(Map<String, dynamic> j) => SalesLineItem(
        id: j['id'] as String,
        reportId: j['report_id'] as String?,
        category: j['category'] as String,
        subcategory: j['subcategory'] as String?,
        klass: j['class'] as String?,
        description: j['description'] as String?,
        grossAmount: (j['gross_amount'] as num).toDouble(),
        qty: (j['qty'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toInsert(String reportId) => {
        'report_id': reportId,
        'category': category,
        'subcategory': subcategory,
        'class': klass,
        'description': description,
        'gross_amount': grossAmount,
        'qty': qty,
      };
}

class SalesReport {
  SalesReport({
    this.id,
    required this.category,
    this.agent,
    required this.reportNumber,
    required this.reportDate,
    required this.grossTotal,
    required this.commissionBeforeVat,
    required this.vat,
    this.vatOnSales,
    required this.nettAmount,
    this.lineItems = const [],
  });
  final String? id;
  final String category;
  final String? agent;
  final String reportNumber;
  final String reportDate;
  final double grossTotal;
  final double commissionBeforeVat;
  final double vat;
  final double? vatOnSales;
  final double nettAmount;
  final List<SalesLineItem> lineItems;

  /// Nett sales for the summary: peppers, potatoes and butternuts without
  /// the VAT on commission (it's claimed back), so gross less commission;
  /// tobacco as on the report (VAT included).
  double get nettSales => category == 'tobacco' ? nettAmount : nettAmount + vat;

  factory SalesReport.fromJson(Map<String, dynamic> j) => SalesReport(
        id: j['id'] as String,
        category: j['category'] as String,
        agent: j['agent'] as String?,
        reportNumber: j['report_number'] as String,
        reportDate: j['report_date'] as String,
        grossTotal: (j['gross_total'] as num?)?.toDouble() ?? 0,
        commissionBeforeVat: (j['commission_before_vat'] as num?)?.toDouble() ?? 0,
        vat: (j['vat'] as num?)?.toDouble() ?? 0,
        vatOnSales: (j['vat_on_sales'] as num?)?.toDouble(),
        nettAmount: (j['nett_amount'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toInsert() => {
        'category': category,
        'agent': agent,
        'report_number': reportNumber,
        'report_date': reportDate,
        'gross_total': grossTotal,
        'commission_before_vat': commissionBeforeVat,
        'vat': vat,
        'vat_on_sales': vatOnSales,
        'nett_amount': nettAmount,
      };
}
