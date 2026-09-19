import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/session.dart';
import '../../theme/nanini_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final usernameCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  bool loading = false;
  String? error;

  Future<void> _submit() async {
    final username = usernameCtrl.text.trim();
    final pin = pinCtrl.text.trim();
    if (username.isEmpty || pin.isEmpty) {
      setState(() => error = 'Enter your username and PIN');
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      final ok = await context.read<Session>().login(username, pin);
      if (!mounted) return;
      if (!ok) {
        setState(() { loading = false; error = 'Incorrect username or PIN'; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { loading = false; error = 'Could not reach the server: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 140,
                    width: 140,
                    child: Image.asset('assets/images/hub-logo.jpg', fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 20),
                  const Text('Sign in to continue', style: TextStyle(color: NaniniColors.muted)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: usernameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: 'PIN'),
                    onSubmitted: (_) => loading ? null : _submit(),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: NaniniColors.red)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: loading ? null : _submit,
                      child: loading
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Sign in'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Don't have a login? Ask an admin to create one for you.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: NaniniColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
