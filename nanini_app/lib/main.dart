import 'package:flutter/material.dart';
import 'app.dart';
import 'core/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const NaniniApp());
}
