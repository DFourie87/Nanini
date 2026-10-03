import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/auth/app_user.dart';
import 'package:nanini_app/core/auth/session.dart';
import 'package:nanini_app/features/hub/financials_screen.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> pump(WidgetTester tester, AppUser user) async {
    final session = Session()..currentUser = user;
    await tester.pumpWidget(ChangeNotifierProvider.value(value: session, child: const MaterialApp(home: FinancialsScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets('Financials: Sales and Suppliers, as the user may open them', (tester) async {
    await pump(tester, AppUser(id: 'a', username: 'admin', displayName: 'Admin', role: 'admin'));
    expect(find.textContaining('Financials', findRichText: true), findsOneWidget);
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Suppliers'), findsOneWidget);

    await pump(tester, AppUser(id: 'b', username: 'clerk', displayName: 'Clerk', role: 'user', modules: const ['suppliers']));
    expect(find.text('Sales'), findsNothing);
    expect(find.text('Suppliers'), findsOneWidget);

    await pump(tester, AppUser(id: 'c', username: 'other', displayName: 'Other', role: 'user', modules: const ['diesel']));
    expect(find.text('No financial apps enabled for your account.'), findsOneWidget);
  });
}
