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
  AppModule('employees_list', 'Employee List'),
  AppModule('truck', 'Truck'),
  AppModule('buffalo', 'Buffalo'),
];
