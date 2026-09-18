import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/auth/session.dart';
import 'features/auth/login_screen.dart';
import 'features/hub/hub_screen.dart';
import 'theme/nanini_theme.dart';

class NaniniApp extends StatelessWidget {
  const NaniniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => Session()..restore(),
      child: MaterialApp(
        title: 'Nanini Boerdery',
        debugShowCheckedModeBanner: false,
        theme: NaniniTheme.light,
        home: const _RootGate(),
      ),
    );
  }
}

class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (!session.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return session.isLoggedIn ? const HubScreen() : const LoginScreen();
  }
}
