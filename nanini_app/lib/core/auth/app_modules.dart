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
];

/// Admin rights a staff account can be given for one farm only (kept in
/// app_users.modules next to the tiles). An admin has them all anyway.
const kExtraRights = <AppModule>[
  AppModule(kRightTuckshopHaaskraal, 'Manage the Haaskraal tuck shop (stock, items, reports)'),
  AppModule(kRightPayrollHaaskraal, 'Run the Haaskraal payroll'),
];
const kRightTuckshopHaaskraal = 'tuckshop:haaskraal';
const kRightPayrollHaaskraal = 'payroll:haaskraal';

/// The right [area] ("tuckshop", "payroll") for the farm called [farmName],
/// e.g. "tuckshop:haaskraal" for "Farm Haaskraal - Swartwater".
String farmRight(String area, String? farmName) {
  final n = (farmName ?? '').toLowerCase();
  for (final r in kExtraRights) {
    final parts = r.key.split(':');
    if (parts.first == area && n.contains(parts.last)) return r.key;
  }
  return '$area:none';
}
