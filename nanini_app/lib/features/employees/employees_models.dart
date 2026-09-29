class Farm {
  Farm({required this.id, required this.name});
  final String id;
  final String name;

  factory Farm.fromJson(Map<String, dynamic> j) => Farm(id: j['id'] as String, name: farmDisplayName(j['name'] as String));
}

/// Farms are known by their name alone: "Farm Haaskraal - Swartwater" ->
/// "Haaskraal" (no "Farm", no location).
String farmDisplayName(String name) {
  var n = name.trim().replaceFirst(RegExp(r'^farm\s+', caseSensitive: false), '');
  final dash = n.indexOf(RegExp(r'\s[-–]\s'));
  if (dash > 0) n = n.substring(0, dash);
  return n.trim().isEmpty ? name : n.trim();
}

class EmployeeGroup {
  EmployeeGroup({required this.id, required this.name, this.farmId});
  final String id;
  final String name;
  final String? farmId;

  factory EmployeeGroup.fromJson(Map<String, dynamic> j) => EmployeeGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        farmId: j['farm_id'] as String?,
      );

  Map<String, dynamic> toInsert() => {'name': name, 'farm_id': farmId};
}

enum PaymentMethod { bank, atm, cash }

PaymentMethod paymentMethodFromString(String? s) {
  switch (s) {
    case 'bank':
      return PaymentMethod.bank;
    case 'atm':
      return PaymentMethod.atm;
    default:
      return PaymentMethod.cash;
  }
}

String paymentMethodToString(PaymentMethod m) => m.name;

class Employee {
  Employee({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.idOrPassport,
    this.fullNames,
    this.surname,
    this.currentGroupId,
    this.farmId,
    this.ratePerHour,
    this.rentDeduction,
    this.loanDeduction,
    this.paymentMethod = PaymentMethod.cash,
    this.bankName,
    this.bankAccountNo,
    this.phoneNumber,
    this.atmAccessCode,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? idOrPassport;

  /// Names as on the ID/passport -- required once [idOrPassport] is on file
  /// (payslips, SARS). [firstName]/[lastName] stay the name everyone knows
  /// them by.
  final String? fullNames;
  final String? surname;
  final String? currentGroupId;

  /// The farm this employee is assigned to -- where their payslip is
  /// generated from (letterhead, etc). Independent of their group, which
  /// can be null ("no group").
  final String? farmId;
  final double? ratePerHour;
  final double? rentDeduction;
  final double? loanDeduction;
  final PaymentMethod paymentMethod;
  final String? bankName;
  final String? bankAccountNo;
  final String? phoneNumber;
  final String? atmAccessCode;

  /// Name and surname -- several workers share a first name. The surname
  /// (as on the ID) is added when the name doesn't already include it.
  String get displayName {
    final n = nameWithSurname('$firstName $lastName', surname);
    return n.isEmpty ? 'Unnamed employee' : n;
  }

  bool get hasId => (idOrPassport ?? '').trim().isNotEmpty;

  /// The same employee with a different tariff, rent or loan (e.g. a change
  /// typed on a capture phone, not yet approved).
  Employee copyWithPay({double? ratePerHour, double? rentDeduction, double? loanDeduction}) => Employee(
        id: id,
        firstName: firstName,
        lastName: lastName,
        idOrPassport: idOrPassport,
        fullNames: fullNames,
        surname: surname,
        currentGroupId: currentGroupId,
        farmId: farmId,
        ratePerHour: ratePerHour ?? this.ratePerHour,
        rentDeduction: rentDeduction ?? this.rentDeduction,
        loanDeduction: loanDeduction ?? this.loanDeduction,
        paymentMethod: paymentMethod,
        bankName: bankName,
        bankAccountNo: bankAccountNo,
        phoneNumber: phoneNumber,
        atmAccessCode: atmAccessCode,
      );

  /// ID on file but not yet the full names and surname that go with it.
  bool get legalNameMissing => hasId && ((fullNames ?? '').trim().isEmpty || (surname ?? '').trim().isEmpty);

  /// Full names + surname when known (official documents), else [displayName].
  String get legalName {
    final n = '${fullNames ?? ''} ${surname ?? ''}'.trim();
    return (fullNames ?? '').trim().isEmpty || (surname ?? '').trim().isEmpty ? displayName : n;
  }

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: j['id'] as String,
        firstName: (j['first_name'] as String?) ?? '',
        lastName: (j['last_name'] as String?) ?? '',
        idOrPassport: j['id_or_passport'] as String?,
        fullNames: j['full_names'] as String?,
        surname: j['surname'] as String?,
        currentGroupId: j['current_group_id'] as String?,
        farmId: j['farm_id'] as String?,
        ratePerHour: (j['rate_per_hour'] as num?)?.toDouble(),
        rentDeduction: (j['rent_deduction'] as num?)?.toDouble(),
        loanDeduction: (j['loan_deduction'] as num?)?.toDouble(),
        paymentMethod: paymentMethodFromString(j['payment_method'] as String?),
        bankName: j['bank_name'] as String?,
        bankAccountNo: j['bank_account_no'] as String?,
        phoneNumber: j['phone_number'] as String?,
        atmAccessCode: j['atm_access_code'] as String?,
      );

  Map<String, dynamic> toInsert() => {
        ...toUpdate(),
        'rate_per_hour': ratePerHour,
        'rent_deduction': rentDeduction,
        'loan_deduction': loanDeduction,
      };

  /// Everything Employees > List edits. Tariff, rent and loan are set in
  /// Summary / Payslips, so an edit here never overwrites them.
  Map<String, dynamic> toUpdate() => {
        'first_name': firstName,
        'last_name': lastName,
        'id_or_passport': idOrPassport,
        'full_names': fullNames,
        'surname': surname,
        'current_group_id': currentGroupId,
        'farm_id': farmId,
        'payment_method': paymentMethodToString(paymentMethod),
        'bank_name': paymentMethod == PaymentMethod.bank ? bankName : null,
        'bank_account_no': paymentMethod == PaymentMethod.bank ? bankAccountNo : null,
        'phone_number': paymentMethod == PaymentMethod.atm ? phoneNumber : null,
        'atm_access_code': paymentMethod == PaymentMethod.atm ? atmAccessCode : null,
      };
}

/// Why these employee details can't be saved yet, or null if they can. A name
/// is always needed; the ID/passport can come later, but once it's there the
/// full names and surname (as on the ID) must be too.
String? employeeDetailsProblem({required String name, String? idOrPassport, String? fullNames, String? surname}) {
  if (name.trim().isEmpty) return 'Enter the name.';
  final id = (idOrPassport ?? '').replaceAll(' ', '');
  if (id.isEmpty) return null;
  if (RegExp(r'^\d+$').hasMatch(id) && id.length != 13) return 'A South African ID number has 13 digits (this has ${id.length}).';
  if (id.length < 5) return 'That ID/passport number looks too short.';
  if ((fullNames ?? '').trim().isEmpty || (surname ?? '').trim().isEmpty) {
    return 'With an ID/passport number, the full names and surname (as on the ID) are needed too.';
  }
  return null;
}

/// [name] followed by [surname], unless the name already has the surname in
/// it (e.g. "Anna Mokoena" + "Mokoena" stays "Anna Mokoena").
String nameWithSurname(String name, String? surname) {
  final n = name.trim();
  final s = (surname ?? '').trim();
  if (s.isEmpty || n.toLowerCase().split(RegExp(r'\s+')).contains(s.toLowerCase())) return n;
  return n.isEmpty ? s : '$n $s';
}
