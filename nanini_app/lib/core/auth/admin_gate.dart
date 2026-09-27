import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'session.dart';

/// Gate for admin-only actions (add/edit/delete master data, reports,
/// settings). Role-based: a staff account is simply denied. The database
/// checks the logged-in user's role again for anything that matters, so
/// there's no need to re-type the PIN here.
Future<bool> requireAdmin(BuildContext context) async {
  final session = context.read<Session>();
  if (session.isAdmin) return true;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Admin access required — ask an admin to do this or to make your account an admin.')),
  );
  return false;
}
