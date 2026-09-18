import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'session.dart';

/// Gate for admin-only actions (add/edit/delete master data, reports,
/// settings) — the direct replacement for the old shared-password
/// `requireManager()`. Now it's role-based: a staff account is simply denied
/// (there's no password that turns a staff login into an admin one), and an
/// admin is prompted to confirm their PIN only once per app run (cached in
/// memory afterwards — see Session).
Future<bool> requireAdmin(BuildContext context) async {
  final session = context.read<Session>();

  if (!session.isAdmin) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Admin access required — ask an admin to do this or to make your account an admin.')),
    );
    return false;
  }

  if (session.adminPin != null) return true;

  final controller = TextEditingController();
  final pin = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirm your PIN'),
      content: TextField(
        controller: controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'PIN'),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Confirm')),
      ],
    ),
  );
  if (pin == null || pin.isEmpty) return false;

  final ok = await session.confirmAdminPin(pin);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
  }
  return ok;
}
