/// The set of hub tiles that can be granted/withheld per staff account --
/// keys must match what's stored in app_users.modules (see
/// docs/sql/app_users_auth.sql) and what HubScreen filters its tiles by.
/// An admin account always sees every tile regardless of this list.
class AppModule {
  const AppModule(this.key, this.label);
  final String key;
  final String label;
}

const kAppModules = <AppModule>[
  AppModule('diesel', 'Diesel'),
  AppModule('tuckshop', 'Tuck Shop'),
  AppModule('hours', 'Employees'),
  AppModule('packaging', 'Packaging'),
  AppModule('sales', 'Sales'),
  AppModule('truck', 'Truck'),
  AppModule('buffalo', 'Buffalo'),
  AppModule('hunting', 'Hunting'),
  AppModule('suppliers', 'Suppliers'),
];

/// Admin rights an admin can give (or take away from) a staff account, one
/// farm at a time, in Manage users -- kept in app_users.modules next to
/// the tiles as "area:farm", e.g. "payroll:haaskraal". An admin has them all.
const kRightTuckshopHaaskraal = 'tuckshop:haaskraal';
const kRightPayrollHaaskraal = 'payroll:haaskraal';

/// "Farm Haaskraal - Swartwater" -> "haaskraal".
String farmKey(String? farmName) {
  var n = (farmName ?? '').trim().replaceFirst(RegExp(r'^Farm\s+', caseSensitive: false), '');
  final dash = n.indexOf(' - ');
  if (dash > 0) n = n.substring(0, dash);
  return n.trim().toLowerCase();
}

String _farmLabel(String farmName) {
  final k = farmKey(farmName);
  return k.isEmpty ? farmName : '${k[0].toUpperCase()}${k.substring(1)}';
}

/// The right [area] ("tuckshop", "payroll") for the farm called [farmName].
String farmRight(String area, String? farmName) => '$area:${farmKey(farmName)}';

/// Whether [key] (from app_users.modules) is an extra right, not a tile.
bool isExtraRight(String key) => key.contains(':');

/// Every extra right there is for these farms: running each farm's payroll,
/// and managing the tuck shop of the farms that have one.
List<AppModule> extraRightsFor(List<String> farmNames) => [
      for (final f in farmNames) ...[
        AppModule(farmRight('payroll', f), 'Run the ${_farmLabel(f)} payroll'),
        if (farmKey(f) == 'limpopodraai' || farmKey(f) == 'haaskraal')
          AppModule(farmRight('tuckshop', f), 'Manage the ${_farmLabel(f)} tuck shop (stock, items, reports)'),
      ],
    ];

/// A right's label when its farm isn't in the list (e.g. renamed).
String extraRightLabel(String key) {
  final parts = key.split(':');
  final farm = parts.length > 1 ? parts[1] : '';
  final f = farm.isEmpty ? farm : '${farm[0].toUpperCase()}${farm.substring(1)}';
  return switch (parts.first) {
    'payroll' => 'Run the $f payroll',
    'tuckshop' => 'Manage the $f tuck shop',
    _ => key,
  };
}
