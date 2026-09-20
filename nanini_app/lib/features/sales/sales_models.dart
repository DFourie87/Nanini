class SalesCategory {
  const SalesCategory(this.key, this.label, this.subcats, this.hasClass);
  final String key;
  final String label;
  final List<String> subcats;
  final bool hasClass;
}

const kSalesCategories = <SalesCategory>[
  SalesCategory('potatoes', 'Potatoes', ['Baby', 'Small', 'Small/Medium', 'Medium', 'Large/Medium', 'Large'], true),
  SalesCategory('peppers', 'Peppers', ['Red', 'Yellow', 'Green'], false),
  SalesCategory('tobacco', 'Tobacco', ['F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'S1', 'S2', 'S3', 'S4'], false),
  SalesCategory('butternut', 'Butternuts', ['10kg', '7kg'], false),
];

const kPotatoClasses = ['Class 1', 'Class 2'];

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
