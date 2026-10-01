import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/auth/app_modules.dart';
import 'package:nanini_app/core/auth/app_user.dart';

void main() {
  test('a farm right only for that farm; admins have every right', () {
    final thys = AppUser(id: '1', username: 'thys', displayName: 'Thys Fourie', role: 'staff', modules: const ['tuckshop', 'hours', kRightTuckshopHaaskraal, kRightPayrollHaaskraal]);
    final staff = AppUser(id: '2', username: 'piet', displayName: 'Piet', role: 'staff', modules: const ['tuckshop']);
    final admin = AppUser(id: '3', username: 'dereck', displayName: 'Dereck', role: 'admin');
    expect(thys.can(farmRight('tuckshop', 'Farm Haaskraal - Swartwater')), isTrue);
    expect(thys.can(farmRight('payroll', 'Farm Haaskraal - Swartwater')), isTrue);
    expect(thys.can(farmRight('tuckshop', 'Farm Limpopodraai - Stockpoort')), isFalse);
    expect(thys.can(farmRight('payroll', 'Farm Doornbult')), isFalse);
    expect(staff.can(farmRight('tuckshop', 'Farm Haaskraal - Swartwater')), isFalse);
    expect(admin.can(farmRight('payroll', 'Farm Doornbult')), isTrue);
  });

  test('the extra rights listed: every farm payroll, tuck shop for the shop farms', () {
    final rights = extraRightsFor(['Farm Doornbult', 'Farm Haaskraal - Swartwater', 'Farm Limpopodraai - Stockpoort']).map((r) => r.key).toList();
    expect(rights, ['payroll:doornbult', 'payroll:haaskraal', 'tuckshop:haaskraal', 'payroll:limpopodraai', 'tuckshop:limpopodraai']);
    expect(extraRightsFor(['Farm Doornbult']).single.label, 'Run the Doornbult payroll');
    expect(isExtraRight('payroll:haaskraal'), isTrue);
    expect(isExtraRight('tuckshop'), isFalse);
  });
}
