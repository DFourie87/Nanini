import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/nanini_theme.dart';

/// Root navigator, so errors nobody caught can still be shown on top of
/// whatever is open (see [reportUncaughtError]).
final appNavigatorKey = GlobalKey<NavigatorState>();

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

/// Pops a small message on top of everything (including an open dialog and
/// the keyboard) -- for "please fill in X" and failed saves from dialogs.
Future<void> showProblem(BuildContext context, String message, {String title = "Can't save yet"}) => showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );

/// Runs a save; if it fails, shows why and returns false so the caller can
/// leave its dialog open.
Future<bool> trySave(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } catch (e) {
    if (context.mounted) await showProblem(context, friendlyDbError(e), title: 'Could not save');
    return false;
  }
}

bool _isNetworkError(Object e) {
  final type = e.runtimeType.toString();
  return e is TimeoutException || type.contains('SocketException') || type.contains('ClientException') || type.contains('HandshakeException');
}

/// Turns a Supabase/Postgres/network error into something readable.
String friendlyDbError(Object e) {
  if (_isNetworkError(e)) return 'No internet connection -- check the signal and try again.';
  final msg = e is PostgrestException ? e.message : (e is StateError ? e.message : e.toString());
  final lower = msg.toLowerCase();
  if ((lower.contains('column') && (lower.contains('does not exist') || lower.contains('could not find'))) ||
      lower.contains('schema cache')) {
    return 'The database is missing an update (run the latest SQL). Details: $msg';
  }
  if (lower.contains('duplicate key') || lower.contains('already exists')) return 'That already exists. Details: $msg';
  if (lower.contains('row-level security') || lower.contains('permission denied')) {
    return 'The database refused this (permissions). Details: $msg';
  }
  return msg;
}

/// Errors that come from a button press (a failed save, no signal, a bug in
/// a handler) and would otherwise vanish silently, making the button look
/// dead. Background noise (e.g. realtime reconnects) is left alone.
bool _isUserFacing(Object e) =>
    e is PostgrestException ||
    e is AuthException ||
    e is StorageException ||
    e is TypeError ||
    e is StateError ||
    e is FormatException ||
    _isNetworkError(e);

var _problemShowing = false;

/// Safety net for errors no screen caught -- shows them instead of the
/// button appearing to do nothing. Returns true if it was shown.
bool reportUncaughtError(Object error) {
  if (!_isUserFacing(error)) return false;
  final ctx = appNavigatorKey.currentContext;
  if (ctx == null || _problemShowing) return ctx != null;
  _problemShowing = true;
  showProblem(ctx, friendlyDbError(error), title: 'Something went wrong').whenComplete(() => _problemShowing = false);
  return true;
}
