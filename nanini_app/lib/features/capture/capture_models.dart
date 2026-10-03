// Shared between the hub and the separate "Nanini Capture" app -- see
// docs/sql/capture_app.sql.

/// Entry types the capture app can send. Each lands in one hub app's
/// "Captured -- to approve" list.
abstract final class CaptureModule {
  static const dieselUsage = 'diesel_usage';
  static const dieselPurchase = 'diesel_purchase';
  static const hours = 'hours';
  static const kg = 'kg';
  static const tuckshop = 'tuckshop';
  static const delivery = 'delivery';

  /// New worker, changed details or worker who left (payload 'action':
  /// add / change / remove) -- approved in the hub's Employees app.
  static const employee = 'employee';

  /// A farm manager's Payslips check: tariff / rent / loan changes and new
  /// extra pay -- approved in the Hours app.
  static const payCheck = 'pay_check';

  /// Who is in which work group (Hours > WORK GROUPS on a phone).
  static const workGroups = 'work_groups';

  /// A supplier's invoice, credit note or statement photographed on a phone
  /// (the photo itself goes separately, see capture_photos) -- an admin
  /// checks it and allocates it to GL accounts in the Suppliers app.
  static const supplierDoc = 'supplier_doc';

  static const dieselModules = [dieselUsage, dieselPurchase];
  static const hoursModules = [hours, kg, payCheck];
  static const tuckshopModules = [tuckshop];
  static const deliveryModules = [delivery];
  static const employeeModules = [employee, workGroups];
  static const supplierModules = [supplierDoc];

  static String label(String module) => switch (module) {
        dieselUsage => 'Diesel used',
        dieselPurchase => 'Diesel delivered',
        hours => 'Hours worked',
        kg => 'Kg picked',
        tuckshop => 'Tuck shop',
        delivery => 'Packaging truck',
        employee => 'Employee details',
        payCheck => 'Payslips check',
        supplierDoc => 'Supplier document',
        _ => module,
      };
}

/// The tasks a phone can be allowed to capture (capture_devices.modules).
/// Employee details and Payslips aren't on by default -- an admin ticks them
/// per phone.
abstract final class CaptureTask {
  static const diesel = 'diesel';
  static const packaging = 'packaging';
  static const hours = 'hours';
  static const tuckshop = 'tuckshop';
  static const employees = 'employees';
  static const payslips = 'payslips';

  /// Photograph suppliers' invoices, credit notes and statements.
  static const suppliers = 'suppliers';
  static const all = [diesel, packaging, hours, tuckshop, employees, payslips, suppliers];

  static String label(String task) => switch (task) {
        diesel => 'Diesel',
        packaging => 'Packaging',
        hours => 'Hours',
        tuckshop => 'Tuck shop',
        employees => 'Employee details',
        payslips => 'Payslips',
        suppliers => 'Suppliers',
        _ => task,
      };
}

class CaptureEntry {
  CaptureEntry({
    required this.id,
    required this.module,
    required this.payload,
    required this.summary,
    required this.capturedAt,
    this.deviceId,
    this.deviceName,
    this.status = 'pending',
    this.rejectReason,
    this.reviewedAt,
  });

  final String id;
  final String module;
  final Map<String, dynamic> payload;
  final String summary;
  final DateTime capturedAt;
  final String? deviceId;
  final String? deviceName;
  final String status;
  final String? rejectReason;
  final DateTime? reviewedAt;

  factory CaptureEntry.fromJson(Map<String, dynamic> j) => CaptureEntry(
        id: j['id'] as String,
        module: j['module'] as String,
        payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? {},
        summary: j['summary'] as String? ?? '',
        capturedAt: DateTime.parse(j['captured_at'] as String).toLocal(),
        deviceId: j['device_id'] as String?,
        deviceName: j['device_name'] as String?,
        status: j['status'] as String? ?? 'pending',
        rejectReason: j['reject_reason'] as String?,
        reviewedAt: j['reviewed_at'] == null ? null : DateTime.parse(j['reviewed_at'] as String).toLocal(),
      );

  /// Local (on-phone) storage form -- also what gets uploaded.
  Map<String, dynamic> toJson() => {
        'id': id,
        'module': module,
        'payload': payload,
        'summary': summary,
        'captured_at': capturedAt.toUtc().toIso8601String(),
        if (deviceId != null) 'device_id': deviceId,
        if (deviceName != null) 'device_name': deviceName,
        'status': status,
        if (rejectReason != null) 'reject_reason': rejectReason,
      };
}

class CaptureDevice {
  CaptureDevice({
    required this.id,
    required this.name,
    required this.modules,
    required this.active,
    this.approved = false,
    this.lastSeenAt,
    this.appVersion,
  });
  final String id;
  final String name;
  final List<String> modules;
  final bool active;

  /// New phones can't send or download anything until an admin approves
  /// them in the hub (Capture phones).
  final bool approved;
  final DateTime? lastSeenAt;
  final String? appVersion;

  factory CaptureDevice.fromJson(Map<String, dynamic> j) => CaptureDevice(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        modules: ((j['modules'] as List?) ?? CaptureTask.all).cast<String>(),
        active: j['active'] as bool? ?? true,
        approved: j['approved'] as bool? ?? false,
        lastSeenAt: j['last_seen_at'] == null ? null : DateTime.parse(j['last_seen_at'] as String).toLocal(),
        appVersion: j['app_version'] as String?,
      );
}
