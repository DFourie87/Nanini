import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/session.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});
  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final repo = AuthRepository();
  final oldPinCtrl = TextEditingController();
  final newPinCtrl = TextEditingController();
  final confirmPinCtrl = TextEditingController();
  bool loading = false;

  Future<void> _submit() async {
    if (newPinCtrl.text != confirmPinCtrl.text) {
      showToast(context, 'New PINs do not match', isError: true);
      return;
    }
    if (newPinCtrl.text.trim().isEmpty) {
      showToast(context, 'Enter a new PIN', isError: true);
      return;
    }
    setState(() => loading = true);
    final session = context.read<Session>();
    final ok = await repo.changeOwnPin(username: session.currentUser!.username, oldPin: oldPinCtrl.text, newPin: newPinCtrl.text);
    if (!mounted) return;
    setState(() => loading = false);
    if (ok) {
      showToast(context, 'PIN changed');
      Navigator.pop(context);
    } else {
      showToast(context, 'Current PIN was incorrect', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const NaniniAppBar(title: 'Change PIN', showManagerButton: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: oldPinCtrl, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Current PIN')),
          const SizedBox(height: 12),
          TextField(controller: newPinCtrl, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'New PIN')),
          const SizedBox(height: 12),
          TextField(controller: confirmPinCtrl, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Confirm new PIN')),
          const SizedBox(height: 20),
          FilledButton(onPressed: loading ? null : _submit, child: const Text('Change PIN')),
        ],
      ),
    );
  }
}
