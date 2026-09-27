import 'package:flutter/material.dart';
import 'app.dart';
import 'core/supabase_client.dart';
import 'core/widgets/dialog_error.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Any error a button handler didn't catch (failed save, no signal) is
  // shown on screen instead of the button silently doing nothing.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (details.library == 'gesture') reportUncaughtError(details.exception);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    reportUncaughtError(error);
    return true;
  };

  await initSupabase();
  runApp(const NaniniApp());
}
