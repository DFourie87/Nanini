class PalletSize {
  const PalletSize(this.key, this.label, this.color, this.grade, this.bagsPerPallet);
  final String key;
  final String label;
  final int color;
  final String grade;
  final int bagsPerPallet;
}

const kPalletSizes = <PalletSize>[
  PalletSize('baby10', 'Baby 1st Grade 10kg', 0xFFE07B00, 'g1', 110),
  PalletSize('small10', 'Small 1st Grade 10kg', 0xFFE07B00, 'g1', 110),
  PalletSize('smallmed7', 'Small/Medium 1st Grade 7kg', 0xFF7B2FBE, 'g1', 143),
  PalletSize('med7', 'Medium 1st Grade 7kg', 0xFF2E7D32, 'g1', 143),
  PalletSize('largemed10', 'Large/Medium 1st Grade 10kg', 0xFF1565C0, 'g1', 110),
  PalletSize('large10', 'Large 1st Grade 10kg', 0xFFC81E1E, 'g1', 110),
  PalletSize('med10g2', 'Medium 2nd Grade 10kg', 0xFF006400, 'g2', 110),
  PalletSize('largemed10g2', 'Large/Medium 2nd Grade 10kg', 0xFF00008B, 'g2', 110),
  PalletSize('large10g2', 'Large 2nd Grade 10kg', 0xFF800000, 'g2', 110),
];

const kFieldNames = ['Field 1', 'Field 2', 'Field 3', 'Field 4', 'Field 5', 'Field 6', 'Field 7', 'Field 8'];
const kDefaultTarget = 30;

const kDefaultMarketAgents = [
  ('Grow Botha Roodt', 'David Nel', 'Johannesburg Fresh Produce Market'),
  ('Dapper Market Agents', 'Monty', 'Johannesburg Fresh Produce Market'),
];

class MarketAgent {
  MarketAgent({required this.id, required this.name, this.attention, this.market});
  final String id;
  final String name;
  final String? attention;
  final String? market;

  factory MarketAgent.fromJson(Map<String, dynamic> j) =>
      MarketAgent(id: j['id'] as String, name: j['name'] as String, attention: j['attention'] as String?, market: j['market'] as String?);
}

enum ProduceType { potato, pepper, butternut }

/// The truck currently being loaded — kept locally only (not synced) until
/// "Finish Truck" saves it as a DeliveryNote.
class ActiveTruck {
  ActiveTruck({required this.produceType, DateTime? date, this.field, this.farm})
      : date = date ?? DateTime.now(),
        pallets = {for (final s in kPalletSizes) s.key: 0},
        peppers = {'5kgRed': 0, '5kgYellow': 0, '5kgGreen': 0, '4kgRed': 0, '4kgYellow': 0, '4kgGreen': 0},
        butternuts = {'10kg': 0, '7kg': 0},
        mixedPallets = [];

  ProduceType produceType;
  DateTime date;
  String? field;
  String? farm;
  int target = kDefaultTarget;
  final Map<String, int> pallets;
  final Map<String, int> peppers;
  final Map<String, int> butternuts;
  final List<Map<String, int>> mixedPallets; // each = {sizeKey: bags}

  int get totalPallets => pallets.values.fold(0, (a, b) => a + b) + mixedPallets.length;
  int get totalPepperBoxes => peppers.values.fold(0, (a, b) => a + b);
  int get totalButternutBags => butternuts.values.fold(0, (a, b) => a + b);
}

class DeliveryNote {
  DeliveryNote({
    required this.id,
    this.noteNumber,
    this.reg,
    this.transportCompany,
    this.agentName,
    this.agentAttention,
    this.agentMarket,
    required this.noteDate,
    this.target,
    this.field,
    this.farm,
    required this.pallets,
    required this.mixedPallets,
    required this.produceType,
    this.produceDetail,
    required this.total,
    required this.createdAt,
    this.status = 'approved',
  });
  final String id;
  final int? noteNumber;
  final String? reg;
  final String? transportCompany;
  final String? agentName;
  final String? agentAttention;
  final String? agentMarket;
  final String noteDate;
  final int? target;
  final String? field;
  final String? farm;
  final Map<String, dynamic> pallets;
  final List<dynamic> mixedPallets;
  final String produceType;
  final Map<String, dynamic>? produceDetail;
  final int total;
  final DateTime createdAt;

  /// 'pending' -- logged on the truck but still needs field/transport/reg/
  /// agent added and approval before it can be printed -- or 'approved'.
  final String status;
  bool get isApproved => status == 'approved';

  factory DeliveryNote.fromJson(Map<String, dynamic> j) => DeliveryNote(
        id: j['id'] as String,
        noteNumber: j['note_number'] as int?,
        reg: j['reg'] as String?,
        transportCompany: j['transport_company'] as String?,
        agentName: j['agent_name'] as String?,
        agentAttention: j['agent_attention'] as String?,
        agentMarket: j['agent_market'] as String?,
        noteDate: j['note_date'] as String,
        target: j['target'] as int?,
        field: j['field'] as String?,
        farm: j['farm'] as String?,
        pallets: (j['pallets'] as Map?)?.cast<String, dynamic>() ?? {},
        mixedPallets: (j['mixed_pallets'] as List?) ?? [],
        produceType: j['produce_type'] as String? ?? 'potato',
        produceDetail: (j['produce_detail'] as Map?)?.cast<String, dynamic>(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(j['created_at'] as String? ?? DateTime.now().toIso8601String()),
        status: j['status'] as String? ?? 'approved',
      );
}

class PalletPurchase {
  PalletPurchase({required this.id, required this.agentName, required this.qty, required this.date});
  final String id;
  final String agentName;
  final int qty;
  final String date;

  factory PalletPurchase.fromJson(Map<String, dynamic> j) =>
      PalletPurchase(id: j['id'] as String, agentName: j['agent_name'] as String, qty: (j['qty'] as num).toInt(), date: j['purchase_date'] as String);
}
