class DieselTank {
  DieselTank({required this.id, required this.name, required this.capacity, required this.initialLevel, required this.createdAt});
  final String id;
  final String name;
  final double capacity;
  final double initialLevel;
  final DateTime createdAt;

  factory DieselTank.fromJson(Map<String, dynamic> j) => DieselTank(
        id: j['id'] as String,
        name: j['name'] as String,
        capacity: (j['capacity'] as num).toDouble(),
        initialLevel: (j['initial_level'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class DieselVehicle {
  DieselVehicle({required this.id, required this.name, this.asset, this.vin, this.unit = 'hours'});
  final String id;
  final String name;
  final String? asset;
  final String? vin;

  /// 'hours' (tractors, equipment) or 'km' (trucks, vehicles) -- which unit
  /// this vehicle's hour meter/odometer reading is logged in.
  final String unit;

  factory DieselVehicle.fromJson(Map<String, dynamic> j) => DieselVehicle(
        id: j['id'] as String,
        name: j['name'] as String,
        asset: j['asset'] as String?,
        vin: j['vin'] as String?,
        unit: j['unit'] as String? ?? 'hours',
      );
}

class DieselActivity {
  DieselActivity({required this.id, required this.name, required this.eligible, this.sortOrder = 0});
  final String id;
  final String name;
  final bool eligible;
  final int sortOrder;

  factory DieselActivity.fromJson(Map<String, dynamic> j) => DieselActivity(
        id: j['id'] as String,
        name: j['name'] as String,
        eligible: j['eligible'] as bool? ?? true,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );
}

const kDefaultDieselActivities = <(String, bool, int)>[
  ('Ploughing, planting, cultivating, harvesting, baling', true, 10),
  ('Spraying and Fertilizing', true, 20),
  ('Livestock care (feeding)', true, 30),
  ('Irrigation pumps and generators', true, 40),
  ('Firebreaks and firefighting', true, 50),
  ('Road and fence maintenance', true, 60),
  ('On-farm transport of products and inputs', true, 70),
  ('Transport of produce to market', false, 80),
  ('Personal use', false, 90),
];

class DieselPurchase {
  DieselPurchase({
    required this.id,
    required this.tankId,
    required this.date,
    required this.litres,
    this.supplier,
    this.invoiceNote, // "invoice" column = delivery note no.
    this.notes,
    this.cost,
    this.invoiceNo,
    this.photo,
    this.invoiceFile,
    required this.createdAt,
  });
  final String id;
  final String tankId;
  final String date;
  final double litres;
  final String? supplier;
  final String? invoiceNote;
  final String? notes;
  final double? cost;
  final String? invoiceNo;
  final String? photo;
  final String? invoiceFile;
  final DateTime createdAt;

  factory DieselPurchase.fromJson(Map<String, dynamic> j) => DieselPurchase(
        id: j['id'] as String,
        tankId: j['tank_id'] as String,
        date: j['purchase_date'] as String,
        litres: (j['litres'] as num).toDouble(),
        supplier: j['supplier'] as String?,
        invoiceNote: j['invoice'] as String?,
        notes: j['notes'] as String?,
        cost: (j['cost'] as num?)?.toDouble(),
        invoiceNo: j['invoice_no'] as String?,
        photo: j['photo'] as String?,
        invoiceFile: j['invoice_file'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class DieselUsage {
  DieselUsage({
    required this.id,
    required this.tankId,
    required this.date,
    required this.litres,
    this.equipment,
    this.asset,
    this.hours,
    this.hourKmUnit = 'hours',
    this.activity,
    this.eligible = false,
    this.notes,
    this.employeeId,
    required this.createdAt,
  });
  final String id;
  final String tankId;
  final String date;
  final double litres;
  final String? equipment;
  final String? asset;
  final String? hours;

  /// 'hours' or 'km' -- the unit `hours` was recorded in, copied from the
  /// selected vehicle at the time so it stays fixed even if that vehicle's
  /// unit changes later.
  final String hourKmUnit;
  final String? activity;
  final bool eligible;
  final String? notes;
  final String? employeeId;
  final DateTime createdAt;

  factory DieselUsage.fromJson(Map<String, dynamic> j) => DieselUsage(
        id: j['id'] as String,
        tankId: j['tank_id'] as String,
        date: j['usage_date'] as String,
        litres: (j['litres'] as num).toDouble(),
        equipment: j['equipment'] as String?,
        asset: j['asset'] as String?,
        hours: j['hours'] as String?,
        hourKmUnit: j['hour_km_unit'] as String? ?? 'hours',
        activity: j['activity'] as String?,
        eligible: j['eligible'] as bool? ?? false,
        notes: j['notes'] as String?,
        employeeId: j['employee_id'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class DieselPriceForecast {
  DieselPriceForecast({
    required this.fuelType,
    required this.bulletinDate,
    required this.nextAdjustmentDate,
    required this.expectedChangeRand,
    required this.updatedAt,
  });
  final String fuelType;
  final String bulletinDate;
  final String nextAdjustmentDate;
  final double expectedChangeRand;
  final DateTime updatedAt;

  factory DieselPriceForecast.fromJson(Map<String, dynamic> j) => DieselPriceForecast(
        fuelType: j['fuel_type'] as String? ?? 'diesel_0_05',
        bulletinDate: j['bulletin_date'] as String,
        nextAdjustmentDate: j['next_adjustment_date'] as String,
        expectedChangeRand: (j['expected_change_rand'] as num).toDouble(),
        updatedAt: DateTime.parse(j['updated_at'] as String),
      );
}

class DieselAdjustment {
  DieselAdjustment({required this.id, required this.tankId, required this.newLevel, this.note, required this.date, required this.createdAt});
  final String id;
  final String tankId;
  final double newLevel;
  final String? note;
  final String date;
  final DateTime createdAt;

  factory DieselAdjustment.fromJson(Map<String, dynamic> j) => DieselAdjustment(
        id: j['id'] as String,
        tankId: j['tank_id'] as String,
        newLevel: (j['new_level'] as num).toDouble(),
        note: j['note'] as String?,
        date: j['adjustment_date'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
