import '../features/employees/employees_models.dart';
import 'pay_ref.dart';
/// The pick-lists the capture app works from offline, refreshed from the
/// hub on every Wi-Fi sync.
class RefItem {
  const RefItem(this.id, this.name, {this.farmId, this.unit});
  final String id;
  final String name;
  final String? farmId;

  /// Vehicles only: 'hours' or 'km'.
  final String? unit;

  factory RefItem.fromJson(Map<String, dynamic> j) =>
      RefItem(j['id'] as String, j['name'] as String, farmId: j['farm_id'] as String?, unit: j['unit'] as String?);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'farm_id': farmId, 'unit': unit};
}

class RefPerson {
  const RefPerson({required this.id, required String name, this.farmId, this.groupId, this.fullNames, this.surname, this.hasId = false, this.idOrPassport})
      : knownName = name;
  final String id;

  /// The name everyone knows them by (as typed in Employees > List).
  final String knownName;

  /// Name and surname, shown everywhere -- several workers share a name.
  String get name => nameWithSurname(knownName, surname);
  final String? farmId;
  final String? groupId;

  /// Names as on the ID, and whether the office has an ID/passport number.
  final String? fullNames;
  final String? surname;
  final bool hasId;

  /// The number itself -- only sent to phones with the Employee details task.
  final String? idOrPassport;

  factory RefPerson.fromJson(Map<String, dynamic> j) => RefPerson(
        id: j['id'] as String,
        name: j['name'] as String,
        farmId: j['farm_id'] as String?,
        groupId: j['group_id'] as String?,
        fullNames: j['full_names'] as String?,
        surname: j['surname'] as String?,
        hasId: j['has_id'] == true,
        idOrPassport: j['id_or_passport'] as String?,
      );
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': knownName, 'farm_id': farmId, 'group_id': groupId, 'full_names': fullNames, 'surname': surname, 'has_id': hasId, 'id_or_passport': idOrPassport};
}

class RefShopItem {
  const RefShopItem({required this.id, required this.name, this.farmId, required this.price, required this.stock});
  final String id;
  final String name;
  final String? farmId;
  final double price;
  final double stock;

  factory RefShopItem.fromJson(Map<String, dynamic> j) => RefShopItem(
        id: j['id'] as String,
        name: j['name'] as String,
        farmId: j['farm_id'] as String?,
        price: (j['price'] as num).toDouble(),
        stock: (j['stock'] as num).toDouble(),
      );
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'farm_id': farmId, 'price': price, 'stock': stock};
}

class RefData {
  RefData({
    required this.farms,
    required this.people,
    required this.groups,
    required this.tanks,
    required this.vehicles,
    required this.activities,
    required this.shopItems,
    this.payJson,
  });
  factory RefData.empty() => RefData(farms: [], people: [], groups: [], tanks: [], vehicles: [], activities: [], shopItems: []);

  final List<RefItem> farms;
  final List<RefPerson> people;
  final List<RefItem> groups;
  final List<RefItem> tanks;
  final List<RefItem> vehicles;
  final List<RefItem> activities;
  final List<RefShopItem> shopItems;

  /// Pay data for the Payslips task (only sent to phones that have it).
  final Map<String, dynamic>? payJson;
  late final PayRef? pay = payJson == null ? null : PayRef.fromJson(_withSurnames(payJson!));

  /// The pay lists' employees with their surnames from [people], so the
  /// Payslips task shows name and surname too.
  Map<String, dynamic> _withSurnames(Map<String, dynamic> j) {
    final surnames = {for (final p in people) p.id: p.surname};
    return {
      ...j,
      'employees': [
        for (final e in (j['employees'] as List?) ?? const [])
          if (e is Map) {...e.cast<String, dynamic>(), 'surname': e['surname'] ?? surnames[e['id']]} else e,
      ],
    };
  }

  bool get isEmpty => farms.isEmpty && people.isEmpty && tanks.isEmpty;

  /// Farms with a tuck shop, same rule as the hub's Tuck Shop app.
  List<RefItem> get shopFarms => farms.where((f) => f.name.contains('Limpopodraai') || f.name.contains('Haaskraal')).toList();

  /// Haaskraal's shop is logged as a money total per person, not per item.
  static bool isManualShop(RefItem farm) => farm.name.contains('Haaskraal');

  factory RefData.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
        ((j[key] as List?) ?? const []).map((e) => f((e as Map).cast<String, dynamic>())).toList();
    return RefData(
      farms: list('farms', RefItem.fromJson),
      people: list('people', RefPerson.fromJson),
      groups: list('groups', RefItem.fromJson),
      tanks: list('tanks', RefItem.fromJson),
      vehicles: list('vehicles', RefItem.fromJson),
      activities: list('activities', RefItem.fromJson),
      shopItems: list('shop_items', RefShopItem.fromJson),
      payJson: (j['pay'] as Map?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'farms': farms.map((e) => e.toJson()).toList(),
        'people': people.map((e) => e.toJson()).toList(),
        'groups': groups.map((e) => e.toJson()).toList(),
        'tanks': tanks.map((e) => e.toJson()).toList(),
        'vehicles': vehicles.map((e) => e.toJson()).toList(),
        'activities': activities.map((e) => e.toJson()).toList(),
        'shop_items': shopItems.map((e) => e.toJson()).toList(),
        'pay': ?payJson,
      };
}
