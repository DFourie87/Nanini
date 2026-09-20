class Farm {
  Farm({required this.id, required this.name});
  final String id;
  final String name;

  factory Farm.fromJson(Map<String, dynamic> j) => Farm(id: j['id'] as String, name: j['name'] as String);
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

  String get displayName {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? 'Unnamed employee' : n;
  }

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: j['id'] as String,
        firstName: (j['first_name'] as String?) ?? '',
        lastName: (j['last_name'] as String?) ?? '',
        idOrPassport: j['id_or_passport'] as String?,
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
        'first_name': firstName,
        'last_name': lastName,
        'id_or_passport': idOrPassport,
        'current_group_id': currentGroupId,
        'farm_id': farmId,
        'rate_per_hour': ratePerHour,
        'rent_deduction': rentDeduction,
        'loan_deduction': loanDeduction,
        'payment_method': paymentMethodToString(paymentMethod),
        'bank_name': paymentMethod == PaymentMethod.bank ? bankName : null,
        'bank_account_no': paymentMethod == PaymentMethod.bank ? bankAccountNo : null,
        'phone_number': paymentMethod == PaymentMethod.atm ? phoneNumber : null,
        'atm_access_code': paymentMethod == PaymentMethod.atm ? atmAccessCode : null,
      };
}
