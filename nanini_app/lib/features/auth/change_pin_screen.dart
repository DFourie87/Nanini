import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/session.dart';
import '../../core/widgets/dialog_error.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../core/widgets/toast.dart';
import '../../theme/nanini_theme.dart';
import '../../core/run_once.dart';

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
  String? error;

  Future<void> _submit() async {
    final newPin = newPinCtrl.text.trim();
    if (!isValidPin(newPin)) {
      setState(() => error = 'The new PIN must be at least $kMinPinLength digits');
      return;
    }
    if (newPin != confirmPinCtrl.text.trim()) {
      setState(() => error = 'New PINs do not match');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    final session = context.read<Session>();
    try {
      final ok = await repo.changeOwnPin(username: session.currentUser!.username, oldPin: oldPinCtrl.text.trim(), newPin: newPin);
      if (!mounted) return;
      if (ok) {
        showToast(context, 'PIN changed');
        Navigator.pop(context);
      } else {
        setState(() => error = 'Current PIN was incorrect');
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Could not change PIN: ${friendlyDbError(e)}');
    } finally {
      if (mounted) setState(() => loading = false);
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
          TextField(
            controller: newPinCtrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'New PIN', helperText: 'At least $kMinPinLength digits'),
          ),
          const SizedBox(height: 12),
          TextField(controller: confirmPinCtrl, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Confirm new PIN')),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: NaniniColors.red, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: loading ? null : () => runOnce('change_pin_screen.1', _submit), child: Text(loading ? 'Saving…' : 'Change PIN')),
        ],
      ),
    );
  }
}

/// Shown right after logging in with a PIN shorter than 6 digits (every PIN
/// from before the lockdown): the app can't be used until a new one is set.
class ForcedPinChangeScreen extends StatefulWidget {
  const ForcedPinChangeScreen({super.key});
  @override
  State<ForcedPinChangeScreen> createState() => _ForcedPinChangeScreenState();
}

class _ForcedPinChangeScreenState extends State<ForcedPinChangeScreen> {
  final newPinCtrl = TextEditingController();
  final confirmPinCtrl = TextEditingController();
  bool loading = false;
  String? error;

  Future<void> _submit() async {
    final newPin = newPinCtrl.text.trim();
    if (!isValidPin(newPin)) {
      setState(() => error = 'The PIN must be at least $kMinPinLength digits');
      return;
    }
    if (newPin != confirmPinCtrl.text.trim()) {
      setState(() => error = 'The PINs do not match');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    final session = context.read<Session>();
    try {
      await AuthRepository().setOwnPin(newPin);
      await session.pinChanged();
    } catch (e) {
      if (mounted) setState(() => error = 'Could not save the PIN: ${friendlyDbError(e)}');
    } finally {
      if (mounted) setState(() => loading = false);
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Choose a new PIN', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text(
                    'For better security, PINs are now at least $kMinPinLength digits. Choose your new PIN -- you will use it from now on.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: NaniniColors.muted),
                  ),
                  const SizedBox(height: 20),
                  TextField(controller: newPinCtrl, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'New PIN')),
                  const SizedBox(height: 12),
                  TextField(controller: confirmPinCtrl, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Type it again')),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: NaniniColors.red, fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(onPressed: loading ? null : () => runOnce('change_pin_screen.2', _submit), child: Text(loading ? 'Saving…' : 'Save PIN')),
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => context.read<Session>().logout(), child: const Text('Log out')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
