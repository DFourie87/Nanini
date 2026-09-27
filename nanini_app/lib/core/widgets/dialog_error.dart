import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/nanini_theme.dart';

/// Dialog title with an error line underneath. A snackbar raised from inside
/// a dialog lands behind it (and the keyboard), so dialogs show their
/// validation/save errors here where they can actually be seen.
Widget dialogTitleWithError(String title, String? error) {
  if (error == null) return Text(title);
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title),
      const SizedBox(height: 6),
      Text(error, style: const TextStyle(color: NaniniColors.red, fontSize: 14, fontWeight: FontWeight.w600)),
    ],
  );
}

/// Turns a Supabase/Postgres error into something readable.
String friendlyDbError(Object e) {
  final msg = e is PostgrestException ? e.message : e.toString();
  final lower = msg.toLowerCase();
  if ((lower.contains('column') && (lower.contains('does not exist') || lower.contains('could not find'))) ||
      lower.contains('schema cache')) {
    return 'the database is missing an update (run the latest SQL). Details: $msg';
  }
  if (lower.contains('duplicate key') || lower.contains('already exists')) return 'that already exists. Details: $msg';
  return msg;
}
