import 'package:flutter/material.dart';
import 'capture_app/capture_app.dart';
import 'core/supabase_client.dart';
import 'core/widgets/dialog_error.dart';

/// Entry point of the separate "Nanini Capture" app (Android flavor
/// `capture`): `flutter build apk --flavor capture -t lib/main_capture.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Offline is normal here -- a failed sync is retried quietly and shown on
  // the home screen, so only errors from a button press pop up.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (details.library == 'gesture') reportUncaughtError(details.exception);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };

  // Works without a connection: this only sets up the client, it doesn't
  // need to reach the server.
  await initSupabase();
  runApp(const CaptureApp());
}
